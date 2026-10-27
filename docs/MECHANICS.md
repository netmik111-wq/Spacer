# Game mechanics

This describes everything already in the game: how it works and with what numbers. The document
grows with every build. What the game doesn't have yet is not written here: that is in
`docs/VISION.md` (the author's vision and plans).

Last updated: build v89 (version 0.82).

Contents:

1. [Basics: server, ticks, network](#1-basics-server-ticks-network)
2. [Ship: decks, floors, ladders](#2-ship-decks-floors-ladders)
3. [Doors and emergency shutters](#3-doors-and-emergency-shutters)
4. [Air and breaches](#4-air-and-breaches)
5. [Health, wounds and death](#5-health-wounds-and-death)
6. [Spacesuit and oxygen](#6-spacesuit-and-oxygen)
7. [Engine and power](#7-engine-and-power)
8. [Machines, breakdowns and repair](#8-machines-breakdowns-and-repair)
9. [Items and inventory](#9-items-and-inventory)
10. [Supply locker, trader, credits](#10-supply-locker-trader-credits)
11. [Light and darkness](#11-light-and-darkness)
12. [Field of view](#12-field-of-view)
13. [Sounds](#13-sounds)
14. [Weapons and combat](#14-weapons-and-combat)
15. [Healing](#15-healing)
16. [Helping the fallen: searching and dragging](#16-helping-the-fallen-searching-and-dragging)
17. [Pirates](#17-pirates)
18. [Bridge and flight within a sector](#18-bridge-and-flight-within-a-sector)
19. [Space, sectors and jumps](#19-space-sectors-and-jumps)
20. [Eventer (GM)](#20-eventer-gm)
21. [Crew, jobs, reserve](#21-crew-jobs-reserve)
22. [Speech, radio, intercom](#22-speech-radio-intercom)
23. [Campaign: hull, end, saving](#23-campaign-hull-end-saving)
24. [Controls](#24-controls)
25. [The road: comms console, quests, food, hydroponics, modes (v63)](#25-the-road-comms-console-quests-food-hydroponics-modes-v63)
26. [Work and money on the road (v67)](#26-work-and-money-on-the-road-v67)
27. [Fights for the whole crew (v68)](#27-fights-for-the-whole-crew-v68)
28. [People over bots (v70)](#28-people-over-bots-v70)
29. [Upkeep: hunger, the galley, complex repairs (v71)](#29-upkeep-hunger-the-galley-complex-repairs-v71)
30. [Bots at work and the bots' log (v72)](#30-bots-at-work-and-the-bots-log-v72)
31. [A friendlier game (v73)](#31-a-friendlier-game-v73)
32. [Art and walking (v74)](#32-art-and-walking-v74)
33. [Polish (v75)](#33-polish-v75)
34. [The evening's bugs, the view and bots on a slant (v77)](#34-the-evenings-bugs-the-view-and-bots-on-a-slant-v77)
35. [The full run's fixes (v80)](#35-the-full-runs-fixes-v80)
36. [The ship editor, asteroids, holding position (v81)](#36-the-ship-editor-asteroids-holding-position-v81)
37. [Polish without extra depth (v82)](#37-polish-without-extra-depth-v82)
38. [Hosting on your own ship (v84)](#38-hosting-on-your-own-ship-v84)
39. [Our fleet and the new character (v85)](#39-our-fleet-and-the-new-character-v85)
40. [The fleet's fixes, the pirates' wingman, the shuttle (v86)](#40-the-fleets-fixes-the-pirates-wingman-the-shuttle-v86)
41. [Man and woman base bodies (v87)](#41-man-and-woman-base-bodies-v87)
42. [Suited man and woman (v88)](#42-suited-man-and-woman-v88)
43. [The Notebook's 18 notes (v89)](#43-the-notebooks-18-notes-v89)

---

## 1. Basics: server, ticks, network

- The server decides everything. The game runs in ticks: **20 ticks per second**.
- A character crosses a cell in **0.2 s** (5 cells per second). Someone dragging a body moves half as fast.
- **Quarter steps** (v78, the author's M1 "D"): a player moves a **quarter of a cell** (8 px) each tick, so at
  the same speed, and stops wherever the key is let go: on the centre of a cell, a quarter or half of one off.
  Everyone sees them there. The cell under the character's **centre** counts for everything else: air, doors,
  sight, using things. The body is a cell wide, so it may lie over the next cell only if that cell is open
  floor; on a slant it never lies over a wall corner or a doorway. Walking into a doorway or a corridor a quarter
  off, the character slides into line by itself. Bots, pirates and robots still step whole cells.
- **Lying down** (v78, C1 "B"): **C** lies down or gets up. Lying, you crawl at **half speed**, and shots fly
  over you unless they are aimed at you (meant for a point within **1 cell** of you). Climbing a ladder or
  being knocked out stands you up. (v79, the author's note and L1 "A") The body lies on the spot where you are,
  seen from above, **head toward where you look** (8 ways), so it always matches your light and view.
  (v80, his note "feels very strange" and L1 "A") It always **lies across**: head to the left or right, the side you
  look to; looking straight up or down keeps the last side.
  (v83, his SS13 video) The side is chosen **once, as you lie down**: turning while down keeps the head where it is and
  shows the figure turned over for the new way (face up, face down, on its side), as in SS13. Lying down no longer
  moves the camera or your light: they stay on your spot.
- (v79, the author's W1 note) People still walk through one another. Two close together (under **1 cell**
  apart) while either walks are drawn **stepping aside**, each up to a **quarter of a cell** off its line, as if
  sliding past; only the picture moves. Two standing still keep the spots they chose.
- Pressing a direction **turns** the character **immediately**, even mid-step or facing a wall.
- **Wall objects** (consoles, racks, locker, engine, air plant, intercom, airlock
  pump) face one room (down if there is floor there, otherwise up or sideways). They can be used
  only from there: standing directly in front of them or one cell to the left or right, facing the wall.
  Not through the wall from the neighbouring room. Breaches and doors — from any side.
- **Left-clicking** something within reach that E works on (v45, the author's request) turns the
  character to it and does what E would: picks up an item from the floor (ahead or underfoot), opens
  a console (sector map, ship control, guns, holomap), the supply locker or the intercom, searches
  a person lying down (with an empty hand), takes the ladder underfoot, switches an airlock pump.
  **Holding** the button holds E: repairing a breach, a machine or a door, forcing a shutter,
  refilling the tank, hacking a lock. The same reach rules as E: next to it, and a thing on a wall only
  from the room it faces. A weapon or something to heal with in hand, clicked at a person (or
  yourself), is used on them instead.
- **Left-clicking** anywhere else turns the character towards the click (in place, without a step),
  then uses the item in hand if it can do anything.
- The game shows your own movement immediately, without waiting for the server, and corrects it if the server
  decided otherwise. So even at 200 ms ping walking feels comfortable.
- The server sends each player only what is nearby: a 3×3 area of 16×16-cell chunks around
  them, on all decks at once. Every 2 seconds the game checks its knowledge of the world against the server.
- Of the people in that area, the server sends only those your character can actually see (see
  [Field of view](#12-field-of-view)), so nobody can find out from the game's data where someone
  hidden from them is.
- The ship is one object with its own network number; a derelict or pirate ship alongside gets one
  of its own. (Nothing changes for the player yet: this is the ground for several crewed ships later.)
- «Новая кампания» ("New campaign") and «Продолжить кампанию» ("Continue campaign") start the server as a separate program in the background. The game host is also the GM:
  they have access to the eventer menu.

## 2. Ship: decks, floors, ladders

- New ship (build v25), nose to the right. It has **two decks**:
  - **upper**: bridge in the nose (sector map, ship control, a spot for the gun console),
    a long corridor, two-door airlock, armoury, medbay, workshop, cabins, two compartments
    for the side guns (empty for now);
  - **lower**: engine room (engine), life support (air plant),
    cargo store, hold with the supply locker, a compartment for the belly gun (empty for now), corridor.
  - Ladders: corridor by the bridge ↔ lower corridor, workshop ↔ hold.
  - Glass in the corridor above the engine and above the air plant: their light is visible from above.
  - New people appear in the upper-deck cabins and in corridors, not in restricted compartments.
  - **Intercoms** — four panels on walls: cabins and corridor upstairs, bridge, store and
    corridor below, corridor and hold below (see section 22).
- (v81) Rooms may be any height from **2 tiles** up (before: exactly 2); a room's middle rows get floor without the
  wall's shade. A room one tile tall is still impossible (the editor says so).
- **Glass** (transparent floor): you can see the lower deck through it; air does not pass.
- **Catwalks** (grating): you can see down, air passes between decks.
- **Hatch with ladder**: you can see down, air passes, you can climb down.
- **Ladders** are used with the E key while standing on their cell. A dragged body goes along with the dragger.
- From the deck above, only those standing on a transparent cell are visible; names are hidden along with the people.
- Air flows between decks half as fast as along a deck.

## 3. Doors and emergency shutters

- Doors **open by themselves** when you walk into them (0.3 s) and close after 2 s. A door
  won't close on someone standing in the doorway.
- A closed door holds air; an open one equalises pressure between compartments.
- **Without power** doors open by hand: a push taking 1.5 s.
- Every door has an **emergency shutter**:
  - it drops by itself when the pressure difference across the door is 25% or more;
  - it rises by itself when the difference is under 10%;
  - you can't walk into a dropped shutter; it shows two pressure lamps, one on each side
    (green — normal, yellow — low air, red — near vacuum);
  - the hint at the door gives the difference in kPa and which side is lower;
  - raise it by hand: hold E for 3 s, the shutter stays raised for 5 s;
  - without power shutters neither drop nor rise, and the lamps go dark.
- **Restricted compartments**: bridge, armoury, medbay, both side gun compartments,
  engine room, life support, belly gun compartment. The closed door of such a
  compartment opens only for those whose job gives access to it (see section 21).
  - A lock lamp glows on the door frame: **green** — you may enter, **red** — you may not.
  - The lock can be **hacked**: hold E for **5 s**. The door opens, and the ship announces to everyone
    who hacked it and where.
  - **Without power** locks don't work: the door opens by hand like any other. That way
    the path to the bridge remains even when everything is broken.
  - (v69, the author's note) **Leaving is always free**: a locked door opens for anyone walking out of its
    compartment, so nobody is shut in (coming back from space short of oxygen, say).
  - (v69) A **hacked lock stays broken**: the door opens for everybody and its lock lamp glows **amber** until
    someone mends it (hold E, 6 s with a spare part, which it uses, 18 s without).
- Door troubles (eventer events):
  - **jammed open**: air moves freely until repaired;
  - **shutter faulty**: stuck as it was, raised or dropped, until repaired.
  - Both are repaired by holding E (6 s with a spare part, 18 s without).

### Two-door airlock

- A 3×2-cell **chamber** between the **inner** door (to the corridor) and the **outer** one (to space;
  a docking port will be above it).
- Only **one** door can be open: the second won't open until the first closes.
  If the second is jammed or open, the interlock can be **released by hand**: hold E for 3 s,
  and the door can be opened within the next 5 s (otherwise a jammed outer door would lock
  the crew outside the chamber forever).
- The outer door is held by its emergency shutter while there is air in the chamber; the inner one while
  the chamber is in vacuum (the same 25% and 10%, space counts as pressure 0). It can be raised by hand
  like any shutter, but then the air escapes.
- **Pump** on the chamber wall: E starts and stops it. It works only when both
  doors are closed and there is power.
  - If the chamber has more than half its air, it pumps it out into the **ship's air reserve**
    (the excess goes overboard), otherwise it pumps air in from the reserve. A full chamber takes ~5 s.
  - With no air reserve there is nothing to pump in: the only option is to raise the inner shutter by hand.
  - (v54) With a ship **docked** at the outer door that holds air, the pump brings the chamber to **that ship's
    pressure** instead (in or out), so the outer door opens onto it; the inner door then follows the usual rule.
  - (v73, the author's note: stuck in the airlock beside a pirate ship) a chamber **already at the docked ship's
    pressure** is pumped back to **our own side's pressure** (in or out), so the inner door opens; the inner door's
    button does the same. Before v73 the pump only knew the docked ship's pressure, and the way home was by hand.
- An open outer door vents the air in its doorway into space.
- (v66, the author's request) **A button by each airlock door**, from the corridor, from the chamber and from space:
  pressing **E** on a shut airlock door held by its shutter runs the chamber's pump so that this door can open (in for
  the inner door, out for the outer one, to a docked ship's pressure at the outer door); ~5 s. It needs power, both doors
  shut and, to pump in, air in the reserve. Holding E still raises the shutter by hand.
- (v69, the author's idea) **One press does the whole trip.** E on either airlock door (from the corridor, the
  chamber or space) shuts the chamber's other door, runs the pump (air out goes into the ship's reserve, air in
  comes from it) and then **opens the pressed door by itself**; it stays open at least **3 s**. A press gives up
  after **40 s** or when the power goes.
- (v66) **Bots and pirates get through the airlock too.** A bot of ours whose way leads through a door that will not
  open presses that door's button and waits; with no power or no air in the reserve it raises the shutter by hand
  (3 s, as above). It waits while the chamber's other door is merely open (that one shuts by itself), and it
  never releases the interlock while the other door is stuck open, so a bot never lets the ship's air out.
  Pirates don't pump: they force the shutter or the interlock by hand.

### Open space

- From the airlock you can **go out into open space** and move around the ship. A step there takes twice
  as long (0.4 s), there is no air: you need the oxygen supply, the pressure lamps light as in a vacuum.
  In a vacuum it is silent.
- (v66) Bots go out into space only in a suit: when following a player who is out there (or to mend the hull, v61),
  and they find their way back in. Pirates in suits cross space too.

## 4. Air and breaches

- Each cell has its own pressure (a single number, no gas composition).
- A hull **breach** vents air outside: a 10-cell compartment loses half its
  air in about 8 seconds.
- **Lack of air is not shown** on screen (the author's decision). You can only tell from
  the instruments: the O2 LOW and kPa lamps. Air streaks are visible only right at the breach.
- **Sealing a breach**: face it and hold E for 6 s; a **patch** is needed.
- A sealed compartment stays without air until you open a door to an intact one. Air lost to space
  is returned by the air plant and the supply station.
- (v69, the author's idea) **A vent in every room** of our ship (drawn as a small floor grille; none in the
  airlock chamber). Fed from the ship's air reserve, it tops its room up to **95%** of normal pressure at the
  air plant's pace (**0.012** of a cell's air per air step). It needs power, a working air plant and the air
  breaker on; it **stops while the room has a hole in the hull** and starts again once the hole is sealed. So a
  sealed-off compartment fills again by itself while the reserve lasts.

## 5. Health, wounds and death

- Health on the SS13 scale: **100** — unharmed, **0 and below** — unconscious, **−100** — death.
  The pulse monitor in the corner shows eight states.
- Below 76% of normal pressure there is nothing to breathe: up to **3** health per second. Below 20%
  the pressure itself harms you: up to **2** more per second. In a vacuum: unconscious after ~20 s,
  death after ~40 s.
- In good air health returns: **1** per second when conscious, **0.5** when
  unconscious. You come to at **10** health.
- **Wounds** (from bullets and blows) are kept separately and **don't heal by themselves**: health
  rises only up to "100 minus wounds". A badly wounded unconscious person won't wake up
  until treated. (v75) Wounds of **100** or more leave nothing to come back to: such a person lies
  dying, **0.5** health a second (about 3 minutes from 0 to death), unless an autodoc or a medkit
  treats them first. (v76) A player out cold (not just stunned) may **hold R for 2 s** to give up: the character
  dies at once (the body stays), and R brings a new one from the reserve as after any death.
- The screen darkens below 40 health. The unconscious and the dead lie down.
- **Bodies remain** where they fell (the author's rule). Above 30 bodies, the oldest is removed.

## 6. Spacesuit and oxygen

- The spacesuit (helmet and tank) is clothing: it can be **taken off and put on** (see "Clothing"). Every
  new crew member arrives wearing one. Without a spacesuit the **oxygen supply doesn't work**:
  there is no protection in a vacuum or without air.
- A removed spacesuit is an item, and its tank keeps how much oxygen is left in it (in tenths).
- The only control on the spacesuit is the **oxygen supply** (Q).
- While the supply is on and the tank isn't empty, the surrounding air doesn't matter: no suffocation, no damage
  from pressure. A full tank lasts **2 minutes**.
- The supply doesn't turn on by itself: the player has to notice the lamp and press Q.
- **Refilling**: face the red oxygen rack and hold E; a full tank in 3 s.
  The rack needs power, and only a worn spacesuit is refilled.

### Clothing

- Three clothing places, to the left of the slots: **spacesuit**, **jumpsuit**, **backpack**.
- **Put on**: take it in hand and press Z. If something is already worn there, it goes into your hand
  (a swap).
- **Take off**: click the worn item, it goes into your hand (or a free slot). The jumpsuit
  and backpack can't be taken off while their places hold items.
- The **jumpsuit** gives 2 pockets (slots 7–8), the **backpack** 4 more places (slots 9–12).
  Without them these slots stay empty and look pale.
- New crew member: spacesuit with a full tank and jumpsuit, no backpack (8 slots).
- Appearance: in a spacesuit with a helmet; without a spacesuit in a jumpsuit and no helmet; with no
  clothing at all in grey underwear. The backpack is visible on the back.
- From a person lying down (search) clothing can be removed by clicking it. You can't dress a person
  by clicking, but you **can give a spacesuit to an unconscious person** (not a dead one): it goes
  onto them and their oxygen supply is turned on, so they don't suffocate in space.
- A dead player returns (R) in a new spacesuit and jumpsuit; the old ones stay on the body.

## 7. Engine and power

- **The rule since v61** (the author's word): **no engine and an empty SMES means no power**, and
  nothing breaks from it. Without power:
  - the ship doesn't move or jump, a jump in progress is aborted;
  - consoles, air plant, oxygen racks, emergency shutters don't work;
  - doors open only by hand;
  - the lights go out (see "Light and darkness").
- The spacesuit, the player's instruments, ladders and repair don't depend on power.
- **Power numbers.** The ship's own draw (lights, air, doors, consoles, pumps) is **4** a second. The reactor
  gives the guns and the shield **8** (10 and 12 with better reactors, section 17 "Ship gear"); the engine
  makes both.
- **SMES** (v61, `S` on the engine room's top wall, ship02): a store of power. Full it holds **2160** units
  (3 minutes of 12, the whole ship in a fight). It:
  - **charges** only from what the reactor has spare after the guns and the shield, up to **6** a second
    (out of a fight the guns stand idle, so it charges from the whole reactor);
  - **adds up to +3** to the reactor's power for the guns and the shield in a fight while the engine runs
    (the gun console shows it); it pays only for what is used above the reactor;
  - **carries the whole ship** when the engine is broken or stalls: the ship's own 4 a second, plus the guns
    and the shield in a fight, up to its output (12, at most 15). Out of a fight a full one lasts about
    9 minutes, in a fight about 3. The crew hears it at 50%, 20% and 5%;
  - **a hit takes its whole charge** (it breaks like a machine; a spare part mends it). Pirate ships aim at
    it like at the shield generator; the flagship battleship goes for it right after the engine.
- **SMES terminal** (E on the SMES, works with the ship dark): charge and state, charging on/off, output
  on/off, input target (0..6), output target (0..15). Its lower half is the **power monitor**: what the engine
  makes, what the ship draws, the power for the guns, how long the charge lasts. The holomap shows the
  same monitor.
- **SMES coils** (gear, installed at the SMES by an engineer): «Ёмкость» ×1.5 charge, +2 a second
  (80 cr); «Сверхпровод» ×2 charge, +4 a second (160 cr). Sold by arms dealers and the black market, found in wrecks.
- **Bridge backup SMES** (`Q`, bridge wall): **360** units, charges itself 2 a second while the ship has power.
  When the ship is dark it keeps the **bridge room lit and its consoles working** for about 6 minutes.
  It cannot make a jump: a jump needs the engine.
- **Power failure** (event): the engine stalls for 8–15 s with nothing broken; the SMES carries the ship
  through it, so only an empty SMES makes it dark.
- (v80, his note "the lights don't go out in a blackout", P2 "A", "1/3?") While the SMES carries the ship (the engine
  down or stalled), the ship runs on **emergency light**: **a third** of the light everywhere but the backup-lit bridge.
  Machines work as before.
- **Ion storm** (v61, a kind of sector): see section 19.

## 8. Machines, breakdowns and repair

- **Engine** — lower deck, engine room, under the corridor glass. Its state is visible from the light on the
  floor: blue — working, flashing red — broken. Also visible from above, through the glass.
- **Air plant** — lower deck, under the corridor glass. Slowly adds
  air to its compartment, not above normal, and uses up the **ship's air reserve** (60 cells).
  When the reserve runs out, it stops.
- **Bridge consoles** break (short circuit): dark screen and sparks.
- (v68, the author's E1) **Breakdowns never come out of nothing** any more: the eventer no longer picks a console fault,
  engine fault, air plant fault, jammed door, shutter fault or power glitch by chance (the host can still fire them). They
  come from **pirate hits** near the thing (section 27) and from **overcharging** the reactor.
- The "not both at once" rule: while a console is broken, the engine doesn't break, and vice versa. So the
  crew always has a way to escape.
- **Drone monitor** (v54) — the fifth console, on the bridge's top wall between the helm and the holomap: the
  scouting drone's screen (see "Scouting drone" under Pirates).
- **Holomap** — a monitor with a blue screen on the bridge wall and in the engine room (top wall). E opens
  the whole ship deck by deck: every floor cell coloured by pressure (blue normal, from 76%; yellow
  lowered; red dangerous, below 20%; dark red vacuum), breaches blinking red, machines and consoles
  (green working, red "!" broken), doors (closed, emergency shutter down in yellow, jammed in orange)
  and a dot where you stand. Above the plan: hull integrity, number of breaches, what is broken,
  how many compartments have lowered pressure or almost no air, shutters down, jammed doors. The mouse
  over a cell shows its pressure in kPa and what is there. Updated twice a second; needs power.
  This is the only place the game shows air in rooms you are not in (the author asked for it).
- **Mending the hull from outside** (v61): in a suit, out in space, face a whole cell of our hull with a
  **patch** and hold E: **+15** hull per patch (v67, the author's H2; was 10), **10 s** (the repair skill cuts it to
  half), up to 200. (v67) With no patch in pockets, a piece of **scrap** is welded on: **+10**.
  A bot on «Работы» does it by itself when the hull is below **80%** with nothing to mend aboard and no
  fight: it takes up to 3 patches and a suit from the locker, fills its tank, pumps an airlock out, floats
  out, mends, comes back and pumps the chamber full. A pirate showing up calls it back.
- **Repair**: face the broken thing and hold E. With a **spare part** 6 s (the part is used up),
  without one 18 s. That is for a person without skill; the repair skill cuts the time by up to half
  (with skill 50 — 4.5 s, with skill 100 — 3 s; see section 21). (v71) A **circuit board** («Плата») counts as a spare
  part too; with **complex repairs** on, a machine wants its own kind and a toolbox (section 29).

## 9. Items and inventory

- Everyone has **6 slots**, plus **2 pockets** with a jumpsuit and **4 places** with a backpack; one item
  per slot. A dead person's items stay on the body.
- **Hand**: one slot is highlighted, that is what's in hand. Choose with: 1–6, mouse wheel, clicking
  a slot. A picked-up item goes into the hand if it is empty.
- **G** — drop the item in hand on the floor at your feet. Up to **4** items per cell.
- **E** — pick up: first what's ahead, then what's underfoot. Whatever E works on in the wall ahead
  (a console, locker, machine, oxygen rack, intercom, holomap, a breach or a door in trouble or locked to
  you) and a person lying ahead or underfoot take priority: E goes to them and picks up nothing, and
  takes no ladder (since v51 the server keeps exactly this order).
- **Z** — use the item by itself (turn on the flashlight, put on clothing).
- **Clicking** an item on the floor next to you or underfoot picks it up, like E (v45).
- **Clicking** the world elsewhere — use the item at that spot (shot, blow, healing).
- **Inventory window** (I or Tab): everything worn and carried, large and with names, grouped as
  kept: 6 at hand, 2 jumpsuit pockets, 4 backpack places (a group without its clothing is marked
  as needing it). Under it: what is in the hand, its state (rounds, uses, oxygen), what it does,
  free slots, and buttons to use, wear, drop and switch the oxygen supply. Click a thing: into the
  hand; right click: onto the floor; click clothing: take it off. You can walk while it is open.
- All items:

| Item | Purpose | In locker | Price |
|---|---|---|---|
| Patch | seal a breach | 8 | 5 |
| Radio | talk with «;» — everyone with a radio hears | 4 | 6 |
| Fuel | a can of **100 units**, poured into the tank at the engine (v67) | 2 | 12 |
| Spare part | repair three times faster | 5 | 10 |
| Flashlight | soft round pool, 6 cells | 4 | 8 |
| Pistol | 8 rounds, damage 30 | 1 (empty) | 25 |
| Magazine | 8 rounds | 2 | 6 |
| Baton | damage 15 to a neighbour | 1 | 8 |
| Plaster | closes 40 wounds at once | 2 | 6 |
| Medkit | 5 uses of 30 wounds, 3 s | 2 | 15 |
| Spacesuit | helmet and oxygen tank | 2 (full) | 40 |
| Jumpsuit | 2 pockets | 2 | 8 |
| Backpack | 4 places | 2 | 15 |
| Scrap («Лом», v67) | cut off wrecks; sold (4), welded onto the hull outside, refined into fuel | 0 | 4 |
| Ore («Руда», v67) | from asteroids; sold (6), refined into fuel | 0 | 6 |
| Scan data («Данные сканирования», v67, cargo) | from anomalies; sold (25) | 0 | 25 |

## 10. Supply locker, trader, credits

- The **supply locker** is a yellow locker in a lower-deck wall. E opens the **ship's store** window
  (the locker doesn't need power):
  - across the top: credits, (v67) the fuel tank (bar, units, jumps it holds and cans in the locker), air for the plant (bar), hull integrity (bar),
    crew reserve (bar);
  - every item the locker keeps as a card with its picture, how many are in the locker and how many you
    carry, grouped: repair and fuel, equipment, medicine, personal weapons, ship weapons, ammunition
    (the last two are cargo: they can't be taken into the hands). (v65) The groups sit under **tabs**:
    Всё (everything), Припасы (repair, fuel, food, medicine), Снаряжение (equipment, personal weapons),
    Орудия (ship guns, ammunition, gun parts), Модули (ship gear: all its kinds, even at ×0), Разведка и охрана
    (probe, drone, security robot), Семена и задания (seeds, quest things). A group longer than a row (10 cards)
    wraps onto more rows, so the window keeps one width (fits 1280×720); the cards scroll. Ship guns, gun parts,
    seeds and quest things show only when held; in «Всё» ship gear too. Long names go on two lines. Left click on a card takes one
    (into the hand if it is empty); right click buys one when a trader is in reach (the price shows on
    the card); hovering shows what the item does;
  - your own slots underneath: click one to put that item back (only whole items; the frame is green
    on those that can go back), or "put everything back";
  - at a trader, the button "Торговля" opens the trader's window.
- Only whole items go back: a used medkit can't be swapped for a new one, a loaded
  pistol goes back empty, a spacesuit only with a full tank.
- The ship sets out with **80 credits** (v67: was 30), **600** units of fuel in its tank, **2** cans and a full air reserve for the plant.
- **Credits** (v67, the author's M1): visiting a new system pays **nothing**, "so people roam around and don't rush". Money
  comes from work: selling scrap, ore and scan data, wanted goods, pirate rewards, quests (section 26).
- **Trader**: fly the ship up to it; trading is done at the locker, power is needed.
  The **trader's window** (v49) sorts its goods into categories on the left: all, repair and fuel, equipment,
  medicine, personal weapons, ship weapons, ammunition, scouting (v53: the probe), services and upgrades. Each row shows the item, how many
  the locker holds, a **buy** button (its price) and a **sell** button: the trader buys any priced item from the
  locker for its share of the price (see below; things you carry must be put in the locker first).
  **Since v58 traders deal in different things** (the author's tiers plan), shown on the chart and in the
  trader's window:
  | Trader | Sells | Buys at (plain things / guns / ammunition and parts) |
  |---|---|---|
  | Оружейник (arms dealer) | ordinary items, rockets (4), EMP rockets (6), shells (3), **3–5 ship guns** (tiered by how far out it is, like the pirates'), **1–2 crates of ship gear** (v59) | 20% / 50% / 50% |
  | Барахольщик (junk dealer) | ordinary items **20% cheaper**, **1 crate of gear** 20% cheaper (v59); no guns, no ammunition | 20% / 20% / 20% |
  | Чёрный рынок (black market) | ordinary items, ammunition, **1–2 guns a tier above** what is usual there, **1 crate of gear a tier above** (v59), at **1.5×** the price | 30% / 30% / 30% |
  Every trader within **2 jumps** of the start is an arms dealer. A trader has **one** of each ship gun: once
  bought it is gone from that trader. A gun of tier 3 is offered with its effect already rolled. Whatever you
  sold a trader can be **bought back** at the price it paid (a guard against a mistaken click; the list shows
  under "Выкуп"). What each trader sold and bought is saved with the campaign.
  Services: (v67) **fuel straight into the tank** (+**100** units for **12** credits), air for the plant (10 cells for 5 credits), **hire a person into the crew reserve** (**30** credits,
  no more than 9 in reserve), **patch the hull** (+**20** integrity for **10** credits).
- **Supply station**: when docked, free of charge it restores air in the compartments and the plant's reserve,
  tops the fuel tank up to **300** units (v67) and patches the hull completely.
  (v69, the author's note) It is **not a trader**: no selling, buying back, hiring or paid services there. Its
  locker screen («Станция снабжения») lists only what it sells (robots, the extender) and what it does for free.

## 11. Light and darkness

- Light works **as in SS13** (v46, the author's screenshots): it is worked out cell by cell and drawn
  smooth, blending between the middles of cells, so it fades softly; a cell the light does not reach
  (behind a wall or a closed door) stays dark, and a wall is lit on the face turned to the light.
- A **flashlight** in hand (v46) lights a soft, warm **round pool** around its holder, its middle
  **1.5 cells** ahead (it stops at a wall you face) and fading to nothing **6 cells** from there:
  bright for about a cell, half at about 3 cells, faint at 5. Walls and closed doors stop it; windows
  and open doors let it through. Someone else's light is visible from afar, but only where you are
  looking: outside the field of view flashlight light is not visible. (Until v45 it was a narrow
  35° beam 9 cells long.)
- **Without power** the ship's lights go out. Space outside doesn't darken.
- **The dark is deep** (v47, the author's "deep dark" as in SS13): unlit places keep only **4.5%** of
  their light (7% in v46), so walls and rooms are just outlines. **Whatever is out of sight is just as
  dark, lit or not**: behind you and beyond the cone you see only the faint outline you remember
  (until v47 a lit place out of sight was only dimmed to about a quarter, and stars were seen there).
- **A soft pool around you** (v47, the author: "light on the main character like in SS13"): all the
  way round you, in any light, the place is made out, fully right at your feet and fading out by
  **3.2 cells**, stopped by walls. In the dark this pool also adds a little light (40% at your feet).
- **Smooth edges** (v48, the author: "smoother, like a triangle"): what you see ends along the straight
  sides of the cone, not cell by cell: each side fades across **1.6 cells** right by you, widening by
  **14°** outwards, so it reads as one soft straight edge; a light's pool fades out
  to nothing over open floor instead of stopping at a cell's edge (it still stops right at walls).
- **In the dark your eyes still make out the room around you** (v45, dimmer in v46): up to **30%** of
  full light right around you, fading out by **5 cells**, stopped by walls; outside the field of view
  and the pool around you it is black. The flashlight is much brighter. The same goes for derelicts and wrecks. People in the dark are still
  seen only within 2 cells or in a light (see "Field of view"). Until v45 there was pitch darkness
  outside the flashlight (build v27–v44).
- **Starlight**: the outer hull of any ship (walls and doors facing open
  space) is always slightly lit, even on a derelict ship and on ours without power.
  Anyone who goes out into space sees the hulls around them; inside a dark ship it is still dark.
- **You yourself** are always visible, even in the dark. The walls next to you are not lit in the dark
  (until v42 they were; the author asked for real darkness).
- A muzzle flash briefly lights up its spot in the dark.

## 12. Field of view

- (v69, the author's note: people popped in late when turning) The server sends each player everyone their
  character could see **by turning round** (walls still hide them); the game itself hides those behind instantly.
  So turning shows people at once, without waiting for the ping.
- (v77, the author's V1–V4) **The view follows the mouse**: the cone turns towards the mouse cursor, smoothly, half a turn
  (180°) in **1/3 s**, so something can still creep up behind you. Walking no longer turns you: you can walk backwards
  at full speed while looking ahead. The body turns with the eyes in 8 ways (others see where you look); E uses what you
  face. The setting «Взгляд за мышью» (Settings, Picture) turns it off: then you look where you walk, as before. While a
  console or a window is open the eyes stay still. Bots and pirates look where they walk.
  (v83, his note) With the cursor within **0.8 cell** of the middle of your body, the eyes and body do not move at all,
  and within **2 cells** the body needs **18°** past the half-way line to turn (6° further out), so a mouse resting on
  your character no longer shakes the view.
- (v79, the author's V1 "A") With the view following the mouse, **the camera leans toward the mouse**: by how far
  the cursor is from the middle of the screen, up to **2 cells** at the screen's edge (setting «Камера смещается к
  мыши»: none, 1, 2 or 3 cells), easing there in about a third of a second. It shows more of the side you look at;
  sight itself is unchanged. No lean while a console or window is open.
- A character sees **only forward**: two eyes of **85°** each, **160°** together, overlapping
  in the middle (later, losing an eye will remove its part of the cone).
- The eyes reach **9 cells** (v46, the author: as in SS13; before it was 20). The screen is zoomed so
  that at least 9 cells show on either side of you across it (19 cells in all, at a whole zoom so
  pixels stay crisp: 2× in a 1280-wide window, 3× at 1920).
- In the dark the room is still seen across the whole **160°** cone, dimly (see "Light and darkness"),
  but **people** only within a **60°** cone: where the flashlight shines, or right next to you, within
  2 cells (their name is visible).
- Walls and closed doors block the view. As in SS13, a cell (floor or wall) your gaze reaches whose
  **middle** is inside the cone is seen **whole** (v43): floor right up to the walls, walls as whole
  tiles. A cell at the edge of the cone whose middle is outside it (walls right beside you or behind
  you) is seen only as far as the cone itself reaches into it, the rest is darkened like anything out of sight.
- Since v44 every cell in the cone is checked on its own, not only those a ray happens to touch: floor
  whose middle can be seen in a straight line, and a wall whose face is turned to you on a floor cell you
  see. So a wall far along a corridor, seen almost edge on, is no longer left dark.
- Since v52 a room's corner wall is seen when the floor diagonally in front of it is seen, and whole cells
  are decided only by these checks, never by whether a drawn ray happened to graze them, so walls and
  corners no longer blink on and off as you walk. The picture moves on by an even amount every frame.
- Since v53 a window or an open door in a wall is told the same way as a wall: seen whole, never with a wedge
  cut out of it.
- What's outside your gaze is darkened: walls and floor
  are dimly visible, people and their names are not visible.
- When unconscious you see nothing.
- **The server decides who you see.** It sends your game only the people you see by these rules
  (judged a little more generously: **12°** wider each side, and for **0.2 s** after they go out
  of sight), the people right next to you (within **1.5** cells: felt, so you can search or drag
  them), and anyone on your deck holding a lit flashlight (its beam is seen from anywhere). Everyone
  else is not sent at all. Bodies count as people here. Shots and sounds are still heard as before.
- **Afterimage**: someone who drops out of the field of view stays where they were seen
  as a pale silhouette that fades over **10 s**. The silhouette disappears at once if you look at that spot
  (you see it as it is) or see the person themselves again.

## 13. Sounds

- Sounds are **audible**: footsteps, doors, the hiss of a breach, a fall, an item's clatter, ladders,
  shots, blows. All are made by the game itself from noise and tones: dry and short, as on
  a metal ship. Nothing borrowed in them.
- A sound comes **from the side where it happened** and is quieter far away.
- **Muffled** (quieter, without high frequencies) you hear what you can't see (behind a wall, behind
  a door), and everything when you yourself stand in thin air (under 60% of normal).
- Your own footsteps are audible only in air (20% of normal or more). In a vacuum and in open
  space they are silent, like everything else (until v40 they were heard there, muffled).
- The **engine hum** is heard on its deck while it runs and there is power; if it stops, there's trouble.
- On-screen markers (circles with a label) remain only for the **breach hiss** and **screams**,
  and only if the source isn't visible. The farther the sound, the less precise the marker; beyond the edge
  of the screen — an arrow at the edge.
- Range in cells:

| Sound | Range |
|---|---|
| footsteps | 6 |
| door | 8 |
| hiss (breach) | 12 |
| fall | 10 |
| clatter (dropped item) | 5 |
| ladder | 7 |
| shot | 18 |
| blow | 8 |
| scream (wounded) | 12 |

- Only your own deck is heard. A sound doesn't tell who made it.
- **In a vacuum it is silent**: if the listener or the source is in a compartment without air (under 20%
  of normal), only what is very close (up to 1.5 cells) is heard.
- A scream or hiss marker in one place is placed no more than once every 1.8 s.
- **Footsteps are quieter** (v56, the author: they hurt the ears): softer and duller, your own −12 dB and
  others' −8 dB below the rest, times the "Шаги" setting (50% by default).
- **The ship fight is heard** (v56, the author asked for it): our guns firing (a different sound for
  lasers and blasters, heavy and siege lasers, rockets and EMP, ion, beams), their shots bursting on our hull
  (a boom through the frame; a heavier one for rockets, heavy shots and meteors), our shield taking a shot
  (an electric crack and hum), and our shots bursting on the pirate ship or on its shield. These are heard
  everywhere aboard our ship, whatever the deck: from where they happen on your own deck, muffled from
  another deck, the pirate ship's a little quieter. Only with air round you: in a vacuum you hear nothing,
  but a blow to the hull still **shakes the screen** (harder close by: up to 9 screen pixels for a heavy
  blow, 5 for a shot; the "Тряска при попаданиях" setting). Our boarders aboard the pirate ship feel and
  hear our shots landing there instead. The "Бой кораблей" setting sets how loud all of this is.
- **Your own sounds** (v56): any sound can be replaced with a file. Put `NAME.ogg` or `NAME.wav` into a
  folder `sounds` next to the game; the names are `step`, `door`, `hiss`, `thud`, `drop`, `ladder`, `shot`,
  `blow`, `hum`, `gun_laser`, `gun_heavy`, `gun_rocket`, `gun_ion`, `gun_beam`, `hull_hit`, `hull_heavy`,
  `shield_hit`, `their_hit`, `their_shield` (the list is in `sounds/README.txt` in the archive).

## 14. Weapons and combat

- **Pistol**: a click fires where you clicked. Damage **30**, range **14** cells,
  no more than once every 0.3 s. The bullet is instant and hits the **first one in its path**, allies too.
  Walls, windows and closed doors stop it.
- **Friendly fire as in RimWorld** (v78, the author's M2): a friend standing **right by the shooter** (within
  1.25 cells across and down, so the next cell, also on a slant) is never hit; a friend further down the line
  still can be. So two or three can fire from one spot. A foe right by the shooter is hit as before.
- The shot starts where the shooter **is drawn** (quarter steps), and hits whoever it passes within the hit
  zone of, where they are drawn: someone half a cell aside of the line is missed.
- Someone **lying down** is passed over (see [Basics](#1-basics-server-ticks-network)) unless the shot is aimed at them.
- A hit is counted where **the shooter saw the target** on their screen: with ping you don't need
  to lead your aim.
- An empty pistol **reloads** on click with a magazine from your slots in 1.5 s.
- **Baton**: damage **15** to whoever stands in one of the eight cells around you, closest
  to the click; no more than once every 0.8 s.
- A hit shows a bullet trail, a muzzle flash and a red flash on the wounded person.
- Four pistol hits knock someone unconscious.
- **Shooting skill** widens the hit zone: from **0.45** cells from the line of fire without
  skill to **0.55** with skill 100.

## 15. Healing

- **Plaster**: click yourself or a neighbour, it closes **40** wounds at once. It is not used up on
  somebody with no wounds (v51).
- **Medkit**: click yourself or a neighbour, both stand still for **3 s**; it closes **30** wounds.
  Enough for **5** uses. If you move, treatment is interrupted. 3 s is without skill; the medicine
  skill cuts the time by up to half (with skill 50 — 2.25 s).
- Healing closes only wounds; health taken by the air returns by itself.
- (v69, the author's note) A click **anywhere on your own cell** treats yourself, and **Z** with a plaster or a
  medkit in hand treats yourself too. When nothing happens a message says why: no wounds, the health was lost to
  hunger (food helps) or to thin air (good air brings it back).

## 16. Helping the fallen: searching and dragging

- A person lying down (unconscious or dead) in your cell or a neighbouring one can be:
  - **searched** (E): you see their slots and yours, a click moves an item there or back;
    you can see how badly they are wounded;
  - **dragged** (F): you move half as fast, they follow one cell behind you, including
    up and down ladders. F again — let go. The dragged person is always visible, even behind your back.
- Someone standing on their feet can't be searched or dragged.
- (v80, his note) With several bodies or things in one cell, the **right-click menu** lists each: «Тащить: имя»,
  «Обыскать: имя» for every body, «Взять: вещь» for every thing in the pile (your cell or the next one).
- (v80, his note) Bodies on a wreck or a derelict (ours and theirs, with what they carried) are still there when it
  comes alongside again.

## 17. Pirates

- Enemies in **brown, red and black** spacesuits. They come with the **«Абордаж»** ("Boarding") event:
  they cut through the hull (a real breach) and come in.
- Number: 1 + half the crew, no more than **4**; one fewer against an unarmed crew.
  A new boarding doesn't come while there is a live pirate on board.
- They see by the same rules as the crew (cone, walls, darkness). In the dark they spot
  someone with a lit flashlight from afar. They always sense someone right next to them.
- They hear the crew's footsteps and noise and go to check. They find paths across the whole ship, via ladders,
  around dropped shutters.
- A gunner shoots from **8** cells with a spread of up to 0.7 cells, once every 0.7–1.3 s, and
  reloads by himself. A baton fighter closes in.
- A pirate remembers whoever wounded him and goes after them.
- Below **30** health he patches wounds with a plaster if he has one, otherwise he retreats.
- **They don't finish off those lying down.** They breathe on their own (sealed spacesuits).
- A killed pirate leaves a body with his weapon; it can be searched.

### Pirate ship

Since v44 a pirate ship comes as **two separate events** (same conditions: large; not in a meteor
shower and not at a station; not while another ship is at the airlock, there are pirates on board or
someone is outside):

- **«Пиратский корабль: абордаж»** ("Pirate ship: boarding"): it comes to board us, as before (below).
- **«Пиратский корабль: бой»** ("Pirate ship: fight"): a raid. It takes the same place above the airlock
  but **does not dock** while we can answer: it fights at a distance until it is wrecked, runs, or we jump away.
  Its crew is its class's (see "Kinds of pirate ship").
  - (v54, the author's word) When **every gun of ours is silent** (broken, put out by ion, or no power) **and we
    cannot jump** (engine out, no fuel, or every sector console broken), it warns, closes in and after **30 s**
    docks by force and boards like the boarding ship below. If a gun of ours can fire again before then, or a
    jump is possible again, it pulls back to its distance.

The boarding ship:

- A ship in brown, red and black colours takes position above the airlock, 3 cells of space away, and
  **opens fire** (see "Ship weapons"). After **90 s** (40 until v49) it **docks by force** (waits if someone is between the ships), **breaks open both
  airlock doors** (they jam open; repair like a jammed door) and lands
  pirates: as many as in a boarding (1 + half the crew, no more than 4).
- Their ship has light, air and power; on the floor 2–4 items: magazines, plasters, patches,
  a pistol, a baton.
- You can't dock with it of your own will. You can undock from the ship-control console: then
  it leaves, taking with it the pirates and bodies remaining on it. (v66) The same goes for a raider (or a hunter) that docked by force: until then it
  stayed alongside, fought on, and 30 s later docked and boarded again with a fresh party. The broken-open airlock then vents
  air into space until the doors are repaired.
- Either ship is left behind if our ship jumps to another sector before it is done with us.

### Kinds of pirate ship

Since v53 (the author's request: many different enemies, a different setup for each) every pirate ship is
**rolled** when it comes. Its hull is one of its class's hand-drawn hulls; everything inside is rolled anew:
which room holds which system, its guns, whether it has a shield, its crew size, its temper and its name
(«Пиратский катер «Гиена»»). Bigger ships come only farther from the start, and they are harder through what
they carry and how they fight, not only through more hull.

| Class | Hulls | Comes from | How often | Hull | System strength | Guns (more far out) | Shield | Guns charge | Our hit chance | Raid crew | Reward | Things aboard |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Катер (cutter) | 2 (6 rooms) | the start | 3 | 8 | 2 | 1, 2 from 4 jumps | 40% | 1.15× slower | −12% (small, nimble) | 2–3 | 25 | 1–3 |
| Рейдер (raider) | 2 (6–7 rooms) | the start | 4 | 12 | 3 | 2, 3 from 5 jumps | 70% | 1.3× slower | as usual | 2–4 | 40 | 2–4 |
| Канонерка (gunship) | 2 (9 rooms) | 2 jumps out | 3 | 14 | 3 | 3, 4 from 8 jumps | 60% | 1.5× slower | as usual | 3–4 | 55 | 3–5 |
| Крейсер (cruiser) | 1 (10 rooms) | 4 jumps out | 2 | 20 | 4 | 3, 4 from 7 jumps | always, refills 1.4× faster | 1.7× slower | +10% (big target) | 4–6 | 80 | 4–6 |
| Дрон-корабль (drone ship, v62) | 4 (of the others) | 3 jumps out | 3 | 10 | 3 | 2, 3 from 7 jumps | 50% | 1.25× slower | −10% | 2 guard robots | 45 | 1–2 |

- **Guns** come from the class's own list (since v58 each gun's tier is rolled by distance first, then a gun of
  that tier from the list; see "Gun tiers"): cutter: laser, rapid, ion, autocannon, blaster, Phoenix; raider:
  laser, rapid, ion, rockets, autocannon, heavy, blaster, railgun, Phoenix, Hammer; gunship: laser, rapid,
  rockets, ion, autocannon, heavy, blaster, EMP, railgun, Devastator, Hammer, siege; cruiser: laser, ion,
  rockets, heavy, ion cannon, EMP, railgun, siege, Storm, Hammer. The first gun is the first of its list when it
  is tier 1.
- **Rooms.** Each of its systems (guns, bridge, engine, quarters, jump drive, shields if it has them) stands
  in a room of its own, picked by lot. The rooms left over are **empty**: a hit there only takes hull.
- A boarding ship's crew is the boarding party (as before); a raid's crew is its class's range.
- **Temper** (how it fights), one of four by lot:

| Temper | Runs at | Shots at our guns (while one works) | Of the rest, at consoles/shield generator | Guns charge |
|---|---|---|---|---|
| Расчётливый (calculating) | a third of its hull | 55% | 40% | as usual |
| Осторожный (cautious) | half its hull | 70% | 30% | as usual |
| Отчаянный (reckless) | never | 30% | 20% (the rest at the hull, where people are) | 15% faster |
| Охотник (hunter) | a third of its hull | 35% | 75% | as usual |

### Scanning the enemy

- A ship that comes is **unknown inside**: the gun console's plan shows its rooms with **«?»**.
- Our **sensors** make out one more room every **7 s** while our ship has power (v59: 4 s or 2.5 s with better sensors).
- A shot that **gets through** shows what is in the room it hit («пусто» if nothing).
- Its guns **firing** give away its gun room.
- A **scanning probe** («Зонд-сканер», cargo, **12** credits at traders, the ship sets out with **1**) is
  launched from the gun console («Запустить зонд-сканер»): it shows every room at once, its crew and its temper.
  Since v54 it also shows **where each of its crew is, for 20 s** (red dots on the plan, a white ring on one
  who is mending, dim if wounded); another probe can be launched once those 20 s are over.
- The **scouting drone** (v54) shows the rooms it enters and the crew near it: see "Scouting drone".

### The pirates' crew at their posts

Since v54 its crew are on its plan, walking room to room (a cell per 0.3 s). Twice a second they decide who
goes where, in this order: to mend a system we **knocked out** (two to it), one to the **cockpit**, then to mend
what is only **worn**, then one to its **guns**, one to its **shield generator**; the rest sit in the **quarters**.
- A system is mended only while somebody stands in its room: **1 point per 15 s** each, two at most.
- With nobody at its guns they charge at **60%** speed; with nobody in the cockpit it **can't dodge** our shots
  and charges its jump at **half** speed.
- A hit that gets through into a room (not ion) finds whoever is in it: each is **wounded 60%** of the time and
  lies low in the quarters for 12 s (no mending, no post). Since the author's word in v54 such hits **kill nobody**;
  the "Quarters" row below still holds: hits on the quarters kill as before.
- We see them only through a probe (20 s) or the drone.

### Scouting drone

- **«Дрон-разведчик»** (cargo, **20** credits at traders, the ship sets out with **1**). Sent from the **drone
  monitor** on the bridge (top wall, next to the holomap; E opens it; needs power) with «Запустить дрон», only while a
  pirate ship fights us.
- It flies over in **4 s** and gets in at the enemy's outer door. While you stand at the monitor, the **walking
  keys steer it** (not your character), a cell per 0.25 s; anybody at the monitor may take over.
- Every room it enters becomes known on the gun console. It sees the pirates in its room and right next to it.
- Its battery lasts **60 s**. Each second, every fit pirate in its room shoots it down with a **15%** chance.
- «Взорвать дрон здесь»: **2 damage** to the system in its room (no shield stops it), **1** to the hull, and it
  may wound the pirates in the room like a hit. The drone is spent.
- It is lost when its battery runs out, when it is shot down, or when the pirate ship goes.

### Ransom

- Since v54 a beaten pirate ship that would run (any temper but reckless) **offers a ransom instead, half the
  time**, once per fight: **60%** of its reward in credits and a **can of fuel**.
- While the offer stands (**20 s**) it does not shoot. «Принять выкуп» on the gun console: we get the credits and
  fuel, **30%** of the time one of its crew joins our reserve, and it leaves (no reward, no wreck).
- Our shot is a refusal; so is silence for 20 s. Either way it then charges its jump to run, as below.
- The guns can aim at any room, known or not: click it on the plan. Unknown rooms have no system button.

### Our crew at their posts (v55)

Since v55 our own crew matter in a fight the way the pirates' do. A post counts as manned when somebody (a player
or a bot) stands facing its machine, conscious, the machine whole and the ship powered.
- **Ship's controls** (pilot): the pirates' shots miss more often: **15%** less chance to hit, plus up to
  **10%** more with the piloting skill (v60; a pilot by job starts at 50, so 20%). Every enemy volley dodged
  at the controls teaches piloting. Somebody also at the **engine** adds **5%** more. Nobody at the controls: **nothing is dodged**
  (as before v55). No dodge with the engine down or without power.
- **Shield generator**: with somebody at it the shield refills **25%** faster.
- **Gun console**: shots are fired from it, as before; a bot there fires every ready gun by itself.
- The pirates were made a little stronger to match (the author's word): **+5%** to every shot of theirs.

### Battle position (v55)

Chosen on the ship's controls during a fight, by whoever stands there (buttons under the sector map):
| Position | Our hits | Their hits | Other |
|---|---|---|---|
| Вплотную (close in; every fight starts here) | as is | as is | our people can cross to them through space |
| На дистанции (at a distance) | −15% | −15% | their docking countdown runs at half speed |
| С фланга (on its flank) | +15% | as is | our dodge counts half |
| В тыл (behind it; v59, only by the phase drive) | +25% | −20% | our people can't cross to them |
- Changing takes an **8 s** manoeuvre; during it we **don't dodge**. It needs the engine working.
- Away from "close in" the ship needs somebody at the controls and the engine going: **5 s** without them and it
  falls back to close in. It also comes back close in at once if anybody of ours is out in space (and you can't
  leave close in while somebody is outside).

### Bots under orders (v55)

- The **crew window** (key **O**) shows which posts are manned, our dodge and position, and a row per bot with
  its order and what it is doing. Orders: **free** (wanders, as before; since v72 it comes to mend what is broken),
  **controls**, **guns**, **engine**,
  **shields**, **repair**, **follow me**. «Все по местам» sends every bot to a post no player mans (controls, guns,
  shields, engine; the rest repair); «Отбой» frees them all.
- Orders come from the **captain**; while no captain is aboard, from anybody.
- Bots walk the ship by the shortest way (ladders included), and avoid rooms with under half the normal air.
  (v66) Their way may lead through the airlock (they cycle it, see "Two-door airlock"). A bot told to **follow**
  goes after its player anywhere it can: through the airlock, onto a ship docked alongside, and out into space
  if it wears a suit; without a suit it does not follow into a vacuum. It stands beside the player, never in a doorway. A **repair** bot goes to the nearest broken machine, jammed or faulty door, or hole
  (if a patch is to be had), taking a **spare part** or **patch** from the hold; it mends like a player.
  A **gun** bot fires every ready gun where the guns aim, but holds fire while a ransom is offered.
- (v79, the author's B1 "B") **Bots and armed boarders.** A bot that sees an armed pirate (any weapon, or a pirate
  robot) by our rules of sight, or one within **4 cells** with nothing between, or is hurt by one, drops its work
  (the repair it had is free for another bot) and **runs**: to open floor at least **10 cells** from every pirate it
  knows of and out of their rooms, by one of our people if possible (one of ours at least 6 cells from the pirates,
  within 2 cells of the spot). There, or with nowhere to go, it **lies down** (shots fly over). The crew window says
  «прячется». It remembers a pirate while that pirate is still on our ship (unseen for **45 s** counts as gone);
  **8 s** after the last one is gone (dead, captured, off the ship) it gets up and goes back to its order. Bots
  following a player, out on the hull or lying in an autodoc take no notice.
- A bot with the **guard's job** does not run while there is a gun for it: it goes to the supply locker, takes a
  **pistol** (or a **shotgun** if there is no pistol) and **2** magazines (boxes of shells), then hunts the pirates
  like our security robots do (crew window: «в бою»). It keeps the gun afterwards. With no gun in the locker it runs
  like the others. Other bots never fight.

### Boarding a pirate ship (v55)

- While close in, our people can push off through space from our airlock to the pirate ship (**3** cells) and
  go in through its outer door.
- The moment the first of us steps aboard, its crew **come to life**: each becomes a real armed pirate where it
  stood, and they fight. With no boarder in sight they go back to their posts. A pirate standing in a system's
  room mends it as before.
- Each of ours standing in a room with a system in it **wrecks it by 1 point every 8 s** (two together, twice
  as fast); the quarters can't be wrecked this way.
- While any of ours is aboard it **can't jump away** and a ransom **can't be taken**. Our own guns hitting a room
  may wound our boarders there too (25 health, 60% each).
- When its whole crew is dead the ship is **captured** and salvaged: **150%** of its reward, **2 spare parts** and
  a **can of fuel** into the hold. It stays alongside dead and dark, to be searched like a wreck (v67: and **14** pieces
  of scrap can be cut off it, against 8 off a wreck).

- (v64) A pirate of its crew that walks across onto our ship while ours are aboard leaves its crew count but is not
  dead: the chat says it crossed over, and it fights on aboard our ship.

### Wrecked raider

- A raider our guns wreck (hull at 0, or its whole crew killed in its quarters), and since v72 a boarding ship whose hull
  our guns bring to 0 before it docks, **stays alongside** as a
  dead hulk: no power, no light, doors open by hand. The ship is paid its class's **reward** (25–80 credits; no canister).
- It can be reached through open space or **docked with** from the ship-control console
  («Пристыковаться к разбитому кораблю»). Aboard: what it carried (2–4 things on the floor plus 1–3 more),
  and the bodies of its dead with their weapons.
- Who is aboard is settled when it is wrecked and found out when the first of our crew sets foot on it:
  - **70%**: nobody alive, only bodies (always so if its quarters were shot empty);
  - **15%**: its survivors **fight**: they come out armed from the far end of the wreck;
  - **15%**: its survivors **give up and join us**: each one becomes +1 to the crew reserve (up to 9).
- Bodies of crew killed by hits on its quarters lie aboard in every case.
- (v69, the author's request) It **stays on the chart** as a place, «разбитый пират», where it was wrecked. It
  stays alongside while our ship is within **10** of that spot; fly further or jump away and it is left there,
  with what is still on it (and any survivors). Come back within 10 and it comes alongside again. If that spot is too
  close to a trader, a station, another place or another wreck, it is marked a little further off (at least **6**
  past both ranges). While someone is on it or it is docked, the ship doesn't move, as with a derelict.
- (v69) **Docking needs the ship stopped**: no course and no jump charging.

### Pirate flagship: the goal of the game (v57)

- Every game has a **goal point**: the pirates' flagship waits in a system of the **4th cluster** (v64; before, 12
  jumps from the start). Never at an exit, rarely in an ion storm. The chart always shows its system in red with a ring
  once we are in its cluster; before that the sector console says how many clusters are left to it.
- Arriving in its sector, the flagship comes out **5 s** later. Which of the two it is stays hidden until
  then (the author: "no courage to fight if you know who you will fight"); it is fixed per game by lot.
- **No way out** (the author: "you win or you lose, no other exit"): while it fights, no jump can be set
  and a jump being charged is cut off; it never runs and never offers a ransom; it does not dock by force.
  Leave its sector before it comes out and it comes again when you return.
- **Battleship «Владыка пустоты»**: hull **30** points, strength 5, always shielded (regen 1.5×), 7 crew,
  guns: heavy laser, two lasers, rocket. It **aims well**: 80% of its shots go at our shield generator while
  it works, then at the engine (an engine hit leaves the whole ship without power), then at our guns;
  20% at the hull anywhere.
- **Carrier «Пожиратель»**: hull **26**, always shielded, 6 crew, a laser and two **neural emitters**
  (charge 9 s, 80% to hit, no damage to the ship: they **stun everyone in the room** they hit by 40 health
  points, without wounds, down to −10 at most). It has a **teleporter** room: 20 s into the fight and then
  every **40 s** it puts **2** boarders straight onto our bridge (8 in all, never more than 4 aboard). They
  hold the bridge and fight whoever comes. The teleporter works only while it is not knocked out and one
  of its crew is at it; our guns can aim at it, and the gun console shows its room.
- **Capture**: if every one of our crew is down (unconscious or dead) while its boarders are aboard,
  for **10 s**, the ship is taken and the campaign ends. Anyone getting back on their feet stops it.
- (v67, the author's O1) **It no longer grows with our guns or gear**, only with time (below). (Before v67: one more
  gun for every mounted gun past a plain laser, and more hull for our gear.)
- **Winning**: wreck it, or board it and kill its whole crew. Everyone sees «ПОБЕДА» for 15 s and the chart
  says the flagship is beaten; its reward is **200** credits and the wreck can be searched. The voyage
  goes on after that; the flagship does not come back.
- The eventer has «Флагман: линкор» and «Флагман: абордажник» to call either one in for testing.
- **It roams and grows** (v63, the author's R7: "FTL-style"). It sleeps until our ship comes into its cluster (v64;
  before, within 2 jumps). Then it wakes («флагман пиратов проснулся») and roams its cluster (never into a station's
  system): every **90 s** it moves to a neighbouring system along a lane (half the time towards us). The chart shows it
  as a red triangle «ФЛАГМАН», the sector console and the comms console say where it is. Meeting it is the fight: we
  arrive where it is (it comes out 5 s later), or it comes into our system (a warning, then **20 s** to jump away).
  Arriving at its lair while it is elsewhere, the chat says so. Its jammer keeps the cluster's exits shut (section 19).
- From waking, its **growth clock** runs, even while we are far away (it is saved): every **3 min** (**2 min** on the
  hard mode) it takes a step, up to **4**: 1 its guns charge in **0.8** of the time; 2 its shield refills **1.5×**
  faster and each of its systems takes one more hit; 3 it carries **4** more boarders (the battleship gets a teleporter
  and sends them the carrier's way); 4 point defence. The clock stands still while it fights us. The chat tells each
  step. The chapter's codes (section 25) take one step off and show all its rooms in the fight.

### Ship weapons

Since v49 (the author's request) guns can be changed, the ship has a shield, and there are ten kinds of ship weapon; v50 added two more beams, the tractor and the siphon (the author chose them).

- The ship has **3 gun mounts** in the hull: in compartments near the nose on the port and starboard sides and under
  the belly. They are worked from the **gun console** on the bridge (E). The console and guns need power.
  The ship sets out with a **laser** on each.
- **Changing guns.** Each mount holds one weapon or none. On the console, "Сменить оружие…" under a gun puts on a
  weapon from the **cargo** (the supply locker); the one taken down goes into the cargo. "Снять в трюм" leaves the
  mount empty. A weapon just put on is unpowered and uncharged. Ship weapons and rockets are cargo: the locker
  shows them, but they can't be taken into the hands.
- **Reactor power: 8** (v59: 10 or 12 with a better reactor, see "Ship gear"). Every powered gun draws its power, the shield **2**. A gun is powered or cut with
  "Питание" on the console; one that doesn't fit in what is left won't power up. A cut gun loses its charge.
  The ship sets out with 3 lasers and the shield on: 5 of 8.
- A powered gun charges by itself (each weapon its own time) while the ship has power and the mount is whole.
  Buttons: fire one gun or a volley of all ready ones.
- **Shots fly** (v56, the author's video of FTL). A shot is decided when it is fired (hit or miss, the room,
  whether the shield will stop it) but lands only when its flight is over, and the hole, the damage and the
  chat line come then: lasers 0.7 s (rapid 0.6 s, siege 0.8 s), blasters 0.7 s, ion 0.9 s, rockets and EMP
  1.3 s; the shots of a burst leave 0.15 s apart. Beams (cutter, tractor, siphon) have no flight. The same
  holds for the pirates' shots at us. A shot still on its way when either ship leaves is lost.
- **What is seen.** In the world: a bright bolt with a trail leaves the gun into space; at the other ship it
  comes in from the side (from space onto our hull) and bursts: a flash that lights the dark, sparks, bits of
  hull and smoke (an ion hit crackles blue; a rocket trails smoke and bursts bigger), or makes a blue ripple
  on the shield's bubble, or flies past. On the gun console's plan (and the drone monitor's): the pirates'
  shield bubble while it is up (brighter the stronger), our shots flying in from the left and bursting in
  their room (the room flashes red), flaring the bubble where the shield stops them, or flying past with
  «ПРОМАХ»; their shots leaving their weapons room.

Since v58 every gun has a hidden **tier** (1, 2 or 3; never shown, a gun is known by its name, look and sound)
and a **kind** of parts (laser, ion, missile, beam, kinetic). Tier 3 guns carry an **effect** (see "Gun tiers").

| Weapon | Tier | Charge | Shots | Hit | Damage | Power | Price | What else |
|---|---|---|---|---|---|---|---|---|
| Лазер (laser) | 1 | 8 s | 1 | 75% | 1 | 1 | 30 | upgrades into the heavy laser |
| Скорострельный лазер (rapid laser) | 1 | 12 s | 6 | 35% each | 1 | 2 | 40 | upgrades into the blaster |
| Тяжёлый лазер (heavy laser) | 2 | 14 s | 1 | 70% | 2 | 3 | 75 | takes 50 off a shield that stops it; upgrades into the siege laser |
| Плазменный бластер (blaster) | 2 | 11 s | 4 pellets | 55% each | 1 | 2 | 80 | half the pellets ignore the shield; upgrades into the Phoenix |
| Осадный лазер (siege laser) | 3 | 20 s | 1 | 65% | 3 | 4 | 150 | takes 75 off a shield |
| Феникс (Phoenix, v58) | 3 | 17 s | 2 | 70% each | 2 | 4 | 170 | two heavy fiery bolts; an orange-gold bolt with a fiery tail |
| Ионная пушка (ion gun) | 1 | 7 s | 1 | 80% | 0 | 1 | 35 | takes 35 off a shield; through it, puts the system it hits out for **3 s** |
| Ионное орудие (ion cannon) | 2 | 13 s | 1 | 75% | 0 | 2 | 90 | takes 70 off a shield; through it, a system out for **3 s** |
| Буря (Storm, v58) | 3 | 14 s | 2 | 75% each | 0 | 3 | 160 | each takes 50 off a shield; through it, a system out for **6 s**; a crackling deep blue ball |
| Ракетная установка (rocket launcher) | 1 | 10 s | 1 | 85% | 2 | 1 | 40 | ignores the shield (not a hardened one); holes the hull 50% of the time; spends a rocket (4 cr.) |
| ЭМИ-установка (EMP launcher) | 2 | 12 s | 1 | 85% | 0 | 1 | 85 | ignores the shield (not a hardened one); puts the system it hits out for **6 s**; spends an EMP rocket (6 cr.) |
| Опустошитель (Devastator, v58) | 3 | 16 s | 1 | 85% | 4 | 2 | 170 | a heavy rocket: ignores the shield (not a hardened one), always holes; spends a rocket |
| Захватный луч (tractor beam, v50) | 1 | 15 s | 1 | never misses | 0 | 2 | 45 | holds the enemy **8 s**: our shots hit **+25%** (up to 95%), its escape jump and its countdown to docking stand still; a shield at 50+ stops it (losing 10) |
| Сифон (siphon beam, v50) | 1 | 12 s | 4 pulses, 1 a second | never misses | 0 | 2 | 45 | each pulse takes **12** from the enemy's shield and adds it to ours (if our generator works, up to 100); no hull damage |
| Резак (cutting beam) | 2 | 16 s | 4 pulses, 1 a second | never misses | 1 a pulse | 2 | 95 | burns the room aimed at; the aim may move while it burns; a shield at 50+ stops it, losing only 10 a pulse |
| Жнец (Reaper, v58) | 3 | 18 s | 6 pulses | never misses | 1 a pulse | 3 | 180 | a crimson beam; a shield at 50+ stops it but loses 25 a pulse |
| Автопушка (autocannon, v58) | 1 | 9 s | 3 shells | 60% each | 1 | 1 | 35 | kinetic: every hit holes; spends a shell (3 cr.) each |
| Рельсотрон (railgun, v58) | 2 | 18 s | 1 | 70% | 3 | 3 | 110 | passes any shield and goes on into a second room; no ammunition |
| Молот (Hammer, v58) | 3 | 16 s | 1 | 70% | 4 | 4 | 175 | kinetic, holes; spends a shell |
| Заслон (point defence, v58) | 1 | 5 s | – | 60% | – | 1 | 50 | its own mount: shoots down rockets coming at us |
| Сверхновая (Nova, v58) | 3 | 25 s | 1 | 90% | 6 | 4 | – | the flagship's own, unique: passes any shield, burns into a second room; never sold |

The pirates' flagship also carries the **neural emitter** (v57), never ours. The upgrade lines: laser → heavy →
siege; rapid → blaster → Phoenix; ion gun → ion cannon → Storm; rockets → EMP → Devastator; tractor or siphon →
cutting beam → Reaper; autocannon → railgun → Hammer.

- **Shields** (the author's rule, not FTL's). A shield is a pool of **0–100** that refills **2.5 a second**.
  A shot that meets it at **50 or more** is stopped and takes **25 per point of its damage** away (ion: its own
  amount, the beam: 10). Below 50 a shot gets through with chance (50 − shield) / 50: at 25, half; at 0, all.
  Lasers and the beam always meet the shield; half the blaster's pellets slip past it; rockets and EMP pass it
  unless it is hardened; ion only wears it down, and what gets through puts a system out instead of doing damage.
- **Our shield generator** stands in the wall of the life-support compartment on the lower deck (the engineer's
  access). It needs power and can be switched off from the gun console (then it frees 2 power). Without power,
  broken, or switched off, the shield is at 0; put out by ion or EMP it stops protecting and refilling for that
  time. A broken generator is repaired like any machine.
- **Shield hardening** (v49–v58): with it the shield stops rockets and EMP rockets too, like lasers. Since v59 nobody
  sells it: the top shield generator «Эгида» does the same (see "Ship gear"). A ship that bought it keeps it.
- Since v59 the shield's refill and the reactor's power depend on the **gear** installed (see "Ship gear").
- The only target is the pirate ship, until it docks. Its hull takes its class's damage (**8–20**). A boarding
  ship or a raider, once wrecked, stays alongside as a wreck and the ship is credited its class's reward (see "Wrecked
  raider"). (v72) A boarding ship wrecked before it docks no longer flies off: its **1** fuel canister lies aboard the
  wreck instead of going into the hold.
- **Its shield and guns** depend on its class (see "Kinds of pirate ship"); its shield has the same rules as
  ours. Its guns charge slower than ours by its class, and slower still as its weapons room is worn. Its rockets
  never run out.
- **Aiming at its systems.** The console shows the pirate ship's plan with its rooms (see "Scanning the enemy");
  a click on a room (or a known system's button) aims all guns there, "Куда попадёт" ("wherever it
  lands") hits a random compartment. The aim is shared by everyone at the console. A hit that gets through
  takes its damage from the hull and from the system there, and makes a breach next to that compartment
  (a rocket: half the time):
  | Compartment | Strength | When knocked out |
  |---|---|---|
  | Weapons (Орудия) | 3 (its class's: cutter 2, cruiser 4) | it stops shooting; worn, it fires slower (at 1 of 3, three times slower) |
  | Bridge (Рубка) | 3 | its shots hit half as often, ours hit 20% more often (up to 95%) |
  | Engine (Двигатель) | 3 | it can't close in (the countdown to docking stands still) and can't jump away |
  | Quarters (Кубрик) | 2 per crewman | every 2 damage kills one of its crew; a boarding ship with none left breaks off and leaves (no reward), a raider becomes a dead wreck |
  | Jump drive (Гипердвигатель) | 3 | worn, its jump charges slower in proportion; knocked out, it can't jump away |
  | Shields (Щиты) | 3 (or none) | worn, its shield refills slower; knocked out, its shield falls to 0 |
- Ion or EMP put a system out for their time: it works as if knocked out (on the shields: the shield stops
  protecting and refilling), then comes back by itself.
- **It runs when beaten** (v44): with its hull down to its temper's share (a third, or half for a cautious
  one; a reckless one never runs), or its guns knocked out and its hull at half or less, it charges its jump drive to get away. With the drive whole that takes **20 s**, worn
  longer in proportion; with the drive or its engine knocked out, the charge stands still until it is
  mended. A ship that gets away pays nothing. While it runs it doesn't close in to dock either.
- Its crew repairs one point of a worn system (not the quarters) every **15 s** while one of them is in its room
  (since v54; twice as fast with two): a system knocked out
  comes before one only worn; while it runs, the jump drive and engine first, otherwise its guns, then its shields.
- **Its shots at us.** While one of our guns works it aims its temper's share of its shots at our guns (20% more
  while it runs); of the rest, its temper's share go at a bridge console or the shield generator, and the others
  hit the hull, half of those next to a crew member. A shot our shield stops shows as a blue ripple off the hull. What gets through: a gun, console or the
  generator breaks (hull −3 per damage); a hull hit makes a breach (hull −5 per damage; a rocket breaches half the
  time); ion or EMP put a gun or the shield generator out for 3 or 6 s. A broken gun is repaired like machines
  (E, 6 s with a spare part).
- Each gun's shots are told in one chat line (hits, what the shield stopped, misses, what it did).
- The console shows the reactor's power, our shield, each gun with its weapon, charge, power and change list,
  the enemy's hull, shield and guns, the time until it docks (or that it fights at a distance), how long until it
  jumps away while it runs, its systems and what knocking each out does.

### Gun tiers, kinetic guns, point defence, loot (v58)

The author's tiers plan, part 1 (part 2, ship gear and its tiers, comes in v59).

- **Tiers come by distance.** Up to 3 jumps from the start every pirate gun is tier 1; 4–7 jumps out half the
  pirate ships carry one tier 2 gun; from 8 jumps on up to half their guns are tier 2 (75% each), and 15% of those
  tier 3. The flagship's guns are all tier 3. Pirates use the new guns too (not the beams or the point defence).
  As a result the first pirate ships are weaker than before v58 (the rapid laser and the ion cannon are no longer
  tier 1 guns).
- (v67) The flagship no longer grows with our guns (it did, by half our tier points, from v58 to v66).
- **Effects of tier 3 guns**, rolled for each gun found, bought or made, shown in its name and on its card:
  | Effect | What it does |
  |---|---|
  | пробивной (piercing) | the shield it meets counts as 30 weaker for it |
  | оглушающий (stunning) | a hit wounds the pirates in the room hit (on us: stuns everybody in the room, 30 health) |
  | сдвоенный (twice) | one volley in three fires again right after |
  | сбивающий (knocking) | the system in the room hit goes out for 2 s |
  | рвущий (tearing) | every hit holes the hull, and once more beside it |
- **Kinetic guns** (the author's notebook): a shield takes **1** off each shell's damage and wears by **15**
  (the autocannon's 1-damage shells only wear a shield; the Hammer's slug goes through with 3). A railgun passes
  any shield. **Armour** turns kinetic shots aside: «РИКОШЕТ», the shot does nothing. Pirate ships have armour
  by class: cutter none, raider 10%, gunship 20%, cruiser and battleship 30%, carrier 20%. Our ship gets
  armour from an armour module (v59, see "Ship gear").
- **Point defence «Заслон».** It goes on its own mount from the gun console ("Точечная оборона": put on from the
  cargo, take down, power), not on a gun's mount, and draws 1 power. Charged (5 s), it shoots at the next rocket
  coming at us and brings it down **60%** of the time («СБИТА»), then charges again. Pirate ships 4+ jumps out
  have one now and then (raider 15%, gunship 35%, cruiser 50%, the battleship always): it shoots down our rockets
  the same way, and our scouting drone on its way in (60%). The console tells whether the enemy has one.
- **Shells** (снаряды) are cargo like rockets: the autocannon and the Hammer spend one a shot; arms dealers and the
  black market sell them at 3.
- **Rare gun drops** (the author: a reward, not routine). (v67, the author's B2: "no full guns from ships; guns come
  as a rare event") A pirate ship no longer leaves a whole gun: a wreck leaves **1** part of one of its guns' kind
  **30%** of the time (or, half of those times, a crate of gear lying aboard), and one taken by boarding always leaves
  **2** parts, into the hold. Rare events still bring whole guns: a derelict hides a ship gun 25% of the time (damaged
  60%), a battlefield holds a damaged one 30% of the time. The flagship's wreck
  holds its own unique gun, the **«Сверхновая»**. A gun found lies on the floor: pick it up and carry it home
  through the airlock to the supply locker (it goes back like anything else). A damaged gun can't be mounted and
  is worth a third; mend it at the workbench.
- **The workbench** (верстак, 'B' on the map: in engine room 2 on the lower deck of ship02, by the lower deck on
  ship01). Only an **engineer** may work at it (the author's choice); it needs no power and doesn't break. E
  opens its screen: every ship gun in the locker with what can be done to it, and the gun parts the locker holds.
  The work goes on by itself while the engineer stays at the bench (stepping away puts it down); the repair
  skill makes it up to twice as quick.
  | Work | Time | Needs | Gives |
  |---|---|---|---|
  | Разобрать (take apart) | 6 s | – | parts of its kind: 1 per tier (one less if damaged, at least 1); the Nova can't be |
  | Починить (mend) | 10 s | a spare part (запчасть) from the locker | the gun whole (a tier 3 one gets an effect rolled) |
  | Улучшить (upgrade) | 15 s | 2 parts of its kind (tier 1 → 2) or 4 (tier 2 → 3) | the next gun of its line (tier 3: with an effect rolled) |
- **New looks and sounds.** Each new gun has its own shot (a short yellow tracer for shells, a long white-blue
  streak for the railgun, a heavy glowing slug for the Hammer, a fiery bolt for the Phoenix, a crackling blue ball
  for the Storm, a fat rocket with red flame for the Devastator, a crimson beam for the Reaper, a blinding ball for
  the Nova, bursts of flak for point defence) and its own sound (`gun_autocannon`, `gun_rail`, `gun_hammer`,
  `gun_phoenix`, `gun_storm`, `gun_devastator`, `gun_reaper`, `gun_flak`, `gun_nova`; replaceable like the others,
  see `sounds\README.txt`). In the cargo a gun's frame is plain, steel or gold by its tier, a gun with an effect
  has a little star, a damaged one is scorched.

### Ship gear: systems, modules, phase drive (v59)

The author's tiers plan, part 2. Gear comes in **crates** (things you carry in a hand, kept in the supply locker,
bought, sold and found; not cargo). Like guns, a tier is hidden: each crate has its own name, and its card says in
numbers what it does. Prices go ×1 / ×2.5 / ×5 by tier. Tiers come by distance like the guns'.

- **Systems.** The ship sets out with a built-in tier 1 shield generator, reactor, engine and sensors. A crate of
  tier 2 or 3 is installed at its machine: the shield generator at the shield generator, the reactor and the engine
  both at the **engine**, the sensors at a **holomap**. The one it replaces comes out into the hand as a crate (a
  built-in one leaves nothing). A weaker one may go back in.
  | System | Tier 1 (built in) | Tier 2 | Tier 3 |
  |---|---|---|---|
  | Генератор щита (shield) | refills 2.5/s | «Бастион» 100 cr: 3.5/s | «Эгида» 200 cr: 4.5/s, and stops rockets and EMP rockets |
  | Реактор (reactor) | 8 power | «Факел» 120 cr: 10 | «Солнце» 240 cr: 12 |
  | Двигатель (engine) | – (a jump burns 40) | «Стриж» 90 cr: dodge +5% (while someone flies), jump charges in ¾ the time, a jump burns **35** (v67) | «Сокол» 180 cr: dodge +10%, jump in half the time, a jump burns **30** (v67) |
  | Сканеры (sensors) | a room every 7 s | «Око» 60 cr: every 4 s | «Всевидящее око» 120 cr: every 2.5 s, and the gun console shows each pirate gun's charge |
  The jump drive's rest after a jump shortens like its charge. A weaker reactor going in cuts guns (then the point
  defence, then the shield) until the power fits.
- **Modules** go in the **module bay** (модульная стойка, 'U' on the map: in engine room 1 on the lower deck of
  ship02, in the lower wall of the middle hall on ship01). It has **2 slots** (3 with the extender, v62), one module of each sort. A module of a sort already in the
  bay swaps with it; with both slots taken by other sorts, take one out first. With empty hands at the bay an
  engineer takes out the last module put in (5 s).
  | Module | Price | What it does |
  |---|---|---|
  | Броня «Стальные листы» (armour, tier 1) | 50 | a pirate hit takes 15% less off the hull, 15% of hull holes don't happen, 10% of kinetic shells ricochet |
  | Броня «Композит» (tier 2) | 125 | 30% / 30% / 20% |
  | Броня «Керамит» (tier 3) | 250 | 45% / 45% / 30% |
  | Фокусирующая решётка (focusing array; the author's "mirror" note) | 120 | lasers fired **in one volley at one room** join into one beam: for each laser past the first, the shield counts **45** weaker for all of them |
  | Фазовый привод (phase drive; replaces the cloak in the plan) | 150 | the battle position changes **at once** (no manoeuvre) and opens **«В тыл»** (behind them: we hit +25%, they hit −20%); then it recharges **60 s**, during which positions change by the usual manoeuvre and "behind them" is closed. No fuel |
- **Installing.** Only an **engineer** installs or takes out gear: face the machine (or the bay) with the crate in
  hand and hold **E** for **10 s** (the repair skill makes it up to twice as quick). A broken machine must be
  mended first. Hovering shows what will happen or why it can't (wrong machine, already installed, slots full,
  not an engineer).
- **Where it shows.** The holomap's summary lists every system's tier and the modules; the gun console shows the
  shield's refill, «держит и ракеты» for the top generator, the focusing array, and (top sensors) the pirate guns'
  charge; the ship's controls show the phase drive and its «Фазой в тыл» button. A phase jump has its own sound
  (`phase`, replaceable).
- **Finding gear.** A wreck that leaves loot (see "Gun tiers") leaves a crate of gear instead of a gun **half** the
  time; a derelict's hidden find is a crate half the time. Traders sell crates (see the trader table).
- (v67) The flagship no longer grows with our gear (from v59 to v66 it got +2 hull and a 10% quicker shield per step).
- Gear is saved with the campaign.

### Crew at work (v60)

The author's notes N1 and S1: the crew do the ship's work with their hands, and bots do it too.
- **Gunners at the mounts.** Whoever stands facing a gun mount in its gun bay (a player or a bot on the new order
  «У орудия»), conscious, with the ship powered, is that gun's gunner: the gun charges **25%** faster, up to
  **50%** with the best gunnery skill (a guard by job, skill 50: 37.5%). Every shot of that gun teaches its gunner
  gunnery. A gun with nobody at it charges as before, so a small crew can still fight. The gun console shows
  «у орудия канонир» on a manned gun. Whoever fires from the console also aims better: **+5%** to hit with the
  best gunnery skill (+2.5% at 50).
- **Guns are carried by hand.** A ship gun is taken out of the supply locker into the hands (click it in the
  locker). Facing a mount with it in hand, hold E for **8 s** (the repair skill makes it up to twice as quick):
  it goes up, unpowered, and the gun that was on the mount comes down into the hands, to be carried back to the
  locker. With empty hands, holding E at a mounted gun for **5 s** takes it down. A damaged gun can't go up (mend
  it at the workbench); the point defence still goes on its own mount from the gun console.
- **The gun console gives orders.** Its weapon list now says «Принести и поставить» (fetch and mount) or «Снять и
  убрать в шкаф» (take down into the locker): the order is shown on the gun's line, and the same order again
  cancels it. Bots on «Работы» carry orders out by themselves; anybody else may too. An order is dropped when it
  is done or nothing can carry it out.
- **Bots at work** («Работы», was "repair"): first a gun in their hands goes to its mount or back to the locker;
  a bot with no suit fetches one from the locker; then broken machines, doors and holes, **walking to the locker
  for spare parts and patches first** (they no longer take them from the hold by magic); then the console's gun
  orders. «Все по местам» now also sends spare bots to the mounted guns.
- **Bots and air.** In air under 80% a bot turns its suit's oxygen supply on (off again in good air). A bot on
  orders whose tank is under 35% walks to a powered oxygen station and fills it to 95% before going on.
- **Bots heal.** A bot under 40 health walks to a free autodoc by itself and lies there until 90 health.
- **The crew is kept full** (the author's word). The "bots" number set when creating a game is how many bots
  stand in besides the host: the crew is kept at bots + 1 people. When another player joins and the crew is full,
  a bot steps aside for them (a free one first; what it carried goes back into the locker). When a living player
  leaves, a bot takes their place. Dead players are not replaced: their bodies stay and the reserve rules hold.

### Medbay: autodocs and the body scanner (v60)

- Two **autodocs** ('Y' on the map) on the medbay's lower wall on the upper deck of ship02, and a **body
  scanner** ('X') between them.
- Whoever lies or stands on the floor cell in front of an autodoc (dragged there unconscious, or walked in) is
  healed **3 health a second** while the ship has power and the autodoc works: wounds close first (they never
  close by themselves), then health. Someone out cold comes round as usual once health is back. From nothing to
  whole takes about 35 s. It **never brings back the dead** (bodies stay).
- Somebody holding E at the autodoc **tends** the patient: twice as quick, and a lesson in medicine every 5 s.
- (v69) With two on its cell it heals **the worst off who needs it**, never a whole one, and never the one holding E:
  you may stand on the bed and tend somebody lying there.
- E at the scanner reports on whoever lies in the nearest autodoc (or on yourself): health, wounds, conscious or
  not, suit and oxygen. It is groundwork for the complex health the author has in mind (cryo capsules later).
- Both can break and be mended like any machine.

### Blast doors (v60)

- Whoever stands at a **holomap** monitor can lock doors against boarders: a click on a door on the plan locks
  it (a click again unlocks it); two buttons lock or unlock every door of our ship. Locked doors are outlined
  purple on the holomap; the summary counts them.
- A locked door still opens for our own crew and bots, but not for pirates while the ship has power. A pirate
  that walks into it stands there **cutting through**: **12 s** of work for one (two cut twice as fast), with a
  blow sound every second. Then the door is wrecked open (jammed) until somebody mends it.
- Without power the locks don't hold, as every lock aboard.

### Enemies (v62)

The author's road plan, part 3. New kinds of enemy and new ways for them to get at us.

- **Drone ship** (дрон-корабль, a fifth class; its name is «Дрон-корабль «Страж»» and the like). Comes from
  **3 jumps** out, weight 3. Hull **10**, system strength 3, guns **2** (3 from 7 jumps) from laser, ion, autocannon,
  rockets, rapid, heavy, ion cannon, Shrapnel, railgun, Hammer; shield 50%; guns charge 1.25× slower; our hit −10%;
  armour 20%, point defence 30% (from 4 jumps); reward **45**, 1–2 things aboard.
  - It has **no crew**: nobody flies it or mans its guns, so it works as if every post were manned. It has no
    cockpit, quarters or jump drive room, but a **control core** (Ядро дронов) in a room of its own.
  - Its temper is **машина** (machine): it **never runs** and **never offers a ransom**, and it **never docks**: it
    always fights at a distance (it does not close in when we are helpless either).
  - While its core works, **repair drones** mend its worn systems at ¾ of one pirate's pace, and it sends an
    **assault drone** across: the first **20 s** into the fight, then every **35 s**. A drone flies **3 s**; our
    point defence, if charged, shoots it down **60%** of the time. One that gets there cuts a hole in our hull
    (like a boarding party) and comes in: a **robot** with a gun and 3 magazines that fights like a pirate, needs no
    air and wears nothing. At most **2** are aboard at once. Knocking out the core stops the drones and the mending.
  - There is **no air** inside it: board it in a suit. Its "crew" are **2 guard robots** standing by its core and
    its guns; they wake when one of ours sets foot aboard. Killing them does not take it: **wreck its core by hand**
    (stand in the core's room, as with any system when boarding) and it is captured: **1.5×** its reward,
    2 spare parts and a fuel can, like any capture. Wrecked from outside, it leaves only dead robots aboard.
- **Teleporters.** From **8 jumps** out an ordinary pirate may carry a **teleporter** in a room of its own
  (raider 25%, gunship 40%, cruiser 60%; only when its hull has a room to spare). **25 s** into the fight and every
  **45 s** after, while it works and somebody of its crew is at it, it puts **2** of its crew into a **random room
  of our ship** (never leaving itself fewer than 2, never more than 4 pirates aboard). The gun console then shows
  a «Телепорт» button to aim at.
- **Boarders without suits** (the author's K12). Boarders who come by docking or teleport may be: **without a
  sealed suit** (35%, from 3 jumps out): they breathe our air and choke when we vent the room; or a **heavy
  stormtrooper** («Штурмовик», 15%, from 6 jumps out): steel plates instead of a suit, takes **half** of every
  wound, but also needs air. Boarders who cut through the hull wear suits as before.
- **Bombs** (a new class of ship gun, ammunition: one rocket each). A bomb is **teleported straight into the room
  aimed at**: no shield, point defence or dodge stops it, but **10%** of the time the teleport loses it. It takes
  nothing from the hull unless said.
  | Bomb | Tier | Charge | Power | Price | What it does |
  |---|---|---|---|---|---|
  | «Шершень» (Hornet) | 2 | 13 s | 1 | 85 | wears the room's system by **2**, wounds everyone in it |
  | «Глушилка» (Damper) | 2 | 12 s | 1 | 80 | puts the system out for **8 s**, stuns everyone in the room |
  | «Термит» (Thermite) | 3 | 16 s | 2 | 175 | wears the system by **3**, **1** hull and a hole, wounds everyone and **kills one** |
  On our ship a pirate bomb bursts at what it aims at (a gun, a console, the shield generator, the SMES, or where
  our people are): it breaks or jams that device, wounds everyone in the room by **25** (the Damper takes 30 health,
  as a stun, instead), and Thermite burns one of them (**60**), holes the hull and takes **5** of its strength.
- **«Шрапнель» (Shrapnel)**, tier 2 kinetic gun: 4 fragments at 70%, 1 damage each, power 2, 90 cr, one shell a
  volley. Half the fragments land in a **room next to** the one aimed at; each wounds everyone where it lands.
- Pirates use them too: gunships may carry Hornet, Shrapnel, Thermite; cruisers Damper, Hornet, Thermite (they
  come with the gun tiers, so from about 4 jumps out).
- **The flagship's second phase** (the author's K21). At **a third of its hull** the flagship mends **every system
  at once** and its shield comes back full. The battleship's guns then charge **1.3×** faster and it sends **assault
  drones** like a drone ship; the carrier teleports every **25 s**, **3** at a time, and calls up **4** more troops.
  The gun console says «Вторая фаза!».
- **Passive modules** (the author's K2: no respirators). Four more modules for the bay, tier 2, sold and found like
  the others:
  | Module | Price | What it does |
  |---|---|---|
  | Глушитель прыжка (jump jammer) | 110 | a pirate's escape jump charges at **half** the pace |
  | Сварочный дрон (welding drone) | 120 | after every jump the hull gets **+5** |
  | Сборщик (salvage arm) | 100 | a wreck or a capture pays **30%** more and **1** more spare part |
  | Автозарядчик (auto-loader) | 100 | a gun with nobody at it charges **10%** faster |
- **Расширитель стойки** (the bay's extender, the author's K3): sold only at **supply stations** (150 cr). Fitted at
  the bay by an engineer like a module, it is used up and gives the bay a **third slot** for good (saved).
- **Our security robots** (the author's K11). «Охранный робот», 120 cr, sold by every trader and at supply stations,
  kept in the locker. With one in hand, click a free floor cell next to you (or press E facing it): it switches on
  and **guards that place**. It fights any pirate it sees (pistol, 2 magazines, a new one every 20 s while it has
  none) and goes back to its place when none is left. It takes **1.4×** a wound (about 70 health against a person's
  100), needs no air, wears nothing, does no work, cannot be ordered and is **not crew** (it fills no crew place). At
  most **2** stand aboard. Broken, it leaves a spare part half the time. A save puts those still standing back into the
  locker in their crates.
- (v65) A robot or a pirate **holds fire** while one of its own side stands within 0.8 of a cell of the line of
  fire, and moves toward its target instead. Before this our robot kept shooting the crewman standing between it and
  a pirate.
- Supply stations now have a small shop at the supply locker: the extender (while the bay has 2 slots) and robots.

### Ammunition at the workbench (v60)

- An engineer at the workbench makes ammunition from **one spare part** in **6 s** (the repair skill makes it up
  to twice as quick): **3 shells**, or **2 rockets**, or **1 EMP rocket**.
- **Point defence** now also shoots at slow shells (the autocannon's and the Hammer's), bringing one down **30%**
  of the time; rockets still 60%. A railgun's slug is too quick for it. This works for us and for pirates alike.

## 18. Bridge and flight within a sector

- The bridge has two consoles (power needed):
  - **sector map** (green screen): the cluster (section 19, "The chart") and jumping. At the bottom of the map there is a legend:
    colour — what is in the sector; white ring — the ship is here; dark dot inside — already visited;
    «?» — unknown what's there; green line — a lane; white — the set jump; (v64) arrow — an exit; grey cloud — a
    nebula; red diamond — a hunter;
  - **ship control** (panel with lights): clicking the sector map sets a course.
- A sector is a 200×200 square; the ship moves in a straight line at 1.5 per second.
- A sector has one main feature: a meteor shower (a circle of radius 45–60, with
  breaches inside), a trader or a station (approach within 10).
- A set jump cancels the course: until the jump the ship drifts straight on by inertia, the course line
  disappears, the helm doesn't respond.

### Derelict ship

- In a **«брошенный корабль»** ("derelict ship") sector it sits at one point, like a trader. Approach within 10 —
  and it appears above the airlock, **3 cells** of open space from the outer door.
- To get there: go out through the airlock and cross space, or **dock** with a button on the ship-control
  console: it comes right alongside, outer door to outer door. Whoever stands on it
  moves along with it. Undocking is the same button.
- It has **no power**: inside it is dark (the room around you is dimly visible, the flashlight lights properly),
  doors open by hand in 1.5 s, there are no emergency shutters.
- Air: some compartments are in vacuum (40%), the rest have thin air (30–90% of normal); in half
  the cases there is a breach in the hull.
- **Loot**: 5–8 items on the floor: patches, spare parts, plasters, magazines, fuel canisters,
  a flashlight, a baton, used medkits, occasionally a pistol with ammo. Whatever is left after you go stays there
  for the next visit.
- While anyone alive is outside our ship (on the derelict or in space) or the ships
  are docked, the ship **doesn't move or jump**; if someone went out while a jump was charging,
  the jump is aborted.
- There are no pirates on derelict ships yet.

## 19. Space, sectors and jumps

- (v64, the author's cluster answers C1–C19) **Space is a road of clusters.** A cluster is **10–14 star
  systems** (up to **16** with a crew of 5 or more players; bots don't count) joined by **lanes**. The ship comes in on
  its left side and leaves by one of **two exits** on its right side. Everything follows from the game's seed: the
  same game always has the same clusters.
- **Jumps go only along lanes** and burn fuel from the tank: **40** units (v67; **35** with the «Стриж» engine, **30** with the «Сокол»). Any system of the current cluster can be visited again.
- **The long jump**: from an exit system, the sector console has «Долгий прыжок» (twice a lane jump's fuel, **80**, a charge 1.5×
  longer). It takes the ship into the **next cluster**, at its start; a cluster left behind can never be entered
  again. Each exit shows the **kind of cluster** it leads to (two exits never lead to the same kind).
- **Kinds of cluster** (the first is always the frontier):
  - **Приграничье** (frontier): a bit of everything.
  - **Пиратские угодья** (pirate territory): more derelicts and ambushes, hunters come sooner (×0.7 of the time).
  - **Торговые миры** (trade worlds): traders and stations, few ambushes, hunters come later (×1.4).
  - **Штормовой пояс** (storm belt): a band of **3–5** ion storms across the cluster.
  - **Мёртвая зона** (dead zone): many derelicts, wrecks and battlefields, one more place per system, **no supply
    station**.
- Every cluster has at least one **trader** and one **derelict**, and every one but the dead zone a **station**. In the
  first cluster a trader is at most **2 jumps** from the start, and the start itself is calm with nothing in it.
- **Danger grows with each cluster** (the author's C13): a cluster is **4 steps** of danger harder than the one before;
  inside a cluster it grows by one step every two columns. Pirate ships and loot tiers go by that
  step, as they went by the distance from the start before.
- **The flagship's lair is the 4th cluster** (section 17). While the flagship lives, its **jammer holds the exits**:
  «Глушилка флагмана пиратов держит выходы из скопления». After it is beaten the exits open and the road goes on,
  harder, cluster after cluster.
- **Nebulae** (the author's C14): a third of the clusters or so (half the pirate ones and dead zones) have a nebula over
  **2–4** neighbouring systems. Inside one: the chart shows nothing but where we have been, the sensors find places only
  within **15**, hunters lose our trail and wander, and the eventer sends pirates half as often.
- **What the chart shows** (the author's C7): the systems we have been to, those within **1/2/3 lanes** (by the sensors'
  tier), and the traders, stations and the flagship (they call out). The rest are «?» until we come near. A system
  inside a nebula shows only once visited.
- (v67) **Exploring pays nothing** (it paid 15 credits before): the author's M1.
- **Old saves** (from before v64) go on at the start of a fresh first cluster; the reserve, the hull, the locker and the
  gear are kept; side quests are dropped, the chapter is kept (a mission under way is set anew in the new space).

- Kinds of system: calm space, meteor shower, trader, supply station, derelict ship, (v61) ion storm, and (v57) the
  pirates' flagship (section 17).
- **Ion storm** (v61): a wide area (55–75 across) around the sector's middle; a jump lands inside it. Inside:
  the reactor gives **half** its power (guns that no longer fit switch off); every **40–70 s** a surge puts one
  of our guns, the shield generator or an SMES out for **10 s** (never the engine or a console). A pirate
  fighting us there suffers too: its guns charge **1.5×** slower, its shield refills at half pace, and the same
  surges put one of its systems out. Leave by flying out or jumping. The chart draws it in blue.
- **Hazards and pirates** (v61): pirate ships come in meteor showers and ion storms as often as in calm space.
  A meteor that strikes our hull in a fight strikes the pirate ship too: **1** off its hull and wear on a room.
- **Jump**: 8 s of preparation, then 15 s for the engine to recharge.
- **Fuel** (v67, the author's R3 and his numbers): the ship has a **tank of 1000 units**. A lane jump burns **40/35/30**
  by the engine's tier, the long jump twice that, at the moment of the jump; **flying inside a system burns 0.1 a unit of
  distance** (crossing a whole system about 20). With an empty tank the ship drifts to a stop and the helm will not
  move it. Without a jump's worth in the tank a jump can't be set, and one whose fuel ran out while charging is aborted.
  Fuel comes as **cans of 100**: hold E at the engine with a can in hand (**3 s**) and it goes into the tank (not
  past 1000, not into a broken engine). A bot on «Работы» pours cans from the locker while the tank is below **400**.
  Sources: a trader's cans (**12**) or fuel straight into the tank (**100 for 12**), a gas cloud (section 26), the
  refinery (section 26), loot, a supply station (tops the tank up to **300**), a wrecked pirate ship (**1** can).
- If the ship cannot jump and has no can aboard (in the locker, in pockets, on bodies or on the floor), after
  **4 minutes** (v67, the author's O2: was 2) help comes. Usually a ship calls on the comms console: nine times in ten a
  passing trader sells **2** cans for **48** credits (double the price); begged, it leaves **1** only one time in four
  (also when nobody answers); one time in ten kind people give **2**. One time in ten it is still the «Дрейфующее
  топливо» ("Drifting fuel") event: **1** can into the locker. No dead end, but help is dear and slow.

### Places inside a system (v64)

- Besides its main thing, a system may hold **places** (none at the first cluster's start, a station or the
  flagship): 0 (30%), 1 (40%), 2 (22%) or 3 (8%). The kind is shown before arrival only as the system's kind; the
  places themselves are **hidden until the sensors come within 35/50/70** (by their tier; 15 inside a nebula). Then the
  chat says so and they appear on the ship-control console. Fly onto one (within **6**) to take it, once.
  (v67, the author's R2) **What a place gives floats out in space** 2–6 cells from one of our airlocks: somebody
  in a suit goes out and brings it in. An armed **tractor beam** pulls one floating thing into the airlock every **5 s**.
  A jump leaves whatever still floats behind. (A ship gear crate or a gun from a place floats too.)
- **Обломки** (debris, 24%): (v67) **2–4 scrap** and, half the time, a spare part; no money.
- **Контейнер** (a dropped container, 20%): 2–3 things (patches, parts, medpatches, magazines, fuel, rations, shells,
  rockets, a probe) and, 30% of the time, a crate of ship gear of the place's tier. **One in five is a pirate mine**:
  **12** off the hull and a breach.
- **Тела** (bodies, 16%): one thing from their pockets and a note; **25%** of the time one of them still breathes:
  **+1 to the reserve**.
- **Брошенный корабль** (an abandoned ship, 10%): it comes alongside like a derelict when the ship is within **10**, to
  be searched (never in a derelict system: one alongside at a time).
- **Поле боя** (a battlefield, 8%; twice as often in the dead zone): debris twice, bodies, gun parts, and 30% of the
  time a damaged ship gun.
- **Засада пиратов** (a pirate ambush, 7%; three times as often in pirate territory, rare in trade worlds): **seen from
  anywhere in the system** and drawn with its circle. Coming within **25** brings its pirate ship out (a raid). It can
  be flown around.
- (v67, the author's R1: work that pays only if you stay) **Work places**, shown with a ring of **10**: the ship must
  stop inside it, and somebody must work.
  - **Аномалия** (anomaly, 10%; twice as often in a storm belt): somebody at a holomap for **30 s** scans it: **1–2 scan
    data** into the locker.
  - **Астероид** (asteroid, 12%): (v81) once the ship stops at it, **the asteroid itself comes alongside** (a rock drawn
    like a ship, with no doors and no air). Its **ore veins** (darker rock with shiny bits) are dug in a suit: hold **E**
    at a vein for **10 s** (up to 30% quicker with the repair skill), a piece of **ore** goes into the hands (or on the
    floor). **4–8** pieces in all, then «Астероид выработан» and the rock drifts off. It cannot be docked, scrapped or
    looted. (Before v81: every 12 s a piece broke off at the feet of one of ours out in space.)
  - **Газовое облако** (gas cloud, 10%; never in a dead zone): while somebody stands at the engine the fuel scoop adds
    **2.5 units a second** to the tank, **150–300** in all.
  - (v77, the author's note) The bridge says for each kind found what it takes («подлетите к метке и остановитесь, потом
    встаньте к двигателю…»), and once the ship holds still there, what to do now. Before, it said "fly to the mark to pick
    up" for all of them.

### Pirate hunters (v64)

- **Hunters** (the author's C15) are pirate ships the chart shows as red diamonds. The first comes **5 min** after the
  ship enters a cluster, then one more every **4 min**; at most **3** at a time (**4** with a crew of 5 or more; **2** in
  the flagship's cluster). These times are ×0.7 in pirate territory, ×1.4 in trade worlds, ×2 on the easy mode and ×0.75
  on the hard one. Each comes in as far from us as it can.
- Every **75 s** each hunter moves one lane closer to us. It **never enters a system with a supply station** (a safe
  harbour). From inside a nebula the chart shows no hunters, and they wander instead of following.
- When one comes into our system, the chat warns: **20 s** to jump away. When we jump into its system, it comes out
  **6 s** later. Its ship is a pirate ship **3 steps** of danger harder than the place, with the hunter's temper, named
  «Охотник «…»». Wreck it, take it, break off its boarding or take its ransom and it is gone; jump away and it stays on
  our trail from where we left it.
  (v67, the author's O3) Jumping out of any pirate fight: every pirate gun charged at least half fires a **parting
  volley** as we go (it lands at once), and the next hunter comes **60 s** sooner.
  (v69, the author's notes) A second hunter already waiting in our system comes out only **45 s** after a fight ends
  (the chat warns), so it can't be taken for the first one back at full strength. A hunter no longer waits while
  another ship is alongside or docked: if nobody of ours is outside, that ship is **pushed off** and the fight starts
  (fly back to it later and it comes alongside again); while anybody of ours is outside, the hunter **shells our hull
  from range**: **4** hull every **8 s** until everyone is back aboard, then comes in.
  (v66) Each time we escape the same hunter it is slower: a lane takes it **75 s × (1 + 0.5 per escape)** (113 s after
  one escape, 150 s after two, 188 s after three).

### The chart (v64)

- The sector console has two views: **«Карта скопления»** (the cluster: systems, lanes, the set jump, exits with arrows
  and the kind of cluster each leads to, «?» for unknown systems, nebulae as grey clouds, hunters, the flagship, quest
  marks and SOS) and **«Карта пути»** (the road: the clusters passed, the one we are in, and how many to the flagship's).
  Its text says the cluster's kind and number, fuel, whether this is an exit, the hunters and the time to the next.
- The ship-control console shows the places found in the system (and the ambush's circle), and (v69) the pirate
  wrecks left in it.

## 20. Eventer (GM)

- Runs events by itself or on an admin's command (admin panel, «Космос и события» tab).
- Events:

| Event | Size | Where |
|---|---|---|
| Micrometeorite (breach) | small | everywhere except a station |
| Meteor volley (3 breaches) | medium | in a meteor shower |
| Console short circuit | medium | everywhere except a station |
| Engine failure | large | everywhere except a station |
| Air plant failure | medium | everywhere except a station |
| Jammed door | small | everywhere except a station |
| Emergency shutter failure | small | everywhere except a station |
| Power failure | medium | everywhere except a station |
| Boarding | large | everywhere except a station |
| Pirate ship: boarding | large | calm space, trader, derelict ship, (v61) meteor shower, ion storm |
| Pirate ship: fight | large | calm space, trader, derelict ship, (v61) meteor shower, ion storm |
| Drifting fuel (1 can, v67) | small | by itself, only when the ship cannot jump and has no can aboard |
| Flagship: battleship, Flagship: carrier (v57) | catastrophe | only on an admin's command |

- Pace: once every 3–6 minutes in a calm sector, at a trader and (v61) in an ion storm (its surges come on
  their own), once every 25–45 s in a meteor shower; no events at a station. More often with a large crew (up to 2.5 times).
- Breathers: 15 s after arriving in a sector, 8 s after entering or leaving a shower.
- The eventer watches the ship: it gives no new troubles while the whole crew is down or there are more breaches
  than people; with no patches on board breaches are three times rarer; unarmed crews are
  boarded half as often.

### Admin panel

- For the **host** (the player whose game created the server) and for players the host **made
  admins**. Admins are remembered by player name in the campaign save. Opens with **F2** or from the
  menu (Esc). The server checks every command; others' presses do nothing. You can walk while it is open.
- **Things** tab (v60.1: built from the game's own item lists, so new things show up by themselves): every
  item as new (a pistol loaded, a medkit full, a spacesuit's tank full), grouped under the supply locker's
  sections, with its hidden **tier** shown on ship guns and ship gear ("ур. N"; only the admin sees it).
  1, 2, 5 or 10 at a time, and **where**: into the hands (else a free slot, else the floor underfoot) or
  into the **supply locker**. Ship guns come in every kind; a picker gives tier 3 guns one of the five
  effects, and a box gives guns damaged. Ammunition, probes, drones and gun parts are cargo and always go
  into the locker. All 15 gear crates (5 systems x 2 upgrades, 3 armours, focusing array, phase drive) are there.
- **People** tab: for everyone aboard (bots and pirates too): heal (health 100, wounds closed, tank
  refilled; also raises the dead where they lie, but not bodies left after a return from the reserve),
  kill, go to them, bring them to me, change job (and access), (v60.1) every skill at its best. «Heal
  everyone»; (v60.1) +1 bot / -1 bot (the crew is kept that size until the server stops; at most 16 bots).
  The host also makes and unmakes admins here.
- **Ship** tab: mend everything (breaches, machines, doors, shutters, power), seal breaches, breach
  the hull near me, normal air in every cell and a full air plant store, fill the supply locker up to
  its starting stock ((v65) and every other kind it keeps: ship gear and seeds 1 each, security robots 2, the black box 1;
  ship guns 1 each, rockets, shells, parts and quest cargo 10), +100 credits, hull to 100, +1 in the reserve, save the campaign, (v60.1) charge
  everything (shield full, armed guns charged, jump drive and phase drive ready), (v61) SMES full or empty,
  an ion surge now. (v60.1) **Ship gear at
  once**, without an engineer's work: each system's tier (1 = built in, 2, 3) from a list that shows the
  tier now fitted, any module into the bay (a module of the same sort is swapped, else it takes a free
  slot, else the first), and emptying the bay. What comes out this way is gone.
- **Space and events** tab: a station, a derelict, (v61) a meteor shower or an ion storm, or (v60.1) a trader of a chosen kind (arms dealer, junk
  dealer, black market) in this sector with the ship put at it (until the next jump), a pirate with a
  pistol or a baton in front of me, (v60.1) a **pirate ship** of a chosen class (cutter, raider, gunship,
  cruiser) and temper (any, calculating, cautious, reckless, hunter) that either fights at a distance or
  comes to board (if a ship can come now), the eventer on or off, and every event by hand (the two
  flagships among them).

## 21. Crew, jobs, reserve

- The **job** is chosen in the menu before joining. It gives access to compartments and a skill that
  grows fast.

| Job | Access | Own skill | Extra starting gear |
|---|---|---|---|
| Captain | everywhere (one per ship) | — | flashlight |
| Pilot | bridge | piloting (v60) | flashlight |
| Engineer | engine room, life support, gun compartments | repair | spare part |
| Doctor | medbay | medicine | plaster |
| Guard | armoury, gun compartments | shooting | stun baton, handcuffs (v70; a baton before) |

- (v70) There are no sailors any more: a newcomer gets the job asked for if no other person aboard holds it, else
  the first free one of pilot, engineer, doctor, guard; with every job held, the one asked for (two share it).
- There is **one** captain per ship: if there already is one, the second applicant gets a free job
  that way and a message about it. Last evening's captain keeps the
  place until they return.
- Each member of the first crew arrives with a **radio**, a **patch** and a **spare part**, plus their
  job's item. Those who come from the reserve (by R or by rejoining after death) are dressed
  (spacesuit and jumpsuit), but **with no items**.
- **Skills**: repair, medicine, shooting (gunnery), and since v60 **piloting** (the pilot's own skill), from 0 to 100.
  Gunnery grows by firing and standing at a mount, piloting by dodging at the controls, medicine by tending an
  autodoc, repair by mending and mounting guns. Your job's skill starts
  at **50**. Each finished task of your own skill gives **+2**; a task of another skill gives **+1**
  for every three. Skills are shown in the second top line (F1).
- Bots and pirates go everywhere (they have no jobs).
- **Crew reserve**: people who will replace the dead. The ship sets out with **3**.
  - A dead player can press **R** after 5 s and return as a new person of the same job
    (skills from zero, own job's skill from 50). This costs **one from the reserve**; the body with its items
    remains.
  - (v66) Whoever comes back (a player or a bot) takes a spawn tile with **no pirate in its room or within 6 tiles**;
    if every free tile is watched, the least watched one.
  - Reserve empty — you can't return until your crewmates hire people at a trader.
  - A dead player who left the game also takes one from the reserve when returning under the same name.
    If the reserve is empty and someone of the crew is alive, they won't be let in.
  - There's no coming back at all if everyone has died and nobody is in reserve: the campaign is over
    (section 23).
- Bots wander the ship, sometimes playing with the flashlight and items; a dead bot returns
  after 15 s and doesn't use the reserve. Since v55 they take orders (section 17, "Bots under orders"); an
  order stays through death.

## 22. Speech, radio, intercom

- **Aloud** (Enter, text): heard by those on the same deck no farther than **7** cells, if
  both the speaker and the listener have air (at least 20% of normal). In a vacuum it is heard
  only up close (up to 1.5 cells: helmet to helmet).
- **Radio**: text starting with «**;**». Heard by everyone who has a radio, on any deck and
  in a vacuum. Without a radio you can't speak this way.
- **Intercom**: text starting with «**!**», standing at a panel (up to 1.5 cells), or E facing the
  panel. Heard by everyone no farther than **6** cells from any panel on the ship and standing in air.
  Power is needed.
- The chat shows where a phrase came from: **[рация]** ("[radio]"), **[интерком]** ("[intercom]"); spoken aloud has no tag.
- You can't speak while unconscious. **The dead** speak only among themselves (**[мёртвые]** ("[dead]")),
  the living don't hear them.
- Ship messages are still seen by everyone.

## 23. Campaign: hull, end, saving

- The **goal** (since v57) is to reach the pirates' flagship in the 4th cluster and beat it (section 17); after
  that the game is won and the voyage may go on. Until then, hold out. The top line (F1) shows the reserve and hull integrity.
- **Modes** (v63, the author's R9): chosen for a new campaign in the menu («Режим новой кампании»), kept in the save.
  **Easy**: a hull worn to nothing does not end the voyage; it costs **50** of the hull's top strength instead, and
  the hull is whole again (200 → 150 → 100 → 50; the next time at 50 is the end). **Normal**: as before. **Hard**:
  pirates are never cautious (reckless or hunters instead), one more boarder in every party, a pirate ship pays
  **75%** of its reward, the flagship grows every 2 min.
- **Hull**: integrity **200** (100 until v49; an older save has its hull doubled). Each breach takes **5**, each
  pirate hit on a gun, console or the shield generator **3** per point of its damage. At **50** and below the ship warns you. It is patched at a trader
  and at a supply station (section 10).
- **End of campaign**: the hull reaches zero (the ship is destroyed), the whole crew has died
  and nobody is in reserve, or (v57) the carrier flagship's boarders have taken the ship. The game stops: no more jumps, the screen shows a summary — how many
  sectors were passed, how far from the start, how many jumps and how long you held out.
  To start over, create a new game.
- **Saving**: the campaign saves itself — once a minute, after every jump and when
  the server is stopped. It is stored in the file `campaign.json` in the game's data folder
  (on Windows: `%APPDATA%\Godot\app_userdata\Космический прототип`).
  - The game host can also save manually: Esc, **«Сохранить кампанию»** ("Save campaign"). Everyone gets
    «Кампания сохранена» ("Campaign saved") in chat (or why it failed: a game without saving, the campaign is over).
  - In the menu: **«Продолжить кампанию»** ("Continue campaign", with a short summary of the save) or **«Новая
    кампания»** ("New campaign"; if a save exists, the button must be pressed twice: the old one will be lost).
  - The dedicated server (`start-server.bat`) continues the saved campaign if there is one;
    `CAMPAIGN=new` in the file starts a new one.
  - (v63) Also saved: the mode and the hull's top strength, quests, the chapter, answered SOS calls, the trays,
    hunger, and the flagship's roaming and growth. A save from before v63 plays on the normal mode and gets the
    start's 16 rations.
  - What is saved: the place in space and where the ship has been, supplies, credits, reserve, hull,
    breakdowns and breaches, jammed doors, air in each compartment, items on the floor, bodies,
    and **each character by player name**: where they stood, health and wounds, items, clothing,
    tank, job and skills. Returning under the same name, a player gets their
    character back. This works the same evening too: leave and rejoin — you're in the same place with the same things.
    (v77, the author's R1) Coming back after a lag drop, before the server noticed it (up to 12 s), the same name from
    the same address takes the same character back at once (before, it made a second one, «Имя 2»). A character saved
    out in space, or on a ship that is no longer alongside, comes back at the spawn point aboard.
  - Not saved: a derelict or pirate ship alongside, pirates on board, bots,
    the eventer's mood.
  - A lost campaign leaves no save.

## 24. Controls

| Key | Action |
|---|---|
| WASD, arrows | walk; (v74) two keys at once (up or down with left or right) walk on a slant |
| E | action: console, locker, holomap, drone monitor, ladder, repair, search, pick up item, hack lock, intercom |
| F | drag a person lying down / let go |
| X | (v81) hold position: a living wall nobody passes, see section 36 |
| Q | oxygen supply |
| 1–6, mouse wheel | what's in hand |
| Z | use the item in hand (flashlight) |
| G | drop the item on the floor |
| Mouse click | on something within reach: as E (pick up, console, machine, repair while held); (v73) on something diagonally next to you: one step to the side, then as E; elsewhere: shot, blow, healing |
| Right click | (v73) a menu of what can be done there: use, work until done, drag, look; on a bot of ours, its orders |
| Ctrl + wheel | (v73) zoom the view one step in or out (three steps in all) |
| R | return after death (takes one from the reserve) |
| Mouse over | (v53) something usable you can see gets an outline, as in SS13: bright yellow within reach, faint grey farther off; since v54 it hugs the thing itself (a machine on a wall, things on the floor, a body), a door, hole or ladder keeps its cell's square |
| I, Tab | inventory window |
| O | (v55) crew window: posts, battle position, orders to bots |
| Enter | chat: aloud; «;» — radio, «!» — intercom at a panel |
| T | chat straight into the radio |
| F2 | admin panel (host and admins) |
| Esc | menu: settings, admin panel, saving (host) |
| H | (v74) the help book |
| F1 | ship status and key hints at the top of the screen (hidden by default since v47) |
| F3 | debug |
| F11 | full screen |

### Settings

- From the main menu and from the game's menu (Esc); kept in `user://options.cfg`, they take effect at once.
- **Sound**: overall volume, sounds on the ship, engine hum, footsteps (v56, 50% by default), the ship
  fight (v56) (each 0–100%), mute.
- **Picture**: full screen, vertical sync, frame limit (30, 60, 120, 144 or none), frame counter
  in the top left corner (shown even while F1's status is hidden), the white flash after a jump,
  the screen shaking when the hull is hit (v56, 0–100%), (v73) the size of the interface and its text (75–150%),
  (v74) «Подсказки первой смены» (the first-shift checklist; turning it on starts it from the beginning),
  (v77) «Взгляд за мышью» (the view follows the mouse; on at first; off: you look where you walk),
  (v79) «Камера смещается к мыши» (none, up to 1, 2 or 3 cells; 2 at first).
- (v79, the author's Task Manager picture: the game's window was marked "not responding" while it played on) While
  the game's window is in the background, vertical sync is off (the frame limit of 30 paces it), so a covered or
  minimised window keeps answering Windows. The program shows as «Spacer» in Task Manager.
- **Controls**: every action above can have two keys. A key may be combined with Ctrl, Shift or
  Alt. A key given to one action is taken from the one that had it (the window says so).
  Backspace clears a key, Esc cancels, one button restores every default. A bare key still works
  with a modifier held, unless that exact combination belongs to another action. Hints on the
  screen name the keys as set.

## 25. The road: comms console, quests, food, hydroponics, modes (v63)

### Comms console and calls

- A **comms console** stands on the bridge (sign `K` on the map, where a window was). E at it opens its screen;
  it needs power (the bridge's backup SMES keeps it going). Its lamp blinks while a call waits.
- **Calls** (the author's R2, "text events"): a short story and **2–4 answers**. Anybody at the console answers
  for the ship; the chat tells everyone the outcome. A call nobody answers in **90 s** takes its plain answer
  (or, if that cannot be paid, the first that can). One call at a time; never in a fight (a call due then waits).
- A call comes on arriving somewhere quiet (calm space, trader, station, derelict; a few also in meteors or the
  storm) **35%** of the time, **8 s** after arriving. **21 events** besides the special ones: a rescue capsule,
  a peddler, miners in trouble, an unmarked container, refugees asking for food, a pirate toll, a broken drone,
  a science ship, a debris swarm, a seed bank, a middleman with cargo, a bounty board, a lost ship's black box,
  a sick trader, an ion jellyfish (storm only), a voice on the radio, an old friend, a trader's fuel leak, a ration
  vending machine, a quarantine buoy, a station's order. Outcomes are drawn by weight: credits, fuel, rations,
  parts, medkits, seeds, a crate of gear, a survivor for the reserve, or a breach, a hurt crew member (wounds 25–35),
  a power glitch, a pirate ship to fight.
- **Blue answers** are open only when somebody alive aboard (a bot counts) has the **job** (doctor, engineer,
  guard), the **skill** (piloting or repair **70**+), or the locker holds the **thing** (a probe; it is not used up).
  They always turn out well. Answers that **cost** (credits, rations, a medkit) are grey without it.

### Quests

- Some answers give a **quest** (at most **3** besides the chapter's missions; no time limit). Its target is a
  system of **this cluster** **2–4 jumps** away (nearer or further if none fits; v64: a cluster left behind fails its side
  quests), marked on the chart with a yellow diamond «!»; the
  comms console lists them with the jumps left and the reward.
  - **Cargo** («Груз для станции»): a crate (`Груз по заданию`) goes into the locker; arriving at the target station
    with it pays **30 + 8 per jump**. Without the crate in the locker the quest fails.
  - **Bounty** («Награда за голову»): a named pirate ship (a rolled raid) comes out **6 s** after we arrive in its
    sector. Wreck it, break off its boarding, take it, or take its ransom: paid **40 + 8 per jump**. If it gets away
    (or we jump away from it) the quest is lost.
  - **Black box** («Чёрный ящик»): in a derelict sector; the derelict there has the box (`Чёрный ящик`) lying aboard.
    Put it into the supply locker: paid **30 + 8 per jump**.
- **The chapter's missions** (the author's R6): arriving at danger step **3–11** (v64: from the end of the first cluster through the third), the fleet calls: «Пропавший
  конвой» (find the convoy's wreck in a derelict sector and bring its log, a black box, to the locker; **60** credits
  and a crate of better gear). That opens «Коды флагмана»: a pirate courier (a gunship) waits in a system 2–4 jumps
  away, towards the cluster's exits (leaving the cluster sets it anew in the next one); beat it for **80** credits and the **flagship's codes**: in its fight all its rooms show at
  once, and its growth goes **one step back**. Turned down, the first mission is offered again 3 jumps later; a
  courier that gets away is found again in another sector.
- **SOS** (the author's R5): about **15%** of calm systems send an SOS, marked «SOS» on the chart. Arriving there brings
  its call: help (**40%** survivors: 2 to the reserve and 3 rations; **30%** the crew is dead: (v77, the author's S1) the
  ship itself comes alongside, dark and nearly airless, with **3** of its dead aboard (1–2 things in each one's pockets)
  and the usual derelict's loot, to board, search and cut for scrap; it stays while our ship stays within **10** of where
  it came, and is left behind (with its dead) once we fly off or jump; if no ship can come alongside, 3 parts and
  15 credits as before; **30%** a pirate trap), the guard's blue answer (no trap: survivors, or the pirates reported for 25 credits), or leave.

### Food and hunger

- **Rations** («Паёк») are kept in the supply locker; the ship starts with **16**; traders sell them (**3** credits).
- Every **jump** the crew eat **one ration for every two** of them (players and bots alive; the reserve sleeps and eats
  nothing). The chat warns when two jumps' worth or less are left.
- With nothing to eat at a jump the crew **starve**: everybody's health sinks by **0.1 a second**, down to **30**.
  Food in the locker again: the hunger passes at once (1 health a second back).
  Until hunger turns deadly it never holds health below **30** on top of wounds, so someone knocked out while starving
  still comes round (only wounds of **90** and more need the autodoc).
- (v71, the author's L1: hunger slows and finally kills) After **10 min** of starving everybody **walks slowly** (as with
  a broken leg; the HUD says «Слабость от голода»). After **25 min** hunger turns **deadly**: health sinks **0.05 a second**
  below 30, so about **35 min** in people pass out and about **68 min** in they die. Bots starve the same way; the reserve
  sleeps and does not. Any food in the locker stops it at once. The old rule "nobody dies of hunger" is gone.
  The comms console shows «Пайков нет: экипаж голодает».

### Hydroponics

- Four **hydroponic trays** (sign `P`) on the lower deck. Hold **E** at one:
  - empty: plants the seed packet in hand, or else the best packet from the locker (**2 s**);
  - growing: when it **wants tending** (every **60–90 s**; a blue drop blinks over it), tends it (**2 s**). Wanting
    care it grows at **half pace**; after **5 min** of that (the drop turns red at half way) it **withers** and must be cleared (2 s);
  - ripe (yellow fruit): harvests it (2 s): its rations (and the herb's plasters) go to the supply locker.
- Without power a tray stands still; **mushrooms** grow in the dark.
- Plants (rations at harvest, time to ripen when tended): **mushrooms** 2, 4 min (seeds 4 cr.); **chlorella** 3, 5 min
  (5 cr.); **soy** 4, 7 min (6 cr.); **potato** 6, 9 min (8 cr.); and two hybrids that are not sold: **sweet tuber** 8, 8 min
  (potato and soy), **healing herb** 1 ration and **2 plasters**, 6 min (mushrooms and chlorella). The ship starts with
  2 packets each of mushrooms and potato.
- A harvest gives its seed back **60%** of the time; that seed **mutates** **20%** of the time: plain → **rich** (+1 ration)
  or **early** (ripens in two thirds of the time), either of those → **choice** (both). A mutated packet has a gold corner.
- **Hybrids**: harvesting a plant while the tray beside it is ripe with its pair gives a hybrid seed **35%** of the time.
- **Bots** on «Работы» tend, harvest, clear and plant the trays (after what is broken, before the guns' orders).
- The eventer's admin panel: «Гидропоника: всё созрело».

### Cryosleep

- Four **cryopods** (sign `C`) in the crew quarters: the reserve sleeps there. One from the reserve who replaces the
  dead (R) comes out in front of a working pod with power; without one, at a spawn point as before. E at a pod tells how
  many sleep.

### The admin panel (v63)

- «Вызов на пульт связи» (any for this sector) and a list of every call by name; «Флагман: проснуться и +1 шаг роста»;
  «Гидропоника: всё созрело».
- (v64) «Охотник входит в скопление», «Открыть все тайники системы», «В следующее скопление (верхний выход)» and
  «(нижний выход)».

## 26. Work and money on the road (v67)

The author's "make every part interesting" answers (`/mnt/project-files/plans/every-part-plan.md`): money comes from
work, not from visiting; fuel is counted in units; places need a trip outside.

- **Fuel in units**: section 19. A tank of 1000; jumps 40/35/30 by the engine; flying burns 0.1 a unit of distance;
  cans of 100 poured at the engine.
- **Scrap** («Лом»): hold E at a wall of a **dark ship alongside** (a derelict or a wreck), from inside it or from space
  in a suit: **8 s** a piece (the repair skill cuts it to half), into the hand or a free slot (else at your feet). A
  derelict gives **8** pieces (remembered for its system), a wreck **8**, a ship taken by boarding **14**; then «С этого
  корабля больше нечего срезать». Debris and battlefields give scrap too (floating outside).
- **What scrap, ore and scan data are for**: traders buy them at their **full price** (4, 6, 25), half as much again
  when wanted; scrap welds the hull from outside (+10, section 8); the refinery makes fuel of scrap or ore.
- **Traders want things** (the author's M3): each trader looks for **two** things among scrap, ore, scan data, rations,
  spare parts, patches, medkits and shells, and pays **1.5×** their price for them. The chart's line for a trader
  says «ищет: …», the chat says it on arrival, and the trader's window marks them. Nobody sells scrap, ore or scan data.
  (v77, the author's T1) A trader **never sells** the two things it looks for: it needs them itself (before, buying one
  cheap and selling it back at 1.5× made endless money).
- **The refinery** (the workbench, an engineer, **10 s**): a can of fuel from **4 scrap** or **3 ore**. It costs more
  than buying (4 scrap sell for 16, 3 ore for 18, a can's worth costs 12 at a trader): it is for when no trader is near.
- **Work places** (anomaly, asteroid, gas cloud) and **floating finds** with the tractor beam: section 19, "Places".
- **Escaping a fight** costs a parting volley and brings the next hunter sooner (section 19, "Pirate hunters").
- **No fuel**: help is slower and dearer (section 19, "Fuel").
- The flagship grows **only with time** (section 17).

## 27. Fights for the whole crew (v68)

The author's F1 to F4, J4, E1 and G3 answers (`/mnt/project-files/plans/every-part-plan.md`): in a ship fight every
seat has a job, not only the gunner's.

- **The pilot's evade** (F1): at the ship's controls, in a fight, the button «Уклонение!» or the **space bar**. For
  **1.5 s** (+1 s with the best piloting skill) the pirates' shots fired hit **50% less often** (never below 5%). It costs
  **40** from the SMES and rests **12 s**; it needs the engine running and no manoeuvre going on. The helm shows how charged
  their guns are (as our sensors see them), so the evade can be timed to their volley.
- **The power panel** (F2): the SMES terminal in the engine room got a second half, «Щит питания». From it, and only
  from it, the guns, the point defence and the shield are switched on and off (the gun console shows their state and
  points to the panel). Also there:
  - **Engines**: 0 to 2 levels of power, **2** energy each, each **+5%** to our dodge while somebody is at the controls.
  - **Breakers**: the lights, the air plant and the hydroponic trays each take **1** of the ship's own draw of 4 (consoles,
    doors and pumps take the last 1 and are never switched off). Switched off, that energy goes to the guns and the
    shield. Lights off: the ship is dark as without power except the bridge (the consoles still work); air off: the air
    plant adds no air; trays off: the plants do not grow.
  - **Overcharge**: the reactor gives **+4** for **20 s**, then cools **40 s**. Each second of it the engine burns out with a
    **3%** chance (mend it as usual; the SMES carries the ship meanwhile).
  - A **bot at the engine post** minds the panel for a lone player: it switches the shield, the guns and the point defence
    back on as far as the reactor allows. It never touches the breakers, the engines or the overcharge.
- **Loaded mounts** (F3): shells and rockets can now be taken out of the supply locker. Facing a gun mount with a round for
  its gun in hand, hold E: **2 s** a round, up to **4** in its breech. While a round is loaded the gun charges **1.3×**
  faster, and it fires the loaded rounds first. An empty breech still takes rounds from the locker as before. A gun taken
  down gives its loaded rounds back to the locker. In a fight bots on «Работы» bring rounds (2 at a time) and load them.
- **Fights with goals** (F4): a pirate ship the eventer or a road ambush sends may come with a goal (20% cargo, 15% bounty,
  15% courier); the chat says it and the gun console shows it.
  - **Cargo pod**: it sits in one room of their ship (marked on the plan with a crate). A hit there smashes it. Whole when
    the ship is wrecked, taken or pays a ransom: **+1×** its usual reward.
  - **Bounty**: knock out its **weapons and engine together** (with none of ours aboard) and it surrenders: **2×** the
    reward, and it goes off under guard. Wrecked, the bounty is lost.
  - **Courier**: it charges its jump at once and is gone in **40 s**. Stop it (engine or jump drive) and wreck or take it:
    **+1×** the reward.
- **Alert levels** (J4), set by the captain (anybody, with no captain aboard) at the ship's controls:
  - **Green**: as usual.
  - **Yellow**: the free bots go to «Ремонт». A pirate ship coming raises yellow by itself, and when the fight is over
    and no pirate is aboard it goes back to green.
  - **Red**: every bot to a post, every door locked as a blast door (while there is power), the lights dimmed, a siren.
    Leaving red unlocks the doors and frees the bots the alert sent.
  - Everyone hears the chime or the siren (where there is air) and sees the level at the top of the screen.
- **Hits break things** (E1): a pirate shot that hits our hull breaks something within **6 cells** of it with a **30%**
  chance (**45%** for a heavy one): a door jams, a shutter fails, the air plant or a console shorts out, or the engine
  stalls for a moment if it is near.
- **The fight's details on the bridge only** (G3 B): who fired what, the shield taking it, beams, repairs, manoeuvres,
  the evade and the drone's reports reach only those standing in a bridge room. Warnings (hull hits, breaches, boarders,
  the alert) still reach everyone.

## 28. People over bots (v70)

The author's P, M, H, G, B and W answers (`/mnt/project-files/plans/every-part-plan.md`, questions page
"Spacer v70: вопросы"): a person at a post is worth more than a bot, and every job has its own work.

- **Bots at half** (P1): a bot at a post gives **half** of what a person gives there: the helm's dodge (15% + up to 10%
  by skill), the engine post's 5%, the shield generator's 1.25× pace (a bot: 1.125×), a gunner's mount pace, the gun
  console's aim bonus and the tending of an autodoc. Only a person can press the evade.
- **Jobs** (J1): see section 21: the sailor is gone, a newcomer takes a free job.
- **The autodoc** (M1): alone it heals only up to **50** health (it says so once). Somebody holding E at it tends it:
  then it heals fully, **2×** faster, up to **3×** with the best medicine skill (a bot tending adds half of that), and after
  **3 s** of tending it also mends the patient's injuries. A bot lying in an untended autodoc gets up at 50.
  The body scanner lists injuries too.
- **Injuries** (M2):
  - **Bleeding**: a bullet starts it **25%** of the time (a pellet 10%). It costs **0.5** health a second (as a wound)
    and stops by itself after **90 s**. A patch, a kit or a tended autodoc stops it.
  - **Broken bones**: a wound of **25+** at once breaks an arm or a leg **20%** of the time. A broken leg makes every step
    slow (as hauling); a broken arm makes the hands **2×** slower and a shot up to **0.8** cells off. A **splint** (click
    on oneself or a neighbour, or Z; **4 s** standing still) or a kit sets it.
  - **Concussion**: a blow gives one **15%** of the time, a stun baton **30%**, a flashbang **30%**, a bomb's blast **50%**.
    For **90 s** the screen swims and a person cannot work a console (a kit or a tended autodoc ends it sooner).
  - The HUD shows one's injuries above the hand line. Coming back from the reserve heals them all.
- **The pilot outside fights** (H1, H2):
  - In a **meteor stream** each meteor is seen **2.5 s** ahead (a beep on the bridge, a line at the helm). The pilot at the
    controls presses the evade (space or the button): **60%** to steer round it, +30% with the best skill, **10** from the
    SMES. A bot at the controls does it by itself at half the chance; with nobody there it hits. A meteor volley's three
    meteors come 3.5 s apart, so each can be steered round.
  - In an **ion storm** a pilot at the controls steers clear of each surge **40%** of the time (+20% with the best skill;
    a bot half).
- **Prisoners** (G1 to G3):
  - A pirate who is down (out cold, or knocked down by a stun baton or a flashbang) is cuffed with a click of
    **handcuffs**: what he fought with falls to the floor, he lies bound and nobody fights him.
  - The **armoury is the brig**: anywhere else he slips the cuffs after **2 min**, grabs a pipe and fights again.
    (v75: also the four cells of the brig, and he slips them only when awake, above half health and with none of ours
    in his room; see section 33.)
  - A supply station or a trader takes every prisoner aboard for **40** credits each (the trade screen's «Сдать пленных»).
  - Searched for the first time he **talks**: every hidden place of this system is marked on the chart, and to a guard
    he also names the pirate hunters' sectors in this cluster.
  - A pirate ship come to fight while we hold one calls the comms console after **6 s**: give him back and they leave;
    ask a ransom (they may pay **30**) or refuse. Never the flagship, never a drone ship, and not while ours are aboard
    their ship.
- **Boarders' goals** (B1): about **half** of a boarding party come for something (at most one bomb and one kidnapper a
  party). A pirate with a goal fights only those within **4** cells, or anybody for **8 s** after being hurt.
  - **Wrecker**: goes to a machine (the engine while the escape rule allows it, the air plant, the shield generator, a
    gun with a weapon on it; never a bridge console) and breaks it in **8 s**.
  - **Robber**: **5 s** at the supply locker, takes **3** things into its pockets and walks back out the hole it came in by.
    Killed on the way, its body holds them.
  - **Bomber**: plants a bomb by a machine in **2 s**. The bomb beeps every **2 s** and goes off after **30 s**: a
    flashbang's burst, a hole in the nearest hull within 3 cells, the nearest machine within 3 cells broken, **25**
    to everyone within 3 cells. Hold E standing on it or facing it to disarm it: **5 s**, an engineer **2.5 s**. It cannot
    be picked up.
  - **Kidnapper**: hauls one of ours who is lying (within 14 cells, on its deck) to its hole and leaves with him: he is
    lost, no body is left. A player comes back from the reserve as after a death; a bot after 15 s.
- **Weapons** (B3, B2):
  - **Shotgun** (45 cr.): **6 pellets** in a fan (**0.2** rad to the outermost), **15** each, reach **6** cells,
    **4** shells (a box of 4 shells: 6 cr.), a shot every **0.45 s** (the pistol: 0.3 s). Up close all pellets hit (90);
    **4 or more** pellets of one shot knock the target down for **1.5 s** (a robot a fifth of that). (v80, his note "the
    pistol is much better"; until v80: 5 pellets of 10, 7 cells, a shot every 0.6 s, no knockdown.)
  - **Stun baton** (the guard's): a blow of **5** that knocks down for **5 s** (a machine 1 s).
  - **Flashbang**: click where to throw (up to **6** cells, it stops short of walls). **1 s** later everybody within **4**
    cells who sees it falls for **3 s**, ours too.
  - **Welder**: hold E at a shut door for **4 s**: it is welded and opens for nobody, ours neither; bots go round it.
    Pirates cut through it in **12 s** (it is then wrecked open, jammed, until mended). Hold E again to cut the weld.
  - The locker starts with 1 shotgun, 2 boxes of shells, 1 stun baton, 2 flashbangs, 1 welder, 2 handcuffs, 2 splints.
- **Pirates walk better**: a pirate now picks its way at the end of each step (before, it changed its way only when it
  ran into a wall, so it went straight down corridors).
- **Boarders force shutters**: the hole a boarder cuts drops the room's emergency shutters; a pirate in its way now
  forces one up by hand (**3 s**, then it stays up **5 s**), as anybody can. Before, it stayed shut in that room.
  Our security robots do not.

## 29. Upkeep: hunger, the galley, complex repairs (v71)

The author's L1, L2 and H1 answers (`/mnt/project-files/plans/every-part-plan.md`; questions page "Spacer v71: вопросы").

- **Hunger** (L1): see "Food and hunger" in section 25: slow after 10 min of starving, deadly after 25 min.
- **The galley** (L2): a **stove** (sign `G`) in the hydroponics room on the lower deck. **E** opens its screen; anybody
  cooks, standing at it (**5 s**, the stove needs power). The ingredients come from the supply locker and the dish goes
  back into it. Bots do not cook.
  - **Рагу** (stew): **2 rations**. Eaten: for **5 min** wounds close by **0.1 a second** (up to **30**).
  - **Кофе** (coffee): **1 ration**. Drunk: for **4 min** all work by hand takes **¾** of its time: repairs, patching,
    treatments, the trays, the workbench, cooking, cutting scrap.
  - **Травяной отвар** (herb broth): **1 ration + 1 plaster**. Drunk: at once stops bleeding, ends a concussion and closes
    **15** wounds.
  - A dish is eaten like a patch: a click on oneself (or **Z**) or on a neighbour. One effect at a time (a new dish
    replaces it); the HUD shows it and the time left. Dishes are never eaten at jumps: the crew's rations are.
- **Complex repairs** (H1: "optional, chosen at the start of the game: hard difficulty means more mechanics"): a
  checkbox «Сложный ремонт» next to the mode in the menu, ticked by itself for the hard mode; a continued campaign keeps
  its own. With it on:
  - consoles and screens (chart, helm, gun console, drone monitor, holomap, comms, intercom, autodoc, scanner, module
    bay, shield generator) want a **circuit board**; everything else and the doors want a **mechanical part**. With
    the wrong part, or none, the work takes **3×** as long (the part is kept);
  - the one at work needs a **toolbox** («Ящик с инструментами», never used up) on them: without one it takes **3×** as
    long again (so **9×** with nothing at all);
  - nothing ever needs a part outright, so a broken helm can always be mended (the escape rule).
  - Engineers come aboard with a toolbox and a board too. Bots on «Работы» fetch a toolbox and the kinds of part the
    broken things want.
  - With it off, any part (mechanical or board) works anywhere, as before, and no toolbox is needed.
- **New things**: toolbox (**20** cr., the locker starts with **2**), circuit board (**12** cr., **2**). Boards are also
  found on derelicts and in containers, and a captured pirate ship gives one.

## 30. Bots at work and the bots' log (v72)

The author's notebook note (a video: bots stood by while a hole was behind an emergency shutter, and mended only after he
raised it by hand): "bots don't open up the door ... 1) tell in chat that one of the bots is taking the work, 2) priority of
the job: repairs always first, 3) logs of what bots are doing, not deleted like normal chat". Questions page "Spacer v72
Questions".

- **Shutters on the way to a repair**: a bot's way never goes through an emergency shutter that is down, unless the job is
  a repair, the bot wears a suit with oxygen, and there is **no other way**. Then it holds "use" on the shutter (**3 s**,
  as a player does), it stays up **5 s**, and the bot walks through. Some air escapes, as when a player does it. A bot
  without a suit fetches one from the locker first if there is one; if not, it says it cannot get there.
- **Shut in with no air**: a suited bot standing in a room with no air whose shutters are down raises one to get out to
  any work (its log says «поднимает аварийный шлюз, чтобы пройти: наружу из отсека без воздуха»). Air flows into the empty
  room, never out of a good one into a bad one.
- **Work with no way to it**: a bot on «Работы» that finds no way to a tray, the engine, a mount or a breech puts that kind
  of work off for **10 s** and does the next work meanwhile (it used to stand still waiting).
- **Repairs first**: a bot on «Работы» mends before anything else (before the gun it carries, unless that gun fills its
  last free hand; before rounds, trays and fuel). A **free** bot also comes to mend when something is broken that no
  other bot has taken, and goes back to wandering when it is done. Bots at a post stay there.
- **One bot per job**: each hole, broken machine or door gone wrong is taken by one bot; the others take other jobs.
- **In chat**: a bot that takes a repair says so to everybody: «Бот 7: беру пробоину (нижняя палуба, рядом двигатель).»;
  a bot on «Работы» that cannot get to one says «не могу добраться: ...» with the reason; when the reason is a missing
  suit and another mending bot wears one, it adds «Передаю работу: Бот N.», and that bot takes the job (the author's
  comment on L1). Nothing else goes to chat.
- **The bots' log**: the crew window (**O**) has «Журнал ботов» below the rows of bots: every order a bot got, every job
  it set about (locker and what for, mount, oxygen, autodoc, trays, fuel, loading, repairs taken and done, shutters raised,
  "cannot get there"), with the game time, kept for the whole game (the newest **2000** lines in the window). The same
  lines go to the file **crew_log.txt** next to the game (or in the game's user folder when run from the project); a new
  game adds a header line, and the file starts afresh past **4 MB**.
- **The boarders' wreck**: see "Ship weapons": a boarding ship we wreck before it docks stays as a wreck to dock with and
  search, with survivors rolled as for a raider (**70%** all dead, else they fight or join).

## 31. A friendlier game (v73)

The author's request: "polish the game ... very friendly UI for everything so it's very easy to interact with", and his
answers on the page "Spacer v73 Friendly Game" (24 questions). Art (items drawn in hands, the sprites folder), diagonal
walking and the first-shift checklist are the next build.

- **Fixes.** The airlock pump takes a chamber at a docked ship's pressure back to ours (see "Two-door airlock"). «Ещё один
  охотник поджидает…» is said once per hunter: a wreck left alongside no longer counts as a fight (it restarted the hunter's
  breather every second, and the line came every second).
- **The thing E acts on** is outlined (the same thin outline as under the mouse) while the mouse is on nothing usable.
- **A ring** fills over the thing while "use" is held on it (mending, forcing, pouring, cutting...); the old bar stays for
  work with the thing in hand (bandaging).
- **Names under the mouse**: a small label beside the pointer names what is there: a person (bot, pirate, our robot,
  unconscious, dead), the machine on the wall (and «не работает»), a door and its state (open, shut, its shutter down, a
  lock, jammed, welded, blast-locked), a hole, what lies on the floor; then «ЛКМ: использовать    ПКМ: действия» or only
  «ПКМ: действия» when it is out of reach. People and floor things are named only where we can see.
- **Right-click menu**: «Использовать» (as E or a click), «Работать, пока не готово» (holds E until the job is done, a
  move key is pressed or 30 s pass), «Шагнуть и использовать» (diagonally next to us), «Тащить» (somebody lying next to
  us), «Отпустить», «Осмотреть» (the label into the chat), and on a bot of ours every order (the crew window's posts) with
  a tick at its present one.
- **Diagonal use**: a click on a usable thing diagonally next to us takes one step to the side (a free floor cell, not a
  door) and then uses it.
- **Hints** at the bottom draw keys as badges: «Держите E, чтобы починить» shows as [держать E] починить, «E: …» as [E] …,
  «E или щелчок: …» as [E / ЛКМ] … (with the keys as set).
- **HUD labels**: pointing at the heart monitor shows health («Здоровье: 80 из 100»), at the oxygen bar the tank's %, at
  each lamp what it means.
- **Hotbar**: number keys in the corner of slots 1–6; pointing at a slot names its thing; a thing dragged onto another slot
  trades places with it (also in the inventory window), dragged off the bar it is put on the floor.
- **Chat**: with the chat open (Enter) it shows up to **18** lines and tabs: «Всё», «Корабль» (the ship's lines and
  warnings), «Рация» (radio and intercom), «Боты» (the bots' log). A line said again within **60 s** joins the last one as
  «×N».
- **Danger banners**: a breach, boarders (cut in, teleported, an assault drone in), a bomb, an enemy ship attacking,
  forced docking, a hunter coming, the flagship coming or boarding, the crew down: a red banner at the top for **4 s**
  with a chime (heard only in air), as well as the chat line. The client adds its own when the hull falls below **30%**
  (again after it is mended past 50%).
- **Interface size**: in the settings («Изображение»), 75–150% in steps of 5; the text grows with it.
- **Zoom**: Ctrl + wheel, one whole step closer or farther (the wheel alone still turns through the slots).
- **Consoles**: every console's frame has an ✕ in the corner (as Esc and E). Keys: at the gun console **1–9** fire that gun
  and **Space** fires all that are ready; at the sector console and the ship's controls **1–9** press that jump button (the
  buttons are numbered); at the supply locker **1–9** pick a tab.
- **Alert panel**: the sector console and the ship's controls show «Состояние корабля» on top: one line per need,
  red/yellow/green, worst first: hull (red below 35%, yellow below 70%), holes, no power, broken machines (red for the
  engine or the helm), fuel (red below one jump, yellow below three), the air reserve (red below 15%, yellow below 40%),
  food (red at none, yellow below two jumps for everyone), the main SMES below 15%, an empty crew reserve; «Всё в порядке»
  in green when nothing is wrong.

## 32. Art and walking (v74)

The author's answers N2–N7 and L1 on the page "Spacer v73 Friendly Game", his second-opinion answers, and his notebook.

- **Walking on a slant.** Up or down held together with left or right walks diagonally. A slant step takes **1.4 times** a
  straight one: 5 or 6 ticks in turn (5.6 on average) against 4, and 11 or 12 against 8 when going slowly. A slant step
  needs the cell it goes to and both cells beside the corner free: no cutting past a wall's corner. Doorways are never
  crossed on a slant (a door is entered and left straight). Held against a wall or a doorway, the slant slides along it
  (across first, then up or down). Somebody dragging a body walks straight. Ladders change decks as before. (v77) Bots,
  pirates and our security robots walk on a slant too (section 34).
- **Eight ways to face.** Characters are drawn facing 8 ways (the slants lean the figure). Sight, the flashlight's cone and
  turning by mouse click use all 8. E while facing a slant uses the console or machine right beside (on the wall next to
  us), or the floor cell on the slant (a thing lying there); never a door on a slant.
- **Things in hands.** The thing a person holds is drawn in their hand (its small picture), behind them when they face away.
  Everyone sees what everyone holds (the server tells it with the look).
- **The «sprites» folder.** Next to the game, like «sounds»: a PNG of the right name there is used instead of the game's own
  picture. Sheets (`chars.png`, `tiles.png`, `breach.png`, `hud_monitor.png`, `hud_alerts.png`) must keep their size; the
  originals are in `sprites/original/`. A thing's picture `item_<number>.png` may be any square size and is drawn in the
  slot, on the floor and in the hand. `sprites/README.txt` lists all **177** names.
- **The first shift.** A short list in the top left corner: walk (6 steps), turn on the oxygen (Q), open the supply locker,
  take another thing in hand, open the help book, stand at the ship's controls, pour a fuel can into the engine, jump.
  Lines tick themselves; what is done is kept between games, and the list goes **4 s** after the last line. ✕ hides it for
  good; the settings bring it back.
- **The help book (H).** Pages: Управление (every key as set), Машины (23 machines with their pictures and what E does
  there), Вещи (every thing in the game with its picture and use), Опасности (8 dangers), Путь (the goal and the road).
  The character can walk with it open; H, Esc or ✕ close it.
- **Bots (his notebook).** A bot says «беру …» once per job in **30 s**, and keeps its job while it fetches the patch or
  part (others no longer take it from it). A bot whose post's console is broken mends it first, then takes its post.
- **The helm's chart** marks a ship alongside next to our dot: «пираты», «обломки пиратов» or «корабль рядом».
- **Work bar.** The bar at the bottom shows only for work with the thing in hand; work on a thing shows the ring alone, and
  the bar no longer stays up after letting go.

## 33. Polish (v75)

The author's 20 answers on the page "Spacer v75 Polish" (every one the recommended pick) and five notes from his notebook.

- **The brig.** Four cells on the upper deck below the armoury, each with its own door. A prisoner left in a cell or in the
  armoury never slips his cuffs. Anywhere else he slips them after **2 min**, but only while he is **awake**, above **half**
  health (50) and with **none of ours in his room**; the clock starts again whenever any of that is not so. Prisoners need no
  food. The cells are marked with bars on the holomap («гауптвахта»), named under the mouse («Камера гауптвахты: здесь
  пленный не освободится», «Дверь камеры»), and the cuffing message says to take him there.
- **Bots.**
  - A gunner at a mount whose gun is broken mends it first (if no other bot took that job), then stands at its gun.
  - A bot that has nothing to do where the air is thinner than **half**, or whose suit tank runs low, walks to the nearest
    place with air («здесь нет воздуха, уходит туда, где он есть»).
  - A bot on its way that reaches no new cell for **20 s** is stuck: it leaves that goal and that job alone for **60 s**,
    writes «застрял по дороге (…): ищу другой путь или другое дело.» in the bots' log and looks for other work. Forcing
    the same shutter up **more than twice in 60 s** counts as stuck too, and the forcing is said in the chat only the first
    time.
  - Two bots do not crowd one doorway: while one forces a shutter or presses an airlock button, another bot waits.
  - Only a breach («беру пробоину») is said in everybody's chat («Всё»); every other job goes to the bots' tab and log.
  - (v77) Bots walk on a slant too (section 34).
- **Hits.** A hurt figure flashes red for **0.25 s**, drops of blood stay on the floor (a robot throws sparks) (the newest **400**
  are kept), and a wet hit sound plays (a metal one for robots). Seen within **24** cells on the same deck.
- **Broken machines** spark and flicker.
- **Red alert** tints the light of a lit ship red, softly pulsing; the old red pulse at the screen's edge is gone. Yellow and
  green change nothing.
- **Music.** Menu music (a slow pad, 16 s loop) and a drone in a fight (also at red alert, and for **20 s** after a pirate is
  seen aboard), crossfading over **2.5 s**. Made in code; `sounds/music_menu.ogg` and `sounds/music_fight.ogg` replace them.
  Its own volume slider («Музыка», **60%** at first).
- **Ship sounds.** Aboard, now and then (every **7–16 s**): a vent's hiss or a pipe's knock nearby; a hull creak **1.8 s**
  after a jump. All can be replaced from «sounds».
- **The end of a run** (lost or won) shows its story: pirate ships beaten, boarders killed, credits earned, and every one of
  ours who died, with how («погиб от ран», «задохнулся», «умер от голода»).
- **Hosting.** The host's chat says the address to give friends (a Radmin VPN 26.x address first). The pause menu (Esc)
  shows it with a copy button and lists who is in the game.
- **Rejoining** by the same name at any time takes back the same character (as before: kept by name).
- **A quiet start.** On easy and normal, the eventer sends nothing and no pirate hunter comes for the first **5 minutes**
  of a campaign. Hard is never quiet.
- **Bug report.** «Сообщить об ошибке» in the main menu, and a button in the pause menu, put the latest logs, the save,
  the settings, the bots' log and a screenshot into one zip in a «bug_reports» folder next to the game, and open the
  folder.

## 34. The evening's bugs, the view and bots on a slant (v77)

The author's answers on the page "Spacer v77 Movement and View" and his seven notes from an evening of play with KaineQwQ.

- **The view follows the mouse** (V1–V4): section 12. A setting, on at first; half a turn in **1/3 s**; walking backwards
  at full speed; others see the turn (8 ways).
- **Bots, pirates and our security robots walk on a slant** (B1): their way is worked out in 8 ways, a slant counting
  **1.4** straight steps (it takes that long), so they never zigzag where straight is as short. A slant is taken only where
  a player could take it: no corner cut, no doorway crossed on a slant. A bot wandering about may step on a slant too.
- **Fixes from the evening:**
  - A trader never sells what it looks for (section 26): no endless money.
  - A wreck left behind while the jump drive charged came straight back, 20 times a second, filling the chat; now it comes
    back only if the jump is called off. Its name in «Рядом …» is said whole (it was cut after its first letter).
  - Rejoining after a lag drop takes the same character back at once (section 23).
  - The dead ship that "did not load" after the rejoin: the player who dropped on it no longer counted as outside, so the
    ship could jump and leave the wreck behind; he then came back afloat in space. Now he comes back aboard.
  - The chat: long lines that wrap no longer push the newest under the input line (the oldest go until the rest fit).
  - The gas cloud and the other places: the bridge says what each takes (section 19).
  - SOS, "the crew died": a real dead ship comes alongside (section 25).
- Left for **v78** (the author's M1 D and C1 B): quarter-tile steps for players, lying down, swapping places with a friend,
  and shots that pass a friend standing right by the shooter (as in RimWorld).

## 35. The full run's fixes (v80)

The author and friends played a whole campaign on v79 and left eleven bug notes and four suggestions. His answers are on
the page "Spacer v80 Playthrough" (https://claude.ai/artifact/3A2HTzKTNpPbgQTuyAFFvc).

- **No hole on a machine**: a breach never opens on a wall cell with a machine, console or gun mount in it (one on the
  supply locker could not be patched: E opened the locker).
- **Shooting in open space**: bullets and pellets fly on through space (they stopped at its first cell); a flashbang can
  land there.
- **Mounted guns**: a bot takes a gun down or puts one up only when the gun console ordered it (G1 "A"). After mending a
  mount, let go of E before a new hold takes its gun down.
- **A ship alongside stays behind** (W1 "A"): a wreck, derelict or SOS ship stays at its mark as soon as our ship gets
  under way; stop near the mark and it comes alongside again.
- **Somebody outside** (P1 "A"): the ship waits for anybody of ours alive outside, out cold too, and the helm says who:
  «Не все на борту: <имя> снаружи корабля без сознания: заберите его на борт». The dead never hold it. A ship already
  flying in the system **stops** when one of ours goes outside.
- **Shots over the fallen** (S1 "A"): a bullet hits the first living person along its line; bodies never stop it.
  Somebody out cold on the floor is now passed over like somebody lying low, unless the shot is aimed at them.
- **The worn suit's gauge** (O1 "A"): the hotbar and the inventory show the air really left in the suit you wear (it was
  always drawn full; the air itself was right).
- **Blood** stays only on floors (never in open space), and blood on a ship alongside goes with it.
- **The flagship's mark** on the cluster chart sits above its system, so the system stays visible.
- Emergency light, lying across, the shotgun, choosing what to take and bodies kept: sections 7, 1, 28 and 16.

## 36. The ship editor, asteroids, holding position (v81)

The author's answers on "Spacer v81 Ship editor" (https://claude.ai/artifact/68oyd5cH9wyAsoT5Gcwfww), all "A".

### The ship editor

- **«Редактор кораблей»** in the main menu. The ship is drawn in the game's own look (the same tiles; doors drawn
  shut, the deck above faint, the deck below seen through glass and catwalks).
- **Tools**: brush (B), line (L), rectangle (R, filled or as walls), **room** (M: walls round a floor in one drag), fill
  (F), eraser (E; the right mouse button erases with any tool), picker (I, or Alt+click), **selection** (S: drag it to
  move, Ctrl+C / Ctrl+X / Ctrl+V, Delete, Ctrl+A; a pasted copy follows the mouse, a click lays it, Esc cancels, spaces in
  it do not erase), **room marks** (K: lock a room by access, a brig cell, a pirate ship's system).
- **Mirror** left-right (X) and up-down (Y) around the ship's middle: one stroke draws both halves; wide windows flip.
- **Undo / redo**: Ctrl+Z, Ctrl+Y (or Ctrl+Shift+Z), 200 steps.
- **Palette**: every sign with its picture and Russian name, in **7 categories** (walls and floor, doors and windows,
  consoles, machines, guns and defence, medicine and living, asteroid) with a **search** box; the last 9 signs used are on keys **1–9**.
- **Decks**: tabs, add, remove (pressed twice), move, rename; Page Up / Page Down.
- **Kind**: our ship, pirate, derelict or **asteroid** (rock «R», ore vein «O», ground «,»).
- **Size**: up to 96×96 per deck, grown or cut from any side.
- **Problems panel**, checked live: red = the game cannot load it (a door in a wrong wall, a wall end without a corner,
  a machine not in a wall, a room one tile tall, no spawn place...); yellow = it loads but misses something (no
  helm, no airlock pump, no SMES, no supply locker, other ships could not come alongside...). A click on a problem
  shows its place.
- **Saving**: Ctrl+S, into the **«ships»** folder next to the game (`ships/NAME.txt`, the same text format the game's own
  ships use); the editor also saves itself every **60 s**. «Открыть…» opens your ships and copies of the game's.
- **«▶ Попробовать»** (F5, only without red problems): plays the drawing at once, alone, with no events. Our ship: you
  stand in it. Pirate, derelict or asteroid: it comes alongside ship02 (docked if it has a door). Esc → «Выйти» brings
  you back to the editor.
- **«Обновить картинки»** rereads the «sprites» folder, so an artist sees new tiles without restarting. A tiles sheet
  from an older build (shorter) is laid over the game's, so the new v81 tiles still show.
- (v84) A game can be hosted on your own ship: see section 38.

- (v82.1, the author's note) **Layers**: every cell has a **floor layer** (space, wall, floor, glass, catwalk, rock)
  and an **object layer** on top (doors, windows, consoles, machines, guns, spawn places, ladders). An object keeps its
  floor: painting a floor under it keeps the object, the eraser takes the object first and shows the floor again, and
  a floor fill runs round objects. «Слой» (Q) picks what the tools change: both, only the floor or only objects (the
  eraser, fill, selection and Delete too). «Объекты видны» (O) hides the objects to show the floor alone. The saved
  file is unchanged (one sign per cell); on opening, the floor under an object is a wall, under a spawn place or a
  ladder floor.

### Holding position

- **X** (changeable in the settings): you **hold your position**, a living wall. Nobody, ours or pirates, can step into
  your tiles; bots and pirates find their way round. Your friends' shots fly past you, so a line can hold a door while
  others shoot through it. A light blue tint shows who holds.
- A step, lying down (C) or falling lets go; X again lets go too.

## 37. Polish without extra depth (v82)

The author's worry ("I'm afraid of making mechanics too deep, so the game loses a bit of fun"), his crawl video and bug
note, and the questions page "Spacer v82 Polish" (https://claude.ai/artifact/NTp7NAbinskUYCEhKwCZVi). No new systems.

- **Lying down and getting up, as in SS13** (his video): the body turns over in **0.2 s** (going down, getting up, and
  falling out cold too) instead of flipping. Getting up takes **1 s**: a small bar over the body fills from red to green,
  you can turn but not walk, and **C** again stays down. Lying down is at once. Bots hiding from pirates still get up at
  once.
- **The name stays its colour while lying low** (his bug note): only somebody out cold or dead has the red name.
- **The autodoc alone heals fully**: up to **50** health at its full pace (3 a second), then on at **half** that pace.
  Somebody holding E by it still makes it **2×** quicker (more with medicine skill) and mends injuries after 3 s. A bot in
  an autodoc gets up at 90 either way. (v70 to v81: alone it stopped at 50.) A **green cross** pulses over anyone lying
  in a working autodoc; over yourself a small bar of your health fills beside it.
- **What the crew used**: every run counts how often people (not bots) used 18 systems: the pilot's evade, the power
  panel, the overcharge, loading rounds by hand, alert levels, the galley, tending an autodoc, the body scanner, kits and
  splints, handcuffs, selling prisoners, welding doors, holding position, lying down, the drone, the workbench, answering
  calls, trading. The end screen lists what was used and what nobody touched; the campaign save keeps the counts over the
  evenings, and **usage.txt** next to the game (on the host's computer) is written at every save. The bug-report zip
  takes it too.
- **You hear your own actions**: your own shots, blows, the doors you open, things you put down and ladders used to be
  silent to you (only others heard them). Now they play for you too; your own footsteps are played by your game as before.
- **Hand guns**: an empty gun with no magazine **clicks** (range 4); putting in a new magazine is heard (**reload**, range 5);
  every shot drops a **spent casing** by the shooter (one for a shotgun's spread) that lies **30 s** and fades in its last 3;
  your own shot **kicks the camera back** 2.5 screen pixels (a shotgun 5), eased back at once, times the screen-shake
  setting. (v83, his video) The kick is now **4** pixels (shotgun 8) with a short **shake** of 1.6 pixels (shotgun 3.2),
  and it works while walking (before, a shot fired on the move was not known as yours). Every shot's trace starts
  where its shooter is drawn, not behind a walker.
- **Small sounds**: picking a thing up (range 4), a console's screen opening and closing, and a low buzz when a console
  will not open for lack of power. All can be replaced from the «sounds» folder (`click`, `reload`, `pickup`, `ui_open`,
  `ui_close`, `ui_deny`).
- **Work you hear**: while a job under your hands goes on (repairs, welding, the workbench, anything held with E) a soft
  tool tick sounds about **3 times a second**; a small knock when it is done; a flick when another thing comes into your
  hand (`ui_work`, `ui_done`, `ui_slot`). Only you hear these, and only in air.
- **A welded door shows its seam**: a row of weld beads where the leaves meet.
- **Getting hurt is felt**: a small camera shake when you are wounded (times the screen-shake setting), a short cry
  (`cry`, heard by those near), and red at the screen's edges once your health is below **75**, deeper and darker down to
  **15**, with a brighter flash at each blow.

## 38. Hosting on your own ship (v84)

The author's answers on the page "Spacer v84 Next" (https://claude.ai/artifact/RVoV4nte7rCpgf2AhH6TTb), all on my picks.

- **The main menu has two columns** so it fits a 720-row window: name, job and joining on the left; one's own game on the
  right.
- **«Корабль:»** (his H2) picks the ship of a **new** campaign: «Стандартный корабль» (ship02) or any drawing of our own
  ship in the «ships» folder (made in the ship editor). A small picture of the chosen ship shows its decks side by side
  (walls, floors, doors, machines). The choice is remembered.
- **A ship that cannot be played** (his H3) is marked «(не готов)» with the reason in red, and «Новая кампания» refuses it.
  Serious problems are the editor's red ones: a drawing that does not build, nowhere for the crew to appear, **no helm**
  («3») or **no engine** («6»). The rest (no shield, no guns, no cryopods...) only warn in the editor; such a ship plays
  without them. A server started on such a drawing by other means refuses it with the same words.
- **Friends need nothing** (his H1): when someone joins, the host's game sends the drawings it plays with (our ship and
  any of our own that come alongside), packed. The guest's own «ships» folder is not read or written. Before v84 a guest
  needed the same files.
- **A continued campaign keeps its ship** (his H4): the save holds its own copy of every drawing of ours it uses, so
  editing or deleting the file later changes nothing in that run. «Продолжить кампанию» always plays on the save's ship
  (the menu's ship is for new campaigns); the save's line in the menu names an own ship.
- **«Мои пираты, обломки и астероиды встречаются в пути»** (his H5, off at first): our own drawings of other kinds come in
  the run with the game's own. A **pirate ship** of ours becomes one more hull of every pirate class (not the drone ship's
  or the flagships'); it needs at least **6 rooms** (one per system) to be used. A **derelict** of ours shares the derelict
  places with the game's: which one a place has goes by the place, the same every visit. An **asteroid** of ours shares
  the asteroid places the same way. A drawing too big to lie off our ship's airlock is never met. The tick is greyed out
  when the folder has none that can be played.
- **A blow that meets nobody** (his bug note and S1): a baton or a fist used at a far tile drew its hit circle where the
  mouse was. Now a blow shows a short **white swing** in front of the one striking, toward the mouse; the circle (and the
  red of a hit) only on someone actually hit. A miss makes a soft **whoosh** (`swing`, range 4, replaceable from «sounds»).

## 39. Our fleet and the new character (v85)

The author's answers on the page "Spacer v85 Ships" (https://claude.ai/artifact/G35RhEtEWHhMGPeuhahtuK): all my picks,
with his words on the visor (C2) and the walking (C3).

### The fleet

- **«Второй корабль:»** on the main menu (his FS3), «нет» at first: the same list as «Корабль:» (the standard ship or a
  drawing of ours). With a second ship a new campaign starts as a **fleet of two** (FS2: two for now). A ship that cannot
  be played refuses here too.
- **Where they lie**: the second ship lies **below** the first in the same world, 4 rows of open space between them.
  People cross over in a spacesuit, out of one ship's airlock and into the other's, as to any ship alongside.
- **Each ship has its own** (FS1, FS7): hull, power (engine, SMES, power panel, backup), air plant, airlocks, vents,
  guns and shield, mounts and gunners, lockers, fuel tank, food and hydroponic trays, gear and module bay, breakdowns,
  alert level and battle position, helm, chart, comms, holomap and the rest. Consoles show the ship one stands in.
- **One purse** (FS7): credits are the fleet's; whatever is earned or spent on either ship is the same money.
- **Bots** (FS8): the menu's bot count is per ship. The first ship keeps one place for the host, as before; the second has
  a bot in that place too. A player who joins takes a bot's place **on their ship**; one who leaves is replaced there.
- **Joining**: next to «Подключиться» a list picks «любой корабль», «корабль 1» or «корабль 2». «Любой» goes where fewer
  players are (the first on a tie). A returning player comes back on the ship they were on.
- **Flying** (FS4): **either ship's helm** moves the whole fleet, and either ship's chart jumps it. The ships fly as one:
  the same system, place and course. **Each burns its own fuel**: a jump needs enough in **every** tank (the chart says
  which ship is short), and if one ship's tank runs dry while flying the fleet stops.
- **Pirates** (FS5): a pirate ship that comes picks one of ours to fight and board: the **weaker** (lower hull share)
  **70 %** of the time, otherwise either at random. Both ships' guns fire at it. If its target is lost it turns on the other.
- **Losing a ship** (FS6): a ship whose hull breaks while the other still stands is **lost**: it goes dark (no power at
  all, even from its SMES), takes no more hits, and drops out of the fight; the run goes on. Patching its hull from
  outside above 0 brings it back. **The run is over only when both are lost** (or the crew is, as before).
- **Saving** keeps both ships: each one's lockers, fuel, hull, guns and mounts, power panel and SMES, gear, food and
  breakdowns; every character is saved with the ship they belong to.
- Later (his FS1 note): enemy fleets, more pirate ships joining a fight. Ships of ours flying apart is the step after.

### The new character (his spriter's sheet; replaced by the base bodies in v87, see 41)

- **The crew is drawn from his sheet** (`sprites/crew.png`, 32×64 per picture; his C1: kept at full size, so people
  stand a bit taller than a tile). Five ways are drawn; the other three are mirrored.
- **The helmet** (his C2 B, "oxygen tank on and off"): **clear glass** while breathing the room's air, the **orange
  visor** down while on the oxygen tank (Q); for **0.3 s** after switching, the half-down picture shows.
- **Walking** (his C3): a small step made from the standing picture: the body bobs 1 pixel and one foot lifts 2 pixels,
  in turn. If his spriter draws step pictures (columns 3 to 6 of the sheet, see `sprites/README.txt`), they are used
  instead.
- **Job colours** (C4): the game repaints the **navy** parts of the suit in the job's colour; the white and orange stay.
- **Pirates** (C5) get the same body in their dark reds. Robots and heavy boarders keep their old pictures until he
  draws them.

## 40. The fleet's fixes, the pirates' wingman, the shuttle (v86)

The author's notes from playing the fleet and his answers on the page "Spacer v86 Fleet and Fire"
(https://claude.ai/artifact/N2RrzNRQjXg2h2Lxq3KZ8U). Fire waits (his FQ5 B: ships and pirate groups first).

### The fleet's fixes (his notes)

- **The holomap** shows only the ship it stands in (N2).
- **Bots work only aboard their own ship** (N4): they mend holes and doors and fetch supplies only there, and never try
  to cross to the other ship.
- **«Все по местам»** sends each ship's bots to **their own ship's** posts (N5). The crew window (O) lists the bots by
  ship, with a heading per ship and «(вы здесь)» on the one you stand in.
- **A pirate ship docked to one of our ships** can no longer be shot by that ship's guns (they cannot reach it), but the
  **other ship's guns still can** (N3); before, its gun console said «Целей нет».
- Pirates may now come alongside **the second ship** too (in v85 it had no room off its airlock).
- **On hard** pirates always go for the **weaker** ship (his N3 note: on high difficulty they focus one ship); on easy and
  normal it stays the weaker 70 % of the time.
- A fleet campaign saved in 0.78 does not load (the ships lie differently now): start a new one.

### The pirates' wingman (his E1 A)

- A fight with an ordinary pirate ship (not the flagship, not a drone ship) may get a **second pirate ship**: in
  **25 %** of fights on normal, **10 %** on easy, **40 %** on hard. It comes out of the dark **25 to 50 s** into the fight,
  with a red banner.
- It fights **at a distance**: guns, shield and hull of its own, rolled like any raider. It never docks, never boards and
  offers no ransom. It shoots the weaker ship of ours (on hard: the same ship as the first pirate).
- **The gun console** shows both enemies as two buttons at the top («У шлюза: hull» and «Второй: hull»); the one pressed
  is what this ship's guns shoot and aim at. Each ship of ours picks its own. The probe works only on the ship alongside.
- **Wrecked**, it pays its reward at once (shared like any salvage); its wreck drifts away, so there is nothing to search.
- **When the ship alongside is beaten or gone**, the wingman charges its jump and is gone in **12 s** unless it is
  wrecked first. **Jumping away** leaves it behind.

### The shuttle and the hangars (his N1 idea)

- **The hangar**: a room of each ship with a **force field** in its outer wall (`F` in a drawing): it holds the air in
  and lets light and sight through, no power needed, and it is never holed. The **dock console** (`V`) stands beside it.
  The standard ship has its hangar on the lower deck, over the room to the right of the shield generator.
- **The shuttle** waits outside one hangar's field. It works only in a fleet of two whose ships both have a hangar.
- At the dock console (**E**): «Сесть в челнок» when it is there (**4 seats**), or «Вызвать челнок сюда» when it waits
  empty at the other ship.
- **Aboard**, its screen shows «Лететь к кораблю N» and «Выйти» (E or Esc gets out while it stands). Nobody walks
  aboard; those inside are not seen and not hit. Any passenger can fly it.
- **The flight takes 10 s.** The passengers' view moves to the far hangar at once, so they watch the shuttle come in.
  There **everyone steps out**, each on a free cell of the hangar. There is no getting out in flight.
- Visitors stay crew of their own ship (they come back there from the reserve). **Bots never use the shuttle** (N4).
- The ship editor has both signs and warns when an own ship has no hangar.

## 41. Man and woman base bodies (v87)

The author's base sheet ("man and woman, just for now") and his two Notebook bugs; questions on the page "Spacer v87
Base Bodies" (https://claude.ai/artifact/QVjVrb4gyzMQF6hdfwPCPg), built on my picks.

### The bodies

- **People are drawn from his base sheet** (`sprites/body.png`, 128×96: four pictures of 32×48 across, front, right side,
  back, left side; the woman's row on top, the man's below). They are **48 pixels** tall again, as before v85.
- **Only four ways are drawn** (his words: no slant pictures for now). Walking or looking on a slant shows the **side**
  it leans to, as in SS13; the 8 ways of walking stay.
- **A man or a woman** (S1): on the main menu under the job, «Персонаж: Мужчина / Женщина» (kept with the other
  settings). Bots and pirates are men or women by lot (by their name).
- **Job colours** (S3): the navy top and shorts are repainted in the job's colour (pirates in their own); with no jumpsuit
  on they are grey.
- **The oxygen tank** (his S4 B, v87.1): nothing on the body shows it for now (the HUD still does); the helmet comes with
  the spriter's clothes later. (v87 drew a glass bubble.)
- **Walking** (his S7 B, v87.1): no step for now: the figure slides standing until the spriter draws step frames. (v87 kept
  the made bob and lifted foot.)
- Robots and heavy boarders keep their old pictures, in four ways too. The spriter's suited character (v85) was kept in the
  game files, unused (S6), until his own suits came in v88 (see 42).

### Two fleet bugs (his notes)

- **The second ship's guns never fired** (and sometimes ours did not): the two ships shared one set of gun charges by
  mistake, so one ship's shot emptied the other's guns too and its gunner bot never found a gun ready. Each ship now
  charges and fires its own guns. (The same mistake shared a few other per-ship lists; all are now each ship's own.)
- **After beating a pirate ship called from the admin panel, no other could be called**: the wreck stays off the airlock,
  and nothing comes while it is there. The admin's call for a pirate ship («Бой» or the events: pirate ship, raid,
  flagship) now lets the wreck drift off first, as a hunter does; it stays on the chart and can be searched later. In a
  normal game a wreck still keeps the next pirate ship away until the ship leaves (B1). If one of ours is on the wreck,
  the admin is told that no ship can come.

## 42. Suited man and woman (v88)

The author's two suit sheets ("full models for suited up"); questions on the page "Spacer v88 Suits"
(https://claude.ai/artifact/FMqARBDwoc4J2UUdpvwYr5), built on my picks.

- **Anyone in a space suit** (ours, bots, pirates) is drawn from his suited sheets, man or woman as their body; without a
  suit it is the base body of 41. Four ways, as the body: a slant shows the side.
- **The visor shows the oxygen tank**: clear glass while off the tank, the orange visor down while breathing from it, and
  for a moment (as the tank goes on or off) the visor half down. The back shows the helmet only. Without a suit nothing
  shows the tank (his S4 B).
- **Job colours** (U1): the navy parts of the suit take the job's colour (pirates their own); the white, the orange and the
  black stay.
- **His own sheets** go in the «sprites» folder as `suit_man.png` and `suit_woman.png`, 96×192 each: frames of 32×48, three
  across, four rows: the back (one frame), the front (glass, half, visor), the left side and the right side (visor, half,
  glass).
- The spriter's old suited sheet of v85 (`crew.png`) is no longer in the game (U4).
- (v88.1, his U2 B) **Pirates' visors glow red** (the orange of their helmet turned red), so they stand out from ours.
- (v88.1, his note) **The shadow follows the body**: a soft oval round the feet while standing, stretching along the whole
  body while lying (crawling, out cold or dead). Robots and heavy boarders keep the shadow of their old pictures.

## 43. The Notebook's 18 notes (v89)

All 18 open notes from his Notebook; questions on the page "Spacer v89 Notes"
(https://claude.ai/artifact/FryDUDpk8c5nbDpC3mJGqk), built on my picks.

### The pirates' teleport (his note: "a little nerf, 5 times; random spawn on the ship; a visual, text and sound alert")

- **5 times rarer**: a teleporting pirate ship sends a party every 225 s (was 45 s), the same size as before.
- **A warning first**: 5 s before they land, a red banner «Пираты заряжают телепорт: через 5 с высадка абордажников (N; ...,
  где мерцает)», a rising hum, and a flickering blue column of light on each spot where one will land (seen and heard
  through the dark and walls, within 30 cells of sound).
- **Spread over the ship**: each boarder lands in a different room of the ship being fought, picked by lot (never two in one
  room, so a small ship gets a smaller party), no longer all in one spot.
- **In suits**: teleported boarders always wear space suits (before, some came without one).
- If our guns knock the pirates' teleporter out during the 5 s, nobody lands («Телепорт пиратов выбит: высадки не будет»).
- **The heavy boarder («Штурмовик»)** is drawn in the new suit, painted dull steel with a red visor (it had the old picture).

### Power

- **What a power shortage switched off comes back on by itself.** When an ion storm's surge or a hit leaves too little power,
  the game switches off guns, the point defence and the shield to fit (as before), and says they will come back. Once a
  second it checks again, and switches them back on (the shield first, then the point defence, then the guns) as soon as
  there is power for each: «Энергии снова хватает: включено — ...». Something switched off by hand at the power panel
  stays off.

### Wrecks and bodies

- **A beaten ship no longer vanishes** when our people come back from it: it stays while our ship is within reach of where it
  was beaten (its chart mark may lie a little further off).
- **Bodies on a wreck stay with it**: dead pirates on their own ship were removed when it drifted off; now they stay aboard
  the wreck and are there again when it comes back.
- **Bodies floating in space are left behind on a jump**, as floating things are.
- **Survivors are told**: the «Пиратский корабль разбит» message now ends with the sensors' count: «Сенсоры: живых на
  обломках нет» or «на обломках живые пираты (N), они прячутся в отсеках подальше от шлюза». Boarding then goes as before
  (they fight or surrender).

### Bots

- **A bot climbs a ladder on its way** whatever stands in front of it. Before, a bot on a ladder with a broken door, a turret
  or a hole in front of it could not climb (the "use" key went to that thing) and stood there.
- **«К оружию»** (his note: "defenders of the ship, or only some of our crew fights back"): the crew window (O) has a
  «К оружию» toggle for each bot and two buttons, «Все к оружию» and «Оружие только охране»; the right-click menu on a bot
  has it too. A bot told so does what the guard does when armed pirates are about: takes a pistol or a shotgun (with two
  magazines) from the supply locker and fights them; with no gun to be had it hides like the others. Guard bots always
  fight. Without the order, bots still hide (v79).

### Fewer events (his numbers)

- **Meteors 3 times rarer**: a micrometeorite or a meteor volley the director picks comes only one time in three (the pace
  between picks stays, so the other times nothing happens).
- **Pirates 1.75 times rarer**: the same for a boarding, a boarding pirate ship and a raid (one time in 1.75).
- **Hunters 1.25 times fewer**: the first comes 375 s into a cluster (was 300), then one more every 300 s (was 240).

### The chart and the interface

- **Click a system to jump**: on the sector chart a click on a system a lane leads to (or on an exit's arrow) does what its
  jump button does, when that button can be pressed.
- **The gun sight is drawn by the game**: a light ring with four ticks and a dot, with a dark rim, the same on every PC (the
  system's thin black cross could vanish against space). `sprites/cursor_sight.png` replaces it (up to 128×128, the shot goes
  to its middle).
- **Things taken off a pile disappear one by one** (the outline under the mouse drew the old pile again on top).
- **Sounds are heard from where you stand**: at the edge of the map (the ship's nose) the camera stops short of the
  character, and sounds used to be heard from the middle of the screen, out of their reach.

