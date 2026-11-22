// Portalcraft's early composite (compiled by the add-on with D3DCompile, ps_3_0/vs_3_0; edits hot-reload).
//
// Drawn by portalcraft.addon32 right before Portal 2 draws its main view: Minecraft's opaque pixels go into Portal 2's
// own colour and depth buffers, so everything Portal 2 draws afterwards (its world, beams, glass, particles, the view
// model, post-processing, the HUD and menus) is depth-tested against Minecraft and lands on top where it should.
// Translucent Minecraft pixels (water, stained glass) and Minecraft's hand/HUD are left to Portalcraft.fx at the end.
//
// Every pixel's view ray (Portal 2's camera, in camera-relative Source units, t = depth along the view axis):
//     ray(t) = t * (Dir0 + ndc.x * DirX + ndc.y * DirY)
// The same point in Minecraft's camera space (x right, y up, looking down -z) is linear in t:
//     mc(t) = McA + t * (McB0 + ndc.x * McBX + ndc.y * McBY)
// and its Portal 2 depth is (Kz + t * dz) / (Kw + t * dw), dz = Dz0 + ndc.x * DzX + ndc.y * DzY (same for dw).

sampler2D sWorld : register(s0); // Minecraft's level pass, RGBA bytes in a BGRA texture, rows bottom-up, premultiplied
sampler2D sDepth : register(s1); // Minecraft's depth (reversed Z), R32F
sampler2D sLight : register(s2); // Portal 2's previous frame, small: the light around each pixel
sampler2D sODepth : register(s3); // Minecraft's depth of only its solid things (before water, glass), R32F

float4 McA : register(c0);      // xyz, w: 1 when Minecraft depth is reversed
float4 McB0 : register(c1);
float4 McBX : register(c2);
float4 McBY : register(c3);
float4 McProj : register(c4);   // x: tan(vfov/2) * aspect, y: tan(vfov/2), z: near (units), w: far (units)
float4 DepthK : register(c5);   // x: Kz, y: Kw, z: depth bias (units), w: farthest march (units)
float4 Dz : register(c6);       // x: Dz0, y: DzX, z: DzY
float4 Dw : register(c7);       // x: Dw0, y: DwX, z: DwY
float4 Screen : register(c8);   // x, y: viewport size, z, w: viewport offset
float4 Light : register(c9);    // x: light match, y: neutral brightness (< 0: tint only), z: tint, w: 1 to show the march (debug)
float4 Fog : register(c10);     // this picture's fluid fog: x start, y end (units from its camera; through a portal, from
                                // the exit portal on: the fluid there), z 1 when on
float4 FogColor : register(c11);
float4 Clip : register(c12);     // through a portal: the exit portal's plane, t * (x + ndc.x y + ndc.y z) + w (> 0: in front)
float4 ClipOn : register(c13);   // x: 1 through a portal; y: 1 when Minecraft fogged this picture itself (its own world)
float4 Opaque : register(c14);   // x: 1 when sODepth is Minecraft's solid-only depth
float4 Sky : register(c15);      // x: 1 in Minecraft's own world (sp_mc_overworld): Minecraft's sky where it has no surface
float4 ObliqueQ : register(c16); // a frame through a portal: its near plane is the exit portal's (q, w in units)
float4 Oblique : register(c17);  // x: 1 when the depth is that oblique kind
float4 PortalF[2] : register(c18); // the open portals: along each one's facing, right and up (units from its centre) a
float4 PortalR[2] : register(c20); // point on the ray is t * (x + ndc.x y + ndc.y z) + w
float4 PortalU[2] : register(c22);
float4 Portals : register(c24);    // x: how many are open
float4 McTexel : register(c25);    // Minecraft's picture: x, y one pixel (0..1), z, w its size (0: an older add-on)
float4 NearFog : register(c26);    // through a portal: the fluid the player's eye is in, up to the portal (as Fog)
float4 NearFogColor : register(c27);

