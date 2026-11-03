// Portalcraft: composites Minecraft (the Portalcraft Fabric mod) into Portal 2. The portalcraft.addon32 add-on uploads
// Minecraft's newest frame into PCWORLD / PCDEPTH / PCOVERLAY and sets the Pc* uniforms every frame.
//
// world:   Minecraft's level pass (blocks, mobs, items), premultiplied RGBA, rows bottom-up (uploaded as raw bytes into
//          BGRA textures, the 8-bit format D3D9 supports everywhere, so samples are swizzled back), re-projected from the
//          camera Minecraft rendered with onto the camera Portal 2 drew this frame with, and depth-tested against
//          Portal 2's depth buffer (everything in Source units).
// overlay: Minecraft's hand, HUD and screens, always on top.
#include "ReShade.fxh"

texture PcWorldTex : PCWORLD;
texture PcDepthTex : PCDEPTH;
texture PcOverlayTex : PCOVERLAY;
texture PcODepthTex : PCODEPTH; // Minecraft's depth of only its solid things (before water, glass)
// Dug cells (real mining): one texel each, min corner from an anchor near them (the camera from it: PcMineEye), w = size.
// Where Portal 2's surface lies in one, Portal 2 is taken away there and Minecraft (the hole) is shown.
texture PcMineTex : PCMINE;
// Hallow's Eve: the clip's frames (keyed, premultiplied BGRA) in one atlas, PcBoo.z columns by PcBoo.w rows
texture PcBooTex : PCBOO;
sampler sWorld { Texture = PcWorldTex; AddressU = CLAMP; AddressV = CLAMP; };
sampler sDepth { Texture = PcDepthTex; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sOverlay { Texture = PcOverlayTex; AddressU = CLAMP; AddressV = CLAMP; };
sampler sODepth { Texture = PcODepthTex; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sMine { Texture = PcMineTex; MinFilter = POINT; MagFilter = POINT; MipFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sBoo { Texture = PcBooTex; AddressU = CLAMP; AddressV = CLAMP; };

// ---- set by the add-on ----
uniform bool PcActive = false;
uniform bool PcOverlay = true;
// the hand and HUD already went in under Portal 2's 2D pass (PcOverlay is false then)
uniform bool PcOverlayEarly = false;
// Hallow's Eve, the frame playing: x 1 while one plays, y the frame, zw the atlas's columns and rows; the frames' part of
// the clip's picture (u0, v0, u1, v1); a frame's size in texels and the clip's aspect (the picture fits the screen)
uniform float4 PcBoo = float4(0.0, 0.0, 1.0, 1.0);
uniform float4 PcBooCrop = float4(0.0, 0.0, 1.0, 1.0);
uniform float3 PcBooFrame = float3(1.0, 1.0, 1.7777778);
// Portal 2's screen fade this frame (env_fade, deaths, level ends): colour and strength, and a multiplying fade's colour -
// the hand and HUD take it too (Portal 2 faded its own picture before this)
uniform float4 PcFade = float4(0.0, 0.0, 0.0, 0.0);
uniform float3 PcFadeMul = float3(1.0, 1.0, 1.0);
// Minecraft's light sources near the player (torches, lava...), in Portal 2's camera space (x right, y up, z back):
// position, and in w its reach (units: light level x 32) + 1000 x its colour (light_colour) - Portal 2's lighting is
// baked, so this lights its surfaces around them. (One array: in shader model 3 ReShade gives every array element four
// constant registers and every other value one, of 224.)
uniform float4 PcLightPos[12];
uniform int PcLightCount = 0;
// emancipation grills and laser fields placed from Minecraft (no brush for Portal 2 to draw them from): axis-aligned boxes
// in world axes, centre relative to the camera (w: 0 grill, 1 laser field) and half sizes - the field is the plane across
// the box's thin side; and the camera's axes in world space
uniform float4 PcFieldC[8];
uniform float4 PcFieldH[8];
uniform int PcFieldCount = 0;
uniform int PcMineCount = 0;
uniform float3 PcMineEye = float3(0.0, 0.0, 0.0);
uniform float3 PcCamR = float3(0.0, -1.0, 0.0);
uniform float3 PcCamU = float3(0.0, 0.0, 1.0);
uniform float3 PcCamF = float3(1.0, 0.0, 0.0);
uniform float PcTimer < source = "timer"; >;
// the add-on drew Minecraft's opaque pixels inside Portal 2's frame (PortalcraftEarly.hlsl): only translucent ones here
uniform bool PcEarly = false;
// the add-on drew the dug holes into Portal 2's frame itself (before its models, beams and captions): nothing to do here
uniform bool PcHoleDone = false;
// sODepth holds Minecraft's solid-only depth this frame
uniform bool PcOpaqueDepth = false;
// Portal 2 is in sp_mc_overworld: Minecraft's own world, its own light and sky
uniform bool PcSurface = false;
// Portal 2's camera near/far (units)
uniform float2 PcHostPlanes = float2(7.0, 28400.0);
// Minecraft's near, far (units) and flags (1: depth in [0,1], 2: rows bottom-up, 4: reversed Z)
uniform float3 PcMcPlanes = float3(1.6, 32768.0, 7.0);
// rows of R_mc^T R_host: a Portal 2 camera-space vector in Minecraft's camera space (x right, y up, -z forward)
uniform float3 PcWarpRow0 = float3(1.0, 0.0, 0.0);
uniform float3 PcWarpRow1 = float3(0.0, 1.0, 0.0);
uniform float3 PcWarpRow2 = float3(0.0, 0.0, 1.0);
// Portal 2's camera position relative to Minecraft's, in Minecraft's camera space (units)
uniform float3 PcWarpT = float3(0.0, 0.0, 0.0);
// x: tan(Portal 2 vertical fov / 2), y: tan(Minecraft's / 2), z: Minecraft's aspect
uniform float3 PcWarpTan = float3(0.75, 0.81, 1.7778);
// x, y: mouse cursor (0..1), z: 1 while a Minecraft screen is open
uniform float3 PcCursor = float3(0.5, 0.5, 0.0);
// the fluid fog Minecraft's camera is in (water, lava, powder snow): start, end (units along the view), 1 when on
uniform float3 PcFog = float3(0.0, 1.0, 0.0);
uniform float3 PcFogColor = float3(0.0, 0.0, 0.0);

// ---- tweakables ----
uniform float DepthBias < ui_type = "drag"; ui_min = 0.0; ui_max = 16.0; ui_step = 0.1; ui_label = "Depth bias (units)";
	ui_tooltip = "How far behind Portal 2's surface Minecraft may still show (blocks resting on floors)."; > = 1.5;
uniform float SlopeBias < ui_type = "drag"; ui_min = 0.0; ui_max = 40.0; ui_step = 0.1; ui_label = "Depth bias per grazing slope"; > = 2.0;
uniform float MaxBias < ui_type = "drag"; ui_min = 0.5; ui_max = 64.0; ui_step = 0.5; ui_label = "Largest depth bias (units)"; > = 12.0;
uniform bool Reproject < ui_label = "Re-project to Portal 2's camera"; > = true;
uniform float LightMatch < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Match Portal 2 lighting";
	ui_tooltip = "Relight Minecraft by the (blurred) Portal 2 picture around it."; > = 0.55;
uniform float LightReference < ui_type = "drag"; ui_min = 0.1; ui_max = 1.0; ui_step = 0.01; ui_label = "Neutral brightness"; > = 0.45;
uniform float LightTint < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Light color"; > = 0.35;
uniform float McLightStrength < ui_type = "drag"; ui_min = 0.0; ui_max = 4.0; ui_step = 0.05; ui_label = "Minecraft light sources on Portal 2"; > = 0.6;
uniform float EdgeSoftness < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Soften Minecraft's edges"; > = 0.6;
uniform bool EarlyComposite < ui_label = "Draw Minecraft inside the Portal 2 frame";
	ui_tooltip = "On: Minecraft goes in before the Portal 2 world, so Portal 2 beams, glass, particles, etc. draw over it with real depth. Off: Just slap it on top."; > = true;
uniform bool OverlayUnderHud < ui_label = "Minecraft hand and HUD under Portal 2 captions";
	ui_tooltip = "On: Minecraft's hand and HUD go in when Portal 2 starts drawing its HUD, so those draw on top. Off: Just. Slap. It. On. Top. I don't CARE."; > = true;
uniform bool EarlyDebug < ui_label = "Show the early composite march (debug)"; > = false;
uniform int DebugView < ui_type = "combo"; ui_items = "Composite\0Portal 2 depth (32-unit bands)\0Minecraft depth (32-unit bands)\0Minecraft unprojected\0"; > = 0;

// Portal 2's picture at quarter size with mips: its blurred levels stand in for the light around each pixel.
texture PcLightTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA8; MipLevels = 6; };
sampler sLight { Texture = PcLightTex; AddressU = CLAMP; AddressV = CLAMP; };
// The composited world (no overlay), alpha = Minecraft coverage (for the edge pass).
texture PcCompositeTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sComposite { Texture = PcCompositeTex; MinFilter = POINT; MagFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };

float luma(float3 c)
{
	return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float mc_linear(float d)
{
	const float n = PcMcPlanes.x, f = PcMcPlanes.y;
	if (d <= 0.0)
		return 1e9; // nothing drawn (reversed Z: cleared to 0)
	return n * f / (n + d * (f - n));
}

float host_linear(float d)
{
	const float n = PcHostPlanes.x, f = PcHostPlanes.y;
	if (d >= 1.0)
		return 1e9;
	return n * f / (f - d * (f - n));
}

float3 bands(float z)
{
	const float t = frac(z / 32.0);
	return lerp(float3(0.1, 0.1, 0.1), float3(1.0, 0.85, 0.3), step(0.5, t)) * saturate(1.5 - z / 3000.0);
}

// muv: Minecraft's picture, y up (its rows are stored bottom-up, so this is the texture coordinate as is)
float4 mc_world(float2 muv)
{
	return tex2Dlod(sWorld, float4(muv, 0, 0)).bgra; // RGBA bytes uploaded into a BGRA texture
}

float mc_depth(float2 muv)
{
	return mc_linear(tex2Dlod(sDepth, float4(muv, 0, 0)).r);
}

float3 relight(float3 c, float2 uv)
{
	if (PcSurface)
		return c; // (Minecraft's own light)
	const float3 L = tex2Dlod(sLight, float4(uv, 0, 3.0)).rgb;
	const float lum = luma(L);
	const float gain = clamp(lum / LightReference, 0.35, 1.25);
	const float3 tint = clamp(lerp(1.0, L / max(lum, 1e-3), LightTint), 0.6, 1.5);
	return lerp(c, c * gain * tint, LightMatch);
}

// LightSources' colours: 0 warm (torches, fire, lava), 1 soul fire, 2 redstone, 3 white, 4 green, 5 purple
float3 light_colour(float i)
{
	return i < 0.5 ? float3(1.0, 0.72, 0.42) : i < 1.5 ? float3(0.45, 0.85, 1.0) : i < 2.5 ? float3(1.0, 0.28, 0.18)
		: i < 3.5 ? float3(0.85, 0.92, 1.0) : i < 4.5 ? float3(0.6, 1.0, 0.7) : float3(0.75, 0.45, 1.0);
}

// Portal 2's surface at view-space point P (normal N) lit by Minecraft's light sources: brighter by how near and how
// squarely it faces each (a surface turned away gets none - so a wall's far side stays dark), as a multiple of its own
// colour (black stays black: fades, shadowed voids)
float3 mc_lights(float3 c, float3 P, float3 N)
{
	if (PcLightCount <= 0 || McLightStrength <= 0.0 || PcSurface)
		return c;
	float3 sum = 0.0;
	[loop] for (int i = 0; i < PcLightCount; ++i)
	{
		const float3 L = PcLightPos[i].xyz - P;
		const float d = length(L);
		const float colour = floor(PcLightPos[i].w / 1000.0);
		const float reach = PcLightPos[i].w - colour * 1000.0;
		// (no `continue` in these loops: in shader model 3 it ended the loop, so only the first light or field counted)
		const float fall = saturate(1.0 - d / reach);
		const float facing = saturate((dot(N, L / max(d, 1e-3)) + 0.3) / 1.3);
		sum += light_colour(colour) * (fall * fall * facing * saturate(reach / 480.0)); // (strength: light level / 15)
	}
	return c * (1.0 + McLightStrength * sum);
}

float hash21(float2 p)
{
	return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float noise2(float2 p)
{
	const float2 i = floor(p), f = frac(p);
	const float2 w = f * f * (3.0 - 2.0 * f);
	return lerp(lerp(hash21(i), hash21(i + float2(1, 0)), w.x), lerp(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), w.x), w.y);
}

// The fields placed from Minecraft where this pixel's view ray crosses them in front of Portal 2's surface (zh along the
// view axis), added on as light: a grill's pale blue haze with streaks drifting up and a scanline, a laser field's red
// glow with bright horizontal lines
// One field where the view ray (world axes, one unit of depth a step) crosses it in front of Portal 2's surface (zh): its
// light, and the tint it gives what is behind it. C: centre relative to the camera (w: kind), H: half sizes.
void mc_field(float4 C, float3 H, float3 dir, float zh, float t, inout float3 add, inout float3 tint)
{
	// a vertical plane: across x (thin in y) or across y (thin in x)
	const bool acrossX = H.x >= H.y;
	const float den = acrossX ? dir.y : dir.x;
	if (abs(den) < 1e-6)
		return;
	const float s = (acrossX ? C.y : C.x) / den; // depth along the view axis, as zh
	if (s <= 0.0 || s >= zh)
		return;
	const float3 d = dir * s - C.xyz;
	const float halfW = acrossX ? H.x : H.y;
	const float along = acrossX ? d.x : d.y;
	if (abs(along) > halfW || abs(d.z) > H.z)
		return;
	const float w = 2.0 * halfW, h = 2.0 * H.z;
	const float x = along + halfW, y = d.z + H.z; // units across and up
	const float edge = min(min(x, w - x), min(y, h - y)); // units from the nearest edge
	const float rim = exp(-edge / 3.0);
	if (C.w < 0.5)
	{
		// an emancipation grill: what is behind it turns blue, under thin bright lines that ripple like light through
		// water, brightest where it meets its emitters
		const float2 p = float2(x, y) / 14.0;
		const float n1 = noise2(p + float2(t * 0.15, t * 0.25)), n2 = noise2(p * 1.7 - float2(t * 0.2, -t * 0.1));
		const float ridges = pow(saturate(1.0 - abs(n1 - n2) * 2.0), 24.0);
		const float side = exp(-min(x, w - x) / 5.0);
		tint *= lerp(1.0, float3(0.55, 0.78, 1.0), 0.55);
		add += float3(0.35, 0.75, 1.0) * (0.05 + 0.45 * ridges) + float3(0.6, 0.9, 1.0) * (0.45 * side + 0.1 * rim);
	}
	else
	{
		// a laser field: a red sheet of bright horizontal lines, flickering along
		const float lines = pow(abs(sin(y * 3.14159 / 6.0)), 20.0) * (0.6 + 0.4 * noise2(float2(x / 10.0 + t * 4.0, y)));
		const float haze = 0.06 + 0.05 * noise2(float2(x / 16.0 - t, y / 16.0));
		tint *= lerp(1.0, float3(1.0, 0.62, 0.55), 0.35);
		add += float3(1.0, 0.32, 0.12) * (haze + 0.8 * lines + 0.4 * rim);
	}
}

float3 mc_fields(float3 c, float3 ray, float zh)
{
	if (PcFieldCount <= 0)
		return c;
	const float t = PcTimer * 0.001;
	// the view ray in world axes (camera z is back; ray.z = -1 is one unit of depth)
	const float3 dir = PcCamR * ray.x + PcCamU * ray.y - PcCamF * ray.z;
	float3 add = 0.0, tint = 1.0;
	[loop] for (int i = 0; i < PcFieldCount; ++i)
		mc_field(PcFieldC[i], PcFieldH[i].xyz, dir, zh, t, add, tint);
	// (Portal 2's fades: the fields fade with its picture)
	return c * tint + add * (1.0 - PcFade.a) * PcFadeMul;
}

// Does the point (world axes, relative to the camera) lie in a dug cell?
bool in_dug(float3 p)
{
	const float3 q = p + PcMineEye;
	bool dug = false;
	[loop] for (int i = 0; i < PcMineCount; ++i)
	{
		const float4 c = tex2Dlod(sMine, float4((i + 0.5) / 256.0, 0.5, 0, 0));
		const float3 d = q - c.xyz;
		dug = dug || (all(d >= 0.0) && all(d < c.w));
	}
	return dug;
}

float4 PS_Light(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 c = tex2D(ReShade::BackBuffer, uv).rgb;
	if (PcActive && PcMineCount > 0 && !PcHoleDone)
	{
		// a dug cell gives no light: what is drawn there is the surface that was dug away (it showed through, tinting the hole)
		const float zh = host_linear(tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, 0)).x);
		const float aspect = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
		const float3 ray = float3((uv.x * 2.0 - 1.0) * PcWarpTan.x * aspect, (1.0 - uv.y * 2.0) * PcWarpTan.x, -1.0);
		if (zh < 1e8 && in_dug((PcCamR * ray.x + PcCamU * ray.y - PcCamF * ray.z) * (zh + 0.5)))
			c = 0.0;
	}
	return float4(c, 1.0);
}

float4 PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 host = tex2D(ReShade::BackBuffer, uv).rgb;
	if (!PcActive)
		return float4(host, 0.0);

	float zh = host_linear(tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, 0)).x);
	const float allow = min(DepthBias + SlopeBias * abs(ddy(zh)) * 0.05, max(MaxBias, DepthBias));
	const float aspect = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
	// this pixel's view ray in Portal 2's camera space (z = -1)
	const float3 ray = float3((uv.x * 2.0 - 1.0) * PcWarpTan.x * aspect, (1.0 - uv.y * 2.0) * PcWarpTan.x, -1.0);
	const float2 mcScale = float2(PcWarpTan.y * PcWarpTan.z, PcWarpTan.y);
	// Portal 2's surface here (view space) and which way it faces, from how the point moves across the screen
	const float3 surface = ray * min(zh, 1e6);
	float3 normal = normalize(cross(ddy(surface), ddx(surface)) + 1e-6);
	normal = dot(normal, surface) > 0.0 ? -normal : normal;
	// a dug cell: Portal 2's surface there is gone (a little behind it decides: the surface lies on a cell's edge)
	bool dug = false;
	if (PcMineCount > 0 && zh < 1e8 && !PcHoleDone)
	{
		const float3 dir = PcCamR * ray.x + PcCamU * ray.y - PcCamF * ray.z;
		dug = in_dug(dir * (zh + 0.5));
		if (dug)
			zh = 1e9;
	}

	float2 muv = 0.5;
	float zm = 1e9;
	bool inside = false;
	if (Reproject)
	{
		// March the ray from near to far, moving each point into Minecraft's camera: the first point behind
		// Minecraft's surface there is where Minecraft is seen. Refine it, then sample.
		const float zNear = 4.0, zFar = max(min(zh + allow, 8000.0), 8.0);
		float zPrev = zNear;
		[loop] for (int i = 0; i < 32; ++i)
		{
			const float z = zNear * pow(zFar / zNear, i / 31.0);
			const float3 p = ray * z;
			const float3 pm = float3(dot(PcWarpRow0, p), dot(PcWarpRow1, p), dot(PcWarpRow2, p)) + PcWarpT;
			if (pm.z > -1.0)
			{
				zPrev = z;
				continue;
			}
			const float2 n = pm.xy / -pm.z / mcScale;
			if (abs(n.x) > 1.0 || abs(n.y) > 1.0)
			{
				zPrev = z;
				continue;
			}
			const float zmv = mc_depth(n * 0.5 + 0.5);
			if (zmv > -pm.z + 1.0)
			{
				zPrev = z;
				continue; // still in front of whatever Minecraft drew there
			}
			// crossed Minecraft's surface since the last step: bisect for where (no edges skipped), then settle on it
			float lo = zPrev, hi = z;
			[loop] for (int j = 0; j < 6; ++j)
			{
				const float zm = 0.5 * (lo + hi);
				const float3 pq = ray * zm;
				const float3 mq = float3(dot(PcWarpRow0, pq), dot(PcWarpRow1, pq), dot(PcWarpRow2, pq)) + PcWarpT;
				const float2 nq = mq.xy / -min(mq.z, -1.0) / mcScale;
				if (mq.z <= -1.0 && abs(nq.x) <= 1.0 && abs(nq.y) <= 1.0 && mc_depth(nq * 0.5 + 0.5) <= -mq.z + 1.0)
					hi = zm;
				else
					lo = zm;
			}
			float zg = hi;
			float2 ndc = n;
			[loop] for (int k = 0; k < 3; ++k)
			{
				const float3 pk = ray * zg;
				const float3 mk = float3(dot(PcWarpRow0, pk), dot(PcWarpRow1, pk), dot(PcWarpRow2, pk)) + PcWarpT;
				if (mk.z > -1.0)
					break;
				const float2 nk = mk.xy / -mk.z / mcScale;
				if (abs(nk.x) > 1.0 || abs(nk.y) > 1.0)
					break;
				const float zk = mc_depth(nk * 0.5 + 0.5);
				if (zk > 1e8)
					break;
				ndc = nk;
				const float3 q = float3(nk * mcScale, -1.0) * zk - PcWarpT;
				zg = -(q.x * PcWarpRow0.z + q.y * PcWarpRow1.z + q.z * PcWarpRow2.z);
			}
			muv = ndc * 0.5 + 0.5;
			zm = zg;
			inside = true;
			break;
		}
	}
	else
	{
		// rotation only
		const float3 pm = float3(dot(PcWarpRow0, ray), dot(PcWarpRow1, ray), dot(PcWarpRow2, ray));
		if (pm.z < -1e-4)
		{
			const float2 n = pm.xy / -pm.z / mcScale;
			muv = n * 0.5 + 0.5;
			inside = abs(n.x) <= 1.0 && abs(n.y) <= 1.0;
			zm = mc_depth(muv) / max(-pm.z, 1e-4); // along Minecraft's axis -> along this ray (approximately)
		}
	}

	float4 world = inside ? mc_world(muv) : 0.0;
	world.rgb *= world.a > 0.0 ? 1.0 : 0.0;
	// Portal 2's own surface (Minecraft lights its own): Minecraft's torches and lava light it
	if (!(inside && world.a > 0.0) && zh < 1e8 && DebugView == 0)
		host = mc_lights(host, surface, normal);
	// the fields placed from Minecraft in front of what is here (Minecraft's solid pixels drew their depth in early)
	if (DebugView == 0)
		host = mc_fields(host, ray, zh);
	// a Portal 2 surface between Minecraft's water (glass) and the solid thing Minecraft has behind it: the early
	// composite left the surface in front (PortalcraftEarly.hlsl) - it shows under the water's tint
	if (PcOpaqueDepth && inside && world.a >= 0.98 && DebugView == 0)
	{
		const float zt = mc_depth(muv);
		const float zo = mc_linear(tex2Dlod(sODepth, float4(muv, 0, 0)).r);
		if (zo < 1e8 && zo > zt + 2.0 && zh > zm + allow && zh < zm * zo / max(zt, 1e-3) - allow)
		{
			const float3 tint = PcFog.z > 0.5 ? PcFogColor : float3(0.17, 0.32, 0.62);
			return float4(lerp(host, tint, 0.45), 1.0);
		}
	}
	// Minecraft's own world without the early composite (which draws the sky there itself): its sky where Portal 2 has
	// nothing - it only depends on the ray's direction, so Minecraft's camera rotation is all that matters
	if (PcSurface && !PcEarly && world.a <= 0.0 && zh > 2000.0 && DebugView == 0)
	{
		const float3 sd = float3(dot(PcWarpRow0, ray), dot(PcWarpRow1, ray), dot(PcWarpRow2, ray));
		if (sd.z < -1e-4)
		{
			const float4 sky = mc_world(clamp(sd.xy / -sd.z / mcScale, -1.0, 1.0) * 0.5 + 0.5);
			return float4(PcFog.z > 0.5 ? PcFogColor : sky.rgb, 1.0); // (alpha 0 low over the horizon: the fog colour)
		}
	}
	// a dug cell with nothing of Minecraft's behind it: dark (what Portal 2 has behind its surface was never drawn)
	if (dug && !(inside && world.a > 0.0) && DebugView == 0)
		return float4(0.0, 0.0, 0.0, 1.0);
	if (PcEarly && (world.a >= 0.98 || PcSurface) && !dug && DebugView == 0)
		return float4(host, 0.0); // already in the picture, under Portal 2's own drawing (Minecraft's own world: all of it)

	if (DebugView == 1)
		return float4(bands(zh), 0.0);
	if (DebugView == 2)
		return float4(world.a > 0.0 ? bands(zm) : host * 0.3, 0.0);
	if (DebugView == 3)
	{
		const float4 raw = tex2Dlod(sWorld, float4(uv.x, 1.0 - uv.y, 0, 0)).bgra;
		return float4(raw.rgb + host * (1.0 - raw.a), 0.0);
	}

	// translucent Minecraft (water, glass) may be further under a Portal 2 floor: Minecraft's water rests on the block
	// grid, up to half a block below a floor that isn't on it, and thin flowing water vanished under it
	const float reach = world.a < 0.98 ? max(allow, 18.0) : allow;
	const float visible = zm < zh + reach ? 1.0 : 0.0;
	const float cover = world.a * visible;
	float3 mc = relight(world.rgb, uv);
	if (PcFog.z > 0.5)
		mc = lerp(mc, PcFogColor * world.a, saturate((zm - PcFog.x) / max(PcFog.y - PcFog.x, 1.0))); // (premultiplied)
	return float4(mc * visible + host * (1.0 - cover), cover);
}

