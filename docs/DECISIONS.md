# Spacer: decisions and reasons

Why each mechanic and piece of the engine is the way it is: the author's words, the
reasons behind numbers and rules, and where in the code each one lives. Moved here from
`CLAUDE.md` in v51 so that every session does not have to read it all.

**Before changing a mechanic, search this file for it** (`rg -n "airlock" docs/DECISIONS.md`):
many rules here are the author's own word and must not be broken silently. When you make a
new decision, add a bullet here in the same style: the rule, its reason, and the code it lives in.

- **Godot 4.7.2 and GDScript.** BYOND is outdated. Robust Toolbox (the SS14 engine) was rejected: C#,
  mixed licenses (MIT, GPLv3, CC-BY-SA), frequent incompatible versions.
- **One thread.** Measurements in `research/`: threads speed up a server tick but don't reduce the total
  load and add hard-to-catch bugs. Revisit if the server has more than 128 players
  or a tick takes longer than 25 ms.
- **Air: one number per tile** (pressure), no gas composition. Composition will be needed
  for the suit and fires. Right now the loop visits every tile; for an 80-tile ship this
  costs nothing. For big maps: compute only unsettled tiles or move it
  into a compiled module (`research/` has measurements: 255×255 in GDScript is 40 ms per tick).
- **Leak speed** is tuned to leave time to react: a 10-tile compartment
  loses half its air in 8 seconds. Coefficients in `src/server/air.gd`.
- **Doors open by themselves**, as in SS13. Players don't collide with each other.
- **Health on the SS13 scale:** from 100 through 0 (unconscious) to −100 (death). The author's `hud.dmi` has
  exactly eight monitor states for this scale and the SS13 alarm lamps: hunger,
  low and high pressure, low and high oxygen, toxic air, O2 supply.
  Used: the monitor, `kpa_low1`, `kpa_low2`, `o2_low`; the rest await their mechanics
  (hunger, fire and overheating, gases, the suit tank). Damage numbers in `src/server/vitals.gd`.
- **Instead of pressure numbers, the author's lamps light up.** Exact values only in debug via F3.
- **The space suit** (until build v29 it was always worn) is now clothing, but everyone arrives in it.
  Only the oxygen supply is controlled, like "internals" in SS13: the author has lamps
  `o2_on` and `o2_off` for this. The supply protects against both suffocation and pressure, and
  doesn't turn on without a suit (`Inventory.set_supply`). There is deliberately no automation.
- **Clothing is three places** (`Player.worn`, `Net.WEAR_*`), separate from slots. There are now
  12 slots: 6 always, 2 pockets with a jumpsuit, 4 with a backpack (`Player.usable`; the client repeats
  the rule in `GameClient.usable`). A worn suit is stored as `ITEM_SUIT`, with oxygen
  in `Player.tank`; a removed one is the item `ITEM_SUIT + tenths of the tank` (like ammo in a pistol).
  Appearance travels in the `S_OUTFIT` packet (a row of `chars.png`: color × 6 looks, `Net.LOOKS`),
  not in the character record: it changes rarely and doesn't touch checksums.
  The tank level bar is drawn in code: the author's HUD has none.
- **The oxygen rack** is a red box on the wall (`console_2` from the mockup), digit 2 in the map.
- **One action key.** The client sends only "pressed/released"; the server looks at the tile
  in front of the character: a breach gets repaired, a rack refills. Add new objects there too
  (`Repairs.update`), and the hint in `GameClient.use_target`.
- **A body is a separate record** with its own number and the kind "body" in the crew list.
- **Bridge consoles are wall tiles:** the green screen (`console_1`, digit 1 in the map) is
  the sector map, the panel with lights (`console_3`, digit 3) is ship control.
  The console's role is determined by its tile (`ShipMap.chart`, `ShipMap.helm`).
- **Inside a sector** is a 200×200 square (`Sectors.SPAN`); the main feature has a place
  and a radius: a meteor stream's circle or docking range. The ship moves in a straight line
  at constant speed, so the server sends its position only when the course changes,
  and the client computes the rest (`GameClient.ship_pos`). Sector danger for the director
  takes the ship's position into account (`Navigation.danger_kind`).
