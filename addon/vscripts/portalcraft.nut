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
// with no hitboxes makes them stop at the box. Only where it is precached, though: a prop made with a model that isn't
// is an "Engine Error" that ends Portal 2. The add-on precaches it with a prop of its own, pc_precache, which it leaves
// in the level - where that prop is, the model is precached (a save brings both back). A variable set once isn't
// enough: a save brings this script's variables back too, and the precache with them only if the prop came along -
// box lines still queued from before a load ran in the new level with the old setting (sp_a2_laser_over_goo).
::PCboxModel <- function () {
	return Entities.FindByName(null, "pc_precache") != null ? "models/props_office/paper_single.mdl" : "models/player/chell/player.mdl";
}
::PCboxHitboxFree <- function (on) {} // (older add-ons switched to the model with this)

/// A box with its min corner at (x, y, z) and size (a, b, c), all in units.
::PCbox <- function (id, x, y, z, a, b, c) {
	PCdel(id);
	local e = CreateProp("prop_dynamic", Vector(x, y, z), PCboxModel(), 0);
	if (e == null) return;
	e.__KeyValueFromInt("solid", 2);
	e.__KeyValueFromInt("rendermode", 10);
	e.__KeyValueFromInt("disableshadows", 1);
	e.__KeyValueFromString("targetname", "pc_box");
	e.SetSize(Vector(0, 0, 0), Vector(a, b, c));
	PCboxes[id] <- e;
}

// ---- Minecraft's own worlds (sp_mc_overworld, sp_mc_nether, ...): their boxes are used again ----
// Every entity a script gets a handle to gets a script id: a string Portal 2 keeps in its game string pool until the
// level unloads, and the pool holds 65535 ("Engine Error: CUtlRBTree overflow!"). The overworld's land comes and goes
// with every step (and every block broken sends a chunk's boxes again), so there a box that goes is parked - no size,
// out of the way, named pc_boxspare - and the next box takes it: new entities only for more boxes at once than ever.
::PCspare <- [];

::PCdelS <- function (id) {
	if (!(id in PCboxes)) return;
	local e = PCboxes[id];
	delete PCboxes[id];
	if (e == null || !e.IsValid()) return;
	e.SetSize(Vector(0, 0, 0), Vector(0, 0, 0));
	e.SetOrigin(Vector(0, 0, -15000));
	e.__KeyValueFromString("targetname", "pc_boxspare");
	PCspare.append(e);
}

::PCboxS <- function (id, x, y, z, a, b, c) {
	PCdelS(id);
	local e = null;
	while (e == null && PCspare.len() > 0) {
		local s = PCspare.pop();
		if (s != null && s.IsValid()) e = s;
	}
	if (e == null) {
		e = CreateProp("prop_dynamic", Vector(x, y, z), PCboxModel(), 0);
		if (e == null) return;
		e.__KeyValueFromInt("solid", 2);
		e.__KeyValueFromInt("rendermode", 10);
		e.__KeyValueFromInt("disableshadows", 1);
	}
	e.__KeyValueFromString("targetname", "pc_box");
	e.SetOrigin(Vector(x, y, z));
	e.SetSize(Vector(0, 0, 0), Vector(a, b, c));
	PCboxes[id] <- e;
}

/// Every box goes (Minecraft sends them all again) - parked, by name too (ones the table lost).
::PCboxClearS <- function () {
	local list = [];
	foreach (id, e in PCboxes) list.append(id);
	foreach (id in list) PCdelS(id);
	list = [];
	for (local e = Entities.FindByName(null, "pc_box"); e != null; e = Entities.FindByName(e, "pc_box")) list.append(e);
	foreach (e in list) {
		e.SetSize(Vector(0, 0, 0), Vector(0, 0, 0));
		e.SetOrigin(Vector(0, 0, -15000));
		e.__KeyValueFromString("targetname", "pc_boxspare");
		PCspare.append(e);
	}
	::PCboxes <- {};
}

