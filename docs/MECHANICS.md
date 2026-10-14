# Game mechanics

This describes everything already in the game: how it works and with what numbers. The document
grows with every build. What the game doesn't have yet is not written here: that is in
`docs/VISION.md` (the author's vision and plans).

Last updated: build v39 (version 0.32).

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
- **Left-clicking** the world turns the character towards the click (in place, without a step),
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
  - the ship is in **pitch darkness** (see "Light and darkness").
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
- **Repair**: face the broken thing and hold E. With a **spare part** 6 s (the part is used up),
  without one 18 s. That is for a person without skill; the repair skill cuts the time by up to half
  (with skill 50 — 4.5 s, with skill 100 — 3 s; see section 21).

## 9. Items and inventory

- Everyone has **6 slots**, plus **2 pockets** with a jumpsuit and **4 places** with a backpack; one item
  per slot. A dead person's items stay on the body.
- **Hand**: one slot is highlighted, that is what's in hand. Choose with: 1–6, mouse wheel, clicking
  a slot. A picked-up item goes into the hand if it is empty.
- **G** — drop the item in hand on the floor at your feet. Up to **4** items per cell.
- **E** — pick up: first what's ahead, then what's underfoot. A wall with a console
  or locker ahead and a person lying down take priority (E goes to them).
- **Z** — use the item by itself (turn on the flashlight, put on clothing).
- **Clicking** the world — use the item at that spot (shot, blow, healing).
- All items:

| Item | Purpose | In locker | Price |
|---|---|---|---|
| Patch | seal a breach | 8 | 5 |
| Radio | talk with «;» — everyone with a radio hears | 4 | 6 |
| Fuel | a canister for one jump | 8 | 6 |
| Spare part | repair three times faster | 5 | 10 |
| Flashlight | 35° beam, 9 cells | 4 | 8 |
| Pistol | 8 rounds, damage 30 | 1 (empty) | 25 |
| Magazine | 8 rounds | 2 | 6 |
| Baton | damage 15 to a neighbour | 1 | 8 |
| Plaster | closes 40 wounds at once | 2 | 6 |
| Medkit | 5 uses of 30 wounds, 3 s | 2 | 15 |
| Spacesuit | helmet and oxygen tank | 2 (full) | 40 |
| Jumpsuit | 2 pockets | 2 | 8 |
| Backpack | 4 places | 2 | 15 |

## 10. Supply locker, trader, credits

- The **supply locker** is a yellow locker in a lower-deck wall. E opens a panel: the ship's
  supplies, take an item, put everything back. The locker doesn't need power.
- Only whole items go back: a used medkit can't be swapped for a new one, a loaded
  pistol goes back empty, a spacesuit only with a full tank.
- The ship sets out with **30 credits** and a full air reserve for the plant.
- **Credits**: **15** for the first jump into each new sector (no other income yet).
- **Trader**: fly the ship up to it; purchases are made at the locker, power is needed.
  Sells all items in the table and air for the plant (10 cells for 5 credits).
  Also there: **hire a person into the crew reserve** (**30** credits, no more than 9 in reserve) and
  **patch the hull** (+**10** integrity for **6** credits).
- **Supply station**: when docked, free of charge it restores air in the compartments and the plant's reserve,
  tops fuel up to **3** canisters and patches the hull completely.

## 11. Light and darkness

- A **flashlight** in hand shines a smooth **35°** cone for **9 cells**. The beam starts at the chest,
  right away as wide as the body. Walls and closed doors stop it; windows and open doors
  let it through. Someone else's beam is visible from afar, but only where you are looking: outside the field of view
  flashlight light is not visible.
- **Without power** the ship is in **pitch darkness**: only the flashlight (and a muzzle flash) gives light,
  nothing around you is visible (the author's request, build v27). Space outside doesn't darken.
- **Starlight**: the outer hull of any ship (walls and doors facing open
  space) is always slightly lit, even on a derelict ship and on ours without power.
  Anyone who goes out into space sees the hulls around them; inside a dark ship it is still dark.
- **Next to you** walls are always visible (the 8 cells around you, even behind your back and in the dark), and so are
  you yourself. The floor around you stays dark in the dark.
- A muzzle flash briefly lights up its spot in the dark.

## 12. Field of view

- A character sees **only forward**: two eyes of **85°** each, **160°** together, overlapping
  in the middle (later, losing an eye will remove its part of the cone).
- In the dark the cone narrows to **60°**; without light you see only where the flashlight shines
  (someone right next to you, within 2 cells, you still notice: their name is visible).
- Walls and closed doors block the view. What's outside your gaze is darkened: walls and floor
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
- Your own footsteps are always audible; in a vacuum they are dull, through the suit.
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

- **Plaster**: click yourself or a neighbour, it closes **40** wounds at once.
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

- The **«Пиратский корабль»** ("Pirate ship") event (large; not in a meteor shower and not at a station; doesn't happen
  while another ship is at the airlock, there are pirates on board or someone is outside).
- A ship in brown, red and black colours takes position above the airlock, 3 cells of space away, and
  **opens fire** (see "Ship weapons"). After **40 s** it **docks by force** (waits if someone is between the ships), **breaks open both
  airlock doors** (they jam open; repair like a jammed door) and lands
  pirates: as many as in a boarding (1 + half the crew, no more than 4).
- Their ship has light, air and power; on the floor 2–4 items: magazines, plasters, patches,
  a pistol, a baton.
- You can't dock with it of your own will. You can undock from the ship-control console: then
  it leaves, taking with it the pirates and bodies remaining on it. The broken-open airlock then vents
  air into space until the doors are repaired.

### Ship weapons

- The ship has **3 guns** in the hull: in compartments near the nose on the port and starboard sides and under the belly.
  They are fired from the **gun console** on the bridge (E). The console and guns need power.
- A gun recharges by itself: **8 s** after a shot. Buttons: fire one gun or a volley from all
  ready ones. Hit chance **75%**.
- The only target is the pirate ship, until it docks. It withstands **6 hits**;
  once wrecked, it leaves with its crew, and the ship is credited **25 credits** and **1** fuel canister.
- The pirate ship fires once every **9–13 s**, hitting with 70% chance: in 60% of cases it
  breaches the hull, otherwise it disables a gun or a bridge console. A broken gun
  is repaired like machines (E, 6 s with a spare part).
- The hint at a gun shows its charge; the console shows the target, the enemy's hull and the time
  until it docks.

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
- It has **no power**: inside is pitch darkness, only the flashlight gives light,
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

- Runs events by itself or on the game host's command (menu on Esc).
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
| Pirate ship | large | calm space, trader, derelict ship |
| Drifting fuel (2 canisters) | small | by itself, only when there is no fuel on board |

- Pace: once every 3–6 minutes in a calm sector and at a trader, once every 25–45 s in a meteor
  shower; no events at a station. More often with a large crew (up to 2.5 times).
- Breathers: 15 s after arriving in a sector, 8 s after entering or leaving a shower.
- The eventer watches the ship: it gives no new troubles while the whole crew is down or there are more breaches
  than people; with no patches on board breaches are three times rarer; unarmed crews are
  boarded half as often.

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
  for every three. Skills are shown in the line under the top panel.
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

- The **goal** is to hold out as long as possible. The top line shows the reserve and hull integrity.
- **Hull**: integrity **100**. Each breach takes **5**, each pirate hit
  on a gun or console **3**. At **30** and below the ship warns you. It is patched at a trader
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
| E | action: console, locker, ladder, repair, search, pick up item, hack lock, intercom |
| F | drag a person lying down / let go |
| Q | oxygen supply |
| 1–6, mouse wheel | what's in hand |
| Z | use the item in hand (flashlight) |
| G | drop the item on the floor |
| Mouse click | shot, blow, healing |
| R | return after death (takes one from the reserve) |
| Enter | chat: aloud; «;» — radio, «!» — intercom at a panel |
| Esc | menu (for the host — eventer) |
| F3 | debug |
| F11 | full screen |
