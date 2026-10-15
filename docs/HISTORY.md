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