// ---- Minecraft's own worlds have no end, this map does: it follows the player (Minecraft's Origin) ----
/// Portal 2's 0, 0 moved under the player: everything here moves (dx, dy) units with it, in this one tick - the land's
/// boxes, the player (unless Minecraft places it: riding), the loose things and what was placed from Minecraft (pc_el_*).
/// (The open portals are moved by the add-on: a script here can't find an entity by its index.)
// (Portal 2's Squirrel has no closures over locals: a nested function can't see d - so plain functions, d passed in)
::PCshiftInside <- function (o) {
	return fabs(o.x) < 15000 && fabs(o.y) < 15000;
}

::PCshiftOne <- function (e, d) {
	if (e == null || !e.IsValid() || e.GetMoveParent() != null) return;
	local o = e.GetOrigin() + d;
	if (!PCshiftInside(o)) return;
	local v = e.GetVelocity();
	e.SetOrigin(o);
	e.SetVelocity(v);
}

::PCshift <- function (dx, dy, player) {
	local d = Vector(dx, dy, 0);
	foreach (id, e in PCboxes) if (e != null && e.IsValid()) e.SetOrigin(e.GetOrigin() + d);
	if (player) PCshiftOne(GetPlayer(), d);
	foreach (cls in ["prop_weighted_cube", "prop_monster_box", "prop_physics", "prop_physics_override", "npc_portal_turret_floor",
		"npc_personality_core", "prop_glass_futbol", "prop_exploding_futbol", "prop_paint_bomb"]) {
		for (local e = Entities.FindByClassname(null, cls); e != null; e = Entities.FindByClassname(e, cls)) PCshiftOne(e, d);
	}
	local placed = [];
	for (local e = Entities.FindByName(null, "pc_el_*"); e != null; e = Entities.FindByName(e, "pc_el_*")) placed.append(e);
	foreach (e in placed) PCshiftOne(e, d);
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
for (local e = Entities.FindByName(null, "pc_boxspare"); e != null; e = Entities.FindByName(null, "pc_boxspare")) e.Destroy();
PCboxes = {};
PCspare = [];

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
		e = CreateProp("prop_dynamic", Vector(x, y, z), PCboxModel(), 0);
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

// ---- cl_show_mcstandin (debugging): the invisible boxes standing in for Minecraft's blocks, drawn near the player a few
// times a second (debug overlay boxes, seen through everything): green the blocks' boxes, yellow the laser twins of
// blocks beside a beam, blue the floors over goo ----
::PCstandin <- { timer = null };

::PCstandinTick <- function () {
	local p = GetPlayer();
	if (p == null) return;
	local at = p.GetOrigin();
	local n = 0;
	foreach (kind in [["pc_box", 80, 255, 80], ["pc_lbox", 255, 220, 40], ["pc_goofloor", 80, 160, 255]]) {
		for (local e = Entities.FindByNameWithin(null, kind[0], at, 768); e != null && n < 800; e = Entities.FindByNameWithin(e, kind[0], at, 768)) {
			DebugDrawBox(e.GetOrigin(), e.GetBoundingMins(), e.GetBoundingMaxs(), kind[1], kind[2], kind[3], 0, 0.3);
			n++;
		}
	}
}

::PCstandinShow <- function (on) {
	if (PCstandin.timer == null || !PCstandin.timer.IsValid()) {
		PCstandin.timer = Entities.FindByName(null, "pc_standin");
		if (PCstandin.timer == null) {
			PCstandin.timer = Entities.CreateByClassname("logic_timer");
			PCstandin.timer.__KeyValueFromString("targetname", "pc_standin");
			PCstandin.timer.__KeyValueFromString("OnTimer", "!self,RunScriptCode,PCstandinTick(),0,-1");
			EntFireByHandle(PCstandin.timer, "RefireTime", "0.25", 0, null, null);
		}
	}
	EntFireByHandle(PCstandin.timer, on ? "Enable" : "Disable", "", 0, null, null);
	printl("[Portalcraft] stand-ins " + (on ? "shown" : "hidden"));
}

printl("[Portalcraft] ready");
