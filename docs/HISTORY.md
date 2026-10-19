# Spacer: history of the plans and builds

What was asked for and built, plan by plan and build by build, oldest first in the plans,
newest first in the build notes. `CLAUDE.md` says where things stand now; this file says
how they got there. Add a paragraph for every build.

## Plans


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

Build v51 (0.44) was the author's request "make the code more optimised for your usage and better
performance, check for bugs": no gameplay changes. The server works out who sees whom about twice as
fast, the game draws light and the field of view about five times cheaper per frame (the same picture),
`CLAUDE.md` was cut to the essentials (the reasons moved to `docs/DECISIONS.md`, this history out of
`NOTES.md`), the bridge consoles' screens moved out of `game_screen.gd`, and seven bugs were fixed
(see the v51 notes below).

## What may come next

After that: engines and complex atmosphere (only after asking). With each step add
items at the trader. The author's sub-items (1.1, 2.1 …) are groundwork for the future.
The author's rule: bodies remain after death. Returning a dead player with the R key as a new
crew member was accepted by the author ("excellent"), but he has not called it final.
What's still missing and suggests itself: other ways to earn credits besides exploration;
new items for slots (tools, medkit, spare tank).

The darkness front (the fourth plan's item 3) is postponed: the author is still thinking it through.
The author's idea (VISION): "Fear of dark space", an entropy enemy ("the ship of darkness"), fighting it
as the finale. Next: ask the author what matters most and build the fifth plan.

Open problems:
- Sounds are made in code and walls don't shape them (only muffling by sight and thin air); no voice chat.
- Jobs are the same for every ship; crew size by ship size (from the survey) is not accounted for yet.
- One crewed ship per server for now (ships have network ids, groundwork for several).
- Builds are not published in GitHub Releases (the author did not answer).

## Build notes

### v65 (storage window fixes; the author's request)
- The supply locker's window was wider than the screen once the locker held many kinds. Its cards now sit under seven
  tabs, long groups wrap at 10 cards, and the window keeps one width (fits 1280×720).
- «Пополнить шкаф снабжения» left ship gear, security robots, seeds and the black box at ×0; it now fills every kind
  the locker keeps. `admintest` fails if it ever misses one, or if a kept kind has no name.
- Seed packets were named "<null>" everywhere (locker, trader, hands): `Items.name_of` now asks `Plants`.
- Friendly fire fix from the CI thread: robots and pirates hold fire while one of their own side is in the way.
- Choices made (all my picks, open to the author): https://claude.ai/artifact/SwbHwmKZcdbPV1yVFB8VsK.
  Build in `/mnt/project-files/builds/v65/`.

### v64 (the cluster map)
- Space is a road of clusters (the author's 19 "A" answers): 10–14 systems on lanes, two exits on the far side, a long
  jump (2 cans) into the next cluster of a kind shown in advance, no way back. Kinds: frontier, pirate territory, trade
  worlds, storm belt, dead zone; nebulae over a few systems. Each cluster is 4 steps of danger harder. The flagship waits
  in the 4th cluster and its jammer holds the exits until it is beaten; after it the road goes on.
- Places inside a system, hidden until the sensors find them: debris, containers (1 in 5 a mine), bodies (now and then a
  survivor), abandoned ships, battlefields, pirate ambushes (his notebook note page1016-07).
- Pirate hunters on the chart that walk the lanes toward us; stations are safe harbours.
- The chart: a cluster view and a road view; the helm shows the places found. Quests point inside the cluster.
  Old saves go on at a fresh first cluster. New server part `src/server/road.gd`, test `tools/roadtest.gd` (26 tests).
  Protocol 43. Follow-up questions https://claude.ai/artifact/UBEtPDJuG7WS7nkqpkhVqN (all "A"). Build in
  `/mnt/project-files/builds/v64/`.
- Fix (found by the CI thread, the author said yes): while one of ours is aboard a pirate ship, a pirate that walks
  across onto our ship is no longer announced as killed; the chat says it crossed over, and it stays a boarder.

### v63 (road and story, part 4 of the road plan)
- The comms console on the bridge (`K`): 26 text events with 2–4 answers each, blue answers by job, skill or
  thing, paid answers, the plain answer after 90 s (new server parts `src/server/story.gd`, data in
  `src/server/tales.gd`; screen `src/ui/comms_view.gd`).
- Quests (cargo, bounty, black box; marked on the chart), the chapter's two missions (convoy log, the courier with
  the flagship's codes), SOS sectors, ships that help a ship dry of fuel.
- Food (rations eaten at every jump, hunger down to 30 health) and hydroponics: 4 trays, 6 plants, mutations,
  hybrids, bots tending (new part `src/server/garden.gd`, plants in `src/shared/plants.gd`). Cryopods for the reserve.
- The flagship wakes near the goal, roams its area and grows every 3 min up to 4 steps.
- Easy and hard modes (menu), `Ship.hull_max`. Admin: calls, growth, ripe trays. New test `tools/storytest.gd`
  (25 tests). Protocol 42. Question page https://claude.ai/artifact/LJnEaFStDXqbZFq1xWPcQZ (my picks, all "A").
- Left for v64: the cluster map (his 19 "A" answers), its regions, places inside a system with small secrets
  (debris, containers, bodies, abandoned ships), pirate hunters.

### v62 (enemies, part 3 of the road plan)
- The drone ship, a fifth pirate class with no crew (`Gunnery.crewless`): a control core (`Net.ESYS_DRONES`),
  repair drones, assault drones that cut in as robots (new server part `src/server/assault.gd`), no air inside,
  two guard robots, taken only by wrecking its core by hand. It never runs, bargains or docks.
- Teleporters on ordinary pirates from 8 jumps (`Assault.teleport`, `Gunnery.crew_sent`); boarders without
  suits and heavy stormtroopers (`Pirates.spawn_boarder`, `Player.toughness`).
- Bombs (`Weapons.CLASS_BOMB`: «Шершень», «Глушилка», «Термит», items from `Net.ITEM_GUN_LATE`) and «Шрапнель»
  (area fragments), for us and for pirates; the flagship's second phase at a third of its hull.
- Four passive modules, the bay's extender (a third slot, sold at stations, which got a small shop), our security
  robots (`src/server/robots.gd`, `Player.ally`). New character rows (enemy robot, our robot, armour), sounds
  `gun_bomb` and `gun_shrapnel`. New test `tools/enemytest.gd` (24 tests). Protocol 41. Question page:
  https://claude.ai/artifact/VCN8eFSoSqhm1E52mYTwrN (built on my picks, all "A"; no answers yet).
- The author answered all 19 cluster map questions "A" (page https://claude.ai/artifact/Q3XhoTfZTiM6CqztJkmmkE),
  adding on C6: places in a system may hide small secrets (debris, a dropped container, dead bodies, an abandoned
  ship). The cluster map is its own build after v63.

### v61 (power, part 2 of the road plan)
- The SMES (`S` in the engine room) and the bridge backup (`Q`), new server part `src/server/power.gd`: the new
  rule "no engine and an empty SMES = no power", a +3 boost in fights, a hit takes the whole charge, an SS13
  terminal with the power monitor (`src/ui/power_view.gd`, also on the holomap), SMES coils as gear.
- The ion storm, a new sector kind, and hazards hitting pirates too (`src/server/hazards.gd`); pirates come in
  meteor showers and storms.
- Hull mending from outside with patches; bots on «Работы» go out through the airlock to do it
  (`src/server/outside.gd`).
- Admin: SMES full/empty, an ion surge, a meteor shower or storm here. New test `tools/powertest.gd`
  (23 tests). Protocol 40. Question page for the author: https://claude.ai/artifact/4grTgyeExpFPEoshxMkMyU
  (built on my picks; no answers yet).

### v60.1 (admin panel catches up; the author's request)
- The author missed the gear modules in the spawn panel. Audit: gear crates were listed (at the bottom), but
  ship guns (carried since v60), their tier 3 effects and damaged guns, ammunition, probes, drones and gun parts
  could not be spawned; nothing could fit gear at once, set skills, add bots, or call a chosen pirate ship or trader.
- The things tab is built from `Items.admin_sections()` (the locker's sections plus «Прочее» for anything new),
  shows hidden tiers, sends things to the hands or the locker (`ADMIN_STORE`), with an effect picker and a
  damaged box for guns. New commands `ADMIN_FIT`, `ADMIN_CHARGE`, `ADMIN_SKILLS`, `ADMIN_BOTS`, `ADMIN_FIGHT`
  (`Shipyard.force_temper`), and a trader's kind on `ADMIN_PLACE`. `admintest` checks that every kind of thing
  is listed. Protocol 39.

### v60 (crew at work, part 1 of the road plan; the author's notes N1 and S1)
- Gunners at the mounts (+25%, up to +50% with gunnery), guns carried from the locker and mounted by hand with E,
  the gun console gives orders that bots on «Работы» carry out (new server part `src/server/mounts.gd`, S_MOUNTS).
- Bots fetch parts, patches and suits from the locker, turn on oxygen in thin air, refill tanks, lie in an
  autodoc when hurt; a new order «У орудия». The crew is kept full: a joining player takes a bot's place and a
  bot takes a leaver's (the author's word).
- Medbay: two autodocs and a body scanner (`src/server/medbay.gd`, map letters Y and X). Blast doors from the
  holomap, which pirates cut through in 12 s (`src/server/blast.gd`).
- The workbench makes shells and rockets from spare parts; point defence shoots slow shells (30%); a piloting
  skill. New test `tools/worktest.gd` (22 tests now). Protocol 38. Bots mending the hull outside move to v61.

### v59 (ship gear, part 2 of the tiers plan)
- Ship gear in crates (`src/shared/gear.gd`, server part `src/server/outfit.gd`): four systems with three hidden
  tiers each (shield generator, reactor, engine, sensors; tier 1 built in) and a module bay ('U' on the map) with
  two slots for armour (3 tiers), the focusing array (the author's mirror note) and the phase drive (replaces the
  cloak). Only engineers install them, holding E at the machine; the replaced crate comes out into the hand.
- Our ship's armour (deferred from v58): less hull damage, fewer holes, kinetic ricochets. The phase drive moves
  the ship to a battle position at once and opens "behind them" (+25% / −20%), 60 s recharge.
- The top shield generator replaces the shield hardening; the top sensors show pirate guns charging on the gun
  console; a better engine charges jumps quicker and sometimes saves fuel.
- Traders sell crates, half of rare wreck and derelict finds are crates, the flagship grows with our gear
  (hull and shield refill), gear is saved. New test `tools/geartest.gd` (21 tests now). Protocol 37.

### v58 (gun tiers, part 1; the author's tiers plan)
- The author answered 65 questions on gear tiers ("Spacer Tier Questions"); the plan was split in two builds.
  Part 1: every gun has a hidden tier (1–3) and a kind of parts, five new named guns fill the tiers (Phoenix,
  Storm, Devastator, Reaper, Hammer), tier 3 guns carry a rolled effect, pirate guns get better with distance and
  the flagship grows by half our tier points.
- Kinetic guns from his notebook (autocannon, railgun, Hammer: the shield only takes 1 off, armour ricochets),
  shells, point defence «Заслон» on its own mount (ours and the pirates'; theirs shoots at our drone too).
- Rare gun drops (wrecks 30%, captured ships always, derelicts 25%; some a tier higher, some damaged), the
  flagship's unique «Сверхновая», three kinds of trader (arms dealer, junk dealer, black market) with one of each
  gun and buy-back of what was sold.
- The workbench ('B' in the engine room, `src/server/workshop.gd`, `src/ui/bench_view.gd`): engineers only (his
  pick on the decision card) take guns apart into parts, mend damaged ones and upgrade them along their line.
- Each new gun has its own shot look and sound (`gun_*` in `sounds\README.txt`); cargo pictures show tier by the
  frame. New test `tools/tiertest.gd` (20 tests now). Protocol 36.

### v57 (the pirates' flagship, the goal of the game; the author's request)
- The author asked for a linear goal: a boss fight with a big flagship in two variants, a battleship whose
  guns aim at our shield and engine, and a carrier that stuns the crew and teleports boarders to take the
  ship. His answers: capture = all crew down; it grows with our gear; the voyage goes on after the win; no
  escape from a boss; 12 jumps away; the variant stays hidden until it comes.
- The goal sector (`Sectors.goal_of`, a lane along its row and column), the chart's red mark and arrow,
  `src/server/flagship.gd` (arrival, teleporting boarders, capture, win, no jump), two hulls
  (`maps/pirate08.txt`, `pirate09.txt`), the neural emitter, the teleporter room, the battleship's aim
  (`Gunnery._boss_target`), the victory panel, `OVER_CAPTURED`, two eventer events, `tools/flagshiptest.gd`
  (19 tests now). fightbench takes a fifth argument to run flagships only. Protocol 35.

### v56 (the ship fight seen and heard; the author's video of FTL)
- The author sent a video of FTL and asked for "projectiles flying around, effects on hits, sounds on hits",
  then added that the fight must be heard, that footsteps hurt the ears, and that he will replace the sounds
  made in code with better ones.
- Shots fly (`Weapons.flight_ticks`, `Gunnery._flying`): rolled when fired, landing 0.6–1.3 s later.
  Drawn in the world (`src/client/fight_fx.gd`: bolts, rocket smoke, bursts that light the dark, sparks,
  debris, smoke, shield ripples) in two legs (`Gunnery._draw_ours`, `_draw_theirs`), and on the gun console's
  plan (`EnemyPlan._draw_fight`, packet `S_VOLLEY`: the enemy's shield bubble, bursts in rooms, «ПРОМАХ»).
- Sounds of the fight (`S_JOLT`, `WorldView._on_jolt`, ten new sounds in `Sounds`): heard aboard wherever
  there is air, blows to the hull shake the screen even in a vacuum; meteors too. Quieter footsteps; settings
  for footsteps, fight volume and shaking; any sound can be a file in `sounds/` next to the game.
- `tools/fxshot.gd` draws the effects into a picture without a fight; `volley_after=S` (with `--inproc`)
  makes a fight fire both ways every second for screenshots.

### v55 (our crew at fight stations, bots under orders, battle position, boarding; the author's notebook)
- The author's paper notes (2026-10-16) became notebook entries; he agreed the next build: our own crew at
  posts in a fight (mirroring the pirates' crew), bots as crew who follow the captain's orders (note 5), and
  the pilot choosing a battle position (my halfway version of note 2, "the engine moves the ship about the
  battlefield", one choice instead of steering). Our boarding of enemy ships was agreed on 2026-10-15.
- `src/server/stations.gd`: posts (controls, guns, engine, shield) count when somebody stands facing them; the
  controls give dodge (none before v55), the engine a little more, the shield generator refills faster.
  Battle positions close / far / flank (8 s manoeuvre). Bot orders (C_ORDER) with a crew window
  (`src/ui/crew_panel.gd`, key O); bots path over our ship, a gun bot fires, a repair bot mends with parts
  from the hold. Boarding: the first of us on a live pirate ship brings its crew to life as pirates
  (`EnemyCrew.come_to_life`), our people wreck systems by standing in their rooms, a captured ship is
  salvaged for 150% of its reward plus parts and fuel.
- The author's answers before the build: anybody may order while no captain is aboard; the pirates a little
  stronger (+5% to their hits); a captured ship salvaged for more than a wreck.
- New test `tools/stationtest.gd` (18 in all); `tools/fightbench.gd` takes a fourth argument, a pilot at the
  controls. Protocol 33.

### v54 (pirate crew, scouting drone, ransom; the list the author agreed after v53)
- The author agreed three things after v53: the probe also shows the enemy's crew moving (about 20 s),
  fights that don't drag on (measure first), and the drone from his notebook steered from a monitor.
- The pirate ship's crew stand at their posts and walk to mend what we knock out (`src/server/enemy_crew.gd`):
  a system is mended only while somebody is in its room, empty posts slow its guns and stop its dodging, and
  our hits may kill or wound those in the room hit. A probe shows them for 20 s, the drone those near it.
- The scouting drone (`src/server/drone.gd`, `src/ui/drone_view.gd`): a new drone monitor ('5') on the bridge
  sends one from the cargo; the walking keys steer it room by room inside the enemy ship; it shows rooms and
  crew, can be shot down, lasts 60 s, can blow itself up for 2 damage through the shield.
- A beaten pirate that would run may offer a ransom instead (credits, fuel, sometimes a prisoner).
- Fight length measured with the new `tools/fightbench.gd`: 0.5–2 min for every class and temper while a
  gunner stays at the console (before and after); fights drag only when nobody can fire. New test
  `tools/dronetest.gd` (17 in all). The enemy plan is drawn by `src/ui/enemy_plan.gd` for both consoles.
  Protocol 32.

- After the first v54 archives the author asked (screenshot) for the mouse-over outline to go round the thing
  itself, not its wall tile: rebuilt with outlines that follow the shape of wall machines, floor things and bodies.
- The author's bug note (videos, then his words): an empty airlock chamber against a docked ship with air kept
  the outer door shut. The pump now brings the chamber to the docked ship's pressure.
- The author's answers: hits into a room only wound (no kills), the ransom stays, and a raider boards when
  our guns are all silent and we cannot jump (engine out, no fuel or the sector console broken).

### v53 (many kinds of pirate ship; the author's request)
- The author asked for more kinds of enemy ship, rolled ("procedural generation"), with a different setup each.
  He agreed to: hand-drawn hulls with everything inside rolled; bigger ships harder through behaviour, not
  only hull; the attack drone left for a build of its own.
- Four classes (cutter, raider, gunship, cruiser; `src/shared/hulls.gd`), six new hulls (`maps/pirate02..07`),
  `src/server/shipyard.gd` rolls the class (by distance from the start), the hull, which room holds which
  system, the guns, the shield, the crew, the temper (four ways of fighting) and the name.
- Rooms are unknown at first; sensors, hits, the enemy's own fire and the new scanning probe show them. The
  guns aim at rooms; empty rooms soak up shots. New test `tools/shiptest.gd` (16 in all).
- From the author's notes: usable things get an outline under the mouse (as in SS13); a window or open door
  is no longer drawn with a wedge cut out of it in the field of view.

### v52 (blinking and smoothness; the author's video)
- The author's video showed wall corners at the ends of rooms blinking on and off while walking, and
  steps jerking every few frames. Corners and other cells grazed by a ray of the field of view are now
  decided by fixed rules (see `docs/DECISIONS.md`, "No blinking at the edges of sight"); rays walk the
  grid cell by cell. The client clock moves once per frame by the frame's length, and the cone's fan
  no longer trails a frame behind the character. No gameplay changes.

### v51 (code tidy-up, speed, bug fixes; the author's request)
- Server: who-sees-whom is worked out once per character per tick rather than once per pair
  (`Replication._prepare`), lines of sight remember which doors they cross (`Sight.clear_cached`,
  `Replication.lines`), and a dark ship alongside no longer makes every pair be worked out every tick.
  32 clients on the 4-CPU test machine: see `docs/BENCHMARK.md`. `tools/bench.sh` now also prints where
  the tick time goes; `tools/sightbench.gd` measures sight alone, without a network.
- Client: pictures of light are made again only when the light, the deck or the doors change
  (`WorldView._light_picture`), pools of light are remembered (`GameClient.glow`), the field of view and
  the light mask are redrawn only when something they depend on changed, and the field of view's rays
  look at each cell once. Script time per frame went from about 6.5 ms to about 1 ms on the test machine.
- Bugs fixed: E on a body lying in front also picked up the thing underfoot or took the ladder; E at a
  working engine, air plant, intercom, holomap or a locked door did the same (the server's order did not
  match what the player is shown); a plaster was used up on somebody with no wounds; a ship alongside
  that moved off or left could leave air behind in the open space where it had been (one could breathe
  there without a suit, and hear); searching a body that was cleared away went on with whoever took its slot next; a
  director door event could fail with no door left to choose; `tools/bench.sh` lost the clients' state
  checks when the server quit first.
- Docs: `CLAUDE.md` is now the short working notes; the decisions moved to `docs/DECISIONS.md` and the
  history to this file (`NOTES.md` is gone). `src/ui/bridge_view.gd` holds the chart and the helm.

### v50 (tractor and siphon beams; the author's answer to the beam card)

- The author picked both other beam ideas ("Option B+C. It's 2 different beams!"); the cutter stays too.
- Tractor beam (`Weapons.TRACTOR`): holds the enemy 8 s (`Gunnery.held`): +25% to our hits, its escape
  jump and docking countdown stand still; a holding shield stops it like the cutter.
- Siphon beam (`Weapons.SIPHON`): 4 pulses, each moves 12 shield from theirs to ours.
- Their cargo items are `Net.ITEM_GUN_MORE + w` (71, 72): 61 and 62 were already the rockets.
- Pirates do not carry the new beams yet. Protocol 30.

### v49 (shields, ship weapons, trader's window; the author's request)
- Ship weapons are swapped on the gun console with the cargo (the supply locker); the reactor gives 8 power to
  guns and shield. Ten weapons in `src/shared/weapons.gd` (all the numbers), shields by the author's rule
  (holds at 50+, leaks below), the shield generator 'Z' on the lower deck, the pirates' sixth room "Щиты".
- Our hull 200, pirates 12, pirates dock after 90 s. Enemy loadouts get a third gun 5 jumps out.
- The trader's window (`src/ui/trade_view.gd`): categories, buy, sell at half price; offers from the server
  (`S_TRADE`), 4 ship weapons per trader, the shield hardening at 1 in 3. Protocol 29.
- The beam: three ideas went to the author (cutter, tractor beam, siphon); the cutter is built as the default.

### v41 (ship's store, gun targeting, holomap; the author's request)
- The supply locker opens a "ship's store" window (`src/ui/store_view.gd`): resources across the top, every
  item as a card with its count, take with a click, buy with a right click, put back one thing by its slot
  (`Net.STORE_PUT_ONE`).
- The gun console (`src/ui/guns_view.gd`) shows the pirate ship's plan by rooms; the guns aim at one of its
  four systems (weapons, bridge, engine, quarters; `Net.ESYS_*`, rooms named by `%` lines in `maps/pirate01.txt`).
  Hits wear a system down and knock it out; its crew mends it. Server side in `src/server/gunnery.gd`.
- Holomap monitors ('M' in the map) on the bridge and in the engine room (`src/server/holomap.gd`,
  `src/ui/holo_view.gd`): the whole ship's air, breaches, broken machines and doors, sent only to whoever
  watches. New test `tools/holotest.gd` (15 tests now).

### v40 (friendly interfaces, the author's request)
- Inventory window (I/Tab, `src/ui/inventory_panel.gd`), settings window with sound, picture and keys
  (`src/ui/options_panel.gd`, `src/client/options.gd`, `user://options.cfg`), admin panel in four tabs
  (`src/ui/admin_panel.gd`, server side `src/server/admin.gd`, test `tools/admintest.gd`).
- Own footsteps are silent in a vacuum and in open space.

### v39 (engineering build)
- `game_server.gd` is split into modules by topic (`chat`, `crew`, `movement`, `inventory`, `looting`, `combat`,
  `repairs`, `systems`, `navigation`, `supplies`, `replication`); ships are `Ship` objects with a network id (`S_SHIPS`).
- The server decides who sees whom and sends each client only those characters (`Replication.sees`).
- All 13 tests run on every push (`.github/workflows/tests.yml`, `tools/runtests.sh`).
- Benchmark: `tools/bench.sh`, numbers in `docs/BENCHMARK.md`. Visibility made ticks ~3-6x dearer (32 players: mean 10.7 ms of 50).
- Still one crewed ship per server, though the code now keeps ships as objects.

## What the game has (as of v49)

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
