// Portalcraft: the Portal 2 (VScript) half of the bridge to Minecraft.
// Put into portal2\scripts\vscripts\portalcraft\ for a play session by tools\portalcraft.ps1 (and taken out again).
// The add-on runs it with `script_execute portalcraft/portalcraft` after every level load, then calls these functions
// with `script "PC...(...)"` console commands.
if (!("Entities" in this)) return; // client side

printl("[Portalcraft] portalcraft.nut");

// ---- Minecraft blocks: invisible solid boxes (the player stands on them, lasers stop at them) ----
::PCboxes <- {};

/// Every box goes (Minecraft sends them all again): by name, so ones the table lost (a script reload) go too.
::PCboxClear <- function () {
	local list = [];
	for (local e = Entities.FindByName(null, "pc_box"); e != null; e = Entities.FindByName(e, "pc_box")) list.append(e);
	foreach (e in list) e.Destroy();
	::PCboxes <- {};
}

::PCdel <- function (id) {
	if (id in PCboxes) {
		local e = PCboxes[id];
		if (e != null && e.IsValid()) e.Destroy();
		delete PCboxes[id];
	}
}

// The box's model is never drawn, but traces that test hitboxes (lasers, bullets: MASK_SHOT) hit a model's hitboxes
// instead of its box. Chell's skeleton stood at each box's corner, so lasers went through most of a block: a model
// with no hitboxes makes them stop at the box. (The add-on precaches it, then switches to it.)
::PCboxModel <- "models/player/chell/player.mdl";
::PCboxHitboxFree <- function (on) {
	PCboxModel = on ? "models/props_office/paper_single.mdl" : "models/player/chell/player.mdl";
}

/// A box with its min corner at (x, y, z) and size (a, b, c), all in units.
::PCbox <- function (id, x, y, z, a, b, c) {
	PCdel(id);
	local e = CreateProp("prop_dynamic", Vector(x, y, z), PCboxModel, 0);
	if (e == null) return;
	e.__KeyValueFromInt("solid", 2);
	e.__KeyValueFromInt("rendermode", 10);
	e.__KeyValueFromInt("disableshadows", 1);
	e.__KeyValueFromString("targetname", "pc_box");
	e.SetSize(Vector(0, 0, 0), Vector(a, b, c));
	PCboxes[id] <- e;
}

// ---- the final fight (sp_a4_finale4) ----
/// The pc_weye marker on Wheatley's eye (the model's "eyes" attachment), for the add-on to read.
::PCweye <- function () {
	local w = Entities.FindByClassname(null, "npc_wheatley_boss");
	if (w == null) return;
	local m = Entities.FindByName(null, "pc_weye");
	if (m == null) {
		m = Entities.CreateByClassname("info_target");
		m.__KeyValueFromString("targetname", "pc_weye");
	}
	local i = w.LookupAttachment("eyes");
	if (i > 0) m.SetOrigin(w.GetAttachmentOrigin(i));
}

// Saves made while Portalcraft runs carry the boxes: they remove themselves when such a save is loaded
// (Minecraft sends them again).
if (Entities.FindByName(null, "pc_cleanup") == null) {
	local la = Entities.CreateByClassname("logic_auto");
	la.__KeyValueFromString("targetname", "pc_cleanup");
	la.__KeyValueFromString("OnLoadGame", "pc_box,Kill,,0,-1");
}
// (at once: an EntFire Kill would land a frame later and take the boxes Minecraft sends right after this script)
for (local e = Entities.FindByName(null, "pc_box"); e != null; e = Entities.FindByName(null, "pc_box")) e.Destroy();
PCboxes = {};