float3 final_color(float2 uv)
{
	if (!PcActive)
		return tex2D(ReShade::BackBuffer, uv).rgb;
	const float2 px = BUFFER_PIXEL_SIZE;
	const float4 c0 = tex2D(sComposite, uv);
	float3 color = c0.rgb;
	if (EdgeSoftness > 0.0)
	{
		// Portal 2's anti-aliasing never saw Minecraft: soften where Minecraft meets Portal 2
		const float4 c1 = tex2D(sComposite, uv + float2(px.x, 0)), c2 = tex2D(sComposite, uv - float2(px.x, 0));
		const float4 c3 = tex2D(sComposite, uv + float2(0, px.y)), c4 = tex2D(sComposite, uv - float2(0, px.y));
		const float edge = saturate(abs(c1.a - c0.a) + abs(c2.a - c0.a) + abs(c3.a - c0.a) + abs(c4.a - c0.a));
		if (edge > 0.0)
			color = lerp(color, (color * 2.0 + c1.rgb + c2.rgb + c3.rgb + c4.rgb) / 6.0, edge * EdgeSoftness);
	}
	if (PcOverlay || (PcOverlayEarly && c0.a > 0.0))
	{
		// (drawn early, the hand and HUD are already in - except under translucent Minecraft blended here: again on top)
		float4 overlay = tex2D(sOverlay, float2(uv.x, 1.0 - uv.y)).bgra; // hand, HUD, screens: screen space, rows bottom-up
		overlay.rgb = lerp(overlay.rgb, PcFade.rgb * overlay.a, PcFade.a) * PcFadeMul;
		color = overlay.rgb + saturate(color) * (1.0 - overlay.a);
	}
	if (PcCursor.z > 0.5)
	{
		// a Minecraft screen is open: Portal 2's cursor is hidden, so draw one (an arrow, white with a dark edge)
		const float2 d = (uv - PcCursor.xy) * float2(BUFFER_WIDTH, BUFFER_HEIGHT);
		const bool body = d.x >= 0.0 && d.y >= 0.0 && d.x <= d.y * 0.62 && d.y <= 17.0 - d.x * 0.35;
		const float2 e = d + 1.2;
		const bool rim = e.x >= -0.5 && e.y >= -0.5 && e.x <= e.y * 0.62 + 1.5 && e.y <= 19.5 - e.x * 0.35;
		if (body)
			color = 1.0;
		else if (rim)
			color = 0.08;
	}
	return color;
}

