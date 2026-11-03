# Portalcraft: real Minecraft inside Portal 2

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
   start only: click through Minecraft's accessibility screen.) Minecraft opens its Portalcraft world by itself. If
   you see the title screen instead, the mod didn't load: check the instance's `mods` folder has both jars.
4. Portal 2 starts by itself once Minecraft is ready. Load a save or start a chapter as usual. Minecraft's window
   hides while Portal 2 runs.
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

**Minecraft Control Takeover** (Portalcraft... > Crossovers > Controls, off by default): for people whose Portal 2 binds
clash with Minecraft's. A key bound to one of Minecraft's other controls (a mod's zoom key, advancements on L, the
creative hotbar keys on C and X...) goes to Minecraft in both modes, never to Portal 2's bind for the same key.
Moving, jumping, sneaking, sprinting, the mouse, the hotbar, inventory, chat and Minecraft's screenshot, fullscreen,
hide-HUD (F1) and camera keys stay as above. To give a key back to Portal 2, unbind it in Minecraft's Controls.

**Minecraft's pause menu has a Portalcraft... button**: pick what crosses between the games (Minecraft movement,
Minecraft HUD in Portal mode, Minecraft healing, Minecraft hurts Chell, knockback, solid blocks, lasers, explosions, spectator = noclip, pause
together, through portals, fresh blocks each map), a **Clear this map's blocks** button, and **Clear all maps...**
(asks first): every Minecraft block, mob and item in all of Portal 2's maps goes, for a fresh run. Your inventory and
Minecraft's own world stay.

**Survival** (`/gamemode survival`): one health for both games, 1 heart = 10 Portal 2 health. With Minecraft healing
on (default), Minecraft decides: Portal 2 stops regenerating, its damage (lasers, turrets: as deadly as in Portal 2)
comes off your hearts, and
you heal by eating like in Minecraft (the starter kit has food). Mob hits knock you back. Dying in one game kills
you in the other.

