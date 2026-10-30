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


### Polish (v75; his 20 answers on the page "Spacer v75 Polish", every one the recommended pick, and five notebook notes)

- **The brig** (P1 "A"): four 1-cell rooms on the upper deck under the armoury, marked in the blueprint by `@ deck x y brig`
  (a marker, not a lock: `ShipMap.brig`, `is_brig`, `brig_cells`). The armoury stays a brig too, so old habits still work.
- **When cuffs slip** (P2 "B", and his note: a prisoner in critical health got a pipe and escaped): only while awake, above
  `Prisons.WHOLE_ENOUGH` (50) health and with none of ours awake in his room (`Prisons.watched`, by `ShipMap.room_at`); the
  2-minute clock starts over whenever one of these fails, so a guard standing by is enough.
- **Prisoners need no food** (P3 "B"): they are pirates, and `Garden` already skips pirates.
- **Stuck bots** (B1 "A"): "stuck" is no new cell on this way for `STUCK_TICKS` (20 s): it catches pushing on a door,
  going back and forth and waiting on something that never comes, without knowing why. The goal and the job are avoided for
  60 s, so it tries another way or other work. Forcing the same shutter more than `FORCE_AGAIN` (2) times in 60 s is
  stuck too (his note «поднимает аварийный шлюз ×5»); only the first forcing is said in the chat.
- **Air for bots** (his note: bots broke when there was no air): a bot with nothing to do where the air is under `BOT_AIR`
  or whose tank runs low gets `TASK_AIR`, the nearest cell with air. Free bots see to it before volunteering.
- **A gunner mends its own mount** (his note): broken mounts are mended first by the gunner at them (as v74 did for post
  consoles), and a broken mount is no post to stand at.
- **One bot per doorway** (B3 "A"): `Stations._door_busy`: a bot waits while another bot is using that door (forcing the
  shutter or pressing the airlock button).
- **Only breaches aloud** (B4 "C"): the rest of «беру» lines go to the bots' tab; breaches are what everyone must act on.
- **Bots on a slant later** (B2 "B").
- **Hits** (F1 "A"): `S_HIT` (u8 kind of blood, u16 id, s16 x, y) to those within `Combat.SHOT_SEEN` on the deck; the client
  flashes the figure (0.25 s), keeps up to 400 drops (client-only, not in the world state: they cost the network nothing)
  and plays `hit`/`hit_metal`. A robot throws sparks instead of blood, and clangs.
- **Red alert light** (F3 "B"): a ColorRect on the dark layer, only when lit and aboard, 0.1 strong and pulsing; the v68
  screen-edge pulse is set to 0 (two red signals at once were too much). Green and yellow change nothing.
- **Music** (F4 "D"): made in code like the other sounds (a 16 s menu pad, an 8 s fight drone), replaceable by files. The
  drone plays in a fight, at red alert and 20 s after a pirate was seen aboard; a `Music` bus with its own slider.
- **Ambience** (F5 "A"): vent and pipe sounds near the listener every 7–16 s, a hull creak 1.8 s after a jump. Quiet
  (−6 dB and lower), as he asked footsteps to be quiet.
- **Sound kinds 10–15** were never played (the client's `SOUND_LOOK` had 10 entries): fixed on the way.
- **The run's story** (E1 "A"): `S_SUMMARY` carries ships beaten, boarders killed, credits earned (`Ship.earned`, which the
  `credits` setter counts up) and up to 20 deaths with how. Saved with the campaign.
- **The host's address** (E2 "A"): Radmin VPN gives 26.x addresses, so those go first; the copy button is in the pause menu.
- **Rejoining** (E3 "B"): already so (`saved_crew` keeps a character by name).
- **The quiet start** (E4 "A"): `Director.quiet()` for the first 5 min on easy and normal; the road's hunters wait for it
  too. Tests that need events at once set `director.quiet_start = false`.
- **The simulator first** (S1 "A"): numbers are changed only after he sees the tables. The script captain now does what a
  v67 player does between jumps: sweeps each system (a loop a quarter in from the sides) to find places, takes them, works
  anomalies at the holomap and gas clouds at the engine (not asteroids: a suit walk), cuts scrap off dark ships, fetches
  what floats outside and sells scrap, ore and data at traders; at most 6 min a system.
- **Bug-report zip** (S2 "A"): `src/client/bug_report.gd` writes `bug_reports/` next to the exe (user:// from the editor):
  the 6 newest logs, the save, the settings, the bots' log and a screenshot (taken when the pause menu opened, so it shows
  the game, not the menu).
- **Soak test** (S3 "A"): `tools/soak.sh` runs the playthrough with 7 bots campaign after campaign for 2 game hours and
  fails on a tick over 200 ms, over 1% of ticks over 50 ms, or objects or memory growing between campaigns.
- **Deep wounds kill slowly** (mine, found by the simulator: all our people lay out cold with boarders aboard, and the
  captain at −5 health could neither wake nor die, a game that never ends): unconscious with wounds of 100 or more loses
  `Vitals.DYING` (0.5) health a second, so about 3 minutes to death unless treated. Then R and the reserve work as always.
  (v76) He kept it ("in 3 minutes the character needs to die") and added: "when the player is unconscious he can choose to
  die instantly and respawn". Holding R for 2 s (a hold, so a stray press does not kill) while out cold, not merely stunned
  and not a prisoner; the death is counted «погиб от ран»; the respawn is the usual second R, from the reserve.
- **The simulator does not replace playtests** (his answer, 2026-10-20): "I need to test it myself, so the game must
  stay the same for now". The v75 tables (0 of 20 won) change no numbers until he has played.
- **Nothing public** (his answer): the repository stays private and no GitHub Release is made; builds go through the chat
  as before.

### The evening's bugs, the view and bots on a slant (v77; his answers on the page "Spacer v77 Movement and View", https://claude.ai/artifact/JFTeczxumE8CGGGcZ58vaJ)
- **The trader's money loop** (T1 "A"): a trader never sells the two things it looks for (`Supplies.offers` skips
  `wanted()`), "it needs them itself". B (sell them at 1.5×) left a shelf nobody buys from; C needed every item to remember
  where it came from. Buying back what we sold stays at the price it paid, so it makes nothing either.
- **The wreck spam on a jump**: `Derelict.update` sent a wreck away while the jump charged and `Road.at_hulk` brought it back
  the next tick. A hulk comes back only with no jump charging. The `%` in «Рядом %s» bound tighter than `+` (the name was cut
  after its first letter; the flagship drone ship's alarm had the same slip).
- **Rejoining** (R1 "A"): the same name from the same address (`ENetPacketPeer.get_remote_address`) takes the character
  at once: the old link is let go as a normal drop (`Crew.drop(peer, true)`: saved by name, no bot takes the place), then
  the usual `saved_crew` restore. B (the name alone) would let anyone take a character while its player is in the game;
  over Radmin each friend has his own address. A full server still lets the same person back in.
- **The dead ship after the rejoin**: not a drawing fault (an in-process client test showed the wreck laid in at once).
  The cause: the dropped player was no longer in the world, so `someone_outside()` let the ship jump and leave the wreck;
  he came back afloat at his saved cell. A saved character whose cell is neither on our ship nor on the ship alongside
  now comes back at the spawn point. (A gone player must not hold the ship forever, so his absence still does not count
  as "outside".)
- **The chat** (his picture): the box had room for 9 lines, but a wrapped line takes two rows, and a VBox taller than its
  rect grows down, under the input. It now grows up, and the oldest lines go until the rest fit `CHAT_ROOM` (278 px).
- **Places' hints**: the bridge said "fly to the mark to pick up" for everything; the gas cloud needs the ship still and
  somebody at the engine. Each kind says what it takes; the work places say what to do once the ship holds there.
- **SOS, the crew dead** (S1 "A"): `Derelict.sos_ship` brings a real derelict with 3 bodies (1–2 pocket things each) and
  the usual loot, not remembered per sector (`_left`), kept alongside while the ship stays within `WRECK_REACH` of where it
  came. Where no derelict can lie alongside (ship01), the old 3 parts and 15 credits.
- **The view follows the mouse** (V1 "C": a setting, the mouse at first; V2 "B": 1/3 s for half a turn; V3 "A": no slower
  backwards; V4 "A": others see it). The server already sends everyone all round (v69), so sight needs no aim from the
  client: the cone, the fan and who is hidden are the client's (`GameClient.look_way`, `Sight.sees_way`). The body's 8-way
  facing follows the eyes as TURN inputs, predicted as before, with a 6° stick past the half-way line so it does not
  flicker. `Mover.State.free_look` (inputs `LOOK_FREE`/`LOOK_WALK`, sent in the self packet) stops walking from turning
  the body; this keeps prediction exact. The flashlight still shines the 8 ways (what others see of it); the cone is smooth.
  Scripted test walks (--demo, goto, path, click, hover) look where they walk; `aim=DX,DY` points the eyes for screenshots.
- **Bots and pirates on a slant** (B1 "A"): one 8-way search for all three walkers (`Paths.first_step`, a bucket queue,
  5 for a straight step, 7 for a slant: 1.4, as a slant takes 1.4 times as long, so no zigzags). A slant needs both cells
  beside it to be cells the walker may step into and no doorway on any of the three or underfoot, as for players
  (`Mover.slant_open`). Wandering bots may pick a slant too (Mover slides along a wall if it is shut).
- **(v77.1) One turn at a time.** The mouse view sends a turn only when none is waiting to be applied
  (`GameClient.aim_at` returns while `_turn_at > pred_tick`): asking on every frame queued each turn a tick later than the
  last, and on his fast computer the queue ran away (game-breaking: no walking, no turning). The headless tests ran too few
  frames a tick to show it; eveningtest's `_mouse_spin` now drives a real client at full frame rate.
- **Left for v78** (M1 "D", Z1 "A" with "not free walking, a quarter of a tile"; C1 "B"): quarter-tile player steps, lying
  down, swapping places; and his M2 and thread words on friendly fire: "when you're almost in one tile you can shoot from
  behind your ally and not hit them, like in RimWorld" (a friend right next to the shooter is never hit).

## v78: quarter steps, lying down, friendly fire (2026-10-21)

His message: "Need your opinion about the 1/4 movement system... now we need to make it so that we can visually stop at
1/4 of a tile". Built on his v77 poll picks (M1 "D", C1 "B", his M2 words on friendly fire).
- **Quarter steps for players only** (`Mover.State.fine`, set each tick from `Player.quarters`, which `Crew` sets for a
  joining player). A step is a quarter of a tile (8 px) and takes a quarter of a whole step's ticks (`MOVE_TICKS / 4` = 1,
  `DRAG_TICKS / 4` = 2), so the speed is unchanged; a slant quarter takes `slant_span(1)`, 1 or 2 ticks, 1.4 on average.
  Bots, pirates and robots keep whole tiles: they plan by tiles (`Paths`), and quarters would only make them jitter. A bot
  that takes a player's place snaps back to its tile's centre on its first step.