float3 PS_Final(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	float3 color = final_color(uv);
	if (PcBoo.x > 0.5)
	{
		// the clip's picture as big as the screen takes (centred), its frame where the atlas has it
		const float screen = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
		float2 p = uv;
		if (screen > PcBooFrame.z)
			p.x = (uv.x - 0.5) * screen / PcBooFrame.z + 0.5;
		else
			p.y = (uv.y - 0.5) * PcBooFrame.z / screen + 0.5;
		const float2 q = (p - PcBooCrop.xy) / (PcBooCrop.zw - PcBooCrop.xy);
		if (all(q >= 0.0) && all(q <= 1.0))
		{
			const float row = floor(PcBoo.y / PcBoo.z);
			const float2 cell = float2(PcBoo.y - row * PcBoo.z, row);
			const float2 inset = 0.5 / PcBooFrame.xy; // (not into the next frame's texels)
			const float4 boo = tex2D(sBoo, (cell + clamp(q, inset, 1.0 - inset)) / PcBoo.zw);
			color = boo.rgb + saturate(color) * (1.0 - boo.a);
		}
	}
	return color;
}

technique Portalcraft < ui_tooltip = "Minecraft inside Portal 2: drawn while the Portalcraft link is up."; >
{
	pass Light
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Light;
		RenderTarget = PcLightTex;
	}
	pass Composite
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Composite;
		RenderTarget = PcCompositeTex;
	}
	pass Final
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Final;
	}
}