**Crossovers** (most can be switched off in the **Portalcraft...** menus of Minecraft's pause screen):
- *Building and mining:* Minecraft blocks are solid in Portal 2 (for you, cubes and lasers). Mining Portal 2's world
  gives Minecraft items: dirt, metal (copper down in Old Aperture), redstone from buttons and doors, torches from light
  bridges, gel potions from painted surfaces. Plants grow on Portal 2's dirt.
- *Digging into Portal 2 (EXPERIMENTAL, off by default):* switch on "Real Mining Portal 2" (Portalcraft... > Crossovers;
  it switches "Mining Portal 2" on with it) and a pickaxe digs real holes into Portal 2's walls, floors and ceilings. The block drops what its surface is made of,
  the blocks around show what the map has there (white concrete under white panels, deepslate deeper in) and mine like
  Minecraft blocks, and you can tunnel, fall in, and break back out into a chamber from behind. Holes refill when the
  map starts fresh, and all of them when the option goes off; balance mode switches it off. Cubes,
  turrets and other physics objects fall into holes too, and Portal 2's lasers, funnels, grills, effects and
  captions stay on top of a hole. Known issues: what Portal 2 has behind a thin surface shows as darkness, and an
  object sunk all the way into a hole is hidden (Portal 2 doesn't draw things inside its walls).
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
- *Portals:* Minecraft is drawn through Portal 2's portals (you see yourself), and mobs, items, arrows, TNT and ender
  pearls go through them with their momentum. Mobs chasing you walk through them when that's the way to you. Ender pearls that fall into a death pit vanish instead of landing you
  in it.
- *Your player* (skin, armour, cape, elytra), seen in third person (F5, in Minecraft mode) or through a portal, is drawn
  by Portal 2 itself from a copy Minecraft keeps, so it stays put when the camera moves fast instead of lagging behind
  or slicing ("Your player drawn by Portal 2", Portalcraft... > Crossovers, on by default). Held items and trimmed
  armour still come from Minecraft's picture. You only see yourself through portals that face each other across a
  room: two portals on the same wall can't show you.
- *Water and goo:* Minecraft water and lava flow over Portal 2's floors; you swim in them, with their fog. Flowing water
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
  only on portalable (white) surfaces, or on your own blocks with a portalable surface within a block of the new one;
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
crafting grid (a Crafter block still makes it).

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
works too: `map sp_mc_overworld`.)
- Both modes work there as everywhere: Portal mode moves you like Chell (a one-block step needs a jump), Minecraft mode
  like Minecraft. Cubes land on the ground.
- **Portals** go on the land: a portal needs 2 x 4 blocks of flat face (solid behind, open in front) near where it
  hits, and snaps to the block grid; on anything smaller it fizzles.
- It's a separate Minecraft dimension (`portalcraft:surface`), 940 blocks across: nothing there touches the blocks you
  build in Portal 2's maps. You arrive on the nearest dry land around its middle, and come back where you left.
- If you die there, you come back on its land.

## Minecraft Music
Minecraft's pause menu > **Portalcraft...** > **Music...** > **Minecraft Music** plays Minecraft's music instead of
Portal 2's (off by default). Portal 2's own music is muted wherever Minecraft's plays, and its background sounds
(machinery, wind, hum) are turned down.
- **Portal 2's ambience**: Off, Quiet (the default, about a third as loud), Half or Full.
- **Minecraft's music** slider: how loud it plays, on top of the Music slider in Minecraft's Music & Sounds settings
  (default 89%, about 1 dB down).
- **A rule for each part of the game** (every map, and the finale in three parts: before the fight, Wheatley's fight,
  the moon shot and ending): *Minecraft's music* (the default: Minecraft's own music comes and goes as it does in
  Minecraft, as often as Minecraft's Music Frequency setting says), *Portal 2's own* (that part keeps Portal 2's music),
  or a track of your choice (searchable list of Minecraft's tracks), which plays where Portal 2's music would.
  Wheatley's fight plays **Pigstep** by default.
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

## Edit Text
**`Edit-Text.bat`** (in the source code, not the player package: it edits the mod's sources; needs Python 3) opens a
page in your browser with every piece of Portalcraft's text: each item's name, description and how-it-works lines (an
item with no description can be given one: it shows in grey under the name), the menus, chat and on-screen messages,
what you're mining, ReShade's settings and the launchers. Edit, then press **Save** (or Ctrl+S). Minecraft's text goes into the Portalcraft instance's `config` folder
(`portalcraft-text.json`) and a running Minecraft shows it within a second; everything also goes into the mod's
sources, so text outside Minecraft (Portal 2's, the launchers') arrives with the next build. Placeholders like `%s`
are filled in by the game: the page warns if one goes missing.

## Known limits
- The ceiling laser at the start of Laser Intro (sp_a2_laser_intro) goes through everything, even Portal 2's own cubes.
- Portal 2's walls and floors are measured to 1/8 of a block, so mobs, items and arrows stop at the real surfaces. But
  Minecraft's blocks always sit on the block grid, and placing goes by it: a block goes in front of the surface you
  click, or into the surface's cell when that sinks it less than half a block. On a Portal 2 floor that isn't on the
  grid a block can stand up to half a block above it, so a 2-block doorway there may be too low to walk through.
  Build on a layer of blocks.
- Floors are measured around you (16 blocks): mobs far away can still fall through model floors.
- Places only Chell can crawl through (under 1.5 blocks high) need Minecraft movement switched off.
- In some maps goo and bottomless pits share one kill volume, so an ender pearl thrown into goo can vanish even with
  "goo is water" on.
- Portal 2 runs with cheats on in these sessions, so its Steam achievements don't unlock. Single player only.
- With SourceAutoRecord (SAR) loaded, Minecraft movement switches itself off (both hook Portal 2's movement; you move
  like Chell). Everything else works. Leave SAR out of Portalcraft sessions (`plugin_load sar` in your autoexec) to get
  it back.
- ReShade's overlay is on Ctrl+F12 (it has the shader's tuning sliders: depth bias, lighting match, debug views).
- Minecraft's world: it stays noon there. In Portal mode there is no swimming (Portal 2 has no water: you walk on the
  bottom). Only the land near you (16 to 32 blocks around) is solid for Portal 2, so a cube thrown far can fall
  through the ground until you walk closer.

## Playtesting: reporting a bug
Say what you were doing, which chapter or map it was (Portal 2's console: `status` shows it), and whether you were in
Portal or Minecraft mode. Then send these files:
- `logs\play.log` in this folder (the Play window's log);
- `runtime\ReShade.log` in this folder (the Portal 2 side; it's replaced each time you play, so copy it before playing
  again);
- Minecraft's `logs\latest.log`, and anything in `crash-reports\`, from the instance's folder (Modrinth App: the
  instance's ... menu > Open folder; official launcher: `%APPDATA%\.portalcraft`);
- `portalcraft_console.log` from Portal 2's `portal2` folder (Steam > Portal 2 > Manage > Browse local files).
A screenshot helps a lot with anything visual. Portal 2 saves made just before the problem are gold: they are in
Portal 2's `portal2\SAVE\<number>\` folder.

## Removing it
ReShade is taken out of Portal 2's folder every time you stop playing (and with `-vulkan`, Portal 2's own
`bin\dxvk_d3d9.dll` is put back), so Portal 2 itself stays untouched. So is Portalcraft's caption folder (an extra
`portal2_dlcN` folder with `portalcraft.txt` in it: in no portal gun mode it holds one of Wheatley's lines, cut from your
own game files, and its caption). If a session ended badly (a crash, the Play window closed early),
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
- Made by ZannaFella, with AI: most of Portalcraft's code was written by Claude (Anthropic's Claude Opus 5.5, in Claude
  Code), with ZannaFella deciding what to build and playtesting every step of it in the real games. The item textures
  are all hand-drawn by ZannaFella.
- It started from universal-modder's Minecraft x GTA V passthrough example
  (https://github.com/rehan-remade/universal-modder, MIT). Portal 2's type layouts and offsets follow SourceAutoRecord
  (https://github.com/p2sr/SourceAutoRecord, MIT). Drawing into Portal 2 is done through ReShade by crosire
  (https://reshade.me, BSD-3-Clause), and the Minecraft side runs on Fabric (https://fabricmc.net).
- Minecraft movement in Portal 2 follows Minecraft 26.3's own rules (its code ships unobfuscated) and the formulas
  collected on the Minecraft Parkour Wiki (https://www.mcpk.wiki).
- Portalcraft's own code is released into the public domain under the Unlicense (`LICENSE`). The third-party parts
  keep their own licenses: `THIRD_PARTY_NOTICES.txt`.
- No game files are included: Portal 2 and Minecraft come from your own copies. Portalcraft is a fan project, not
  affiliated with or endorsed by Valve or Mojang/Microsoft.
