# Game mechanics

This describes everything already in the game: how it works and with what numbers. The document
grows with every build. What the game doesn't have yet is not written here: that is in
`docs/VISION.md` (the author's vision and plans).

Last updated: build v54 (version 0.47).

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

- **The engine powers the whole ship** (the author's word). When it shuts down, all systems
  stop working, but **don't break**:
  - the ship doesn't move or jump, a jump in progress is aborted;
  - consoles, air plant, oxygen racks, emergency shutters don't work;
  - doors open only by hand;
  - the lights go out (see "Light and darkness").
- The spacesuit, the player's instruments, ladders and repair don't depend on power.
- **Power failure** (event): power is lost for 8–15 s with the engine intact.

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
    (the last two are cargo: they can't be taken into the hands). Left click on a card takes one
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
  locker for **half** its price (things you carry must be put in the locker first).
  It sells all ordinary items, rockets (4) and EMP rockets (6), **4 of the 10** kinds of ship weapon (the same
  ones at the same trader every time) and, at about 1 trader in 3, the **shield hardening** (80).
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

- **Guns** come from the class's own list: cutter: laser, rapid, ion, blaster; raider: laser, rapid, blaster,
  ion, rockets, heavy; gunship: laser, heavy, rapid, blaster, rockets, ion, EMP; cruiser: heavy, laser, ion
  cannon, rockets, EMP, siege laser. The first gun is always the first of its list.
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
- Our **sensors** make out one more room every **7 s** while our ship has power.
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

### Ship weapons

Since v49 (the author's request) guns can be changed, the ship has a shield, and there are ten kinds of ship weapon; v50 added two more beams, the tractor and the siphon (the author chose them).

- The ship has **3 gun mounts** in the hull: in compartments near the nose on the port and starboard sides and under
  the belly. They are worked from the **gun console** on the bridge (E). The console and guns need power.
  The ship sets out with a **laser** on each.
- **Changing guns.** Each mount holds one weapon or none. On the console, "Сменить оружие…" under a gun puts on a
  weapon from the **cargo** (the supply locker); the one taken down goes into the cargo. "Снять в трюм" leaves the
  mount empty. A weapon just put on is unpowered and uncharged. Ship weapons and rockets are cargo: the locker
  shows them, but they can't be taken into the hands.
- **Reactor power: 8.** Every powered gun draws its power, the shield **2**. A gun is powered or cut with
  "Питание" on the console; one that doesn't fit in what is left won't power up. A cut gun loses its charge.
  The ship sets out with 3 lasers and the shield on: 5 of 8.
- A powered gun charges by itself (each weapon its own time) while the ship has power and the mount is whole.
  Buttons: fire one gun or a volley of all ready ones.

| Weapon | Charge | Shots | Hit | Damage | Power | Price | What else |
|---|---|---|---|---|---|---|---|
| Лазер (laser) | 8 s | 1 | 75% | 1 | 1 | 30 | |
| Тяжёлый лазер (heavy laser) | 14 s | 1 | 70% | 2 | 3 | 60 | takes 50 off a shield that stops it |
| Осадный лазер (siege laser) | 20 s | 1 | 65% | 3 | 4 | 90 | takes 75 off a shield |
| Скорострельный лазер (rapid laser) | 12 s | 6 | 35% each | 1 | 2 | 55 | |
| Резак (cutting beam) | 16 s | 4 pulses, 1 a second | never misses | 1 a pulse | 2 | 70 | burns the room aimed at; the aim may move while it burns; a shield at 50+ stops it, losing only 10 a pulse |
| Плазменный бластер (blaster) | 11 s | 4 pellets | 55% each | 1 | 2 | 55 | half the pellets ignore the shield |
| Ракетная установка (rocket launcher) | 10 s | 1 | 85% | 2 | 1 | 50 | ignores the shield (not a hardened one); holes the hull 50% of the time; spends a rocket (4 cr.) |
| ЭМИ-установка (EMP launcher) | 12 s | 1 | 85% | 0 | 1 | 60 | ignores the shield (not a hardened one); puts the system it hits out for **6 s**; spends an EMP rocket (6 cr.) |
| Ионная пушка (ion gun) | 7 s | 1 | 80% | 0 | 1 | 40 | takes 35 off a shield; through it, puts the system it hits out for **3 s** |
| Ионное орудие (ion cannon) | 13 s | 1 | 75% | 0 | 2 | 70 | takes 70 off a shield; through it, puts a system out for **3 s** |
| Захватный луч (tractor beam, v50) | 15 s | 1 | never misses | 0 | 2 | 60 | holds the enemy **8 s**: our shots hit **+25%** (up to 95%), its escape jump and its countdown to docking stand still; a shield at 50+ stops it (losing 10) |
| Сифон (siphon beam, v50) | 12 s | 4 pulses, 1 a second | never misses | 0 | 2 | 65 | each pulse takes **12** from the enemy's shield and adds it to ours (if our generator works, up to 100); no hull damage |

- **Shields** (the author's rule, not FTL's). A shield is a pool of **0–100** that refills **2.5 a second**.
  A shot that meets it at **50 or more** is stopped and takes **25 per point of its damage** away (ion: its own
  amount, the beam: 10). Below 50 a shot gets through with chance (50 − shield) / 50: at 25, half; at 0, all.
  Lasers and the beam always meet the shield; half the blaster's pellets slip past it; rockets and EMP pass it
  unless it is hardened; ion only wears it down, and what gets through puts a system out instead of doing damage.
- **Our shield generator** stands in the wall of the life-support compartment on the lower deck (the engineer's
  access). It needs power and can be switched off from the gun console (then it frees 2 power). Without power,
  broken, or switched off, the shield is at 0; put out by ion or EMP it stops protecting and refilling for that
  time. A broken generator is repaired like any machine.
- **Shield hardening**: a rare upgrade, offered by about **1 trader in 3** for **80** credits. With it the shield
  stops rockets and EMP rockets too, like lasers. Once bought, it stays.
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

## 18. Bridge and flight within a sector

- The bridge has two consoles (power needed):
  - **sector map** (green screen): neighbouring sectors and jumping. At the bottom of the map there is a legend:
    colour — what is in the sector; white ring — the ship is here; dark dot inside — already visited;
    small grey dot — unknown what's there; green line — route; white — the set jump;
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

- **Space is infinite.** Sectors are created as you approach; the same place is always
  the same. The map shows a 7×5 neighbourhood around the ship.
- Every sector has a route north or east (no dead ends) and, with probability
  0.3, one more in each direction; no more than 4.
- Sector kinds: calm space, meteor shower, trader, supply station,
  derelict ship.
  The share of meteor showers grows with distance from the start: from 20% to 45%.
- **Jump**: 8 s of preparation, then 15 s for the engine to recharge.
- **Fuel**: a jump burns **1** canister from the supply locker at the moment of the jump. Without fuel
  in the locker a jump can't be set; if the last canister is taken out while the jump is charging, it is aborted.
  The ship sets out with **8** canisters. Other sources: the trader (**6** credits), loot
  on derelict and pirate ships, the supply station (up to **3**), a wrecked pirate ship (**1**).
- If there isn't a single canister on board (in the locker, in pockets, on bodies or on the floor), after
  **2 minutes** the «Дрейфующее топливо» ("Drifting fuel") event comes: **2** canisters into the locker. So there's no dead end without
  fuel, but time passes.

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
| Pirate ship: boarding | large | calm space, trader, derelict ship |
| Pirate ship: fight | large | calm space, trader, derelict ship |
| Drifting fuel (2 canisters) | small | by itself, only when there is no fuel on board |

- Pace: once every 3–6 minutes in a calm sector and at a trader, once every 25–45 s in a meteor
  shower; no events at a station. More often with a large crew (up to 2.5 times).
- Breathers: 15 s after arriving in a sector, 8 s after entering or leaving a shower.
- The eventer watches the ship: it gives no new troubles while the whole crew is down or there are more breaches
  than people; with no patches on board breaches are three times rarer; unarmed crews are
  boarded half as often.

### Admin panel

- For the **host** (the player whose game created the server) and for players the host **made
  admins**. Admins are remembered by player name in the campaign save. Opens with **F2** or from the
  menu (Esc). The server checks every command; others' presses do nothing. You can walk while it is open.
- **Things** tab: every item, as new (a pistol loaded, a medkit full, a spacesuit's tank full), 1, 2,
  5 or 10 at a time. It goes into the hand, else a free slot, else the floor underfoot.
- **People** tab: for everyone aboard (bots and pirates too): heal (health 100, wounds closed, tank
  refilled; also raises the dead where they lie, but not bodies left after a return from the reserve),
  kill, go to them, bring them to me, change job (and access). «Heal everyone». The host also
  makes and unmakes admins here.
- **Ship** tab: mend everything (breaches, machines, doors, shutters, power), seal breaches, breach
  the hull near me, normal air in every cell and a full air plant store, fill the supply locker up to
  its starting stock, +100 credits, hull to 100, +1 in the reserve, save the campaign.
- **Space and events** tab: a station, a trader or a derelict in this sector with the ship put at
  it (until the next jump), a pirate with a pistol or a baton in front of me, the eventer on or off,
  and every event by hand.

## 21. Crew, jobs, reserve

- The **job** is chosen in the menu before joining. It gives access to compartments and a skill that
  grows fast.

| Job | Access | Own skill | Extra starting gear |
|---|---|---|---|
| Sailor | nowhere | — | — |
| Captain | everywhere (one per ship) | — | flashlight |
| Pilot | bridge | — | flashlight |
| Engineer | engine room, life support, gun compartments | repair | spare part |
| Doctor | medbay | medicine | plaster |
| Guard | armoury, gun compartments | shooting | baton |

- There is **one** captain per ship: if there already is one, the second applicant boards
  as a sailor and gets a message about it. Last evening's captain keeps the
  place until they return.
- Each member of the first crew arrives with a **radio**, a **patch** and a **spare part**, plus their
  job's item. Those who come from the reserve (by R or by rejoining after death) are dressed
  (spacesuit and jumpsuit), but **with no items**.
- **Skills**: repair, medicine, shooting, from 0 to 100. Your job's skill starts
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
  after 15 s and doesn't use the reserve.

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

- The **goal** is to hold out as long as possible. The top line (F1) shows the reserve and hull integrity.
- **Hull**: integrity **200** (100 until v49; an older save has its hull doubled). Each breach takes **5**, each
  pirate hit on a gun, console or the shield generator **3** per point of its damage. At **50** and below the ship warns you. It is patched at a trader
  and at a supply station (section 10).
- **End of campaign**: the hull reaches zero (the ship is destroyed) or the whole crew has died
  and nobody is in reserve. The game stops: no more jumps, the screen shows a summary — how many
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
| Enter | chat: aloud; «;» — radio, «!» — intercom at a panel |
| T | chat straight into the radio |
| F2 | admin panel (host and admins) |
| Esc | menu: settings, admin panel, saving (host) |
| F1 | ship status and key hints at the top of the screen (hidden by default since v47) |
| F3 | debug |
| F11 | full screen |

### Settings

- From the main menu and from the game's menu (Esc); kept in `user://options.cfg`, they take effect at once.
- **Sound**: overall volume, sounds on the ship, engine hum (each 0–100%), mute.
- **Picture**: full screen, vertical sync, frame limit (30, 60, 120, 144 or none), frame counter
  in the top left corner (shown even while F1's status is hidden), the white flash after a jump.
- **Controls**: every action above can have two keys. A key may be combined with Ctrl, Shift or
  Alt. A key given to one action is taken from the one that had it (the window says so).
  Backspace clears a key, Esc cancels, one button restores every default. A bare key still works
  with a modifier held, unless that exact combination belongs to another action. Hints on the
  screen name the keys as set.
