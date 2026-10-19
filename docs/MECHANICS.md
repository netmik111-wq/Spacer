# Game mechanics

This describes everything already in the game: how it works and with what numbers. The document
grows with every build. What the game doesn't have yet is not written here: that is in
`docs/VISION.md` (the author's vision and plans).

Last updated: build v65 (version 0.58).

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

---

## 1. Basics: server, ticks, network

- The server decides everything. The game runs in ticks: **20 ticks per second**.
- A character crosses a cell in **0.2 s** (5 cells per second). Someone dragging a body moves half as fast.
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
- An open outer door vents the air in its doorway into space.

### Open space

- From the airlock you can **go out into open space** and move around the ship. A step there takes twice
  as long (0.4 s), there is no air: you need the oxygen supply, the pressure lamps light as in a vacuum.
  In a vacuum it is silent.
- Bots and pirates don't go out into space.

## 4. Air and breaches

- Each cell has its own pressure (a single number, no gas composition).
- A hull **breach** vents air outside: a 10-cell compartment loses half its
  air in about 8 seconds.
- **Lack of air is not shown** on screen (the author's decision). You can only tell from
  the instruments: the O2 LOW and kPa lamps. Air streaks are visible only right at the breach.
- **Sealing a breach**: face it and hold E for 6 s; a **patch** is needed.
- A sealed compartment stays without air until you open a door to an intact one. Air lost to space
  is returned by the air plant and the supply station.

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
  until treated.
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
- **Ion storm** (v61, a kind of sector): see section 19.

## 8. Machines, breakdowns and repair

- **Engine** — lower deck, engine room, under the corridor glass. Its state is visible from the light on the
  floor: blue — working, flashing red — broken. Also visible from above, through the glass.
- **Air plant** — lower deck, under the corridor glass. Slowly adds
  air to its compartment, not above normal, and uses up the **ship's air reserve** (60 cells).
  When the reserve runs out, it stops.
- **Bridge consoles** break (short circuit): dark screen and sparks.
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
  **patch** and hold E: **+10** hull per patch, **10 s** (the repair skill cuts it to half), up to 200.
  A bot on «Работы» does it by itself when the hull is below **80%** with nothing to mend aboard and no
  fight: it takes up to 3 patches and a suit from the locker, fills its tank, pumps an airlock out, floats
  out, mends, comes back and pumps the chamber full. A pirate showing up calls it back.
- **Repair**: face the broken thing and hold E. With a **spare part** 6 s (the part is used up),
  without one 18 s. That is for a person without skill; the repair skill cuts the time by up to half
  (with skill 50 — 4.5 s, with skill 100 — 3 s; see section 21).

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
| Fuel | a canister for one jump | 8 | 6 |
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

## 10. Supply locker, trader, credits

- The **supply locker** is a yellow locker in a lower-deck wall. E opens the **ship's store** window
  (the locker doesn't need power):
  - across the top: credits, fuel canisters, air for the plant (bar), hull integrity (bar),
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
- The ship sets out with **30 credits** and a full air reserve for the plant.
- **Credits**: **15** for the first jump into each new sector (no other income yet).
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
  Services: air for the plant (10 cells for 5 credits), **hire a person into the crew reserve** (**30** credits,
  no more than 9 in reserve), **patch the hull** (+**20** integrity for **10** credits).
- **Supply station**: when docked, free of charge it restores air in the compartments and the plant's reserve,
  tops fuel up to **3** canisters and patches the hull completely.

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

## 16. Helping the fallen: searching and dragging

- A person lying down (unconscious or dead) in your cell or a neighbouring one can be:
  - **searched** (E): you see their slots and yours, a click moves an item there or back;
    you can see how badly they are wounded;
  - **dragged** (F): you move half as fast, they follow one cell behind you, including
    up and down ladders. F again — let go. The dragged person is always visible, even behind your back.
- Someone standing on their feet can't be searched or dragged.

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
  it leaves, taking with it the pirates and bodies remaining on it. The broken-open airlock then vents
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
  its order and what it is doing. Orders: **free** (wanders, as before), **controls**, **guns**, **engine**,
  **shields**, **repair**, **follow me**. «Все по местам» sends every bot to a post no player mans (controls, guns,
  shields, engine; the rest repair); «Отбой» frees them all.
- Orders come from the **captain**; while no captain is aboard, from anybody.
- Bots walk the ship by the shortest way (ladders included), never go out into space, and avoid rooms with
  under half the normal air. A **repair** bot goes to the nearest broken machine, jammed or faulty door, or hole
  (if a patch is to be had), taking a **spare part** or **patch** from the hold; it mends like a player.
  A **gun** bot fires every ready gun where the guns aim, but holds fire while a ransom is offered.

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
  a **can of fuel** into the hold. It stays alongside dead and dark, to be searched like a wreck.

- (v64) A pirate of its crew that walks across onto our ship while ours are aboard leaves its crew count but is not
  dead: the chat says it crossed over, and it fights on aboard our ship.

### Wrecked raider

- A raider our guns wreck (hull at 0, or its whole crew killed in its quarters) **stays alongside** as a
  dead hulk: no power, no light, doors open by hand. The ship is paid its class's **reward** (25–80 credits; no canister).
- It can be reached through open space or **docked with** from the ship-control console
  («Пристыковаться к разбитому кораблю»). Aboard: what it carried (2–4 things on the floor plus 1–3 more),
  and the bodies of its dead with their weapons.
- Who is aboard is settled when it is wrecked and found out when the first of our crew sets foot on it:
  - **70%**: nobody alive, only bodies (always so if its quarters were shot empty);
  - **15%**: its survivors **fight**: they come out armed from the far end of the wreck;
  - **15%**: its survivors **give up and join us**: each one becomes +1 to the crew reserve (up to 9).
- Bodies of crew killed by hits on its quarters lie aboard in every case.
- It stays until our ship moves (a course or a jump); while someone is on it or it is docked, the ship
  doesn't move, as with a derelict.

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
- **It grows with our gear**: for every mounted gun other than a plain laser it gets one more gun from its
  list (battleship: ion, laser, heavy laser; carrier: laser, neural, heavy laser), up to 3.
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
  ship, once wrecked, leaves with its crew, and the ship is credited its class's reward and **1** fuel canister;
  a raider stays as a wreck (see "Wrecked raider").
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
- **The flagship grows** by half our tier points: each mounted gun of tier 2 counts 1, of tier 3 counts 2;
  every 2 points add one more gun to it (spares in the cargo do not count).
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
- **Rare gun drops** (the author: a reward, not routine). A wrecked pirate ship leaves one of its guns in its wreck
  **30%** of the time; one taken by boarding always leaves one. Such a gun is one tier higher 10% of the time and
  **damaged** 40% of the time. A derelict hides a ship gun 25% of the time (damaged 60%). The flagship's wreck
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
  | Двигатель (engine) | – | «Стриж» 90 cr: dodge +5% (while someone flies), jump charges in ¾ the time, 1 jump in 4 burns no fuel | «Сокол» 180 cr: dodge +10%, jump in half the time, 1 jump in 2 burns no fuel |
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
- **The flagship grows** with our gear too: half our gear's tier points (each system of tier 2 counts 1, of tier 3
  counts 2; armour the same; the focusing array and the phase drive 1 each), each step giving it **+2 hull** and
  a **10%** quicker shield.
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
- **Jumps go only along lanes** and burn **1** canister. Any system of the current cluster can be visited again.
- **The long jump**: from an exit system, the sector console has «Долгий прыжок» (**2** canisters, a charge 1.5×
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
- **Exploring pays**: the first visit to a system pays **15** credits.
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
- **Fuel**: a jump burns **1** canister from the supply locker at the moment of the jump. Without fuel
  in the locker a jump can't be set; if the last canister is taken out while the jump is charging, it is aborted.
  The ship sets out with **8** canisters. Other sources: the trader (**6** credits), loot
  on derelict and pirate ships, the supply station (up to **3**), a wrecked pirate ship (**1**).
- If there isn't a single canister on board (in the locker, in pockets, on bodies or on the floor), after
  **2 minutes** help comes. (v63) Most often a ship calls on the comms console: a passing trader sells **2** cans for
  **20** credits, or leaves **1** for nothing if asked (also what happens when nobody answers), or kind people give
  **2**. Three times in ten it is still the «Дрейфующее топливо» ("Drifting fuel") event: **2** canisters into the
  locker. So there's no dead end without fuel, but time passes.

### Places inside a system (v64)

- Besides its main thing, a system may hold **places** (none at the first cluster's start, a station or the
  flagship): 0 (30%), 1 (40%), 2 (22%) or 3 (8%). The kind is shown before arrival only as the system's kind; the
  places themselves are **hidden until the sensors come within 35/50/70** (by their tier; 15 inside a nebula). Then the
  chat says so and they appear on the ship-control console. Fly onto one (within **6**) to take it, once.
- **Обломки** (debris, 30%): 1–2 spare parts and 5–15 credits of scrap.
- **Контейнер** (a dropped container, 25%): 2–3 things (patches, parts, medpatches, magazines, fuel, rations, shells,
  rockets, a probe) and, 30% of the time, a crate of ship gear of the place's tier. **One in five is a pirate mine**:
  **12** off the hull and a breach.
- **Тела** (bodies, 20%): one thing from their pockets and a note; **25%** of the time one of them still breathes:
  **+1 to the reserve**.
- **Брошенный корабль** (an abandoned ship, 10%): it comes alongside like a derelict when the ship is within **10**, to
  be searched (never in a derelict system: one alongside at a time).
- **Поле боя** (a battlefield, 8%; twice as often in the dead zone): debris twice, bodies, gun parts, and 30% of the
  time a damaged ship gun.
- **Засада пиратов** (a pirate ambush, 7%; three times as often in pirate territory, rare in trade worlds): **seen from
  anywhere in the system** and drawn with its circle. Coming within **25** brings its pirate ship out (a raid). It can
  be flown around.

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

### The chart (v64)

- The sector console has two views: **«Карта скопления»** (the cluster: systems, lanes, the set jump, exits with arrows
  and the kind of cluster each leads to, «?» for unknown systems, nebulae as grey clouds, hunters, the flagship, quest
  marks and SOS) and **«Карта пути»** (the road: the clusters passed, the one we are in, and how many to the flagship's).
  Its text says the cluster's kind and number, fuel, whether this is an exit, the hunters and the time to the next.
- The ship-control console shows the places found in the system (and the ambush's circle).

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
| Drifting fuel (2 canisters) | small | by itself, only when there is no fuel on board |
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
| Sailor | nowhere | — | — |
| Captain | everywhere (one per ship) | — | flashlight |
| Pilot | bridge | piloting (v60) | flashlight |
| Engineer | engine room, life support, gun compartments | repair | spare part |
| Doctor | medbay | medicine | plaster |
| Guard | armoury, gun compartments | shooting | baton |

- There is **one** captain per ship: if there already is one, the second applicant boards
  as a sailor and gets a message about it. Last evening's captain keeps the
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
  - Not saved: a derelict or pirate ship alongside, pirates on board, bots,
    the eventer's mood.
  - A lost campaign leaves no save.

## 24. Controls

| Key | Action |
|---|---|
| WASD, arrows | walk |
| E | action: console, locker, holomap, drone monitor, ladder, repair, search, pick up item, hack lock, intercom |
| F | drag a person lying down / let go |
| Q | oxygen supply |
| 1–6, mouse wheel | what's in hand |
| Z | use the item in hand (flashlight) |
| G | drop the item on the floor |
| Mouse click | on something within reach: as E (pick up, console, machine, repair while held); elsewhere: shot, blow, healing |
| R | return after death (takes one from the reserve) |
| Mouse over | (v53) something usable you can see gets an outline, as in SS13: bright yellow within reach, faint grey farther off; since v54 it hugs the thing itself (a machine on a wall, things on the floor, a body), a door, hole or ladder keeps its cell's square |
| I, Tab | inventory window |
| O | (v55) crew window: posts, battle position, orders to bots |
| Enter | chat: aloud; «;» — radio, «!» — intercom at a panel |
| T | chat straight into the radio |
| F2 | admin panel (host and admins) |
| Esc | menu: settings, admin panel, saving (host) |
| F1 | ship status and key hints at the top of the screen (hidden by default since v47) |
| F3 | debug |
| F11 | full screen |

### Settings

- From the main menu and from the game's menu (Esc); kept in `user://options.cfg`, they take effect at once.
- **Sound**: overall volume, sounds on the ship, engine hum, footsteps (v56, 50% by default), the ship
  fight (v56) (each 0–100%), mute.
- **Picture**: full screen, vertical sync, frame limit (30, 60, 120, 144 or none), frame counter
  in the top left corner (shown even while F1's status is hidden), the white flash after a jump,
  the screen shaking when the hull is hit (v56, 0–100%).
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
  its call: help (**40%** survivors: 2 to the reserve and 3 rations; **30%** salvage: 3 parts and 15 credits; **30%** a
  pirate trap), the guard's blue answer (no trap: survivors, or the pirates reported for 25 credits), or leave.

### Food and hunger

- **Rations** («Паёк») are kept in the supply locker; the ship starts with **16**; traders sell them (**3** credits).
- Every **jump** the crew eat **one ration for every two** of them (players and bots alive; the reserve sleeps and eats
  nothing). The chat warns when two jumps' worth or less are left.
- With nothing to eat at a jump the crew **starve**: everybody's health sinks by **0.1 a second**, down to **30** and
  never lower: nobody dies of hunger. Food in the locker again: the hunger passes (1 health a second back).
  Hunger never holds health below **30** on top of wounds, so someone knocked out while starving still comes round
  (only wounds of **90** and more need the autodoc).
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