// ---- Minecraft explosions: a real Portal 2 explosion (fireball, sound, shake) and a physics blast; no Portal 2
// damage to the player (Minecraft already hurt it, and its hits reach Portal 2) ----
::PCboom <- function (x, y, z, r, wind) {
	// a wind charge's burst only pushes (no fire, smoke or shake)
	local ex = wind ? null : Entities.CreateByClassname("env_explosion");
	if (ex != null) {
		ex.SetOrigin(Vector(x, y, z));
		ex.__KeyValueFromInt("iMagnitude", (r * 0.8).tointeger());
		ex.__KeyValueFromInt("iRadiusOverride", (r * 2.0).tointeger());
		ex.__KeyValueFromInt("spawnflags", 1); // no damage
		EntFireByHandle(ex, "Explode", "", 0, null, null);
		EntFireByHandle(ex, "Kill", "", 2.0, null, null);
	}
	local shake = wind ? null : Entities.CreateByClassname("env_shake");
	if (shake != null) {
		shake.SetOrigin(Vector(x, y, z));
		shake.__KeyValueFromFloat("amplitude", 8.0);
		shake.__KeyValueFromFloat("radius", r * 4.0);
		shake.__KeyValueFromFloat("duration", 0.8);
		shake.__KeyValueFromFloat("frequency", 120.0);
		EntFireByHandle(shake, "StartShake", "", 0, null, null);
		EntFireByHandle(shake, "Kill", "", 2.0, null, null);
	}
	// security cameras in the blast come off their walls (Ragdoll), then the blast throws them about
	local cams = 0;
	local cam = null;
	while ((cam = Entities.FindByClassnameWithin(cam, "npc_security_camera", Vector(x, y, z), r * 2.5)) != null) {
		EntFireByHandle(cam, "Ragdoll", "", 0, null, null);
		cams++;
	}
	if (cams > 0) printl("[Portalcraft] explosion knocked " + cams + " camera(s) off");
	local e = Entities.CreateByClassname("env_physexplosion");
	if (e == null) return;
	e.SetOrigin(Vector(x, y, z));
	e.__KeyValueFromInt("spawnflags", 1);
	e.__KeyValueFromFloat("magnitude", r * 4.0);
	e.__KeyValueFromFloat("radius", r * 2.0);
	EntFireByHandle(e, "Explode", "", cams > 0 ? 0.1 : 0, null, null);
	EntFireByHandle(e, "Kill", "", 0.5, null, null);
}

// ---- Goo Walker (Long Fall Boots): an invisible floor on the goo under the player, moved along with it ----
::PCgooFloor <- function (on, x, y, z) {
	local e = Entities.FindByName(null, "pc_goofloor");
	if (!on) {
		if (e != null) e.Destroy();
		return;
	}
	if (e == null) {
		e = CreateProp("prop_dynamic", Vector(x, y, z), PCboxModel, 0);
		if (e == null) return;
		e.__KeyValueFromInt("solid", 2);
		e.__KeyValueFromInt("rendermode", 10);
		e.__KeyValueFromInt("disableshadows", 1);
		e.__KeyValueFromString("targetname", "pc_goofloor");
		e.SetSize(Vector(-96, -96, -8), Vector(96, 96, 0));
	}
	e.SetOrigin(Vector(x, y, z));
}

// ---- a Minecraft projectile hit something: a small push away from where it hit ----
::PCnudge <- function (x, y, z, m) {
	local e = Entities.CreateByClassname("env_physexplosion");
	if (e == null) return;
	e.SetOrigin(Vector(x, y, z));
	e.__KeyValueFromInt("spawnflags", 1); // force only (no damage), players aren't pushed
	e.__KeyValueFromFloat("magnitude", m);
	e.__KeyValueFromFloat("radius", 72.0);
	EntFireByHandle(e, "Explode", "", 0, null, null);
	EntFireByHandle(e, "Kill", "", 0.2, null, null);
}

// ---- lasers: Minecraft sets the player on fire instead of Portal 2's laser burn (DMG_BURN, 8) ----
::PClaser <- function (on) {
	local f = Entities.FindByName(null, "pc_nolaserburn");
	if (f == null) {
		f = Entities.CreateByClassname("filter_damage_type");
		f.__KeyValueFromString("targetname", "pc_nolaserburn");
		f.__KeyValueFromInt("damagetype", 8);
		f.__KeyValueFromInt("Negated", 1);
	}
	EntFireByHandle(GetPlayer(), "SetDamageFilter", on ? "pc_nolaserburn" : "", 0, null, null);
}

// ---- Minecraft's spectator mode is noclip ----
::PCnoclip <- function (on) {
	if (GetPlayer().IsNoclipping() != on) SendToConsole("noclip");
}

// ---- Minecraft's knockback and health ----
::PCpush <- function (x, y, z) {
	local p = GetPlayer();
	p.SetVelocity(p.GetVelocity() + Vector(x, y, z));
}

::PChealth <- function (hp) {
	GetPlayer().SetHealth(hp);
}

// ---- creative flight ----
// While flying, the player's velocity is set every tick from the movement keys (the add-on sends them):
// Minecraft-like flight, and Portal 2's own movement still does the collision.
::PCfly <- { on = false, fwd = 0, side = 0, up = 0, speed = 350.0, think = null };

::PCflyInput <- function (fwd, side, up) {
	PCfly.fwd = fwd;
	PCfly.side = side;
	PCfly.up = up;
}

