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
  the engine shuts down, absolutely all systems stop working, but don't break. **Changed in v61** (the
  author's road plan answers): no engine *and an empty SMES* means no power, nothing breaks from it; see
  "Power and the SMES (v61)" below. `GameServer.powered()` asks `Power.on()`.
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
  (v60.1) The panel's lists are built from the game's own tables (`Items.admin_sections`, `Gear.all`,
  `Hulls.CLASSES`/`TEMPERS`, `Sectors.DEAL_NAMES`, `Director.EVENTS`), so new content appears in it without
  touching the panel; `admintest` fails if a kind of thing is missing. Gear fitted from the panel skips the
  engineer and what it replaces is gone (a test shortcut, my call); the flagships stay events, since they
  are the end of the game, not a class to pick.
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

- **The goal of the game is the pirates' flagship** (v57, the author: "a linear point in the game where we go...
  a boss fight with a big ship... win the boss, end of the game"). It waits in one sector per game,
  `Sectors.goal_of(seed)`: 3–5 rows north and the rest east, 12 jumps in all (the author: "12 jumps away
  for now is ok"). Routes are random, so a lane is laid along the goal's row and column (`Sectors.joined`):
  any path that reaches the lane reaches the goal (flagshiptest checks 300 seeds). The sector is always
  known on the chart, with an arrow at the window's edge when it is off it.
- **Two flagships, the kind hidden** (the author's two variants; "no courage to fight if you know who you
  will fight"). Kind by lot from the seed (`Flagship.kind`). Both are their own classes in `Hulls`
  (`ECLASS_BATTLESHIP`, `ECLASS_CARRIER`, weight 0, so `Shipyard.make` never rolls them) with hand-drawn
  38-wide hulls (`maps/pirate08.txt`, `pirate09.txt`) and their own tempers (no fleeing, no ransom).
- **The battleship aims** (the author: "better AI to target our engine and shield room"). `Gunnery._boss_target`:
  80% (`BOSS_AIM`) at the shield generator while it is unbroken and on, then the engine, then the guns; the
  rest at the hull. The engine is hit even when breaking it would leave no way out: the escape rule does not
  hold against bosses (the author: "you win or you lose, no other exit"), so no jump while it fights either
  (`Flagship.holds_jump`). Its numbers came from `fightbench`: at "slower" 1.6 it won every fight against our
  starting ship, 2.0 about half, 2.1 about 65% ours, 2.4 about 90% ours. I chose 2.1 with a pilot at the
  controls: a final fight that a prepared crew mostly wins and an unprepared one often loses.
- **The carrier stuns and boards** (the author: "guns that damage crew directly and a teleport to send a board
  team... knocking down crew and taking control over the ship"). Neural emitters (`Weapons.NEURAL`, enemy only)
  stun a room by 40 health without wounds, down to −10 (`Gunnery.STUN_FLOOR`) so a stun never kills by itself.
  The teleporter is a seventh enemy system (`Net.ESYS_TELEPORT`), only on the carrier, so it can be shot out
  like FTL's. Every 40 s, 2 boarders onto our bridge (8 in all, at most 4 aboard): the bridge because taking
  control of the ship means its controls. They hold it (`Player.hold`). Capture (the author: "all crew are
  down and nobody can resist") is every non-pirate down for 10 s while its boarders are aboard
  (`Flagship._watch_crew`), and ends the campaign (`Net.OVER_CAPTURED`). fightbench cannot show its danger:
  its guns do little to the hull; its threat is the stun and the boarders, which need real people.
- **The flagship grows with our gear** (the author agreed to my suggestion, notebook page1016-08). For each
  mounted gun other than the plain laser (`Shipyard.upgrades`; spares in the cargo don't count, we have only 3
  mounts) it takes one more from its `extra` list, up to 3.
- **After the win the voyage goes on** (the author: "you can roam around after we kill the flagship").
  `GameServer.won` is saved with the campaign and sent in `S_CAMPAIGN`; the flagship does not come again;
  the victory panel shows only to those who were there (not to someone joining later).

- **Gun tiers are hidden; a tier is a different named gun** (v58, the author's tiers plan: answers on the
  "Spacer Tier Questions" page, summary in the project's `plans/tiers-plan.md`). `Weapons.INFO` gives every
  gun a `tier`, a `kind` of parts and the `next` gun of its line; the tier is never shown, so players learn
  guns by name, look (`FightFx`, `EnemyPlan`) and sound (`Sounds.GUN_*`). Every kind has a gun in each tier;
  the gaps were filled with new named guns (Phoenix, Storm, Devastator, Reaper, Hammer). Prices follow his
  ×1 / ×2.5 / ×5 by tier, and tier 3 costs one more power than tier 2 of its line. The rapid laser and the
  ion cannon moved: the rapid laser is tier 1, the ion cannon tier 2, so the first pirate ships are a bit
  weaker than in v57 (told to the author). Enemy beams stay out of pirate pools (their AI has no beam aim).
- **A gun's state lives in its item id** (u8): plain guns `ITEM_GUN + w` (and `ITEM_GUN_MORE` past 10),
  a tier 3 gun with its effect `ITEM_GUN_FX + FX_GUNS.find(w) * 5 + fx - 1`, a damaged one
  `ITEM_GUN_DAMAGED + w` (`Weapons.item_of`, `of_item`). So the store, the floor, trading and saves needed no
  new fields; `Items.INFO` is built from `BASE` plus generated gun entries. Only the effect of a mounted gun
  needs its own field (`Ship.mount_fx`).
- **Tier 3 effects** (the author: rolled per gun, shown on its card, no fire): pierce (the shield counts 30
  lower), stun, twice (a third of volleys), knock (2 s out), tear (an extra hole). Rolled whenever a tier 3
  gun comes into being: on a pirate ship, at a trader, from loot, from mending or upgrading at the workbench.
- **Tiers come by distance, little by little** (the author's T5): `Weapons.tiers_for`. 0–3 jumps all tier 1;
  4–7 at most one tier 2 (50% of ships); 8+ up to half tier 2, 15% of those tier 3. The flagship's guns are
  tier 3 and it grows by half of our tier points (`Shipyard.upgrades`, replacing v57's one gun per non-laser).
- **Kinetic guns** (the author's notebook page1016-03 and W1–W7): a shield takes 1 off each shell and wears by
  15, so the 1-damage autocannon only wears a shield and the Hammer goes through with 3; the railgun passes any
  shield and pierces a second room; armour ricochets them. Only pirate ships have armour in v58 (by class);
  ours comes with the armour plating gear in v59. Shells are cargo ammo like rockets.
- **Point defence has its own mount** (the author's R12: not a gun mount). `Net.GUARD_MOUNT` in the gun
  console's packets; no map cell, so it cannot break (my call; the plan's "weak to hull" is left for v59 with
  armour). 60% to shoot down a rocket, 5 s recharge; on pirate ships from 4 jumps by class chance; theirs
  also shoots at our drone flying in.
- **Gun drops are rare** (the author's D1–D8): a wreck 30%, a captured ship always, 10% a tier higher, 40%
  damaged; derelicts 25% (60% damaged). The gun lies on the floor and is carried home by hand through the
  airlock (no two-person carry yet). The flagship drops the unique Nova (the author's "BFG"): never sold, can't
  be taken apart.
- **Traders deal in different things** (the author's S1–S4, R9): arms dealer, junk dealer, black market, by
  lot per sector (`Sectors.deal_at`); every trader within 2 jumps of the start is an arms dealer (my addition,
  so an early game is never gunless). One of each gun per trader (`Supplies.bought`), and anything sold can be
  bought back at the price paid (`Supplies.sold`, the author's misclick guard). Both are saved.
- **The workbench is engineers only** (the author picked it on the decision card in the v58 thread). It works
  on guns in the supply locker, not in the hands, because ship guns are cargo that can't be taken from the
  locker; parts and spare parts come from the locker too. Times 6 / 10 / 15 s, quicker with the repair skill;
  the work goes on by itself while the engineer stays (`Workshop.update`, progress through `Player.work`).
  No power and no breakdowns: it is a bench of tools.
- **Gear: systems with tiers plus two module slots** (v59, the author's G2 "both", G3 B, R6 "a module in a
  crate"; `src/shared/gear.gd`, `src/server/outfit.gd`). Four systems (shield generator, reactor, engine,
  sensors) have a tier kept in `Ship.gear`; tier 1 is built in and leaves nothing when replaced. Armour, the
  focusing array and the phase drive are modules in the bay's 2 slots (`Ship.modules`), one of each sort. A crate
  is a plain u8 thing (`Net.ITEM_GEAR + g`), so trade, floor, locker and saves needed no new fields. The reactor
  and the engine both install at the engine because the ship has no separate reactor machine (several reactors
  is a later question round: it breaks the one-engine rule). Sensors install at a holomap (the nearest thing to
  a sensor machine the ship has).
- **Only engineers install gear** (my default, asked the author; it extends his workbench pick). 10 s to install,
  5 s to take a module out, halved at most by the repair skill; it reuses `Repairs` work progress, so a broken
  machine is mended first and hover hints come from the same `can()` on both sides (`GameClient.gear_here`).
- **The middle shield tier refills faster instead of a bigger pool** (my call, asked the author): 2.5 → 3.5 →
  4.5 a second. A bigger pool would break the 50-point "stopped" rule all weapons are balanced on. The top
  generator stops rockets, so it replaces the shield hardening (nobody sells that any more; a saved ship that
  bought it keeps it).
- **Reactor 8 / 10 / 12, engine dodge +5 / +10% while someone flies, jumps ¾ / ½ charge, ¼ / ½ free jumps,
  sensors 7 / 4 / 2.5 s and the top one shows pirate guns charging** (my numbers; the plan named the effects).
  A weaker reactor going in cuts guns from the last mount, then the point defence, then the shield.
- **Armour on our ship** (deferred from v58): a hit takes 15/30/45% less off the hull, 15/30/45% of holes don't
  happen, 10/20/30% of kinetic shells ricochet (as the pirates' armour). No rng is drawn without armour, so old
  tests and fights replay the same.
- **The focusing array is the author's "mirror system" note** (page1016-01; my advice there was a volley bonus,
  and he took the focusing array in G10): lasers fired in one volley at one room count the shield 45 weaker per
  extra laser. Not for a volley aimed "anywhere": they would not land in one room.
- **The phase drive replaces the cloak** (the author's G15/R7): the battle position changes at once and
  "behind them" (+25% our hits, −20% theirs, my numbers) opens; 60 s recharge, no fuel. Behind them is reached
  only by phase, so the manoeuvre rules of v55 stay as they were.
- **Gear in loot and at traders** (the author's S1 B: "4 guns + 2 modules"; D2 30%): half of the rare wreck and
  derelict finds are a crate instead of a gun (`Gunnery.WRECK_GEAR`, `Derelict.DERELICT_GEAR`), so guns don't get
  rarer per wreck in total but each kind does. Arms dealer 1–2 crates, black market 1 a tier higher at ×1.5,
  junk dealer 1 at its 20% discount.
- **The flagship grows with our gear at half its tier points** (my default, asked the author): as +2 hull and a
  10% quicker shield per step, not more guns, so gear makes the boss tougher but not deadlier.
- **Gunners are a bonus, not a need** (v60, the author's W1): a manned mount charges 25% faster, up to 50% with
  gunnery skill, so a small crew still fights at full rate from the console (`Mounts.pace`, `Gunnery` charge).
  Firing from the console adds up to +5% to hit with gunnery (`Gunnery.GUNNER_HIT`).
- **Guns are mounted by hand; the console orders** (v60, the author's N1 "bots take guns from storage and mount
  them", A1 on the question page). The point defence keeps its console mount (it has no place in the hull).
  The cost, told to the author: a lone player with no bots walks to the mount. The server never changes a
  player's hand slot (it is not sent to the client); only bots' (`Mounts`, `Stations._at_mount`).
- **No shell crates to carry to kinetic guns** (my advice on A2, the author agreed): it would make kinetic the
  only gun that needs a person and a small crew could not use it mid-fight.
- **Bots walk to the locker for supplies** (v60): they no longer take parts and patches from the hold at a
  distance. A bot fetches a suit if it has none, turns its supply on in air under 80%, fills its tank under 35%
  (to 95%, kept as the task until full so replanning does not stop it at 36%) and lies in an autodoc under 40
  health until 90 (`Stations`).
- **The crew is kept full by bots** (the author's word, 2026-10-18: "if people join the game they take place of
  a bot, if they leave, bot takes their place"). `GameServer.crew_size` = bots asked for + 1 (the host). A joining
  player beyond it removes a bot (free ones first, its things into the locker); a living player leaving adds one.
  Dead players are not replaced, so bodies and the reserve keep their meaning (`Crew._bot_makes_way`,
  `_bot_takes_over`).
- **The autodoc heals, never revives** (v60, the author's S1; bodies stay): 3 health a second (A4), doubled
  while somebody tends it, wounds first. The scanner only reports for now: groundwork for complex health and
  cryo capsules (`Medbay`). Two autodocs and the scanner went on the existing upper-deck medbay wall (A5).
- **Blast doors from any holomap** (v60, A6, A7): our people pass (`Net.ACCESS_OURS`, given to every job and
  bot), pirates cut 12 s and leave the door jammed; no power, no lock, like every lock aboard (`Blast`,
  `Doors.blocks`, checked in `Mover.step` so both sides agree).
- **Ammo from spare parts** (v60, A8): 1 part = 3 shells, 2 rockets or 1 EMP rocket, 6 s at the workbench.
- **Point defence also shoots slow shells, at 30%** (v60, my number; rockets stay 60%). The railgun's slug is too
  quick (`Weapons.guard_chance`).
- **Piloting is the only new skill** (v60, A9): the pilot's own, worth up to +10% dodge (a pilot by job starts at
  50, so the old 20% stays). It grows with each enemy volley dodged at the controls.

### Power and the SMES (v61)
- **The rule** (the author, road plan): no engine and an empty SMES = no power, nothing breaks. Things with power
  ask `Power.at(cell)` when they sit on the bridge (the backup may keep them going), else `GameServer.powered()`.
- **The SMES loses its whole charge when hit** (the author's P7 correction). It is a machine in `Ship.broken`.
- **Numbers** (my picks V1-V4, the author's P2/P4): the ship's own draw 4, charging from the reactor's spare power
  only (never taking from a gun), 6 a second, 2160 units (3 minutes of the whole armed ship, 12 a second), starts
  full with charging and output on and output 12, a boost of up to +3 for guns and shield while the engine runs.
- **Out of a fight the guns and the shield draw nothing** (my call while building): `Gunnery.power_used` counts armed
  guns all the time, and with the reactor full of guns the SMES would never charge. So `Power._load` counts them only
  in a fight; with the engine out an idle ship lasts 9 minutes, a fighting one 3 (P4).
- **A dark ship keeps its guns armed** (`Power.budget` returns the reactor when dark): nothing charges then anyway,
  and disarming everything would be one more chore after the engine is mended.
- **A power glitch is an engine stall** (V7): `Ship.power_out_until`; the SMES carries the ship through it.
- **Bridge backup SMES** (P3, V6): 360 units, keeps the bridge room's light and consoles (`ShipMap.on_backup`, the
  room `Q` faces) about 6 minutes. No jump without the engine (my correction of my own P3 note).
- **Pirates aim at the SMES** like the shield generator (V8); the battleship goes for it right after the engine.
- **Coils as gear** (P8, V9): `Gear.SYS_COILS`, ×1.5/+2 and ×2/+4, at the arms dealer and black market, in wrecks.
- **No cables** (P9). The terminal (P5) is the SMES's own and works dark; the power monitor (P6) is its lower half
  and on the holomap (V10).
- **Ion storm** (K16, V11-V13): a sector kind taken from a third of the quiet ones; half reactor; a surge every
  40-70 s puts out a gun, the shield, or an SMES for 10 s, never the engine or a console (the escape rule). In a
  storm a pirate's guns charge 1.5x slower, its shield refills at half pace and surges hit it too (`Hazards`).
- **Every hazard hits the enemy** (the author): meteors strike the pirate ship as they strike us (1 hull, 1 wear).
- **Pirates come in hazards as often as in quiet space** (V14).
- **Hull mending from outside** (moved from v60, V15/V16): +10 a patch, 10 s, up to full; bots on «Работы» go
  below 80% when there is nothing to mend aboard and no fight, one at a time, never in a fight (`Outside`).

### Enemies (v62)
Built on my picks (all "A") on the question page https://claude.ai/artifact/VCN8eFSoSqhm1E52mYTwrN, unanswered at
build time; change them if the author answers otherwise.
- **The drone ship is a fifth class, not a temper** (D1): `Hulls` class "drone" with its own temper `machine` (never
  rolled for crewed ships). `Gunnery.crewless`: `EnemyCrew.manned` is always true, no `_plan`, and its "crew"
  (`ESYS_CREW` strength) are 2 guard robots posted at the core and the guns. It has no cockpit, quarters or jump drive
  rooms; helm and jump keep a strength so the old code paths stay whole, but nothing aims at them.
- **A drone ship is taken only by wrecking its core by hand** (D3): its guards can be killed, but `_settle` waits for
  `systems[ESYS_DRONES] == 0` while ours are aboard. Wrecked from outside it is a dead hulk (no survivors, robot bodies).
  No air inside it (`Derelict.pirates_come`), so boarding it needs suits.
- **Assault drones are Players** (`Pirates.spawn_robot`: pirate + robot, no suit, `Player.robot` breathes nothing),
  cut in like a boarding party (`Pirates.cut_in`, split out of `board`), 2 at most, first at 20 s, every 35 s, shot
  down by our charged point defence 60% (D2). They are not counted in its crew: they are machines it carries.
- **Teleporters** (B1): rolled from 8 jumps for raiders/gunships/cruisers, only when the hull has a room to spare
  (6-room hulls lost the teleporter with a shield). `Gunnery.crew_sent` takes the teleported crew out of every count
  (`ESYS_CREW`, `Derelict._pirates_party`, `EnemyCrew.keep`) so the v54 pitfall holds. The teleporter post moved
  before the shield post so a small crew mans it.
- **Suitless boarders only by docking or teleport** (B2/B3): cutting through the hull means vacuum, so they wear
  suits. Heavy stormtroopers have `Player.toughness` 0.5 (Combat.hurt multiplies); no suit, so venting works (B4).
- **Bombs are their own class** (`Weapons.CLASS_BOMB`, G1) using rockets as ammunition: they skip `_hit_chance`
  (a flat 90%: dodge does not apply to a teleport), the shield and point defence. Damage goes to the room's system,
  not the hull (except Thermite's 1). `crew` = the chance each one in the room is wounded, `kill` kills one.
  Weapon ids 23+ map to items from `ITEM_GUN_LATE` (200): `ITEM_GUN_MORE + 23` would have hit the shell's id.
- **Shrapnel** (G2) is a kinetic gun with `area`: half its fragments land in a room beside (rooms within 2 cells
  of each other, `Gunnery._beside`). Each wounds everyone where it lands.
- **Pirates carry bombs from tier 2** (G3): gunships and cruisers have them in their pools; a pirate bomb lands where
  `_enemy_target` aims, or where our people are.
- **Flagship phase two** (F1, the author's K21): at a third of its hull, once: every system mended, shield full,
  battleship guns ×1.3 and assault drones, carrier teleport every 25 s, 3 at a time, +4 troops (`Flagship.phase_two`).
- **Passive modules** (P1, the author's K2 "no respirators"): jammer, welder, salvage arm, auto-loader, tier 2 each,
  prices 100-120. The bay's extender (P2, K3) is a crate that is used up (`ship.modules.append`), only sold at stations,
  which got a tiny shop at the locker (`Supplies.offers` for `Sectors.STATION`).
- **Security robots** (R1, the author's K11): `Player.ally` (not crew, not pirate), moved by `Pirates.think` with
  the sides turned (`Pirates.foe`). Up to 2, toughness 1.4, set down on a cell beside its carrier; a save puts them
  back into the locker. Every check that counts the crew skips `ally` too (new pitfall).
- **Hold fire past a friend** (2026-10-19, mine, found by a flaky enemytest check): a bullet hits whoever it meets
  first, and `Pirates.think` shot without looking, so our robot emptied magazines into the crewman beside it and
  pirates shot each other. `Pirates._friend_in_way` stops the shot when one of its own side stands within
  `FRIEND_CLEAR` (0.8 cells: the hit radius 0.45 plus about half the aim spread) of the line short of the target;
  it then walks toward the target, which usually clears the line.

### The road and its story (v63)

Built on my picks (all "A") from the question page https://claude.ai/artifact/LJnEaFStDXqbZFq1xWPcQZ (S1..S17;
no answers when it was built). Change any of these if he answers otherwise.
- **The road plan's v63 was split** (S1): v63 = comms console, text events, quests, missions, SOS, dry-fuel visitors,
  food and hydroponics, cryosleep, the roaming growing flagship, the easy and hard modes. The cluster map (his 19 "A"
  answers), its regions, places inside a system with C6's secrets, and the pirate hunters are v64: they change how
  space is laid out, and events/quests were written to sit on it (a target is a sector cell; a cluster system can
  take the same role).
- **Calls come through one console** (S2), on the bridge where a window was (`K`): one place for the story, as FTL's
  event window, but in the world, so somebody has to walk there. Anyone answers; nobody answering in 90 s takes a plain
  answer (S3), so a crew busy elsewhere is not stuck. Never during a fight; one at a time.
- **35% of quiet arrivals bring a call** (S4); meteors and the storm have only the swarm/container/jellyfish/toll ones.
- **Blue answers** (S5, FTL's): a job held by anyone alive aboard, bots included (bots fill every slot, so most jobs are
  aboard most of the time; a dead doctor closes the doctor's answers), a skill of 70, or a thing in the locker that
  is not used up. Paid answers are grey when the ship cannot pay. Blue answers always turn out well.
- **Quests have no time limit** (S6) and at most 3 at once; targets are 2–4 jumps away (6 if nothing fits), worked
  out from `Sectors.kind_at` over the whole of space, not only the chart's window. Cargo is a real crate in the locker
  (losing it fails the quest); the bounty's pirate is a rolled raid with a name; the black box lies aboard the derelict
  of its sector (placed once, at `Derelict._arrive`; kept like any loot after) and counts when put into the locker
  (`Story._boxes`, once a second). A bounty paid off by ransom counts as beaten (it surrendered); one that escapes,
  or that we jump away from, is lost.
- **The chapter is two missions** (S7): find the convoy's log (3–6 jumps out), then catch the courier (a gunship,
  towards the goal) for the flagship's codes: all its rooms shown and one step of growth off. The courier that gets
  away is found again (the main story must not be lost for good).
- **SOS sectors** (S8) are an overlay on calm sectors (`Story.sos_at`, a hash of the seed and the cell, 15%), so
  `Sectors.kind_at` and older saves stay as they were. Answered ones are saved by key. Odds: 40/30/30 good/salvage/trap;
  the guard's blue answer sees the trap.
- **Out of fuel** (S9, the author's R8): after the old 2 minutes, 70% a passing ship calls (a trader selling 2 cans
  for 20, or giving 1 for nothing; kind people giving 2), 30% the old drifting can. The trader's free can is also the
  unanswered default, so there is still no dead end.
- **Food** (S10): one ration per two crew per jump, bots included (they stand for people), the reserve not
  (cryosleep). Start 16, price 3. Hunger lowers the health ceiling (`Garden.hunger`, passed to `Vitals.advance` with the
  wounds) by 0.1/s down to 30, never lower: the rule "no two obstacles at once" (hunger never kills, it only weakens
  for the next fight; v71, the author's L1: it now slows after 10 min and kills after a long time, see "Upkeep"). It goes back at 1/s once there is food.
- **Hydroponics** (S11, his notebook note page1016-04): 4 trays, 4 bought plants and 2 hybrids, traits by mutation
  (rich, early, choice), hybrids from ripe neighbours (35%). Harvests go straight to the locker (carrying rations by
  hand would only be walking); planting with empty hands takes the best seed from the locker so bots can do it too.
  Tending every 60–90 s keeps somebody busy between fights; neglect halves growth and withers after 5 min, so a
  crew that ignores it loses only the seed. Mushrooms grow without power (something to eat when dark).
- **Cryosleep** (S12): 4 pods in the quarters; the one from the reserve wakes in front of a pod with power. It explains
  why the reserve eats nothing.
- **The flagship roams** (S13, the author's R7): it wakes when we come within 2 jumps of the goal (before that it would
  only be a far dot), roams that area every 90 s along routes, leaning half the time towards us; it can step into our
  sector with a 20 s warning (time to jump: no fight starts without a way out until it is actually out). Its growth
  clock (S14) runs from waking, even while we are away, every 3 min (2 on hard), 4 steps in his order: faster guns
  (×0.8 charge), shield (×1.5 refill and +1 system strength), boarders (+4; the battleship gets a teleporter, so
  `Flagship._teleport_tick` runs for any boss with one), point defence. The clock stops in its fight. "Ask how fast":
  these numbers are on the question page (S14).
- **Modes** (S15, the author's R9 "easier mode"): picked in the menu for a new campaign. Easy keeps the voyage when the
  hull breaks, at 50 of its top strength each time (`Ship.hull_max`, 200 → 50, then the end): mistakes cost but do
  not end the evening. Hard: no cautious tempers, +1 boarder, 75% pirate rewards, faster flagship growth (S16).
- **Hunger and the easy mode never stack into a dead end**: the easy mode does not touch food; hunger never kills.
- **Admin** (S17): a call by name, the flagship's growth step, every tray ripe.
- **Text is server data** (`src/server/tales.gd`): one table, so adding an event needs no code. Effects are a small
  closed set (`Story._apply`).


### The cluster map, places and hunters (v64)

The author answered "A" to all 19 cluster questions (https://claude.ai/artifact/Q3XhoTfZTiM6CqztJkmmkE, C1..C19)
and to all 11 of my follow-ups (https://claude.ai/artifact/UBEtPDJuG7WS7nkqpkhVqN, V1..V11).
- **One cluster at a time, laid on cells** (`Sectors.build`): a cluster is a 5×4 grid of cells starting at column
  `6 * depth`, so no two clusters of a game share a cell and everything keyed by a cell (`Sectors.key`: `been`, the
  derelict's leftovers, a trader's buy-backs, SOS marks) kept working unchanged. What a cluster holds follows from the
  seed, its depth and the cell the ship came in at (`Road.entry`): only those are saved. The old infinite grid
  (`kind_at`, the 7×5 window) is gone.
- **Lanes**: two random paths from the entry to the two exits, filled up to 10–14 systems (16 with 5+ players, C17),
  then a tree, 40% extra lanes between neighbours and 15% diagonals. Every system is reachable (spacetest checks 1200
  clusters).
- **Guarantees**: a trader and a derelict in every cluster (quests need a derelict), a station in all but the dead
  zone, a trader within 2 jumps of the first start (the arms-dealer rule of v58 still holds near the start). Picked by
  turning a quiet system first, then meteors or a derelict, an ion storm last; the flagship is placed before them so it
  can't overwrite one.
- **Exits**: one on the top half, one on the bottom half of the far column; their cluster kinds differ (C9). The long
  jump costs 2 cans and charges 1.5× longer (C11): leaving is a decision, not a click. `Net`/`Sectors.EXIT_JUMP` (254)
  is the jump target for it, so the old jump packet carries it.
- **Flagship's cluster (V1)**: its exits are locked by its jammer until it is beaten (his comment: "U cannot leave,
  jummer is here"). That is the one lock: inside the cluster you can always jump, so the rule "while a console works
  there is a way to escape" still holds; the boss fight itself keeps v57's "no exit". It wakes on entering its cluster
  and roams all of it (V2), never into a station's system; it is never at an exit and avoids ion storms.
  (Fix, found by a flaky storytest) If its only lane leads to a station it slips past to the systems beyond,
  rather than sitting in that dead end for the whole game.
- (Fix, found by the playthrough simulator) The long jump with quest cargo aboard read the old system's index
  in the new cluster (a script error that cut `Story.left_cluster` short): `Road.next_cluster` now sets the ship's
  system before the story is told.
- (Fix, found by the playthrough simulator) Hunger took up to 70 off the health a person can recover to, on top of
  wounds, so a starving crewman with 20+ wounds who got knocked out could never come round (the wake-up line is 10),
  and with nobody to carry him to the autodoc the game never ended. `Garden.hunger_of` now takes off at most what
  leaves 30 above the wounds, the same floor the hunger keeps anyway; heavy wounds still need treatment.
- **Danger by level** (C13): `far_from_start` now returns `depth*4 + column/2`, so each cluster is 4 steps harder and
  everything that read "distance from the start" (pirate classes, loot tiers, trader stock, gear tiers) follows.
- **Cluster kinds** (C12): weights per kind (`SYSTEM_WEIGHTS`), a storm band of 3–5 storms (`_patch`, a breadth-first
  patch from a random system), dead zones with no station and stations turned to derelicts. Nebulae (C14, V10) are an
  overlay over 2–4 systems: they blind the chart and the sensors, halve pirate events, and hunters wander.
- **Places (C6, V3–V5, his notebook page1016-07)**: rolled per system from the seed (`Sectors.places_of`), at least
  25 from where a jump lands (an ambush 50) so nothing happens on arrival. Hidden until the sensors are within 35/50/70
  (a fifth to a third of the system's width); an ambush is always seen (a fight you choose). The abandoned ship reuses
  the derelict code (`Derelict.update` asks `Road.at_wreck`). Mines (1 in 5 containers) and survivors (1 in 4 bodies)
  are V4. Found and taken places are saved by `key*8 + index`.
- **Hunters (C15, V6–V8)**: first after 5 min, then every 4, at most 3 (4 with a big crew, 2 in the flagship's cluster,
  where the flagship is the pressure), one lane per 75 s, never into a station's system (V7). A hunter is a pirate ship
  3 steps of danger harder, of the biggest classes that level allows, with its own temper `Net.TEMPER_HUNTER`
  (aggressive, V8). Hunters come only while the eventer is on (`director.auto`), so tests stay quiet.
- **Quests stay inside the cluster (V9)**: targets are systems of this cluster (nearer or further when none is 2–4
  away); leaving fails side quests, and a mission under way is set anew in the next cluster. The first mission is
  offered from level 3 to 11 (the end of the first cluster through the third).
- **Old saves (C19, V11)**: a save without "road" goes on at the start of a fresh first cluster with ship, crew,
  locker, money, the chapter and the codes; visited marks and side quests are reset; the flagship goes back to sleep.
- **The chart (C16)**: the cluster view plus a road tab, drawn in `BridgeView`; what is known comes from the server
  (`S_ROAD`), so the client cannot peek at unknown systems' kinds (it still has them in the cluster packet, as before).
- **A pirate crossing over during our boarding** (the CI thread's find, the author's "yes"): `EnemyCrew._read_world` counts
  those gone from its crew alive and off their ship (`crossed`); `Gunnery.crew_lost` then says it crossed over instead of
  "killed". It still leaves the enemy's crew count (it is a boarder aboard ours, counted by `Pirates.aboard`).

### Storage window fixes (v65)

- **Tabs, not folding sections** (my pick, asked at https://claude.ai/artifact/SwbHwmKZcdbPV1yVFB8VsK): seven tabs fit
  1280×720 and keep the window one size; folding sections would change its height with every click. «Всё» stays first.
- **Width**: 10 cards a row (`PER_ROW`); a group longer than that wraps, so the window never grows past ~870 px. The
  cards' area is as high as the window allows (400 px at most, 220 at least).
- **«Всё» hides ship gear at ×0**: 19 empty cards were most of the screen. The Модули tab shows every kind, as a catalogue.
- **Refill amounts**: the starting stock where there is one; ship gear, seeds and the black box 1 each, security robots 2
  (as many as may stand aboard); ship guns 1, ammunition, parts and quest cargo 10. Quest things are included because
  the author asked for "everything"; a black box can finish a quest at once (admin only).
- **Seed names**: `Items.name_of` had no case for seeds (their name lives in `Plants`), so it read a missing "name"
  and showed "<null>" in the locker, the trader and the hands.

### Fixes found by the game simulator (for v66)

- **Respawn away from boarders** (the author's pick on 2026-10-19, "Safe spawn"): a bot came back on a spawn tile beside a
  boarder and was shot down the same second (two pistol hits, with starving crew capped at 30 health).
  `Crew.spawn_point` now skips free tiles with a living pirate in the same room or within `SPAWN_SAFE` (6) tiles, and if
  all are watched takes the least watched (risk = sum of 1/(1+distance)). The rng draw is unchanged, so with no
  pirates aboard the tile picked is the same as before.
- **Undocking from a raider that boarded sends it away** (my call, a bug): `_pirates_board` left `raid` set, so after the
  crew undocked it stayed alongside, the fight went on, and with our guns still silent it docked again 30 s later with a
  full new party (careful-06: 12 boardings by one hunter). Boarding now clears `raid`, so it behaves like the boarding
  ship, which MECHANICS already described: undocked, it leaves.
- **Hunters slow down each time we escape them** (the author's pick on 2026-10-19, "Slower each time"; my recommendation was
  "give up after 3 escapes"): in the simulator one hunter attacked up to 10 times in a game because the script captain
  always jumped away, and it caught up again ~95 s later every time. Now each hunter counts how often we escaped it
  (`escaped`, kept in saves) and its lane step is `HUNTER_STEP * (1 + HUNTER_SLOWER * escaped)`, `HUNTER_SLOWER` 0.5.
  The warning (20 s) is unchanged.

### Bots and pirates at the airlock (v66, the author's note "feels like bots cannot do it")

- **What was wrong** (found by `tools/airlocktest.gd`): bot routes skipped any door whose shutter was down, and an
  airlock chamber that differs from its side always has one down, so a bot in an emptied chamber stood at the inner door
  forever («не может пройти»); the follow order only worked aboard our own ship, so bots never followed anyone out; pirates
  could not cross space at all and also stopped at a downed shutter.
- **A button by each airlock door** (the author's answer to L1 at https://claude.ai/artifact/KuZruvE1aMGdyMBR7yCLLK: "need
  buttons on the space side and inside the ship"): no new tile; the door itself is the button. A press of E on a shut
  airlock door held by its shutter (`Repairs.press` → `Systems.call_lock`) runs the pump the way that door needs:
  `_way_through` gives in for the inner door, out for the outer one, or the docked ship's pressure. Not at the inner door
  while a ship with air is docked (the pump only matches the docked ship there; the shutter is raised by hand). A hold
  still forces the shutter, as before. The hint says "E: кнопка шлюза". A drawn panel can come later.
- **How a bot gets past** (`Systems.get_past`): routes may run through our airlock doors (`Systems.lock_door`). When the
  next door will not open (`lock_bars`), the bot presses its button and waits; when the pump cannot help (no power, empty
  air reserve, the docked case above) it raises the shutter by hand like a player (Repairs, 3 s). Forcing can only cost the
  chamber's air: a shutter is forced only while the chamber's other door is shut. (Before the author's answer the bot walked
  to the pump inside the chamber; the button made that, and its `Player.bot_lock`, unnecessary.)
- **A bot never overrides the interlock** (my pick L2): while the other door is merely open it waits for it to shut; while
  it is stuck open (jammed or forced) the bot waits with «не может пройти» rather than open the ship to space. Pirates
  (`ours` = false) never pump and do override it.
- **`Movement._would_vent`** lets a bot step into an airlock door whose other door is shut: only the chamber fills or empties.
- **Follow** (my pick L3, B offered: fetch a suit first): goals are the cells beside the leader anywhere walkable (a docked
  ship too) or in open space if the bot wears a suit, never a doorway, never a cell it cannot breathe in without a suit.
  `Stations._route` gets `wide` (follow, or the bot is off our ship) and `suited`; ordinary posts stay aboard.
- **Pirates** (my pick L4): `_first_step` crosses open space in a suit and treats airlock doors as passable; at one that
  will not open they force it (`think`, `using` is reset each tick).
- The pump a button runs must be our own (`on_ship` of the pump's front): `Ship.pumps` is our ship's.
- The author's other answers: L3 A (follow as built), L4 A (pirates use the airlock), L5 D (a question round on making
  every part of the game interesting comes before the next plan).

### Work and money on the road (v67, the author's "every part" answers)

Plan: `/mnt/project-files/plans/every-part-plan.md`, answers at https://claude.ai/artifact/1mLabQSBdQ7TskVPLU586r.
- **Visiting pays nothing** (the author's M1: "so people roam around and don't rush"). `Net.EXPLORE_REWARD` = 0. Money comes
  from work. To keep the first cluster alive the ship starts with **80** credits (was 30): my pick, put to him.
- **Fuel in units** (his R3 and his numbers): a tank of 1000 (`Ship.tank`, server only, sent at the end of `S_STORE`); a
  lane jump 40/35/30 by the engine's tier (`Gear.JUMP_FUEL`, his "40 35 30"), the long jump `Sectors.EXIT_FUEL` (2) times
  that; flying inside a system 0.1 a unit of distance (his "fuel per inner movement, more like STtE"; my reading, which he
  agreed to: lanes stay one price). The engine's "free jump" chance (v59) is gone: a better engine now simply burns less.
  The old can stays as an item of 100 units (12 credits, my pick) poured at the engine with E (3 s), so finds and loot keep
  working; traders also pour 100 straight into the tank for 12 (`STORE_BUY_FUEL`). Start: 600 in the tank and 2 cans.
  A station tops the tank up to 300. `Ship.can_jump()` is the one question "is there fuel for a jump".
- **Bots pour cans** (`Stations.TASK_FUEL`, `BOT_POURS_BELOW` 400): without it a crew of bots would strand the ship with
  cans in the locker. Players do it by hand.
- **Scrap** (`Salvage`, his B2: "salvage part of the ship for more resources, but no full guns"): cut by hand off a dark
  ship's walls, 8 s, a budget per ship (derelict 8 per system, wreck 8, captured 14: my numbers) so a wreck is a trip, not
  a mine. Scrap sells at 4, welds +10 onto the hull outside (his H2: the hull comes back from the crew's work; patches
  now +15), and refines into fuel.
- **No whole guns from pirate ships** (his B2): `_loot_gun` gives parts of a gun's kind (1 from a wreck at 30%, 2 from a
  capture). Derelicts' hidden guns (25%) and the battlefield's damaged gun (30%) stay: they are the "rare event".
- **Places float** (his R2: places need a crew trip outside; a tractor beam pulls small things in): `Salvage.float_out`
  puts finds in space 2–6 cells from an airlock that opens to space; an armed tractor beam brings one into the chamber
  every 5 s; a jump leaves them behind (otherwise jumping first and fetching later would undo the trip). Debris gives
  scrap, no credits.
- **Work places** (his R1: "work that pays only if you stay"): anomaly (holomap 30 s → 1–2 scan data, sold at 25),
  asteroid (ore every 12 s to one of ours outside, 4–8), gas cloud (2.5 units a second with somebody at the engine,
  150–300). Not taken on arrival; the ship must stop within `Sectors.WORK_REACH`. They take weight from the old places
  (debris 30→24, container 25→20, bodies 20→16). No gas in dead zones ("little fuel"), anomalies twice in storm belts.
- **Traders want things** (his M3): two of `Sectors.WANTS` per trader by the seed (`Sectors.wants`, packed after the road),
  paid at 1.5×; scrap, ore and data at full price otherwise; nobody sells them.
- **The refinery** (his R3: "costs more than finding or buying fuel"): 4 scrap (16 cr) or 3 ore (18 cr) → a can (12 cr).
- **The flagship grows only with time** (his O1): `Shipyard.upgrades()` and `gear_upgrades()` return 0, so buying guns
  and gear is never a trap.
- **Out of fuel** (his O2): the wait is 240 s (was 120); the passing trader's 2 cans cost 48 (double); begged, it gives a
  can one time in four; kind people and the drifting can are one in ten each. "Dry" now means "cannot jump and no can
  aboard".
- **Escaping a fight** (his O3: always possible, but it costs): `Gunnery.parting_volley` fires every pirate gun charged
  half or more as the jump lands (at once, since flying shots are dropped when a ship leaves), and `Road.escaped` brings
  the next hunter 60 s sooner. The v66 slower-hunter rule stays.
- Not in v67 (later builds in the plan): deckhand/sailor removal, injuries, alert levels, fights with goals, hunger that
  kills. The simulator's captain (`tools/playthrough.gd`) only learned to count fuel in units and pour cans; it does not
  salvage or work places yet, so its money numbers undercount a real crew.

### Fights for the whole crew (v68, the author's F1–F4, J4, E1, G3 answers)

- **The evade** (his F1: "timing, cost, cooldown"): `Stations.evade_asked`, 1.5 s (+1 s with full piloting skill),
  −0.5 off their hit chance (clamped at 5%), 40 from the SMES, 12 s rest (my numbers). It needs the engine and no manoeuvre,
  so the two pilot tools do not stack. The helm lists their gun charges so the press can be timed.
- **The power panel** (his F2): the guns', point defence's and shield's switches moved from the gun console to the main
  SMES terminal (`Power._panel`, actions from `ACT_GUARD`), so the engineer has a job in a fight. The gun console keeps the
  state as read-only text. The ship's own draw of 4 became a core of 1 plus three breakers (lights, air plant, trays), so
  `base_load()` with every breaker on is the old `BASE_LOAD` and nothing changes for a crew that never touches them.
  Engines: 2 levels × 2 energy, +5% dodge each. Overcharge +4 for 20 s, 40 s rest, 3% a second to burn the engine (the
  only breakdown besides hits that is not someone's lot; it is the crew's own risk).
- **A bot at the engine post minds the panel** (my pick, page question P1): a lone player with bots cannot be on the bridge
  and in the engine room at once, so the bot switches back on what is off (shield, guns, guard) as far as power allows. It
  never overcharges or cuts breakers: those are the player's risks.
- **Loaded mounts** (his F3: "a bonus; an empty mount still takes from the locker"): `Mounts.loaded`, 2 s a round, 4 in a
  breech, 1.3× charge while loaded, breech first, unloaded rounds go back to the locker. Rounds became carriable
  (`Items.carried_round`). Bots on «Работы» carry up to 2 in a fight (`Stations.TASK_LOAD`).
- **Fights with goals** (his F4): only raids the eventer (`PIRATE_RAID`) or a road ambush sends may roll one
  (`Gunnery.goal_next`): tests and hunters' ordinary pirates stay plain, so their credits do not move by lot. 20% cargo
  (1× the reward, the pod in an empty room, else beside any system but weapons or shield), 15% bounty (2×, weapons and
  engine down together = surrender; wrecked = nothing), 15% courier (1×, flees in 40 s instead of the usual). My numbers.
- **Alert levels** (his J4): `Stations.set_alert`. Red reuses "all to posts" and the holomap's "lock every door"; it
  locks only with power, as blast doors do. A pirate ship raises yellow by itself (my pick C1) and it drops back only if
  it was raised by itself. Calling it off frees only the bots still on the alert's order: one the captain
  ordered since keeps that order. The client dims the light by 0.3 on red and plays a chime or siren where there is air.
- **No breakdowns out of nothing** (his E1: "they should not come from nothing but create more danger"): the six fault
  events have weight 0 (the host can still fire them). `Systems.knock_on` breaks something within 6 cells of a pirate hull
  hit at 30% (45% heavy): door, shutter, air plant, console, or an engine stall if it is near. The "never two obstacles to
  escape" rule still holds through `can_break`.
- **The fight's details on the bridge only** (his G3 B): `Chat.say_bridge` sends to those in a room a bridge console faces
  (helm, gun console, chart). Everyone carries a radio, so "bridge and radio" would have changed nothing. Warnings stay
  on `say`.
- Questions on this build: https://claude.ai/artifact/BbM7SUq3yA36g4PBxrGA2q (built on my picks, all "A").

### Bug fixes and two ideas (v69, the author's notebook: 11 bugs and 2 ideas; his answers on the questions page)

- **Self-treatment** (notes "bandage/first aid kit doesn't work at all"): both worked, but `Combat._beside` took a click
  on oneself only within 0.5 of the cell's middle while the client rounds the mouse to a cell, so the corners missed.
  It now compares the rounded cell. Z with a plaster or medkit in hand treats oneself (`Combat.treat_self`, from
  `Inventory.act`). They still close wounds only (his M1 "A"): `_why_not_treated` says why nothing happened (no wounds,
  hunger, thin air) instead of silence.
- **"Cannot take bandage"**: a patch floating outside lay where the derelict docked, inside its wall.
  `Derelict._unbury` moves anything left in a non-walkable cell after `_place` to the nearest free cell (else the
  locker), and `_put` adds to what lies there instead of replacing it (that lost finds 1 time in 15).
- **The autodoc** (his M2 "A"): `Medbay.in_bed(doc, but)` picks the worst off who needs healing and skips the one
  tending, so one can stand on the bed and hold E for somebody lying there.
- **People popping in late when turning** (his video, S1 "A"): the server sent only those inside the 160° cone, so a
  turn waited a ping. `Replication.all_round` sends everyone the character could see by turning (walls still hide);
  the client already hides those behind. Cost: a hacked client could show people behind. `sighttest` pins it off.
- **Hunters and the one other-ship slot** (notes "docked, hunter not attacking", "it came back at full hp"; H1, H2 "A"):
  only one other ship fits beside ours. If nobody of ours is outside, `Derelict.cast_off` pushes the ship alongside away
  and the hunter comes; while somebody is outside it shells the hull (4 every 8 s, my numbers) so nobody is left in
  space with no ship. The "same hunter at full HP" was a second hunter already waiting in the system: it now waits
  `Road.breather` (45 s) after a fight ends. `roadtest` sets the breather to 0.
- **Wrecks stay on the chart** (note "cannot dock to the killed ship", H3 "A", and his message "make it appear on the map
  like an event ... a little further"): the wreck left as soon as the ship moved. Now it stays while the ship is within
  `WRECK_REACH` of `wreck_at`, and when the ship leaves it is kept in `Road.hulks` per system (a P_HULK place on the
  chart, saved) with its things, air and survivors; coming within reach brings it back alongside. `Road.hulk_spot` nudges
  the spot clear of the system's trader or station, places and other wrecks by `HULK_APART` (6) past both reaches,
  in rings of 4. Only a pirate wreck is kept, and only when the ship moves on (a test's `_leave` does not record one).
- **Docking on the move** (note): `dock(true)` is refused while the ship has a course or charges a jump.
- **The station worked like a trader** (note, D2 "A"): the server let every trade action through at a station while
  the client showed nothing. `Supplies.trader_here` gates selling, buying back and services; a station sells only
  what `offers()` lists (robots, the extender) and its locker screen says so.
- **Locked rooms** (note "no time to unlock the door and the airlock", D1): leaving a locked compartment is always
  free (`ShipMap.leaving`, from `access_in` per cell, checked in `Mover.step`), and a hacked lock stays broken
  (`Doors.picked`, flags bit 5, amber lamp) until mended with the repair hold. He picked "B" (airlocks in rooms of
  their own, open to all): ship02's only airlock already is one (its chamber opens on the open corridor), so there was
  nothing to redraw; my question wrongly said both lower airlocks sat in locked rooms.
- **One-press airlock** (his idea, A1 "A"): `Systems.call_lock` starts a trip (`cycles`): shut the other door, pump,
  then open the pressed door for 3 s more than usual. 40 s gives up. Buttons stay on the doors, so bots use it as before.
- **Vents** (his idea, A2: "stop while there is a hole, start again when sealed, stop at normal kPa, take air from
  storage"): `ShipMap.vents`, one per room but airlock chambers; `Systems._vents` feeds 0.012 per air step from the
  reserve up to 95%, needs power, the air plant whole and its breaker on, and skips holed rooms. `machinetest` turns
  vents off (it checks sealed rooms staying empty).
- Protocol 46 (the door flags' new bit). New test `tools/fixtest.gd` (30 scripts).
- Questions: https://claude.ai/artifact/9DBk13CrtNCfmyFPdQoL1N (all answered: "A" but D1 "B", and a comment on A2).

### People over bots (v70, the "every part interesting" plan's third step; questions page https://claude.ai/artifact/UsGtByhPuWjBu3PKWwPFVm, built on my picks)

- **Bots at half** (P1 "A"): one number, `Stations.BOT_SHARE` (0.5), through `Stations.share(p)`, applied where a post's
  help is worked out (`our_dodge`, `shield_pace`, `Mounts.pace`, `Gunnery.fire`'s aim bonus, `Medbay.tending`). Only the
  bonus is halved, never the base (a mount's 1×), so a bot is still worth having. The evade stays a person's (v68).
- **No sailor** (J1): `Crew.free_job` gives the job asked for unless another person holds it, else the first free of
  pilot, engineer, doctor, guard; all taken, the one asked for. `JOB_CREWMAN` (0) is kept in the code for "no access"
  (tests, old saves) but the menu no longer offers it.
- **Autodoc** (M1 "A"): `UNTENDED_CAP` 50: alone it keeps people alive, it does not replace the medic. Tended pace
  `1 + (TENDED - 1 + SKILL_TEND × skill) × share`. Bots lying in an untended autodoc get up at the cap (else they would
  lie there forever). Injuries mend after `FIX_SECONDS` (3) of tending.
- **Injuries** (M2 "A"): kept on `Player` (`bleeding` ticks, `leg`, `arm`, `concussed` until-tick), made in
  `Combat.injure` by the wound's cause (`CAUSE_*`: shot, pellet, blow, blast). The leg uses the haul's slow step
  (`st.slow`, already predicted by the client), so no new movement rule was needed; `Player.heal_injuries` resets it to
  the haul state. Concussion: `Systems.at_console` refuses a person (bots keep their posts, or a bot could be stuck
  for 90 s). The client gets the injuries in SEC_VITALS' flags byte (bits 1..5, bit 5 = hauling, because with a broken
  leg `pred.slow` no longer means hauling).
- **Meteors** (H1 "A"): only in a meteor stream (`Director._do("hole")` asks `Stations.meteor_seen`); micrometeorites
  elsewhere still come unseen. The volley's gap went from 1.5 s to 3.5 s, so each meteor gets its own warning.
  Ion surges (H2 "A"): `Hazards.STEER_CLEAR` 0.4 + 0.2 × skill, × share.
- **Prisoners** (G1–G3 "A"): `src/server/prisons.gd`. A prisoner is still a pirate `Player` with `prisoner` set: every
  place that counts pirates or picks a foe skips it (`Pirates.aboard`, `foe`, `EnemyCrew._alive`, `Crew._danger_at`,
  roster `KIND_PRISONER`). Brig = cells with `ACCESS_ARMORY` in `ShipMap.access_in`. The swap is a tale
  (`prisoner_swap`, effect "swap") so it rides the comms console's call machinery; it is never offered by the flagship
  or a drone ship, and refused while ours are aboard their ship (they could not leave).
- **Boarders' goals** (B1 "A"): set when a boarder comes aboard (`Pirates.give_goal`), half of them, one bomb and one
  kidnapper a party at most (a party = boarders within `PARTY_GAP` ticks). Wreckers never touch the bridge consoles and
  the engine only when `Systems.can_break("engine")` allows it: the escape rule holds. A bomb is a floor thing
  (`ITEM_BOMB`) plus `Pirates.bombs`; it cannot be picked up, only disarmed (held E, `Repairs.update` first). A
  kidnapped person is `Player.taken`: dead, hidden from every client (`Replication._characters`), and `Crew.respawn`
  leaves no body for him (the author's "bodies stay" rule is about deaths; he is not dead aboard).
- **Welder** (W1 "A"): a door flag (`Doors.welded`, bit 6) that `Doors.blocks` answers for everybody, so `Mover.step`
  and the client's prediction need nothing new; `Blast.tick` already makes pirates cut what blocks them (now also
  welds, and clears the weld). Bots' routes skip welded doors.
- **Pirates' walking** (found while testing the robber): `Pirates.think` turned only at `cd == 0`, which a walking
  character never shows (Mover.step counts down and steps in the same tick), so pirates went straight until a wall.
  It now turns at `cd <= 1`.
- Protocol 47 (new items, sounds, the stations packet's meteor bytes, the vitals flags).
- (v70, mine) Boarders force any emergency shutter in their way, as they already forced airlock doors. The 30-run
  check of the robber showed why: the hole a boarder cuts drops its room's shutters, and while the hole stays open
  the pressure keeps them down, so a robber or wrecker with a goal stood in that room for good. Forcing takes the
  same 3 s as for a person (Repairs). Our security robots do not force them (that lets air out).

### Upkeep (v71, the "every part interesting" plan's fourth step; questions page https://claude.ai/artifact/Qtp5awvEXeZn5G4rjoXVL6, built on my picks)

- **Hunger that slows and kills** (L1 "C", "and it slows down at some point"): it replaces v63's "hunger never kills".
  Measured in **seconds of starving** (`Garden.starved`), not in jumps: a crew that stops jumping must not escape it by
  standing still. `WEAK_AFTER` 600 s: everybody walks slowly, through the same `st.slow` a broken leg uses
  (`Player.slowed()`), so the client already predicts it; SEC_VITALS bit 6 tells the client, because `pred.slow`
  alone no longer means hauling. `DEADLY_AFTER` 1500 s: the 30 floor goes and health sinks 0.05/s, so out cold
  ~35 min and dead ~68 min after the food ran out. Long on purpose: hunger is a clock to watch, not a sudden death, and
  any ration in the locker stops it at once. The escape rule is untouched: hunger never blocks a jump, and traders,
  stations and the trays are always one jump away.
- **The galley** (L2 "A"): `src/server/galley.gd`, the stove `G` in the hydroponics room of `ship02` (the food room).
  It reuses the workbench's packet (`C_BENCH` with `BENCH_STEW..BROTH`) and `Player.bench` for the work in progress,
  so no new packet; `Workshop.asked/update` hand the dishes on. Dishes (`Items.DISHES`, shared with the screen) are
  locker things eaten by hand like a patch. Three effects, each a different kind of help: the stew heals over time
  (the medic's slow work), coffee is speed (`Player.pace`, applied in `Repairs._work_done`, `Combat._treat_ticks`, the
  workbench and the stove), the broth clears injuries. One effect at a time to keep it readable. Dishes are never eaten
  at jumps (rations are the ship's food, dishes are a person's): otherwise cooking would only lose rations.
  Bots do not cook: people over bots (G2).
- **Complex repairs** (H1 "A" with his comment "optional, chosen at the start; hard difficulty means more mechanics,
  not more enemy HP"): `server.complex_repairs`, set before start like the mode, saved in the campaign, told to clients
  in S_CAMPAIGN byte 17. The hard mode turns it on by default; the menu checkbox lets any mode choose (the option travels
  as "hard+plain" / "normal+complex" in the `mode=` text). Two part kinds only (a board for consoles and screens, the
  old mechanical part for everything else): three kinds would mean three trader lines and three loot lines for little
  play. `src/shared/upkeep.gd` holds the rules, so the server and the client's hints agree. **Nothing ever needs a part
  outright** (only slower: 3× without the right part, 3× more without a toolbox): a broken helm must always be mendable
  (the escape rule). The toolbox is never used up; the ship starts with 2 and engineers bring their own in complex games.
  Without complex repairs a board works as any part, so it is never dead weight.

### Bots at work and the boarders' wreck (v72, the author's two notebook notes; questions page https://claude.ai/artifact/Ht1weGfuxFTaiJXPwywy63, built on my picks)

- **Shutters** (his video: the door he raised was an emergency shutter, not the airlock): `Stations._route` skipped every
  sealed non-airlock door, so a hole behind one was never reached and the bot fell through to other work. Now `_plan`
  routes a second time with `shutters = true` only when the first way fails, the task is `TASK_MEND`, and the bot wears a
  suit with oxygen (B1 "A"); `_through_shutter` holds "use" on it (the same `Repairs` forcing a player does, 3 s up for 5 s)
  and `_forced_ahead` lets it past `Movement._would_vent` while the shutter is forced. Air lost is the price, as for a
  player; never for wandering.
- **Repairs first** (his "priority of the job: repairs always first"): `_work_goals` now asks `_mend_goals` before the
  carried gun (unless the gun fills its last free hand: a bot with no free slot could never fetch a patch and would stand
  at the hole), rounds, trays and fuel. Free bots volunteer (`_volunteers`, every `BOT_PLAN_TICKS`, staggered by slot)
  and use the same `_mend_goals`; posts stay manned (B2 "A").
- **One bot per job** (B3 "A", my idea so "a bot takes the work" means something): `Player.bot_job`, set by `_took`;
  `_repair_jobs` drops jobs held by another bot that is up. A bot that cannot reach its job lets it go.
- **Chat and log** (L1 "A", L2 "A"): `Chat.bot_log` sends `Net.S_BOTLOG` to every client (protocol 49); the same line twice
  in a row is dropped (`Player.bot_said`), so plans every 10 ticks do not spam. Only "беру ..." and "не могу добраться"
  (the latter for bots on «Работы» only) also go to chat. The client keeps 2000 lines for the crew window and appends all
  to `crew_log.txt` next to the exe (`GameClient.log_path`, user:// from the editor; headless clients write none), so the
  author can send it with a bug. Where a job is: the deck name and the nearest named thing in the same room
  (`Stations._where`).
- **Handing a job over** (his comment on L1: "if a bot cannot take the job, he passes it to the next with a spacesuit"):
  a job nobody holds is anybody's, so a suited bot takes it by itself; `_mend_goals` now looks for jobs in reach before
  fetching patches (else the suitless bot walked to the locker and the job looked taken), and `_suited_helper` only names
  the bot in the "cannot get there" line. A free bot come to mend takes from the locker only what mending wants (it used
  to pocket a fuel can it would never pour: found by `salvagetest`).
- **What next** (N1, his comment "we need to polish the game first"): v73 is polish, not fear.
- **The boarders' wreck** (his note "they need to die not to run and become part of the map where we can dock and loot"):
  `Gunnery._wrecked` calls `Derelict.becomes_wreck` for a boarding ship too, so it is kept on the chart like a raider's
  (v69). Survivors are rolled as for a raider (W1 "A": `WRECK_ALL_DEAD` 70%); the `WRECK_FUEL` can now lies aboard
  (`Derelict.drop_thing`) instead of going into the hold. A boarding ship whose crew we kill in its quarters still breaks
  off and goes unpaid (unchanged: no hull damage, it is not wrecked).


- (v72, found looking at the author's old failed CI runs) salvagetest failed 1 run in 20 on main too: a suited bot on «Работы»
  stood 90 s in a room left with no air behind its own shutters (no way out for anything but a repair), or kept picking a tray
  it had no way to. So a suited bot may raise a shutter to get **out** of a room with no air for any work (air only flows in),
  and a kind of work with no way to it is put off for 10 s (`Stations._skip`, `BOT_SKIP_TICKS`). The log tells each piece of
  work once (`_logged`) and each shutter once (`_forcing`), not on every fresh look.

### A friendlier game (v73, the author's "very friendly UI for everything"; questions page https://claude.ai/artifact/L5C4LmRshPrQehcRoQJJKS, all 24 answered)

- **The split** (Z1 "B"): v73 is fixes, using things, the screen, consoles and the bridge's alert panel; items drawn in hands,
  a `sprites/` folder, diagonal walking with 8 drawn directions (N4 "B") and a first-shift checklist are v74. His word on art:
  simple base pictures that an artist replaces, not drawn in code from scratch.
- **The airlock trap** (his words: "when pressure was same like on enemy ship, I am trying to go back to our ship and nothing
  works"): with a ship docked, the pump and the inner door's button only aimed at the docked ship's pressure, so a chamber
  already there had nothing to do and the inner door stayed held. Now a pump run has a goal (`Systems.pump_goal`): the outer
  door's way aims at the docked ship's air, the inner door's way (and the pump pressed when the chamber is already at the
  docked air) at our side's (`inside_air`, the floor past the inner door, `ShipMap.lock_inside`).
- **Hunter spam**: `Road._hunters_second` set `busy_tick` whenever anything was alongside, a wreck too, so the hunter's
  breather restarted each second and «поджидает» came every second. Only a live pirate ship counts now, and `_meet` says it
  once per hunter (`h["told"]`).
- **Pirates pacing** (the rare airlocktest failure left from v72, 1 run in ~200 on main too): a pirate kept its planned
  step for `PLAN_EVERY` (10) ticks, and steps in a chamber take 4, so near its goal it walked one cell past, turned, walked
  past again, and could pace between the airlock and space for good. `Pirates.think` now also plans again before each new
  step once it stands on a new cell (`Player.ai_plan_cell`). 600 runs clean after. A walking pirate now never stands at cd 0, so a kidnapper grabs
  at `cd <= 1` (as turning does since v70), or it walked past the one it came for.
- **The shutter "one tap"** (his note) was a hold already: `Repairs._work_done` resets on letting go. Kept; the ring now
  shows the hold.
- **Using things**: the right-click menu (U2 "A") lists only what can be done there; «Работать, пока не готово» holds E for
  the player (stops on a move key or after 30 s). A click on a usable thing diagonally next to us steps one cell to the side
  first (U5): diagonal use without diagonal walking. The E target is outlined only while the mouse is on nothing usable, so
  two outlines never show.
- **The ring** is drawn by the client from its own "use" hold and the work's length it already knows; another person's work
  is not shown (that would need a packet per worker; not asked for).
- **Hints with badges**: the server's hint texts are unchanged (tests read them); `GameScreen._badges` turns their key words
  into badges on the client, so one rule covers every hint.
- **Chat tabs and repeats** (S4 "A"): the client keeps the last 80 lines with their tab; a repeat within 60 s merges as ×N. Warnings
  that need everyone's eyes go through the new `Chat.alarm` (`Net.CHAT_ALARM`): a red banner for 4 s and a chime, as well as
  the line. Banners are server words only, plus the client's own for hull below 30% (S5 "A").
- **Interface size** (S6 "A") scales the whole HUD root (`GameScreen._fit_root`), so text grows with it; the world's zoom is
  Ctrl+wheel (H6 "B"), in whole steps to keep pixels sharp.
- **Hotbar drag** (H3 "A") is a new packet `C_SWAP` (protocol 50): the server swaps two slots and the client moves its own
  hand along (the server never sets a player's hand).
- **Consoles** (C1 "A"): one frame with a title and ✕; number keys press the numbered buttons of the gun console, the jump
  list and the locker's tabs.
- **The bridge's alert panel** (his L2 comment: "alert panel on the bridge with green, yellow and red if something is low"):
  `Look.needs` on the sector console and the ship's controls, worst first. Thresholds are mine: hull 35/70%, fuel 1 and 3
  jumps, air reserve 15/40%, food 2 jumps for everyone, SMES 15%.

### Art and walking (v74; his answers N2–N7, L1 on the v73 page, and his second-opinion answers)

- **Slant step time** (his N3 "1.4x"): ticks are whole, so `Mover.slant_span` gives 5 or 6 ticks by the tick number
  (`(straight * 14 + tick % 10) / 10`), exactly 1.4 times on average and the same on server and client.
- **No corners, no doorways on a slant** (mine, he agreed): a slant needs its target and both side cells passable. Doors
  are entered straight, so door bumps, shutters and the airlock keep their one-axis rules; a slant held at a wall slides
  along it, as in most top-down games. Hauling goes straight so the dragged body keeps following the old cell.
- **Bots and pirates walk straight in v74** (his "Okey but in the future we need make them move diagonal"): their routes
  are 4-way paths; making them 8-way is a later build.
- **E on a slant** (mine, he agreed): a fitting right beside on the wall, else the floor cell on the slant; never a door
  (a door is used facing it straight).
- **Directions 1..8** with `Mover.TURN` moved to 16; facing takes 4 bits of the look byte (light moved to 128, the old
  long-step bit dropped: the self packet carries the step's span instead).
- **The hand** (his N5; my suggestion of the existing item pictures, he agreed): the item kind in hand goes out as a 5th
  byte of `S_OUTFIT`, sent only when it changes; our own hand is drawn from the client's hand at once.
- **The sprites folder** (his N7, art note: simple base pictures an artist replaces): sheets must keep their size so frames
  keep their places; item pictures are per kind (`item_<kind>.png`), any square size. Read once, when first wanted.
- **The help book on H** (his L1, mine for the key, he agreed): H was free. Built when first opened, like console screens.
- **The first shift** (his L1): the progress is kept in options, not in the save, as it is the player's, not the ship's.
- **Bots' job hand-over** (his notebook, «беру пробоину» spam): a bot fetching a patch keeps its job reserved
  (`Stations._fetch_for`), the spot's passer-by does not count against the bot holding the job, and «беру» is said once
  per job per 30 s. A bot at a post whose consoles are all broken mends them first (`Stations._post_down`).

