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
The plan under way (accepted 2026-10-19): `/mnt/project-files/plans/every-part-plan.md`, v67 and v68 done;
next v69 people over bots, v70 upkeep, v71 fear, then a question round on fire.

The darkness front (the fourth plan's item 3) is postponed: the author is still thinking it through.
The author's idea (VISION): "Fear of dark space", an entropy enemy ("the ship of darkness"), fighting it
as the finale. Next: ask the author what matters most and build the fifth plan.

Open problems:
- Sounds are made in code and walls don't shape them (only muffling by sight and thin air); no voice chat.
- Jobs are the same for every ship; crew size by ship size (from the survey) is not accounted for yet.
- One crewed ship per server for now (ships have network ids, groundwork for several).
- Builds are not published in GitHub Releases (the author did not answer).

## Build notes

### Game simulator (2026-10-19, no build; the author: "simulate 10 times full game, I need numbers")
- `tools/playthrough.gd` plays whole campaigns with a script captain and three bots; `tools/simreport.py` makes tables.
  Records in `/mnt/project-files/sims/2026-10-19/` (20 games: 10 careful, 10 hurried) and on the page "Spacer game sims"
  (https://claude.ai/artifact/1n6gfKcFtVKwPS9CtGi5xi). 3 of 20 won, all against a flagship grown 0 or 1 steps.
- Fixes the runs found (go into the next build; update the Claude Docs mechanics document then): the long jump with
  quest cargo aboard hit a script error; the roaming flagship could stay stuck in a dead end beside a station; a starving,
  lightly wounded crewman knocked out could never come round (`docs/MECHANICS.md`, Food and hunger).

### v73 (a friendlier game; the author's "very friendly UI for everything" and his 24 answers)
- Fixes: the airlock pump and the inner door's button take a chamber at a docked ship's pressure back to ours (he was
  trapped in it); the hunter's «поджидает» comes once, not every second. A pirate near its goal no longer paces back and forth
  for good (the rare airlocktest failure).
- Using things: the target of E is outlined, a ring fills while E is held, a right-click menu (use, work until done, step
  and use, drag, look, a bot's orders), use from a diagonal by one step to the side, hints with key badges.
- The screen: names under the mouse, labels on the heart monitor, oxygen bar and lamps, hotbar numbers and drag (also in
  the inventory), chat tabs and ×N repeats, red banners with a chime for danger, interface size 75–150%, Ctrl+wheel zoom.
- Consoles: ✕ on every frame, number keys for guns, jumps and locker tabs. The bridge's alert panel (his idea): the ship's
  needs in red, yellow and green on the sector console and the ship's controls.
- Protocol 50. Questions: https://claude.ai/artifact/L5C4LmRshPrQehcRoQJJKS. Build in `/mnt/project-files/builds/v73/`.

### v77 (the evening's bugs, the view following the mouse, bots on a slant; his answers on "Spacer v77 Movement and View")
- Seven notes from his evening with KaineQwQ: the trader's buy-cheap-sell-dear loop, the wreck spam while the jump
  charged, «KaineQwQ 2» after a lag drop, the dead ship missing after the rejoin, the chat sitting too low, the gas cloud's
  wrong hint, and the SOS dead ship that never came. All fixed; the bridge explains every kind of place.
- The view follows the mouse (a setting, on at first; half a turn in 1/3 s; the body turns in 8 ways for others to see).
- Bots, pirates and our robots walk on a slant (one 8-way search, `src/server/paths.gd`).
- New test `tools/eveningtest.gd` (36 scripts now); protocol 53. Version 0.70, build in `/mnt/project-files/builds/v77/`.

### v77.1 (his urgent note: a game-breaking bug, a video the same night)
- With the view following the mouse, a fast computer (many frames a tick) asked for the same turn on every frame until the
  first one took effect a tick later; each ask was queued a tick further on, so turns and the walking behind them ran
  seconds, then minutes, into the future: the character froze and never turned. Now one turn waits for the last to land
  (`GameClient.aim_at`, `facing_soon`). eveningtest spins the mouse for 4 s: inputs 421 ticks ahead before, 2 after.
  Version 0.70.1, build in `/mnt/project-files/builds/v77.1/`.

### v86 (his fleet notes and answers on "Spacer v86 Fleet and Fire": fleet fixes, the wingman, the shuttle)
- Five fleet notes fixed: the holomap shows its own ship, bots mend and take posts only aboard their own ship, the crew
  window groups bots by ship, a pirate docked to one ship is still a target for the other, pirates may come to the
  second ship. On hard pirates focus the weaker ship.
- A second pirate ship may join a fight (25 % of fights on normal) and fight from afar; the gun console picks which of
  the two to shoot; beaten, it pays; with the first one beaten it runs (protocol 62).
- The shuttle (his N1 idea): a force-field hangar on each ship, a dock console, 4 seats, 10 s between the ships.
- Fire waits (his FQ5 B); his fire answers kept for later. New tests `tools/wingtest.gd`, `tools/shuttletest.gd`
  (44 scripts). Version 0.79, build in `/mnt/project-files/builds/v86/`.

### v87 (his base sheet "man and woman, just for now" and two Notebook bugs; questions on "Spacer v87 Base Bodies")
- People are drawn from his base bodies (`body.png`, 32x48): a man or a woman picked on the main menu, bots and pirates
  by lot; only four ways (a slant shows the side); the top and shorts in the job's colour; a glass bubble round the head
  while on the oxygen tank. The v85 suited character stays unused for clothes later (protocol 63).
- Fixed: the fleet's two ships shared their gun charges (packed arrays were not copied per ship), so the second ship's
  gunner never fired; an admin-called pirate ship could not come while a wreck lay alongside (the wreck now drifts off).
- Checks added to `weartest` and `wingtest` (44 scripts). Version 0.80, build in `/mnt/project-files/builds/v87/`.
- v87.1 (0.80.1), his answers: no tank bubble (S4 B), no made step, figures slide standing (S7 B). Build in
  `/mnt/project-files/builds/v87.1/`.

### v88 (his suit sheets "full models for suited up"; questions on "Spacer v88 Suits")

- Anyone in a space suit is drawn from his suited man and woman: the visor clear, half or down by the oxygen tank, the
  suit's navy in the job's colour. `sprites/suit_man.png` and `suit_woman.png` replace them. v85's `crew.png` removed.
- Version 0.81, build in `/mnt/project-files/builds/v88/`.
- v88.1 (0.81.1), his answers and note: pirates' visors glow red (U2 B); the shadow is drawn by the game and lies along a
  body lying down. Build in `/mnt/project-files/builds/v88.1/`.

### v91 (his v90 answers and two pictures; plan on "Spacer v91 Plan")

- Machines stand on the floor in front of the walls, used from their front (his M1, M3, G1-G4); tall ones (lockers, SMES,
  engine, air plant...) block sight, low ones are seen over, none is walked through (his card pick). Our ship
  redrawn with 3-tall rooms, a big bridge and the holo table in its middle; old drawings move their machines out of the walls
  when loaded; a save of a redrawn ship starts its cells over.
- Stairs between decks (his F3): walk over a flight to change decks, dark going down, white going up; bots use them; one
  flight on our ship by the stern ladder.
- Doors: kinds from the drawing (`&` lines, the editor), lamps green (opens for you), yellow (opening), red (blocked for you),
  lamps on the floor by lockable doors, the danger
  line in airlocks, vents in his picture. Windows: outer and inner panes, upright windows, shutters at red alert and over a
  broken window (1 s, the room keeps its air). Boxes on the walls (first aid and spare parts from the locker's stock, fire box,
  light), the pump as his button, his ship icons on the chart.
- Protocol 65; new `tools/windowtest.gd` (45 scripts). Version 0.84, build in `/mnt/project-files/builds/v91/`.

### v90 (his tile set; questions on "Spacer v90 Tiles")

- His Aseprite tile set draws the walls, floors, see-through floors, windows (a row is one pane), doors (four kinds, lamps by
  state, open stages) and ten machines (wide ones over a row of their signs, seen from behind when facing up). The old mockup
  and the v89 sheet moved to `art_src/old/`; the build carries the old sheet in «sprites/old».
- Client only, protocol unchanged; `edittest` checks every look tile is in the sheet (44 scripts). Version 0.83, build in
  `/mnt/project-files/builds/v90/`.


### v90.1 (his note on the preview: "Wall dont have cross connection")

- Where a vertical wall meets a horizontal one from above, the joint is drawn now: the crossing and a new turned-T piece
  (`wall_tup`, at the end of the sheet) made from his T. Maps rebuilt. Version 0.83.1, build in `/mnt/project-files/builds/v90.1/`.

### v90.2 (his drawing of which wall pieces join)

- The crossing is his T under the wall that ends in `vertical_wall_to_T-shaped_corner`, the turned T his plain horizontal wall
  (v90.1's flipped T removed). Pictures only, maps unchanged. Version 0.83.2, build in `/mnt/project-files/builds/v90.2/`.

### v89 (his 18 Notebook notes; questions on "Spacer v89 Notes")

- Fixed: guns switched off by a power shortage (ion storm) now come back on by themselves; teleported pirates arrive
  suited; the heavy boarder in the new suit; a wreck no longer vanishes when our people leave it; bodies stay on wrecks and
  floating ones are left behind on a jump; bots climb ladders with a door or turret in front; a pile's things vanish one by
  one; sounds heard from the character's feet (silent nose); a drawn gun sight.
- His suggestions: the pirates' teleport 5 times rarer, with a 5 s warning (banner, hum, shimmer) and boarders spread over
  rooms; meteors 3 times, pirate events 1.75 times rarer, hunters 1.25 times fewer; click a system on the chart to jump;
  «К оружию» orders for bots; the «beaten» message tells the survivors.
- Protocol 64; checks added to `enemytest` and `defencetest` (44 scripts). Version 0.82, build in
  `/mnt/project-files/builds/v89/`.

### v85 (his answers on "Spacer v85 Ships": our fleet, the spriter's character)
- «Второй корабль:» on the main menu starts a fleet of two ships of ours, one below the other: each with its own hull,
  power, air, guns, lockers, fuel, food and bots, one purse, either helm flies both, each burns its own fuel. Pirates
  mostly pick the weaker ship; a ship whose hull breaks goes dark and the run goes on until both are lost. A guest picks
  a ship when joining. Saves keep both (protocol 61).
- The crew is drawn from his spriter's sheet (`sprites/crew.png`): job colours repainted, pirates in red, the visor down
  while on the oxygen tank (his C2 words), a small made step.
- New test `tools/fleettest.gd` (42 scripts). Version 0.78, build in `/mnt/project-files/builds/v85/`.
- His note for later: enemy fleets, more pirate ships joining a fight (in the vision).

### v84 (his answers on "Spacer v84 Next": hosting on your own ship)
- «Корабль:» in the main menu picks a new campaign's ship (the game's or a drawing from «ships»), with a small picture;
  a ship with no helm or no engine (or any red editor problem) cannot start. The menu has two columns (it fits 720 rows).
- The server sends its drawings of one's own to every guest in the welcome (protocol 60): friends copy nothing.
- The save keeps copies of the drawings it plays with; a continued run is on the save's ship.
- «Мои пираты, обломки и астероиды встречаются в пути»: own pirate ships join every pirate class's hulls, own derelicts
  and asteroids share those places by place.
- His bug note: a blow at a far tile drew its circle far away; now a swing in front, the circle only on a hit, a whoosh.
- An old rare server error when several players leave at once (a greeting to an already gone peer) is fixed.
- New test `tools/hosttest.gd` (41 scripts). Version 0.77, build in `/mnt/project-files/builds/v84/`.
- His other answers: after v84, several friendly ships (E1 B), then fire (v85, the simpler form: oxygen, burnt air and
  heat; he: "we will make it deeper in future versions"). No playtest evening soon (P1 B).

### v83 (his notes: crawl like SS13, the mouse in the middle, shots on the move)
- Lying down picks the head's side once; turning while down shows the turned-over figure for the new way and keeps the
  head in place, as his SS13 video shows. The camera, light and sight stay on one's spot when lying down.
- The mouse within 0.8 cell of one's body moves nothing (it shook the view and body); near the body turns need more.
- Shots and blows carry the shooter's id (`S_SHOT`, protocol 59): the trace starts where the shooter is drawn (it started
  behind a walker), and one's own kick works on the move; the kick is a little stronger, with a short shake.
- eveningtest checks the still mouse and the shooter's id. Version 0.76, build in `/mnt/project-files/builds/v83/`.

### v82.1 (his note: layers in the ship editor)
- Each cell has a floor layer and an object layer; objects keep their floor, the eraser takes the object first, a
  floor fill runs round objects; Q picks the layer the tools change, O hides objects. Editor only: no game rule or
  protocol change. Version 0.75.1, build in `/mnt/project-files/builds/v82.1/`.

### v82 (polish without extra depth; his worry that mechanics get too deep, his crawl video and a bug note)
- My second opinion on the page "Spacer v82 Polish" (https://claude.ai/artifact/NTp7NAbinskUYCEhKwCZVi): most deep systems
  already work if nobody touches them; a rule "the ship runs fine untouched, touching gives a bonus" (he chose B: case by
  case, no rule); count what people really use; a pause on new systems until a few evenings of play.
- Lying down and getting up as in SS13: the body turns over in 0.2 s, getting up takes 1 s with a bar (C again stays down);
  the name no longer turns red for one lying low by choice (his note).
- The autodoc alone heals past 50 at half pace (no one has to stand holding E). Per-run counts of 18 systems people used,
  on the end screen, in the save and in `usage.txt` (new part `src/server/usage.gd`).
- Found while adding the empty click: one never heard one's own shots, blows or doors. Now one does (only footsteps are
  played locally). A dry click, a reload sound, casings on the floor, a small camera kick, pickup and console sounds.
- From his answers: a green cross over anyone healing in an autodoc (and a bar of one's own health), soft work ticks and
  a "done" knock, a flick when a thing comes into the hand, a welded door's seam, and being hit: a small shake, a cry,
  red screen edges that deepen and darken with lower health.
- Own-ship hosting moves to v83 (his O1: yes). Protocol 58. Version 0.75, build in `/mnt/project-files/builds/v82/`.

### v81 (the ship editor; his answers on "Spacer v81 Ship editor", all "A")
- «Редактор кораблей» in the main menu: the game's own look, brush, line, rectangle, room, fill, eraser, picker,
  selection with Ctrl+C/X/V and moving, mirrors, undo/redo, a categorised palette with search and the last 9 signs on
  1–9, deck tabs, size, room marks (locks, brig, pirate systems), a live problems panel, saving to `ships/` next to the
  game with autosave each minute, «Попробовать» to play the drawing alone at once, «Обновить картинки» for the artist.
- The map builder now lives in the game too (`src/shared/map_builder.gd`, same result as `tools/make_assets.py`).
- His "can you make rooms more than 2 tiles": rooms any height from 2 (middle floor tiles in the sheet).
- His E1 "And asteroids!": asteroids are drawn maps that come alongside at an asteroid place; ore is dug from veins.
- The human wall (his note): X holds position; nobody passes, friends' shots fly past.
- Hosting a game on one's own ship: v82. New test `tools/edittest.gd` (40 scripts). Protocol 57. Version 0.74, build in
  `/mnt/project-files/builds/v81/`.

### v80 (the full run: his eleven bug notes, four suggestions and his answers on "Spacer v80 Playthrough")
- Bugs: no hole on a machine in the wall; bullets fly through open space; bots touch mounted guns only on the console's
  order (and a mend's hold no longer unmounts); a ship alongside stays at its mark once ours gets under way; a flying
  ship stops when one of ours goes out and the helm names who is outside; the worn suit shows its real air; blood only
  on floors; the flagship's chart mark above its system; bodies on a wreck or derelict kept when it leaves.
- His picks: emergency light at a third while the SMES carries the ship (P2 "1/3?"); a body lying low always lies across
  (L1); shots pass over people out cold (S1). His suggestions: a stronger shotgun up close (6 pellets of 15, knocks down);
  the right-click menu picks which body to drag or search and which thing to take from a pile (new `C_TAKE`).
- His top priority, a ship editor for his artist, and the human wall: question page
  https://claude.ai/artifact/68oyd5cH9wyAsoT5Gcwfww; my pick is the editor as v81. Several friendly ships: in the vision.
- New test `tools/fullruntest.gd` (39 scripts). Protocol 56. Version 0.73, build in `/mnt/project-files/builds/v80/`.

### v79 (polish after quarter steps; his answers on "Spacer v79 Polish" and his notebook note)
- The lying body (his note with a video) lies on the player's spot, head toward where they look (8 ways). People
  passing through one another are drawn stepping a quarter of a tile aside (his W1 note). With the mouse view the camera
  leans up to 2 tiles toward the cursor (a setting, 0–3).
- Bots run from armed boarders to open floor far away (by our people if possible) and lie low there; 8 s after the
  pirates are gone they go back to work. A guard bot takes a pistol (or shotgun) and two magazines from the supply locker
  and fights them (his B1 "B"). New server part `defence`.
- His Task Manager picture (the game's window "not responding" while it played on): vsync is off while the window is in
  the background, and the exe is named "Spacer". His PC confirmed the three old unknowns (server as a second process,
  no bar over heads, glass floors).
- Fire and gases question page: https://claude.ai/artifact/GrbXt4V21HzZUojDiYqEKk (the fire build after his answers).
  Fear waits until he has the concept.
- New test `tools/defencetest.gd` (38 scripts). Protocol 55. Version 0.72, build in `/mnt/project-files/builds/v79/`.

### v78 (quarter steps, lying down, friendly fire; his poll picks M1 "D", C1 "B" and his M2 words)
- Players step a quarter of a tile (8 px) a tick, the same speed as before, and stop on any quarter; everyone sees them
  there. The tile under the centre still decides air, doors, sight and use; the body never lies over a wall, a slant
  never over a doorway, and a player a quarter off a doorway slides into line. Bots, pirates and robots keep whole tiles.
- C lies down or gets up: crawling at half speed, shots fly over unless aimed at you. A friend right by the shooter
  (the next tile, slants too) is never hit; further on, still. Swapping places left out: people already walk through
  each other (said so in the thread).
- New test `tools/quartertest.gd` (37 scripts). Protocol 54. Benchmark at 32 players: tick 9.9 -> 12.0 ms (of 50).
  Version 0.71, build in `/mnt/project-files/builds/v78/`.

### v76 (his answers after v75)
- Out cold, a player may hold R for 2 s to give up: the character dies at once and R brings a new one from the reserve.
  Deep wounds killing in about 3 minutes stays (his yes). No numbers changed after the simulator (he will test himself);
  nothing published outside (the repository stays private). Version 0.69, build in `/mnt/project-files/builds/v76/`.

### v75 (polish; his 20 answers on "Spacer v75 Polish", all the recommended picks, and five notebook notes)
- Prisoners: a four-cell brig under the armoury (`@ deck x y brig`), cuffs slip only when awake, above half health and
  with none of ours in the room (his note: a prisoner in critical health got a pipe and escaped); no food for prisoners;
  brig hints on the holomap and under the mouse.
- Bots: a gunner mends its broken mount (his note), a bot with nothing to do leaves a room with no air (his note), a bot
  that reaches no new cell for 20 s is stuck and tries something else (also the same shutter forced 3 times: his «×5»
  note), two bots do not crowd a doorway, only breaches are said in «Всё». The old line «Воздух сам не вернётся» now says
  the vents bring the air back.
- Feel: hits flash red, leave blood and sound; broken machines spark; red alert tints the light; code-made menu music
  and a fight drone with their own slider; vent, pipe and hull-creak sounds. Sound kinds 10–15 had never played: fixed.
- Start and end: the run's story on the last screen (`S_SUMMARY`), the host's address with a copy button and the
  player list in Esc, a quiet first 5 minutes on easy and normal, a bug-report zip button.
- The simulator (S1): the script captain now sweeps systems for places, takes them, works anomalies and gas clouds,
  cuts scrap, fetches floating finds, sells at traders and fights boarders. 20 games
  (`/mnt/project-files/sims/2026-10-20/`): 0 won (3 of 20 before v67), on average about 150 credits earned against
  400 before, now mostly from selling finds (visiting no longer pays since v67); the hull loses about 280 a game (240 of
  it in 17 fights) and only about 100 is mended. No numbers were changed: they wait for the author.
- The simulator found a game that could never end: everyone out cold with boarders aboard, wounds over 100, nobody
  waking or dying. Such wounds now kill in about 3 minutes unless treated.
- The soak test (S3, `tools/soak.sh`): 2 game hours with 7 bots: tick at most 25 ms, 1 ms on average, no growth.
- New test `tools/polishtest.gd` (35 scripts). Protocol 52. Build in `/mnt/project-files/builds/v75/`.

### v74 (art and walking; his answers N2–N7, L1 and Z1 "B", his second-opinion answers and his notebook)
- Walking on a slant: two keys at once, 1.4 times a straight step (5 or 6 ticks), no cutting wall corners, doorways
  straight, sliding along a wall; 8 facings for sight, the flashlight, turning and using. Bots and pirates still walk
  straight (his answer: they should too, later).
- Art: characters drawn in 8 directions (`tools/make_assets.py` leans the figure for slants), the thing in hand drawn in
  the hand for everyone, and a `sprites/` folder next to the game for an artist's pictures (`src/client/sprites.gd`, names
  in `sprites/README.txt` made by `tools/spritelist.gd`, the sheets' originals in `sprites/original/`).
- The first-shift checklist (8 lines that tick themselves) and the help book on H (keys, machines, things, dangers, road).
- His notebook: bots no longer pass a job between them while fetching a patch (one «беру» per job in 30 s); a bot at a
  broken post console mends it first; the helm's chart shows the ship alongside; the work bar no longer stays after
  letting go of E. The rare airlocktest failure was checked: 200 runs clean since v73.
- New test `tools/walktest.gd` (34 scripts). Protocol 51. Build in `/mnt/project-files/builds/v74/`.

### v72 (the author's two notebook notes: bots at work, the boarders' wreck)
- Bots on a repair now raise an emergency shutter that is down when it is the only way to the job (suited only), mend
  before any other work, and free bots come to mend too. Each job is taken by one bot, which says so in chat.
- The bots' log: the crew window (O) keeps every order and job of every bot for the whole game, and the same lines go
  to `crew_log.txt` next to the game.
- A boarding ship wrecked before it docks stays alongside as a wreck (on the chart, dockable, its fuel can aboard).
- Looking at the author's old failed CI emails (v68): two of the three tests pass every time now; the third (salvagetest,
  1 run in 20) was a real bot bug: a suited bot shut in a room with no air stood still. Now it raises a shutter to get out,
  and work with no way to it is put off for 10 s.
- New test `tools/bottest.gd` (33 scripts), protocol 49. Questions: https://claude.ai/artifact/Ht1weGfuxFTaiJXPwywy63
  (built on my picks). Build in `/mnt/project-files/builds/v72/`.

### v71 (upkeep; the fourth step of the "every part interesting" plan, the author's H1, L1 and L2)
- Hunger slows and finally kills: after 10 min of starving everybody walks slowly, after 25 min health sinks with no
  floor (death about 68 min after the rations ran out). Any food at a jump ends it.
- The galley: a stove in the hydroponics room. Anybody cooks stew (wounds close for 5 min), coffee (work by hand
  takes ¾ of its time for 4 min) or herb broth (stops bleeding and concussion, +15 health) from rations and plasters.
  Bots do not cook.
- Complex repairs, a checkbox in the menu (ticked by itself for hard): consoles want a circuit board, the rest a
  mechanical part, and the one at work wants a toolbox. Without them the work is slower (3× each), never impossible.
- New test `tools/upkeeptest.gd` (32 scripts), protocol 48. Questions: https://claude.ai/artifact/Qtp5awvEXeZn5G4rjoXVL6
  (built on my picks while he slept). Build in `/mnt/project-files/builds/v71/`.

### v70 (people over bots; the third step of the "every part interesting" plan)
- A bot at a post gives half the help a person gives (helm, engine, shield, guns, the gun console, tending the autodoc);
  only a person presses the evade. The sailor is gone: a newcomer takes a free job.
- The autodoc alone heals only to 50 health; tended it heals fully and mends injuries. New injuries: bleeding, broken
  arm or leg (splints), concussion (no consoles for a person).
- The pilot steers round meteors in a stream (seen 2.5 s ahead) and clear of ion surges.
- Prisoners: stun baton, flashbang and handcuffs; the armoury is the brig; prisoners are sold, questioned or exchanged
  with their ship over the comms console.
- Boarders come for something: to wreck a machine, rob the locker, plant a bomb or drag one of ours off. New shotgun
  and welder (welds a door shut). Pirates now pick their way at every step (they used to go straight until a wall).
- New test `tools/peopletest.gd` (31 scripts), protocol 47. Questions: https://claude.ai/artifact/UsGtByhPuWjBu3PKWwPFVm
  (built on my picks while he slept). Build in `/mnt/project-files/builds/v70/`.

### v69 (bug fixes and two ideas; the author's notebook)
- Fixes: plasters and medkits treat yourself with a click anywhere on you or Z, and say why when nothing happens; the
  autodoc heals the worst off and can be tended from its bed; finds no longer vanish inside a docking ship's wall;
  people show at once when you turn; a hunter no longer waits forever while a ship is alongside (it pushes it off, or
  shells the hull while someone is outside), and a second hunter waits 45 s after a fight; no docking on the move; a
  supply station no longer trades like a trader; anyone can leave a locked room, and a hacked lock stays broken until
  mended.
- Wrecked pirate ships stay on the chart as places (moved a little away from traders and other places), and come back
  alongside when you return (the author's request in the thread).
- His two ideas: one press of an airlock door's button does the whole trip, and a vent in every room refills it from
  the air reserve (not while there is a hole).
- New test `tools/fixtest.gd` (30 scripts), protocol 46. Questions: https://claude.ai/artifact/9DBk13CrtNCfmyFPdQoL1N.
  Build in `/mnt/project-files/builds/v69/`.

### v68 (fights for the whole crew; the author's F1–F4, J4, E1 and G3 answers)
- The pilot's evade at the helm (button or space bar: 1.5–2.5 s of their shots hitting half as often, 40 SMES, 12 s rest).
  The engineer's power panel at the SMES: guns, point defence and shield switches (moved off the gun console), power for
  the engines (dodge), breakers for the lights, air plant and trays (energy for the guns), a risky reactor overcharge.
  Rounds carried by hand into a gun's breech (faster charge). Fights with goals: a cargo pod, a bounty, a courier.
  Green/yellow/red alert (red: bots to posts, doors locked, lights dimmed, siren). Breakdowns now come from pirate hits
  near the thing, never by chance. The fight's details are told on the bridge only.
- New test `tools/crewfighttest.gd` (29 scripts), protocol 45. Questions: https://claude.ai/artifact/BbM7SUq3yA36g4PBxrGA2q.
  Build in `/mnt/project-files/builds/v68/`.

### v67 (work and money on the road; the author's "every part interesting" answers, and "40 35 30")
- Fuel in units: a tank of 1000 (600 at the start), jumps 40/35/30 by the engine tier, flying in a system burns 0.1 a unit
  of distance, cans of 100 are poured at the engine (bots pour below 400), stations top the tank up to 300.
- Visiting pays nothing now; money comes from scrap (cut off dark ships' walls), ore and scan data, sold at full price,
  half as much again to a trader who wants them (each wants two things). Finds float outside near an airlock (a suit or the
  tractor beam brings them in). New places: anomaly, asteroid, gas cloud. The workbench refines scrap or ore into a can;
  scrap welds the hull from outside. Captured guns come as parts. Escaping a fight costs a parting volley and brings the
  next hunter sooner. Pirates no longer scale with our upgrades. Start money 80.
- New part `src/server/salvage.gd`, test `tools/salvagetest.gd` (28 scripts), protocol 44. The simulator's captain does not
  salvage yet, so the sims were not rerun.
  Build in `/mnt/project-files/builds/v67/`.

### v66 (airlocks; the author's note "feels like bots cannot do it", plus the simulator's fixes)
- Bots could not use the airlock: a bot in an emptied chamber stood at the inner door forever, and «за мной» stopped at
  our own hull. Now each airlock door has a button (E on the door, from either side, runs the pump: the author's answer),
  bots press it (or raise the shutter by hand without power), follow through the
  airlock, onto a docked ship and into space in a suit, and never lets the ship's air out. Pirates in suits cross space and
  force airlock doors. New test `tools/airlocktest.gd` (27 scripts in `runtests.sh`).
- Ships the fixes merged after v65 (PRs #34, #35, #37): quest cargo on the long jump, the roaming flagship stuck by a
  station, a starving knocked-out crewman never waking, the raider undock loop, respawn away from boarders, hunters slower
  after each escape.
- Choices made (my picks, open to the author): https://claude.ai/artifact/KuZruvE1aMGdyMBR7yCLLK.
  Build in `/mnt/project-files/builds/v66/`.

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

## v92: the fight in real time (the author's roadmap, item 0)

He wrote a long roadmap (2026-10-27): 0 a real-time fight like Starsector where every gun is worked by a person and
the pilot steers, 0.2 armour, penetration and ricochet, 1 procedural derelicts, stations and asteroids, 2 races,
3 more weapons and gear, 3.2 boarding pods and our teleporter, 4 breaching and entering. The plan is
`/mnt/project-files/plans/roadmap-v92.md` (v92 arena, v93 armour, v94 docking and pods, v95 polish, v96-97 places,
v98 arsenal, v99+ races); 28 questions on `https://claude.ai/artifact/V1AEJgkFnsjG9b8vk4DAmj`. Built on my picks
while his answers are pending:
- `src/server/arena.gd`: ships as bodies in space built from their drawings (`src/shared/arena_shape.gd`), flying
  and turning by class; the pilot's keys (C_PILOT), bot pilots to the battle position, pirate pilots by temper,
  drifting with nobody at the helm; guns as 180° turrets; shots that fly, lead their target and strike the cell
  they meet (Gunnery's hit code kept: `arena_hit`, `arena_bubble`, `arena_guard`, `arena_miss`); shield bubbles,
  point defence, beams in reach; collisions; the docking clock waiting while far; leaving past the edge.
- The client: `ArenaSeen` (S_ARENA every other tick, S_ARENA_SHOT once per shot) and `SpaceView`: the helm shows the
  fight in space in a fight, a gun mount can be taken by hand (use target 49, C_TURRET), V shows a small window.
- `tools/arenatest.gd` (30/30 passes); guntest and derelicttest keep the old fight (`arena.enabled = false`).
  Protocol 66. Nettest, lossy nettest and the soak test pass.

## v93: armour, penetration and ricochet; his note; goggles

The roadmap's item 0.2, his answers on "Spacer v93: броня" (`https://claude.ai/artifact/GePkt2SGzwqVSACbk6hZNJ`, all A
but O1 B) and on the v92 page (D3 C, the P1 note, P5 A), and one Notebook note with a picture of the v92 ship.
- Armour on every outer wall cell (`ArenaShape.edge`, `normal`): ours 2 (+ the armour module's tier), pirates 1..4 by
  class, windows 1. Penetration per gun (`Weapons.PENETRATION`), thickened by the slant (at most 2x); held shots only
  shake the ship; every hit wears the armour (2 for heavy guns); ricochets past 60° (kinetic 70%, lasers 30%) fly on
  and can strike another ship. Ours stays worn (`Ship.worn`, saved) and is mended from outside with a patch, by people
  and bots; the station, the bought hull and the admin make it whole. Clients see worn places (`ARENA_ARMOUR`).
- The shield a bubble or an arc on one side (E at the generator; 1.5x strength, half the wear). The pilot's mouse fires
  every free gun (`Net.ALL_GUNS`); the gun console shows the fight in space (Tab: the old screen). No dodge roll in space.
- Night vision and thermal goggles: a fourth wear place (`Net.WEAR_EYES`), sold by traders (30 and 45).
- His note: machines' "_up"/"_down" pictures swapped back (they faced the wall), the holo globe a tile higher, outer
  windows are his v2 pane with shutters, inner ones v1 without.
- `tools/armourtest.gd`, `tools/eyestest.gd` (30/30 each). Protocol 67, 48 test scripts. Mount kinds and choosing the
  enemy deck moved to v94.

## v94: the fight like Starsector; three mount kinds; his notes

The author: "make all guns work properly and rework the whole damage/shield/hull/armour system more like in Starsector,
so fights feel more alive". Questions `https://claude.ai/artifact/RFiT641SPv4FoHqLDujHRC` (19, built on my picks).
- Every gun has numbers in space (`Weapons.SPACE`: damage, shots, pace 0.3-12 s, heat, kind, clip) and fires on its own
  clock; Starsector's damage kinds against shields and armour.
- Heat (flux) per ship (`Arena.Body.heat`, `hard`, `FLUX_OF`): firing heats, the shield stops shots and heats, overload
  5 s, V vents; the pilot holds the shield with the right mouse button, the arc follows the mouse (`C_SHIELD`).
- Starsector's armour per outer cell (ours 150), hull points (ours shown 4000; every 100 through = a hit inside).
- Mount kinds: fixed, side, roof (`ArenaShape.MOUNT_*`, `^` lines, the editor's mark menu); turrets turn at a pace.
  Our ship has a fourth mount, a fixed laser in the lower deck's bow, switched off at the start.
- Ammunition rounds feed clips (`Mounts.clip`); beams, the siphon and the tractor work in space.
- The gun console always shows space (his note), Starsector-like bars for hull, heat and charges.
- His bugs: thermal goggles only in the view cone; a side wall's joint by the airlock looked broken off.
- `tools/fluxtest.gd` (every gun hits, heat, overload, vent, mount kinds, clips). Protocol 68, 49 test scripts.

## v94.1: his answers on the v94 page

He answered the 19 questions of `https://claude.ai/artifact/RFiT641SPv4FoHqLDujHRC`: all as built but three.
- S4 B ("only the shield heats"): our own shots heat nothing now (`Weapons.SHOTS_HEAT` off; the heat numbers are kept).
- M2, his note "better tie the weapon types to the points than give the points modifiers": a mount gives only its arc;
  each gun lists the mount kinds it goes on (`Weapons.FITS`: the biggest only the bow's fixed mount, the heavy ones
  the bow or a side), and turns at its own pace (light 120°/s, heavy 60°/s). Hand mounting, the gun console's orders
  and its list refuse a misfit; pirates fire each gun from a mount it fits.
- N1's comment ("so one can fire with no enemies near"): moved to v95 with the WASD system flight, where the space view
  is always on.
- Also: `Pirates.cut_in` never cuts in onto a walled-in nook (CI's rare peopletest failure after v94).

## v95 (0.88): flying round the system in space

His Notebook note ("the old control of the ship needs to be gone, so people see the ship as in the battle and can move
towards it by WASD around the map") with his N1 comment (fire with no enemies near). Questions on "Spacer v95"
(`https://claude.ai/artifact/Y5SD56y9aj1rZMF9KFEJGa`), built on my picks; he answered all A, with three comments.
- Our ships are bodies in space all the time (4 cells to a unit of the system's map). The ship control console shows
  space: WASD/QE fly, a click on the small map of the system sets an autopilot, any key takes over. Fuel burns only
  while the engines push; the system's edge is a wall; somebody outside or a ship docked holds the engines; the second
  ship keeps formation out of a fight.
- Guns fire with no enemy near (by hand, with the mouse at the controls or the gun console); shots meet nothing yet.
- No fight circle: a fight is where the ship is; breaking off is 170 cells from every pirate for 3 s; an ambush comes
  out of its place.
- Pirates' boarding pods: a boarding ship with a pod bay (his P2 note: "not every ship"; raider 40%, gunship 50%,
  cruiser 60%) kept away sends slow pods that pass the shield, meet point defence and our shots, and breach the hull
  where they strike, with 2 boarders. Assault drones fly in space the same way.
- His other comments for later: places drawn, dockable and landable, drawn only when near (F5); better bot fighting
  (P1). New test `tools/flighttest.gd` (50 scripts); protocol 69.