- **The tile is the one under the centre** (`x, y`, with `ox, oy` in -2..1 quarters off it; -2 is on the border and
  belongs to this tile). So everything that asks `st.x, st.y` (air, doors, sight, use, bots, saves) works unchanged: my
  main reason for this shape over a free position. The tile changes half way between two centres, not at a step's start.
- **The body is a tile wide**: off centre it lies over the next tile too (`Mover.body_tiles`, 1, 2 or 4 tiles). Every
  tile it newly lies over must be passable to it, with a door pushed open first (the same checks as a whole step); lying
  over four tiles needs all four open, no doorway, one deck (as a slant step's `slant_open`). A door does not shut on a
  body half in its doorway (`Systems.update_doors`, `_door_free`).
- **Sliding into line** (`Mover._line_up`): a straight quarter refused while off line across the way slides a quarter
  towards the row (or column) the way ahead is open from, as old console games do at corners: without it a player a
  quarter off a doorway would push on the wall beside it. On a slant: the slant, then across, then up or down, then the
  two slides.
- **Network**: `S_WORLD` character records gain a byte (`Net.pack_off`: offsets and lying down; `ENT_BYTES` 8), the self
  packet gains one (`SELF_BYTES` 19; byte 18's bits: free look, fine, prone), `fx, fy` are in quarters. Protocol 54.
  Others are drawn by their quarter steps (`GameClient._apply_record` keeps 24 recent steps). Walking players send a record
  every tick instead of every 4: the benchmark's tick went from 9.9 to 12.0 ms at 32 players (of 50), nettest corrections
  stayed under 0.25% even at 210 ms ping with 5% loss.
- **A hauled body follows by whole tiles**, when the hauler's tile changes (`Movement.move`); the client's guess of it
  follows our tile too. Step sounds count tiles, not quarters.
- **Lying down** (C1 "B"): inputs `Mover.LIE`/`RISE` in the walking stream (predicted), key C (`Options` "lie"). Crawling
  takes `DRAG_TICKS` per tile (half speed). A shot passes over one lying down unless aimed within `Combat.PRONE_AIMED`
  (1 cell) of it. `place()` stands one up (ladders, respawn); being knocked out or a bot taking over too. Drawn on its side
  in its own colours.
- **Friendly fire as in RimWorld** (his M2: "shoot with friends in one place constantly, just to suppress"; thread: "a
  friend right next to the shooter is never hit"): `Combat.spared` skips one on the shooter's side within
  `FRIEND_CLOSE` (1.25 cells across and down: the next tile, a slant too, and quarters off it). Friends further on still
  get hit. Sides are `pirate` or not (our robots and bots are ours). Shots now start where the shooter is drawn
  (`place_at`), and pirates aim at where a player is drawn (`Pirates` uses `visual_pos`), or a player half a tile off its
  tile would be missed by every pirate.
- **Swapping places is left out** (my disagreement, told to him): characters already walk through one another, so there
  is nothing to swap. If he wants bodies to block (then swapping matters), that is its own question.

## v79: polish after quarter steps (2026-10-21)

His answers on the page "Spacer v79 Polish" (https://claude.ai/artifact/RMLhvSAPdwjWFUssNC8LDM): L1 "A", B1 "B", W1 "A"
with his note, V1 "A", K1 (all three old unknowns fine on his PC), Z1 "A and C without fear".

- **The lying body** (his notebook note with a video: "you look the other way for half a tile"; L1 "A"): v78 drew one
  lying low like one knocked out, always head to the right and slid back about two thirds of a tile over its tile. Now it
  is drawn from the front frame, turned so the head points along the facing (8 ways), its middle `PRONE_CENTRE` above
  where its feet would stand, so it matches the light cone. The hand's picture goes with the front frame. Knocked-out
  bodies are drawn as before.
- **Sliding past** (W1 "A" with his note "it needs to look like you slide using 1/4 of a tile"): people keep walking
  through one another (no blocking, no swapping). Only the drawing changes: two standing characters under
  `WorldView.PASS_REACH` (1 cell) apart, while either walks, are pushed apart sideways to the line between them, each up
  to a quarter of a tile, more the closer they are (`WorldView._passing`); the side is kept per pair while they overlap so
  it does not flip. Two who stopped near each other keep the push they had (no pop). Nothing on the server or the network.
- **Camera lean** (V1 "A"): with the mouse view only, `focus += _lean`, eased toward `(mouse - centre) / half screen`
  (length at most 1) × `Options.lean` tiles (0..3, 2 at first, a setting). It is worked from screen coordinates, so it
  does not feed back on itself as the camera moves. Off while a console or window is open or a scripted aim is set.
- **Bots and armed boarders** (B1 "B", against my pick "A": he wants the guard bot to fight too): a new server part
  `Defence` (`src/server/defence.gd`), asked first in `Movement.bot_think`. Noticing: `Pirates._sees` from the bot (its
  cone), or within `NEAR` 4 cells with a clear line, or a wound from a pirate (`Combat.hurt` → `hurt_by`). "Armed" = a
  pirate robot or any weapon in a pirate's slots: the unarmed are not worth running from. A known pirate is kept while it
  stands on our ship and was seen in the last `LOST_SECONDS` (45 s); `CALM_SECONDS` (8 s) after the last is gone the bot
  replans its order. Running goes to the nearest (by path) open floor ≥ `SAFE_FROM` (10) cells from every known pirate
  and outside their rooms, preferring cells within 2 of one of our people who is ≥ 6 from them; there it lies down
  (`st.prone`, which `Movement` no longer resets for a bot that `Defence.busy`). Its repair job is let go on noticing so
  another bot may take it. Not for bots following a player (the player leads), out on the hull, or in an autodoc.
- **The guard bot** fights by `Pirates.think`, as our security robots do: `Pirates.foe` treats a bot like our robots
  (fights pirates only), `_first_step` does not force shutters for it, and reloading uses `Items.ammo_of` so a shotgun
  works. Its gun comes from the supply locker (pistol first, then shotgun) with `AMMO_TAKEN` 2 magazines or boxes; it
  keeps it after. With no gun in the locker, no free slot or no way to the locker it runs like the others. Other bots never
  fight ("people over bots", v70). Crew window: two new `DOING_*` (hides, fights). Protocol 55 for those values.
- **"Not responding"** (his Task Manager picture: the game's process marked «Не отвечает», 13% GPU, the server process
  fine, all playing normally): the server is not it (a headless process has no window to hang). Most likely the OpenGL
  window waiting on vertical sync while covered or minimised, which some drivers block on for seconds; Windows then marks
  it hung. Not seen on Linux; the fix is a guess, said so to him: on focus out vsync is turned off (the 30 fps background
  limit already paces it), on focus in the setting is applied again. The export now sets the exe's product name and
  description to "Spacer" (`application/modify_resources`), so Task Manager names it.
- **Fire questions** (Z1 "C"): page "Spacer Fire Questions" (https://claude.ai/artifact/GrbXt4V21HzZUojDiYqEKk), my
  picks: FTL-like tile fire that needs air, smoke, no heat, fire from causes, extinguishers, venting and a trader's module.
  Nothing built until he answers. Fear waits for his concept ("I don't have the full concept").

## v80: the full run's bugs (2026-10-21)

He and friends played a whole campaign on v79 and left eleven bug notes in the Notebook. The question page "Spacer v80
Playthrough" (https://claude.ai/artifact/3A2HTzKTNpPbgQTuyAFFvc) asks about the fixes that change play; each is built as
my pick until he answers otherwise. Checked by `tools/fullruntest.gd`.

- **No hole on a machine** (his picture: a hole over the supply locker, E opened the locker and nobody could patch it):
  `ShipMap.hull` leaves out every wall cell with a fitting (`fitting_front`) or a gun mount. Simpler than teaching every
  "use" path to prefer the hole, and a hole on a console never made sense.
- **Bullets through space** ("in space you cannot shoot enemies"): `Combat._stops_shot` asked `walkable`, and open space
  is not walkable, so every shot stopped at the first space cell. It asks `passable` now (floor, doorway or open space);
  the flashbang's landing cell too.
- **Mounted guns left alone** ("bots take the ship's guns without an order", G1 "A"): with empty hands at a mounted gun a
  held "use" takes it down. A bot holding "use" there for something else (a repair finished, a round loaded, a hold left
  set while it ran from boarders) could do that. `Mounts.can` now refuses a bot unless the console's order for that mount
  is `WANT_DOWN`, and a bot may put up only the gun ordered there. For everybody, `Player.mended` keeps the hold that
  mended a mount from rolling on into taking its gun down: a fresh press is needed.
- **A ship alongside never flies along** (his video: a wreck stayed over the airlock while we flew, until out of reach,
  W1 "A"): a wreck leaves as soon as `ship.moving`, a derelict or SOS ship too (`want` is false while moving), and a hulk
  comes back only to a stopped ship in reach. The ship cannot move while anybody is on it or docked, so nobody is lost.
- **Somebody outside** (P1 "A"; "if a person dies in space you cannot move", "people outside are left behind and die"):
  the dead and bodies never held the ship; somebody out cold in a suit (breathing from the tank) does, and that is kept,
  but `Derelict.holds_ship` now names who and says "без сознания" (`who_outside`). The ship checked only when a course was
  set, so somebody stepping out while it flew was left behind: `Navigation.update` stops the ship (every 10 ticks) when
  anybody is outside. I could not repeat "a dead body holds the ship"; asked him to describe it if it was that.
- **Emergency light** ("the lights don't go out in a blackout", P2 "A"): his pictures were the engine failing and the SMES
  carrying the ship, which by the v61 rule keeps everything going. The client now dims the lights to `EMERGENCY_DIM`
  (0.67, a third of the light, his comment "1/3?" on P2; the red alert's is 0.3) while the power monitor's flags say the SMES carries the ship (bit 4), outside the
  backup-lit bridge. Drawing only: sight and the server's light are unchanged.
- **The worn suit's gauge** ("putting on an empty suit fills its air", O1 "A"): the server kept the air; the hotbar and the
  inventory always drew the worn suit as `ITEM_SUIT + 10` (full). Both now draw `Items.suit_with(client.tank)`; the
  search window draws the other's suit as sent.
- **Blood only on floors**: a stain is kept with its cell and drawn only while that cell is floor, so blood in open space is
  never made and blood on a ship alongside goes with it.
- **Lying down across** ("this feels very strange and odd", L1 "A"): v79 turned a body lying low toward its look in 8
  ways, so looking up it stood upright and looking down it stood on its head. It now always lies across, head to the
  side it looks to (`WorldView._prone_side`), kept while it looks straight up or down.
- **Shots over the fallen** (his question: which of many bodies on a tile is shot; S1 "A"): the first living one along
  the line; bodies never stop a bullet. Somebody out cold (`COND_CRIT`) is now spared like one lying low: hit only when
  aimed within `PRONE_AIMED`.
- **The flagship mark** on the cluster chart (his picture): drawn above the system, pointing down, so the system's dot
  and "?" stay visible.

## v81: the ship editor, asteroids, holding position (2026-10-22)

His answers on "Spacer v81 Ship editor" (https://claude.ai/artifact/68oyd5cH9wyAsoT5Gcwfww) were all "A", with comments:
E1 "And asteroids!", E4 "Dont forget ctrl+z/c/v", E5 categories in the palette, H1 "need to test in game". His notebook
notes: the editor (top priority, for his artist) and the human wall. In the thread he asked for rooms taller than 2 tiles.

- **The editor is inside the game** (`src/ui/ship_editor.gd`, `src/ui/editor/`), not a separate tool: his artist has only
  the game, and drawing with the game's own tiles shows exactly what will be played. It writes the same text maps as
  `maps/*.txt`, so a ship drawn there can become one of the game's by copying the file into `maps/` and running
  `tools/make_assets.py`.
- **One builder, two languages**: `src/shared/map_builder.gd` turns a drawing into the layout the game loads, the same as
  `tools/make_assets.py` does for `maps/`. `edittest` checks they agree on every map in `maps/`; change both together.
  The Python script stays because it also draws the tile sheets.
- **Lenient building**: the builder picks tiles even where a drawing is wrong and lists problems with their cells, so the
  editor can show a half-done ship. The game (`ShipMap.load_from`) refuses a drawing with a problem and says the first one.
- **Problems in two colours**: red only for what the game cannot load; yellow for what loads but plays badly (no helm,
  no pump, other ships cannot come alongside). Saving is always allowed (an artist works over days); «Попробовать» waits
  for the red ones only.
- **«ships:NAME»** is the map name of a ship of one's own (`ShipMap.USER_PREFIX`); the folder is next to the exe (the
  project folder when run from the editor). `ShipMap.ships_override` points tests elsewhere.
- **Trying a pirate, derelict or asteroid** lays it alongside ship02 through the derelict's machinery
  (`Derelict.try_alongside`), with `ShipMap.try_other` adding the drawing to the other maps for that game only. The trial
  never leaves on its own and the game's events are off (`director/road/story.auto = false`), so it can be looked at.
- **Taller rooms**: the tile sheet gained floor pieces for a room's middle rows (the wall's shade only on the top and bottom
  rows). New tiles are added at the end of the sheet so an artist's older sheet still lines up; a shorter `tiles.png` in
  `sprites/` is laid over the game's (`Sprites.sheet`). A one-tile-tall room stays an error: a floor needs a top and a
  bottom piece.
- **Asteroids as maps** (his E1): an asteroid place now brings a drawn rock alongside (`Net.OTHER_ROCK`, maps of kind
  `asteroid`), with no doors, air or loot; ore is dug from veins by hand (`Salvage.mine`, 10 s), the place's old count
  of 4–8 pieces kept. The old "ore breaks off at your feet every 12 s" stays only for a ship that somehow has no rock.
  This makes the place work instead of waiting, and lets the artist draw asteroids too. Not docked: no door to dock to.
- **Hold position** (the human wall): one key (X), a flag in the walking state (`Mover.State.hold`) so the client predicts
  it, and the cells held in `ShipMap.held`, which `Mover.step` refuses for others. Shots of the same side pass a holder
  (`Combat.spared`), so a line can hold a door while the rest shoot. Any step, lying down or falling lets go: holding is
  standing, not a stance to walk in. I chose a key over a right-click item: it is a fighting move and must be quick.
- **My second opinion** (posted before building): hosting a game on one's own ship waits for v82, since a drawn ship
  must be tested by the server's rules (spawns, pumps, other ships' spots) and the editor's checks are the first half of that.

## v82: polish without extra depth (2026-10-22)

The author: "We need to polish the game further ... I'm afraid of making the mechanics too deep, so the game loses a bit
of fun." Questions page "Spacer v82 Polish" (https://claude.ai/artifact/NTp7NAbinskUYCEhKwCZVi); built on my picks while
he answers.

- **No general rule for depth** (his D1 answer B, against my pick of a rule "the ship runs fine untouched, touching
  gives a bonus"): each mechanic is judged on its own, case by case. Most systems already work untouched anyway (guns
  start armed, rounds come from the locker too, complex repairs are hard mode only, the galley's dishes are extras).
- **The autodoc alone heals fully** (his D2 answer A): alone it stopped at 50, so one player had to stand holding E. Now
  alone it goes on at half pace past 50 (`Medbay.UNTENDED_SLOW`); tending keeps its 2× and the injuries. He added "it needs
  a bar or something to see that you are being healed": a green cross pulses over anyone on a working autodoc's bed, and
  over oneself a bar of one's own health (`WorldView._in_autodocs`). Others' health is not sent to clients, so their
  cross only says the machine is at them.
- **Count what people use, not what bots do** (D3): `src/server/usage.gd` counts people's uses of 18 systems, kept in the
  save and written to `usage.txt` next to the game (the host's), shown on the end screen with what nobody touched. The
  simulator cannot say what is fun; his evenings with friends can. Then we cut or simplify by real play. Nothing is sent
  anywhere by itself (the game stays private).
- **A pause on new systems** (D5, my pick): fixes, feel, art, the editor and own ships until he has played a few evenings.
- **Getting up takes a second** (his crawl video, SS13): `Mover.State.rise` counts the ticks in the shared walking rule, so
  the client predicts it like a step (`Mover.RISE_TICKS` = 20; the self section grew a byte, protocol 58). It makes lying
  down a choice in a gunfight rather than a free dodge. Lying down stays instant. Bots hiding from pirates still get up at
  once: their mind (`Defence`) would otherwise stand in place for a second at every alarm.
- **The turn over is drawn only** (`WorldView._lie`, 0.2 s), for everyone and for falling out cold too.
- **The red name meant "down"**: it was keyed on the sprite being turned, so lying low turned it red. Now it is keyed on the
  condition.
- **One's own sounds**: `Chat.sound` skipped the one who made a sound, so a shooter never heard their own gun, nor the door
  they opened. Only footsteps are played by the client itself (they come every step and are predicted); every other sound
  of one's own is now sent back. Found while adding the empty click.
- **Feel without rules** (F1, F2): an empty click and a reload sound (new `Net.SOUND_*` 16 to 18), casings that are only
  drawn, a camera kick for one's own shot only (scaled by the shake setting, so it can be turned off), console sounds kept
  quiet (−10 dB) and only in air (vacuum stays silent).
- **His F1 note: "a little sound for everything we do"**: a soft tool tick every 0.32 s while a job under our hands goes
  on, a knock when it is done (the share was 95+ when it stopped; a release that late also knocks, which is fine), a flick
  when another thing comes into the hand. All client only (`WorldView._work_sounds`), quiet and only in air.
- **A welded door shows its seam** (his F1 note): beads of weld drawn where the leaves meet (`WorldView._draw_fx`).
- **Being hit is felt** (his O1 note): a small shake for one's own wound (`HURT_SHAKE`, times the shake setting), the
  cry (`SOUND_CRY` had no sound of its own, only a mark), and red at the screen's edges below 75 health, deeper and darker
  down to 15, with a brighter moment at each blow (`GameScreen._update_hurt_edge`). The older darkening below 40 stays.


## v82.1: layers in the ship editor (2026-10-22)

His note: "Need add layers for floors so object have priority on layers. Like floors 1 layers. doors 2 and stuff like that."

- **Two layers, not more**: floor (the signs the builder treats as ground: space, wall, floor, glass, catwalk, rock) and
  objects (every other sign). The game has one sign per cell, so more layers would have nothing to stand for.
- **Editor only**: the file keeps one sign per cell, so the game, `MapBuilder` and old ships are unchanged. The floor
  under an object is not saved; on opening it is worked out (`Drawing.base_for`: a wall under wall objects, floor under
  a spawn place or a ladder), which is always what the game needs there.
- **Objects win**: a floor stroke never removes an object (his "priority"); the eraser in "both" takes the object
  first. Delete on a selection in "both" wipes both layers, as before, since that is what a box delete is for.
- Keys Q (cycle the layer) and O (show objects) were free.


## v83: crawl like SS13, the mouse in the middle, shots on the move (2026-10-23)

His notes: "where you lay, the head stays in the same position, like in SS13 (video)"; "when I put the mouse in the
middle of the screen it becomes buggy"; a video: "when you move, shots spawn behind and no shake after shots, for all guns".

- **Head stays put** (his SS13 video, frames checked): SS13 turns the lying sprite a quarter round its middle and keeps
  that angle; turning while down changes only the sprite's frame. We do the same: `WorldView._prone_side` is taken only
  on the frame the body starts going down (`was_t <= 0`), and the frame drawn is the facing's own. Before, the body
  flipped end to end whenever one looked the other way.
- **The camera stays on one's feet** (`WorldView._stand`, `_my_spot`): the lying body is drawn half a body to one side,
  and the camera and the light followed the drawn sprite, so lying down or flipping slid the screen. Sight is by tile
  on the server, so the feet are the right origin.
- **The mouse dead zone** (`GameClient.LOOK_STILL` 0.8 cell, measured from the body's middle, 0.3 cell above the feet;
  `LOOK_NEAR` 2 cells with triple stick): right by the body one pixel of the mouse is many degrees, and the 8-way body
  flicked with the hand's tremor. 0.35 was too small.
- **Whose shot** (`S_SHOT` + u16 shooter, protocol 59): the client guessed "mine" by distance from its predicted place,
  but its own place runs ahead of the server by the ping, so a shot fired on the move was never "mine" (no kick) and
  its trace began where the server had us, behind. Now the trace starts at the shooter's drawn feet (ours and others'),
  its end stays where the server says it landed. Ship guns pass no shooter.
- **Kick** 2.5 -> 4 px and a short shake of 1.6 px (`KICK_SHAKE`, both times the shake setting): he asked for a shake
  after every shot; small enough not to spoil aiming.

## v84: hosting on one's own ship (2026-10-23)

His answers on "Spacer v84 Next" (https://claude.ai/artifact/RVoV4nte7rCpgf2AhH6TTb): all my picks except E1 (he wants
several friendly ships before more variety) and P1 (no playtest evening soon).

- **The server sends the drawings** (H1): `ShipMap.pack_maps` appends to `S_WELCOME` the other ships' map names in the
  server's order and the texts of every "ships:" drawing in use, deflated (protocol 60). The client fills
  `ShipMap.drawings` from it and loads from those before the «ships» folder, so a guest's own files never matter and are
  never written. Sending the other maps' order also lets the server add drawings the client has never heard of.
- **`ShipMap.drawings` is the one source for a "ships:" text**: `load_from` keeps whatever it read there. The host clears it
  for a new campaign or a try (so an edited drawing is read anew), fills it from the save for a continued one
  (`main.gd _prepare_ships`), and saves `drawings_in_use` (H4). The save's ship wins over the menu's for «Продолжить»:
  the alternative (refuse, "the save was played on another ship") only confuses.
- **Serious problems** (H3) are the editor's red ones: build problems and no spawn place were already refused by
  `load_from`; no helm and no engine are now refused by `GameServer.start` too (`ShipMap.serious`), with the editor's words.
  A ship with no helm can never jump; one with no engine can never move or charge. Everything else stays a warning.
- **Own other drawings** (H5): `ShipMap.own_others` (after `Net.OTHER_MAPS` in `others`). Pirate ships of ours join every
  class's hulls except the drone ship and the bosses, so they come about as often as one class's own hull; one with fewer
  rooms than systems (6) is left out (`coming_in_run`). A derelict place picks its drawing by `Sectors.key % count`, so
  what was left on it lines up on the next visit. The client no longer takes "layout 0" to mean a derelict: it reads the
  ship's kind (`GameClient.other_derelict`).
- **The kind of a "ships:" drawing** comes from the file's name too (`MapBuilder.build` is given the name without the
  prefix): a copied `pirate_x.txt` with no `; kind` line was taken for our own ship.
- **The menu in two columns**: with the ship row and its picture the one column ran past a 720-row window (it already
  did with a save). Left: who one is and joining. Right: one's own game.
- **The blow's circle** (his note, S1): `Combat.swing_end` keeps a miss within `REACH` (0.8 cell) of the striker; the
  client draws a swing arc round the striker toward that end, and the circle only on a hit; a miss sounds `SOUND_SWING`.
- **Fire after this** (his fire page): he picked SS13's gas mix and heat (F1 B, F3 B) against my FTL pick. My second
  opinion: per-tile gas and heat roughly doubles the air's tick cost, and it is the depth he worried about in v82. He
  agreed to start simpler: oxygen, burnt air and heat, deeper later. Measure the air's cost first (`tools/bench.sh`).

- **Several leaving at once** (found by nettest with lag, 2 runs of 13): when one player's leave was handled, the server
  greeted (bot takes over, chat line) players whose own leave ENet had already done but not yet reported, and Godot
  logged "Unable to send packet". `Crew.remove` already skipped those; now `announce_join`, `Chat.say` and
  `GameServer.to_all` skip any peer not `STATE_CONNECTED` too (0 of 8 runs after).

## v85: our fleet and the new character (2026-10-23)

His answers on "Spacer v85 Ships" (https://claude.ai/artifact/G35RhEtEWHhMGPeuhahtuK): all my picks, C2 B in his words
("oxygen tank on and off for now").

- **One grid, ships one below another** (FS1 A): the fleet's drawings are joined into one map (`MapBuilder.fleet_text`,
  map names joined by `ShipMap.FLEET_JOIN` "|", `FLEET_GAP` 4 empty rows between), so movement, doors, air, sight and
  replication need nothing new, and crossing over is a walk through space like any ship alongside. The alternative (a
  second world) would have doubled every system.
- **A context swap, not a rewrite**: about 500 places say `server.ship` and the parts keep one ship's state. `Fleet.use(i)`
  puts ship i in place: `server.ship`, the map's per-ship fittings (`ShipMap.use_ship`, the `FLEET_FITS` lists filtered
  by `fleet_of(cell)`; guns and trays are numbered per ship again) and the fields of the parts named in `Fleet.OWN`. A
  tick runs the ship-wide parts once per ship (`Fleet.each`); a packet from a player runs for the ship they stand in
  (`use_for`). With one ship nothing moves, so the single-ship game is unchanged (all 41 old scripts pass as they were).
  The cost: a new per-ship field in a part must go into `Fleet.OWN`, or both ships share it.
- **Two ships for now** (FS2 A, `Net.FLEET_MAX`). Nothing in the code is limited to two except the menus.
- **Either helm moves the fleet** (FS4 A): the first ship leads (`navigation` puts it in place); `Fleet.follow` copies its
  place, course and jump to the others every tick. Each ship burns its own fuel, and a jump waits for every tank, so the
  second crew's fuel matters. A lost first ship still leads but burns nothing.
- **The weaker 70 %** (FS5 A): enough that the weak ship is usually the one in trouble (the other crew has a reason to help)
  without making it certain. Pirates turn to a standing ship if theirs is lost (the soak found them shooting a dead hull
  until the run ended).
- **A lost ship** (FS6 A): dark, no more hits, not a target; mending its hull from outside above 0 brings it back. The
  run ends only when every ship is lost (`Crew.hull_hit`). The easy mode's "the hull costs its top strength" still comes
  first for each ship.
- **One purse** (FS7 A): `Ship.purse` points the second ship's credits at the first's; `earned` counts on the lead.
- **Bots** (FS8 A): the menu's count is per ship; the second ship gets `crew_size` bots (the host's spare place filled
  too, as nobody hosts there). Joining asks for a ship (a byte after the job in the hello, 0 = any; "any" = fewest players).
- **The client** is told which ship it is aboard (`S_BOARD`, protocol 61) when it crosses over, then that ship's nav,
  helm, devices, power, store and campaign packets; `S_CAMPAIGN` carries the ship's id. It filters its map's fittings to
  that ship, so the gun console's numbers match the server's.
- **Saves**: the first ship's fields stay where they were (an older save loads as before); the others go in `"fleet"`, and
  a character keeps `"fleet"`, the ship it belongs to.
- **Enemy fleets** (his FS1 note): written into the vision; not in this build (it needs two of every fight part).
- **The character** (C1 A): his 32×64 frames are kept at full size (shrinking pixel art blurs it). `CrewArt` builds the
  people's sheet at start (about 220 ms, made in the menu like the sounds so joining is not slowed): job colours by
  repainting the navy (hue 205–252°, saturation 0.28 and up), pirates in their reds, three mirrored ways, feet set on
  one line, a soft shadow, and made steps (1 px bob, one foot up 2 px). His row 1 runs visor-to-glass, the others
  glass-to-visor; `make_assets.py` turns it round, and copies his single back picture into the visor columns.
- **The visor is the oxygen tank** (his C2 B): `Net.LOOK_TANK` (8) in the look byte while `supply` is on (pirates in
  suits always); the half picture shows 0.3 s after a change, drawn by the client alone.

## v86: the fleet's fixes, the pirates' wingman, the shuttle (2026-10-24)

His notes from playing the fleet and his answers on "Spacer v86 Fleet and Fire"
(https://claude.ai/artifact/N2RrzNRQjXg2h2Lxq3KZ8U). He asked to be asked before the build started; fire waits (FQ5 B).

- **The five fleet notes** came from one cause each: the holomap took every cell of the grid (now `GameClient._holo_cells`
  keeps its own ship's); bots' repair jobs and supplies took holes and doors of the whole grid (now `fleet.mine`); «Все по
  местам» gave one ship's posts to every bot (now per ship, `Stations._bots(aboard)`); a pirate docked to one ship was "no
  target" for both (now `Gunnery.engaged()` is false only for the ship it is docked to). The second ship had no room for
  pirates because `MapBuilder.fleet_text` dropped its empty top rows: they are kept now, so a fleet's rows differ from
  0.78's and an old fleet save is refused rather than loaded wrong (`Campaign`, `"fleet_rows"`).
- **Bots stay aboard** (his N4 A): "talk again when pods come; maybe a teleporter better". So bots never take the shuttle.
- **Hard focuses one ship** (his N3 note): `Fleet.target()` always gives the weaker on hard, and a wingman on hard shoots
  the same ship as the first pirate.
- **The wingman** (his E1 A, the first step to enemy fleets): Gunnery was written for one enemy. Rather than doubling it,
  `Wing` keeps the wingman's own copy of Gunnery's enemy fields (`Wing.ENEMY`) and swaps it in for its share of the tick
  and for our shots at it, the way `Fleet` swaps our ships. It stays out of the grid (never docks or boards), so the
  pirates' crew, assault, prisons and the drone need nothing. `Gunnery.engaged()` is "the enemy in place is in the fight
  for this ship"; `fighting()` is "either enemy is". Calls that mean the ship alongside only (drone, flagship, prisons,
  story) use `engaged()`. The odds (25/10/40 % by mode, 25–50 s in) are mine, to be tried in his own games; it comes only
  while the director sends things, so tests are not surprised. Its wreck drifts off (no second hulk on the chart), and it
  runs 12 s after the ship alongside is beaten so the fight still ends.
- **The gun console's two buttons** (`Gunnery.foe`, per ship of ours, `GUNSET_FOE`): one choice for all guns of that ship,
  simpler than a target per gun. `S_GUNS` gains a tail (foe and two summaries), protocol 62.
- **The shuttle** (his N1 idea, picked on the card «Челнок и ангар с полем»): a hangar of each ship with a force field
  (`F`, a window to light, air and movement: no new rule for air or sight) and the dock console (`V`); the field is not in
  `ShipMap.hull`, as a hole in a field makes no sense. The shuttle itself is not laid into the grid (that would need a
  third moving map): it is drawn outside the field, and its passengers are taken out of the world (`Player.in_shuttle`:
  no walking, no air, not seen, not hit, not anybody's foe) and put back at the far hangar. Their view moves at the
  take-off so they see it come in. 4 seats and 10 s are mine. Everyone steps out on landing (fewer buttons); one may get
  out while it stands. Visitors keep their own ship's crew place (`fleet_ship`), so the bots-fill rule does not shuffle
  bots. The flight is drawn as leaving one field and coming to the other; nothing in between, as the two ships lie in one
  grid with no real space between them to show. It needs no power: the author's rule is that nothing breaks for want
  of it.
- **Docks**: `ShipMap.shuttle_docks()` finds each ship's dock the same way on the server and the client (the console,
  the nearest field cells in its wall, which side is space). The standard ship's hangar is on the lower deck over the
  room right of the shield generator; the test ship's at the bottom of its lower deck.


## v87: man and woman base bodies, two fleet bugs

- **The base bodies** (his sheet, "man and woman, just for now"): `CrewArt` now reads `body.png` (4 ways x 2 bodies of
  32x48) instead of v85's suited `crew.png`, which stays in `assets/` unused for the clothes layer later (S6). A new file
  name, so an old suited `crew.png` left in someone's «sprites» folder cannot break the new body (S8).
- **Four ways** (his words: no slant pictures, too much work for the spriter): the made sheet keeps its 24 columns, the
  man's 12 frames (4 ways x 3 poses) then the woman's from `CrewArt.WOMAN_COLUMN`, so the sheet stays under the GPU's
  16384-pixel size (two bodies in rows would not). A slant shows the side it leans to, as SS13 does (S2), in
  `WorldView.FACING_COLUMN`; the hand on a slant is drawn as on that side.
- **Man or woman** travels in the look byte (`Net.LOOK_WOMAN`, 16; the woman's columns), so nothing new per tick. The
  player picks on the main menu (S1) and the pick goes in the hello (one byte after the ship asked for, protocol 63).
  Bots and pirates by lot from their name's hash: the game's own dice are left alone, so tests' sequences don't move.
- **Job colours** (S3): the navy repaint of v85 works on his top and shorts unchanged; no jumpsuit = grey, as before.
- **The tank sign** (S4): v85's visor showed the oxygen tank (his C2). The body has no helmet, so a glass bubble is drawn
  round the head (found from the figure's top 12 rows) on the rows that had the visor down; half seen for the switch.
  A stand-in until the helmet layer.
- **Height 48** (S5): drawn at his size, sharp; `WorldView.CHAR_H` back to 48 and the hands back to v84's places.
- **The second ship never fired** (his note with a video): `Fleet.use` gave a ship its own copy of a part's field the
  first time only for `Array` and `Dictionary`. Godot passes packed arrays (`PackedFloat32Array` charge, `beam_left`...)
  by reference too, so both ships shared them: ship 1's bot fired, the shared charges dropped, and ship 2's bot never
  found a ready gun. Now every value of type Dictionary or above (Array and the packed arrays) is duplicated.
- **No pirate after a won forced fight** (his note): the beaten ship's wreck stays alongside (v72) and `pirates_can_come`
  refuses while anything is there. `Derelict.make_room()` lets it drift off (as `cast_off` does for a hunter; kept on the
  chart) for the admin's calls only (B1): in a normal game a wreck still gives a breather until the ship leaves.
- **v87.1, his answers**: all my picks but two. S4 B: no sign of the oxygen tank on the body (the bubble is gone); S7 B: no
  made step, the figure slides standing. The tank rows and the step columns of the made sheet stay (holding the plain
  standing body), so the helmet and the spriter's steps can drop in without moving the layout.

## v88: suited man and woman

- **His suit sheets** ("full models for suited up", 96x192 each: 3 x 4 frames of 32x48): read as he drew them
  (`CrewArt.SUIT_AT`), so nothing needs redrawing: the back once, the front from clear glass to visor, the sides from visor
  to clear glass. Two files as he sent them (`suit_man.png`, `suit_woman.png`), each replaceable in the «sprites» folder.
- **They fill the rows that waited for them**: the suited looks' plain rows take clear glass, the tank rows the visor down,
  `HALF_ROW` the half visor. The made sheet's layout does not move. `CrewArt.suited` lays a visor's frames out as
  body.png is, so the painting and `_row` work on both.
- **The half visor only in a suit** (`WorldView._row_of`): `HALF_ROW` is per colour, not per look, so someone in a jumpsuit
  switching the tank would have flashed a suit.
- **Job colours on the suit** (U1 A): the same navy repaint as the body; his suit's navy (hue ~230) falls in `NAVY_HUE`.
- **v85's `crew.png` removed** from `assets/` (U4 A; `art_src/crew.png` kept as a reference): his own suits replace it.
- **v88.1, his answers** (all my picks but U2 B; "choose for yourself" on the rest): pirates' visors red, the bright
  orange in a frame's top `HELMET_ROWS` (19) turned red (`CrewArt._visor_red`), so the face, hair and the suit's orange
  marks lower down stay.
- **v88.1, the shadow** (his note: crawling, the shadow stayed a small one at the feet): it was baked into every frame,
  so it turned over with the figure. Now `WorldView.ShadowArt`, a child of the figure drawn behind it, goes from an oval
  round the feet to one along the body by the same `_lie` amount that turns the body over. The machines' old pictures
  still have theirs baked in, so they get none.

## v89: the Notebook's 18 notes

Questions on "Spacer v89 Notes" (https://claude.ai/artifact/FryDUDpk8c5nbDpC3mJGqk); built on my picks.
- **Guns off after an ion storm or a teleport** (his "game breaker"): the panel itself worked. A surge (or a hit) left too
  little power, `Outfit.fit_power` switched guns off and nothing ever switched them on, so it looked broken. What it switches
  off is kept in `Ship.cut` (mount numbers, `Outfit.CUT_GUARD`, `CUT_SHIELD`); `Outfit.restore_power`, once a second from
  `Power.tick`, brings each back in that order when `power_used + need <= budget`. Switching a thing off by hand (`arm`,
  `switch_shield`, `arm_guard`) takes it off the list, so the player's own choice stands.
- **Teleport** ("5 times" read as 5 times rarer, T1): `TELEPORT_SECONDS` 225 (was 45). `Assault.teleport` now charges:
  `TELEPORT_WARN` 5 s with an alarm, `Net.SOUND_TELEPORT` (new kind 20, 30 cells, a rising hum) on each landing cell, and
  the client draws a flickering column there, seen or not (a warning must reach those who cannot see the spot). Cells come
  from `landing_cells`, one per random room of the ship being fought (`gunnery.target` in a fleet). `beam_in` lands them,
  suited (`spawn_boarder(..., bare_ok = false)`: the bare boarders of v62 are for docking only); a teleporter knocked out
  meanwhile lands nobody.
- **The heavy boarder** wore chars.png's old frame. It is now the suit sheet painted `ARMOUR_TINT` with the white dulled
  (`CrewArt._steel`) and the red visor, so all people share one art; chars.png keeps only the robots.
- **A wreck vanishing as our people left it**: `_hulk_leaves` measured from `wreck_at`, which `Road.hulk_spot` may move off
  to keep chart marks apart, so the ship stood "far" from its own wreck and it went the moment nobody was aboard. It now
  measures from where it was beaten (`Derelict._wreck_seen`).
- **Bodies on a wreck**: `_leave` removes pirates; dead ones on their own ship were not counted as bodies
  (`_bodies_aboard` took only `p.corpse`). Dead pirates (not prisoners) are now kept as bodies too. Floating bodies are
  dropped in `Salvage.jumped` with the floating things.
- **"Enemies spawn after they lose"**: the wreck's survivors (v53) are made when we first board, which looks like spawning
  from nothing. Kept (T3 A), but `Derelict.survivors_note()` adds the count to the «разбит» message, so it is fair.
- **Bots stuck on a ladder**: `Movement.climb` refuses while `Repairs.usable_ahead` (the "use" key goes to the thing in
  front). A bot whose route says climb (`bot_step == -1`, and the guard's, the runner's, the hull mender's and the pirates'
  routes) now passes `on_way = true` and climbs anyway. Players still get the old rule.
- **Defenders** (T4 A): his options were all bots fight, a button, or only some. All bots fighting by default would undo
  "people over bots" (v70), so it is an order: `Player.defends`, set by `C_ORDER` with `Net.POST_ARMS` / `POST_NO_ARMS`
  (with NOBODY: every bot). `Defence.think` treats such a bot as a guard. `S_STATIONS` carries it as `Net.ORDER_ARMS` (128)
  in the order byte, so the packet's size does not change. Not saved (bots' orders never were).
- **Rarer events** (his numbers): `Director.RARER` skips a picked event with chance 1 - 1/factor (meteors 3, pirate events
  1.75), so each kind is exactly that much rarer while the pace and the others stay. Hunters: `HUNTER_FIRST` 375,
  `HUNTER_EVERY` 300 (both x1.25). `directortest`'s lower bounds were lowered to match.
- **Click on the chart** (S2 A): one click jumps, the same as the button and only while it is enabled (`BridgeView.chart_clicked`,
  buttons carry `to`), so no new rule can slip in.
- **The gun sight** ("no target with a gun", "cannot fight in space"): the server's shots work in space (`fullruntest`), so
  the likely cause is Windows' cross cursor, thin and black, lost on the dark. The game sets its own `CURSOR_CROSS` image
  (`GameScreen._set_sight_cursor`), replaceable by `sprites/cursor_sight.png`.
- **Pile drawn whole while taken**: the hover outline redraws the things in the cell, and was redrawn only when the mouse
  moved; it now also follows `client.floor_changes`.
- **No sound in the nose**: `AudioStreamPlayer2D` hears from the screen's middle; at the map's edge the camera is clamped,
  so the character can be half a screen away from it. An `AudioListener2D` at our feet (`WorldView._ears`).
- Protocol 64 (the new sound kind).
- **A rare wingtest crash** (seen on PR #63): our gunner bots killed the test pirate's crew, it broke off and left, and
  `_wrecked` then hit a null ship. The test keeps the ship whole and calls another if it went; `becomes_wreck` returns when
  nothing is alongside.


## v90: the author's tile set

- **The sheet is still built by `tools/make_assets.py`**, now from `art_src/tileset/Tile_set_1.png` + `.json` (his Aseprite
  export, kept as he sent it). Tile numbers and the maps are unchanged: every old tile name gets his picture
  (`NEW_ART`, `art_tile`), new pieces go at the end of the sheet. Mine: the maps and saves keep working, and a «sprites/tiles.png»
  drawn for an older build still lays over the top.
- **His export is read leniently** (`load_tileset`): names trimmed, one-tile slices snapped to the 32-pixel grid (three were one
  pixel off), a name given twice is told apart by place (`ladder_floor_down_internal_corner_r` twice: the left one is `_l`).
  His horizontal glass `_l`/`_r` are crosswise to their pictures (the frame is on the other side), so windows take them by
  picture (`WINDOW_SPOTS`).
- **Wall pieces were chosen by eye on the ship previews**: `horizontal_corner_l/r` are the top corners (his `internal_corner`
  pieces looked thicker there), `external_corner` the bottom ones, `vertical_wall_to_internal_corner_r/l` the vertical wall's
  foot at a corner (crosswise again), `vertical_wall_down_to_T-shaped_corner` the crossing. His loose wall ends, column and
  `top_wall_junction` are not used (the maps refuse loose ends).
- **Looks the client lays, not the map** (`WorldView._laid`, `_door_look`): a window's place in a row, a machine facing the room
  above, a wide machine's pieces, a door's kind and lamp and its opening frame. Mine: no map, save or protocol change, and the
  ship editor still draws its single tiles. The look is worked out when the decks are laid; doors every frame by name.
- **Door kinds from the map** (my pick until his D1 answer): hermetic for an airlock's doors and doors into space, technical where
  only some jobs pass, cargo by the supply locker or the module bay, plain elsewhere. **Lamps** the same for everyone (D2 A):
  per-viewer lamps would make two players see one door differently.
- **Wide terminals** (his helm 64 px, gun console 96, comms 64): a row of as many same signs is one wide machine; a single sign
  shows the picture's two ends squeezed together (`art_machine`). Our ships' maps are not widened until his M1 answer: the bridge
  has windows beside each console.
- **Not used yet, asked first**: the window stages (I read them as a shutter, W1), vertical glass, side-wall terminals, the big holo
  table and sphere, ship icons, the brown and red lockers, the med/tech/fire boxes, button and wall light, soil floor, floor lamps,
  danger line, vent, stairs. The stairs are 48 and 64 px tall, so they cannot go in the 32-px sheet as they are.


## v90.1: wall crossings (the author: "Wall dont have cross connection")

- **His set has the T joint only one way**: a vertical wall going down from a horizontal one (`T-shaped_corner`). Where a
  vertical wall meets the band from above, the band was drawn plain (`horizontal_wall`) and his
  `vertical_wall_down_to_T-shaped_corner` crossing has no arms, so the walls looked cut. Mine: both joints are made from his T
  turned upside down (`WALL_JOINS` in `make_assets.py`): the crossing is the T with the turned T's top 16 rows over it, and
  a new `wall_tup` (a wall from above only) is the horizontal wall with the turned T's top 20 rows. `wall_tup` is new, so it
  goes at the end of the sheet (with its pirate copy) and the maps are rebuilt (`MapBuilder` picks it the same way).

## v90.2: wall crossings as he drew them

- **He drew which pieces join** (a picture of his set with lines) and asked to read the slice names again. His
  `vertical_wall_down_to_T-shaped_corner` is the same picture as `vertical_wall_to_T-shaped_corner` (a vertical wall whose foot
  opens into the band's top), not a crossing: v90 used it as the crossing, so the crossing had no arms. Now the vertical wall
  above a band ends in that piece (as before), the crossing is his `T-shaped_corner`, and the turned T (`wall_tup`) is the plain
  `horizontal_wall`, whose top face the foot opens into. v90.1's made-up flipped-T pieces are gone. His
  `internal_corner_l/r` (with `vertical_wall_to_internal_corner_l/r` above) join a vertical wall that goes on down past a band
  turning one way; our maps refuse such a wall (├, ┤), so they stay unused until a map allows them.


## v91: machines on the floor, doors, windows, wall boxes (his v90 answers and two pictures)

- **Machines stand on the floor** (his M1 "machines become objects on the ground", M3 "not walls, on the ground", two pictures
  of a locker and the gun console before the bottom wall). A machine sign is a thing on a floor cell (`things` in the map's
  JSON: cell and the floor under it; `ShipMap.on_floor`): `walk` 0, `opaque` 0 (G1: walked round, seen over, as in SS13).
  His G1 note "if it's small like a cabinet you can move through it, but vision is blocked if it's tall": asked on a card,
  he picked "machines solid, decor walk-through" (small decor such as his v2/v3 lockers, when it comes, may be walked
  through). Tall machines (`ShipMap.TALL`: locker, both SMES, engine, air plant, module bay, shield, cryopod; by his
  pictures and what they are) are `opaque` 1 (`ShipMap.tall`), so they stop sight and cast shadows; the wall at a tall
  machine's back (`ShipMap.behind`) is told seen by the client when the machine is, or a dark patch would sit above it.
  Air does not stand in its cell (the air grid is walkable cells), so it goes round it; against a wall that changes nothing.
  The signs are `MapBuilder.MACHINE_SIGNS` (= `MACHINE_SIGNS` in `make_assets.py`); the oxygen station, the intercom, the pump,
  guns, the dock console and the boxes stay wall things. A run of machine signs between two wall pieces with nothing solid
  above or below is still read as in the wall, so old drawings with a console row in a wall band keep working.
- **Its front** is the floor cell opposite its back: the first of up, down, left, right that is a plain wall with walkable
  floor on the other side (`ShipMap.fitting_front`). Used only from there (`use_ahead`), as wall machines were.
- **Wide machines are one** (`ShipMap.root`, `pieces`, `machine_of`): a row of k same signs, k from `MACHINE_WIDE`, is
  grouped from its first cell; only the root goes into the device dictionaries, so breakdowns, use and hints see one
  machine. A 2×2 block of the chart sign on the floor is his big holo table.
- **Old drawings are converted when read** (G3 A, `MapBuilder.to_floor`, also in the editor): each in-wall machine moves to
  the floor: a row of machines in a wall goes one cell into the room below it (or else above), where that is plain floor, no
  `@`/`%` mark points, no doorway is blocked and no part of the deck is cut off; a row with no such room stays in the wall.
  The game's own maps were converted once by `tools/floorize.gd`; `ship02` was redrawn by hand (G2 A): rooms with machines 3
  tall, the bridge 4× with the holo table in its middle, the engine and the air plant inside the locked engine rooms.
- **A save of a ship drawn anew** (`"layout"` = `ShipMap.crc` in the save): a mismatch keeps the campaign (crew, store, money,
  road) but not what sits in cells: air, holes, broken machines, jammed and picked doors are dropped, floor things go to the
  locker, people and bodies go to spawn places. Mine: cells of the old drawing may be walls or machines now.
- **Door kinds from the drawing** (his D1, my D1b A): a `& deck x y kind` line or the editor's mark menu on a door; without
  one, v90's rule. The map JSON carries `door_looks`.
- **Door lamps** (his D2b note: "green is open, yellow is like open up animation, red is blocked closed; sealed door with
  welding for now, a sprite for sealed doors later"): his open frames already have the lamp yellow, so a shut door is green
  or red only; red is "will not open for me" (`WorldView._blocked`: welded, blast-locked, locked, held by its airlock
  partner, or `Doors.barred` for our own `pred.access`), so a job's door is green to those it opens for. A blast-locked door
  stays red for the crew too, though it opens for us: it says the ship is sealed. No blinking (my first reading of his D2
  "with animation", dropped with the `door_*_off` frames, which were never shipped). v90's yellow shut frame stays in the
  sheet unused (the sheet's older pieces keep their places).
- **Floor lamps** (his F2, my F2b A, he picked A) only by doors that can lock (job doors, airlock doors), on the floor cells
  either side, turned toward the door (TileMap transform flags): green, yellow while the door is open or opening, red as the
  door's own lamp. Orange is "broken": stuck open, a dead ship's door, or no power. The lamp's bar is cut from his `floor_door_lamp_*` minus
  his plain floor, so it lies over any floor. Vents and the danger line are in their own layer under the lamps.
- **Window panes** (his W2): v1 where the cell above or below is space, v2 elsewhere. His v1 horizontal pane has no shutter
  stages, so a shutter coming down over it is drawn in the v2 stages (asked him whether to draw v1 stages).
- **Window shutters** (his W1 A and my W1b A): the server decides (`Systems.update_panes`, every air step, per fleet ship by
  its own alert and power). Down at red alert, and over a window with a hole `PANE_SHUT_TICKS` (1 s) after it was torn: the
  hole stays in `Air.holes` (it needs a patch, counts as a hole) but is `Air.sealed` (no leak, no hiss). Clients learn it as
  hull states 2 (hole behind a shutter) and 3 (shutter down), protocol 65. A shutter down is opaque on both sides
  (`ShipMap.set_pane`; the server forgets its cached lines of sight, the client bumps `other_changes`): a metal plate.
  Without power nothing moves, as the doors' shutters. A save does not keep the sealing: after loading, a broken window
  shuts again 1 s later.
- **Wall boxes** (his M7): the first-aid box and the spare parts box are the supply locker's stock within reach, not stock of
  their own: nothing new comes aboard, nothing to save, no number changes (he wants numbers tested by people first). With a
  whole one in hand E puts it back (the same key, so no new control). The spare parts box gives the kind one carries fewer of.
  The fire box and the wall light are pictures (no fire yet; light is not per room in this game). New signs `E J N L`.
- **Chart icons** (his M5): ours his big ship (`map_ship_5`) in his own colour (87, 191, 236 at alpha 132), turned toward
  the course and keeping that heading when stopped; pirates `map_ship_3`, wrecks and derelicts `map_ship_4`, traders `map_ship_2`,
  hunters `map_ship_1`. The small ones are drawn twice as big (4-10 px otherwise). In the sheet they are white, tinted when drawn.
- **Stairs** (his F3 "dark stairs down, white up", F3b A): sign `/`, two cells in a row on a deck over the same two on the
  deck below (`ShipMap._find_stairs`; the direction comes from the drawing: the lower flight opens into a room at one end,
  the upper one ends at a wall). One changes decks on arriving (the step over, `cd` 0) on the far end of a flight
  (`ShipMap.stair_to`): over the stairwell above, under the upper deck's floor below, in shared `Mover.step`, so the client
  predicts it, and placed in the middle of the cell with no slide drawn between decks (a quarter-step walker's offsets are
  dropped: half a tile at most). No ping-pong: one comes out on a cell that is not a far end. Mine: a flight is 2 long
  because his pictures are 48-64 px; his "big" (two wide) pictures are not used yet. The pictures lie in the marks layer,
  a row's flight 2×2 (the top of his white railing reaches into the row above), a column's 1×2, flipped for the other way.
  Paths treat a step onto a far end as arriving below (bots, pirates, robots). Air: the far end above shares air with the
  cell under it (`air_down`). Our ship02 got one flight next to the stern ladder (the ladder stays: tests know it).
- **Not in v91**: his brown and red lockers (M6 C: only looks) need a sign for a decor locker (and, by his card pick, may
  be walked through).

## v92: the fight in real time (the author's roadmap, item 0)

- **Two layers** (my pick R2 A on `https://claude.ai/artifact/V1AEJgkFnsjG9b8vk4DAmj`, answers pending): inside, the
  ship stays the grid it always was and never turns; outside, `Arena` keeps each ship as a body built from its
  drawing (`ArenaShape`, every deck laid over the others). Turning the grid itself would have broken walking,
  prediction, sight, air and every test; this way the inside knows nothing of the fight's space. A hit point on a
  body maps back to the drawing's cells there, one deck picked by lot (G2 A).
- **Replace the old fight at once, keep everything inside it** (R1 A): the gun console, power panel, crew posts,
  dodge, battle position, shields and ammo all stay. The old hit chance now sets how far off a bot or a pirate
  aims (`BOT_SPREAD`, doubled at `FAR_SPREAD`), so every bonus that changed hit chances still counts.
  `Gunnery.flies == false` (tests, the parting volley) still rolls the old dice; tests that are about the old
  fight set `server.arena.enabled = false` (guntest, derelicttest).
- **Heavy, slow ships** (R5 A): top speeds 4.5..9 cells/s, turn rates 0.22..0.6 rad/s, dampers lose 25% a second:
  a fight of positioning, not of dogfighting. Our ship 6 / 1.6 / 0.35, a middle raider-gunship.
- **WASD at the controls** (P1 A, P5 A), Q/E sideways, Space the old evade as a push. E does not close the controls in
  a fight (it slides); Esc does. Nobody steering (P2 A): the ship drifts (no autopilot for players' ships), but a bot at
  the controls flies the battle position, so a crew of bots still fights as before.
- **Guns as 180° turrets** at their mounts (G1 A): `ArenaShape.outward` takes the side of the mount with the fewest
  solid cells as "out". A gun fires only inside its arc, which is what makes the pilot matter.
- **Aiming by hand at the mount** (G3 A): "use" at a mount with anything but a gun or its round in hand. Mounts.can
  refuses to take a gun down in a fight then (taking a gun down mid-fight was the old empty-hand use).
- **Shot speeds** are slow enough to dodge at range (lasers 45 cells/s: 1.5 s at 70 cells), railgun fast (110).
- **Shields as bubbles** 1.6 cells off the hull (D3 A); point defence meets rockets 16 cells out.
- **Docking clock waits while far** (B1 A): otherwise a boarding ship docks from 70 cells away.
- **Leaving past the edge** (P3 A) replaces jumping away as the only way out of a fight in space: 170 cells, no
  pirate within 60, for 3 s. The escape rule holds: the controls still jump as before.
- **Collisions** (P4 A) hurt a little (1 hull) and push apart; ramming as a weapon waits for the boarding pods (v94).
- Known gap: walking out in a suit to a far ship is still possible, because the grid placement of the ship
  alongside is unchanged; v94 (docking and pods) settles crossing.

## v93: armour, penetration, ricochet; his note; goggles

His answers on "Spacer v93: броня" (`https://claude.ai/artifact/GePkt2SGzwqVSACbk6hZNJ`, all A except O1 B) and on the
v92 page (D3 C, P1 note, P5 A, O4 A).
- **The note's picture** (machines looking into the wall, the globe too low, outer windows without shutters): his
  "_up" picture is a machine at the TOP wall with its face to the room below, so `MACHINE_ART` swaps them (N1 A); the
  holo table's sphere is laid on the objects layer a tile above the table (N2 A, `WorldView._lay_globe`); his v2 pane
  (with the shutter frame) is the outer window, v1 the inner one (N3 A). Only outer windows get shutters
  (`ShipMap.outer_pane`): a shutter between two rooms guards nothing from space.
- **Armour on the outer wall only** (A1 A): `ArenaShape.edge` marks a solid cell with open space among its 8 neighbours
  (4 neighbours missed the corners a slanted shot enters by). Ours 2 points, pirates 1..4 by class; the armour
  module adds its tier; windows at most 1, so a window stays a weak spot.
- **Penetration against points, thickened by the slant** (A2 A): `pen < left / cos(angle)` (at most 2x) holds it.
  Simple to read: a laser (2) is held by 3, goes through 2 head-on but not at 50°. `SLANT_SLACK` lets a nearly
  head-on shot count as head-on (float noise in the normal otherwise held shots that should pass).
- **Every shot that meets armour wears it**, through or not, heavier guns more (A3 A): a long fight opens holes in
  the armour where the enemy keeps hitting, which rewards turning the other side.
- **Ricochet flies on** (R1 A, his note "can hit another enemy"): a glanced shot keeps 70% speed for 1.2 s, never
  back into the same ship (`off`), and can strike any other ship of the side it was fired at. It wears nothing
  (it did not bite). Kinetic 70%, lasers 30%: the old v59 random kinetic ricochet is replaced in space.
- **Mended from outside** (M1 A): the same hull mending (suit, patch, hold use at the outer wall) also makes worn
  armour whole in a 3x3 area; bots go out for it when the hull is whole. Station docking, the bought hull and the
  admin also make it whole. Worn armour is in the Ship (`Ship.worn`) and the save.
- **The shield's arc** (his D3 C): E at the generator cycles bubble -> bow -> starboard -> stern -> port. The arc is
  72° either side and counts the shield as 1.5x, a stopped shot taking half: worth turning to the threat, punished
  by a flanker. Pirates keep bubbles (no AI for it yet).
- **One pilot fires all free guns** (his P1 note): `Net.ALL_GUNS` in C_TURRET; a gunner at his mount keeps his gun,
  the gun console's mouse comes before the pilot's. The gun console in a fight shows space (Tab: the old screen).
- **No dodge roll in space** (his P5 A): the pilot's dodge chance is 0 while the arena flies; flying is the dodge.
- **Goggles now** (his O1 B): a fourth wear place (`Net.WEAR_EYES`), night vision makes the dark count as lit for
  sight (server `Replication.sees`, client `can_see`) with a thin green veil; thermal shows the warm (alive, not
  robots) within 7 cells on one's deck through walls, drawn over everything as an orange figure. Prices 30 and 45
  (my pick; numbers to his playtests). Mount kinds (hardpoint, side, roof) and choosing the enemy deck went to v94.

## v94: the fight like Starsector (his "make all guns work properly ... more like in Starsector")

Questions on `https://claude.ai/artifact/RFiT641SPv4FoHqLDujHRC`; built on my picks (all A) while his answers wait.
- **Three mount kinds pulled from the v94 docking plan** (his G1 note, M1 A): fixed (along the bow, ±5°, damage x1.25,
  scatter x0.5), side turret (180°, 90°/s) and roof turret (360°, 60°/s, x0.8, scatter x1.3). The kind is a `^` line or
  by place: a gun in the bow fifth or a bow wall is fixed. A fixed gun points along the bow from a side wall: our own
  hull never stops our shots, so no new tile art was needed. Docking and boarding pods wait for v95+.
- **Our ship got a fourth mount**, a fixed laser in the bow wall of the lower deck, so the author sees a fixed gun at
  once. It starts switched off (`Gunnery.START_ARMED` 3): the power at the start is unchanged (his "no number changes").
- **Turrets turn at their own pace** (M2 A): before v94 they snapped to the target; now a turret must turn first, which
  makes the pilot's turning matter.
- **Starsector's damage kinds** (D1 A): energy, kinetic (x2 shields, x0.5 armour), explosive (x0.5 / x2), fragments
  (x0.25 / x0.25, full on a bare hull) and ion (x1 plus extra shield heat, a chance to put a system out).
- **Every 100 hull points that get through is one hit inside** (D2 A): the inside (breaches, systems, crew) stays the
  old fight's, so v92/v93 and everything aboard still work; hull points are only the measure in space. Our hull is shown
  x20 (4000) but saves, repairs and prices keep the old 0..200.
- **Guns fire on their own clocks, 0.3-12 s** (D3 A, `Weapons.SPACE`): the old 5-20 s charges made space quiet. The
  numbers are mine, scaled so a laser against a raider's armour does about 7 a hit: a fight lasts about as long as v93's.
- **Ammunition as a clip** (D4 A): one round feeds a few bursts (`Mounts.clip`), so a fast autocannon does not empty the
  locker in a minute.
- **The shield is heat, Starsector's flux** (S1 A): it stops every shot (but the railgun, «Сверхновая», bombs and half a
  blaster's pellets) and heats by the damage; the shield's own heat (`hard`) goes only while it is down. Full: an
  overload of 5 s (S2 A), no shield and no guns. V vents (S3 A). Old shield points stay as what the screens show
  (100 x the heat left), so the old UI still reads.
- **The pilot holds the shield with the right mouse button** and its arc follows the mouse (S4 A); with nobody holding
  it, it goes up when a shot is 1.2 s off and down to cool (bots and pirates the same). The v93 generator switch (bubble
  or arc) stays.
- **Our own shots heat us** (S5 A): firing and shielding share one heat, the central Starsector choice.
- **Starsector's armour** (A1 A): per cell 150 (ours), pirates 50..300 by class; a hit counts half the cell and half its
  neighbours, at least 5%; damage x s/(s+armour), at least 15%. Wear by s, half on the cell. The v93 penetration table
  is gone; ricochet and mending outside stay.
- **The gun console always shows space** (his Notebook note, U1 A) with the guns' list in one column beside it; the old
  FTL screen and its Tab are gone. His other note (the helm's old system map replaced by flying with WASD) goes to v95:
  it changes how a jump and system flight work and needs its own questions.
- **Chat is quiet in space**: with many shots a second, only hits that get inside, an overload and what goes wrong are
  said; the bars show the rest.
- **Thermal goggles inside the view cone only** (his bug note): both `Replication.sees` and `WorldView`.
- **A side wall's joint by a door** (his bug note): the map's piece was right (├), but the wall going on above it lay
  out of sight, so it looked broken off. The sight mask now shows half a cell more of a side wall above and below a seen
  joint (`WorldView._side_wall`), which reads as a wall going on.

- (v94, after the build, mine) `Pirates.cut_in` never cuts in onto a cell with no walkable neighbour. ship02's
  cell 39,13 (between the helm and the drone monitor, against the hull) is such a nook since v91: a boarder cut in
  there stood forever (peopletest's robber failed 1 run in 16). The fix reaches players with the next build.

## v94.1: his answers on the v94 page

- His S4 B: firing does not heat the ship; only the shield does. `Weapons.SHOTS_HEAT` is a switch rather than deleting
  the heat numbers, in case his play says otherwise. With it off a gun waits only for an overload or venting.
- His M2 note ("better tie the weapon types to the points than give the points modifiers"). My reading, which he picked on a
  decision card (2026-10-29): each gun says which mount kinds it fits; the mount's damage x1.25/x0.8 and scatter are gone.
  Fits: siege laser, railgun, Devastator, Nova only the fixed bow mount (they need the whole ship pointed); heavy laser,
  Phoenix, ion cannon, Storm, Hammer, Reaper the bow or a side; everything else anywhere. Turning is the gun's (as in
  Starsector): 120°/s light, 60°/s heavy. A gun already on a misfit mount (old saves, tests) stays and works: only putting
  one up checks. Pirates' weapons pick a fitting mount (`Arena._their_gun`); a pirate drawing with no fitting mount fires
  from its own. The mount kind outside the arena comes from `ArenaShape.kind_in_fleet` (a shape cached per map and ship).
- His N1 comment (fire with no enemies near) waits for v95: the arena runs only in a fight now, and v95's WASD flight
  keeps space on all the time, which is where firing at nothing belongs.

## v95: flying round the system in space

His Notebook note (the old helm map gone, fly with WASD as in a fight) and his N1 comment (fire with no enemy near).
Page "Spacer v95" (https://claude.ai/artifact/Y5SD56y9aj1rZMF9KFEJGa), all answered A.

- **One space for flight and fight** (mine, F1 A): the arena keeps our bodies all the time (`Arena._cruise`, `flying()`);
  `on()` still means a fight. **4 cells to a unit** (`Arena.SCALE`): the old helm's 1.5 units/s is exactly our top
  speed of 6 cells/s, so crossing a system takes as long as before, and a fight's 70-cell approach is 17 units, a short
  way on the chart. The body's place is written back to `Ship.pos` each tick, so places, meteors, the station, saves and
  the chart all keep reading `Ship.pos` as before.
- **The autopilot** (F2 A): a click on the small map flies there even with nobody at the helm, as the old course did;
  any key takes over. Old tests and saves that set `Ship.dest`/`moving` by hand still give a course (`_told_dest`), and
  setting `Ship.pos` by hand places the fleet there (`_told_pos`); moving a body by hand (arena tests) stays put.
- **Fuel only while pushing** (F3 A): the old helm burned by distance; coasting now is free, which is what a player
  flying by keys expects. The rate per unit is the same (his R3 numbers).
- **The edge is a wall** (F4 A): a system is the cluster's square; leaving it is a jump.
- **The ship alongside** (F5 A) is drawn glued where it lies; while it holds the ship (docked, somebody outside, our
  people aboard) the engines do not push, as the old helm refused a course. His comment: later every object (stations,
  places) should be drawn, dockable and landable, but drawn only when near, for speed. Left for the places build.
- **The second ship** (F6 A) holds formation 14 cells behind out of a fight (`Body.formed`), flies itself in a fight and
  goes back after. "Ships flying apart" stays for later.
- **Firing at nothing** (N1 A, N2 A): practice shots (`"practice"`) meet nothing and never tell Gunnery; rounds are spent
  through `Mounts.take_round` as in a fight. Out of a fight empty hands at a mount still take the gun down, so firing
  by hand there needs something else in hand (a tool), as in a fight before v92's change. Meteors and asteroids as
  targets come with the places build.
- **No circle** (B1 A): a fight is wherever the ship is; breaking off is 170 cells from every pirate for 3 s. The old
  "out past the edge with no pirate within 60" made sense only for a circle.
- **Ambushes come out of their place** (B2 A, `Arena.come_from`).
- **Boarding pods** (P1 A, P2 A): they make keeping range no longer safe and give point defence a second job. His P2
  note: "not every ship can do it; it needs a bay or module", so a pod bay is rolled per class like the teleporter
  (raider 0.4, gunship 0.5, cruiser 0.6; cutters and drone ships none; `Hulls` "pods", `Gunnery.pods`). Pods pass the
  shield (they are slow and fly under it), meet point defence once and break after 2 of our hits. Where one strikes it
  breaches the nearest whole hull cell with a floor behind it (`Pirates.cut_in_near`).
- **Assault drones in space** (P3 A): the same flight as pods with a robot inside; outside a fight in space (old tests)
  they keep the old 3 s unseen flight.
- His P1 comment: "improve our bots' AI, or guard bots that fight boarders". The guard bot (v79, the «К оружию» order
  and the guard's job) already fetches a gun and fights; better bot fighting is a question for a later build.
- **Our pods and teleport** (P4 A): with the places build (how ours come back, what stays on the enemy ship).

## v96: places seen in space, meteors, our boarding pod, bots in a fight

He wrote "next build". Questions on `https://claude.ai/artifact/1PD8wL3crt6FGhEEHQ21sx`; built on my picks (all A) while
his answers are pending.
- **Places drawn** (M1 A, his F5 comment "drawn only when near, for speed"): each place is drawn by what it is; a derelict,
  wreck or asteroid from the very drawing that comes alongside (`Road.look_of`, sent in S_ROAD), so what one sees from
  afar is what docks. Only places within 40 cells of the screen are drawn (`SpaceView._seen`).
- **Gliding to the airlock** (M2 A): the server still puts the ship alongside at once (the docking code stays as it is);
  the client draws it gliding from where it lay for 2 s. Cheaper and safer than flying a hulk in the arena.
- **Docking only when stopped** (M3 A): flying through a station's circle topped everything up, which made a station a
  drive-through. `Navigation._reach` treats a moving ship as out of reach of a station or trader.
- **Meteors are rocks** (R1 A): the old lot did not fit a ship one flies by hand. A rock aims a little inside the hull
  (a line at an outline point may only graze it), leads the ship's speed, and is seen 5 s out (the old warning). An evade
  1 s or more before it strikes steers round it (`dash` marks it dodged); later is too late. The shield stops it and
  takes 300 heat; a hull corner pokes out of the shield's ellipse, so a rock at a corner is stopped there too. Out of a
  fight our shield's heat tick runs while rocks fly (and until it falls), so the shield rises at one.
- **A bot at the controls** (R2 A) keeps the old lot (half a person's chance) and dashes 1.5 s before.
- **Asteroids** (R3 A): a shot only flashes; guns cutting ore would undo the suited work at a vein.
- **Our pod** (B1 A): a machine, not a module, so the editor can place it; one per ship02, 2 seats, 5 s wait (or both
  seats taken). It passes their shield like theirs pass ours, meets their point defence once (`_their_guard`, their
  guard's own chance and charge). Shot down it is thrown back (15 to each rider, 30 s mending) rather than killing them:
  a pod is a chance, not a death trap. Their guns do not aim at it (they aim at ships).
- **Coming back** (B2 A): the pod stays stuck in their hull; E there takes up to 2 home (3 s, 6 s flight). An empty pod
  comes home by itself when the fight ends and nobody of ours is left over there.
- **Bots** (B3 A): one bot (the nearest «К оружию» or guard) takes the second seat; a pod waits up to 15 s for it. Over
  there it fights with `Pirates.think`, then goes back to the pod. Riders reuse the shuttle's "out of the world"
  (`in_shuttle`), so targets, sight and the tick skip them with no new checks.
- **The teleporter** (B4 A): later, a rare find with procedural places.
- **Bots fighting** (his P1 comment; D1-D4 all A): radio (fighters know what any of ours sees, `Defence.spotted`), falling
  back below 40 (back above 70, a medical patch on the way), the shotgun first plus a patch from the locker, and one
  target for fighters within 6 cells. Bots without a patch heal as before (the autodoc when free).

## v97: derelicts made from pieces, their robots and vaults, our teleporter

He wrote "next build". Questions on `https://claude.ai/artifact/7jRYnpwScA1mbRd5FsiuQX`: he answered all A except
T1 C. His v96 page answers came in the same evening: all A, so v96 stood as built.
- **Made, not drawn by hand** (P1 A): a campaign makes 8 derelicts from pieces at its start (`PlaceMaker`) and keeps
  them, rather than a new one at every arrival: a place should be the same ship when one comes back to it, and the
  save keeps what was left on it by the layout. They are plain drawings in the editor's text (`ShipMap.MADE_PREFIX`,
  texts in `ShipMap.drawings`), so MapBuilder, the welcome's drawings (v84) and the save's copies carry them with no new
  format. The old drawn derelict stays among them.
- **One deck, 7 rows** (P2 A): a derelict lies over our airlock in ship02's 10 empty rows (GAP 3 and the docking row
  take the rest), so a made derelict can be no taller than derelict01. Places with several decks wait for landing on
  stations (another docking).
- **Robots, not pirates** (I1 A): a derelict has little air, and a robot needs none; pirates already live on their own
  wrecks. They wake when the first of ours sets foot aboard (as a wreck's survivors do) in the rooms farthest from the
  way in, and hold their places (`Player.stays`) until they have somebody to go after: one walking about a dark ship
  from the start would meet our people at the airlock every time. One more a cluster, at most 4.
- **Kept between visits** (I2 A): `Derelict._homes` per sector, like `_left`; not in the save (neither is `_left`).
- **The vault** (V1 A): welded shut, so the welder (v70) opens it and nothing new is needed; the weld is kept when the
  derelict docks (`_move` used to clear every door's flags). Its keeper takes 35% of wounds (heavier than a stormtrooper's
  50%), 6 magazines, and holds its place.
- **The prize** (V2 A): the teleporter in 40% of vaults while none lay in one this campaign (one a campaign: it is the
  late tech); else a gun or a crate one tier above what lies about there, so a vault pays for the fight.
- **The teleporter is a machine of its own** (his T1 C, not my A: a module): the pad `t`, a wall machine used from the
  floor in front, like the pod's bay; the found crate (thing 253: 191 is the night vision goggles, so Gear's numbers past
  190 needed their own thing) is installed in it by an engineer, and `Ship.teleporter` says it is in. ship02 has an
  empty pad in the workshop. E at the pad sends; who stands within 4 cells and is an armed bot told «К оружию» (or a
  guard) goes along, up to 3 in all.
- **Home** (T2 A), **through shields** (T3 A), **never sold** (T4 A, a trader pays 400). A ship that leaves sends home
  whoever our teleporter put on it (`Teleporter.ship_leaves` in `Derelict._leave`): otherwise they would be removed with
  its pirates, or left in a grid that no longer holds that ship.
- **machinetest's trading check** had failed since v96 (the helm's course still braking at (150, 150), and v96's M3
  docks only a stopped ship): the test now ends the course before docking.

## v97.1: side-wall joints

- **His internal corners' top bevel is cut off** (his screenshot with four arrows, "next build also not fixed"): v90.2
  and v93 looked at which pieces join and at sight, not at the pixels of the seam. `internal_corner_l/r` start their
  wall with a 4-row bevel, as a wall end does, while the piece above (`vertical_wall_to_internal_corner_*`) runs straight
  to its edge. Mine: the wall side's top 4 rows repeat row 4 (`JOINT_TOPS`); the band side keeps his drawing, as it
  opens into the room's wall. I checked every touching pair of wall tiles in all maps: the wall side now differs from
  the piece above only by the rib's edge, as between two plain side-wall pieces.

## v98: arsenal, body armour, helmets, suits that inflate

He asked for the arsenal step (lasers and plasma, hand and energy shields) and added body armour, suits that inflate
or let down, and "don't forget about helmets". Questions on `https://claude.ai/artifact/JESXpjSKin5YKnoKTCcccr`: all A
but his notes on A2, W1 and S1 (below).
- **Kinds of harm** (`src/shared/armour.gd`, shared so hints and server agree): bullets/pellets, laser, plasma, blows,
  blasts and "other" (ship hits inside, the admin's, a bruise: no armour). `Combat.hurt` maps its CAUSE_* to one.
- **His numbers for the vest** (A2): blows 60%, bullets and lasers 45%, blasts 30%. Plasma 0: his H2 A says a vest
  and helmet do not save from plasma, and plasma has to be the answer to armour. **The helmet the same** (W1). Shares
  multiply, so a vest and helmet leave 30% of a bullet: strong, by his word; numbers wait for his playtests.
- **No armour with a suit, either way round** (A2: "armour is for inside our ship or boarding by drop pod"). So the
  suit itself is the armour outside: 10% sealed, 30% let down (A1 A).
- **A let-down suit still feeds the mask** (my pick, A1 A): only the pressure's harm (`Vitals.pressure_harm`, up to
  2/s) reaches the body. Taking breath away too would make letting down useless in a fight, where the ship loses air.
  Switching takes 2 s (`Armour.SWITCH_SECONDS`) so it is a choice made before a fight, not a reflex. Taken off, a suit
  is folded sealed. Pirates never let theirs down.
- **A suit's helmet counts as a helmet for concussions** (W1), but only a real helmet's visor halves a flashbang:
  boarders mostly wear suits, and halving flashbangs on them all would quietly weaken a v70 tool.
- **The hand shield is worn, not held** (his S1 note "a slot for the shield; no shooting with it, but a baton"): an
  eighth worn place, `WEAR_SHIELD`. It blocks within 60° of facing (the server's 8-way facing), shots and blows alike;
  a blocked shotgun blast does not knock down, a blocked stun baton does not stun.
- **Energy shield** (S2 A): charge on the Player (`shield`), not in the item: one item number each, and it charges
  again in 10 s anyway. Blows pass it (Dune's slow blade), plasma drains it twice.
- **Energy guns share one cell** (H3 A). Their charges are the item number, as a pistol's rounds: laser 89..99,
  plasma 65..69, the cell 70 (free numbers; 228/229 the new ship guns, `Net.ITEM_GUN_NEW`, since seeds took 204..227).
- **Two ship guns** (G1 A): pulse laser (tier 2, any mount) and plasma cannon (tier 3, CLASS_BLASTER so it slips
  shields half the time like the blaster, bow or side). No tier 3 effects for them: `ITEM_GUN_FX` has no room.
- **Fire guns wait** (G2 A) for the fire question round. Armour is not drawn on the body (the artist's layers).
- admintest assumed every gun loads `PISTOL_ROUNDS`; it now asks `Items.loaded`.
