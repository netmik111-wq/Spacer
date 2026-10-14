# Spacer

A 2D multiplayer game about the crew of a spaceship. Inspired by Space Station 13
(above all the FTL13 build) and FTL. At its core are space and its cruelty.

Made with Godot 4.7, in GDScript. The first five-step plan is done: a server and players
on one ship, doors, air per compartment and hull breaches, health and death from lack of air,
a space suit with a tank and breach repair, a bridge, sectors with jumps and the event director.
After the plan we added steering the ship within a sector, bridge console breakdowns,
a second deck with ladders, glass floors and catwalks, with an engine
and an air plant on it, ship power from the engine, emergency shutters at doors,
ship supplies spent on repairs and a trader, a slot inventory, searching
and dragging people who are down, and infinite space.

Where the game is heading next is written in [docs/VISION.md](docs/VISION.md).

## Plan

1. **Done.** Server and clients: characters walk around the ship and see each other.
2. **Done.** Compartments with air: doors, hull breach, leaks, pressure equalization.
3. **Done.** Environmental damage and health states, up to critical condition and death.
4. **Done.** A space suit with an oxygen supply and hull breach repair.
5. **Done.** A bridge with two consoles, sectors, jumps and an event director that breaks the ship on its own.

The second plan (engine and air plant, emergency shutters, new events, supplies
and a trader, inventory with searching and dragging, infinite space) is also done.

The author's third plan is now under way; all of it is written in `docs/VISION.md`:

1. **Done.** Items: what's in hand, drop and pick up, item properties, flashlight.
2. **Done.** Cone-shaped field of view and sound icons outside it.
3. **Done.** Weapons and pirate boarders.
4. **Done.** Healing.
5. A new, tidier ship with a two-door airlock.
6. Derelict ships. 7. Pirate ship. 8. Clothing. 9. Ship weapons.

## How to open

1. Download Godot 4.7 (the standard version, not .NET) from godotengine.org.
2. Download this repository: the green button «Code → Download ZIP», then unpack the archive.
3. In the Godot project manager press «Импорт» ("Import") and choose the `project.godot` file from this folder.
4. F5 runs the game. To open two windows at once: «Отладка → Настроить экземпляры запуска» ("Debug → Customize Run Instances").

## What is where