::PCflyTick <- function () {
	if (!PCfly.on) return;
	local p = GetPlayer();
	if (p == null) return;
	local f = p.GetForwardVector();
	f = Vector(f.x, f.y, 0);
	local len = f.Length();
	if (len > 0.001) f = f * (1.0 / len);
	local left = Vector(-f.y, f.x, 0);
	local want = (f * PCfly.fwd + left * PCfly.side);
	local wl = want.Length();
	if (wl > 1.0) want = want * (1.0 / wl);
	want = want * PCfly.speed + Vector(0, 0, PCfly.up * PCfly.speed * 0.8);
	// ease towards it, like Minecraft's flight drag (plus a little against gravity between ticks)
	local v = p.GetVelocity();
	v = v + (want - v) * 0.35;
	p.SetVelocity(v + Vector(0, 0, 600.0 * FrameTime()));
}

::PCflySet <- function (on) {
	PCfly.on = on;
	if (PCfly.think == null || !PCfly.think.IsValid()) {
		// a timer firing every tick runs PCflyTick (Portal 2's VScript has no think functions of its own)
		PCfly.think = Entities.CreateByClassname("logic_timer");
		PCfly.think.__KeyValueFromString("targetname", "pc_fly");
		PCfly.think.__KeyValueFromString("OnTimer", "!self,RunScriptCode,PCflyTick(),0,-1");
		EntFireByHandle(PCfly.think, "RefireTime", "0.01", 0, null, null);
		EntFireByHandle(PCfly.think, "Enable", "", 0, null, null);
	}
	if (!on) {
		local p = GetPlayer();
		local v = p.GetVelocity();
		p.SetVelocity(Vector(v.x * 0.5, v.y * 0.5, v.z < 0 ? v.z : 0));
	}
	printl("[Portalcraft] flight " + (on ? "on" : "off"));
}

// ---- Chell hidden while Minecraft's player stands in for her (portal views, F5: the add-on moves the camera) ----
::PChide <- function (on) {
	EntFireByHandle(GetPlayer(), on ? "DisableDraw" : "EnableDraw", "", 0, null, null);
}

// ---- testing elements placed from Minecraft (the add-on's elements.cpp): an emancipation grill (kind 0) or a laser
// field (1) is a box trigger, built as ppmod builds triggers - it has no brush, so the add-on's effect draws its field.
// Centre (x, y, z), half sizes (a, b, c) ----
::PCfield <- function (kind, n, x, y, z, a, b, c) {
	local t = Entities.CreateByClassname(kind == 0 ? "trigger_portal_cleanser" : "trigger_hurt");
	if (t == null) return;
	t.__KeyValueFromString("targetname", (kind == 0 ? "pc_el_emancipation_grill_" : "pc_el_laser_field_") + n);
	t.__KeyValueFromInt("solid", 3);
	t.SetOrigin(Vector(x, y, z));
	t.SetSize(Vector(-a, -b, -c), Vector(a, b, c));
	t.__KeyValueFromInt("CollisionGroup", 21);
	if (kind == 0) {
		t.__KeyValueFromInt("spawnflags", 4105); // the player (and its portals), physics objects - as the stock grills
		t.__KeyValueFromInt("Visible", 0);
	} else {
		t.__KeyValueFromInt("spawnflags", 3); // the player and NPCs (turrets)
		t.__KeyValueFromFloat("damage", 200.0);
		t.__KeyValueFromInt("damagetype", 1024); // DMG_ENERGYBEAM
		t.__KeyValueFromInt("nodmgforce", 1);
	}
	EntFireByHandle(t, "Enable", "", 0, null, null);
	printl("[Portalcraft] field " + n + (kind == 0 ? " (emancipation grill)" : " (laser field)"));
}

// ---- Portalwhip: what the portal gun hits goes as if through an emancipation grill - a grill around it for a moment ----
::PCzap <- function (x, y, z, a, b, c) {
	local t = Entities.CreateByClassname("trigger_portal_cleanser");
	if (t == null) return;
	t.__KeyValueFromString("targetname", "pc_zap");
	t.__KeyValueFromInt("solid", 3);
	t.SetOrigin(Vector(x, y, z));
	t.SetSize(Vector(-a, -b, -c), Vector(a, b, c));
	t.__KeyValueFromInt("CollisionGroup", 21);
	t.__KeyValueFromInt("spawnflags", 4104); // physics objects (not the player: its portals stay open)
	t.__KeyValueFromInt("Visible", 0);
	// (off and on again: a trigger coming on touches what is already inside it)
	EntFireByHandle(t, "Disable", "", 0, null, null);
	EntFireByHandle(t, "Enable", "", 0.03, null, null);
	EntFireByHandle(t, "Kill", "", 0.6, null, null);
}

printl("[Portalcraft] ready");
