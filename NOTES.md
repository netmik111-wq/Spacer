# Spacer — summary for continuing the work

State as of build **v41 (version 0.34)**, 14 October 2026. Details: `CLAUDE.md` (decisions, pitfalls,
check procedure), `docs/MECHANICS.md` (all mechanics with numbers), `docs/VISION.md` (the author's vision).

## Links
- Repository: https://github.com/netmik111-wq/Spacer (branch `main`).
- Document «Spacer: механики игры» ("Spacer: game mechanics"; Claude Docs, update with every build):
  https://claude.ai/artifact/CkpfXu7j25QbPqTijemas6 (project `5f32e1ae-d2f4-4651-9d5a-aca9b95268ad`).
- The author's survey «Spacer: куда дальше» ("Spacer: where next"; answers in the db, collection `survey`, document `answers`):
  https://claude.ai/artifact/WkAgPwZZ2Xpwv25kzHLcs5 — read `ArtifactData get survey/answers` and build the fourth plan.

## Key decisions
- Godot 4.7.2 (GDScript, Compatibility), own protocol on ENet (`Net.PROTOCOL` = 27), the server decides everything,
  20 ticks/s, one thread; the client predicts movement and doors (`src/shared/`), checked against checksums.
- Builds for Windows only (the author plays over Radmin VPN); the exe is split into two archives, `play.bat` joins them.
- Everything on GitHub (docs, notes, code comments, commit messages) is in English. What the player sees in the game stays in Russian; the author chose this on 2026-10-14 ("GitHub only").
- The author's rules: air is not highlighted; bodies stay; the engine powers everything; it is silent in vacuum;
  in the dark only the flashlight shines; while at least one bridge console is intact, there is a way to escape.
- Atmosphere with gases, fire and electricity only after asking the author in detail.

## v41 (ship's store, gun targeting, holomap; the author's request)
- The supply locker opens a "ship's store" window (`src/ui/store_view.gd`): resources across the top, every
  item as a card with its count, take with a click, buy with a right click, put back one thing by its slot
  (`Net.STORE_PUT_ONE`).
- The gun console (`src/ui/guns_view.gd`) shows the pirate ship's plan by rooms; the guns aim at one of its
  four systems (weapons, bridge, engine, quarters; `Net.ESYS_*`, rooms named by `%` lines in `maps/pirate01.txt`).
  Hits wear a system down and knock it out; its crew mends it. Server side in `src/server/gunnery.gd`.
- Holomap monitors ('M' in the map) on the bridge and in the engine room (`src/server/holomap.gd`,
  `src/ui/holo_view.gd`): the whole ship's air, breaches, broken machines and doors, sent only to whoever
  watches. New test `tools/holotest.gd` (15 tests now).

## v40 (friendly interfaces, the author's request)
- Inventory window (I/Tab, `src/ui/inventory_panel.gd`), settings window with sound, picture and keys
  (`src/ui/options_panel.gd`, `src/client/options.gd`, `user://options.cfg`), admin panel in four tabs
  (`src/ui/admin_panel.gd`, server side `src/server/admin.gd`, test `tools/admintest.gd`).
- Own footsteps are silent in a vacuum and in open space.

## v39 (engineering build)
- `game_server.gd` is split into modules by topic (`chat`, `crew`, `movement`, `inventory`, `looting`, `combat`,
  `repairs`, `systems`, `navigation`, `supplies`, `replication`); ships are `Ship` objects with a network id (`S_SHIPS`).
- The server decides who sees whom and sends each client only those characters (`Replication.sees`).
- All 13 tests run on every push (`.github/workflows/tests.yml`, `tools/runtests.sh`).
- Benchmark: `tools/bench.sh`, numbers in `docs/BENCHMARK.md`. Visibility made ticks ~3-6x dearer (32 players: mean 10.7 ms of 50).
- Still one crewed ship per server, though the code now keeps ships as objects.

## What the game has
- Ship `ship02`: 2 decks, bow on the right, bridge (chart, helm, gun console), a two-door airlock
  with a pump, 3 guns, engine room, life support, a hold with the supply locker. `ship01` is for tests only.
- Per-cell air, hull breaches, doors with emergency shutters, power, breakdowns and repair (spare parts, patches).
- SS13-scale health, wounds, healing (plaster, medkit), the space suit as clothing (oxygen in a tank),
  jumpsuit (+2 pockets), backpack (+4), 12 slots in total; items on the floor, searching, dragging.
- Field of view (160°, 60° in the dark), flashlight 35°/9 cells, pitch darkness without power, silhouettes of those
  who left view for 10 s, sounds as icons (through air), turning instantly and by mouse click.
- Combat: pistol, baton, pirates with AI (boarding through a breach), pirate ship (40 s of shelling,
  then it docks by force and breaks open the airlock; 6 hits from the guns wreck it, +25 credits).
- Space: infinite sectors, jumps, trader, station, derelict ships (approach, spacewalk,
  docking, loot, darkness), the event director (GM) with 11 events; credits for exploration and for pirates; fuel.
- Campaign: crew reserve (R and returning a dead character cost one person, hiring at the trader), hull integrity,
  campaign end with a summary, saving between evenings (`user://campaign.json`, characters by player name).
- Jobs (sailor, captain, pilot, engineer, doctor, security) with access to compartments (a lock is broken
  in 5 s, does not work without power) and repair, medicine and shooting skills.
- Speech out loud (7 cells, through air), radio («;»), intercoms («!», 4 panels), dead chat.
- Sounds are audible: made in code (`src/client/sounds.gd`), with direction and muffling, engine hum.

## Open problems
- Sounds are still synthetic and walls don't shape them (muffling by visibility); no voice chat.
- Jobs are the same for every ship; crew size by ship size (from the survey) is not accounted for yet.
- One player ship per server (architecture; the scale in the vision needs several).
- Field of view is client-only (the server also sends invisible players) — fix before playing with strangers.
- Not verified: the server as a separate process on Windows, playing over the internet without VPN, the bar above
  heads and transparent floors on the author's graphics card.
- Builds are not published to GitHub Releases (the author did not answer).

## Next steps
The fourth plan (survey answers, order and status in `CLAUDE.md`) is done, except the darkness front:
fuel (v34), the rest in a single build v35 at the author's request. The darkness front is postponed: the author is still
thinking the concept through. Next — ask the author what matters most and build the fifth plan. The author's idea (VISION): "Fear of dark space",
an entropy enemy ("the ship of darkness"), fighting it as the finale.
Builds are in the project's shared folder `/mnt/project-files/builds/vNN/` (two archives).

## Build workflow
Code → `godot --headless --path . --import` → all tests from `CLAUDE.md` (13 scripts + nettest with loss,
`DERELICT=3`, `PIRATESHIP=2`) → `MECHANICS.md`, the Claude Docs document, `dist_files/README.txt`
(CRLF, BOM), version in `project.godot` → export, size in `play.bat`, two archives → commit in English
and push to `main`.