struct Out
{
	float4 color : COLOR0;
	float depth : DEPTH;
};

float mc_linear(float d)
{
	const float n = McProj.z, f = McProj.w;
	if (d <= 0.0)
		return 1e9; // nothing drawn (reversed Z clears to 0)
	return n * f / (n + d * (f - n));
}

float mc_depth(float2 muv)
{
	const float d = tex2Dlod(sDepth, float4(muv, 0, 0)).r;
	if (Oblique.x < 0.5)
		return mc_linear(d);
	// (depth = 1 - q.v / dist: dist = q.w / ((1 - depth) - (q.x x tx + q.y y ty - q.z)) at Minecraft's ndc x, y)
	if (d <= 0.0)
		return 1e9;
	const float2 n = muv * 2.0 - 1.0;
	const float den = (1.0 - d) - (ObliqueQ.x * n.x * McProj.x + ObliqueQ.y * n.y * McProj.y - ObliqueQ.z);
	return den < -1e-7 ? ObliqueQ.w / den : 1e9;
}

float luma(float3 c)
{
	return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float fog_amount(float4 f, float d)
{
	return f.z > 0.5 ? saturate((d - f.x) / max(f.y - f.x, 1.0)) : 0.0;
}

// a colour d units off along this ray (through a portal it came out of the exit portal dExit units along it): this
// picture's own fluid from there on (own: unless Minecraft fogged it already), then the player's own up to the portal
float3 fogged(float3 col, float d, float dExit, bool own)
{
	if (own)
		col = lerp(col, FogColor.rgb, fog_amount(Fog, d - dExit));
	return lerp(col, NearFogColor.rgb, fog_amount(NearFog, dExit));
}

Out main(float2 vpos : VPOS)
{
	Out o;
	const float2 px = vpos + 0.5 - Screen.zw;
	const float2 ndc = float2(px.x / Screen.x * 2.0 - 1.0, 1.0 - px.y / Screen.y * 2.0);
	const float3 b = McB0.xyz + ndc.x * McBX.xyz + ndc.y * McBY.xyz;
	const float2 mcScale = McProj.xy;
	// distances along this ray (fog, like Minecraft's, by distance from the eye): units per t, and through a portal how
	// far it goes before it comes out of the exit portal (the camera is behind it - as far as the player is from the portal)
	const float rayLen = length(b);
	float dExit = 0.0;
	if (ClipOn.x > 0.5)
	{
		const float k = Clip.x + ndc.x * Clip.y + ndc.y * Clip.z;
		dExit = k > 1e-6 ? max(-Clip.w / k, 0.0) * rayLen : 0.0;
	}

	// march from near to far in log steps: the first point behind Minecraft's surface is where Minecraft is seen
	const float zNear = 4.0, zFar = DepthK.w;
	float tHit = -1.0;
	float2 uvHit = 0.0;
	float tPrev = zNear;
	// Minecraft's camera was a little elsewhere: past an edge, this ray can go behind a surface without meeting it
	// (Minecraft saw that surface in front of what this ray sees). It looks on past it (behind a leaf, a fence, a tree
	// there can be ground Minecraft does see); nFill is where it first went behind one - the picture just this side of
	// that surface's edge, what is behind the surface, for when nothing further on is met.
	bool behind = false, gap = false;
	float2 nFill = 0.0;
	[loop] for (int i = 0; i < 32; ++i)
	{
		const float t = zNear * pow(zFar / zNear, i / 31.0);
		const float3 c = McA.xyz + t * b;
		if (c.z > -1.0)
		{
			tPrev = t;
			continue;
		}
		const float2 n = c.xy / -c.z / mcScale;
		if (abs(n.x) > 1.0 || abs(n.y) > 1.0)
		{
			tPrev = t;
			continue;
		}
		if (mc_depth(n * 0.5 + 0.5) > -c.z + 1.0)
		{
			tPrev = t;
			behind = false;
			continue; // still in front of what Minecraft drew there
		}
		if (behind)
		{
			tPrev = t;
			continue; // still behind the surface it went behind
		}
		// crossed Minecraft's surface between the last step and this one: bisect for where (a long step skipped past
		// a block's edge onto what is behind it - stacked "ghost" edges), then settle on the surface
		float lo = tPrev, hi = t;
		[loop] for (int j = 0; j < 6; ++j)
		{
			const float tm = 0.5 * (lo + hi);
			const float3 cm = McA.xyz + tm * b;
			const float2 nm = cm.xy / -min(cm.z, -1.0) / mcScale;
			if (cm.z <= -1.0 && abs(nm.x) <= 1.0 && abs(nm.y) <= 1.0 && mc_depth(nm * 0.5 + 0.5) <= -cm.z + 1.0)
				hi = tm;
			else
				lo = tm;
		}
		float tg = hi;
		float2 nh = n;
		[loop] for (int k = 0; k < 3; ++k)
		{
			const float3 ck = McA.xyz + tg * b;
			if (ck.z > -1.0)
				break;
			const float2 nk = ck.xy / -ck.z / mcScale;
			if (abs(nk.x) > 1.0 || abs(nk.y) > 1.0)
				break;
			const float zk = mc_depth(nk * 0.5 + 0.5);
			if (zk > 1e8)
				break;
			nh = nk;
			// the surface point's distance along Minecraft's axis is zk: where on this ray is that? (c.z = -zk)
			tg = (-zk - McA.z) / min(b.z, -1e-4);
		}
		// at a silhouette the settled point can sit on the other surface (the picture is from a camera a little
		// behind this one): a point whose depth there disagrees with the ray is not Minecraft's - no streak
		const float3 cf = McA.xyz + tg * b;
		const float2 nf = cf.xy / -cf.z / mcScale;
		const float zf = mc_depth(nf * 0.5 + 0.5);
		if (abs(nf.x) <= 1.0 && abs(nf.y) <= 1.0 && abs(zf - -cf.z) <= 2.0 + 0.02 * -cf.z)
		{
			tHit = tg;
			uvHit = nf * 0.5 + 0.5;
			break;
		}
		// (on past it in every map: behind a Minecraft block's edge can be another Minecraft block)
		if (!gap)
		{
			const float3 cl = McA.xyz + lo * b;
			nFill = cl.xy / -min(cl.z, -1.0) / mcScale;
			gap = true;
		}
		behind = true;
		tPrev = t;
	}
	// a gap: what this ray meets, Minecraft's camera didn't see (it is behind something from there). It is filled with the
	// farthest of the pixels around the edge it went behind - what is behind that thing - not with a copy of the thing
	// itself (the sky's sample below, along the ray's direction, lands on it: a hill's top, shifted up - a ghost of it).
	// Where that is nothing, Minecraft's own world has its sky there and Portal 2's maps their own world. (Walking under
	// a tree, nearly every ray between the leaves goes behind one in Minecraft's picture, a frame behind: without the
	// fill, Portal 2's ceiling showed through the whole canopy.)
	bool skyFill = false;
	if (tHit < 0.0 && gap)
	{
		const float2 tx = McTexel.x > 0.0 ? McTexel.xy : float2(1.0 / 1920.0, 1.0 / 1080.0);
		const float2 at = (floor(saturate(clamp(nFill, -1.0, 1.0) * 0.5 + 0.5) / tx) + 0.5) * tx;
		float2 uvBest = at;
		float zBest = mc_depth(at);
		[unroll] for (int k = 0; k < 8; ++k)
		{
			// (the ring two pixels out: past an edge pixel that blends both sides)
			const float a = k * 0.78539816;
			const float2 uv = saturate(at + round(float2(cos(a), sin(a)) * 2.0) * tx);
			const float z = mc_depth(uv);
			if (z > zBest)
			{
				zBest = z;
				uvBest = uv;
			}
		}
		uvHit = uvBest;
		if (zBest > 1e8)
			skyFill = Sky.x > 0.5; // (nothing there: Minecraft's sky, or Portal 2's world)
		else
			tHit = max((-zBest - McA.z) / min(b.z, -1e-4), zNear);
	}
	if (skyFill)
	{
		const float4 sky = tex2Dlod(sWorld, float4(uvHit, 0, 0)).bgra;
		o.color = float4(fogged(sky.rgb, 1e9, dExit, true), 1.0);
		o.depth = 1.0;
		return o;
	}
	if (tHit < 0.0 && !gap && Sky.x < 0.5 && dot(McA.xyz, McA.xyz) < 0.0625)
	{
		// Portal 2 (Direct3D 9) takes each pixel at its corner, Minecraft (OpenGL) at its centre - half a pixel apart.
		// Where a hole is dug into Portal 2's wall, its surface is cut away by the corner, so along the hole's bottom edge
		// is a row whose centre just misses the hole's floor in Minecraft's picture: nothing went in, and Portal 2's
		// world far behind the wall showed there (a white seam, img14). With the cameras together (not moving: the
		// picture is exact), the nearest of the four Minecraft pixels around the corner goes in.
		const float2 pc = vpos - Screen.zw;
		const float2 nc = float2(pc.x / Screen.x * 2.0 - 1.0, 1.0 - pc.y / Screen.y * 2.0);
		const float3 bc = McB0.xyz + nc.x * McBX.xyz + nc.y * McBY.xyz;
		if (bc.z < -1e-4)
		{
			const float2 tx = McTexel.x > 0.0 ? McTexel.xy : float2(1.0 / 1920.0, 1.0 / 1080.0);
			const float2 at = clamp(bc.xy / -bc.z / mcScale, -1.0, 1.0) * 0.5 + 0.5;
			float zBest = 1e9;
			float2 uvBest = at;
			[unroll] for (int k = 0; k < 4; ++k)
			{
				const float2 uv = saturate(at + (float2(k % 2, k / 2) - 0.5) * tx);
				const float z = mc_depth(uv);
				if (z < zBest)
				{
					zBest = z;
					uvBest = uv;
				}
			}
			if (zBest < 1e8)
			{
				uvHit = uvBest;
				tHit = max((-zBest - McA.z) / min(b.z, -1e-4), zNear);
			}
		}
	}
	if (tHit < 0.0)
	{
		// no Minecraft surface on this ray. In Minecraft's own world that is its sky: it only depends on the ray's
		// direction (b, the ray at infinity in Minecraft's camera), so it is exact however far the two cameras are
		// apart. It goes in at the far plane: everything Portal 2 draws (portals, cubes, the gun) lands on top.
		clip(Sky.x - 0.5);
		clip(-b.z - 1e-4);
		const float2 ns = clamp(b.xy / -b.z / mcScale, -1.0, 1.0);
		// (alpha 0 is fine: low over the horizon Minecraft draws no sky disc, only its fog colour behind everything - the
		// clear colour, which is that pixel's colour)
		const float4 sky = tex2Dlod(sWorld, float4(ns * 0.5 + 0.5, 0, 0)).bgra;
		o.color = float4(fogged(sky.rgb, 1e9, dExit, true), 1.0);
		o.depth = 1.0;
		return o;
	}
	// through a portal: what is behind the exit portal (between the camera behind it and its surface) isn't seen
	if (ClipOn.x > 0.5)
		clip(tHit * (Clip.x + ndc.x * Clip.y + ndc.y * Clip.z) + Clip.w + 1.0);
	float4 world = tex2Dlod(sWorld, float4(uvHit, 0, 0)).bgra;
	if (world.a < 0.98 && Sky.x < 0.5)
	{
		// at a solid surface's edge the (linear) lookup takes in the empty pixel beside it: not see-through - the pixel
		// whose depth this is is solid. (Handed on to Portalcraft.fx, it was blended over whatever Portal 2 has behind:
		// in a hole dug into its wall, its far-off world - the white seam again.)
		const float2 tx = McTexel.x > 0.0 ? McTexel.xy : float2(1.0 / 1920.0, 1.0 / 1080.0);
		const float4 own = tex2Dlod(sWorld, float4((floor(uvHit / tx) + 0.5) * tx, 0, 0)).bgra;
		if (own.a >= 0.98)
			world = own;
	}
	if (world.a < 0.98)
	{
		// translucent (water, glass): Portalcraft.fx blends it over Portal 2's own picture at the end. In Minecraft's
		// own world there is no Portal 2 picture behind it (it blended over black or the last frame's smears), and its
		// colour already holds what Minecraft has behind it (terrain, or its fog-coloured background; the alpha there is
		// only the leaves' or the water's): it goes in as it is.
		clip(Sky.x - 0.5);
		world.a = 1.0;
	}

	// relight by the light around this pixel in Portal 2's picture
	const float2 suv = px / Screen.xy;
	const float3 L = tex2Dlod(sLight, float4(suv, 0, 0)).rgb;
	const float lum = luma(L);
	const float gain = Light.y < 0.0 ? 1.0 : clamp(lum / Light.y, 0.35, 1.25); // (Minecraft already has Portal 2's light)
	const float3 tint = clamp(lerp(1.0, L / max(lum, 1e-3), Light.z), 0.6, 1.5);
	o.color = float4(lerp(world.rgb, world.rgb * gain * tint, Light.x), 1.0);
	// under water (lava, powder snow): Minecraft's fog, like Portal 2's fog cvars give Portal 2's world. Not where
	// Minecraft fogged its picture already (its own world, the player's view: again here, the water got twice as murky
	// as Minecraft's own); through a portal there it leaves a fluid's to this, from the exit portal on.
	o.color.rgb = fogged(o.color.rgb, tHit * rayLen, dExit, ClipOn.y < 0.5);
	if (Light.w > 0.5)
		o.color = float4(frac(tHit / 64.0), uvHit, 1.0);

	// seen through water (glass): the colour carries what Minecraft has behind the water, so the depth is that solid
	// thing's - a Portal 2 wall between the water and it hides it (the water's tint goes on that wall in Portalcraft.fx)
	float tDepth = tHit;
	if (Opaque.x > 0.5)
	{
		const float zo = mc_linear(tex2Dlod(sODepth, float4(uvHit, 0, 0)).r);
		if (zo < 1e8 && zo > mc_depth(uvHit) + 2.0)
			tDepth = max((-zo - McA.z) / min(b.z, -1e-4), tHit);
	}
	// Portal 2's depth for this point, a little closer (so Minecraft wins ties against the surfaces it rests on) - but on
	// an open portal's own surface a little farther: Portal 2 draws the portal a unit off it, and the portal must win
	// (a portal on Minecraft's blocks; a Minecraft surface just behind a wall a portal is on)
	float bias = DepthK.z;
	[unroll] for (int p = 0; p < 2; ++p)
	{
		const float pf = tHit * (PortalF[p].x + ndc.x * PortalF[p].y + ndc.y * PortalF[p].z) + PortalF[p].w;
		const float pr = tHit * (PortalR[p].x + ndc.x * PortalR[p].y + ndc.y * PortalR[p].z) + PortalR[p].w;
		const float pu = tHit * (PortalU[p].x + ndc.x * PortalU[p].y + ndc.y * PortalU[p].z) + PortalU[p].w;
		// (behind the portal's plane, up to a few units into its surface; across its 2 x 4 blocks)
		if (p < Portals.x && pf > -6.0 && pf < 1.0 && abs(pr) < 34.0 && abs(pu) < 66.0)
			bias = -2.0;
	}
	const float t = max(tDepth - bias, 1.0);
	const float zc = DepthK.x + t * (Dz.x + ndc.x * Dz.y + ndc.y * Dz.z);
	const float wc = DepthK.y + t * (Dw.x + ndc.x * Dw.y + ndc.y * Dw.z);
	o.depth = saturate(zc / wc);
	return o;
}
