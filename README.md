# Portalcraft: Minecraft inside Portal 2

Real Minecraft Java 26.3 runs next to Portal 2, follows Portal 2's camera, and is drawn into every Portal 2 frame with
depth: Minecraft blocks and mobs stand on Portal 2's floors, hide behind its walls and stay put while you move. Build
with Minecraft blocks (Portal 2's player collides with them), fight Minecraft mobs (in survival their hits come out of
Portal 2's health), and keep using the portal gun. You are Minecraft's player: its size, and it moves the way
Minecraft's does. Single player only.

**To play, download the release zip** (Releases, on the right of the GitHub page), not the source code: unzip it
anywhere and follow *Install* below. It has the built mod, the add-on and ReShade in it; the source code alone has to be
built first (see *Building from source*).

## How it works (short)
- **Portal 2 side:** ReShade 6.8 (add-on build) loads `portalcraft.addon32`. It hooks Portal 2's camera every frame
  (`ClientModeShared::OverrideView`), picks the exact camera of the frame on screen from the shader constants, routes
  input, and draws Minecraft's picture *into* Portal 2's frame (`PortalcraftEarly.hlsl`: colour and depth written
  before Portal 2 draws its world, re-projected to Portal 2's camera), so Portal 2's own drawing lands on top where it
  should; `Portalcraft.fx` adds Minecraft's translucent bits and hand/HUD. Minecraft blocks become invisible solid
  boxes in Portal 2 (VScript props), and Portal 2's floors and lasers are traced and sent to Minecraft. Portal 2's
  player movement (`IGameMovement::ProcessMovement`) runs Minecraft's movement rules 20 times a second while Portal 2
  keeps doing the collision, portals and faith plates (`addon/src/movement.cpp`).
- **Minecraft side:** the Fabric mod renders from Portal 2's camera with no sky or fog, exports colour, depth and the
  hand/HUD layer, turns each Portal 2 map (`.bsp`) into invisible barrier blocks in its own region of a void world, and
  bridges health.
- They talk through shared memory on your PC (`Local\PortalcraftLink`); nothing goes over the network.
- The whole design, the problems met building it and how they were solved: `P2-MC_DESIGN.md`.

## Install (once)
You need Windows, Portal 2 on Steam, and Minecraft: Java Edition (an account that owns it). Pick the launcher you use
for mods.

**Modrinth App (recommended):**
1. In the Modrinth App: **+ Create instance** → name **Portalcraft**, Loader **Fabric**, Game version **26.3** → Create.
2. Double-click **`Install-Portalcraft-Modrinth.bat`**. It copies the Portalcraft mod into that instance's `mods`
   folder, plus Fabric API if the instance doesn't have it (from Fabric's official Maven, checksum-verified).
   Run it again after the mod is rebuilt.

Either installer (and the first Play) also copies Portal 2's saves, once, to
`Documents\Portal 2 saves (backup before Portalcraft)`, with a README.txt on how to put them back. Portalcraft never
touches that copy again; removing Portalcraft leaves it there.

**Official Minecraft Launcher:**
1. Close the Minecraft Launcher.
2. Double-click **`Install-Portalcraft.bat`**. It adds a **Portalcraft** installation (Fabric Loader 0.19.5 for 26.3)
   with its own game folder `%APPDATA%\.portalcraft` (its own world and options; your normal worlds aren't touched)
   and puts the mod and Fabric API in its `mods` folder. `launcher_profiles.json` is backed up first.
   `Install-Portalcraft.ps1 -Uninstall` removes it again.

## Play
1. Make sure Steam is running.
2. Double-click **`Play-Portalcraft.bat`**.
3. The Modrinth App opens (or, without a Modrinth Portalcraft instance, the Minecraft Launcher): press **Play** on
   **Portalcraft**. (Official launcher: it warns that the installation is modified, press **Play** again. First
   start only: click through Minecraft's accessibility screen.) Minecraft stops at its title screen, which says
   **Waiting for Portal 2** under its buttons. If it doesn't say that, the mod didn't load: check the instance's
   `mods` folder has both jars.
4. Portal 2 starts by itself once Minecraft is up, and Minecraft then opens its Portalcraft world on its own (it
   waits for Portal 2 so that it never takes the mouse: there is nothing to click in its window). Load a save or
   start a chapter as usual. Minecraft's window hides while Portal 2 runs.
5. Quit Portal 2 normally when you're done. Minecraft saves and quits, and ReShade is taken back out of Portal 2's
   folder. Leave the black Play window open until then.

Options: `Play-Portalcraft.bat -Map sp_a1_intro3` (straight into a map), `-Windowed` (borderless window), `-Vulkan`
(Portal 2 on Vulkan, see below).

**Vulkan** works on both sides, and can be faster on some PCs:
- *Portal 2*: with `-vulkan` in its launch options (Steam > Portal 2 > Properties), or `Play-Portalcraft.bat -Vulkan`,
  Portal 2 draws through its own DXVK. For those sessions Play puts ReShade in front of DXVK instead (Portal 2's
  `bin\dxvk_d3d9.dll` waits next to it as `dxvk_d3d9.portalcraft-original.dll`, and is put back when Portal 2 closes).
- *Minecraft*: Options > Video Settings > Graphics API: Vulkan (restart Minecraft). Nothing else to do.

If something goes wrong, the window stays open with the reason, and the full log is in `logs\play.log` (or
`logs\install.log`). Use the `.bat` files: on most PCs `.ps1` files open in Notepad, and "Run with PowerShell" closes
its window before you can read an error. If the Play window was closed while waiting, ReShade may still be in
Portal 2's folder: `powershell -ExecutionPolicy Bypass -File tools\portalcraft.ps1 remove` takes it out.

Portal 2 is started with `-insecure` (VAC off), `-novid` and `+sv_cheats 1` (needed for Minecraft damage to reach
Portal 2). With cheats on, Portal 2's Steam achievements don't unlock in these sessions. Don't use it in co-op.

**Nothing happens in Portal 2** (no ReShade line at the top of the screen as it starts, Tab does nothing, Minecraft's
window stays open next to it): Portal 2 didn't load ReShade, so Portalcraft's half never started. Once Portal 2 is
running, the Play window says why (or that "Portalcraft is on"). The usual causes:
- another `d3d9.dll` next to `portal2.exe` (another ReShade, DXVK...): Portal 2 loads that one instead. Play stops and
  says so; move it out while you play Portalcraft.
- Windows 11's **Smart App Control** turned on: it blocks unsigned DLLs Windows doesn't know, and ReShade's and
  Portalcraft's are unsigned. Play warns when it is on. It's in Windows Security > App & browser control; Windows
  doesn't let you turn it back on without reinstalling, so decide for yourself.
- an antivirus blocking or removing `bin\d3d9.dll` (ReShade; `bin\dxvk_d3d9.dll` with `-vulkan`): allow it.
- Portal 2 started some other way than by the Play window (from Steam, a shortcut, or after Play stopped with an
  error): ReShade is only in Portal 2's folder while the Play window runs.
- something running as administrator: run the Play window, the Modrinth App and Steam normally.

**"Portalcraft is off"**: the two halves check each other when they connect, and stay off rather than misbehave.
- *Different builds*: the Portal 2 add-on (in this folder) and the Minecraft mod (in the instance) come from different
  Portalcraft packages. Portal 2 shows it in the middle of the screen, Minecraft as a pop-up and a chat line. Run the
  installer from the same package again, so both match.
- *Another Portal 2 build*: Portalcraft hooks into Portal 2's own code, so it only switches on in the Portal 2 build
  it was made for (Steam's 2026-09-08 update). In any other build Portal 2 plays as usual and Minecraft tells you why
  (the details are in `runtime\ReShade.log`). To try anyway, add `-pc_anybuild` to Portal 2's launch options (Steam >
  Portal 2 > Properties > Launch options); take it out again if Portal 2 crashes.

## Controls: two modes that take turns
**Tab** switches between them (change it in Minecraft: Options > Controls > Key Binds > Portalcraft). Both games
start in Portal mode.

| | Portal mode | Minecraft mode |
|---|---|---|
| What you hold | the portal gun | Minecraft's hand and items (portal gun, crosshair and portal indicator hidden) |
| HUD | Portal 2's only | Minecraft's hotbar, hearts and crosshair |
| Left click | blue portal | attack / break; **on a cube, button, turret… (or while carrying something): Portal 2's use** |
| Right click | orange portal | use / place |
| Middle click, wheel, 1–9 | Portal 2's own | pick block, hotbar |
| **E** | Portal 2 use | inventory |
| **Q / F / T / /** | Portal 2's own | drop / swap hands / chat / command |
| **F5** | Portal 2's screenshot | Minecraft's F5: behind you, then in front of you, then back to first person |
| **Esc** | Portal 2's menu (pauses Minecraft too) | **Minecraft's pause menu** (pauses Portal 2 too) |

**In Minecraft mode, moving is Minecraft's** (the "Minecraft movement" option, on by default), with Minecraft's keys.
Portal mode moves you like Chell (her size, speed and Portal 2's physics), so puzzles play as in Portal 2.

| Key | Does |
|---|---|
| **W A S D** | walk (4.3 blocks/s) |
| **Ctrl**, or **W twice** | sprint (5.6 blocks/s; stops when you let go of W, run into a wall or get hungry) |
| **Shift** | sneak (1.3 blocks/s; you stop at edges instead of falling off) |
| **Space** | jump (1.25 blocks high); held, you keep jumping like in Minecraft |
| **Space twice** (creative) | fly: Space up, Shift down, Ctrl faster; landing ends it |

Speed and jump effects, ice and soul sand work as in Minecraft. You're Minecraft's size (1.8 blocks tall, eyes at
1.62, 1.5 sneaking), and the view bobs and widens when you sprint (Minecraft's own View Bobbing and FOV Effects options
turn that off). Faith plates, portals and Portal 2 launches still throw you Portal 2's way, so puzzles land where they
should; Minecraft's rules take over again when you land. Blue (repulsion) gel bounces you Portal 2's way too. Mob hits,
explosions and wind charges knock you back the Minecraft way; cobwebs, berry bushes and powder snow hold you back, a
spyglass zooms, and gliding with an elytra lowers your view like Minecraft's. With an elytra on, **Space in mid-air in
Portal mode** switches to Minecraft mode and glides straight away, so a faith plate's throw turns into a glide in one
press. With the option off you are Chell in both modes (her size and movement; Ctrl crouches).

While a Minecraft screen is open (inventory, chat, chest, pause menu), everything goes to Minecraft and a cursor is
drawn.

**Spectator** (`/gamemode spectator`, with "spectator = noclip" on): you fly through Portal 2's walls with its noclip,
and the mouse wheel sets the flying speed as in Minecraft, in both modes (in Portal mode Portal 2's own binds on the
wheel don't fire while it turns).

**Minecraft Control Takeover** (Portalcraft... > Crossovers > Controls, off by default): for people whose Portal 2 binds
clash with Minecraft's. A key bound to one of Minecraft's other controls (a mod's zoom key, advancements on L, the
creative hotbar keys on C and X...) goes to Minecraft in both modes, never to Portal 2's bind for the same key.
Moving, jumping, sneaking, sprinting, the mouse, the hotbar, inventory, chat and Minecraft's screenshot, fullscreen,
hide-HUD (F1) and camera keys stay as above. To give a key back to Portal 2, unbind it in Minecraft's Controls.

**MC Caption Mode** (Portalcraft..., off by default): with Portal 2's subtitles on, what its characters say goes to
Minecraft's chat instead of Portal 2's caption box, in their colours (Wheatley's blue, GLaDOS's green...), and fades
when Portal 2's caption would: as the line ends. Captions of sounds ([Clock Ticking]) stay Portal 2's. While it's on,
the chat shows in Portal mode too. In cutscenes, or with Minecraft's HUD (F1) or chat hidden, Portal 2 shows its
lines as ever.

**Minecraft's pause menu has a Portalcraft... button**: pick what crosses between the games (Minecraft movement,
Minecraft HUD in Portal mode, Minecraft healing, Minecraft hurts Chell, knockback, solid blocks, lasers, explosions, spectator = noclip, pause
together, through portals, fresh blocks each map), a **Clear this map's blocks** button, and **Clear all maps...**
(asks first): every Minecraft block, mob and item in all of Portal 2's maps goes, for a fresh run. Your inventory and
Minecraft's own world stay.

**Survival**: Portalcraft's world starts in survival, as Minecraft's own new worlds do, and the first time you're in
it you get the Aperture Science Survival Kit (an oak sapling, bones, Long Fall Boots and the Survival Guide). Worlds
made by older versions started in creative; `/gamemode survival` switches (and `/gamemode creative` back). One health
for both games, 1 heart = 10 Portal 2 health. With Minecraft healing on (default), Minecraft decides: Portal 2 stops
regenerating, its damage (lasers, turrets: as deadly as in Portal 2) comes off your hearts, and you heal like in
Minecraft: with Infinite saturation (on by default) you never get hungry, so you heal by yourself; with it off, you
eat. Mob hits knock you back. Dying in one game kills you in the other.

**Crossovers** (most can be switched off in the **Portalcraft...** menus of Minecraft's pause screen):
- *Building and mining:* Minecraft blocks are solid in Portal 2 (for you, cubes and lasers), and light bridges and
  funnels stop at them as at a wall (a portal on a block takes them on). Mining Portal 2's world
  gives Minecraft items: dirt, metal (copper down in Old Aperture), redstone from buttons and doors, torches from light
  bridges, gel potions from painted surfaces. Plants grow on Portal 2's dirt.
- *Digging into Portal 2 (off by default):* switch on "Real Mining Portal 2" (Portalcraft... > Crossovers;
  it switches "Mining Portal 2" on with it) and a pickaxe digs real holes into Portal 2's walls, floors and ceilings. The block drops what its surface is made of,
  the blocks around show what the map has there (white concrete under white panels, deepslate deeper in) and mine like
  Minecraft blocks, and you can tunnel, fall in, and break back out into a chamber from behind. Holes refill when the
  map starts fresh, and all of them when the option goes off; balance mode switches it off. Cubes,
  turrets and other physics objects fall into holes too, and Portal 2's lasers, funnels, grills, effects and
  captions stay on top of a hole. A hole through a thin wall shows what Portal 2 has behind it (the next room), except
  where Minecraft has a block there: a cell holding part of a Portal 2 surface turns to deepslate when it's uncovered,
  and mining it opens the view. Known issue: an object sunk all the way into a hole is hidden (Portal 2 doesn't draw
  things inside its walls).
- *White and black panels:* Portal 2's own wall panels as blocks (4 from 4 concrete of their colour in a square, or one
  from one on a stonecutter, and back to concrete the same way). Portal 2 draws its own white or black panel texture,
  from your Portal 2 install, on every face of them that shows, lit by Portal 2's light around them. A panel filling
  in a dug-out hole of its own colour becomes the wall it was cut from (the map's texture, alignment and lightmap
  there), so the hole is simply gone. A panel anywhere else takes the look of the last panel of its colour you filled
  in (walls and floors keep one each), or, before you've filled any in on this map, the nearest map surface of its
  colour; with no such surface nearby it's Portal 2's chamber panels (one panel covers 2 by 2 blocks, lined up with the
  world, floor tiles on top faces). Underneath they are white and black concrete, so they look like that if Portal 2
  can't draw them.
- *Panel stairs and slabs:* white and black, crafted like stone's (6 panels make 4 stairs, 3 make 6 slabs, or 1 makes
  1 stair or 2 slabs on a stonecutter). Portal 2 draws them in its panels too, with every face of one block that
  points the same way looking the same. White ones take portals only on whole block faces: a top slab's top, a double
  slab, a stair's back or bottom. A step or a bottom slab's top fizzles the shot.
- *Portalable blocks:* Portal 2's gun puts portals on white panels (and their stairs and slabs), white concrete and white concrete powder, as on its
  own white walls (black panels and every other block refuse them, like Portal 2's black walls). The face needs room
  for a whole portal, and breaking a block under a portal fizzles it.
- *Heal* (a Potion of Healing in the middle of the grid, white concrete or white panels above it and to its left, black
  concrete or black panels to its right and below it): with Real Mining on, it puts back the dug-out terrain you aim
  at, as it was; crouch while using it to put back all the terrain dug out of the map. Crafting it with another Potion
  of Healing makes it put back a bigger square each time, up to 5 by 5 blocks (its tooltip shows the area). Cells
  that would shut you inside the rock or take the floor from under you stay dug: step out of the hole first. With
  nothing dug, or Real Mining off, it heals 5 hearts. One is used up each time in survival.
- *Portal 2 things in Minecraft:* punch a cube (or sneak and punch a turret) to put it in your inventory and place it
  again elsewhere; everything Portalcraft adds is in its own tab of the creative inventory;
  personality cores and the portal gun can be crafted; Minecraft's portal gun item fires Portal 2's portals, and up
  close it's a sword: a mob or a Minecraft block in reach gets hit or mined instead (an iron sword's damage, sweeping
  hits, sword enchantments; it never wears out); the Aperture Science Handheld Electrical Synthesizer makes any item
  from concrete and redstone. The portal gun item glows the colour of the last portal Portal 2's gun really placed
  (a shot that fizzles on a black wall doesn't change it).
- *Minecraft portal gun (off by default; Portalcraft... > Crossovers, under Looks):* Portal 2's portal gun looks like
  Minecraft's portal gun item, as in the ending. In Portal mode your Minecraft hand holds the item instead of Portal 2's
  gun and swings when it fires; the guns lying in the chambers (on the pedestal in Portal Gun, sp_a1_intro3, and the
  one that falls into the incinerator in The Cold Boot, sp_a2_intro) are dropped items that bob and spin; and in the
  ending, with Ending Arms, your arms pick up and hold the item. It's only looks: the gun works as always. PotatOS is
  part of Portal 2's gun model, so she isn't shown while the item is in your hand.
- *Testing elements:* craft Portal 2's own (recipes below) and use one on a Portal 2 surface to put it there, switched
  on: laser emitters, blue and orange portal emitters (the first blue opens onto the first orange, and so on), hard
  light bridges, excursion funnels and reverse funnels, sentry turrets, emancipation grills and laser fields (from wall
  to wall across a passage, up to 4 blocks high; Minecraft items dropped through any grill fizzle away). They stay, in Portal 2's saves too, until the **Aperture Science
  Remover Stick** takes them away. It takes the map's own testing elements as well; yours come back into your
  inventory.
- *The A.S.M.B.U.T.S.* (Aperture Science Modified Bundle with Unrestricted Temporal Storage): use it on one of Portal
  2's loose objects (security cameras, bottles, any loose prop) to store it whole, up to 6 of them; use it anywhere
  else, or sneak, to put the top one back where you're looking. Hover it in your inventory to see what's inside (a
  little picture of each, taken as it went in); scroll to pick one and click the A.S.M.B.U.T.S. to bring it to the top.
  It won't take what you can already carry (cubes, turrets), characters like Wheatley, or anything the map's own logic
  uses (a prop wired to a button, attached to something, or that the map moves itself).
- *Gels:* bounce and speed gel work on you; a glass bottle fills from falling gel (repulsion = Leaping II, propulsion =
  Speed, conversion = Portal Master: portals go anywhere, after a little nausea; cleansing gel = water). An **Arrow of
  Portaling** (tipped with Portal Master) gives whatever it hits the infinite fall: once it has landed from the hit,
  your blue portal opens under it and the orange one above it.
- *Tech:* redstone opens doors and switches lasers, funnels, bridges; beacon beams power laser catchers; Portal 2's
  lasers burn mobs and light TNT; turrets shoot Minecraft's mobs and catch fire in Minecraft's fire, and the mobs
  they shoot fight back (passive ones run): their hits knock the turret about, and an iron golem flings it across the
  room; Minecraft explosions shove cubes and turrets and break Wheatley's monitors.
- *Glass relays lasers (off by default; Portalcraft... > Crossovers):* a laser that hits a glass block (plain or
  stained) comes out of it again like out of a reflector cube, in the direction you faced when you placed the block
  (glass that got there any other way passes it straight on). Tinted glass just blocks it. Two blocks aimed at each
  other only stay lit while a real laser feeds them.
- *Portals:* Minecraft is drawn through Portal 2's portals (you see yourself), and mobs, items, arrows, TNT and ender
  pearls go through them with their momentum. Mobs, items and other blocky things cross smoothly: part-way through, they
  stick out of the other portal, and they switch sides once their middle is across (an idea from Immersive Portals).
  Mobs chasing you walk through them when that's the way to you. Ender pearls that fall into a death pit vanish instead of landing you
  in it.
- *Your player* (skin, armour, cape, elytra), seen in third person (F5, in Minecraft mode) or through a portal, is drawn
  by Portal 2 itself from a copy Minecraft keeps, so it stays put when the camera moves fast instead of lagging behind
  or slicing ("Your player drawn by Portal 2", Portalcraft... > Crossovers, on by default). Held items and trimmed
  armour still come from Minecraft's picture. You only see yourself through portals that face each other across a
  room: two portals on the same wall can't show you.
- *Water and goo:* Minecraft water and lava flow over Portal 2's floors; you swim in them in either mode (Portal mode
  swims Minecraft's way while you're in deeper than your knees), with their fog. Flowing water
  carries cubes, turrets and Portal 2's other loose things along with it. Optionally Portal 2's goo is water too: you
  swim in it, and fish and squids live in it.
- *Light:* Minecraft's torches, lanterns, fire, lava and glowstone light up Portal 2's surfaces around them (Portal 2's
  own lighting is baked into its maps, so this is an extra pass: no shadows), and the three nearest shine real Portal 2
  light into dark places ("Torches light Portal 2", Portalcraft... > Crossover). ReShade's overlay (Ctrl+F12) has
  "Minecraft light sources on Portal 2" to set the glow's strength.
- *Shields:* a shield raised towards a turret takes its bullets, and wears like any shield.
- *Survival extras:* starter kit (sapling, 5 bones, Long Fall Boots), fall damage without the boots, armour reduces
  Portal 2 damage, a level of XP per test chamber, optional infinite food, and the final boss: mobs, arrows and TNT
  hurt Wheatley while he is open to a bomb, and his bombs hurt mobs. Saying "yes" in chat answers Wheatley in the
  first chapter.
- *Mob spawning (off by default; Portalcraft... > Crossovers, under Survival):* Minecraft's monsters come out in the
  chambers at night, and always in Old Aperture: up to 5 at a time, within 20 blocks of you, only on floors you could
  walk to from where you stand (never inside walls, behind glass, in pits or out of bounds). Time passes while it's on,
  and you get a clock to tell it by; switching it off takes the clock back and makes it noon again. The chambers stay
  lit as at noon either way.
- *Balance* (Portalcraft... > Balance..., each rule on its own or all at once, all off by default): blocks and buckets
  only on portalable (white) surfaces (white panels and white concrete count), or on your own blocks with a portalable
  surface within a block of the new one;
  no cube copies; three hits for each of Wheatley's phases; ender pearls fizzle in grills; and **Saves rewind Minecraft**: when Portal 2 loads a save (dying,
  a quickload, `load a` for a `save a`), Minecraft goes back to that save too - blocks placed and broken since, your
  inventory, XP, health, hunger and effects, and mobs and items that came since (mobs killed since stay gone; chests
  keep what was taken out). Each save file keeps its own point (the last 10), so loading an older save goes back to
  that one. A save of another map brings back your inventory, and that map's blocks too unless they were cleared since
  (fresh blocks each map).
- *No portal gun mode:* play without it (it comes back for the very last shot). Chambers that can't be done without
  a portal get a Minecraft way through: punch the glass in the first test chambers, take the double helping from a
  "miswired" reflection cube dropper, and Wheatley finds his own way to get you across.
- *Enchantments* (enchanting table, villagers, loot): Long Fall Boots take Protection (I–IV, like any boots) and
  **Goo Walker** (walk on goo as if it were ground); the portal gun takes the sword enchantments,
  **Portalwhip I–II** (hitting a mob does more damage; hitting a cube or turret fizzles it away, as an emancipation
  grill would) and **Glasscutter** (portals go on glass); the synthesizer takes Efficiency I–III (a material costs down
  to 2 instead of 5) and **Buy 1 Get 1 I–III** (20/35/50% chance of a free extra); the cube item takes **Polish** (it's
  placed as a reflector cube); the A.S.M.B.U.T.S. takes **Holding I–III** (12/18/24 objects).
- *Riding:* boats, minecarts and rideable mobs carry you (WASD steers, crouch gets off); Portal 2's walls stop them.

**Recipes unlock as you go through the campaign.** The cores, the synthesizer, the A.S.M.B.U.T.S. and Long Fall
Boots can be crafted from the start; each testing element can be crafted once Portal 2 reaches the map where it first
turns up (or any map after it). Chat says which recipes are new. A recipe that isn't unlocked yet gives nothing in the
crafting grid, and a Crafter block won't make it either.

| Unlocked at | Recipes |
|---|---|
| Container Ride (sp_a1_intro1) | Blue and Orange Portal Emitters |
| Portal Gun (sp_a1_intro3) | Portal Gun |
| Laser Intro (sp_a2_laser_intro) | Laser Emitter |
| Fizzler Intro (sp_a2_fizzler_intro) | Material Emancipation Grill, Aperture Science Remover Stick |
| Bridge Intro (sp_a2_bridge_intro) | Hard Light Bridge |
| Turret Intro (sp_a2_turret_intro) | Sentry Turret (and the redstone one) |
| Funnel Intro (sp_a4_tb_intro) | Excursion Funnel |
| Polarity (sp_a4_tb_polarity) | Reverse Excursion Funnel |
| Laser Platform (sp_a4_laser_platform) | Laser Field |

Maps outside the campaign (Minecraft's world, workshop maps) unlock nothing new, and a world keeps what it has
unlocked.

**Testing element recipes** (crafting table, top row first; "-" is an empty slot):

| Item | Recipe |
|---|---|
| Laser Emitter | iron block, glass, iron block / iron block, redstone block, iron block / iron block, redstone lamp, iron block |
| Blue Portal Emitter | iron block, ender pearl, iron block / iron block, blue concrete, iron block (two rows) |
| Orange Portal Emitter | iron block, ender pearl, iron block / iron block, orange concrete, iron block (two rows) |
| Hard Light Bridge | torch x3 / torch x3 / iron ingot, redstone dust, iron ingot |
| Excursion Funnel | iron ingot, *slow falling*, iron ingot / iron ingot, dispenser, iron ingot / iron block, blue dye, iron block |
| Reverse Excursion Funnel | as the funnel, with orange dye |
| Sentry Turret | iron ingot x3 / iron ingot, red stained glass, iron ingot / iron ingot, bow, iron ingot |
| Material Emancipation Grill | iron ingot, torch, iron ingot / cactus, flint and steel, cactus / iron ingot, torch, iron ingot |
| Laser Field | iron ingot, torch, iron ingot / redstone dust, lava bucket, redstone dust / iron ingot, torch, iron ingot |
| Aperture Science Remover Stick | stick, redstone dust and an emancipation grill, anywhere in the grid |
| A.S.M.B.U.T.S. | an empty white bundle, any cube and a slime ball, anywhere in the grid |
| Long Fall Boots | - / iron ingot, iron boots, iron ingot / slime ball, -, slime ball |

*Slow falling*: a potion of Slow Falling (any kind) or a Feather Falling enchanted book.

## Minecraft's world
Minecraft's pause menu > **Portalcraft...** > **Minecraft's world** takes Portal 2 to `sp_mc_overworld`, a map that is
Minecraft's own generated land: hills, forests, lakes, its sky. Portal 2's game is saved first (`pc_before_overworld`),
and **Back to the test chambers** (same button) loads it again: the same chamber, the same place. (Portal 2's console
works too: `map sp_mc_overworld`.) Once you've finished Portal 2, its main menu's **Extras** has it as well: **Minecraft:
The Overworld**, at the bottom of the list, goes straight there.
- Both modes work there as everywhere: Portal mode moves you like Chell (a one-block step needs a jump), Minecraft mode
  like Minecraft. Cubes land on the ground 32 to 48 blocks around you; one left lying farther away is held where it
  rests until you come back.
- Days and nights pass there. The chambers stay at noon: it's noon again when you go back.
- Minecraft's light falls on what Portal 2 draws there: the portal gun in your hand, Chell (and Steve) seen through a
  portal, take the light where you stand - dark blue at night, warm beside a torch, as bright as ever by day. The
  portals' glow stays bright.
- **Portals** go on the land: a portal needs 2 x 4 blocks of flat face (solid behind, open in front) near where it
  hits, and snaps to the block grid; on anything smaller it fizzles. A shot carries as far as you can see - a hill or a
  wall a hundred blocks off takes a portal too.
- It's a separate Minecraft dimension (`portalcraft:surface`): nothing there touches the blocks you build in Portal 2's
  maps. You arrive on the nearest dry land around its middle, and come back where you left.
- **It has no edge**, like Minecraft's own world. Portal 2's map is only 940 blocks across, so it follows you: each time
  you get 256 blocks from its middle, it moves back under you, with your portals, cubes and anything you placed. You
  shouldn't notice it happen. (Garry's Mod's Infinite Map Base addon fakes endless maps the same way.)
- **Portals any distance apart.** A portal left far behind (a few hundred blocks, past the edge of Portal 2's map) stays
  open: Portal 2 keeps it high in its sky (a tiny portal far up there is one), Minecraft keeps the land around it
  loaded, and walking into the other portal takes you to its real place with your speed. Through it you see what's
  within your render distance; past that, sky. A cube thrown into a portal that far away comes out of the one in the
  sky.
- If you die there, you come back on its land.

### The Nether, the End, and other dimensions
Minecraft's own portals work in Minecraft's world, and Portal 2 follows you into each dimension's map:
- A **Nether portal** (an obsidian frame, lit) takes you to the Nether, and Portal 2 loads `sp_mc_nether`. The Nether's
  portals lead back to Minecraft's world, never into the test chambers.
- An **End portal** takes you to the End, and Portal 2 loads `sp_mc_end`. The End's exit portal, which opens once the
  dragon is dead, takes you back to Minecraft's world. The first time, the credits roll before you go back, as they do in Minecraft.
- **A mod's dimension** (the Aether, say) works the same way through that mod's own portal: Portal 2 loads `sp_mc_other`,
  which stands for whichever such dimension you went to last. Portalcraft builds whatever is there, but it doesn't
  support any mod's own features, only getting there and walking around. `map sp_mc_other` with no such dimension takes
  you to Minecraft's world instead.
- **You can only travel between dimensions in these maps** - unless **Wormhole Allowance** is on (Portalcraft... >
  Crossovers, off by default: "How do you block making a wormhole, anyhow?"). With it off, a Nether or End portal in
  Portal 2's chambers does nothing. With it on:
  - A Nether or End portal (or a mod's) built in a test chamber works. Portal 2 saves the chamber and loads that
    dimension's map, and the Nether portal leads there 1:1: one block of the Nether for one block of the chamber, not
    eight, because Portal 2's chambers aren't Minecraft's world.
  - Going back through the portal you came out of (the one in the Nether, or any way out of the End) takes you back
    into that test chamber, as it was, standing in the portal you built. Any other portal leads to Minecraft's world as
    usual.
  - Portalcraft remembers the last 32 of these wormholes, each with its own Portal 2 save (`pc_wormhole_<n>`;
    `tools\portalcraft.ps1 remove` deletes them).
- Portal 2's console takes you straight there: `map sp_mc_nether`, `map sp_mc_end`. You arrive near the middle: on the
  End's obsidian platform, or on solid ground in the Nether.
- Every dimension is endless, as in Minecraft: portals link the way Minecraft links them (one block of the Nether for
  eight of Minecraft's world), and the End's outer islands are out there past its gateways. (Worlds made before this
  had a 940-block border; it's gone the next time you go there.)

### A new Minecraft world
These Minecraft chat commands only work in Minecraft's world (the `sp_mc_*` maps). Portal 2's maps reject them.
- **`/newworld`** makes a new Minecraft world with a new seed: a new surface, Nether, End and any mod dimensions.
  **The current one is deleted**, unless you add `keep_current_world:true`, which keeps it to load later.
  `seed:<number or text>` picks the seed.
- **`/loadworld [name]`** loads a kept world. With no name it loads the last one kept; Tab lists their names
  (`world_1`, `world_2`, ...). The world you leave is kept too, unless you add `keep_current_world:false`.
- Minecraft saves, closes and reopens its world for either one, which takes a few seconds. Portal 2 stays where it is, and
  you arrive on the new surface. You keep your inventory, your Portal 2 progress and whatever you built in the test
  chambers. A bed you slept in over there is gone.

## Advancements
Minecraft's Advancements screen has a **Portalcraft** tab: 17 advancements for Portal 2's story, from getting the
Portal Gun to escaping the facility. They come as the story gets there (a line of dialogue, a map you arrive at, the
gel pipes connecting, your first ride in an excursion funnel), plus a few of your own doing: drinking a gel potion,
turning on No Portal Gun mode. Each one pops up in the corner, in either mode. (Minecraft's other pop-ups stay hidden.)

## Minecraft Music
Minecraft's pause menu > **Portalcraft...** > **Music...** > **Minecraft Music** plays Minecraft's music instead of
Portal 2's (off by default). Portal 2's own music is muted wherever Minecraft's plays, and its background sounds
(machinery, wind, hum) are turned down. Off: Portal 2's own music, and none of Minecraft's while Portal 2 is running
(switching it off stops Minecraft's track at once).
- **Portal 2's ambience**: Off, Quiet (the default, about a third as loud), Half or Full.
- **Minecraft's music** slider: how loud it plays, on top of the Music slider in Minecraft's Music & Sounds settings
  (default 89%, about 1 dB down). If that Music slider is at 0%, nothing of Minecraft's can be heard: the screen then
  says so in this row, and clicking it sets the slider to 100%.
- **A rule for each part of the game** (every map, and the finale in three parts: before the fight, Wheatley's fight,
  the moon shot and ending): *Minecraft's music* (the default: Minecraft's own music comes and goes as it does in
  Minecraft, as often as Minecraft's Music Frequency setting says), *Portal 2's own* (that part keeps Portal 2's music),
  or a track of your choice (searchable list of Minecraft's tracks), which plays where Portal 2's music would.
  Wheatley's fight plays **Pigstep** by default. The fight starts with Wheatley's first bombs and lasts until the
  moon shot, a saved game loaded in the middle of it included.
- The screen shows what's playing now and which part of the game you're in.
- The credits song stays muted unless its part is set to *Portal 2's own*; the moon shot's sound mix isn't muted.
- While Portal 2 loads a map (the next chamber, a reload, a save), Minecraft's music and sounds pause, and carry on
  where they were once it's in.

## Ending Arms
In the game's ending, Portal 2 shows Chell's arms (holding on to Wheatley, picking herself up after his trap). Portalcraft
draws your Minecraft arms there instead, with your skin, in both modes. Their poses come from **`Ending-Arms.bat`**
(needs Python 3): it opens a small page in your browser with the ending's animations, read from your own Portal 2, and
Minecraft's arms on them. Move, turn and scale the arms (keyframes per animation), then press **Export**: the poses go
to the Portalcraft instance's `config` folder (`portalcraft-ending-arms.json`) and Minecraft picks them up straight
away. Your work is kept in `tools\chellpose\pose.json`. The package comes with a finished set of poses, but the
exported file is worked out from Portal 2's animations on your PC, so open the tool once and press Export to use them:
until then the ending shows Chell's arms as usual.

## End Poem ending
With **End poem ending** on (Crossover features, off by default), Portal 2's ending movie - the ride up after "You win.
Just go." - doesn't play. Minecraft's end poem scrolls instead, on its End-portal background, to Aria Math on a loop,
while Portal 2 stays silent. Space speeds it up, and Escape skips it. When it's over, the game counts as finished, and
you wake up in Minecraft's own world (sp_mc_overworld) with a Weighted Companion Cube: "And the universe said, I love
you. / Because you are love." From there, **Back to the test chambers** goes to Portal 2's main menu. Loading any
chamber save makes it work as usual again.

## Edit Text
**`Edit-Text.bat`** (in the source code, not the player package: it edits the mod's sources; needs Python 3) opens a
page in your browser with every piece of Portalcraft's text: each item's name, description and how-it-works lines (an
item with no description can be given one: it shows in grey under the name), the menus, chat and on-screen messages,
what you're mining, ReShade's settings and the launchers. Edit, then press **Save** (or Ctrl+S). Minecraft's text goes into the Portalcraft instance's `config` folder
(`portalcraft-text.json`) and a running Minecraft shows it within a second; everything also goes into the mod's
sources, so text outside Minecraft (Portal 2's, the launchers') arrives with the next build. Placeholders like `%s`
are filled in by the game: the page warns if one goes missing.

## Known limits
- Floors are measured around you (16 blocks): mobs far away can still fall through model floors.
- Places only Chell can crawl through (under 1.5 blocks high) need Minecraft movement switched off.
- In some maps goo and bottomless pits share one kill volume, so an ender pearl thrown into goo can vanish even with
  "goo is water" on.
- SourceAutoRecord (SAR) works alongside Portalcraft (tested with SAR 1.15.5), Minecraft movement included. SAR's own
  crash reports (`crash_reports` in Portal 2's folder) may still log a few harmless ones from Portal 2's start-up.
- ReShade's overlay is on Ctrl+F12 (it has the shader's tuning sliders: depth bias, lighting match, debug views).
- Minecraft's world: only the land near you is solid for Portal 2 (for you 16 to 32 blocks around, for cubes 32 to 48),
  so a cube thrown farther than that falls through the ground.

### Can't be fixed (as far as we know)
- **Water looking lighter over shallow ground.** Seen from above, a lake's shallow bed (sand, gravel) shows through as a
  lighter blue haze, darker where the water is deep. That is Minecraft's own water: the same spot drawn by Minecraft
  alone, with Portal 2 closed, looks the same. (Under water there was a real bug, now fixed: in Minecraft's own world
  the water's fog went on twice, a second lighter blue haze over Minecraft's own.)
- **Achievements.** Portal 2 runs with cheats on in these sessions (Portalcraft needs its console), so its Steam
  achievements don't unlock.
- **Single player only.** Co-op has two players and a split screen; Portalcraft drives one player and one view.
- **Blocks on off-grid floors.** Portal 2's walls and floors are measured to 1/8 of a block, so mobs, items and arrows
  stop at the real surfaces. But Minecraft's blocks always sit on the block grid, and placing goes by it: a block goes
  in front of the surface you click, or into the surface's cell when that sinks it less than half a block. On a Portal
  2 floor that isn't on the grid a block can stand up to half a block above it, so a 2-block doorway there may be too
  low to walk through. Build on a layer of blocks.
- **The ceiling laser at the start of Laser Intro** (sp_a2_laser_intro) goes through everything, even Portal 2's own
  cubes: no blocker tried (props, boxes, cubes) stops it.

## Portal 2's console: Portalcraft's own settings
Type these into Portal 2's console (` key). They are there once a map has loaded, and go back to their defaults when
Portal 2 closes; typing just the name shows the value and what it does.
- `mc_function_key_toggle 1`: Minecraft's function keys work in Portal mode too. F1 hides Minecraft's HUD, F2 takes a
  Minecraft screenshot, F3 (and the F3 + key combinations) shows Minecraft's debug screen. F4, F6 to F10 and F12 go to
  Minecraft as well, in both modes, instead of Portal 2's binds on them. F5 and F11 stay as they were. `0` (the
  default) turns it off.
- `player_size_x`, `player_size_y`, `player_size_z`: the player's size in blocks, from 0.1 to 16. x runs along
  Minecraft's east-west axis, z north-south, y is the height; Minecraft's own size is 0.6, 1.8, 0.6. The eye sits at
  nine tenths of the height, and crouching and swimming shrink in proportion. Minecraft's player is scaled with the
  height (its own box stays square). Any size other than Minecraft's is yours in both modes; otherwise Portal mode is
  Chell's size, as always.
- `cl_show_mcstandin 1` (debugging): draws the invisible boxes that stand in for Minecraft's blocks in Portal 2 (what
  you stand on, what lasers stop at) near you, through walls: green for blocks, yellow for the laser twins of blocks
  beside a beam, blue for floors over goo.
- `rendering_snap` (debugging): saves what the bridge between the two games is drawing right now, in
  `runtime\snaps\`: a `.txt` (both games' cameras, Minecraft's frames, every value the effect was given) and a `.bmp`
  of the screen.
- `mc_p2_demo` (debugging): Portal 2's demo recording with Minecraft's side recorded alongside, to show a bug exactly
  as it happened. `mc_p2_demo record name` (in a map) starts one, `mc_p2_demo stop` ends it (so does a map change).
  `mc_p2_demo play name` plays it back: Minecraft opens a copy of the world as it was there (your own world is never
  touched) and follows the demo, then goes back to your world when it ends. `mc_p2_demo list` lists them. Each one is
  a folder in `runtime\demos\` (about 30 MB: a copy of the part of your world around you).

## Playtesting: reporting a bug
Say what you were doing, which chapter or map it was (Portal 2's console: `status` shows it), and whether you were in
Portal or Minecraft mode. For something that looks wrong, type `rendering_snap` into Portal 2's console while it's on
screen and send the two files it makes in `runtime\snaps\` too. For something you can make happen again, an
`mc_p2_demo record` of it (zip its folder in `runtime\demos\`) shows it best. Then send these files:
- `logs\play.log` in this folder (the Play window's log);
- `runtime\ReShade.log` in this folder (the Portal 2 side; it's replaced each time you play, so copy it before playing
  again), and `runtime\crash.txt` if Portal 2 closed by itself (where it crashed, if it did);
- Minecraft's `logs\latest.log`, and anything in `crash-reports\`, from the instance's folder (Modrinth App: the
  instance's ... menu > Open folder; official launcher: `%APPDATA%\.portalcraft`);
- `portalcraft_console.log` from Portal 2's `portal2` folder (Steam > Portal 2 > Manage > Browse local files).
A screenshot helps a lot with anything visual. Portal 2 saves made just before the problem are gold: they are in
Portal 2's `portal2\SAVE\<number>\` folder.

## Removing it
ReShade is taken out of Portal 2's folder every time you stop playing (and with `-vulkan`, Portal 2's own
`bin\dxvk_d3d9.dll` is put back), so Portal 2 itself stays untouched. So is Portalcraft's caption folder (an extra
`portal2_dlcN` folder with `portalcraft.txt` in it: in no portal gun mode it holds one of Wheatley's lines, cut from your
own game files, and its caption), and `portal2\maps\pclong` (made while you play a community map whose name is too
long for Portalcraft's link: a short-named link to that map's file, so Minecraft can read it) and `pcdemo_*.dem` in
`portal2\` (`mc_p2_demo`'s demo files while they're in use). If a session ended badly (a crash, the Play window closed early),
`tools\portalcraft.ps1 remove` (run with `powershell -ExecutionPolicy Bypass -File tools\portalcraft.ps1 remove`) does
it; so does the next Play. Steam's Verify integrity of game files puts ReShade's slot back but leaves that folder. Then delete the Portalcraft
instance in the Modrinth App (official launcher: `Install-Portalcraft.ps1 -Uninstall`) and this folder. The save
backup in `Documents\Portal 2 saves (backup before Portalcraft)` stays: delete it yourself once you don't need it.

## Building from source
- Minecraft mod: JDK 25 (`JAVA_HOME` pointing at it), `cd mc` then `gradlew build` →
  `mc\build\libs\portalcraft-0.1.0.jar` (then rerun the installer). `gradlew runClient` starts a dev Minecraft.
- Portal 2 add-on: Visual Studio 2022 Build Tools with the C++ x86 tools, `addon\build.bat`, then `tools\portalcraft.ps1 deploy`.
- ReShade 6.8.0 (add-on build, 32-bit) goes in `third_party\runtime\ReShade32.dll`. It isn't in the source code: take
  it from a release zip (same path), or from the official `ReShade_Setup_6.8.0_Addon.exe` from reshade.me.
- `tools\package.ps1` builds the release zip (`dist\`) from the built halves.
- How the two halves talk (the shared-memory link, the frames block, every bit and message): `PROTOCOL.md`.
  `python tools\protocol_check.py` checks both halves' code against it (needs Python 3); `tools\package.ps1` runs it.
- `python tools\fakehost.py` stands in for Portal 2: with the Minecraft mod running (`gradlew runClient`) it checks the
  version handshake, the status, the frames and where a test block is drawn (needs Python 3 with numpy and Pillow).
- More test tools are in `tools\` (each says what it does at its top). They talk to the games only through the link,
  `runtime\cmd.txt` (Portal 2's console) and window messages, never your real mouse and keyboard.

## Credits and license
- Made by ZannaFella, with AI: all of Portalcraft's code was written by Claude (Anthropic's Claude Opus 5.5, in Claude
  Code). ZannaFella came up with what to build and how it should work, wrote most of the mod's text, drew every item
  texture by hand, and playtested every step of it in the real games. `P2-MC_DESIGN.md` says who did what in detail.
- It started from universal-modder's Minecraft x GTA V passthrough example
  (https://github.com/rehan-remade/universal-modder, MIT). Portal 2's type layouts and offsets follow SourceAutoRecord
  (https://github.com/p2sr/SourceAutoRecord, MIT). Drawing into Portal 2 is done through ReShade by crosire
  (https://reshade.me, BSD-3-Clause), and the Minecraft side runs on Fabric (https://fabricmc.net).
- Smooth crossing (mobs and items part-way through a portal, drawn at both ends) follows the way Immersive Portals by
  qouteall and contributors does it (https://github.com/iPortalTeam/ImmersivePortalsMod, MIT) - the idea, not its code.
- Minecraft movement in Portal 2 follows Minecraft 26.3's own rules (its code ships unobfuscated) and the formulas
  collected on the Minecraft Parkour Wiki (https://www.mcpk.wiki).
- Portalcraft's own code is released into the public domain under the Unlicense (`LICENSE`). The third-party parts
  keep their own licenses: `THIRD_PARTY_NOTICES.txt`.
- No game files are included: Portal 2 and Minecraft come from your own copies. Portalcraft is a fan project, not
  affiliated with or endorsed by Valve or Mojang/Microsoft.
