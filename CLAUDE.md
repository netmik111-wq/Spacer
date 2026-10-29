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

Build v96 (version 0.89: places drawn in space, meteors as rocks, our boarding pod, bots fighting together) is the latest. Plans one to four are done except the darkness front (the
author is still thinking it through); builds v40 to v60 were the author's own requests, one build each.
v58 and v59 built the gear tiers plan (`/mnt/project-files/plans/tiers-plan.md`): guns in v58, ship gear
(systems' tiers, the module bay, armour, focusing array, phase drive) in v59. v60 began the road plan
(`/mnt/project-files/plans/road-plan.md`): crew at work (gunners, carried guns, bots at work, medbay, blast doors);
v61 power (SMES, bridge backup, ion storm, hazards hit pirates, hull mending outside); v62 enemies (drone ships,
teleporters, suitless boarders, bombs, Shrapnel, flagship phase two, passive modules, bay extender, security robots);
v63 road and story (comms console, events, quests, missions, SOS, food, hydroponics, cryopods, the roaming flagship,
modes); v64 the cluster map (his 19 cluster answers and 11 follow-ups, all "A"): a road of clusters with lanes and exits,
cluster kinds and nebulae, places inside systems, pirate hunters; v65 fixes (the locker window's tabs, the admin
refill fills every kind, seed names, robots and pirates hold fire past their own side); v66 airlocks (a button by each
airlock door, bots use it, follow out into space; pirates cross space) and the simulator's fixes; v67 began the "every part
interesting" plan (`/mnt/project-files/plans/every-part-plan.md`): fuel in units, scrap cut off dark ships, finds floating
outside, work places, traders' wants, the refinery, the parting volley; v68 fights for the whole crew: the pilot's evade, the engineer's power panel (switches, breakers,
overcharge), rounds loaded by hand, fights with goals, alert levels, breakdowns from hits, fight news on the bridge only.
Several reactors is a later question round (it breaks the one-engine rule).
v69 was the author's notebook between plan builds: 11 bug fixes, wrecks kept on the chart, the one-press airlock, vents.
v70 people over bots: bots at posts give half, no sailor, the autodoc needs a medic, injuries, the pilot steers round
meteors and surges, prisoners, boarders with goals (wreck, rob, bomb, kidnap), the shotgun and the welder.
v71 upkeep: hunger that slows (10 min) and kills (25 min on), the galley's stove and three dishes, complex repairs
(a toolbox and two part kinds) as a campaign option the hard mode turns on.
v72 his two notes: bots raise shutters on the way to a repair (suited, no other way), repairs first, free bots mend, one
bot per job said in chat, the bots' log (crew window and crew_log.txt); a boarding ship wrecked before docking stays a wreck.
v73 a friendlier game (his 24 answers, `https://claude.ai/artifact/L5C4LmRshPrQehcRoQJJKS`): the airlock pump takes a chamber
at a docked ship's pressure back home, the hunter's line once, an outline and a ring for E, a right-click menu, diagonal use,
key badges in hints, names under the mouse, hotbar drag, chat tabs and repeats, danger banners, interface size, Ctrl+wheel
zoom, ✕ and number keys on consoles, the bridge's alert panel.
v74 art and walking: things drawn in hands, a `sprites/` folder of simple base pictures an artist replaces, diagonal
walking (1.4x a step, 8 drawn directions), a first-shift checklist and a help book (H); bots keep their job while fetching
and mend their own post's console. v75 polish (his 20 answers, `https://claude.ai/artifact/AoY7KnfqbGL6JzfNhYGoS5`, and five notebook notes): a four-cell brig
and cuffs that slip only when awake, whole and unwatched; bots mend their mount, leave airless rooms, notice when stuck,
wait at a busy door and say only breaches aloud; hits flash and bleed, red light at red alert, music and ship sounds; the
run's story at the end, the host's address and players, a quiet first 5 minutes, a bug-report zip; deep wounds kill
slowly (the simulator found a game that could never end); the simulator salvages, and a soak test.
v76: out cold, hold R 2 s to give up and come back from the reserve. He said: the simulator does not replace his own
playtests, so no numbers change for now; nothing public (no GitHub Releases, the repository stays private).
v77 (his answers, `https://claude.ai/artifact/JFTeczxumE8CGGGcZ58vaJ`): seven bugs from an evening with KaineQwQ (the
trader's money loop, wreck spam on a jump, rejoining as «Name 2», the dead ship left behind, the chat too low, place
hints, the SOS dead ship), the view following the mouse (a setting), bots and pirates walking on a slant.
v78 (his picks M1 D, C1 B): players step a quarter of a tile and stop on any quarter, C lies down (crawl, shots fly over),
a friend right by the shooter is never hit. Swapping places was left out (people already walk through each other).
v79 (his answers, `https://claude.ai/artifact/RMLhvSAPdwjWFUssNC8LDM`): the lying body on its spot, head where one looks;
passing people drawn sliding a quarter aside; the camera leans toward the mouse; bots run from armed boarders and lie low,
a guard bot fetches a gun and fights (`defence`); vsync off in the background (his "not responding" picture).
v80 (his full run's notes, `https://claude.ai/artifact/3A2HTzKTNpPbgQTuyAFFvc`): eleven bug fixes (holes never on machines,
shots through space, mounts left alone, ships alongside stay behind, stopping for those outside, bodies kept), emergency
light, lying across, a stronger shotgun, picking what to take in the right-click menu.
v81 (his answers, `https://claude.ai/artifact/68oyd5cH9wyAsoT5Gcwfww`, all "A"): the ship editor in the main menu (game look,
tools, mirrors, select/copy/paste, undo, palette, decks, room marks, problems, `ships/` folder, «Попробовать»), the map builder
in the game, rooms taller than 2 tiles, asteroids as maps with ore veins, hold position (X, the human wall).
v82 (his worry "mechanics too deep", `https://claude.ai/artifact/NTp7NAbinskUYCEhKwCZVi`): no general depth rule (his D1: case by
case), getting up takes 1 s as in SS13, the autodoc alone heals on at half pace, per-run
counts of what people used (`usage.txt`), one's own sounds heard, empty click, casings, a camera kick, console sounds; (his answers) a healing
cross and bar at the autodoc, work ticks, a welded door's seam, being hit shakes, cries and reddens the screen's edges.
v82.1 (his note): the ship editor's two layers, floor under objects (`Drawing.base`, Q picks the layer, O hides objects).
v83 (his notes and two videos): the lying head's side is chosen once (turning while down keeps it, as in SS13), the camera
stays on one's feet, a 0.8-cell mouse dead zone round the body, shots carry the shooter (traces start at the drawn shooter,
the kick works on the move, a short shake).
v84 (his answers, `https://claude.ai/artifact/RVoV4nte7rCpgf2AhH6TTb`): a new campaign's ship picked in the menu (with a
picture, two-column menu), the server sends its drawings to guests, saves keep their copies, a ship with no helm or engine
cannot start, own pirate ships/derelicts/asteroids in the run (a tick), the blow's swing.
v85 (his answers, `https://claude.ai/artifact/G35RhEtEWHhMGPeuhahtuK`): a fleet of two ships of ours, one below the other
(each its own hull, power, guns, lockers, fuel, bots; one purse; either helm flies both; pirates mostly pick the weaker;
the run is lost only when both are), a guest picks a ship; the spriter's character (`sprites/crew.png`, job colours
repainted, the visor down while on the oxygen tank, a made step). Later: enemy fleets (his FS1 note), our ships flying
apart. Next: fire (his fire answers on `https://claude.ai/artifact/GrbXt4V21HzZUojDiYqEKk`: SS13-like gas and heat, agreed
to start simpler: oxygen, burnt air, heat; measure the air's cost first). Fear: later, when he has the concept.
v86 (his fleet notes and answers, `https://claude.ai/artifact/N2RrzNRQjXg2h2Lxq3KZ8U`): five fleet bugs (holomap, bots
aboard their own ship only, posts per ship, a docked pirate still a target for the other ship, pirates off the second
ship), hard focuses the weaker ship, a second pirate ship (the wingman) joining fights, the shuttle with force-field
hangars (4 seats, 10 s). He put fire off (FQ5 B: "focus on ships and pirate groups"); his fire answers are on that page.
Bots and the shuttle: he said "talk again when pods come; maybe a teleporter better".
v87 (his base sheet "man and woman, just for now", answers on `https://claude.ai/artifact/QVjVrb4gyzMQF6hdfwPCPg`): people drawn
from `body.png` (32x48, four ways, a slant shows the side), man or woman picked on the menu (bots by lot), job colours on the
top and shorts (v87.1, his S4 B and S7 B: no tank sign on the body, no made step); fixed: the fleet's ships shared their gun charges (the second never fired),
and an admin-called pirate could not come while a wreck lay alongside. Next art step he may take: clothes as layers.
v88 (his suit sheets, answers on `https://claude.ai/artifact/FMqARBDwoc4J2UUdpvwYr5`): anyone in a space suit is drawn from
`suit_man.png`/`suit_woman.png` (3 visors x 4 ways of 32x48, `CrewArt.SUIT_AT`): clear glass, half, the visor down on the tank;
(v88.1) pirates' visors red, people's shadow drawn by the game (`WorldView.ShadowArt`), along the body when lying.
v89 (his 18 Notebook notes, answers on `https://claude.ai/artifact/FryDUDpk8c5nbDpC3mJGqk`): what a power shortage cut comes
back by itself, the teleport 5x rarer with a 5 s warning and boarders spread over rooms in suits, the heavy boarder in the
suit, wrecks and bodies kept, bots climb ladders whatever is in front, «К оружию» per bot, meteors 3x / pirates 1.75x rarer,
hunters 1.25x fewer, click a system to jump, a drawn gun sight, sounds heard from the feet.
v90 (his Aseprite tile set, `art_src/tileset/`; questions on `https://claude.ai/artifact/FkyjH7eBxzYEQhCXbPkNFG`): every wall,
floor, window and door from his set, doors in four kinds with lamps and open stages, ten machines (wide over a row of signs, from
behind when facing up); the rest of his set (stairs, holo table, soil, floor lamps, window stages, lockers, boxes) waits for his answers. v90.1/v90.2 (his notes): wall crossings are his T under `vertical_wall_to_T-shaped_corner`; a wall from above only meets the plain band (`wall_tup`).
v91 (his v90 answers, two pictures; plan `https://claude.ai/artifact/YE4L4MZxffs8FVnetN4kuq`): machines stand on the floor in front
of walls (used from the front, seen over), our ship redrawn (3-tall rooms, big bridge, holo table), old drawings converted on load;
tall machines block sight (`ShipMap.tall`), stairs between decks (`/`, his F3); door kinds from `&` lines, lamps green/yellow
(opening)/red (blocked for you), floor lamps, danger line; outer/inner panes and window shutters (red alert, broken
window after 1 s); first-aid and spare parts boxes (the locker's stock), fire box, wall light; his ship icons on the chart. Left for
his answers: decor lockers (M6: walk-through, by his card), v1 shutter stages.
v92 (his roadmap, plan `/mnt/project-files/plans/roadmap-v92.md`, questions `https://claude.ai/artifact/V1AEJgkFnsjG9b8vk4DAmj`,
built on my picks while his answers are pending): item 0, the fight in real time: ships as bodies in space (`Arena`, `ArenaShape`),
the pilot steers with WASD/QE at the controls, guns are 180° turrets fired from the console, by bots or by hand at the mount, shots
fly and strike the cell they meet, shields are bubbles, the docking clock waits while far, leaving past the edge.
v93 (his answers on `https://claude.ai/artifact/GePkt2SGzwqVSACbk6hZNJ` and the v92 page; one Notebook note with a picture):
armour on the outer wall (ours 2, pirates by class), penetration thickened by the slant, wear, ricochets that fly on and
strike another ship, worn armour mended from outside; the shield a bubble or a stronger arc (E at the generator); a lone
pilot fires every free gun with the mouse, the gun console shows space; no dodge roll in space; night vision and thermal
goggles (a fourth wear place); his note: machine pictures face the room, the globe a tile up, outer windows with shutters.
v94 (his "make all guns work properly ... more like in Starsector"; questions `https://claude.ai/artifact/RFiT641SPv4FoHqLDujHRC`,
built on my picks): every gun's own numbers in space (`Weapons.SPACE`), Starsector's damage kinds, heat (flux) with the shield
stopping shots, overload and venting (V), the pilot's shield on the right mouse, Starsector's armour, hull points (every 100
through = one hit inside), three mount kinds (fixed, side 180°, roof 360°; `^` lines; our ship's fourth, fixed bow gun starts
off), ammunition clips, the gun console always in space; his notes: thermal only in the view cone, a side wall's joint.
v94.1 (his answers on that page, all A but S4 B: firing heats nothing; his M2 note: a mount gives only its arc, each gun
fits certain mount kinds, `Weapons.FITS`, and turns at its own pace).
v95 (his Notebook note "fly with WASD instead of the old helm map" and N1; answers on `https://claude.ai/artifact/Y5SD56y9aj1rZMF9KFEJGa`,
all A): our ships are bodies in space always (4 cells a unit), WASD and an autopilot by a click on the small map, fuel only
while pushing, the edge a wall, practice fire, no fight circle (break off at 170 cells from every pirate), ambushes from
their place, pirates' boarding pods (only ships with a pod bay, his P2 note) and assault drones flying in space.
v96 ("next build"; questions `https://claude.ai/artifact/1PD8wL3crt6FGhEEHQ21sx`, built on my picks, all A): places drawn
in space only when near (his F5), a derelict/wreck/rock glides to the airlock, stations and traders dock only once stopped;
meteors are rocks flying in space (evade early, shoot, shield); our boarding pod (`k`, `pods.gd`: 2 seats, flies to the pirate
alongside, sticks, E takes riders home, bots called); bots' radio, falling back, shotgun first, one target.
Next: the teleporter as a rare find with procedural places, choosing the enemy deck, arsenal, races.
Engines and complex atmosphere (gases, fire, electricity) only after asking the author in detail.

The author's standing rules (details in `docs/DECISIONS.md`):
- Bodies remain after death. R returns a dead player as a new crew member from the reserve.
- (v61) No engine and an empty SMES = no power; nothing breaks from it. Anything new aboard asks
  `GameServer.powered()` (client `GameClient.powered()`); things on the bridge ask `Power.at(cell)` (client
  `GameClient.power_at(cell)`), as the bridge backup SMES keeps them going.
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

    tools/runtests.sh          (all 51 scripts below in a row; GitHub Actions runs it on every push)
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
    godot --headless --path . --script res://tools/powertest.gd (since v61: SMES, backup, terminal, coils, ion storm, hull mending outside)
    godot --headless --path . --script res://tools/enemytest.gd (since v62: drone ship, teleport, suitless boarders, bombs, phase two, modules, robots)
    godot --headless --path . --script res://tools/storytest.gd (since v63: calls, quests, missions, SOS, food, trays, cryo, roaming flagship, modes)
    godot --headless --path . --script res://tools/roadtest.gd (since v64: places, hunters, the long jump, the road packet, saves)
    godot --headless --path . --script res://tools/airlocktest.gd (since v66: bots and pirates through the airlock, follow outside)
    godot --headless --path . --script res://tools/salvagetest.gd (since v67: fuel units, pouring, scrap, floating finds, work places, refinery)
    godot --headless --path . --script res://tools/crewfighttest.gd (since v68: power panel, overcharge, evade, loaded mounts, goals, alerts, knock-on)
    godot --headless --path . --script res://tools/fixtest.gd (since v69: self-healing, autodoc, buried finds, docking, wrecks on the chart, hunters, station, locked rooms, airlock cycle, vents, sight)
    godot --headless --path . --script res://tools/peopletest.gd (since v70: bots at half, jobs, autodoc, injuries, meteors, surges, prisoners, boarders' goals, bombs, kidnapping, shotgun, flashbang, welder)
    godot --headless --path . --script res://tools/upkeeptest.gd (since v71: hunger slows and kills, the galley and its dishes, complex repairs, bots' parts)
    godot --headless --path . --script res://tools/bottest.gd (since v72: bots through shutters, one bot per job, free bots mend, the log, the boarders' wreck)
    godot --headless --path . --script res://tools/walktest.gd (since v74: 8 ways, slant steps, corners, doorways, use and sight on a slant, the look byte)
    godot --headless --path . --script res://tools/polishtest.gd (since v75: gunner mends its mount, bots leave airless rooms, stuck shutters, busy doors, breaches aloud, quiet start, summary)
    godot --headless --path . --script res://tools/eveningtest.gd (since v77: trader's wants, wreck on a jump, saved in space, SOS ship, free look, slant ways, rejoin with real clients)
    godot --headless --path . --script res://tools/quartertest.gd (since v78: quarter steps, bodies never in walls, sliding into doorways, held doors, hauling, lying down, friendly fire)
    godot --headless --path . --script res://tools/defencetest.gd (since v79: bots run from armed pirates and lie low, a guard bot fetches a gun and fights, the camera lean setting)
    godot --headless --path . --script res://tools/fullruntest.gd (since v80: no holes on machines, shots through space, mounts left alone, wrecks stay behind, stopping for those outside, out cold spared)
    godot --headless --path . --script res://tools/edittest.gd (since v81: builder = script, drawing tools, own ships, checks, trials, asteroids, hold position)
    godot --headless --path . --script res://tools/hosttest.gd (since v84: own ship, drawings sent to guests, serious problems, saves' copies, own others, the swing)
    godot --headless --path . --script res://tools/fleettest.gd (since v85: two ships, own state, one purse, flying together, targets, saves, losing one)
    godot --headless --path . --script res://tools/wingtest.gd (since v86: the fleet notes' fixes, the pirates' wingman)
    godot --headless --path . --script res://tools/shuttletest.gd (since v86: hangars, the force field, boarding, flying, calling the shuttle)
    godot --headless --path . --script res://tools/windowtest.gd (since v91: machines on the floor, window shutters, wall boxes, stairs)
    godot --headless --path . --script res://tools/arenatest.gd (since v92: shapes, the pilot, drift, arcs, shots flying and striking, shield, hand aim, bumps, the edge, docking)
    godot --headless --path . --script res://tools/armourtest.gd (since v93: armour, penetration, slant, wear, ricochet, mending outside, all guns from the helm, the shield's arc)
    godot --headless --path . --script res://tools/eyestest.gd (since v93: goggles, night vision, thermal through walls)
    godot --headless --path . --script res://tools/fluxtest.gd (since v94: every gun in space, heat, overload, vent, the pilot's shield, mount kinds, clips)
    godot --headless --path . --script res://tools/flighttest.gd (since v95: flying the system, autopilot, edge, held, jump, practice fire, break-off, ambush, pods)
    godot --headless --path . --script res://tools/podtest.gd (since v96: places' drawings, meteors in space, our boarding pod, bots' radio, falling back, shotgun, one target)
    GODOT=... tools/soak.sh 2      (since v75, the author's S3: 2 game hours with 7 bots; last line "soak: ok")
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
request. A red check on GitHub means one of the 51 scripts failed; its log is attached to the run.

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
  onto mounts, `medbay`: autodocs and the scanner, `blast`: blast doors; since v61 `power`: the SMES and the ship's
  power, `hazards`: the ion storm and hazards hitting pirates, `outside`: mending the hull from outside; since v62 `assault`:
  teleported boarders and assault drones, `robots`: our security robots; since v63 `story`: the comms console's
  calls (data in `tales.gd`), quests, missions, SOS, and `garden`: food, hunger and the hydroponic trays; since v64 `road`:
  the road of clusters, places inside a system and pirate hunters; since v67 `salvage`: cutting scrap off dark ships and
  things floating outside; since v70 `prisons`: pirates in our handcuffs, the brig, selling, questioning, the swap;
  since v71 `galley`: the stove, its dishes and their effects; since v79 `defence`: bots against armed boarders; since v85
  `fleet`: our ships, and which one's state is in place; since v86 `wing`: a second pirate ship fighting from afar,
  `shuttle`: the fleet's shuttle between the hangars; since v92 `arena`: the fight in real time, ships as bodies in space;
  since v96 `pods`: our boarding pod).
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
  `weapons.gd`, `sectors.gd`, `hulls.gd` (pirate ship classes and tempers), `gear.gd` (v59: crates of ship gear),
  `plants.gd` (v63: what grows in the trays), `upkeep.gd` (v71: complex repairs' rules, shared with the hints),
  `map_builder.gd` (v81: a text drawing to the layout, as `tools/make_assets.py` does).
- `src/server/`: `game_server.gd` (state, network loop, tick order) and one part per topic (see
  "How it works"); `player.gd`, `ship.gd`, `air.gd`, `vitals.gd`; (v77) `paths.gd`, the 8-way way-finding every bot,
  pirate and robot uses. (v82) `usage.gd`, what people used this run.
- `src/client/`: `game_client.gd` (network, prediction, what the client knows), `world_view.gd` (the
  world, light and sight drawing), `fight_fx.gd` (v56: ships' shots flying and bursting), `arena_seen.gd` (v92: the fight in space as the client knows it; v93 worn armour), `sounds.gd` (any
  sound can be replaced by `sounds/NAME.ogg|wav` next to the game), `options.gd`, `item_art.gd`, `crew_art.gd` (v85: the people's sheet; since v87 built from `body.png`, v88 the suits from `suit_man.png`/`suit_woman.png`), `sprites.gd` (v74: pictures
  replaced from `sprites/` next to the game; every sheet and item picture loads through it).
- `src/ui/`: `game_screen.gd` (HUD, chat, the console frame), console screens `bridge_view.gd` (chart and
  helm), `store_view.gd`, `trade_view.gd`, `guns_view.gd`, `holo_view.gd`, `drone_view.gd` (`enemy_plan.gd`
  draws the enemy ship's plan for the last two consoles' screens); `inventory_panel.gd`, `crew_panel.gd` (v55, key O),
  `admin_panel.gd`, `options_panel.gd`, `main_menu.gd`, `bench_view.gd` (v58, the workbench), `power_view.gd` (v61),
  `comms_view.gd` (v63, the comms console), `galley_view.gd` (v71, the galley's stove), `help_book.gd` and
  `first_shift.gd` (v74, H and the first-shift checklist).
  (v81) `ship_editor.gd` (the ship editor) with `src/ui/editor/`: `drawing.gd` (the model, tools, undo, text), `canvas.gd`
  (drawing and the mouse), `checks.gd` (the problems panel).
  (v84) `ship_preview.gd`, the main menu's small picture of a ship. (v86) `shuttle_view.gd`, the shuttle's console. (v92) `space_view.gd`, the fight in space (v94: also beside the gun console's list, `GunsView.compact`).
  (v75) `src/client/music.gd` (one music player with a crossfade, menu and fight), `src/client/bug_report.gd` (the zip).
- `tools/`: tests (`*test.gd`, `runtests.sh`, `nettest.sh`), `bench.sh`, `sightbench.gd`, `fightbench.gd`, `lagproxy.rs`,
  `make_assets.py`, `fxshot.gd` (v56: a picture of the fight's effects, `godot --path . --script res://tools/fxshot.gd -- OUT.png`
  under xvfb-run), `playthrough.gd` (2026-10-19: a script captain plays whole campaigns and records every number,
  `-- OUT_DIR runs first mode hours stay`; since v75 it salvages and sells, and SOAK=1 makes it the soak test), `simreport.py` (gathers those records into tables for the records page), `spritelist.gd` (v74: writes
  `dist_files/sprites/README.txt`, the names of every replaceable picture; rerun when items are added).
  `maps/`: ship blueprints (`*.txt`, built to `*.json`).

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
- Pirates are Players too: whatever counts the crew must skip `p.pirate` (and `p.bot`, `p.corpse`; since v62 also
  `p.ally`, our security robots). Enemy robots (assault drones, a drone ship's guards) are pirates with `p.robot`.
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
- (v61) Power is set up before Outfit: it reads the coils from `Ship.gear` itself. A test that wants the ship dark
  must empty the SMES too (`server.power.set_charge(0.0)`): a broken engine alone no longer darkens it. Guns and
  shield draw from the SMES only in a fight (`Power._load`). Godot virtuals: never name a method `_get` or `_set`.
- (v62) A drone ship (`Gunnery.crewless`) has no cockpit, quarters or jump drive room: `room_of_system` gives -1 for
  them. `Ship.modules` may hold 3 slots (the extender): never assume `Gear.MODULE_SLOTS`. Gun ids from
  `Weapons.HORNET` map to items from `Net.ITEM_GUN_LATE` (always go through `Weapons.item_of`/`of_item`).
- (v63) Tests that wait a long time must keep the story still: `server.story.auto = false` (no calls on arrival), and
  a fight with a grown flagship (growth 3+) can capture the ship (it teleports boarders). The hull's top strength is
  `Ship.hull_max` (the easy mode lowers it), never `Net.HULL_MAX` for our ship. Food is eaten in `Garden.jumped`: a test
  that jumps many times may starve its crew (health down to 30).
- (v64) `Sectors` holds only the cluster the ship is in; `kind_at` and the endless grid are gone. Ask `sectors.index_of(cell)`
  (-1: not in this cluster) and `sectors.kind[i]`; distances are `hops`/`hops_between`/`distances`, never cell arithmetic. To put
  a test in another cluster set `server.road.depth` and `server.road.entry` (`Vector2i(6 * depth, 0)`) and call
  `server.road.build(cell)`. The long jump's target is `Sectors.EXIT_JUMP`. Hunters come only while `road.auto` and
  `director.auto`. Tests that need places, wrecks or ambushes use `ship02` (`ship01` has no spots for a ship alongside).
- (v65) The supply locker window has a fixed width (`StoreView.WIDTH`, 10 cards) and tabs (`StoreView.TABS`, by
  `Items.CATEGORIES` captions); a new category goes into a tab there or lands in the last one. The admin refill
  (`Admin.restock_least`) gives every kind `Items.kept_in_locker()` lists; `admintest` checks none stays at 0 and all have names.
- (v66) Bot and pirate routes may pass airlock doors whose shutter is down (`Systems.lock_door`); whoever walks a route
  must call `Systems.get_past` when the next door `lock_bars`, or it pushes on a shut door forever. E on such a door is its
  button (`Systems.call_lock`); the client's hint finds the pump with `GameScreen._lock_pump_of`.
- (v67) The ship's fuel is `Ship.tank` in units (client `GameClient.fuel`, `fuel_max`, `jump_cost`); the player's `tank` and
  the client's `tank` are the oxygen tank. Ask `Ship.can_jump(long_jump)` before a jump, never count cans in the store. Things
  floating in space are floor things on space cells (`Salvage.floating()`), cleared on every jump; a test that lets a derelict
  leave must bring its players back aboard first (`crew.spawn_point()`), or the derelict stays.
- (v68) Gun, guard and shield power is switched from the power panel (`Power._panel`, `Gunnery.arm`/`switch_shield`/`arm_guard`,
  `p` may be null for bots); the gun console's `GUNSET_ARM`/`GUNSET_SHIELD` only say so. The ship's own draw is
  `Power.base_load()` (core + breakers), never `BASE_LOAD`. Light is `Power.light_at(cell)` (client `light_at`), not `at`. A
  fight's detail goes through `chat.say_bridge`, a warning through `say`. Breakdowns by chance are off (weight 0): a test
  that needs one calls `Systems` directly; `systems.knock_chance` pins pirate hits' knock-on (0 or 1). Raids roll a goal only
  with `gunnery.goal_next` (the director and the road set it) or `goal_for_test`. A mount fires its breech first
  (`Mounts.take_round`/`has_round`): never take ammo from the store by hand for a shot.
- (v69) A pirate wreck left behind is kept in `Road.hulks` (a P_HULK place) and comes back alongside when the ship is
  within `WRECK_REACH` of it again: a test that wrecks pirates and then moves the ship or wants a clear system clears
  `server.road.hulks`. A hunter after a fight waits `road.breather` (tests set 0). The server sends characters all round
  (`replication.set_round(false)` for strict cone checks). Vents refill sealed rooms (`systems.vents_on = false` to
  keep a room empty). Leaving a locked room is free (`ShipMap.leaving`); a hacked lock stays open (`Doors.picked`).
  `Derelict._put` adds to a floor cell, never replaces.
- (v70) A prisoner is a pirate `Player` with `prisoner` set: whatever counts pirates or picks a foe must skip it (as
  `Pirates.aboard`/`foe` do). A kidnapped one is `taken` (dead, hidden from clients, no body on respawn). A bot's help at a
  post goes through `Stations.share(p)`. Pirates' bombs are floor things plus `Pirates.bombs`; boarders get goals only while
  `pirates.goals_on` (tests that count pirates' fighting may want it off). `Systems.at_console` refuses a concussed person.
  Pirates turn at `cd <= 1` (a walking character never shows cd 0 to a think).
- (v71) Work by hand goes through `Repairs._work_done` (or takes `Player.pace(tick)` itself, as the workbench, the stove
  and treatments do): coffee makes it 0.75. Mending a machine or door uses `Repairs.spare_for` (never `ITEM_PART` by
  hand); `server.complex_repairs` (set before start, like `mode`) decides the part kinds (`Upkeep.part_for`). A slow
  walk is `Player.slowed()` (a broken leg or hunger's `weak`), never `p.leg` alone. Hunger counts `Garden.starved`
  seconds: a test that starves the crew calls `garden._feed_tick()` per second rather than running 25 min of ticks.
- (v72) A bot's repair job is `Player.bot_job` (set only by `Stations._took`, which also says it aloud); whatever moves a
  bot to other work must let it go (`_set_order` does). Bots' log lines go through `Chat.bot_log` (`chat.bot_lines` keeps
  them only with `keep_heard`). Free bots volunteer to mend: a test that wants a breach or a broken machine left alone sets
  `server.stations.volunteers = false` (or gives the bots posts). A boarding ship wrecked by the guns now stays (`Derelict.wreck`): a test that wants the next pirate
  ship calls `derelict.pirates_wrecked()` to clear it away.
- (v73) A warning everyone must see goes through `chat.alarm` (red banner, chime), not `say`. A pump run has a goal
  (`Systems.pump_goal`, set by `toggle_pump`'s `goal`): with a ship docked the outer door's way aims at its air, the inner
  door's at `inside_air`. The client's chat keeps lines with a tab (`GameScreen._say(text, tab)`); new lines go through it,
  never straight into `_chat_lines`. The HUD hint the player reads is `_hint_rich` (badges); `_hint` keeps the plain text,
  invisible. The interface size scales `GameScreen`'s root (`_fit_root`): place new HUD pieces inside it. Hotbar drag is
  `C_SWAP` (`Inventory.swap`), which the client mirrors on its own hand.
- (v74) Directions are 1..8 (`Net.DIRS`; 5–8 are slants, `Net.diagonal`, `Net.way`, `Net.dir_of`); `Mover.TURN` is 16.
  Facing takes bits 0–3 of the look byte (`Net.pack_look`), light is 128: never add a look bit below 16. Loops over
  directions go to `Net.DIRS`, never 4. A slant step's time is `Mover.slant_span`; the self packet carries the span. Bots
  and pirates still give only 1..4. Load pictures through `Sprites.sheet(name)`, never `load("res://assets/...png")`, or the
  `sprites/` folder won't replace them. `S_OUTFIT` carries the kind in hand (`GameClient.held_by`).
- (v75) The first 5 minutes of a campaign are quiet on easy and normal (`Director.quiet()`; the road's hunters wait too):
  a test that wants events or hunters at once sets `server.director.quiet_start = false`. A brig is a `@ deck x y brig` line
  (`ShipMap.is_brig`), not a lock. A prisoner slips cuffs only awake, above `Prisons.WHOLE_ENOUGH` and unwatched (none of
  ours awake in his room). Bots may drop a goal as stuck (`Stations.stuck`, 20 s with no new cell, 60 s avoided): a test that
  holds a bot still on purpose lets go of `bot_goal`. Only breaches are said aloud by bots. Unconscious with wounds of 100+
  dies slowly (`Vitals.DYING`). `S_HIT` and `S_SUMMARY` are new (protocol 52). The client's sound kinds go through
  `WorldView.SOUND_LOOK`: one entry per `Net.SOUND_*`, or the new kind is never played (10–15 were silent until v75).
- (v77) The view following the mouse is the client's alone (`GameClient.look_way`, `aim_at`); the server only learns the
  8-way facing (TURN inputs) and `Mover.State.free_look` (inputs `Mover.LOOK_FREE`/`LOOK_WALK`, byte 18 of SEC_SELF): with it
  set, walking does not turn a character. Anything new that hides or shows by our sight asks `look_way()`, never
  `Net.way(pred.facing)`. Scripted walks in `main.gd` turn it off (`GameScreen.scripted_look`). Bots, pirates and robots find
  ways with `Paths.first_step` (directions 1..8): never write a 4-way search again. A trader never offers what it `wanted()`:
  a test buying plain things picks ones it does not look for. Same name and same address in a hello takes the old
  character over (`Crew._same_person`). Protocol 53. (v77.1) The client sends one turn at a time (`facing_soon`): never
  send an input on every frame, as each is stamped a tick after the last and the queue runs away at high frame rates.
- (v78) A player's tile `st.x, st.y` is the one under its centre; `st.ox, st.oy` (-2..1 quarters) say how far off it
  it stands, only when `st.fine` (players: `Player.quarters`; tests set it). Where it is drawn is `Mover.visual_pos`
  (quarters included); `st.fx, st.fy` are in quarters (`qx()`, `qy()`). Whatever asks "is somebody in this doorway" must
  look at `Mover.body_tiles(st)` too. Shots start and land by drawn places (`Combat.place_at`); aim at a player with
  `visual_pos`, not its tile. A friend within `Combat.FRIEND_CLOSE` of the shooter is never hit (`Combat.spared`): a test
  that wants a friend hit puts it two tiles on. Character records are 8 bytes, the self section 19 (protocol 54).
  `tools/nettest.sh` runs in parallel only without `unshare -n` here (no `ip` to raise the loopback).
- (v79) A bot that `server.defence.busy(p)` runs, hides (lying low) or, with the guard's job, fights by `Pirates.think`:
  its order waits. Tests that keep armed pirates near bots and count on the bots working set `server.defence.on = false`.
  `Pirates.foe` treats a bot like our robots. `Net.DOING_HIDE`/`DOING_FIGHT` are new (protocol 55). The camera's lean is
  `WorldView._lean` (with the mouse view only); the sliding-past push is drawing only (`WorldView._passing`).
- (v80) No breach on a wall cell with a fitting or gun (`ShipMap.hull`). Shots stop at `passable`, not `walkable`: they
  fly through open space. A bot may take a mounted gun down or put one up only on the console's order (`Mounts.can`);
  `Player.mended` keeps a mend's hold from going on to unmount. A ship alongside leaves as soon as `ship.moving`, and a
  hulk comes back only to a stopped ship: a test that moves the ship on purpose by setting `pos` (not `moving`) keeps it.
  `Navigation.update` stops a flying ship while `derelict.someone_outside()`. Bodies on the ship alongside go into the
  hulk (`"bodies"`) or `_left_bodies` and come back with it. `C_TAKE` takes one chosen floor thing (protocol 56).
- (v81) `MapBuilder` and `tools/make_assets.py` must build the same layout (`edittest` compares every map): change both.
  New tiles go at the END of the sheet (an artist's older sheet still lines up). A map's kind is `ShipMap.kind` (from
  `; kind =` or its name); pick other maps with `map.others_of(kind)` and the list with `map.other_maps()` (it adds the
  editor's trial, `ShipMap.try_other`), never `Net.OTHER_MAPS` alone. An asteroid alongside is `Net.OTHER_ROCK` (ship kind
  `SHIP_ROCK`): no doors, no dock, no scrap. Held cells are `ShipMap.held` (filled by `Movement.mark_held` each tick, by the
  client in `_mark_held`): whatever moves a character other than through `Mover.step` should respect them. Protocol 57.
  (v82.1) The editor's `Drawing` keeps two arrays per deck, `cells` (what the game sees) and `base` (the floor layer):
  change them only through `_put_sign`/`_layers`, which keep them in step.
- (v82) Getting up is `Mover.State.rise` (ticks left, `Mover.RISE_TICKS`), predicted like a step and sent in the self
  section (20 bytes, protocol 58); a test that sends RISE must step the state RISE_TICKS times. Whatever people choose to
  use goes through `server.usage.note(p, key)` (bots skipped); a new key goes into `Usage.NAMES`. `Chat.sound` now sends a
  sound back to the one who made it, except footsteps. He chose no general depth rule: judge each mechanic on its own.
- (v83) `S_SHOT` ends with the shooter's id (`Combat.tell_shot(..., by)`, protocol 59): pass the Player for hand shots and
  blows, so the client draws the trace from where it shows him and knows its own shots. The camera, light and sight
  origin follow `WorldView._my_spot()` (the feet), never the drawn sprite (a lying body is drawn to one side).
- (v84) A "ships:NAME" drawing's text comes from `ShipMap.drawings` first (what the server read or sent, or the save
  kept), then the «ships» folder; clear it before starting anything that should read the files anew (`main.gd
  _prepare_ships`). Own other drawings are `ShipMap.own_others`, after `Net.OTHER_MAPS` in `others`: never take a layout
  number as a kind (a derelict is `Net.SHIP_DERELICT`, client `other_derelict`). `S_WELCOME` ends with
  `ShipMap.pack_maps` (protocol 60). `GameServer.start` refuses an own ship without helm or engine (`ShipMap.serious`).
- (v85) Our fleet is one grid (`ShipMap.fleet_rows`, `fleet_of(cell)`; -1 = the ship alongside) and a context swap:
  `server.fleet.use(i)` puts ship i's `Ship`, its fittings (`ShipMap.FLEET_FITS`, guns and trays numbered per ship) and
  the parts' fields in `Fleet.OWN` in place. A new per-ship field in a part goes into `Fleet.OWN`; a new per-ship fitting
  list into `FLEET_FITS`. Whatever runs for every ship goes through `fleet.each`; whatever a player asks is done for the
  ship they stand in (`use_for`, in `_on_packet` and per player in the tick). The tick ends with ship 0 in place; code
  that calls `use` puts 0 back (`new_player`/`add_bot` leave their ship in place). Map-wide lists (bridge consoles for
  chat) use `map.all_of(field)`. A lost ship (`fleet.is_lost()`) has no power and takes no hull hits. `S_BOARD`
  (protocol 61) tells a client its ship; the look byte's 8 is `Net.LOOK_TANK` (mask it off for the outfit).
- (v86) Gunnery's enemy fields are "the enemy in place": `server.wing.use(1)` puts the wingman's in (`Wing.ENEMY`), `use(0)`
  puts the ship alongside's back; code that swaps must put 0 back. `Gunnery.engaged()` = the enemy in place fights this
  ship of ours (false for the ship a pirate is docked to); `fighting()` = either enemy does. Anything about the ship
  alongside only (drone, flagship, prisons, story) asks `engaged()`. A new per-enemy field in Gunnery goes into
  `Wing.ENEMY`. The wingman comes only while `director.auto` (or `wing.chance_for_test`). `Gunnery.foe` (per ship of ours,
  in `Fleet.OWN`) picks which our guns shoot; `S_GUNS` ends with foe and two 5-byte summaries (protocol 62).
  `ShipMap.fleet_near(cell)` gives the ship by rows, the ship alongside included. A fleet save must have the same
  `fleet_rows`. Bots' own-ship lists go through `Stations._bots(true)` and `fleet.mine(cell)`.
  The shuttle's passengers are `Player.in_shuttle`: whatever picks a target or counts who is seen must skip them (as
  `Combat`, `Pirates.foe` and `Replication` do); the tick loop runs only `Shuttle.hold` for them. Map signs `F`
  (`window_field`, a see-through wall never in `hull`) and `V` (`dock`, a fitting); docks are `ShipMap.shuttle_docks()`.
- (v87) `Fleet.use` gives each ship its own copy of every Array, Dictionary and packed array in `Fleet.OWN`: Godot
  passes packed arrays by reference, and before v87 the ships shared them (the second ship's guns never charged apart).
  People are `CrewArt` from `body.png`; a woman's frames are `CrewArt.WOMAN_COLUMN` further on, chosen by `Net.LOOK_WOMAN`
  in the look byte (mask it off with the tank bit for the outfit). Only four ways are drawn: `WorldView.FACING_COLUMN`
  maps slants to sides. The hello ends with a byte for the body (protocol 63). The admin's pirate calls run
  `Derelict.make_room()` first.
- (v89) A power shortage's cuts are `Ship.cut` and come back through `Outfit.restore_power`: whatever switches a gun, the
  guard or the shield off on purpose must take it off that list (as `Gunnery.arm`/`switch_shield`/`arm_guard` do), or it
  comes back on by itself. The pirates' teleport charges first (`Assault.charging()`, `TELEPORT_WARN`): a test that wants
  boarders aboard runs that long after `teleport()` (or calls `beam_in()`). A route's climb goes through
  `Movement.climb(p, true)`; the plain call is the "use" key's. Director events by chance pass through `Director.RARER`.
  A bot's «К оружию» is `Player.defends`, sent as `Net.ORDER_ARMS` in the order byte (mask it off for the post). Sounds are
  heard at `WorldView._ears` (our feet), not the camera. `S_SOUND` kind 20 is the teleport (protocol 64).
- (v90) The tile sheet comes from the author's set (`tools/make_assets.py` `load_tileset`, `NEW_ART`, `art_tile`); new pieces
  go at the end. The client lays some cells in another tile than the map's (`WorldView._laid`: windows in a row, machines facing
  up, wide machines; `_door_look`: door kind, lamp, open stage): whatever reads a cell's look from the layer rather than
  `map.cells` gets that piece. A new machine picture goes into `MACHINE_ART` (make_assets) and `WorldView.MACHINE_WIDE` together;
  `edittest` checks the sheet has every piece.
- (v91) A machine sign is a thing on the floor (`ShipMap.on_floor`: cell -> the floor tile under it; walk 0, opaque 0, or 1
  for the `ShipMap.TALL` ones, `map.tall`), unless
  its row sits in a wall band (`MapBuilder.MACHINE_SIGNS`, the same set in `make_assets.py`). Ask for a machine through
  `map.machine_of(cell)` (a wide one's root; only roots are in the device dictionaries) and its use cell through
  `fitting_front`; draw it with `standing_look`. Old drawings go through `MapBuilder.to_floor` when read. Window shutters are
  `Systems.panes_down` (hull states 2/3; `Air.sealed` holes leak nothing; a test that wants a window's hole to keep leaking sets
  `server.systems.panes_on = false`); whatever changes a pane's opacity calls
  `ShipMap.set_pane` on both sides and the server forgets `replication.lines`. Wall boxes (`med_box`, `tech_box`) are wall things
  in `FLEET_FITS`. A save keeps `layout` (`map.crc`): a mismatch resets the cells' state (`Campaign.restore`). Protocol 65.
  Stairs (`/`) change a character's deck inside `Mover.step` (`ShipMap.stair_to`, when a step is over): anything that moves a
  character by hand onto a far end of a flight sends it on next tick. `Paths` maps a step onto a far end to its other deck.
- (v92) The fight in space is `server.arena` (`Arena`): it runs only while `gunnery.flies` and a pirate fights (`_lead_fights`,
  `_wing_fights`). Bodies 0 and 1 are our fleet's ships, `Arena.LEAD` (2) the ship alongside, `Arena.WING` (3) its wingman; a body's
  shape is `ArenaShape` (shared with the client, `of_fleet`/`of_layout`). With the arena on, Gunnery's shots go through
  `arena.fire_ours`/`fire_theirs` and come back as `arena_hit`/`arena_bubble`/`arena_guard`/`arena_miss`; `Gunnery.in_flight()` does
  not count them (`arena.in_flight()` does). A gun fires only while `arena.bears` (beams: `reaches`). Tests about the old fight set
  `server.arena.enabled = false`; `arena.hold_pirates` keeps pirates where a test puts them; `enemy_hit_chance` 1 aims true, 0
  aims clear of the whole ship. `S_ARENA`, `S_ARENA_SHOT`, `C_PILOT`, `C_TURRET` are new (protocol 66); the client keeps it in
  `GameClient.arena` (`ArenaSeen`) and draws it in `SpaceView`. Use target 49 is a gun mount taken by hand.
- (v93) Armour is per body in the arena (`Body.plates`, `Body.worn`; ours share `Ship.worn`, keyed by `ArenaShape` index):
  whatever makes our hull whole by hand also clears `ship.worn` and calls `arena.armour_mended()`. A shot dictionary
  with `"off"` glanced off that body (never hits it again, says nothing at its end); `"armour"` tells Gunnery it was held
  or glanced (`Net.HELD`, `Net.RICOCHET`). `arena.pane_armour` is a test knob (windows hold 1). `Net.ALL_GUNS` in
  C_TURRET is the helm's or gun console's mouse for every free gun. `Ship.shield_arc` (-1 bubble, 0..3) rides in the
  S_ARENA flags (`Net.ARENA_ARC_SHIFT`). Worn things are `Net.WORN` = 4 (`WEAR_EYES`): old saves are resized on load.
  Sight asks goggles in `Replication.sees` (and its cache key) and `WorldView.can_see`/`_my_dark`. Protocol 67.
- (v94) In space a gun's damage, pace and heat are `Weapons.SPACE` (`space_ticks`, `space_shots`, `space_damage`,
  `burst_heat`, `clip`); `Weapons.penetration` is gone. A shot's `"d"`/`"type"` ride in the shot dictionary. Hull damage
  goes into `Body.debt`; every `Arena.INSIDE_UNIT` makes one hit inside, passed to Gunnery as `meta["units"]` (`Gunnery._units`
  overrides the gun's own damage in `_land_through`/`_their_shot_lands`). The shield in space is heat (`Body.heat`, `hard`,
  `cap`): `Ship.shield` and `Gunnery.enemy_shield` are written from it each tick, never set them by hand in a space test (use
  `arena.pirate_shields = false` to keep the pirates' down). Turrets turn at `ArenaShape.MOUNT_TURN`: a test that moves a
  target runs a second or two before asking `bears`. A gun's kind is `ArenaShape.mount_kind` (`ShipMap.gun_kind` from `^`
  lines), its straight-out angle `mount_out`. Ammo in space comes through `Mounts.clip` (in `Fleet.OWN`). ship02 has 4 guns;
  guns past `Gunnery.START_ARMED` start switched off. A heavy gun's late hits wait in `Gunnery._flying`: a test that resets
  the pirate between shots clears it. C_SHIELD is new; S_ARENA's body record is 31 bytes + 4 a gun (protocol 68).
  (v94.1) Whatever puts a gun on a mount asks `Mounts.misfit` (client: `Weapons.fits` with `ArenaShape.kind_in_fleet`);
  a mount kind outside the arena comes from `kind_in_fleet`, never a new `of_fleet` per call. A turret's pace is
  `Arena._turn` (its gun's `Weapons.turn_speed`); a pirate's weapon fires from `Arena._their_gun`, not `weapon % guns`.
  Firing heats nothing while `Weapons.SHOTS_HEAT` is off (his S4 B).
- (v95) The arena runs always (`arena.flying()`: our bodies exist; `arena.on()`: a fight). Our first body's place is written
  to `Ship.pos` each tick (`Arena.SCALE` cells a unit): setting `Ship.pos` by hand re-places the fleet (`_told_pos`), setting
  a body's `pos` by hand keeps it; `Ship.dest`/`moving` set by hand become the autopilot's course (`_told_dest`). With
  `arena.enabled = false` the old `Navigation._old_flight` flies instead. The system's edge clamps our body (tests that
  put our ship at negative coordinates get it pushed back in). Fuel burns only while `Body.thrusting`. Pods and drones are
  shot dictionaries with `"pod"`; practice shots carry `"practice"` (never notify Gunnery). Pods need `Gunnery.pods` (the
  pod bay, in `Wing.ENEMY`; `shipyard.force_pods` for tests) and `arena.pods_on`; `arena.launch_pod` sends one at once.
  `S_ARENA`'s byte 5 is flags (`ARENA_FIGHT`, `ARENA_COURSE`), the count is byte 6, records from 7 (protocol 69).
  `fleet.follow()` runs again after `arena.tick()`.
- (v96) Our boarding pod is `server.pods` (`Pods`): riders are `Player.in_pod` (the bay) with `in_shuttle` set, so they are
  out of the world as the shuttle's are; a bot called to a seat is `Player.pod_call`. The flight is an arena shot with
  `"pod": "ours"` (`launch_our_pod`); `"home"` is drawing only. Meteors in space are shots with `"pod": "rock"` (side 1,
  `Arena.launch_meteor`); `Stations.meteor_seen` launches one while `arena.flying()` and its end calls `meteor_over`
  (tests of the old lot set `arena.enabled = false`). Out of a fight our shield's heat tick runs while rocks fly. A new map
  sign `k` (wall band, `ShipMap.pod`: wall cell -> front). S_ROAD's place record is 5 bytes (the drawing it is seen by) plus
  the system's own drawing at the end; S_POD, C_POD, `SHOT_ROCK` (protocol 70). Use target 51 is the pod bay. `Defence.radio`
  (D1) and `Player.falling_back` (D2) are new; `defence.spotted()` is cached per tick.
- Tests play with dice, so a new check that passes once may fail 1 run in 30 in CI (each build's first push went red
  this way, v60 to v63). Before a pull request, run the new test 30+ times. Parallel runs collide on ports and on
  `user://`: run each in `unshare -n` with its own `XDG_DATA_HOME`. Pin what the check is not about (keep a target in
  place, give more tries, look at everybody a lot may pick) rather than widening bounds blindly.
- Ships' shots land later than they are fired (v56, `Gunnery._flying`). A test that checks a hit right after
  `fire` or `_enemy_fires` must set `server.gunnery.flies = false` (the gun, ship, drone and station tests do).
  Effects that are only drawn take their lots from `Gunnery._fx`, so the game's own rng sequence is unchanged.

## Delivering builds

- The archive's first part carries `dist_files/sounds/README.txt` as `sounds/README.txt` (v56: the names of
  the sounds the author may replace), and (v74) `dist_files/sprites/README.txt` as `sprites/README.txt` with the six
  sheets copied from `assets/` into `sprites/original/` (not into `sprites/` itself, or they'd be used as replacements);
  (v90) and `art_src/old/tiles_v89.png` as `sprites/old/tiles.png`, the author's "folders for old sprites".
- A file up to 30 MB goes through chat, and the Windows game weighs 36 MB archived. So it
  is split into `game.001` and `game.002` in two archives; `play.bat` joins them and checks
  the size. The size in `play.bat` is updated with every build.
- Builds aren't stored in git: the exe is larger than 100 MB. Nothing is published outside (the author, 2026-10-20:
  no GitHub Releases, the repository stays fully private).

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

- (v90) `art_src/tileset/Tile_set_1.png` + `.json` is the author's tile set (Aseprite slices), the source of `assets/tiles.png`.
  `art_src/old/` keeps the v89 mockup and sheet (the mockup still gives the oxygen console's picture).
- `art_src/` holds the author's references. `art_src/old/map_mockup.png` is scaled 2×; the 32-pixel grid
  starts at an offset of 5.5. `chars_ref.png` has one angle and cropped legs, so the crew
  is drawn in code for now. `hud.dmi` has 20 unnamed states; which is which is recorded
  in `tools/make_assets.py` (`HUD_ALERTS`).
- Everything in `assets/` and `maps/*.json` is built by `tools/make_assets.py`. Don't edit it by hand.
- The map is drawn by decks, the top one first; each starts with a line `= name`.
  New signs: `g` glass, `c` catwalks, `H` ladder (in one tile of two adjacent decks),
  `6` engine, `7` air plant, `8` supply locker (a wall, like consoles; the script draws their tiles),
  `I` intercom, `M` holomap, `5` drone monitor (v54), `B` workbench (v58), `U` module bay (v59), `Y` autodoc, `X` body scanner (v60), `S` SMES, `Q` bridge backup SMES (v61),
  `K` comms console, `P` hydroponic tray, `C` cryopod (v63), `G` the galley's stove (v71). A line `% deck x y system` names the room of an enemy ship's system (used only by
  the classic pirate01; rolled ships put systems in rooms by lot, see `docs/DECISIONS.md`). A line `@ deck x y access` makes a compartment locked. (v91) `E` first-aid box, `J` spare parts box, `N` fire box, `L` wall light (wall things); a line
  `& deck x y base|tech|cargo|herm` gives a door its look; machine signs outside a wall band are machines on the floor;
  `/` stairs, two in a row on a deck over the same two on the deck below. (v96) `k` our boarding pod's bay (in an outer wall band).