- **An ordered jump cancels the in-sector course** (the author's remark): a moving ship
  coasts straight until the jump rather than toward the old point (`Navigation.start_jump` moves the target
  to the sector's edge), the course line from the control console disappears, the helm doesn't respond.
- **Everything broken** (consoles, engine, air plant) lives in `Ship.broken`
  keyed by wall tile and is sent in full on change. Repaired with the action key, like a breach.
  The "not both at once" rule is in `Systems.can_break`: bridge consoles and the engine break one at a time.
  For the consoles, this guarantees an escape route from the author's vision.
- **The engine powers the whole ship** (tile `engine`, digit 6 in the map). The author's word: when
  the engine shuts down, absolutely all systems stop working, but don't break.
  So everything added to the ship must ask `GameServer.powered()`
  (on the client `GameClient.powered()`). Currently dependent on power: movement and jump, consoles,
  the air plant, oxygen racks, emergency shutters, doors (`Doors.manual`: without
  power they open with a push over 1.5 s) and light (darkening in `GameScreen`). Not dependent
  on power: the suit, the player's instruments, ladders and repair: otherwise the engine couldn't be repaired.
  So there are never two obstacles to escape at once, the engine doesn't break while a
  console is broken and vice versa.
- **The emergency shutter is a property of the door**, not a separate object: it isn't in the map, every
  door has one (`Doors.locked`). The server drops it based on the pressure difference on the tiles on the two
  sides of the door (`ShipMap.door_sides`) and sends it along with the door. The rule "you can't walk into a locked door"
  lives in `Doors.bump`, because the client predicts it. The client computes the pressure difference itself from
  the air it already knows. This is the only place where the ship
  shows where there is no air: the author asked for this himself.
- **A door's troubles travel in one byte** with it (`Doors.flags`): shutter down, door jammed
  open, shutter faulty. A door jams specifically open: a closed door that won't
  open would be the same to the player as a fallen faulty shutter.
- **The server tells the client about power** (`S_POWER`); the client doesn't infer it from the
  engine's state: power can be lost with an intact engine (the "Power failure" event).
  The server checks it every tick in `Systems.power_changed`.
- **The shutter slams an open door early.** This breaks the "Pitfalls" rule about
  `Doors.HOLD_TICKS`: a player walking into the door at that moment gets a one-step correction.
  Accepted: it happens only with a fresh breach.
- **The air plant** (tile `air_plant`, digit 7) adds air to the tile in front of it
  (`Air.PLANT_PER_STEP`), not above normal, and spends the ship's store on it (`Ship.store_air`).
- **Inventory is six slots, one item per slot** (`Player.slots`, `Net.ITEM_*`). Slots
  travel to the client in the wellbeing record. An item lies in a slot (of a living person or a body), as a count
  in a locker, or on the floor (`GameServer.floor_things`: tile → up to `Net.FLOOR_STACK` items,
  sent by chunks in the `SEC_FLOOR` record and included in the ship checksum).
  Add a new item like this: a number in `Net.ITEM_*`, a line in `Items.INFO` (properties),
  a picture in `ItemArt.draw`, its use wherever it's needed.
- **An item's state is a separate item number** (lit flashlight `ITEM_FLASHLIGHT_ON`), not a
  separate field: that way the state travels with slots, in searches and on the floor by itself. The `kind` property
  says what the item counts as (a lit flashlight in the locker and in counts is a flashlight).
- **The hand is chosen by the client** (`C_HAND`); the server only follows it and doesn't send it back:
  otherwise fast switching would flicker. A taken item goes into the hand if it's empty (`Player.add`).
- **A left click is E on what was clicked** (v45, the author's request): `GameClient.click_facing`
  finds the facing for which `use_target` reaches the clicked cell (current facing first); the screen
  turns the character (`GameClient.face`, a predicted turn), waits until the prediction shows the turn
  (so the press carries a tick after it), then opens the console like the key (`GameScreen._use_screen`)
  or holds "use" while the button is held. A weapon or medical item clicked at a person (or ourselves)
  still fires (`GameScreen._fires_at`); anywhere else the click is the old `send_fire`. No protocol change.
  Test helper: `click=X,Y click_after=S` in `main.gd`.
- **E first targets the object on the wall ahead, then a downed person, then an item on the floor, then a ladder**
  (`Repairs.press`, `Inventory.pick_up`; the client uses the same order in `use_target`). You can't pick up
  an item a person is lying on: E then opens the search.
- **Light is computed per tile** (`Sight.cone`): a tile is lit if it falls into the cone
  even by an edge and the straight line to it doesn't pass through a wall or closed door. That's how tiles
  are lit in SS13, and the same will be used for the field of view. The server doesn't use light yet,
  and the client uses tiles only to decide whether a name is visible. Light is drawn smoothly: the beam is a polygon
  of rays cut off at walls (until v45; since v46 see "Light as in SS13"). Without power the ship is dark: a black cover
  with a shader and an image mask where red marks light; space outside doesn't darken.
- **Darkness is dim, not pitch black** (v45, the author's screenshot; it replaces the v27–v44 rule
  "only the flashlight gives light"). In the dark a red glow `DIM` (0.3 since v46) around our character,
  a `Sight.glow` pool of `DIM_RADIUS` cells, goes into the mask (`WorldView._draw_mask`), so the room is
  made out dimly and the flashlight is clearly brighter. Since v46 the dark sheet itself is not opaque
  (`DARK` alpha 0.93; 0.955 since v47): unlit places stay faintly readable, as in SS13.
- **Deep dark** (v47, the author's word and SS13 screenshot). Out of sight is as dark as unlit (`UNSEEN`,
  the shader mixes it by the green of the mask), whether the place is lit or not; it replaces the v46
  `FOG` (a lit place out of sight was only dimmed to 0.74), so stars and lit rooms behind you are black
  too. Instead a soft pool `NEAR` of `NEAR_RADIUS` cells (`Sight.glow`, stopped by walls) is drawn green
  into `_look` all round our character, and in the dark adds a little red light: that is the SS13 look of
  a player standing in a small pool. Purely client drawing; who is seen is unchanged (`can_see`,
  `Replication.sees`).
- **The smooth cone** (v48, "smoother, like a triangle"). A second picture, `_cone_view`, holds the
  field of view as one soft fan not cut by walls (`CONE_SHADER`, worked out per pixel: a side fades across
  `CONE_BAND` cells at our feet, widening by `CONE_SOFT` degrees outwards), plus the `NEAR` pool;
  the shaders multiply the cells seen (green, worked out `LOOK_MARGIN` wider each side) by it, so walls
  still cut sight cell by cell but the sides are straight and soft. `_draw_light` takes one cell more
  round a light and lets open floor past its edge blend to zero (walls still keep the light up to them).
- **A clean screen** (v47, the author crossed them out): the status lines (`_info`) and the key hints
  (`_keys`) in `GameScreen` are hidden until the `info` action (F1). The frame counter alone stays
  in the top left when it is on in the settings. The first chat line names F1.
- **Light as in SS13** (v46, the author's screenshots). A light is a set of cells with strengths
  (`Sight.glow`: a round pool around a spot ahead of the holder, cells with a clear line from the
  holder, walls lit on a face turned to the light; the old `Sight.cone` is only in tests now). The
  client draws such a set (`WorldView._draw_light`) as a small picture, `LIGHT_SUB` pixels a cell,
  blending between cell middles and zero in cells the light does not reach, stretched with linear
  filtering: smooth falloff, no leaks past walls. The flashlight is `Items.light` = [radius, ahead];
  the server (`Replication._lit_cells`) and the client (`GameClient.lit_cells`) use the same pool, so
  people stood in it are seen. Add new light sources as more `_draw_light` sets.
- **Vision 9 cells** (v46, the author): `Sight.SIGHT_REACH` is 9 (eyes, server visibility, pirates),
  and the camera zoom is the whole number that shows at least `VIEW_CELLS` (9) cells either side across. The look (green) is always the full 160°
  cone now. People in the dark are still judged by the old rule (60°, 2 cells or a light: `can_see`,
  `Replication.sees`), so the dark keeps hiding them.
- **Cells are seen whole** (v42–v43, the author's request): `WorldView._draw_look` keeps the smooth cone
  (rays now stop exactly at a wall's face) and paints as a full tile of green every cell a ray passes or
  stops at whose middle lies inside an eye's arc; our own cell is a square (a disc used to poke into the
  wall beside us). A cell whose middle is outside (the wall right beside us) stays dark beyond the cone. The v38 rule "walls around you always visible" is gone: the author
  found it lit walls behind him and in the pitch dark.
- **Every cell in the cone is checked on its own** (v44, the author's screenshot): the rays of
  `_draw_look` were too sparse to touch a wall seen nearly edge on far down a corridor. Now floor whose
  middle has a clear line (`_clear_to`, cell by cell) and a wall with a face turned to the eye on a seen
  floor cell count too. A wall is never "seen" through another wall (that chained down whole columns
  in a first try). It costs a few milliseconds a frame in software rendering.
- **No blinking at the edges of sight** (v52, the author's video): whole cells are decided only by
  `_clear_to` (floor and walls whose middle is in plain sight), a wall's face on a seen floor cell, and a
  corner (walls on both sides towards us, the diagonal floor seen); never by whether a ray touched them,
  since rays move with every pixel walked and a room's far corner was shown one frame, hidden the next
  (in the video ~60 blinks in 20 s; in a scripted walk here 23–26 before, 0 after). The rays are walked
  cell by cell (`_ray_reach`), so they stop exactly at a wall and never slip past a corner.
- **One clock per frame** (v52, the author's video: steps jerked every few frames): `GameClient.now_ticks`
  moves once a frame by the frame's length (`_tick_frame_clock`), pulled 5% a frame towards the wall clock
  and snapped to it past 2 ticks. Reading the wall clock mid-frame put each frame's picture as far on as
  that frame happened to start late. `GameClient` processes first (`process_priority` -100), and the
  cone's soft fan (`_update_fan`) is placed after the characters move: it trailed a frame behind.
- **The light and sight mask** (`WorldView._draw_mask`, `_draw_look`): red is ship light,
  blue is flashlights and flashes (they light only where green is, i.e. where we look), green is
  the field of view. Warm beam light (`_shade`) is also drawn only within the field of view. Whoever disappears
  from view leaves a silhouette for 10 s (`_afterimages`, the author's request, build v30).
- **The server decides who each client sees** (since v39, the author's request). A client is sent
  only the characters its own one sees by the same rules the client draws by (`Replication.sees`
  repeats `WorldView.can_see`: the cone, walls and shut doors, the dark, see-through floors), those
  right next to it (felt: searching and dragging need them, as with pirates), and those on its deck
  with a lit flashlight (the beam is seen from anywhere, and the client draws beams from characters
  it knows). The server's cone is 12° wider each side and a character stays sent 4 ticks after going
  out of sight: the client judges sight on its own predicted clock, so without the margin people
  would pop in late at the edge. One going out of sight is sent as `Net.FACING_HIDDEN` with the cell
  where it was last seen, and the client leaves the silhouette there (`GameClient.hidden`). Bodies are
  characters too and follow the same rule. Shots (`S_SHOT`) and sounds still reach everyone in range:
  they are heard, not seen. Sight is cached per pair until either moves or turns or
  `Replication.sight_changed()` is called; in the dark it is worked out every tick.
  Sight and light are computed by the shared `Sight` code, which pirates also use.
- **Sound travels through air** (I proposed it, the author accepted "silence in vacuum"): `Chat.hears`
  requires air at the source and at the listener, except very close (`SOUND_CONTACT`).
  A sound doesn't say who made it; your own sounds aren't sent. Only your own deck is heard.
- **A shot is instant, with time rewind** (`Combat.use_at`, `Combat._shoot`, `Combat.place_at`):
  the client sends the tick at which it saw the others, and the server checks the hit at that position.
  Bullets are stopped by any impassable tile, including a window (`Combat._stops_shot`).
- **A fatal wound takes health one below −100**, otherwise the next breath of good
  air would "resurrect" the dead. A pirate killed in this tick no longer thinks.
- **Wounds are separate from health** (`Player.wounds`, groundwork for the author's item 2.1: damage types).
  Health rises by itself only up to `100 − wounds`; wounds are closed only by healing
  (`Combat.heal`). The medkit heals with a delay (`Combat.update_treatment`, progress shows as
  the work bar); its charges are part of the item number, like ammo. Only whole items
  go back into the locker (`Items.whole`), so a used medkit can't be swapped for a new one.
- **Pirates are ordinary Players with the `pirate` flag** (kind in the list `KIND_PIRATE`, colors are three
  rows of `chars.png` after the crew colors). They breathe on their own (sealed suits). All their
  behavior is in `src/server/pirates.gd`; they pathfind over the grid with ladders, around fallen shutters.
- **Boarding** doesn't repeat while a living pirate is aboard; an unarmed crew gets it
  half as often and with one pirate fewer.
- **Searching and dragging** work only with a downed person (unconscious or dead) in your own
  or a neighboring tile. Presses carry the client's tick number, like the ladder
  (`Looting.hands_asked`). A search works as a subscription: the server sends the downed person's slots while
  the searcher is near (`S_SEARCH`), and closes it itself.
- **The dragger walks half as fast** (`Mover.State.slow`, `Net.DRAG_TICKS`): this is part of the movement
  rule, and the client predicts it. The flag travels in the character's look byte (`LOOK_SLOW`),
  so others' steps are drawn at the right length too. The body moves into the tile the dragger
  left (`Looting.haul`); on the dragger's screen it is drawn in step with their own steps
  (`GameClient.sample`), otherwise it would lag by the ping.
- **The ship's store is shared and lives in the supply locker** (tile `locker`, digit 8): patches,
  spare parts, air for the plant, credits (`Ship.store`, `Ship.store_air`, `Ship.credits`). The locker opens with a panel, like consoles, but without power; buying from the trader goes through
  the same panel and requires power. I designed this; the author approved the step's whole concept.
- **Without a spare part you can repair, but three times slower**, and without a patch a breach can't be sealed.
  So a ship with a dead engine and an empty locker doesn't hit a dead end, while losing
  compartments stays real.
- **Fuel is an item in the supply locker** (`Net.ITEM_FUEL`), not a separate number: that way the trader
  sells it automatically, it lies as loot on other ships, it can be carried away and put
  back. A jump checks for a canister when ordered and burns it at the moment of the jump
  (`Navigation.update_jump`); if the last one is removed during charging, the jump fails.
  No dead end: with not a single canister aboard, after 2 minutes the director itself gives the event
  «Дрейфующее топливо» ("Drifting fuel") (`Director._watch_fuel`); a station tops up to 3. I decided this.
- **Crew reserve** (`GameServer.reserve`): R costs a person (`Crew.respawn_from_reserve`);
  a dead player who left and came back under the same name also costs one (`_dead_names`, the check
  in `Crew.hello`). If the reserve is empty and there are living crew, they aren't let in (`REJECT_NO_CREW`): otherwise
  leaving and rejoining would bypass the reserve. New names come free. I decided this.
- **Campaign end** (`Crew.end_campaign`): hull at zero or all players dead with an empty
  reserve (`Crew.check_crew`, once per second). The game freezes: the director is silent, no jumps,
  everyone gets the summary screen. There is no live restart: the host creates a new game. It's simpler
  and more honest; I decided this.
- **Jobs and access**: access is a bitmask (`Net.ACCESS_*`, `Net.JOB_ACCESS`); a
  door's is `ShipMap.door_access` from lines `@ deck x y access` in the map (compartment fill
  in `make_assets.py`). The check is in the shared `Mover.step` via `Doors.barred`, so the client
  predicts it; the client learns its own mask from the `S_ME` packet. Without power locks don't
  work (the escape-route rule); a lock is hacked in 5 s with a ship-wide announcement.
  Spawn points are moved out of locked compartments (checked by `crewtest`).
  Bots and pirates go everywhere. I invented the skill numbers.
- **Speech** (`Chat.talk`, `Chat.hears_said`): the channel is chosen by a sign at the start of the line
  (`;` radio, `!` intercom), to avoid multiplying keys; `S_CHAT` carries the channel number.
  Spoken aloud — by the same air rules as sounds (`Chat.hears_voice`). The dead talk among themselves.
- **Saving** (`src/server/campaign.gd`): one JSON in `user://`, written to a temporary file
  and renamed. Characters are stored by player name (`saved_crew`); the living character of a player
  who left also goes there, so you can leave and rejoin the same evening. Another ship
  alongside, pirates and the director aren't saved. Tests and nettest don't write a save
  (`save_path` empty, `campaign=off`). The host also saves manually (Esc, `Net.ADMIN_SAVE`):
  the author didn't find a button and decided there was no saving, so it's shown in chat.
- **Sounds are made in code** (`src/client/sounds.gd`) from noise and tones: no files and no others'
  licenses (TauCetiClassic is only for ideas, as the author said). Muffling is the
  `Muffled` bus with a low-pass filter, if the source isn't visible or the air around is thin.
- **Credits are given for the first jump into a sector.** This is an economy placeholder: there's no other income.
  In infinite space this income never runs out, and there's a trader in roughly every
  fifth sector.
- **The director watches the store:** with not a single patch aboard, breaches are three times rarer
  (`Director._weight`). This is the first "equipment scan" from the vision.
- **The action hint** sits between the chat and the instruments and wraps by words
  (`HINT_LEFT`, `HINT_RIGHT`): otherwise long lines overlapped the chat.
- **Machine state is visible as light on the floor** (`WorldView._draw_fx`): so it can also be seen through
  the glass floor from the upper deck. That's why the engine stands under the bridge glass, and the plant
  under the corridor glass.
- **Transparent floors are tile kinds:** `glass` (visible, air doesn't pass), `grate` (catwalks:
  visible, air passes), `hatch` (hatch with a ladder: visible, air passes, can go down),
  `ladder` (bottom of a ladder). `make_assets.py` draws them from each floor piece, cutting out
  the middle. That air goes through catwalks and not through glass was my decision; the author didn't specify it.
- **Ladder by the action key:** stand on the tile and press E. Climbing isn't predicted by the
  client. The press carries the tick number by the client's clock, and the server checks the ladder at that
  tick: otherwise with ping the press arrived when the server hadn't yet brought the character to the tile.
- **What's visible through the floor:** the lower deck is drawn in full under the current one and darkened;
  the current deck's floor covers it everywhere except transparent tiles. From the deck above, only those
  standing on a transparent tile are visible. Names are hidden along with their owners (`GameClient.seen_from`).
  The client still knows everything about the other deck: this doesn't protect against peeking.
- **Air between decks** flows half as fast as along a deck (`Air.FLOW_DECK`): a tile now
  has up to six neighbors, and with the old coefficient the computation would start to oscillate.
- **Space is infinite and stored nowhere** (`src/shared/sectors.gd`). Sectors sit on a grid
  without edges; a sector's contents are computed from its position and the game's number (`space_seed`), so
  the same place is always the same. `Sectors` keeps only a 7×5 window around the ship;
  the server rebuilds it on every arrival and sends it in full (`S_SECTORS`), and sector
  numbers on the network are numbers within the window. Only where the ship has been is remembered (`GameServer.been`).
- **Routes:** every sector has a mandatory route north or east, plus
  one in each direction with probability 0.3. The mandatory route guarantees there are no
  dead ends or closed pockets; there are never more than four routes (that's how many jump
  buttons fit on the console).
- **Difficulty grows with distance:** the share of meteor streams goes from 20% at the start
  to 45% (`Sectors.NEAR_METEORS`, `FAR_METEORS`, `MOST_METEORS`). I decided this; future threats
  should be tied to it too.
- **The director** is in `src/server/director.gd`. A new event: a line in `EVENTS`, a branch
  in `_run` and a branch in `_can_happen` (an event isn't chosen if it would change nothing;
  limits are in `Systems.can_break`). "Scanning" the ship and crew is the `assess` function; add there
  what the director looks at. Pacing is checked by `tools/directortest.gd` without waiting.
- **The game host is also the GM:** commands to the director use the same secret pass
  as stopping the server.
- **Lack of air is not drawn.** The author asked to remove the darkening of compartments to make it
  harder: the player sees only the pressure in their own tile. Air wisps right at the breach
  remain. Don't add hints about air without his word.

- **Game ship `ship02`, tests on `ship01`:** the coordinates in tests are tied to the old map,
  so it remains. The airlock is checked by `tools/locktest.gd` on `ship02`.
- **The two-door airlock** is found by its pump (tile `lock_pump`, digit 9): the chamber is the floor
  in front of the pump up to the doors, the outer door is the one with space behind it (`ShipMap.door_vent`).
  The rule "only one open" lives in `Doors.bump` (`partner`); the client predicts it.
  The interlock is released manually (E for 3 s, `Doors.forced`, bit 3 in the door's trouble byte): without it
  a jammed outer door locked the chamber forever (softlock, found by the author in v32).
  There's no separate locking logic: emergency shutters treat space as pressure 0, so they
  hold the outer door themselves when there's air in the chamber and the inner one in vacuum. The pump
  (`Systems.toggle_pump`, `Systems.run_pumps`) moves air into the ship's store and back;
  its operation travels in `S_DEVICES` after the list of broken things. An open outer door
  vents the air in its doorway (`Air.VENT`).

- **A derelict ship is placed in the same grid** (`ShipMap.add_other`, `place_other`): its
  blueprint is `maps/derelict01.txt`, its door numbers are kept at the end of the door list, and `base_*`
  holds our ship without it. There are 10 empty rows above our ship for this. Where it lies,
  the server sends via `S_OTHER`; everything else (items, breaches, air, doors) goes in ordinary
  chunk records. The logic is in `src/server/derelict.gd`: it stands `GAP` tiles above the airlock
  or is docked door to door (it shifts with everything on it). Items left
  on it are remembered per sector. It has no power: doors are manual (`Doors.dead`), it's dark.
- **There are several kinds of other ships** (`Net.OTHER_MAPS`: derelict and pirate); all lie
  in the same place in the grid (`ShipMap.others`, `place_other(at, kind)`), with shared door
  numbers. The pirate ship is the same `derelict.gd` module: it comes alongside, after
  `PIRATE_WARNING_TICKS` docks by force, jams both airlock doors open and releases
  pirates (`pirates.spawn`); it has power and light. Its tiles are the same tiles
  recolored by the script (`pirate_*`; the `pirate*` map lays them out itself).
- **Ship weapons** are in `src/server/gunnery.gd`: guns are `gun` tiles in the hull (sign `T`
  in the map, `ShipMap.guns`), the console is `console_4` (`ShipMap.gun_console`). State travels
  in the `S_GUNS` packet on change. Combat happens only while the pirate ship stands alongside
  and isn't docked (`fighting`): it shoots at us, we at it; 6 hits and it's wrecked
  (`Derelict.pirates_wrecked`), 25 credits. This is the second source of credits after exploration.
- **Aiming at the enemy's systems** (v41, the author's request). The pirate ship's rooms are named by
  lines `% deck x y system` in its map (`ShipMap.zones`, `Net.ESYS_*`): weapons, bridge, engine, quarters, jump drive (v44).
  The aim is one per ship (`Gunnery.aim`, `C_AIM`), not per gun, so everyone at the console sees the same.
  A hit takes 1 from its hull and 1 from the system in the room it lands in (a random room without aim),
  and holes its hull next to that room. Effects: weapons out = it does not shoot; bridge out = it hits
  half as often and we hit 95%; engine out = the docking countdown stands still; quarters: every 2 hits
  kill a boarder, none left = it breaks off unpaid. Its crew mends the worst system by 1 every 15 s.
  I chose these numbers and effects; there are no shields in the game, so no shield system.
- **Two pirate-ship events** (v44, the author's request): `PIRATE_SHIP` boards as before; `PIRATE_RAID`
  (`Derelict.raid`, `Gunnery.raid`) never docks. The enemy runs when its hull is at `FLEE_HULL` or its
  guns are out at half hull: `Gunnery.flee` counts the jump charge, its pace is the jump drive's
  strength share (`Net.ESYS_JUMP`, a fifth room in `pirate01`), nothing with the drive or engine out.
  A wrecked raider stays as `Net.SHIP_WRECK` (dark, doors dead, `Derelict.dark()`), dockable, and leaves
  when our ship moves. Who is aboard is rolled at wreck time (`Derelict.WRECK_ALL_DEAD` 70%, the rest
  half fight, half join the reserve) and shown to the first of the crew aboard (`_watch_boarding`).
  Defaults I chose: flee threshold, 50/50 for fight/join, joiners go into the reserve, worn drive =
  slower charge in proportion. Either enemy is left behind when our ship jumps to another sector.
- **The holomap** (v41, tile `holo`, sign `M`) is the one exception to "lack of air is not drawn": the
  author asked for a monitor that shows where the pressure is. It is a console one must stand at, with
  power. A client knows the air only around itself, so the server sends `S_HOLO` (air of every floor cell
  of our ship in `ShipMap.on_ship` order, holes, door states) twice a second only to those watching
  (`Holomap.watching`), and stops when they step away or the power goes. No new gas mechanics.
- **The ship's store window** (`StoreView`) and the gun and holomap screens (`GunsView`, `HoloView`) live
  inside the console frame of `GameScreen` (shown instead of its chart, text and buttons), so the old
  rules for consoles hold: E or Esc closes, stepping away or losing power closes.
- **Open space is passable** (`ShipMap.floats`, `Mover`): within the grid and deck rows,
  a step takes twice as long, there's no air. While someone alive is outside or the ships are docked,
  the ship doesn't move or jump (`Derelict.holds_ship`), and a started jump fails.
  I decided this: we don't abandon anyone. Bots and pirates don't go into space.

- **Ship weapons, power and shields** (v49, the author's request; `src/shared/weapons.gd` holds every number
  the server and the client share). A gun mount (`ShipMap.guns`) holds a weapon (`Ship.mounts`), powered or not
  (`Ship.armed`); a weapon off its mount is cargo: the item `Net.ITEM_GUN + Weapons.*` in the locker, with
  `Items` "cargo" (never carried, `STORE_TAKE` refuses it). Rockets are cargo items too. The reactor gives
  `Weapons.REACTOR` (8) to the guns and the shield (2); I chose the numbers. Set-up goes by `C_GUNSET` from
  the gun console. Shields follow the author's rule exactly (holds at 50+, below lets through with chance
  (50 − level)/50); rockets pass unless `Ship.hardened`, half the blaster's pellets pass, ion only wears
  the shield and puts a system out (`Ship.jammed` for ours, `Gunnery.systems_out` for theirs). Our generator
  is the `shield` tile ('Z'); theirs is the sixth room `Net.ESYS_SHIELDS` (70% of pirates have one). Our
  shield falls to 0 without power, broken or switched off; ionised it keeps its level but does not protect.
  Enemy guns are a loadout from `Gunnery.ENEMY_*`, each charging on its own (1.3× slower than ours).
  Weapons from `Weapons.TRACTOR` on are the items `Net.ITEM_GUN_MORE + w` (the rockets hold 61 and 62);
  always go through `Weapons.item_of`/`of_item`, never `ITEM_GUN + w`.
- **The trader's offers are made by the server** (`Supplies.offers`, `S_TRADE`), seeded by the game and the
  place, so the same trader always has the same 4 ship weapons and, 30% of the time, the hardening. Selling
  is from the locker at half price (`Weapons.SELL_SHARE`). The trader's window is `TradeView`, opened from the
  locker's window (`GameScreen._show_trade`).
- **Admin rights** (`src/server/admin.gd`, since v40). The host's game proves itself with the
  server's secret text (`ADMIN_HELLO` right after joining; `Player.host`), and only the host makes
  others admins (`ADMIN_GRANT`), by player name (`Admin.names`, kept in the save). Others send
  `C_ADMIN` with no text; the server checks `Player.admin`. The client learns its rights from the flags
  byte at the end of `S_ME`. The author asked for an admin panel "for all tests"; I decided that
  healing raises the dead where they lie, and that a body left after a return from the reserve stays a body.
- **The player's settings** live in `user://options.cfg` (`src/client/options.gd`), not in the menu's
  `settings.cfg`, which the menu rewrites whole. Every key is an action in `Options.ACTIONS` (two keys
  each, physical keycodes, optional Ctrl/Shift/Alt). Check keys with `Options.pressed` and `Options.held`,
  never `is_action_pressed`: a bare key also works with a modifier held unless that exact combination
  is another action's. Text on screen is written with the default letters and passed through
  `Options.keyed`, which puts the player's keys in their place. Sounds go to the `World` bus and the
  engine hum to `Hum` (both made by `Options.ensure_buses`).
- **Windows over the game** (inventory, admin panel) do not take the keyboard: their buttons have
  `FOCUS_NONE`, so the character walks while they are open. The settings window and the menu do take it.
- **Own footsteps** are played by the client only in air (`Net.SOUND_AIR`) and never in open space:
  the author's rule that vacuum is silent (they were heard muffled until v40).

- **Who sees whom is prepared once a tick** (v51, the author's request for speed). `Replication._prepare`
  packs every character's place and look, chunk and light once, so the per-pair work only compares
  numbers; the pair's cached answer is worked out again in the dark only for pairs that stand in a dark
  place (`_dark_cell`), not for everyone whenever a dark ship is alongside. Lines of sight are remembered
  by cell pair with the doors they cross (`Sight.clear_cached`); pirates use the same memory. Measured
  with `tools/sightbench.gd` and `tools/bench.sh`, which prints the tick split into parts (`GameServer._lap`).
- **The client draws only what changed** (v51). Light pictures are made again only when the light's cells
  change (`WorldView._light_picture`); the light mask and the field of view are redrawn only when their
  key changes; pools of light are remembered by place, facing and doors (`GameClient.glow`). The picture
  is the same as before, pixel for pixel in the screenshot check.
- **E does one thing, in the order the player is shown** (v51 bug fix). `Repairs.press` stops at whatever
  is usable on the wall ahead (machines, intercom, holomap and locked doors included) or a downed person
  ahead or underfoot, before it would pick up an item or take a ladder; this is the order of
  `GameClient.use_target`.
- **A plaster is not used up on somebody with no wounds** (v51 bug fix, `Combat`): it would have been
  wasted and the player sees nothing happen.
- **Pirate ships are rolled from hand-drawn hulls** (v53, the author: "make them procedural... different
  setups for each ship"; he agreed to hand-drawn hulls with the insides rolled). Fully generated hulls would
  need their own checks that they fit off our airlock, draw well and have a room per system; seven drawn hulls
  in four classes give variety while rooms, systems, guns, shield, crew, temper and name are rolled
  (`src/server/shipyard.gd`, classes in `src/shared/hulls.gd`). Any hull may be added as `maps/pirateNN.txt`:
  7 rows (band, 2 room rows, band, 2 room rows, band), the outer `D` in the bottom band at x ≤ 10, the upper
  half narrower than the lower, at least 6 rooms; add it to `Net.OTHER_MAPS` and a class's `layouts`.
- **Bigger is harder through behaviour, not only hull** (v53, the author agreed): a class differs in guns,
  their pool, shield and its refill, how slowly its guns charge, how easily it is hit, crew and reward; the
  temper (calculating, cautious, reckless, hunter) decides when it runs and what it shoots at. Classes come
  only from some distance out (`from`), so the first fights stay small.
- **Its insides are unknown until found** (v53, mine): with systems in random rooms, knowing them is the
  interesting part of a fight. Sensors (one room per 7 s while powered), hits, its own fire and a probe
  (12 cr., one aboard at the start) show rooms; aim goes at a room (`Net.AIM_ROOM + room`), so firing blind is
  allowed. Rooms are found by flood fill of floor bounded by walls and doors (`ShipMap.rooms`), the same on
  server and client, so only per-room bytes go over the network.
- **The old pirate ship stays for tests** (`Shipyard.classic`): guntest was written against its fixed
  rooms and numbers; `tools/shiptest.gd` checks the rolled ones.
- **Outline under the mouse** (v53, the author's note and video, as in SS13): usable things you can see (or
  can reach) get a thin outline, bright within reach, faint beyond (`WorldView._update_hover`,
  `GameClient.usable_at`). Since v54 (the author: "the outline must be around the object itself, not around
  the wall") it follows the thing's own shape: for a thing fitted into a wall, the pixels of its tile that
  differ from the bare wall tile, made solid, are outlined once per tile (`WorldView._tile_line`); things on
  the floor are drawn again in the outline colour a pixel out four ways under themselves; a body gets a copy
  of its figure whose shader draws only the rim. Doors, holes and ladders keep the cell's square: there the
  tile is the thing.
- **Windows and open doors are told as walls in the field of view** (v53, the author's video): a see-through
  cell in a wall whose middle is hidden used to be left to the rays, which cut a wedge out of it; now the
  wall rules (a seen face or corner) show it whole (`WorldView._draw_look`).
- **The pirates' crew stand at their posts** (v54, the author: "the probe also shows the enemy crew moving
  through their rooms"; the rest is mine). They are not characters in the world (`Player`), only places on
  the enemy's drawing (`src/server/enemy_crew.gd`): real characters would need the pirates' AI, sight and
  network for every one of them for a sight nobody stands next to. What they do counts, as in FTL, so
  watching them is worth a probe: a knocked-out system is mended only while somebody is in its room (a
  point per 15 s each, at most two), its guns charge at 60% with nobody at them, it cannot dodge with
  nobody in its cockpit and charges its jump at half speed. Order of posts: what is knocked out, the
  cockpit, what is worn, guns, shield, the rest rest. A shot that gets through into a room kills each one
  in it 30% of the time and wounds 40% (12 s lying low in the quarters); the crew count
  (`systems[ESYS_CREW]`, two points a head) follows, so the old quarters rule still holds.
- **A probe shows the crew for 20 s** (the author's yes to "about 20 s"); it can be launched again once that
  is over even if every room is known.
- **The scouting drone** (v54, the author's notebook: an intruder drone steered by hand from a monitor). It
  is a place on the enemy's drawing too, not a thing in the world: the author asked for scouting through a
  monitor, and a real flying object would bring physics, collisions and sight for little. The drone monitor
  is the fifth console of the mockup ('5', unused until now) on the bridge. 4 s to fly over, in at the
  enemy's outer door, a cell per 0.25 s, 60 s of battery, seen pirates in its room shoot it down 15% a
  second each. It shows the rooms it enters and the crew in its room and next to it. Its blast (my idea,
  asked of the author) does 2 to the system in its room through any shield and 1 to the hull: a choice
  between scouting longer and one sure hit. 20 credits at traders, one aboard at the start.
- **Ransom** (v54, mine, asked of the author): a beaten pirate that would run (not a reckless one) offers a
  ransom instead half the time: 60% of its reward and a can of fuel, 30% a prisoner for the reserve. It holds
  its fire for the 20 s the offer stands; our shot is a refusal; either way it then runs. It gives a
  peaceful end to a fight and a choice (money now, or the wreck's loot and full reward if we can stop it).
- **Fight length** (v54, the author: "balance fights so they don't go too long"). Measured with
  `tools/fightbench.gd` (a sensible gunner who stays at the console, our crew mending a device every 10 s):
  every class and temper ends in 0.5–2 minutes with the starting three lasers, before v54 as well. Fights
  drag only when nobody can fire: the gunner knocked out (the enemy holes the hull near the crew) or our guns
  broken and not mended; then a gunship or cruiser wrecks us in 3–6 minutes. So no numbers were changed for
  length beyond the crew rules and the ransom; what to do when our guns fall silent went to the author as a
  question.
- **"Щиты: нет"** on the gun console when the enemy has no shield generator (v54 fix): it showed "?" even
  though the shield line said there was none.
- **The airlock pump matches a docked ship** (v54, the author's bug note: the chamber was empty, the docked
  ship had air, and the outer door's shutter would not let him through; the pump only knew the corridor and
  space). When the floor past the outer door belongs to a docked ship with air (`ShipMap.lock_beyond`,
  `Systems.docked_air`), the pump works towards its pressure and stops within 0.05. Raising the shutter by
  hand still works, as before.
- **Hits only wound the pirates' crew; a helpless ship is boarded** (v54, the author's answers after the
  build): a hit into a room wounds each one in it 60% of the time and kills nobody (`EnemyCrew.KILL_CHANCE` 0;
  hits on the quarters still kill, as since v41: that is how a boarding party is beaten). A raider closes in and
  boards only when all our guns are silent and the engine or the jump is gone (`Derelict._raid_closes_in`,
  `Gunnery.our_guns_silent`, `Navigation.cannot_jump`); the author named "the jump drive": we have none as a
  device, so the jump counts as gone without the engine, fuel or a working sector console. 30 s to board is mine.
- **Our crew at their posts** (v55, the author's notebook and his yes to the plan; the numbers are mine). Posts
  mirror the pirates' (`src/server/stations.gd`): a post is manned by whoever stands facing its machine, so
  nothing new is drawn and players and bots man posts the same way. The controls give dodge (15%, 20% for a
  pilot by job, +5% with the engine minded); nobody there gives none, which is how every fight was before
  v55, so manning the helm is a reward, not a new penalty. The shield generator refills 25% faster when
  manned. The gun console keeps its old role (shots are fired there); a bot at it fires what is ready.
- **The pirates got +5% to hit** (`Gunnery.ENEMY_EDGE`, the author: "make it stronger a little bit") to
  balance the new dodge. `tools/fightbench.gd -- 4 0 10 [pilot]` before and after: fights still end in
  0.5–2 minutes for every class and temper, with or without a pilot (4 fights per cell, so the hull lost is
  noisy). Tests that set `enemy_hit_chance` bypass both the edge and the dodge.
- **Bots take orders from the captain, or from anybody while no captain is aboard** (the author's yes). Orders
  are standing posts (free, controls, guns, engine, shields, repair, follow), not one-off tasks, so a bot
  keeps working while the captain does other things; an order stays through a bot's death. Bots path only
  over our own ship and avoid thin air: they have no suits, and walking in space would need its own AI.
  A repair bot takes parts and patches from the hold itself (a player would have to fetch them).
- **The battle position is one choice, not steering** (my halfway version of the author's note "the engine
  moves the ship about the battlefield"; he agreed). Free flying would turn the FTL fight into another game.
  Close in is as before; at a distance both sides hit 15% less and their docking clock runs at half speed
  (not stopped, so boarders can't be avoided forever: the author agreed); on the flank we hit 15% better
  but dodge half. An 8 s manoeuvre with no dodge makes switching a cost. Far and flank need somebody at the
  controls (5 s grace) and nobody of ours outside: we would not leave a crewmate in space.
- **Boarding brings the pirates' crew to life** (v55; the author agreed our boarding on 2026-10-15). Their
  crew stay cells of the drawing (cheap, v54) until one of ours steps aboard; then each becomes a pirate
  Player where it stood (`EnemyCrew.come_to_life`), and from then on `EnemyCrew` only reads their places off
  those pirates, so the gun console, drone and mending keep working unchanged. Their count is kept in step
  by `Gunnery.crew_lost` (the pitfall in CLAUDE.md). With a boarder aboard it can't jump away and a ransom
  can't be taken (either would leave our people in space). Our boarders wreck a system by standing in its
  room (a point per 8 s), as in FTL. Our own hits into a room may wound our boarders too.
- **A captured ship is salvaged** (the author: "if we capture an alive ship we salvage it for more resources,
  more credits like reward, for now"): 150% of its reward, 2 spare parts and a can of fuel; it then stays
  alongside as a dead wreck to search. Keeping it as a second ship may come later.

- **Ship's shots fly, and land when they arrive** (v56, the author's video of FTL: "projectiles flying
  around, effects on hits, sounds on hits"). Everything about a shot is rolled when it is fired (hit or miss,
  the room or our cell, whether the shield stops it, against the shield as each earlier shot of the burst
  leaves it), so the odds are as before; what it does is put off by `Weapons.flight_ticks` (lasers 0.7 s,
  rockets 1.3 s) in `Gunnery._flying`, so the hole, the damage and the chat line come when the bolt gets
  there. Beams stay instant (they burn, they don't fly). `Gunnery.enemy_gone` drops what is still on its way.
  Tests set `Gunnery.flies = false` to keep their old checks exact; guntest checks the flight itself.
  Only-drawn randomness (where a miss flies, which cell of a room) uses `Gunnery._fx`, not the game's rng.
- **A shot is drawn in two legs** (`Gunnery._draw_ours`, `_draw_theirs`): out of the gun into space, then in
  at the other ship from the side (ours) or from space straight at the hull cell (theirs). One straight line
  from gun to target would cross our own decks (the pirate ship lies 3 cells off our airlock, our guns also
  point down), and players see 9 cells, so nobody sees both legs at once. The gun console's plan gets its
  own small packet (`S_VOLLEY`) because the console is too far from the pirate ship for `S_SHOT`'s 24 cells.
- **The ship fight is heard, through the ship** (v56). The author's rule is that a vacuum is silent; the
  author also asked that the fight be heard ("if no sound follows through battle it's not looking cool").
  So every sound of it (`S_JOLT`) goes to everyone and plays where there is air round the listener: our guns
  and blows to our hull through the frame (any deck, muffled from another), the pirate ship's bursts as
  the ship's sensors give them, 7 dB quieter. In a vacuum only the shaking is left (`WorldView._on_jolt`).
  Hits on the pirate ship were my question to the author (beeps from the console or the bursts themselves);
  his answer chose the bursts.
- **The screen shakes by whole screen pixels** (`WorldView._shake`, added to the camera after its rounding),
  so the "world on whole pixels" pitfall holds; the mask and cone cameras copy it, so light and sight stay on
  the world. A setting turns it down or off.
- **Sounds can be files** (v56, the author: the sounds made in code are not good enough and he will replace
  them). `Sounds.prepare` looks for `NAME.ogg` or `NAME.wav` in `sounds/` next to the game (and in the project
  folder), so a sound can be changed without a new build; the names are in `Sounds.NAMES` and `FIGHT_NAMES`
  and in `dist_files/sounds/README.txt`. Footsteps are softer and quieter (the author: "killing ears") with
  their own setting.