| Folder | Contents |
|---|---|
| `src/shared/` | Shared by server and client: movement rule, doors, map, network protocol |
| `src/server/` | Server: simulation at 20 ticks per second, air, health, sending changes, bots |
| `src/client/` | Client: talking to the server, predicting your own character, drawing the ship |
| `src/ui/` | Menu, game screen, chat, pause |
| `maps/` | Maps: `ship02.txt` (the game's ship), `ship01.txt` (the test ship) and `derelict01.txt` (derelict ship) are drawn with characters, the `.json` files are built from them |
| `assets/` | Finished graphics that the game reads |
| `art_src/` | Source art references |
| `tools/` | Building graphics and maps, network tests |
| `dist_files/` | Files placed next to the game in the Windows archive |
| `docs/` | The game's vision in the author's words (`VISION.md`) and a description of all mechanics (`MECHANICS.md`) |
| `research/` | Measurements of networking, threads and atmosphere that the technical decisions rest on |
| `CLAUDE.md` | Working notes: agreements, reasons for decisions, check procedure, pitfalls |

## How to change the map

Open `maps/ship02.txt`: the ship is drawn with characters (`#` wall, `.` floor, `s` spawn point,
`D` door in a horizontal wall, `A` door in a vertical wall, `W` and `<>` windows, `1`–`5` wall with a console,
`6` engine, `7` air plant, `8` supply locker, `9` airlock pump (a wall of the airlock chamber; the chamber's outer door `D` faces space), `g` glass floor, `c` catwalk, `H` ladder).
Decks are drawn one after another, the top one first; each starts with a line `= name`.
A ladder `H` goes in the same cell of two adjacent decks. There must be floor under catwalks.
The mockup tiles are designed for compartments two cells tall; the script checks this and picks wall joints itself.

    python3 tools/make_assets.py

You need Python 3 with the Pillow library. A preview image will appear in `tools/preview/`.

## Running from the command line

Parameters go after `--`:

    godot --path . -- --host bots=2 name=Капитан       create a game right away
    godot --path . -- join=192.168.0.10 name=Инженер   join right away
    godot --headless --path . -- --server port=24500   server only, no window

## How to build the game

The repository holds only the sources: the finished Windows game is over 100 MB,
and GitHub does not accept files that large in a repository.

In Godot: install the templates once («Редактор → Управление шаблонами экспорта», "Editor → Manage Export Templates"),
then «Проект → Экспорт» ("Project → Export"), choose «Windows Desktop» or «Linux» and press «Экспорт проекта» ("Export Project").

The same from the command line:

    mkdir -p build/windows build/linux
    godot --headless --path . --export-release "Windows Desktop" build/windows/SpacePrototype.exe
    godot --headless --path . --export-release "Linux" build/linux/SpacePrototype.x86_64

## Network check

`tools/nettest.sh` starts a server and several real windowless clients and counts
how many steps the server corrected and whether the state matched. `tools/lagproxy.rs` is a relay
that adds delay and packet loss, like the real internet
(built with `rustc -O tools/lagproxy.rs -o tools/lagproxy`).

    GODOT=/path/to/godot tools/nettest.sh 4 20                 4 clients, 20 seconds
    GODOT=... LAGPROXY=tools/lagproxy tools/nettest.sh 4 20 40 10 2   delay 40±10 ms, 2% loss
    GODOT=... LAGPROXY=tools/lagproxy tools/nettest.sh 4 20 80 15 0 200 1000   the link freezes for 200 ms once a second

## Air check

    godot --headless --path . --script res://tools/airtest.gd

Measures on the real map how fast a breached compartment empties, and checks that air
doesn't come from nowhere, doesn't pass through a closed door, and that everything settles.
Right now a 10-cell compartment loses half its air in 8 seconds and almost all of it in half a minute.
The same test measures how long a person left in a breached compartment survives.

## Ship: doors, air, hull

- **Doors** are closed. Whoever walks into a door opens it: after 0.3 seconds it is passable.
  It closes by itself 2 seconds after the last person passes, but not on someone standing in it.
- **Air** is stored in every cell you can stand on. 10 times a second it flows
  between neighbouring cells towards lower pressure. A closed door lets nothing through.
- A **hull breach** can happen in any cell of an outer wall or window. Cells next to it
  lose air into space.
- Bots don't open doors with a big pressure difference behind them, so as not to let
  the air out of the whole ship.
- A compartment without air looks no different from a normal one. The player sees only the pressure
  in their own cell; this is intentional: it should be hard.
- The event director breaks the ship; the host can breach and seal the hull themselves from the menu (Esc).

## Decks

- The ship has two decks, one above the other. The player sees the one they are standing on.
- A **ladder** is a hatch in the upper deck floor with a ladder under it. Stand on the cell and press E.
- **Glass floors** and **catwalks** (grating) are transparent: from above you can see the lower deck through them
  and everyone under them; from below you can see those standing on them. Through normal floor you see
  nothing, including names.
- **Air** flows between decks through catwalks and hatches, but not through glass. A breach
  under catwalks also lets out the air from the compartment above them.
- In the map file and over the network the decks lie in one grid one below another (`ShipMap`), so
  a cell is always given by two numbers.

## Machines

- The **engine** (lower deck, under the bridge) powers the whole ship. When it's broken, all
  systems stop, but none of them break. The ship stops, a started jump fails,
  the bridge consoles don't turn on, the air plant and oxygen racks don't work,
  emergency shutters don't trigger, doors open only by hand (1.5 seconds instead of
  0.3), the lights go out. The engine's light on the floor is visible from the bridge through the glass: blue or red.
- The **air plant** (lower corridor) adds air to the cell in front of it,
  0.12 cells per second, no higher than normal pressure, while the ship has an air supply.
- Both are repaired by holding E for six seconds. The event director breaks them: the events «Отказ двигателя» ("Engine failure")
  and «Отказ воздушной установки» ("Air plant failure").
- While a bridge console is broken, the engine does not break, and vice versa (`Systems.can_break`).

- Every door has an **emergency shutter**. It drops when the pressure on the two sides of the door
  differs by a quarter of normal, and rises when the difference is under a tenth. A dropped one
  keeps the door from opening and slams an open one shut if nobody is in the doorway. Two lamps
  show the pressure on each side; the hint at the bottom of the screen gives the difference in kilopascals.
  To raise it by hand: hold E for three seconds, the shutter rises for five seconds.
  Numbers in `src/shared/net.gd` (`SHUTTER_*`, `FORCE_TICKS`, `FORCED_OPEN_TICKS`).

- **A door can jam open** (`Doors.jammed`): it doesn't close, and the shutter won't close it.
  **A shutter can fail** (`Doors.faulty`): it stays as it is, dropped or raised, whatever
  the pressure does. Both are repaired by holding E for six seconds.
- A **power failure** cuts power to the ship for 8–15 seconds without breaking the engine.

Checking machines, power, doors and shutters without network or window:

    godot --headless --path . --script res://tools/machinetest.gd

## Items, inventory, searching, dragging

- Each character has six slots, one item per slot (`Net.SLOTS`, `Net.ITEM_*`).
  A dead character's items stay on the body.
- What each item is and what it can do is written in one table, `src/shared/items.gd`:
  name, description, trader price, how many are in the locker at the start, what it
  toggles into in hand, what light it gives. Both the server and the client read it. Item pictures
  are drawn by code in `src/client/item_art.gd`.
- There are three items: patch, spare part and flashlight.
- **Hand.** One of the slots is in hand; it is highlighted. Choose it with keys 1–6, the mouse wheel
  or by clicking a slot. What you take from a locker or the floor goes into your hand if it's empty.
- **Z** uses the item in hand by itself: turns the flashlight on and off.
- **G** puts the item from your hand on the floor in your cell. A cell holds four items.
  **E** picks up the top item from the cell ahead, and if that's empty, from under your feet. An item
  on the wall ahead (console, locker, rack) and a person lying down take priority: E goes to them.
- Items on the floor are sent by chunks, like breaches, and are part of the checksum.
- A **flashlight** in hand lights a soft round pool of warm light (v46, as in SS13), its middle
  1.5 cells ahead of the holder, fading out 6 cells from there (`Sight.glow`). Light is worked out
  cell by cell and drawn smooth (`WorldView._draw_light`); walls and closed doors stop it, windows
  and open doors let it through. Everyone sees that a flashlight is on:
  the flag travels in the character's look byte (`Net.LOOK_LIGHT`), and the pool is computed by every
  client. Without power the ship is dark: a near-black cover over the screen (unlit places stay
  faintly readable) with holes where light falls (flashlights, and a dim glow around yourself that
  shows the room). The holes are drawn
  into a separate mask image that follows the camera (`WorldView._draw_mask`). Light is computed in `src/shared/sight.gd`, which will also
  be the basis of the field of view.
- A person lying down (unconscious or dead) can be **searched** with E: a panel shows their
  slots and yours, a click moves an item either way.
- A person lying down can be **dragged** with F: a step takes twice as long, the body moves into the cell
  the dragger just left, and goes up and down ladders with them.
- The server checks both on the tick the client named, like a ladder press.

## Supplies and trade

- The ship has supplies in the supply locker (lower deck): patches, spare parts, flashlights,
  air for the plant and credits. A player takes items along, in inventory slots. The locker
  holds any item that has a starting stock in the item table.
- A breach needs a patch. Repairing a machine, door or shutter uses a spare part, and without one
  takes three times longer. The air plant uses up the air supply and stops when it runs out.
- The trader sells locker items and air for credits when the ship has come up to it.
  Purchases are made at the supply locker. A supply station refills air for free.
- Credits are given for the first jump into each sector.
- Item prices and starting stock are in `src/shared/items.gd`, other numbers in `src/shared/net.gd`
  (`SLOTS`, `START_CREDITS`, `PRICE_AIR`, `EXPLORE_REWARD`).

## Field of view and sounds

- A character sees only forward: a cone from two eyes of 85 degrees each, 160 together; in the middle
  they overlap. In the dark the cone narrows to 60 degrees, and without light only
  2 cells can be made out. Walls and closed doors stop sight. Each eye is computed separately
  (`Sight.eye_arcs`), so that later an eye can be lost together with its part of the cone.
- What's out of sight is dimmed: walls and floor are seen dimly, people there are not visible, nor their names.
- The dimming is drawn as one sheet over the screen using a two-colour mask: red — where
  it's lit, green — where the eyes are looking (`WorldView._draw_mask`, `_draw_look`).
- Sounds (`Net.SOUND_*`): footsteps, door, breach hiss, falling, the clatter of a dropped item,
  ladder. The server sends a sound to those within its range on the same deck
  (`Chat.sound`, `Chat.hears`). Sound travels only through air: if the listener or the source
  is in vacuum, only what's right next to you is heard. The client draws an icon where the sound was
  if that place isn't visible; the farther the sound, the less precise the place; a sound beyond the screen edge
  is marked at the edge with an arrow.

## Weapons and pirates

- Items: pistol (rounds are part of the item number, `Net.ITEM_PISTOL + n`), magazine, baton,
  plaster. All are in the table `src/shared/items.gd`, in the locker and at the trader.
- A mouse click on something within reach that E works on acts like E (v45: pick up, consoles, machines, repair while held); elsewhere it uses the item in hand (`C_FIRE`, `Combat.use_at`): the pistol
  fires there, an empty one reloads with a magazine, the baton hits the adjacent cell, the plaster
  heals yourself or a neighbour. Friendly fire is possible.
- The server computes a shot instantly in a straight line up to a wall or closed door, hitting
  the first one in the way. The target is taken where the shooter saw it: the client sends its "render
  tick", the server remembers where everyone was over the last 32 ticks (`Combat.place_at`).
- Pirates (`src/server/pirates.gd`) are ordinary characters controlled by the server.
  They see by the same rules as the crew, go towards what they hear, shoot with spread, hit
  with a baton at close range, patch their wounds or retreat when badly hurt, and leave people lying down alone.
  A dead pirate leaves a body with a weapon. The event director sends them with the event «Абордаж» ("Boarding"):
  they cut through the hull (a real breach) and come in; their number depends on the crew.

- Wounds (`Player.wounds`) don't heal by themselves: good air gives back only what bad air
  took (`Vitals.advance`). Wounds are healed by the plaster (instantly) and the medkit: click on yourself or
  a neighbour, both can't move for 3 seconds, heals 30, 5 uses per medkit. A badly wounded
  unconscious person won't wake up by themselves until healed. Searching shows how badly the person lying down is wounded.

Checking weapons, wounds, healing and pirates without network or window:

    godot --headless --path . --script res://tools/fighttest.gd

Network test with boarding: `BOARD=4 tools/nettest.sh 8 30`.

Checking field of view and sounds without network or window:

    godot --headless --path . --script res://tools/sighttest.gd

Checking items, hand, floor, locker and light without network or window:

    godot --headless --path . --script res://tools/itemtest.gd

## Health

- Health goes from 100 (unhurt) through 0 (unconscious) to −100 (dead). This is the scale
  of Space Station 13; the pulse monitor with eight states is drawn for it.
- Below 76% of normal pressure there is nothing to breathe: up to 3 health per second.
  Below 20% the pressure itself injures: another 2 per second.
- In vacuum from full health: unconscious after 20 seconds, dead after 40.
  In a breached 10-cell compartment: 40 and 61 seconds from the breach.
- In good air health comes back: 1 per second when conscious, 0.5 when unconscious;
  people come to at 10.
- The unconscious and the dead lie down and can't walk. A dead player can press R after 5 seconds
  and return as a new crew member. Bots return by themselves after 15 seconds.
- Bodies stay where they fell, including the body of a dead player who left.
  When there are more than 30 bodies, the oldest is removed.
- Instruments: pulse monitor, the O2 LOW lamp and the kPa lamp (it blinks when pressure is already injuring).
  The player doesn't see exact numbers; they are only in the F3 debug view.
- All numbers are in `src/server/vitals.gd`.

## Space suit and repair

- **Oxygen supply** (Q). While it's on and the tank isn't empty, the surrounding air doesn't matter:
  no suffocation and no pressure damage. A full tank lasts 2 minutes. The supply
  never turns on or off by itself, except when the tank runs empty.
- **Refilling**: face the red box on the wall and hold E. Three seconds for a full tank.
- **Repair**: right up against the breach, facing it, hold E for six seconds without a break.
- A sealed compartment stays without air until a door to an intact one opens. Air lost
  to space is returned by the air plant and the supply station.
- One E key for everything: the server first looks at what's in front of the character, then whether there's an item
  on the floor ahead or underfoot, and only then whether they're standing on a ladder.

## Bridge, sectors, event director

- The **bridge** is the upper right compartment with two consoles on the wall. You face a console
  and press E. The sector chart (green screen) sets a jump; the helm
  (panel with orange lights) steers the ship within a sector.
- **Within a sector** the ship is on a 200 by 200 square. Clicking the map on the helm
  sets a course; the ship goes there in a straight line at 1.5 per second.
  Meanwhile stars drift past the windows.
- **The sector's main feature has a location.** A meteor shower is a circle, and a jump
  lands inside it; outside the circle the sector behaves like calm space. You must come up to a station
  or a trader: the station refills air when docked.
- **Consoles break** (the event «Замыкание пульта», "Console short circuit"). A broken one doesn't work, goes dark
  and sparks; it's repaired by holding E for six seconds. Both never break at once, so one
  of the two ways to escape always remains.
- **Space is infinite.** Sectors sit on a grid without edges. What's in a sector follows from its
  location and the number the game started with, so nothing is stored about sectors the ship
  hasn't come near. The server keeps and sends only a 7 by 5 window of sectors
  around the ship and rebuilds it after every jump (`src/shared/sectors.gd`).
  Every sector has a route north or east, so there are no dead ends.
  The farther from the start, the more frequent the meteor showers.
- **Sectors.** Each has one main feature: calm space, a meteor shower, a trader
  (sells supplies) or a supply station (refills air).
  The crew knows what's in sectors they've been to and in those next to the current one.
- A **jump** charges for 8 seconds, then the engine rests for 15 seconds. Only someone standing
  at the console can set it.
- The **event director** (`src/server/director.gd`) decides what breaks and when. It has a catalogue
  of events in four sizes (eleven events now: micrometeorite, meteor volley,
  console short circuit, engine failure, air plant failure, jammed door,
  emergency shutter failure, power failure, boarding and pirate ship, which it picks by chance,
  and drifting fuel, which comes by itself to a ship left with no fuel at all), a pace depending on the sector and the number of players, and "restraint":
  while there are more open breaches than the crew can reach, or everyone is down,
  there are no new events.
- The host can run events themselves: in the menu, the checkbox «Ивентер ведёт события сам» ("The event director runs events itself")
  and a button for each event.

Checking the pace without waiting in real time:

    godot --headless --path . --script res://tools/directortest.gd

Checking space (one place is always the same, no dead ends, the map remembers where you've been):

    godot --headless --path . --script res://tools/spacetest.gd

## How it works

- The server decides everything: the client sends only "which key is held", the server moves characters
  and tells each client what changed near it.
- «Создать игру» ("Create game") starts the server as a second windowless process, so it doesn't freeze
  when the host minimizes or drags the game window. When the host leaves, the server
  says goodbye to the players and shuts down. If the separate process couldn't be started,
  the server runs inside the game, as before.
- The client sends every change of direction three times in a row: losing one packet
  doesn't delay the command.
- Your own character moves on the client immediately, without waiting for a reply: the client runs the same movement
  rule as the server, and quietly corrects itself on a mismatch.
- Other characters are drawn with a 0.1-second delay, so they move smoothly even over an uneven connection.
- Every two seconds the server sends a checksum, and the client checks its picture of the world against it
  (visible with F3).

## What is temporary

The map is made of mockup tiles. Characters, the closed shutter, half-open doors and the breach
are drawn by code (`tools/make_assets.py`). Stars and the sparks of a broken console are drawn by the game itself.
