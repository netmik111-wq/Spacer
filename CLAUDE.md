# Spacer: working notes

**Read `docs/VISION.md` first.** It records, in the author's own words, how he sees the game
in the future. Make decisions with that in mind, and when the author adds to the vision,
write it down there too.

**`docs/MECHANICS.md` describes every mechanic already in the game, with numbers** (the
author's request). Update it in every build that changes something for the player, along with
the build number in its header. **In the same step, also update the author's document "Spacer: механики игры"
(Spacer: game mechanics)** in Claude Docs (https://claude.ai/artifact/CkpfXu7j25QbPqTijemas6, project
`5f32e1ae-d2f4-4651-9d5a-aca9b95268ad`): the author asked to keep it in the same shape. It is
edited with the Claude Docs tools (read it first: the author may edit it himself).

Notes for continuing work in a new session. What the game is and how to open it is in
`README.md`. This file holds what is not in the code: agreements, reasons for decisions, the
order of checks, and pitfalls.

## About the project

- Our own 2D networked game inspired by Space Station 13 (the FTL13 build) and FTL, not a fork.
  Networking comes first. It needs a story and a campaign. At its core are space and its cruelty.
  The scale should grow with the number of players.
- We move in small steps. The mechanics are our own; ideas come from books and other games.
  We study FTL13 (`github.com/FTL13/FTL13`) to understand how its mechanics work.
- Language: as of 2026-10-14 the author asked that everything on GitHub (docs, notes, code
  comments, commit messages) be in English. In-game text (interface, messages the player sees)
  is still Russian until the author confirms it should switch too. Replies to the author are
  now in English. Explain things in simple words, without jargon.
- The game is tested on Windows over Radmin VPN. Every change reaches players only through
  a Windows build, so changes should be gathered into one build.

## Plan

1. Done. Server and clients: characters walk around the ship and see each other.
2. Done. Compartments with air: doors, a hull breach, leaking, pressure equalization.
3. Done. Environmental damage and health states using the indicators from the author's HUD
   (`art_src/hud.dmi`), up to critical condition and death.
4. Done. Space suit with an oxygen supply, and breach repair.
5. Done. Bridge with two consoles, sectors, jumping, and the event director.

The first plan is complete. After it, at the author's word, we added steering the ship within
a sector (with console breakdowns) and a second deck with ladders, glass floors and catwalks.

The second plan was proposed by me; the author answered «Начинай» ("Go ahead"). Each step is one build:

1. Done. Something to do on the lower deck: the engine and the air plant.
2. Done. Emergency shutters at doors (the author's wish).
3. Done. New director events: jammed door, emergency shutter failure, power failure.
4. Done. Repair costs and a trader: patches, spare parts, air for the plant, credits.
5. Done. Helping someone who is down: drag a downed person, search them; slot-based inventory
   (the author chose slots rather than backpack volume).
6. Done. Infinite space: sectors are generated as you approach.

The second plan is complete.

The third plan was given by the author himself; it is written out in full in `docs/VISION.md`
("The author's third plan"). The order of steps was accepted by the author; each step is one build:

1. Done. Items: what's in hand, drop and pick up, item properties, flashlight.
2. Done. Field of view (160° cone; in the dark 60° and 2 tiles; flashlight 35° and 9 tiles;
   groundwork for two eyes) and sound icons outside it; silence in vacuum.
3. Done. Weapons and pirate boarders, a simple bandage.
4. Done. Healing: medkit, heal yourself and others.
5. Done. New, orderly ship `ship02` and a two-door airlock (the author accepted the plan:
   "we'll edit it as the game grows").
6. Done. Derelict ships: fly up, exit through the airlock into open space, or
   dock (the author's word); no pirates on them yet, the author will develop them further.
7. Done. Pirate ship: a director event; it docks by force, breaks open the airlock, lands pirates.
8. Done. Clothing: removable space suit, jumpsuit (2 pockets), backpack (4 places).
9. Done. Ship weapons: three guns and a weapons console, fighting the pirate ship before it docks.

The third plan is complete.

The fourth plan was assembled from the author's answers to the survey "Spacer: куда дальше"
("Spacer: where next") (October 13, 2026; answers in the survey database: collection `survey`,
document `answers`). The author said to do every item except the darkness front: he is still
thinking that concept through. At first each step was a separate build; after fuel the author
asked for the rest to be done as one build (v35):

1. Done (v34). Fuel for jumps, as in FTL (later the author wants a more complex system).
2. Done (v35). Crew reserve instead of a free R (hiring at the trader is an "extra life",
   the author's word), hull integrity, campaign end and summary.
3. Postponed. Darkness front across the sector map.
4. Done (v35). Saving the campaign between evenings (the author chose a long campaign; later there
   will be PvP, sandbox and roleplay modes as in SS13).
5. Done (v35). Local speech, radio and intercoms (the author's word).
6. Done (v35). First real sounds: dry and realistic (footsteps, creaks, hissing), with
   direction; only breaches and screams remain as icons (as the author asked earlier).
7. Done (v35). Strict jobs with their own access; skills grow by job,
   others more slowly.

The fourth plan is complete except for the darkness front. The next plan comes from new questions to the author.

Build v40 (0.33) was the author's own request for friendly interfaces, done as one build: an
inventory window, settings (sound, picture, every key rebindable with Ctrl/Shift/Alt), an admin
panel in tabs for the host and the admins the host names, and the fix for own footsteps heard in
space. The author also allowed merging pull requests without asking.

Build v41 (0.34) was again the author's own request, as one build: a good window for the ship's store,
an interface for the guns with zones of the enemy ship to aim at (knocking out its systems), and
holomap monitors on the bridge and in the engine room (the ship's damage and pressure).

Build v44 (0.37) was the author's own request, as one build: the whole 160° cone seen (a wall far along
a corridor was left dark), the pirate ship split into two events (boarding as before, and a fight in
space whose wreck can be boarded and looted), a smarter enemy that runs on its jump drive when beaten,
and three outcomes on boarding a wreck (70% all dead, fight, join).

Build v45 (0.38) was the author's own request, as one build: the dark no longer pitch black (the room in
view dimly seen, the flashlight brighter; on wrecks, derelicts and our ship without power) and the left
mouse button working as E on what it clicks (items on the floor, consoles, machines, repairs).

Build v46 (0.39) was the author's own request, as one build: light and darkness as in his SS13
screenshots (soft per-cell light, near-black but readable dark, the flashlight a warm round pool instead
of a beam) and vision of 9 cells (eyes and screen).

Build v47 (0.40) was the author's own request, as one build: a clean screen (the status lines and the key
hints at the top are hidden, F1 shows them) and "deep dark" as in SS13 (out of sight is near black, a soft
pool all round the character).

Build v48 (0.41) was the author's comment on the v47 picture: "smoother, like a triangle". The seen area
now fades along the cone's straight sides, and light pools fade out over open floor.

Build v49 (0.42) was the author's own request, as one build: ship weapons changed at the gun console and
kept in the cargo, a reactor power budget, shields (ours and the pirates') by the author's rule, ten weapons
(lasers heavy/siege/rapid, the cutting beam, blaster, rockets, EMP, ion gun and cannon), our hull 200 and
pirates 12, and a trader's window with categories, buying and selling. The beam was mine to invent (the
author did not want FTL's); three ideas were put to him, the cutter is built as the default.

Build v50 (0.43): the author answered the beam card with "B+C, 2 different beams": the tractor beam (holds
the enemy 8 s: we hit more, it can't run or close in) and the siphon beam (moves its shield into ours) were
added beside the cutter.

After that: engines and complex atmosphere (only after asking). With each step add
items at the trader. The author's sub-items (1.1, 2.1 …) are groundwork for the future.
The author's rule: bodies remain after death. Returning a dead player with the R key as a new
crew member was accepted by the author ("excellent"), but he has not called it final.
What's still missing and suggests itself: other ways to earn credits besides exploration;
new items for slots (tools, medkit, spare tank).

## Environment

- Godot 4.7.2, standard build (not .NET), Compatibility renderer. Download:
  `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip`
- Export templates (1.3 GB, needed only to build the game), same address, file
  `Godot_v4.7.2-stable_export_templates.tpz`. It is a zip: the needed files from the `templates/` folder
  (`linux_release.x86_64`, `windows_release_x86_64.exe`, `windows_release_x86_64_console.exe`,
  `version.txt`) go into `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Python 3 with Pillow for `tools/make_assets.py`, `rustc` for `tools/lagproxy.rs`.
- A screenshot of the game without a monitor: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path .
  --resolution 1280x720 -- --host bots=2 shot=FILE.png shot_after=6 quit_after=7`.
- After changing code or resources: `godot --headless --path . --import`.

## Checks before shipping

    tools/runtests.sh          (all 15 scripts below in a row; GitHub Actions runs it on every push)
    godot --headless --path . --script res://tools/airtest.gd
    godot --headless --path . --script res://tools/directortest.gd
    godot --headless --path . --script res://tools/machinetest.gd
    godot --headless --path . --script res://tools/spacetest.gd
    godot --headless --path . --script res://tools/itemtest.gd
    godot --headless --path . --script res://tools/sighttest.gd
    godot --headless --path . --script res://tools/fighttest.gd
    godot --headless --path . --script res://tools/locktest.gd
    godot --headless --path . --script res://tools/derelicttest.gd
    godot --headless --path . --script res://tools/weartest.gd
    godot --headless --path . --script res://tools/guntest.gd   (since v49 also weapons, shields, trade)
    godot --headless --path . --script res://tools/crewtest.gd
    godot --headless --path . --script res://tools/savetest.gd
    godot --headless --path . --script res://tools/admintest.gd
    godot --headless --path . --script res://tools/holotest.gd
    rustc -O tools/lagproxy.rs -o tools/lagproxy
    GODOT=... tools/nettest.sh 8 30
    GODOT=... LAGPROXY=tools/lagproxy tools/nettest.sh 8 30 40 10 2
    GODOT=... LAGPROXY=tools/lagproxy tools/nettest.sh 8 30 100 30 5
    GODOT=... DERELICT=3 tools/nettest.sh 8 30
    GODOT=... PIRATESHIP=2 tools/nettest.sh 8 30

Expected result: `state checks ... 0 bad`, `ended where the server says: N/N`,
no errors in the logs. Corrected steps: 0–0.3% direct, up to 1% with 2% loss
(since v35 closed doors added rare corrections near them), up to 2–3% with 5% loss and 210 ms ping. The test breaches the hull itself at the sixth second;
the director is off in it.

Load benchmark (not needed for every build; rerun after changes to networking or the tick):
`GODOT=... tools/bench.sh 32 60` starts a server and 32 windowless clients, and prints how long
logging in takes and how long a server tick takes (the budget is 50 ms). With `PIN=1` (default)
the server gets CPU 0 to itself. Results are in `docs/BENCHMARK.md`.

GitHub Actions (`.github/workflows/tests.yml`) runs `tools/runtests.sh` on every push and pull
request. A red check on GitHub means one of the 15 scripts failed; its log is attached to the run.

Host scenarios (server as a separate process) are checked on the built game: the guest
gets "connection lost" right after the host leaves; a busy port gives a clear
message; a killed game does not leave the server running forever; creating a game again works.
The parameters for these checks are described in the header of `src/main.gd`.

## How it works

- The server decides everything, 20 ticks per second, single thread. The client sends only direction changes
  with the tick number on which they should take effect.
- Our own binary protocol on top of `ENetConnection` (`src/shared/net.gd`); Godot's high-level networking
  is not used. When the packet format changes, increase `PROTOCOL`.
- The world is sent in 16×16-tile chunks; the client gets the 3×3 chunks around itself: full
  contents when a chunk enters view, then only changes. Doors, breaches, things on the floor
  and air travel this way. Characters inside those chunks are sent per client, only those it may
  see (see "The server decides who each client sees"). Every 2 seconds the server sends checksums,
  and the client compares.
- **The server is split by topic** (since v39). `src/server/game_server.gd` keeps the state of the
  world, the network loop and the order of a tick; everything else is in parts it keeps one of each:
  `chat`, `crew`, `movement`, `inventory`, `looting`, `combat`, `repairs`, `systems`, `navigation`,
  `supplies`, `replication`, `holomap` (plus the older `director`, `pirates`, `derelict`, `gunnery`, `campaign`).
  A part reaches the rest through `server` (typed `GameServer`, a `class_name`), so a wrong name is a
  parse error, not a surprise at run time. Calls between parts go `server.chat.say(...)`.
- **Ships are objects with a network id** (`src/server/ship.gd`, since v39). The crew's ship is
  `GameServer.ship` (id `Net.CREW_SHIP`): its place in space and course, power, breakdowns, pumps,
  supplies, money, hull. Another ship alongside is `Derelict.ship` with a fresh id each time one comes.
  `S_SHIPS` lists the ships (replaced `S_OTHER`); every packet about one ship (`S_NAV`, `S_HELM`,
  `S_DEVICES`, `S_POWER`, `S_STORE`, `S_GUNS`) carries its id after the kind byte, and the client
  takes those about the ship it is on (`GameClient.my_ship`, from `S_WELCOME`). This is groundwork for
  several crewed ships in one world (the vision's scale); there is still one now.
- Decks lie in one grid, one below another (`ShipMap`): deck 0 is the top and starts
  at row 0, the next at row `deck_stride` (a multiple of 16; there is always an
  empty row between decks). So a tile is given by x and y everywhere, and movement, doors, breaches
  and network records know nothing about decks. Things that do know about decks: the map (`see_through`,
  `air_down`/`air_up`, `climb`), air, view and rendering.
- Client view: the 3×3 chunks around it on its deck and the same chunks on all other decks.
  So changing decks sends nothing new.
- Rules the client predicts live in `src/shared/` and are shared by both sides:
  `Mover.step` (movement) and `Doors.bump` (opening a door). Change them only there.
- Turning without a step (mouse click) is also a command in the walking stream: the value
  `Mover.TURN + direction` (`Mover.apply_input`), so it is predicted without delay.
- On every server word about its own character and every door change, the client
  replays its unconfirmed commands (`_rebuild_prediction`).
- «Создать игру» ("Create game") launches the server as a second process of the same program (`--headless -- --server`).
  If that fails, the server runs inside the game. The host's game knows the server's secret string:
  it grants the right to stop the server and use test commands.

## Decisions and reasons

- **Godot 4.7.2 and GDScript.** BYOND is outdated. Robust Toolbox (the SS14 engine) was rejected: C#,
  mixed licenses (MIT, GPLv3, CC-BY-SA), frequent incompatible versions.
- **One thread.** Measurements in `research/`: threads speed up a server tick but don't reduce the total
  load and add hard-to-catch bugs. Revisit if the server has more than 128 players
  or a tick takes longer than 25 ms.
- **Air: one number per tile** (pressure), no gas composition. Composition will be needed
  for the suit and fires. Right now the loop visits every tile; for an 80-tile ship this
  costs nothing. For big maps: compute only unsettled tiles or move it
  into a compiled module (`research/` has measurements: 255×255 in GDScript is 40 ms per tick).
- **Leak speed** is tuned to leave time to react: a 10-tile compartment
  loses half its air in 8 seconds. Coefficients in `src/server/air.gd`.
- **Doors open by themselves**, as in SS13. Players don't collide with each other.
- **Health on the SS13 scale:** from 100 through 0 (unconscious) to −100 (death). The author's `hud.dmi` has
  exactly eight monitor states for this scale and the SS13 alarm lamps: hunger,
  low and high pressure, low and high oxygen, toxic air, O2 supply.
  Used: the monitor, `kpa_low1`, `kpa_low2`, `o2_low`; the rest await their mechanics
  (hunger, fire and overheating, gases, the suit tank). Damage numbers in `src/server/vitals.gd`.
- **Instead of pressure numbers, the author's lamps light up.** Exact values only in debug via F3.
- **The space suit** (until build v29 it was always worn) is now clothing, but everyone arrives in it.
  Only the oxygen supply is controlled, like "internals" in SS13: the author has lamps
  `o2_on` and `o2_off` for this. The supply protects against both suffocation and pressure, and
  doesn't turn on without a suit (`Inventory.set_supply`). There is deliberately no automation.
- **Clothing is three places** (`Player.worn`, `Net.WEAR_*`), separate from slots. There are now
  12 slots: 6 always, 2 pockets with a jumpsuit, 4 with a backpack (`Player.usable`; the client repeats
  the rule in `GameClient.usable`). A worn suit is stored as `ITEM_SUIT`, with oxygen
  in `Player.tank`; a removed one is the item `ITEM_SUIT + tenths of the tank` (like ammo in a pistol).
  Appearance travels in the `S_OUTFIT` packet (a row of `chars.png`: color × 6 looks, `Net.LOOKS`),
  not in the character record: it changes rarely and doesn't touch checksums.
  The tank level bar is drawn in code: the author's HUD has none.
- **The oxygen rack** is a red box on the wall (`console_2` from the mockup), digit 2 in the map.
- **One action key.** The client sends only "pressed/released"; the server looks at the tile
  in front of the character: a breach gets repaired, a rack refills. Add new objects there too
  (`Repairs.update`), and the hint in `GameClient.use_target`.
- **A body is a separate record** with its own number and the kind "body" in the crew list.
- **Bridge consoles are wall tiles:** the green screen (`console_1`, digit 1 in the map) is
  the sector map, the panel with lights (`console_3`, digit 3) is ship control.
  The console's role is determined by its tile (`ShipMap.chart`, `ShipMap.helm`).
- **Inside a sector** is a 200×200 square (`Sectors.SPAN`); the main feature has a place
  and a radius: a meteor stream's circle or docking range. The ship moves in a straight line
  at constant speed, so the server sends its position only when the course changes,
  and the client computes the rest (`GameClient.ship_pos`). Sector danger for the director
  takes the ship's position into account (`Navigation.danger_kind`).
- **An ordered jump cancels the in-sector course** (the author's remark): a moving ship
  coasts straight until the jump rather than toward the old point (`Navigation.start_jump` moves the target
  to the sector's edge), the course line from the control console disappears, the helm doesn't respond.
- **Everything broken** (consoles, engine, air plant) lives in `Ship.broken`
  keyed by wall tile and is sent in full on change. Repaired with the action key, like a breach.
  The "not both at once" rule is in `Systems.can_break`: bridge consoles and the engine break one at a time.
  For the consoles, this guarantees an escape route from the author's vision.
- **The engine powers the whole ship** (tile `engine`, digit 6 in the map). The author's word: when
  the engine shuts down, absolutely all systems stop working, but don't break.
  So everything added to the ship must ask `GameServer.powered()`
  (on the client `GameClient.powered()`). Currently dependent on power: movement and jump, consoles,
  the air plant, oxygen racks, emergency shutters, doors (`Doors.manual`: without
  power they open with a push over 1.5 s) and light (darkening in `GameScreen`). Not dependent
  on power: the suit, the player's instruments, ladders and repair: otherwise the engine couldn't be repaired.
  So there are never two obstacles to escape at once, the engine doesn't break while a
  console is broken and vice versa.
- **The emergency shutter is a property of the door**, not a separate object: it isn't in the map, every
  door has one (`Doors.locked`). The server drops it based on the pressure difference on the tiles on the two
  sides of the door (`ShipMap.door_sides`) and sends it along with the door. The rule "you can't walk into a locked door"
  lives in `Doors.bump`, because the client predicts it. The client computes the pressure difference itself from
  the air it already knows. This is the only place where the ship
  shows where there is no air: the author asked for this himself.
- **A door's troubles travel in one byte** with it (`Doors.flags`): shutter down, door jammed
  open, shutter faulty. A door jams specifically open: a closed door that won't
  open would be the same to the player as a fallen faulty shutter.
- **The server tells the client about power** (`S_POWER`); the client doesn't infer it from the
  engine's state: power can be lost with an intact engine (the "Power failure" event).
  The server checks it every tick in `Systems.power_changed`.
- **The shutter slams an open door early.** This breaks the "Pitfalls" rule about
  `Doors.HOLD_TICKS`: a player walking into the door at that moment gets a one-step correction.
  Accepted: it happens only with a fresh breach.
- **The air plant** (tile `air_plant`, digit 7) adds air to the tile in front of it
  (`Air.PLANT_PER_STEP`), not above normal, and spends the ship's store on it (`Ship.store_air`).
- **Inventory is six slots, one item per slot** (`Player.slots`, `Net.ITEM_*`). Slots
  travel to the client in the wellbeing record. An item lies in a slot (of a living person or a body), as a count
  in a locker, or on the floor (`GameServer.floor_things`: tile → up to `Net.FLOOR_STACK` items,
  sent by chunks in the `SEC_FLOOR` record and included in the ship checksum).
  Add a new item like this: a number in `Net.ITEM_*`, a line in `Items.INFO` (properties),
  a picture in `ItemArt.draw`, its use wherever it's needed.
- **An item's state is a separate item number** (lit flashlight `ITEM_FLASHLIGHT_ON`), not a
  separate field: that way the state travels with slots, in searches and on the floor by itself. The `kind` property
  says what the item counts as (a lit flashlight in the locker and in counts is a flashlight).
- **The hand is chosen by the client** (`C_HAND`); the server only follows it and doesn't send it back:
  otherwise fast switching would flicker. A taken item goes into the hand if it's empty (`Player.add`).
- **A left click is E on what was clicked** (v45, the author's request): `GameClient.click_facing`
  finds the facing for which `use_target` reaches the clicked cell (current facing first); the screen
  turns the character (`GameClient.face`, a predicted turn), waits until the prediction shows the turn
  (so the press carries a tick after it), then opens the console like the key (`GameScreen._use_screen`)
  or holds "use" while the button is held. A weapon or medical item clicked at a person (or ourselves)
  still fires (`GameScreen._fires_at`); anywhere else the click is the old `send_fire`. No protocol change.
  Test helper: `click=X,Y click_after=S` in `main.gd`.
- **E first targets the object on the wall ahead, then a downed person, then an item on the floor, then a ladder**
  (`Repairs.press`, `Inventory.pick_up`; the client uses the same order in `use_target`). You can't pick up
  an item a person is lying on: E then opens the search.
- **Light is computed per tile** (`Sight.cone`): a tile is lit if it falls into the cone
  even by an edge and the straight line to it doesn't pass through a wall or closed door. That's how tiles
  are lit in SS13, and the same will be used for the field of view. The server doesn't use light yet,
  and the client uses tiles only to decide whether a name is visible. Light is drawn smoothly: the beam is a polygon
  of rays cut off at walls (until v45; since v46 see "Light as in SS13"). Without power the ship is dark: a black cover
  with a shader and an image mask where red marks light; space outside doesn't darken.
- **Darkness is dim, not pitch black** (v45, the author's screenshot; it replaces the v27–v44 rule
  "only the flashlight gives light"). In the dark a red glow `DIM` (0.3 since v46) around our character,
  a `Sight.glow` pool of `DIM_RADIUS` cells, goes into the mask (`WorldView._draw_mask`), so the room is
  made out dimly and the flashlight is clearly brighter. Since v46 the dark sheet itself is not opaque
  (`DARK` alpha 0.93; 0.955 since v47): unlit places stay faintly readable, as in SS13.
- **Deep dark** (v47, the author's word and SS13 screenshot). Out of sight is as dark as unlit (`UNSEEN`,
  the shader mixes it by the green of the mask), whether the place is lit or not; it replaces the v46
  `FOG` (a lit place out of sight was only dimmed to 0.74), so stars and lit rooms behind you are black
  too. Instead a soft pool `NEAR` of `NEAR_RADIUS` cells (`Sight.glow`, stopped by walls) is drawn green
  into `_look` all round our character, and in the dark adds a little red light: that is the SS13 look of
  a player standing in a small pool. Purely client drawing; who is seen is unchanged (`can_see`,
  `Replication.sees`).
- **The smooth cone** (v48, "smoother, like a triangle"). A second picture, `_cone_view`, holds the
  field of view as one soft fan not cut by walls (`CONE_SHADER`, worked out per pixel: a side fades across
  `CONE_BAND` cells at our feet, widening by `CONE_SOFT` degrees outwards), plus the `NEAR` pool;
  the shaders multiply the cells seen (green, worked out `LOOK_MARGIN` wider each side) by it, so walls
  still cut sight cell by cell but the sides are straight and soft. `_draw_light` takes one cell more
  round a light and lets open floor past its edge blend to zero (walls still keep the light up to them).
- **A clean screen** (v47, the author crossed them out): the status lines (`_info`) and the key hints
  (`_keys`) in `GameScreen` are hidden until the `info` action (F1). The frame counter alone stays
  in the top left when it is on in the settings. The first chat line names F1.
- **Light as in SS13** (v46, the author's screenshots). A light is a set of cells with strengths
  (`Sight.glow`: a round pool around a spot ahead of the holder, cells with a clear line from the
  holder, walls lit on a face turned to the light; the old `Sight.cone` is only in tests now). The
  client draws such a set (`WorldView._draw_light`) as a small picture, `LIGHT_SUB` pixels a cell,
  blending between cell middles and zero in cells the light does not reach, stretched with linear
  filtering: smooth falloff, no leaks past walls. The flashlight is `Items.light` = [radius, ahead];
  the server (`Replication._lit_cells`) and the client (`GameClient.lit_cells`) use the same pool, so
  people stood in it are seen. Add new light sources as more `_draw_light` sets.
- **Vision 9 cells** (v46, the author): `Sight.SIGHT_REACH` is 9 (eyes, server visibility, pirates),
  and the camera zoom is the whole number that shows at least `VIEW_CELLS` (9) cells either side across. The look (green) is always the full 160°
  cone now. People in the dark are still judged by the old rule (60°, 2 cells or a light: `can_see`,
  `Replication.sees`), so the dark keeps hiding them.
- **Cells are seen whole** (v42–v43, the author's request): `WorldView._draw_look` keeps the smooth cone
  (rays now stop exactly at a wall's face) and paints as a full tile of green every cell a ray passes or
  stops at whose middle lies inside an eye's arc; our own cell is a square (a disc used to poke into the
  wall beside us). A cell whose middle is outside (the wall right beside us) stays dark beyond the cone. The v38 rule "walls around you always visible" is gone: the author
  found it lit walls behind him and in the pitch dark.
- **Every cell in the cone is checked on its own** (v44, the author's screenshot): the rays of
  `_draw_look` were too sparse to touch a wall seen nearly edge on far down a corridor. Now floor whose
  middle has a clear line (`_clear_to`, cell by cell) and a wall with a face turned to the eye on a seen
  floor cell count too. A wall is never "seen" through another wall (that chained down whole columns
  in a first try). It costs a few milliseconds a frame in software rendering.
- **The light and sight mask** (`WorldView._draw_mask`, `_draw_look`): red is ship light,
  blue is flashlights and flashes (they light only where green is, i.e. where we look), green is
  the field of view. Warm beam light (`_shade`) is also drawn only within the field of view. Whoever disappears
  from view leaves a silhouette for 10 s (`_afterimages`, the author's request, build v30).
- **The server decides who each client sees** (since v39, the author's request). A client is sent
  only the characters its own one sees by the same rules the client draws by (`Replication.sees`
  repeats `WorldView.can_see`: the cone, walls and shut doors, the dark, see-through floors), those
  right next to it (felt: searching and dragging need them, as with pirates), and those on its deck
  with a lit flashlight (the beam is seen from anywhere, and the client draws beams from characters
  it knows). The server's cone is 12° wider each side and a character stays sent 4 ticks after going
  out of sight: the client judges sight on its own predicted clock, so without the margin people
  would pop in late at the edge. One going out of sight is sent as `Net.FACING_HIDDEN` with the cell
  where it was last seen, and the client leaves the silhouette there (`GameClient.hidden`). Bodies are
  characters too and follow the same rule. Shots (`S_SHOT`) and sounds still reach everyone in range:
  they are heard, not seen. Sight is cached per pair until either moves or turns or
  `Replication.sight_changed()` is called; in the dark it is worked out every tick.
  Sight and light are computed by the shared `Sight` code, which pirates also use.
- **Sound travels through air** (I proposed it, the author accepted "silence in vacuum"): `Chat.hears`
  requires air at the source and at the listener, except very close (`SOUND_CONTACT`).
  A sound doesn't say who made it; your own sounds aren't sent. Only your own deck is heard.
- **A shot is instant, with time rewind** (`Combat.use_at`, `Combat._shoot`, `Combat.place_at`):
  the client sends the tick at which it saw the others, and the server checks the hit at that position.
  Bullets are stopped by any impassable tile, including a window (`Combat._stops_shot`).
- **A fatal wound takes health one below −100**, otherwise the next breath of good
  air would "resurrect" the dead. A pirate killed in this tick no longer thinks.
- **Wounds are separate from health** (`Player.wounds`, groundwork for the author's item 2.1: damage types).
  Health rises by itself only up to `100 − wounds`; wounds are closed only by healing
  (`Combat.heal`). The medkit heals with a delay (`Combat.update_treatment`, progress shows as
  the work bar); its charges are part of the item number, like ammo. Only whole items
  go back into the locker (`Items.whole`), so a used medkit can't be swapped for a new one.
- **Pirates are ordinary Players with the `pirate` flag** (kind in the list `KIND_PIRATE`, colors are three
  rows of `chars.png` after the crew colors). They breathe on their own (sealed suits). All their
  behavior is in `src/server/pirates.gd`; they pathfind over the grid with ladders, around fallen shutters.
- **Boarding** doesn't repeat while a living pirate is aboard; an unarmed crew gets it
  half as often and with one pirate fewer.
- **Searching and dragging** work only with a downed person (unconscious or dead) in your own
  or a neighboring tile. Presses carry the client's tick number, like the ladder
  (`Looting.hands_asked`). A search works as a subscription: the server sends the downed person's slots while
  the searcher is near (`S_SEARCH`), and closes it itself.
- **The dragger walks half as fast** (`Mover.State.slow`, `Net.DRAG_TICKS`): this is part of the movement
  rule, and the client predicts it. The flag travels in the character's look byte (`LOOK_SLOW`),
  so others' steps are drawn at the right length too. The body moves into the tile the dragger
  left (`Looting.haul`); on the dragger's screen it is drawn in step with their own steps
  (`GameClient.sample`), otherwise it would lag by the ping.
- **The ship's store is shared and lives in the supply locker** (tile `locker`, digit 8): patches,
  spare parts, air for the plant, credits (`Ship.store`, `Ship.store_air`, `Ship.credits`). The locker opens with a panel, like consoles, but without power; buying from the trader goes through
  the same panel and requires power. I designed this; the author approved the step's whole concept.
- **Without a spare part you can repair, but three times slower**, and without a patch a breach can't be sealed.
  So a ship with a dead engine and an empty locker doesn't hit a dead end, while losing
  compartments stays real.
- **Fuel is an item in the supply locker** (`Net.ITEM_FUEL`), not a separate number: that way the trader
  sells it automatically, it lies as loot on other ships, it can be carried away and put
  back. A jump checks for a canister when ordered and burns it at the moment of the jump
  (`Navigation.update_jump`); if the last one is removed during charging, the jump fails.
  No dead end: with not a single canister aboard, after 2 minutes the director itself gives the event
  «Дрейфующее топливо» ("Drifting fuel") (`Director._watch_fuel`); a station tops up to 3. I decided this.
- **Crew reserve** (`GameServer.reserve`): R costs a person (`Crew.respawn_from_reserve`);
  a dead player who left and came back under the same name also costs one (`_dead_names`, the check
  in `Crew.hello`). If the reserve is empty and there are living crew, they aren't let in (`REJECT_NO_CREW`): otherwise
  leaving and rejoining would bypass the reserve. New names come free. I decided this.
- **Campaign end** (`Crew.end_campaign`): hull at zero or all players dead with an empty
  reserve (`Crew.check_crew`, once per second). The game freezes: the director is silent, no jumps,
  everyone gets the summary screen. There is no live restart: the host creates a new game. It's simpler
  and more honest; I decided this.
- **Jobs and access**: access is a bitmask (`Net.ACCESS_*`, `Net.JOB_ACCESS`); a
  door's is `ShipMap.door_access` from lines `@ deck x y access` in the map (compartment fill
  in `make_assets.py`). The check is in the shared `Mover.step` via `Doors.barred`, so the client
  predicts it; the client learns its own mask from the `S_ME` packet. Without power locks don't
  work (the escape-route rule); a lock is hacked in 5 s with a ship-wide announcement.
  Spawn points are moved out of locked compartments (checked by `crewtest`).
  Bots and pirates go everywhere. I invented the skill numbers.
- **Speech** (`Chat.talk`, `Chat.hears_said`): the channel is chosen by a sign at the start of the line
  (`;` radio, `!` intercom), to avoid multiplying keys; `S_CHAT` carries the channel number.
  Spoken aloud — by the same air rules as sounds (`Chat.hears_voice`). The dead talk among themselves.
- **Saving** (`src/server/campaign.gd`): one JSON in `user://`, written to a temporary file
  and renamed. Characters are stored by player name (`saved_crew`); the living character of a player
  who left also goes there, so you can leave and rejoin the same evening. Another ship
  alongside, pirates and the director aren't saved. Tests and nettest don't write a save
  (`save_path` empty, `campaign=off`). The host also saves manually (Esc, `Net.ADMIN_SAVE`):
  the author didn't find a button and decided there was no saving, so it's shown in chat.
- **Sounds are made in code** (`src/client/sounds.gd`) from noise and tones: no files and no others'
  licenses (TauCetiClassic is only for ideas, as the author said). Muffling is the
  `Muffled` bus with a low-pass filter, if the source isn't visible or the air around is thin.
- **Credits are given for the first jump into a sector.** This is an economy placeholder: there's no other income.
  In infinite space this income never runs out, and there's a trader in roughly every
  fifth sector.
- **The director watches the store:** with not a single patch aboard, breaches are three times rarer
  (`Director._weight`). This is the first "equipment scan" from the vision.
- **The action hint** sits between the chat and the instruments and wraps by words
  (`HINT_LEFT`, `HINT_RIGHT`): otherwise long lines overlapped the chat.
- **Machine state is visible as light on the floor** (`WorldView._draw_fx`): so it can also be seen through
  the glass floor from the upper deck. That's why the engine stands under the bridge glass, and the plant
  under the corridor glass.
- **Transparent floors are tile kinds:** `glass` (visible, air doesn't pass), `grate` (catwalks:
  visible, air passes), `hatch` (hatch with a ladder: visible, air passes, can go down),
  `ladder` (bottom of a ladder). `make_assets.py` draws them from each floor piece, cutting out
  the middle. That air goes through catwalks and not through glass was my decision; the author didn't specify it.
- **Ladder by the action key:** stand on the tile and press E. Climbing isn't predicted by the
  client. The press carries the tick number by the client's clock, and the server checks the ladder at that
  tick: otherwise with ping the press arrived when the server hadn't yet brought the character to the tile.
- **What's visible through the floor:** the lower deck is drawn in full under the current one and darkened;
  the current deck's floor covers it everywhere except transparent tiles. From the deck above, only those
  standing on a transparent tile are visible. Names are hidden along with their owners (`GameClient.seen_from`).
  The client still knows everything about the other deck: this doesn't protect against peeking.
- **Air between decks** flows half as fast as along a deck (`Air.FLOW_DECK`): a tile now
  has up to six neighbors, and with the old coefficient the computation would start to oscillate.
- **Space is infinite and stored nowhere** (`src/shared/sectors.gd`). Sectors sit on a grid
  without edges; a sector's contents are computed from its position and the game's number (`space_seed`), so
  the same place is always the same. `Sectors` keeps only a 7×5 window around the ship;
  the server rebuilds it on every arrival and sends it in full (`S_SECTORS`), and sector
  numbers on the network are numbers within the window. Only where the ship has been is remembered (`GameServer.been`).
- **Routes:** every sector has a mandatory route north or east, plus
  one in each direction with probability 0.3. The mandatory route guarantees there are no
  dead ends or closed pockets; there are never more than four routes (that's how many jump
  buttons fit on the console).
- **Difficulty grows with distance:** the share of meteor streams goes from 20% at the start
  to 45% (`Sectors.NEAR_METEORS`, `FAR_METEORS`, `MOST_METEORS`). I decided this; future threats
  should be tied to it too.
- **The director** is in `src/server/director.gd`. A new event: a line in `EVENTS`, a branch
  in `_run` and a branch in `_can_happen` (an event isn't chosen if it would change nothing;
  limits are in `Systems.can_break`). "Scanning" the ship and crew is the `assess` function; add there
  what the director looks at. Pacing is checked by `tools/directortest.gd` without waiting.
- **The game host is also the GM:** commands to the director use the same secret pass
  as stopping the server.
- **Lack of air is not drawn.** The author asked to remove the darkening of compartments to make it
  harder: the player sees only the pressure in their own tile. Air wisps right at the breach
  remain. Don't add hints about air without his word.

- **Game ship `ship02`, tests on `ship01`:** the coordinates in tests are tied to the old map,
  so it remains. The airlock is checked by `tools/locktest.gd` on `ship02`.
- **The two-door airlock** is found by its pump (tile `lock_pump`, digit 9): the chamber is the floor
  in front of the pump up to the doors, the outer door is the one with space behind it (`ShipMap.door_vent`).
  The rule "only one open" lives in `Doors.bump` (`partner`); the client predicts it.
  The interlock is released manually (E for 3 s, `Doors.forced`, bit 3 in the door's trouble byte): without it
  a jammed outer door locked the chamber forever (softlock, found by the author in v32).
  There's no separate locking logic: emergency shutters treat space as pressure 0, so they
  hold the outer door themselves when there's air in the chamber and the inner one in vacuum. The pump
  (`Systems.toggle_pump`, `Systems.run_pumps`) moves air into the ship's store and back;
  its operation travels in `S_DEVICES` after the list of broken things. An open outer door
  vents the air in its doorway (`Air.VENT`).

- **A derelict ship is placed in the same grid** (`ShipMap.add_other`, `place_other`): its
  blueprint is `maps/derelict01.txt`, its door numbers are kept at the end of the door list, and `base_*`
  holds our ship without it. There are 10 empty rows above our ship for this. Where it lies,
  the server sends via `S_OTHER`; everything else (items, breaches, air, doors) goes in ordinary
  chunk records. The logic is in `src/server/derelict.gd`: it stands `GAP` tiles above the airlock
  or is docked door to door (it shifts with everything on it). Items left
  on it are remembered per sector. It has no power: doors are manual (`Doors.dead`), it's dark.
- **There are several kinds of other ships** (`Net.OTHER_MAPS`: derelict and pirate); all lie
  in the same place in the grid (`ShipMap.others`, `place_other(at, kind)`), with shared door
  numbers. The pirate ship is the same `derelict.gd` module: it comes alongside, after
  `PIRATE_WARNING_TICKS` docks by force, jams both airlock doors open and releases
  pirates (`pirates.spawn`); it has power and light. Its tiles are the same tiles
  recolored by the script (`pirate_*`; the `pirate*` map lays them out itself).
- **Ship weapons** are in `src/server/gunnery.gd`: guns are `gun` tiles in the hull (sign `T`
  in the map, `ShipMap.guns`), the console is `console_4` (`ShipMap.gun_console`). State travels
  in the `S_GUNS` packet on change. Combat happens only while the pirate ship stands alongside
  and isn't docked (`fighting`): it shoots at us, we at it; 6 hits and it's wrecked
  (`Derelict.pirates_wrecked`), 25 credits. This is the second source of credits after exploration.
- **Aiming at the enemy's systems** (v41, the author's request). The pirate ship's rooms are named by
  lines `% deck x y system` in its map (`ShipMap.zones`, `Net.ESYS_*`): weapons, bridge, engine, quarters, jump drive (v44).
  The aim is one per ship (`Gunnery.aim`, `C_AIM`), not per gun, so everyone at the console sees the same.
  A hit takes 1 from its hull and 1 from the system in the room it lands in (a random room without aim),
  and holes its hull next to that room. Effects: weapons out = it does not shoot; bridge out = it hits
  half as often and we hit 95%; engine out = the docking countdown stands still; quarters: every 2 hits
  kill a boarder, none left = it breaks off unpaid. Its crew mends the worst system by 1 every 15 s.
  I chose these numbers and effects; there are no shields in the game, so no shield system.
- **Two pirate-ship events** (v44, the author's request): `PIRATE_SHIP` boards as before; `PIRATE_RAID`
  (`Derelict.raid`, `Gunnery.raid`) never docks. The enemy runs when its hull is at `FLEE_HULL` or its
  guns are out at half hull: `Gunnery.flee` counts the jump charge, its pace is the jump drive's
  strength share (`Net.ESYS_JUMP`, a fifth room in `pirate01`), nothing with the drive or engine out.
  A wrecked raider stays as `Net.SHIP_WRECK` (dark, doors dead, `Derelict.dark()`), dockable, and leaves
  when our ship moves. Who is aboard is rolled at wreck time (`Derelict.WRECK_ALL_DEAD` 70%, the rest
  half fight, half join the reserve) and shown to the first of the crew aboard (`_watch_boarding`).
  Defaults I chose: flee threshold, 50/50 for fight/join, joiners go into the reserve, worn drive =
  slower charge in proportion. Either enemy is left behind when our ship jumps to another sector.
- **The holomap** (v41, tile `holo`, sign `M`) is the one exception to "lack of air is not drawn": the
  author asked for a monitor that shows where the pressure is. It is a console one must stand at, with
  power. A client knows the air only around itself, so the server sends `S_HOLO` (air of every floor cell
  of our ship in `ShipMap.on_ship` order, holes, door states) twice a second only to those watching
  (`Holomap.watching`), and stops when they step away or the power goes. No new gas mechanics.
- **The ship's store window** (`StoreView`) and the gun and holomap screens (`GunsView`, `HoloView`) live
  inside the console frame of `GameScreen` (shown instead of its chart, text and buttons), so the old
  rules for consoles hold: E or Esc closes, stepping away or losing power closes.
- **Open space is passable** (`ShipMap.floats`, `Mover`): within the grid and deck rows,
  a step takes twice as long, there's no air. While someone alive is outside or the ships are docked,
  the ship doesn't move or jump (`Derelict.holds_ship`), and a started jump fails.
  I decided this: we don't abandon anyone. Bots and pirates don't go into space.

- **Ship weapons, power and shields** (v49, the author's request; `src/shared/weapons.gd` holds every number
  the server and the client share). A gun mount (`ShipMap.guns`) holds a weapon (`Ship.mounts`), powered or not
  (`Ship.armed`); a weapon off its mount is cargo: the item `Net.ITEM_GUN + Weapons.*` in the locker, with
  `Items` "cargo" (never carried, `STORE_TAKE` refuses it). Rockets are cargo items too. The reactor gives
  `Weapons.REACTOR` (8) to the guns and the shield (2); I chose the numbers. Set-up goes by `C_GUNSET` from
  the gun console. Shields follow the author's rule exactly (holds at 50+, below lets through with chance
  (50 − level)/50); rockets pass unless `Ship.hardened`, half the blaster's pellets pass, ion only wears
  the shield and puts a system out (`Ship.jammed` for ours, `Gunnery.systems_out` for theirs). Our generator
  is the `shield` tile ('Z'); theirs is the sixth room `Net.ESYS_SHIELDS` (70% of pirates have one). Our
  shield falls to 0 without power, broken or switched off; ionised it keeps its level but does not protect.
  Enemy guns are a loadout from `Gunnery.ENEMY_*`, each charging on its own (1.3× slower than ours).
  Weapons from `Weapons.TRACTOR` on are the items `Net.ITEM_GUN_MORE + w` (the rockets hold 61 and 62);
  always go through `Weapons.item_of`/`of_item`, never `ITEM_GUN + w`.
- **The trader's offers are made by the server** (`Supplies.offers`, `S_TRADE`), seeded by the game and the
  place, so the same trader always has the same 4 ship weapons and, 30% of the time, the hardening. Selling
  is from the locker at half price (`Weapons.SELL_SHARE`). The trader's window is `TradeView`, opened from the
  locker's window (`GameScreen._show_trade`).
- **Admin rights** (`src/server/admin.gd`, since v40). The host's game proves itself with the
  server's secret text (`ADMIN_HELLO` right after joining; `Player.host`), and only the host makes
  others admins (`ADMIN_GRANT`), by player name (`Admin.names`, kept in the save). Others send
  `C_ADMIN` with no text; the server checks `Player.admin`. The client learns its rights from the flags
  byte at the end of `S_ME`. The author asked for an admin panel "for all tests"; I decided that
  healing raises the dead where they lie, and that a body left after a return from the reserve stays a body.
- **The player's settings** live in `user://options.cfg` (`src/client/options.gd`), not in the menu's
  `settings.cfg`, which the menu rewrites whole. Every key is an action in `Options.ACTIONS` (two keys
  each, physical keycodes, optional Ctrl/Shift/Alt). Check keys with `Options.pressed` and `Options.held`,
  never `is_action_pressed`: a bare key also works with a modifier held unless that exact combination
  is another action's. Text on screen is written with the default letters and passed through
  `Options.keyed`, which puts the player's keys in their place. Sounds go to the `World` bus and the
  engine hum to `Hum` (both made by `Options.ensure_buses`).
- **Windows over the game** (inventory, admin panel) do not take the keyboard: their buttons have
  `FOCUS_NONE`, so the character walks while they are open. The settings window and the menu do take it.
- **Own footsteps** are played by the client only in air (`Net.SOUND_AIR`) and never in open space:
  the author's rule that vacuum is silent (they were heard muffled until v40).

## Pitfalls

- `ENetConnection.service()` with a non-zero timeout spins the CPU the whole time.
  Poll with `service(0)`.
- The server won't read a message immediately followed by a disconnect: on
  disconnect ENet throws away unread data. So the client waits for the server to disconnect it itself
  (`stop_server_and_close`), and the server waits for the goodbyes to go out before closing.
- `peer_disconnect_later()` doesn't fire under a continuous stream of reliable packets
  until the host closes. Use `peer_disconnect()` and service the host to the end.
- `(array[i] as PackedByteArray).append_array(...)` modifies a copy. Take the element
  into a typed local variable.
- `set_anchors_preset()` doesn't move an already placed element; use
  `set_anchors_and_offsets_preset()`.
- Frames in a sprite sheet must have a transparent border, and the world must sit on whole
  screen pixels. Otherwise in an odd-sized window the GPU grabs the neighboring frame.
- Command-line export requires the folders `build/windows` and `build/linux` to exist.
- `OS.is_process_running()` on Windows only knows processes the game created itself.
- The client clock for prediction takes the freshest of recent readings, not the average:
  a delayed packet otherwise slows the clock, and commands start arriving late.
- Characters are not sent through per-chunk change lists any more (since v39): each client has its
  own list of what it was told (`Player.known`), and the server sends the difference every tick
  (`Replication._characters`). The old pitfall (a ladder and a step in one tick left others seeing
  the character on the old tile) cannot happen this way. Doors, holes, floor and air still go by chunk.
- Whatever changes what blocks sight must call `Replication.sight_changed()` (doors opening and
  shutting, power, the other ship moving already do): who sees whom is cached until then.
- A Control that draws on another one from a method named `_draw` also runs it for itself, and
  Godot complains ("Drawing is only allowed inside this node's `_draw()`"). Name it otherwise.
- Pirates are Players too: whatever counts the crew must skip `p.pirate` (and `p.bot`, `p.corpse`).
  The director counted boarders as crew until v40's fix, so it let holes pile up past its limit
  after a boarding (`directortest` failed now and then).
- A node with a negative `z_index` is drawn under what its parent draws itself (the stars
  in `WorldView._draw`). So decks are ordered with non-negative numbers.
- Air falls asleep (`Air.settled`) while a door is still opening: it must also be woken
  on the tick the door became passable (`Systems.update_doors`), otherwise air won't flow through it.
- A test that crashed with a script error doesn't exit by itself and hangs until the timeout, and its output
  through a pipe is lost. Run with `timeout` and output to a file.
- A door must stay open longer than the stretch the client replays
  on a correction (`Doors.HOLD_TICKS`, currently 2 seconds).
- Console screens that build many controls (`GunsView`, `TradeView`) are set up when first opened, not
  when `GameScreen` is built at joining: in v49 building them at joining cost ~60 ms and doubled the
  corrections in nettest (the same clock pitfall as below).
- Long client work at the moment of joining the game (as with creating sounds in `WorldView._ready`)
  knocks its clock off relative to the server, and the first steps get corrected. So sounds
  are made in advance while the menu is open (`Sounds.prepare` in `main.gd`).

## Delivering builds

- A file up to 30 MB goes through chat, and the Windows game weighs 36 MB archived. So it
  is split into `game.001` and `game.002` in two archives; `play.bat` joins them and checks
  the size. The size in `play.bat` is updated with every build.
- Builds aren't stored in git: the exe is larger than 100 MB. The author was offered to publish them
  in the Releases section as one archive; no answer yet.

## Not yet verified

- The server as a separate process on Windows: verified only on the Linux build. In case
  of failure there's a fallback (server inside the game).
- Playing over the internet with an open port: the author has only played over Radmin VPN.
- Whether the bar above characters' heads disappeared on the author's GPU.
- How transparent floors look on the author's GPU (verified only with software rendering).

## Graphics

- `art_src/` holds the author's references. `map_mockup.png` is scaled 2×; the 32-pixel grid
  starts at an offset of 5.5. `chars_ref.png` has one angle and cropped legs, so the crew
  is drawn in code for now. `hud.dmi` has 20 unnamed states; which is which is recorded
  in `tools/make_assets.py` (`HUD_ALERTS`).
- Everything in `assets/` and `maps/*.json` is built by `tools/make_assets.py`. Don't edit it by hand.
- The map is drawn by decks, the top one first; each starts with a line `= name`.
  New signs: `g` glass, `c` catwalks, `H` ladder (in one tile of two adjacent decks),
  `6` engine, `7` air plant, `8` supply locker (a wall, like consoles; the script draws their tiles),
  `I` intercom, `M` holomap. A line `% deck x y system` names the room of an enemy ship's system. A line `@ deck x y access` makes a compartment locked.
