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
float4 Fog : register(c10);     // the fluid fog Minecraft's camera is in: x start, y end (units, along the view), z 1 when on
float4 FogColor : register(c11);
float4 Clip : register(c12);     // through a portal: the exit portal's plane, t * (x + ndc.x y + ndc.y z) + w (> 0: in front)
float4 ClipOn : register(c13);   // x: 1 through a portal
float4 Opaque : register(c14);   // x: 1 when sODepth is Minecraft's solid-only depth
float4 Sky : register(c15);      // x: 1 in Minecraft's own world (sp_mc_overworld): Minecraft's sky where it has no surface
float4 ObliqueQ : register(c16); // a frame through a portal: its near plane is the exit portal's (q, w in units)
float4 Oblique : register(c17);  // x: 1 when the depth is that oblique kind

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

Out main(float2 vpos : VPOS)
{
	Out o;
	const float2 px = vpos + 0.5 - Screen.zw;
	const float2 ndc = float2(px.x / Screen.x * 2.0 - 1.0, 1.0 - px.y / Screen.y * 2.0);
	const float3 b = McB0.xyz + ndc.x * McBX.xyz + ndc.y * McBY.xyz;
	const float2 mcScale = McProj.xy;

	// march from near to far in log steps: the first point behind Minecraft's surface is where Minecraft is seen
	const float zNear = 4.0, zFar = DepthK.w;
	float tHit = -1.0;
	float2 uvHit = 0.0;
	float tPrev = zNear;
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
			continue; // still in front of what Minecraft drew there
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
		if (abs(nf.x) > 1.0 || abs(nf.y) > 1.0 || abs(zf - -cf.z) > 2.0 + 0.02 * -cf.z)
			break;
		tHit = tg;
		uvHit = nf * 0.5 + 0.5;
		break;
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
		o.color = float4(sky.rgb, 1.0);
		if (Fog.z > 0.5)
			o.color.rgb = FogColor.rgb;
		o.depth = 1.0;
		return o;
	}
	// through a portal: what is behind the exit portal (between the camera behind it and its surface) isn't seen
	if (ClipOn.x > 0.5)
		clip(tHit * (Clip.x + ndc.x * Clip.y + ndc.y * Clip.z) + Clip.w + 1.0);
	float4 world = tex2Dlod(sWorld, float4(uvHit, 0, 0)).bgra;
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
	// under water (lava, powder snow): Minecraft's fog, like Portal 2's fog cvars give Portal 2's world (by view depth)
	if (Fog.z > 0.5)
		o.color.rgb = lerp(o.color.rgb, FogColor.rgb, saturate((tHit - Fog.x) / max(Fog.y - Fog.x, 1.0)));
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
	// Portal 2's depth for this point, a little closer (so Minecraft wins ties against the surfaces it rests on)
	const float t = max(tDepth - DepthK.z, 1.0);
	const float zc = DepthK.x + t * (Dz.x + ndc.x * Dz.y + ndc.y * Dz.z);
	const float wc = DepthK.y + t * (Dw.x + ndc.x * Dw.y + ndc.y * Dw.z);
	o.depth = saturate(zc / wc);
	return o;
}
