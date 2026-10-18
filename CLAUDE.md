# Spacer: working notes

Notes for continuing work in a new session: agreements, the order of checks, how the code is laid
out and its pitfalls. What the game is and how to open it is in `README.md`. Read only what the task
needs:

- **`docs/VISION.md`**: how the author sees the game's future, in his own words. Make decisions with
  it in mind; when the author adds to the vision, write it down there.
- **`docs/MECHANICS.md`**: every mechanic in the game, with numbers (the author's request). Update it
  in every build that changes something for the player, with the build number in its header. **In the
  same step update the author's document "Spacer: механики игры"** (Spacer: game mechanics) in Claude
  Docs (https://claude.ai/artifact/CkpfXu7j25QbPqTijemas6, project
  `5f32e1ae-d2f4-4651-9d5a-aca9b95268ad`) in the same shape, with the Claude Docs tools; read it first,
  the author may edit it himself.
- **`docs/DECISIONS.md`**: why each mechanic and piece of code is the way it is (the author's word or
  mine, the numbers chosen). Search it (`grep -n`) for the mechanic before changing it, and add a
  decision there whenever you make one.
- **`docs/HISTORY.md`**: the plans the author accepted and what each build did.
- `docs/BENCHMARK.md`: server load measurements.

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

## Where things stand

Build v60 (version 0.53) is the latest. Plans one to four are done except the darkness front (the
author is still thinking it through); builds v40 to v60 were the author's own requests, one build each.
v58 and v59 built the gear tiers plan (`/mnt/project-files/plans/tiers-plan.md`): guns in v58, ship gear
(systems' tiers, the module bay, armour, focusing array, phase drive) in v59. v60 began the road plan
(`/mnt/project-files/plans/road-plan.md`): crew at work (gunners, carried guns, bots at work, medbay, blast doors);
v61 power (SMES), v62 enemies, v63 road and story come next. Several reactors is a later
question round (it breaks the one-engine rule).
The next plan comes from new questions to the author (see "What may come next" in `docs/HISTORY.md`).
Engines and complex atmosphere (gases, fire, electricity) only after asking the author in detail.

The author's standing rules (details in `docs/DECISIONS.md`):
- Bodies remain after death. R returns a dead player as a new crew member from the reserve.
- The engine powers the whole ship: when it stops, every system stops but nothing breaks. Anything new
  aboard asks `GameServer.powered()` (client `GameClient.powered()`).
- While any bridge console works there is a way to escape; there are never two obstacles to escape at once.
  Except against the flagship (v57): "you win or you lose, no other exit".
- Lack of air is not drawn (only the holomap shows pressure, at his request). Vacuum is silent (the listener
  needs air), but the ship fight is heard aboard and blows to the hull shake the screen (v56).
- The dark is dim, not pitch black: the room in view is made out, the flashlight is clearly brighter.
- Each step adds items at the trader. The author's sub-items (1.1, 2.1 ...) are groundwork for later.
- Changes are gathered into one Windows build. Pull requests may be merged without asking once CI is green.

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

    tools/runtests.sh          (all 22 scripts below in a row; GitHub Actions runs it on every push)
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
    godot --headless --path . --script res://tools/shiptest.gd  (rolled pirate ships, scanning, the probe)
    godot --headless --path . --script res://tools/dronetest.gd (since v54: the pirates' crew, the drone, ransom)
    godot --headless --path . --script res://tools/stationtest.gd (since v55: our posts, bot orders, position, boarding)
    godot --headless --path . --script res://tools/flagshiptest.gd (since v57: the goal, both flagships, win, capture)
    godot --headless --path . --script res://tools/tiertest.gd (since v58: gun tiers, kinetic guns, point defence, loot, traders, workbench)
    godot --headless --path . --script res://tools/geartest.gd (since v59: ship gear, installing, module bay, armour, focus, phase drive)
    godot --headless --path . --script res://tools/worktest.gd (since v60: gunners, carried guns, bots at work, medbay, blast doors, ammo)
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
the server gets CPU 0 to itself; it also prints where the tick time went (players, ship, air, sight,
sending). Results are in `docs/BENCHMARK.md`. Sight alone, without a network:
`godot --headless --path . --script res://tools/sightbench.gd -- 32 400` (bots, ticks).
How long ship fights last, per class and temper (since v54; rerun after changing fight numbers):
`godot --headless --path . --script res://tools/fightbench.gd -- 4 0 10 1` (fights per cell, jumps out, our mend seconds,
1 = a pilot at the controls). Runs side by side need different mend seconds or jumps out: they pick the port.

GitHub Actions (`.github/workflows/tests.yml`) runs `tools/runtests.sh` on every push and pull
request. A red check on GitHub means one of the 22 scripts failed; its log is attached to the run.

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
  `supplies`, `replication`, `holomap` (plus the older `director`, `pirates`, `derelict`, `gunnery`, `campaign`,
  and `shipyard`, which rolls every pirate ship since v53; since v54 `enemy_crew`, the pirate ship's crew at
  their posts, and `drone`, the scouting drone; since v55 `stations`: our crew at posts, bot orders, the
  battle position, our boarders; since v57 `flagship`: the goal of the game, the boss fight, win and capture; since v58
  `workshop`: the workbench; since v59 `outfit`: the ship's gear, its effects and installing it; since v60 `mounts`: gunners and carrying guns
  onto mounts, `medbay`: autodocs and the scanner, `blast`: blast doors).
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

## Where the code is

- `src/main.gd`: start-up, command-line options for tests and screenshots (listed in its header).
- `src/shared/`: what both sides use. `net.gd` (protocol, ids, constants), `mover.gd` and `doors.gd`
  (predicted rules), `ship_map.gd` (the grid, decks, tiles), `sight.gd` (sight and light), `items.gd`,
  `weapons.gd`, `sectors.gd`, `hulls.gd` (pirate ship classes and tempers), `gear.gd` (v59: crates of ship gear).
- `src/server/`: `game_server.gd` (state, network loop, tick order) and one part per topic (see
  "How it works"); `player.gd`, `ship.gd`, `air.gd`, `vitals.gd`.
- `src/client/`: `game_client.gd` (network, prediction, what the client knows), `world_view.gd` (the
  world, light and sight drawing), `fight_fx.gd` (v56: ships' shots flying and bursting), `sounds.gd` (any
  sound can be replaced by `sounds/NAME.ogg|wav` next to the game), `options.gd`, `item_art.gd`.
- `src/ui/`: `game_screen.gd` (HUD, chat, the console frame), console screens `bridge_view.gd` (chart and
  helm), `store_view.gd`, `trade_view.gd`, `guns_view.gd`, `holo_view.gd`, `drone_view.gd` (`enemy_plan.gd`
  draws the enemy ship's plan for the last two consoles' screens); `inventory_panel.gd`, `crew_panel.gd` (v55, key O),
  `admin_panel.gd`, `options_panel.gd`, `main_menu.gd`, `bench_view.gd` (v58, the workbench).
- `tools/`: tests (`*test.gd`, `runtests.sh`, `nettest.sh`), `bench.sh`, `sightbench.gd`, `fightbench.gd`, `lagproxy.rs`,
  `make_assets.py`, `fxshot.gd` (v56: a picture of the fight's effects, `godot --path . --script res://tools/fxshot.gd -- OUT.png`
  under xvfb-run). `maps/`: ship blueprints (`*.txt`, built to `*.json`).

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
- The pirate ship's own crew during a fight are not Players (v54): they are cells of its drawing in
  `EnemyCrew`. Their count must stay equal to `Gunnery.boarders_left()` and `Derelict._pirates_party`:
  kill them through `Gunnery.crew_hit` or quarters hits, which keep all three in step. Since v55 they become
  Players once one of ours boards (`EnemyCrew.in_world`); then `Stations._boarding` calls `Gunnery.crew_lost`
  each tick to keep the counts in step, and nothing may spawn them again (docking, the wreck).
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
- Lines of sight are remembered by cell pair (`Replication.lines`, `Sight.clear_cached`: walls only, the
  doors on the way are looked at each time). Whatever changes the shape of the grid must call
  `Replication.index_doors()`, which forgets them (`Derelict._place` does).
- The client redraws the light mask and the field of view only when their key changes (`mask_key` in
  `WorldView._update_ship`, `look_key` in `WorldView._process`). Whatever new changes what they draw
  must go into the key, or the picture stays stale. Pictures of light are kept per light
  (`_light_made`) the same way.
- `GameClient.glow` returns remembered dictionaries shared between callers: read them, never change them.
- (v58) A ship gun's state is in its item id (`Weapons.item_of`/`of_item`): never compare a stored gun with
  `ITEM_GUN + w` directly, and use `Weapons.of_item(item) != Weapons.NONE` to ask "is it a gun". The gun console's
  `GUNSET_MOUNT` takes an item id (with its effect), and `Net.GUARD_MOUNT` as the mount means the point defence.
- (v58) `Items.INFO` and `Items.CATEGORIES` are static vars built at load from `Items.BASE` and the guns; add
  plain things to `BASE`.
- (v59) Whatever the gear changes asks `server.outfit` (`reactor()`, `shield_regen()`, `hardened()`, `jump_share()`,
  `hull_share()`...), never `Weapons.REACTOR` or `Weapons.SHIELD_REGEN` for our ship. After changing `Ship.gear` or
  `Ship.modules` by hand (tests, saves) call `outfit.refresh()`: it sets `Ship.armour` and cuts guns the reactor no
  longer feeds. `Outfit.can()` and `GameClient.gear_here()` must give the same answers (hover hints).
- (v59) A test holding "use" at a machine must let go once the gear went in: with empty hands at the bay the
  same hold starts taking the last module out.
- (v60) The server must not change a player's `hand` (the client keeps its own and is not told): `Mounts.finish`
  puts the gun into the hand slot already chosen. Only bots get their hand set by the server.
- (v60) Bots are kept at `GameServer.crew_size` (bots asked for + 1) by `Crew._bot_makes_way`/`_bot_takes_over`
  on join and leave; tests that add players with `new_player` skip it.
- (v60) A blast-locked door (`Doors.blast`) is checked in `Mover.step` through `Doors.blocks(door, access)`; our
  people and bots carry `Net.ACCESS_OURS` (`Net.access_of(job)`), never compare `Net.JOB_ACCESS` with access any more.
- Ships' shots land later than they are fired (v56, `Gunnery._flying`). A test that checks a hit right after
  `fire` or `_enemy_fires` must set `server.gunnery.flies = false` (the gun, ship, drone and station tests do).
  Effects that are only drawn take their lots from `Gunnery._fx`, so the game's own rng sequence is unchanged.

## Delivering builds

- The archive's first part carries `dist_files/sounds/README.txt` as `sounds/README.txt` (v56: the names of
  the sounds the author may replace).
- A file up to 30 MB goes through chat, and the Windows game weighs 36 MB archived. So it
  is split into `game.001` and `game.002` in two archives; `play.bat` joins them and checks
  the size. The size in `play.bat` is updated with every build.
- Builds aren't stored in git: the exe is larger than 100 MB. The author was offered to publish them
  in the Releases section as one archive; no answer yet.

The order of a build: code → `godot --headless --path . --import` → all checks above →
`docs/MECHANICS.md`, the Claude Docs document, `dist_files/README.txt` (CRLF line ends, BOM),
`config/version` in `project.godot` → export (create `build/windows` and `build/linux` first), the
size in `play.bat`, two archives in `/mnt/project-files/builds/vNN/` → a paragraph in
`docs/HISTORY.md` → commit in English, push the branch, pull request, merge when green.

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
  `I` intercom, `M` holomap, `5` drone monitor (v54), `B` workbench (v58), `U` module bay (v59), `Y` autodoc, `X` body scanner (v60). A line `% deck x y system` names the room of an enemy ship's system (used only by
  the classic pirate01; rolled ships put systems in rooms by lot, see `docs/DECISIONS.md`). A line `@ deck x y access` makes a compartment locked.
