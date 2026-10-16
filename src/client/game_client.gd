extends Node
## The client's side of the connection. It keeps what the server says about
## the world (`ents`), and predicts the player's own character so that it
## reacts to keys at once instead of waiting for the server's answer.
##
## Two clocks are kept, both measured in server ticks:
##  - the "received" clock: roughly the newest tick we have data for. Other
##    characters are drawn a little behind it, so their movement is smooth
##    even when packets arrive unevenly;
##  - the "predicted" clock: runs ahead by the connection delay. Our own
##    inputs are stamped with it, so they reach the server just before the
##    tick they are meant for, and server and client simulate them alike.

signal joined                        # accepted by the server; map is loaded
signal failed(reason: String)        # could not get in
signal lost(reason: String)          # dropped while playing
signal roster_changed
signal chat(from_id: int, channel: int, text: String)
signal notice(text: String)
signal shot(kind: int, hit: bool, from: Vector2, to: Vector2)   # a shot or a blow, in cells of the whole grid
signal heard(kind: int, x: int, y: int)   # a sound reached our character (see Net.SOUND_*)
signal arrived                       # the ship has just landed in another sector

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")

const INTERP_TICKS := 2.0            # others are drawn this far in the past (0.1 s)
const PRED_MARGIN := 1.5             # safety margin of the predicted clock, in ticks
const FRAME_CLOCK_SNAP := 2.0         # ticks the frame clock may stray from the wall clock before it jumps to it
const FRAME_CLOCK_PULL := 0.05        # and the share of the gap it closes each frame
const CLOCK_SNAP := 6.0              # a clock this far off is set at once instead of eased
const CONNECT_TIMEOUT_MS := 6000
const INPUT_COPIES := 2              # extra copies of every input change, one per frame

enum { IDLE, CONNECTING, GREETING, PLAYING }


class Ent:
	var id := 0
	var x := 0
	var y := 0
	var facing := 2
	var cond := 0                    # Net.COND_*
	var look := 2                    # facing and condition as the server packs them (for the checksum)
	var light := false               # shines a light (a lit flashlight in the hand)
	var steps: Array = []            # recent steps: [start tick, from x, from y, to x, to y, facing, ticks it takes]


var phase := IDLE
var my_id := -1
var map := ShipMap.new()
var roster := {}                     # id -> {"name": String, "colour": int, "kind": Net.KIND_*}
var ents := {}                       # id -> Ent, exactly as the server reported
var hidden := {}                     # id -> the cell it was last seen in: the server stopped telling us about it because we no longer
                                     # see it (Net.FACING_HIDDEN); its silhouette may still fade where it was
var my_ship := Net.CREW_SHIP         # the network id of the ship we are on (see Net.S_SHIPS)
var ships := {}                      # id -> {"kind": Net.SHIP_*, "docked": bool, "at": Vector2i, "name": String}
var predict := true                  # predict our own character (false = wait for the server)
var admin_token := ""                # set when this game started the server: unlocks the host's test tools
var is_admin := false                # the server lets us use the admin panel (see Net.ME_ADMIN)
var is_host := false                 # we are the hosting player: we may make others admins

# the ship itself, as the server last described it
var doors := Doors.new()
var air := PackedByteArray()         # per cell: 0..Net.AIR_FULL (cells outside our view keep their last value)
var holes := {}                      # breached hull cell -> true
var floor_things := {}               # things lying on the floor: cell -> PackedByteArray (see Net.SEC_FLOOR)
var floor_changes := 0               # goes up whenever something is put down or picked up
var ship_changes := 0                # goes up whenever doors, hull or air change: views redraw on it

# where the ship is
var sectors := Sectors.new()
var sector := 0                      # the sector the ship is in
var jump_to := Net.NO_SECTOR         # the sector it is jumping to, if any
var jump_tick := 0                   # the server tick the jump lands on
var drive_ready := 0                 # the server tick from which the drive can be used again
var ship_from := Vector2.ZERO        # where the ship was inside its sector on tick `ship_tick`
var ship_dest := Vector2.ZERO        # where it is heading
var ship_moving := false
var ship_tick := 0
var broken := {}                     # things out of order (bridge consoles, the engine, the air plant): wall cell -> true
var slots := PackedByteArray()       # what our character carries: one item per slot (Net.ITEM_*)
var hand := 0                        # the slot whose thing is in the hand (we choose it; the server follows)
var patches := 0                     # of that, hull patches
var parts := 0                       # and spare parts
var search_id := -1                  # the lying character whose pockets we are going through (-1 = nobody)
var search_hurt := 0                 # how hurt they look (see Combat.hurt_level)
var search_slots := PackedByteArray()  # what they carry
var search_worn := PackedByteArray()   # and what they wear
var worn := PackedByteArray()        # what our character wears (Net.WEAR_*)
var looks := {}                      # id -> how that character is dressed (Net.LOOKS); not there = in a suit
var drag_id := -1                    # the lying character we last took hold of (who we haul, while dragging() is true)
var store := {}                      # the ship's supplies in the locker: thing -> how many
var other_docked := false           # the derelict alongside is docked (where it lies is in map.other_at)
var other_wreck := false            # the ship alongside is a pirate ship our guns wrecked: dark and dead
var _glows := {}                     # pools of light worked out lately (see glow)
var other_changes := 0               # goes up whenever the other ship comes, goes or moves: views redraw on it
var gun_weapon := PackedByteArray()  # per gun mount: the weapon on it (Weapons.*; see Net.S_GUNS)
var gun_charge := PackedByteArray()  # per gun mount: 0..100, Net.GUN_BROKEN, Net.GUN_JAMMED
var gun_flags := PackedByteArray()   # per gun mount: Net.GUNF_*
var power_used := 0                  # power the armed guns and the shield draw
var power_max := 0                   # and what the reactor gives
var shield := 0                      # our shield, 0..100
var shield_flags := 0                # Net.SHF_*
var enemy_sys_out := PackedByteArray() # per Net.ESYS_*: seconds it is still put out by ion or EMP
var enemy_shield := 0                # the enemy's shield, 0..100
var enemy_weapons := PackedByteArray() # the enemy's guns (Weapons.*)
var enemy_class := Net.ECLASS_RAIDER # (v53) its class (Hulls)
var enemy_temper := Net.TEMPER_UNKNOWN # how it fights, once a probe has shown it
var enemy_rooms := PackedByteArray() # per room of its drawing (ShipMap.rooms): Net.ESYS_*, ROOM_EMPTY or ROOM_UNKNOWN
var probes := 0                      # scanning probes in the cargo
var ransom := 0                      # (v54) credits a beaten pirate ship offers to be let go (0 = none)
var ransom_left := 0                 # seconds the offer stands
var drone_state := Net.DRONE_NONE    # (v54) the scouting drone (Net.S_DRONE)
var drone_at := 0                    # the cell of the enemy's drawing it is in
var drone_battery := 0               # seconds of battery left
var drone_coming := 0                # seconds until it gets there (while flying)
var drones := 0                      # drones in the cargo
var ecrew := PackedInt32Array()      # (v54) the enemy's crew we can see: per one, its cell of the enemy's drawing
var ecrew_flags := PackedByteArray() # per one, Net.ECREW_*
var ecrew_probe := 0                 # seconds a probe still shows them all
# (v55) our crew at their posts (Net.S_STATIONS)
var battle_pos := Net.POS_CLOSE      # the battle position
var battle_goal := Net.POS_NONE      # the one the ship is manoeuvring to
var battle_left := 0                 # seconds of the manoeuvre left
var our_dodge := 0                   # in %
var our_hit := 0                     # what the position adds to our hits, in % (may be below 0)
var their_hit := 0                   # and to theirs
var posts_manned := 0                # Net.STATION_* bits
var crew_bots: Array = []            # per bot of ours: [id, order (POST_*), what it does (DOING_*)]
var trade := {}                      # what the trader alongside sells: thing -> price (empty = no trader)
var trade_flags := 0                 # Net.TRADE_*
var enemy_hull := 0                  # hits the pirate ship off the airlock can still take (0 = none)
var enemy_full := 0
var enemy_docks_in := 0              # seconds until it docks by force
var enemy_flags := 0                 # Net.ENEMY_*: it came for a raid, it is running
var enemy_jumps_in := 0              # (while it runs) seconds until it jumps away; 65535 = it cannot now
var gun_aim := Net.AIM_ANY           # where our guns aim: Net.ESYS_*, Net.AIM_ROOM + room or Net.AIM_ANY
var enemy_sys := PackedByteArray()   # per Net.ESYS_*: the strength the enemy's system has left (empty = no enemy)
var enemy_sys_full := PackedByteArray()
# the holomap, while we watch one (see Net.S_HOLO)
var holo_cells := PackedInt32Array() # the cells of our ship's floor, in the order the server sends their air
var holo_air := PackedByteArray()    # per cell of holo_cells: 0..Net.AIR_FULL
var holo_holes := {}                 # every hole in our hull: cell -> true
var holo_doors := PackedByteArray()  # per door of our ship: bit 0 open, the rest Doors.flags shifted up by one
var holo_changes := 0                # goes up with every holomap the server sends
var pumps := {}                     # airlock pumps at work: wall cell -> Systems.PUMP_OUT or PUMP_IN
var store_air := 0.0                 # air left for the air plant, in cells' worth
var credits := 0
# the campaign (see Net.S_CAMPAIGN)
var hull := Net.HULL_MAX
var reserve := 0
var over := Net.OVER_NONE
var sectors_seen := 0
var farthest := 0
var jumps := 0
var voyage_seconds := 0
# our own job and skills (see Net.S_ME)
var job := Net.JOB_CREWMAN
var skills := PackedByteArray([0, 0, 0])
var _power := true                   # the ship has power (see powered)

# our own character's body
var health := 100                    # 100 = unhurt, 0 and below = unconscious, Net.HEALTH_DEAD = dead
var my_cond := 0                     # Net.COND_*
var tank := Net.TANK_FULL            # oxygen left in the suit's tank, 0..Net.TANK_FULL
var supply := false                  # breathing from the tank
var work := 0                        # progress of what we are doing with the "use" key, 0..100
var want_dir := 0                    # direction the player holds right now; set by the game screen

# for the debug overlay
var rtt_ms := 0.0
var server_tick := 0
var mispredicts := 0
var steps_predicted := 0
var checks_ok := 0
var checks_bad := 0
var ship_checks_bad := 0             # of those, the ones where doors, hull or air disagreed
var bytes_in := 0
var packets_in := 0

var pred := Mover.State.new()        # our own character, predicted
var pred_tick := 0                   # last tick simulated for it
var pred_doors := Doors.new()        # the doors as our own predicted walking leaves them

var _auth := Mover.State.new()       # the server's last word on our character...
var _auth_tick := 0                  # ...and the tick it was true on

var _host: ENetConnection = null
var _peer: ENetPacketPeer = null
var _name := ""
var _t_connect := 0
var login_ms := -1                    # from asking to connect to being let aboard (for tools/bench.sh)
var in_world_ms := -1                 # and to the first word on our own character in the world
var _view_cx := -100                 # the chunk our view is centred on; the row is counted inside its deck
var _view_cy := -100

var _have_clock := false
var _frame_clock := -1.0             # now_ticks(): moved on once a frame (see _tick_frame_clock)
var _recv_offset := 0.0
var _recv_target := 0.0
var _pred_offset := 0.0
var _pred_target := 0.0
var _ahead_best := PackedFloat64Array()   # freshest clock reading in each of the last few half-seconds
var _ahead_slot := -1

var _have_self := false
var _have_auth := false
var _nav_known := false
var _ship_cell := Vector2i.ZERO      # where in space the ship was when we last heard
var _inputs: Array = []              # input changes not yet confirmed: [seq, apply tick, dir, applied]
var _seq := 0
var _sent_dir := 0
var _last_apply := 0
var _corr := Vector2.ZERO            # leftover of a correction, eased out so the sprite does not jump
var _repeat_msg := PackedByteArray() # the newest input change, repeated in case the first copy is lost
var _repeat_left := 0
var _haul_from := Vector2.ZERO       # the one we haul is drawn sliding between these two cells, in step with
var _haul_to := Vector2.ZERO         # our own predicted character rather than a moment behind it
var _haul_seen := -1                 # our step (its start tick) that slide belongs to
var _haul_id := -1                   # who it was worked out for


func _init() -> void:
	process_priority = -100              # the clock and the network first, then the views draw the same frame from them


func connect_to(address: String, port: int, player_name: String, wanted_job: int = Net.JOB_CREWMAN) -> String:
	## Starts connecting. Returns "" or what went wrong straight away;
	## later results come through the `joined` / `failed` signals.
	close()
	_host = ENetConnection.new()
	if _host.create_host(1, 2) != OK:
		_host = null
		return "Не удалось открыть сетевое соединение."
	_peer = _host.connect_to_host(address, port, 2)
	if _peer == null:
		_host.destroy()
		_host = null
		return "Не удалось начать подключение к %s:%d. Проверьте адрес." % [address, port]
	_name = player_name
	job = clampi(wanted_job, 0, Net.JOBS - 1)
	_auth.access = Net.JOB_ACCESS[job]     # until the server says otherwise (see Net.S_ME)
	pred.access = _auth.access
	_t_connect = Time.get_ticks_msec()
	phase = CONNECTING
	return ""


func close() -> void:
	if _host != null:
		if _peer != null and _peer.is_active():
			_peer.peer_disconnect()
			_host.flush()
		_host.destroy()
	_host = null
	_peer = null
	phase = IDLE
	my_id = -1
	roster.clear()
	ents.clear()
	_inputs.clear()
	_have_clock = false
	_ahead_best.clear()
	_ahead_slot = -1
	_have_self = false
	_have_auth = false
	_view_cx = -100
	_view_cy = -100
	_sent_dir = 0
	_last_apply = 0
	_repeat_left = 0
	_corr = Vector2.ZERO
	want_dir = 0
	mispredicts = 0
	steps_predicted = 0
	checks_ok = 0
	checks_bad = 0
	ship_checks_bad = 0
	holes.clear()
	floor_things.clear()
	hand = 0
	store.clear()
	trade.clear()
	admin_token = ""
	is_admin = false
	is_host = false
	health = 100
	my_cond = 0
	tank = Net.TANK_FULL
	supply = false
	work = 0
	sector = 0
	jump_to = Net.NO_SECTOR
	_nav_known = false
	ship_moving = false
	broken.clear()
	_power = true
	patches = 0
	parts = 0
	slots = PackedByteArray()
	slots.resize(Net.SLOTS)
	worn.resize(Net.WORN)
	looks.clear()
	search_id = -1
	drag_id = -1
	bytes_in = 0
	packets_in = 0


func send_chat(text: String) -> void:
	if phase != PLAYING:
		return
	var body := text.left(Net.MAX_CHAT).to_utf8_buffer()
	if body.is_empty():
		return
	var msg := PackedByteArray()
	msg.resize(3)
	msg.encode_u8(0, Net.C_CHAT)
	msg.encode_u16(1, body.size())
	msg.append_array(body)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func stop_server_and_close(token: String) -> void:
	## Asks the server to stop (it obeys only the game that started it, see
	## main.gd), waits a moment for it to hang up on us, then closes.
	## The wait matters: a goodbye sent right behind the request would make
	## the server drop the request unread.
	if _peer != null and _peer.is_active() and not token.is_empty():
		var msg := PackedByteArray([Net.C_SHUTDOWN])
		msg.append_array(token.to_utf8_buffer())
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
		var deadline := Time.get_ticks_msec() + 500
		while Time.get_ticks_msec() < deadline and _peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
			_host.service(0)
			OS.delay_msec(5)
	close()


func send_use(held: bool) -> void:
	## The "use" key went down or up. The server decides what it does (see Repairs.update).
	if phase == PLAYING:
		_simulate_to_now()
		var msg := PackedByteArray([Net.C_USE, 1 if held else 0, 0, 0, 0, 0])
		msg.encode_u32(2, maxi(pred_tick, 0))    # the tick we see our character on (see Net.C_USE)
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func send_hand(slot: int) -> void:
	## Takes the thing in that slot into the hand (or an empty hand, if the slot is empty).
	if phase == PLAYING and slot >= 0 and slot < Net.SLOTS:
		hand = slot
		_peer.send(0, PackedByteArray([Net.C_HAND, slot]), ENetPacketPeer.FLAG_RELIABLE)


func turn_to(at: Vector2) -> void:
	## Turns our character to face a place (in cells of the whole grid), the way a
	## click does: sent as an input like walking, so it is predicted at once.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK:
		return
	var d := at - Vector2(pred.x, pred.y)
	if d.length() < 0.3:
		return
	face((Net.DIR_RIGHT if d.x > 0.0 else Net.DIR_LEFT) if absf(d.x) >= absf(d.y) else (Net.DIR_DOWN if d.y > 0.0 else Net.DIR_UP))


func face(facing: int) -> void:
	## Turns our character to face that way (Net.DIR_*), predicted at once.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK or facing == pred.facing:
		return
	var at_tick := maxi(pred_tick + 1, _last_apply + 1)
	_seq += 1
	_inputs.append([_seq, at_tick, Mover.TURN + facing, false])
	_last_apply = at_tick
	var msg := PackedByteArray()
	msg.resize(8)
	msg.encode_u8(0, Net.C_INPUT)
	msg.encode_u16(1, _seq & 0xFFFF)
	msg.encode_u32(3, at_tick)
	msg.encode_u8(7, Mover.TURN + facing)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	_host.flush()
	_repeat_msg = msg
	_repeat_left = INPUT_COPIES


func send_fire(at: Vector2) -> void:
	## Uses the thing in the hand on that place (in cells of the whole grid):
	## shoot, strike, bandage. It carries the tick we see the others on, so the
	## server judges a shot against what we saw.
	if phase == PLAYING:
		var msg := PackedByteArray([Net.C_FIRE, 0, 0, 0, 0, 0, 0, 0, 0])
		msg.encode_u32(1, maxi(int(render_tick()), 0))
		msg.encode_s16(5, clampi(roundi(at.x * 16.0), -32000, 32000))
		msg.encode_s16(7, clampi(roundi(at.y * 16.0), -32000, 32000))
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func is_pirate(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_PIRATE


func send_drop() -> void:
	## Puts the thing in the hand down here.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_DROP]), ENetPacketPeer.FLAG_RELIABLE)


func send_act() -> void:
	## Uses the thing in the hand by itself (switches a flashlight).
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_ACT]), ENetPacketPeer.FLAG_RELIABLE)


func in_hand() -> int:
	return slots[hand] if hand < slots.size() else Net.ITEM_NONE


func stock(item: int) -> int:
	## How many of that thing the supply locker holds.
	return int(store.get(item, 0))


func usable(at: int) -> bool:
	## Is this slot of ours there: pockets with a jumpsuit, the last ones with a backpack (as Player.usable).
	if at < Net.BASE_SLOTS:
		return true
	if at < Net.BASE_SLOTS + Net.POCKETS:
		return worn.size() > Net.WEAR_JUMPSUIT and worn[Net.WEAR_JUMPSUIT] != Net.ITEM_NONE
	return worn.size() > Net.WEAR_PACK and worn[Net.WEAR_PACK] != Net.ITEM_NONE


func has_suit() -> bool:
	return worn.size() > 0 and worn[Net.WEAR_SUIT] != Net.ITEM_NONE


func look_of(id: int) -> int:
	return int(looks.get(id, 0))


func send_guns(which: int) -> void:
	## Fires a gun (255 = every gun that is ready); only from the gun console.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_GUNS, which]), ENetPacketPeer.FLAG_RELIABLE)


func send_aim(which: int) -> void:
	## Points the guns at one of the enemy's systems (Net.ESYS_*) or anywhere; only from the gun console.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_AIM, which]), ENetPacketPeer.FLAG_RELIABLE)


func send_gunset(action: int, a: int, b: int) -> void:
	## Sets the guns up (Net.GUNSET_*: power a gun, switch the shield, change a gun); only from the gun console.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_GUNSET, action, a, b]), ENetPacketPeer.FLAG_RELIABLE)


func send_order(id: int, post: int) -> void:
	## (v55) The captain's order to a bot (Net.NOBODY: to every bot, see Net.C_ORDER).
	if _peer != null:
		var msg := PackedByteArray([Net.C_ORDER, 0, 0, post])
		msg.encode_u16(1, id)
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func send_position(pos: int) -> void:
	## (v55) Takes the ship to a battle position (Net.POS_*); only from the ship's controls.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_POSITION, pos]), ENetPacketPeer.FLAG_RELIABLE)


func may_order() -> bool:
	## (v55) May we give the bots orders: we are the captain, or no captain is aboard (the server decides).
	if job == Net.JOB_CAPTAIN:
		return true
	for id: int in roster.keys():
		if int(roster[id]["kind"]) == Net.KIND_PLAYER and int(roster[id].get("job", 0)) == Net.JOB_CAPTAIN:
			return false
	return true


func fighting() -> bool:
	## A pirate ship lies off the airlock and fights us (it has not docked, it is not a wreck).
	return enemy_hull > 0 and pirates_alongside() and not other_docked


func send_drone(action: int, a: int = 0) -> void:
	## Launches, steers or blows up the scouting drone (Net.DRONE_*); only from the drone monitor.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_DRONE, action, a]), ENetPacketPeer.FLAG_RELIABLE)


func send_holo(on: bool) -> void:
	## Starts or stops watching the holomap our character stands at.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_HOLO, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


func send_wear(wear: int) -> void:
	## Asks to take off what we wear there.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_WEAR, wear]), ENetPacketPeer.FLAG_RELIABLE)


func carried(item: int) -> int:
	## How many of that thing (in any state) our character carries.
	var n := 0
	for v in slots:
		if v != Net.ITEM_NONE and Items.kind_of(v) == Items.kind_of(item):
			n += 1
	return n


func floor_cell(facing: int = -1) -> int:
	## The cell whose top thing the "use" key would pick up: the one in front, or
	## failing that our own; -1 if there is nothing to pick up (the same order as
	## Inventory.pick_up). `facing`: as if our character faced that way.
	if phase != PLAYING or my_cond != Net.COND_OK:
		return -1
	var ahead := map.cell_ahead(pred.x, pred.y, pred.facing if facing < 0 else facing)
	if ahead >= 0 and floor_things.has(ahead):
		return ahead
	var here := pred.y * map.width + pred.x
	return here if floor_things.has(here) else -1


func top_thing(cell: int) -> int:
	## The thing lying on top in that cell (ITEM_NONE if none).
	var things: PackedByteArray = floor_things.get(cell, PackedByteArray())
	for k in range(things.size() - 1, -1, -1):
		if things[k] != Net.ITEM_NONE:
			return things[k]
	return Net.ITEM_NONE


func lit_cells() -> Dictionary:
	## Every cell some light falls on (a flashlight in somebody's hand): cell ->
	## how strongly. Lights are worked out from where characters are drawn.
	var out := {}
	for id: int in ents.keys():
		var lit := (id == my_id and not Items.light(in_hand()).is_empty() and my_cond != Net.COND_DEAD) if id == my_id \
			else (ents[id] as Ent).light
		if not lit:
			continue
		var s := sample(id)
		if s.is_empty():
			continue
		var pool := Items.light(Net.ITEM_FLASHLIGHT_ON)
		var cells := glow(s[0], s[1], float(pool[0]), float(pool[1]))
		for cell: int in cells.keys():
			out[cell] = maxf(float(out.get(cell, 0.0)), float(cells[cell]))
	return out


func glow(origin: Vector2, facing: int, radius: float, ahead: float) -> Dictionary:
	## Sight.glow on our map and doors, remembered: the same pool of light is
	## asked for many times while nobody moves and no door changes.
	var key := hash([origin, facing, radius, ahead, hash(doors.ready), other_changes])
	var known: Variant = _glows.get(key)
	if known != null:
		return known
	if _glows.size() > 64:
		_glows.clear()
	var cells := Sight.glow(map, doors, origin, facing, radius, ahead)
	_glows[key] = cells
	return cells


func other_here() -> bool:
	## Is another ship alongside (a derelict, or pirates)?
	return map.other_at != ShipMap.NO_OTHER


func pirates_alongside() -> bool:
	## Is a pirate ship (still able to fight) alongside?
	return other_here() and map.other_kind >= Net.OTHER_PIRATE and not other_wreck


func other_dark() -> bool:
	## Is the ship alongside one without light of its own (a derelict, or a wreck)?
	return other_here() and (map.other_kind == Net.OTHER_DERELICT or other_wreck)


func dark_cell(cell: int) -> bool:
	## Is this cell on a derelict or a wreck, which have no light of their own? (A pirate ship is lit.)
	return map.is_other(cell) and other_dark()


func send_dock(on: bool) -> void:
	## Asks to dock with the derelict alongside (or undock). Only from the ship's controls.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_DOCK, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


func send_jump(target: int) -> void:
	## Asks for a jump. The server agrees only while our character stands at the sector console.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_JUMP, target]), ENetPacketPeer.FLAG_RELIABLE)


func send_helm(go: bool, to: Vector2 = Vector2.ZERO) -> void:
	## Sets a course inside the sector or stops the ship. The server agrees
	## only while our character stands at the ship's controls.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_HELM, 1 if go else 0, clampi(roundi(to.x), 0, 200), clampi(roundi(to.y), 0, 200)]),
			ENetPacketPeer.FLAG_RELIABLE)


func ship_pos() -> Vector2:
	## Where the ship is inside its sector right now: it moves in a straight line at a fixed speed.
	if not ship_moving:
		return ship_from
	return ship_from.move_toward(ship_dest, Sectors.SHIP_SPEED * maxf(server_now() - ship_tick, 0.0) / Net.TICK_HZ)


func ship_under_way() -> bool:
	return ship_moving and not ship_pos().is_equal_approx(ship_dest)


func server_now() -> float:
	## Our best guess of the server's tick right now.
	return now_ticks() + _recv_offset


func knows_sector(id: int) -> bool:
	## The crew knows what is in a sector it has been to or can reach in one jump.
	return sectors.visited[id] == 1 or sectors.linked(sector, id)


func send_suit(on: bool) -> void:
	## Turns the suit's oxygen supply on or off.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_SUIT, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


func use_target(facing: int = -1) -> int:
	## What our character would use right now: 0 = nothing, 1 = a hole to mend,
	## 2 = an oxygen station, 3 = the sector console, 4 = the ship's controls,
	## 5 = something out of order that can be mended (a console, the engine, the air plant),
	## 6 = a ladder down, 7 = a ladder up (the character stands on it),
	## 8 = the engine or the air plant in working order: nothing to do, but it says so,
	## 9 = a door whose emergency shutter is down and can be forced,
	## 10 = a door jammed open, 11 = a door whose emergency shutter is faulty (both can be mended),
	## 12 = the supply locker, 13 = somebody lying here who can be searched (and hauled),
	## 14 = something lying on the floor in front or underfoot, to pick up,
	## 15 = an airlock pump, 16 = an airlock door held shut because the other one is open,
	## 17 = the gun console, 18 = a shut door of a room our job gives no access to (its lock can be broken),
	## 19 = an intercom, 20 = a holomap monitor, 21 = the drone monitor (v54).
	## `facing`: as if our character faced that way (a click turns it first).
	if phase != PLAYING or my_cond != Net.COND_OK:
		return 0
	var f := pred.facing if facing < 0 else facing
	var cell := map.use_ahead(pred.x, pred.y, f, holes)
	if cell >= 0:
		if holes.has(cell):
			return 1
		if map.oxygen.has(cell):
			return 2
		if broken.has(cell):
			return 5
		if map.chart.has(cell):
			return 3
		if map.helm.has(cell):
			return 4
		if map.engine.has(cell) or map.air_plant.has(cell):
			return 8
		if map.locker.has(cell):
			return 12
		if map.lock_pump.has(cell):
			return 15
		if map.gun_console.has(cell):
			return 17
		if map.guns.has(cell):
			return 8
		if map.intercom.has(cell):
			return 19
		if map.holo.has(cell):
			return 20
		if map.drone_console.has(cell):
			return 21
		var door := map.door_of[cell]
		if door >= 0:
			if doors.is_shut(door) and doors.held_by_partner(door):
				return 16
			if doors.jammed[door] == 1:
				return 10
			if doors.faulty[door] == 1:
				return 11
			if doors.is_sealed(door):
				return 9
			if doors.barred(door, map.door_access[door], pred.access):
				return 18
	if lying_near(f) >= 0:
		return 13
	if floor_cell(f) >= 0:
		return 14
	var here := pred.y * map.width + pred.x
	if map.climb[here] >= 0:
		return 6 if map.climb[here] > here else 7
	return 0


func usable_at(cell: int) -> bool:
	## Is there something in that cell the "use" key (or a click) works on, near
	## or not: a thing on a wall, a door, a hole, things on the floor, somebody
	## lying, a ladder? For the outline under the mouse (WorldView._draw_hover).
	if cell < 0 or cell >= map.cells.size():
		return false
	if holes.has(cell) or floor_things.has(cell) or map.door_of[cell] >= 0 or map.climb[cell] >= 0 or map.guns.has(cell):
		return true
	for things: Dictionary in [map.oxygen, map.chart, map.helm, map.engine, map.air_plant, map.locker, map.lock_pump,
			map.gun_console, map.intercom, map.holo, map.drone_console]:
		if things.has(cell):
			return true
	for e: Ent in ents.values():
		if e.id != my_id and e.cond != Net.COND_OK and e.y * map.width + e.x == cell:
			return true
	return false


func click_facing(c: Vector2i) -> int:
	## A left click on the cell `c` works like the "use" key on what is there (a
	## thing on the wall, a door, a hole, things on the floor, somebody lying, the
	## ladder underfoot): which way must our character face for the key to reach
	## it? The way it faces now is tried first. -1 = nothing to use there, or out
	## of reach (the same rules as the key: a thing on a wall only from its front).
	if phase != PLAYING or my_cond != Net.COND_OK or not _have_self:
		return -1
	if c.x < 0 or c.y < 0 or c.x >= map.width or c.y >= map.height:
		return -1
	var cell := c.y * map.width + c.x
	var here := pred.y * map.width + pred.x
	var order: Array[int] = [pred.facing]
	for f in range(1, 5):
		if f != pred.facing:
			order.append(f)
	for f: int in order:
		var t := use_target(f)
		var on := -1
		if t == 0:
			continue
		elif t == 13:
			var e: Ent = ents.get(lying_near(f))
			on = e.y * map.width + e.x if e != null else -1
		elif t == 14:
			on = floor_cell(f)
		elif t == 6 or t == 7:
			on = here
		else:
			on = map.use_ahead(pred.x, pred.y, f, holes)
		if on == cell:
			return f
	return -1


func lock_air(pump: int) -> float:
	## The air in the chamber of an airlock as our character sees it (0..1).
	var cells: PackedInt32Array = map.lock_pump[pump]["chamber"]
	var sum := 0
	for c in cells:
		sum += air[c]
	return float(sum) / (cells.size() * Net.AIR_FULL)


func docked_air(pump: int) -> float:
	## The air of the ship docked at that airlock's outer door as we know it (0..1),
	## or -1 (the same rule as Systems.docked_air).
	var beyond := map.lock_beyond(pump)
	if beyond < 0:
		return -1.0
	var there := float(air[beyond]) / Net.AIR_FULL
	return there if there >= Net.SHUTTER_LIFT else -1.0


func lying_near(facing: int = -1) -> int:
	## The id of somebody lying (unconscious or dead) in the cell our character
	## faces, or failing that in its own cell; -1 if there is nobody.
	if phase != PLAYING or my_cond != Net.COND_OK:
		return -1
	var ahead := map.cell_ahead(pred.x, pred.y, pred.facing if facing < 0 else facing)
	var best := -1
	var best_here := -1
	for e: Ent in ents.values():
		if e.id == my_id or e.cond == Net.COND_OK:
			continue
		var cell := e.y * map.width + e.x
		if cell == ahead and (best < 0 or e.id < best):
			best = e.id
		elif e.x == pred.x and e.y == pred.y and (best_here < 0 or e.id < best_here):
			best_here = e.id
	return best if best >= 0 else best_here


func dragging() -> bool:
	## Our character is hauling somebody along (the server says so).
	return _have_self and pred.slow and my_cond == Net.COND_OK


func _send_hands(kind: int, id: int) -> void:
	_simulate_to_now()
	var msg := PackedByteArray([kind, 0, 0, 0, 0, 0, 0])
	msg.encode_u16(1, id)
	msg.encode_u32(3, maxi(pred_tick, 0))        # the tick we see our character on (see Net.C_USE)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func send_search(id: int) -> void:
	## Starts going through the pockets of somebody lying next to us (Net.NOBODY: stops).
	if phase == PLAYING:
		_send_hands(Net.C_SEARCH, id)


func send_drag(id: int) -> void:
	## Takes hold of somebody lying next to us (Net.NOBODY: lets go).
	if phase == PLAYING:
		if id != Net.NOBODY:
			drag_id = id
		_send_hands(Net.C_DRAG, id)


func send_loot(theirs: bool, index: int) -> void:
	## While searching: takes the thing in one of their slots, or gives them one of ours.
	if phase == PLAYING and search_id >= 0:
		_peer.send(0, PackedByteArray([Net.C_LOOT, 1 if theirs else 0, index]), ENetPacketPeer.FLAG_RELIABLE)


func send_store(action: int, item: int = Net.ITEM_NONE) -> void:
	## Asks the supply locker for something (Net.STORE_*). The server agrees
	## only while our character stands at the locker.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_STORE, action, item]), ENetPacketPeer.FLAG_RELIABLE)


func can_trade() -> bool:
	## Docked with a trader, with power for the link (the same rule as Supplies.can_trade).
	return powered() and sectors.count > 0 and sectors.kind[sector] == Sectors.TRADER \
		and sectors.within_reach(sector, ship_pos())


func powered() -> bool:
	## The ship has power: the server says so (the engine may be out, or the power may have failed for a moment).
	return _power


func shutter_gap(door: int) -> Array:
	## What the emergency shutter of a door shows: [the pressure difference across
	## it in network units (0..Net.AIR_FULL), how the far side compares with ours:
	## -1 = lower there, 1 = higher there, 0 = cannot tell].
	var a := map.door_sides[door * 2]
	var b := map.door_sides[door * 2 + 1]
	if a < 0 or b < 0:
		return [0, 0]
	var ours := pred.y * map.width + pred.x
	var gap: int = absi(air[a] - air[b])
	if ours != a and ours != b:
		return [gap, 0]
	var far := air[b] if ours == a else air[a]
	return [gap, signi(far - air[ours])]


func use_cell() -> int:
	## The cell our character faces, or -1.
	return map.use_ahead(pred.x, pred.y, pred.facing, holes) if phase == PLAYING else -1


func engine_down() -> bool:
	## The ship has an engine and it is out of order (the same rule as GameServer.engine_down).
	if map.engine.is_empty():
		return false
	for cell: int in map.engine.keys():
		if not broken.has(cell):
			return false
	return true


func my_deck() -> int:
	## The deck our character is on (0 = the top one).
	return map.deck_of(pred.y) if _have_self else 0


func seen_from(deck: int, x: int, y: int) -> bool:
	## Can something at this cell be seen from that deck? Always on the deck
	## itself; one deck down or up only through a see-through floor.
	var its := map.deck_of(y)
	if its == deck:
		return true
	if its == deck + 1:
		return map.see_through[(y - map.deck_stride) * map.width + x] == 1
	if its == deck - 1:
		return map.see_through[y * map.width + x] == 1
	return false


func crew_count() -> int:
	## Everybody aboard who is not a body left behind.
	var n := 0
	for id: int in roster.keys():
		if int(roster[id]["kind"]) != Net.KIND_CORPSE and int(roster[id]["kind"]) != Net.KIND_PIRATE:
			n += 1
	return n


func is_corpse(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_CORPSE


func send_respawn() -> void:
	## Dead: ask to come back as a new crew member (the server allows it after a few seconds).
	if phase == PLAYING and my_cond == Net.COND_DEAD:
		_peer.send(0, PackedByteArray([Net.C_RESPAWN]), ENetPacketPeer.FLAG_RELIABLE)


func send_admin(command: int, argument: int = 0, target: int = 0) -> void:
	## The admin panel and the host's test tools (Net.ADMIN_*). The server ignores
	## them unless the token is right or it made our player an admin.
	if phase != PLAYING or (admin_token.is_empty() and not is_admin):
		return
	var msg := PackedByteArray([Net.C_ADMIN, command, argument, 0, 0])
	msg.encode_u16(3, target)
	msg.append_array(admin_token.to_utf8_buffer())
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func air_at(x: int, y: int) -> int:
	## Air in a cell, 0..Net.AIR_FULL (none at all out in space); -1 where nobody can stand.
	if map.floats(x, y):
		return 0
	if not map.walkable(x, y):
		return -1
	return air[y * map.width + x]


func door_open_amount(door: int) -> float:
	## 0 = shut, 1 = open, in between while it slides. Our own pushes show at once.
	var table := pred_doors if (predict and _have_self) else doors
	var ready := table.ready[door]
	if ready == Doors.CLOSED:
		return 0.0
	var t := pred_time() if (predict and _have_self) else now_ticks() + _recv_offset
	return clampf(1.0 - (float(ready) - t) / float(table.open_ticks(door)), 0.0, 1.0)


func player_name(id: int) -> String:
	return str(roster[id]["name"]) if roster.has(id) else "?"


func is_bot(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_BOT


func player_colour(id: int) -> int:
	return int(roster[id]["colour"]) if roster.has(id) else 0


# ------------------------------------------------------------------ clocks

func now_ticks() -> float:
	## The client's clock, in ticks. It moves once a frame, by the frame's own
	## length (see _tick_frame_clock), so everything drawn in one frame is drawn
	## for one moment, and each frame moves the picture on by an even amount.
	if _frame_clock < 0.0:
		return Time.get_ticks_usec() * 0.000001 * Net.TICK_HZ
	return _frame_clock


func _tick_frame_clock(delta: float) -> void:
	## Reading the wall clock in the middle of a frame makes steps uneven: a frame
	## that starts a few milliseconds late shows the world further on, though it
	## reaches the screen at the same even beat as the rest (v52: the author's
	## video, movement jerking every few frames). So the clock follows the
	## frames' lengths, which Godot evens out, and is pulled gently towards the
	## wall clock so it never drifts away from it.
	var real := Time.get_ticks_usec() * 0.000001 * Net.TICK_HZ
	if _frame_clock < 0.0:
		_frame_clock = real
		return
	_frame_clock += delta * Net.TICK_HZ
	var off := real - _frame_clock
	if absf(off) > FRAME_CLOCK_SNAP:
		_frame_clock = real                  # a long freeze, or a frame far off: catch up at once
	else:
		_frame_clock += off * FRAME_CLOCK_PULL


func render_tick() -> float:
	return now_ticks() + _recv_offset - INTERP_TICKS


func pred_time() -> float:
	return now_ticks() + _pred_offset


func _update_clock(s_tick: int) -> void:
	var now := now_ticks()
	rtt_ms = minf(_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME), 400.0)
	var recv := float(s_tick) - now
	var ahead := float(s_tick) + rtt_ms * 0.001 * Net.TICK_HZ + PRED_MARGIN - now
	# A packet that was held up on the way (a resend after a loss, a stalled
	# link) reads as "the server is further behind" and would slow our clock, so
	# our inputs would start arriving late. A delay can only make a reading
	# smaller, never larger, so the largest recent reading is the truthful one.
	# On an uneven link this also adds headroom by itself: the clock follows the
	# fastest packets while the inputs travel at the average speed.
	var slot := Time.get_ticks_msec() / 500
	if slot != _ahead_slot:
		_ahead_slot = slot
		_ahead_best.append(ahead)
		if _ahead_best.size() > 4:
			_ahead_best.remove_at(0)
	else:
		_ahead_best[_ahead_best.size() - 1] = maxf(_ahead_best[_ahead_best.size() - 1], ahead)
	for v in _ahead_best:
		ahead = maxf(ahead, v)
	if not _have_clock:
		_have_clock = true
		_recv_target = recv
		_recv_offset = recv
		_pred_target = ahead
		_pred_offset = ahead
		pred_tick = int(floor(now + _pred_offset))
	else:
		_recv_target += (recv - _recv_target) * 0.1
		_pred_target += (ahead - _pred_target) * 0.1


func _ease_clock(current: float, target: float, dt_ticks: float) -> float:
	var d := target - current
	if absf(d) > CLOCK_SNAP:
		return target
	var limit := dt_ticks * 0.15      # run at most 15% faster or slower than real time
	return current + clampf(d, -limit, limit)


# ----------------------------------------------------------------- network

func _process(delta: float) -> void:
	_tick_frame_clock(delta)
	if phase == IDLE:
		return
	_poll()
	if phase == CONNECTING or phase == GREETING:
		if Time.get_ticks_msec() - _t_connect > CONNECT_TIMEOUT_MS:
			close()
			failed.emit("Сервер не отвечает. Проверьте адрес, порт и что сервер запущен.")
	elif phase == PLAYING:
		_advance(delta)


func _poll() -> void:
	var ev: Array = _host.service(0)
	while phase != IDLE and int(ev[0]) > 0:
		match int(ev[0]):
			ENetConnection.EVENT_CONNECT:
				_peer.set_timeout(32, 4000, 12000)
				var name_bytes := _name.to_utf8_buffer()
				var hello := PackedByteArray()
				hello.resize(4)
				hello.encode_u8(0, Net.C_HELLO)
				hello.encode_u16(1, Net.PROTOCOL)
				hello.encode_u8(3, name_bytes.size())
				hello.append_array(name_bytes)
				hello.append(job)
				_peer.send(0, hello, ENetPacketPeer.FLAG_RELIABLE)
				phase = GREETING
			ENetConnection.EVENT_DISCONNECT:
				var was_playing := phase == PLAYING
				close()
				if was_playing:
					lost.emit("Соединение с сервером потеряно.")
				else:
					failed.emit("Не удалось подключиться к серверу.")
				return
			ENetConnection.EVENT_RECEIVE:
				var pkt := _peer.get_packet()
				packets_in += 1
				bytes_in += pkt.size()
				if not pkt.is_empty():
					_on_packet(pkt)
		if phase == IDLE:
			return
		ev = _host.service(0)


func _on_packet(pkt: PackedByteArray) -> void:
	match pkt[0]:
		Net.S_WORLD:
			if phase == PLAYING:
				_on_world(pkt)
		Net.S_WELCOME:
			_on_welcome(pkt)
		Net.S_REJECT:
			var reason := pkt[1] if pkt.size() > 1 else 0
			close()
			failed.emit(Net.reject_text(reason))
		Net.S_ROSTER:
			roster.clear()
			var count := pkt.decode_u16(1)
			var pos := 3
			for i in count:
				pos = _read_roster_entry(pkt, pos)
			roster_changed.emit()
		Net.S_JOIN:
			var id := pkt.decode_u16(1)
			var was_here := roster.has(id)     # (already aboard: only its entry changed, a new job say)
			_read_roster_entry(pkt, 1)
			roster_changed.emit()
			if id != my_id and not was_here and not is_corpse(id) and not is_pirate(id):
				notice.emit("%s на борту." % player_name(id))
		Net.S_LEAVE:
			var gone := pkt.decode_u16(1)
			if roster.has(gone) and not is_corpse(gone) and not is_pirate(gone):
				notice.emit("%s покинул корабль." % player_name(gone))
			roster.erase(gone)
			ents.erase(gone)
			hidden.erase(gone)
			roster_changed.emit()
		Net.S_SECTORS:
			sectors.unpack(pkt, 1)
		Net.S_NAV:
			# (the window of space is sent before this whenever the ship has arrived somewhere)
			if not _ours(pkt):
				return
			sector = pkt[3]
			jump_to = pkt[4]
			jump_tick = pkt.decode_u32(5)
			drive_ready = pkt.decode_u32(9)
			var now_at: Vector2i = sectors.cell[sector] if sector < sectors.count else Vector2i.ZERO
			if _nav_known and now_at != _ship_cell and phase == PLAYING:
				arrived.emit()
			_nav_known = true
			_ship_cell = now_at
		Net.S_HELM:
			if not _ours(pkt):
				return
			ship_from = Vector2(pkt.decode_s16(3), pkt.decode_s16(5)) / 10.0
			ship_moving = pkt[7] != 0
			ship_dest = Vector2(pkt[8], pkt[9])
			ship_tick = pkt.decode_u32(10)
		Net.S_DEVICES:
			if not _ours(pkt):
				return
			broken.clear()
			var n: int = pkt[3]
			for i in n:
				broken[pkt[4 + i * 2] | (pkt[5 + i * 2] << 8)] = true
			pumps.clear()
			var at: int = 4 + n * 2
			if pkt.size() > at:
				for i in pkt[at]:
					pumps[pkt.decode_u16(at + 1 + i * 3)] = pkt[at + 3 + i * 3]
			ship_changes += 1
		Net.S_SHIPS:
			_on_ships(pkt)
		Net.S_SEARCH:
			var who := pkt.decode_u16(1)
			search_id = -1 if who == Net.NOBODY else who
			search_slots = pkt.slice(3, 3 + Net.SLOTS)
			search_worn = pkt.slice(3 + Net.SLOTS, 3 + Net.SLOTS + Net.WORN)
			search_hurt = pkt[3 + Net.SLOTS + Net.WORN] if pkt.size() > 3 + Net.SLOTS + Net.WORN else 0
		Net.S_GUNS:
			if not _ours(pkt):
				return
			var n: int = pkt[3]
			gun_weapon = PackedByteArray()
			gun_charge = PackedByteArray()
			gun_flags = PackedByteArray()
			for i in n:
				gun_weapon.append(pkt[4 + i * 3])
				gun_charge.append(pkt[5 + i * 3])
				gun_flags.append(pkt[6 + i * 3])
			var at: int = 4 + n * 3
			power_used = pkt[at]
			power_max = pkt[at + 1]
			shield = pkt[at + 2]
			shield_flags = pkt[at + 3]
			at += 4
			enemy_hull = pkt[at]
			enemy_full = pkt[at + 1]
			enemy_docks_in = pkt.decode_u16(at + 2)
			gun_aim = pkt[at + 4]
			var k: int = pkt[at + 5]
			at += 6
			enemy_sys = PackedByteArray()
			enemy_sys_full = PackedByteArray()
			enemy_sys_out = PackedByteArray()
			for i in k:
				enemy_sys.append(pkt[at + i * 3])
				enemy_sys_full.append(pkt[at + i * 3 + 1])
				enemy_sys_out.append(pkt[at + i * 3 + 2])
			at += k * 3
			enemy_flags = pkt[at]
			enemy_jumps_in = pkt.decode_u16(at + 1)
			enemy_shield = pkt[at + 3]
			enemy_class = pkt[at + 4]
			enemy_temper = pkt[at + 5]
			var rooms: int = pkt[at + 6]
			enemy_rooms = pkt.slice(at + 7, at + 7 + rooms)
			at += 7 + rooms
			probes = pkt[at]
			enemy_weapons = pkt.slice(at + 2, at + 2 + pkt[at + 1])
			at += 2 + pkt[at + 1]
			ransom = pkt[at] if pkt.size() > at + 1 else 0
			ransom_left = pkt[at + 1] if pkt.size() > at + 1 else 0
		Net.S_DRONE:
			drone_state = pkt[1]
			drone_at = pkt.decode_u16(2)
			drone_battery = pkt[4]
			drone_coming = pkt[5]
			drones = pkt[6]
		Net.S_STATIONS:
			if not _ours(pkt) or pkt.size() < 11:
				return
			battle_pos = pkt[3]
			battle_goal = pkt[4]
			battle_left = pkt[5]
			our_dodge = pkt[6]
			our_hit = pkt[7] - 100
			their_hit = pkt[8] - 100
			posts_manned = pkt[9]
			crew_bots = []
			for i in pkt[10]:
				var at := 11 + i * 4
				if pkt.size() >= at + 4:
					crew_bots.append([pkt.decode_u16(at), pkt[at + 2], pkt[at + 3]])
		Net.S_ECREW:
			ecrew_probe = pkt[3]
			ecrew = PackedInt32Array()
			ecrew_flags = PackedByteArray()
			for i in pkt[4]:
				ecrew.append(pkt.decode_u16(5 + i * 3))
				ecrew_flags.append(pkt[7 + i * 3])
		Net.S_TRADE:
			trade.clear()
			for i in pkt[1]:
				trade[pkt[2 + i * 3]] = pkt.decode_u16(3 + i * 3)
			trade_flags = pkt[2 + pkt[1] * 3] if pkt.size() > 2 + pkt[1] * 3 else 0
		Net.S_HOLO:
			if not _ours(pkt):
				return
			var n := pkt.decode_u16(3)
			if n != holo_cells.size():
				return                       # (not the ship we know)
			holo_air = pkt.slice(5, 5 + n)
			var at := 5 + n
			holo_holes.clear()
			for i in pkt.decode_u16(at):
				holo_holes[pkt.decode_u16(at + 2 + i * 2)] = true
			at += 2 + pkt.decode_u16(at) * 2
			holo_doors = pkt.slice(at + 1, at + 1 + pkt[at])
			holo_changes += 1
		Net.S_OUTFIT:
			if pkt.size() >= 4:
				looks[pkt.decode_u16(1)] = pkt[3]
		Net.S_STORE:
			if not _ours(pkt):
				return
			store_air = pkt.decode_u16(3) / 10.0
			credits = pkt.decode_u16(5)
			store.clear()
			for i in pkt[7]:
				store[pkt[8 + i * 3]] = pkt.decode_u16(9 + i * 3)
		Net.S_CAMPAIGN:
			if pkt.size() >= 14:
				hull = pkt[1]
				reserve = pkt[2]
				over = pkt[3]
				sectors_seen = pkt.decode_u16(4)
				farthest = pkt.decode_u16(6)
				jumps = pkt.decode_u16(8)
				voyage_seconds = pkt.decode_u32(10)
		Net.S_ME:
			if pkt.size() >= 2 + Net.SKILLS:
				job = pkt[1]
				skills = pkt.slice(2, 2 + Net.SKILLS)
				var flags: int = pkt[2 + Net.SKILLS] if pkt.size() > 2 + Net.SKILLS else 0
				is_admin = flags & Net.ME_ADMIN != 0
				is_host = flags & Net.ME_HOST != 0
				if _auth.access != Net.JOB_ACCESS[job]:
					_auth.access = Net.JOB_ACCESS[job]
					pred.access = _auth.access
					_rebuild_prediction()
		Net.S_POWER:
			if not _ours(pkt):
				return
			_power = pkt[3] != 0
			ship_changes += 1
			# without power doors open by hand: that is part of the walking rule we predict
			doors.manual = not _power
			_rebuild_prediction()
		Net.S_SHOT:
			if pkt.size() >= 11:
				shot.emit(pkt[1], pkt[2] != 0, Vector2(pkt.decode_s16(3), pkt.decode_s16(5)) / 16.0,
					Vector2(pkt.decode_s16(7), pkt.decode_s16(9)) / 16.0)
		Net.S_SOUND:
			if pkt.size() >= 6:
				heard.emit(pkt[1], pkt.decode_s16(2), pkt.decode_s16(4))
		Net.S_CHAT:
			var n := pkt.decode_u16(4)
			chat.emit(pkt.decode_u16(1), pkt[3], pkt.slice(6, 6 + n).get_string_from_utf8())


func _ours(pkt: PackedByteArray) -> bool:
	## Is this packet about one ship (see Net.S_NAV) about the ship we are on?
	return pkt.size() >= 3 and pkt.decode_u16(1) == my_ship


func _on_ships(pkt: PackedByteArray) -> void:
	## The ships in the world. One other than ours lies alongside: it is laid into our grid.
	ships.clear()
	var pos := 2
	for i in pkt[1]:
		var n: int = pkt[pos + 9]
		ships[pkt.decode_u16(pos)] = {"kind": pkt[pos + 2], "docked": pkt[pos + 3] != 0,
			"at": Vector2i(pkt.decode_s16(pos + 4), pkt.decode_s16(pos + 6)), "layout": pkt[pos + 8],
			"name": pkt.slice(pos + 10, pos + 10 + n).get_string_from_utf8()}
		pos += 10 + n
	var at := ShipMap.NO_OTHER
	var kind := Net.OTHER_DERELICT
	var wreck := false
	other_docked = false
	for id: int in ships.keys():
		if id != my_ship:
			at = ships[id]["at"]
			wreck = int(ships[id]["kind"]) == Net.SHIP_WRECK
			kind = int(ships[id]["layout"]) if int(ships[id]["layout"]) < map.others.size() else Net.OTHER_DERELICT
			other_docked = ships[id]["docked"]
	if at != map.other_at or (at != ShipMap.NO_OTHER and kind != map.other_kind) or wreck != other_wreck:
		if at != map.other_at or kind != map.other_kind:
			map.place_other(at, kind)
			for d in range(map.other_first_door, map.doors.size()):
				doors.ready[d] = Doors.CLOSED
				doors.set_flags(d, 0)
		other_wreck = wreck
		for d in range(map.other_first_door, map.doors.size()):
			doors.dead[d] = 1 if kind == Net.OTHER_DERELICT or wreck else 0
		other_changes += 1
		ship_changes += 1
		_rebuild_prediction()


func _read_roster_entry(pkt: PackedByteArray, pos: int) -> int:
	var n := pkt[pos + 5]
	roster[pkt.decode_u16(pos)] = {
		"colour": pkt[pos + 2],
		"kind": pkt[pos + 3],
		"job": pkt[pos + 4],
		"name": pkt.slice(pos + 6, pos + 6 + n).get_string_from_utf8(),
	}
	return pos + 6 + n


func _on_welcome(pkt: PackedByteArray) -> void:
	my_id = pkt.decode_u16(1)
	server_tick = pkt.decode_u32(3)
	var crc := pkt.decode_u32(7)
	my_ship = pkt.decode_u16(11)
	var n := pkt[13]
	var map_name := pkt.slice(14, 14 + n).get_string_from_utf8()
	var problem := map.load_from(map_name)
	for other_map in Net.OTHER_MAPS:
		if problem == "" and map.add_other(other_map) < 0:
			problem = "Не найдена карта «%s»." % other_map
	holo_cells = PackedInt32Array()
	for c in map.base_walk.size():
		if map.on_ship(c):
			holo_cells.append(c)
	if problem == "" and map.crc != crc:
		problem = "Карта «%s» на сервере отличается от вашей. Нужна одинаковая сборка игры." % map_name
	if problem != "":
		close()
		failed.emit(problem)
		return
	doors.setup(map.doors.size())
	pred_doors.setup(map.doors.size())
	doors.partner = map.door_partner
	pred_doors.partner = map.door_partner
	pred_doors.dead = doors.dead
	other_docked = false
	other_wreck = false
	pumps.clear()
	air.resize(map.width * map.height)
	air.fill(0)
	holes.clear()
	phase = PLAYING
	login_ms = Time.get_ticks_msec() - _t_connect
	joined.emit()


func _on_world(pkt: PackedByteArray) -> void:
	var s_tick := pkt.decode_u32(1)
	server_tick = s_tick
	_update_clock(s_tick)
	var size := pkt.size()
	var pos := 5
	var doors_moved := false
	var reconciled := false
	while pos < size:
		var sec := pkt[pos]
		pos += 1
		if sec == Net.SEC_ENT:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				_apply_record(pkt.decode_u16(pos), pkt.decode_s16(pos + 2), pkt.decode_s16(pos + 4), pkt[pos + 6], s_tick)
				pos += Net.ENT_BYTES
		elif sec == Net.SEC_SELF:
			if in_world_ms < 0:
				in_world_ms = Time.get_ticks_msec() - _t_connect
			_reconcile(s_tick, pkt, pos)
			reconciled = true
			pos += Net.SELF_BYTES
		elif sec == Net.SEC_VITALS:
			health = pkt.decode_s16(pos)
			tank = pkt[pos + 2]
			supply = (pkt[pos + 3] & 1) != 0
			work = pkt[pos + 4]
			slots = pkt.slice(pos + 5, pos + 5 + Net.SLOTS)
			worn = pkt.slice(pos + 5 + Net.SLOTS, pos + 5 + Net.SLOTS + Net.WORN)
			patches = carried(Net.ITEM_PATCH)
			parts = carried(Net.ITEM_PART)
			pos += Net.VITALS_BYTES
		elif sec == Net.SEC_DOOR:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				var ready := pkt.decode_s32(pos + 2)
				doors.ready[pkt.decode_u16(pos)] = Doors.CLOSED if ready < 0 else ready
				doors.set_flags(pkt.decode_u16(pos), pkt[pos + 6])
				pos += Net.DOOR_BYTES
			doors_moved = true
			ship_changes += 1
		elif sec == Net.SEC_HULL:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				var cell := pkt.decode_s16(pos + 2) * map.width + pkt.decode_s16(pos)
				if pkt[pos + 4] != 0:
					holes[cell] = true
				else:
					holes.erase(cell)
				pos += Net.HULL_BYTES
			ship_changes += 1
		elif sec == Net.SEC_FLOOR:
			var count := pkt.decode_u16(pos)
			pos += 2
			for i in count:
				var cell := pkt.decode_s16(pos + 2) * map.width + pkt.decode_s16(pos)
				var things := pkt.slice(pos + 4, pos + 4 + Net.FLOOR_STACK)
				if things.count(Net.ITEM_NONE) == Net.FLOOR_STACK:
					floor_things.erase(cell)
				else:
					floor_things[cell] = things
				pos += Net.FLOOR_BYTES
			floor_changes += 1
		elif sec == Net.SEC_AIR:
			var x0 := pkt[pos] * 16
			var y0 := pkt[pos + 1] * 16
			var count := pkt.decode_u16(pos + 2)
			pos += 4
			for i in count:
				var local := pkt[pos]
				air[(y0 + (local >> 4)) * map.width + x0 + (local & 15)] = pkt[pos + 1]
				pos += 2
			ship_changes += 1
		elif sec == Net.SEC_AIR_FULL:
			var x0 := pkt[pos] * 16
			var y0 := pkt[pos + 1] * 16
			pos += 2
			for ly in 16:
				if y0 + ly >= map.height:
					break
				for lx in 16:
					if x0 + lx >= map.width:
						break
					air[(y0 + ly) * map.width + x0 + lx] = pkt[pos + ly * 16 + lx]
			pos += 256
			ship_changes += 1
		elif sec == Net.SEC_VIEW:
			_view_cx = pkt[pos]
			_view_cy = pkt[pos + 1]
			pos += 2
			for id: int in ents.keys():
				var e: Ent = ents[id]
				if _outside_view(e.x, e.y):
					ents.erase(id)
			for cell: int in holes.keys():
				if _outside_view(cell % map.width, cell / map.width):
					holes.erase(cell)
			for cell: int in floor_things.keys():
				if _outside_view(cell % map.width, cell / map.width):
					floor_things.erase(cell)
			floor_changes += 1
		elif sec == Net.SEC_CHECK:
			var want := pkt.decode_u32(pos)
			var want_ship := pkt.decode_u32(pos + 4)
			pos += 8
			var sum := 0
			for e: Ent in ents.values():
				sum += Net.ent_hash(e.id, e.x, e.y, e.look)
			var ship_ok := (_ship_sum() & 0xFFFFFFFF) == want_ship
			if (sum & 0xFFFFFFFF) == want and ship_ok:
				checks_ok += 1
			else:
				checks_bad += 1
				if not ship_ok:
					ship_checks_bad += 1
		else:
			push_warning("Непонятный раздел %d в пакете сервера." % sec)
			return
	if doors_moved and not reconciled:
		_rebuild_prediction()     # a door somebody else moved may change where our own walking ends up


func _ship_sum() -> int:
	## Checksum of the doors, holes and air in the chunks we are shown (see Net.*_hash).
	var sum := 0
	for d in doors.ready.size():
		var at: Vector2i = map.doors[d]
		if map.door_here(d) and not _outside_view(at.x, at.y):
			sum += Net.door_hash(d, -1 if doors.ready[d] == Doors.CLOSED else doors.ready[d], doors.flags(d))
	for cell: int in holes.keys():
		sum += Net.hull_hash(cell % map.width, cell / map.width)
	for cell: int in floor_things.keys():
		sum += Net.floor_hash(cell % map.width, cell / map.width, floor_things[cell])
	for deck in map.deck_count:
		for cy in range(maxi(_view_cy - 1, 0), mini(_view_cy + 2, map.chunks_high())):
			var y0 := deck * map.deck_stride + cy * 16
			for cx in range(maxi(_view_cx - 1, 0), mini(_view_cx + 2, map.chunks_wide())):
				for y in range(y0, mini(y0 + 16, map.height)):
					var row := y * map.width
					for x in range(cx * 16, mini(cx * 16 + 16, map.width)):
						var a := air[row + x]
						if a != 0:
							sum += Net.air_hash(x, y, a)
	return sum


func _outside_view(x: int, y: int) -> bool:
	## We are shown the chunks around us on our own deck and the same chunks of every other deck.
	return absi((x >> Net.CHUNK_SHIFT) - _view_cx) > 1 or absi((map.local_y(y) >> Net.CHUNK_SHIFT) - _view_cy) > 1


func _apply_record(id: int, x: int, y: int, look: int, s_tick: int) -> void:
	if look == Net.FACING_HIDDEN:
		# out of our sight now: the server tells us no more about it
		var e_hidden: Ent = ents.get(id)
		if e_hidden != null:
			hidden[id] = Vector2i(e_hidden.x, e_hidden.y)
		ents.erase(id)
		return
	hidden.erase(id)
	if look == Net.FACING_GONE or _outside_view(x, y):
		ents.erase(id)
		return
	var facing := Net.look_facing(look)
	var e: Ent = ents.get(id)
	if e == null:
		e = Ent.new()
		e.id = id
		e.x = x
		e.y = y
		e.facing = facing
		e.look = look
		e.cond = Net.look_cond(look)
		e.light = Net.look_light(look)
		ents[id] = e
		return
	e.look = look
	e.cond = Net.look_cond(look)
	e.light = Net.look_light(look)
	if e.x != x or e.y != y:
		if absi(e.x - x) + absi(e.y - y) == 1:
			# somebody hauling, or being hauled, takes longer over a step
			e.steps.append([s_tick, e.x, e.y, x, y, facing, Net.DRAG_TICKS if Net.look_slow(look) else Net.MOVE_TICKS])
			if e.steps.size() > 8:
				e.steps.pop_front()
		else:
			e.steps.clear()          # moved further than one step: place it there
		e.x = x
		e.y = y
	e.facing = facing


# ------------------------------------------------------------- prediction

func _advance(delta: float) -> void:
	if not _have_clock:
		return
	var dt_ticks := delta * Net.TICK_HZ
	_recv_offset = _ease_clock(_recv_offset, _recv_target, dt_ticks)
	_pred_offset = _ease_clock(_pred_offset, _pred_target, dt_ticks)
	_corr = _corr.lerp(Vector2.ZERO, 1.0 - exp(-delta * 16.0))
	if not _have_self:
		return
	# a change of the held direction is stamped with the tick it takes effect on
	if want_dir != _sent_dir and _last_apply - pred_tick < 6:
		var at := maxi(pred_tick + 1, _last_apply + 1)
		_seq += 1
		_inputs.append([_seq, at, want_dir, false])
		_sent_dir = want_dir
		_last_apply = at
		var msg := PackedByteArray()
		msg.resize(8)
		msg.encode_u8(0, Net.C_INPUT)
		msg.encode_u16(1, _seq & 0xFFFF)
		msg.encode_u32(3, at)
		msg.encode_u8(7, want_dir)
		_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
		_host.flush()
		_repeat_msg = msg
		_repeat_left = INPUT_COPIES
	elif _repeat_left > 0:
		# The same change again, in a packet of its own on the frames that follow.
		# If the first copy is lost, the server would otherwise learn about it only
		# after a resend, too late for the tick it was meant for.
		_repeat_left -= 1
		_peer.send(1, _repeat_msg, ENetPacketPeer.FLAG_UNSEQUENCED)
		_host.flush()
	_simulate_to_now()


func _simulate_to_now() -> void:
	## Brings the predicted character up to the current predicted tick. Called
	## every frame and again before drawing, so the picture never lags a tick
	## behind the clock, whatever order the nodes are processed in.
	if not _have_self:
		return
	var target := int(floor(now_ticks() + _pred_offset))
	if target - pred_tick > 40:
		pred_tick = target - 40      # after a long freeze, do not replay everything
	while pred_tick < target:
		pred_tick += 1
		for inp: Array in _inputs:
			if not inp[3] and int(inp[1]) <= pred_tick:
				Mover.apply_input(pred, inp[2])
				inp[3] = true
		if Mover.step(pred, map, pred_doors, pred_tick):
			steps_predicted += 1
	pred_doors.bumped.clear()


func _reconcile(s_tick: int, pkt: PackedByteArray, o: int) -> void:
	## The server's word on our own character at tick `s_tick`.
	_auth.x = pkt.decode_s16(o)
	_auth.y = pkt.decode_s16(o + 2)
	_auth.cd = pkt[o + 4]
	_auth.facing = Net.look_facing(pkt[o + 5])
	my_cond = Net.look_cond(pkt[o + 5])
	_auth.down = my_cond != Net.COND_OK
	_auth.slow = Net.look_slow(pkt[o + 5])
	_auth.span = Net.DRAG_TICKS if (pkt[o + 5] & Net.LOOK_LONG_STEP) != 0 else Net.MOVE_TICKS
	_auth.dir = pkt[o + 6]
	var ack := pkt.decode_u16(o + 7)
	_auth.move_tick = pkt.decode_s32(o + 9)
	_auth.fx = pkt.decode_s16(o + 13)
	_auth.fy = pkt.decode_s16(o + 15)
	_auth_tick = s_tick
	for i in _inputs.size():
		if (int(_inputs[i][0]) & 0xFFFF) == ack:
			_inputs = _inputs.slice(i + 1)
			break
	_have_auth = true
	_rebuild_prediction()


func _rebuild_prediction() -> void:
	## Rebuilds the prediction from the server's last word: start from that
	## state and the doors as the server describes them, and replay the input
	## changes the server has not confirmed yet.
	## (A door the server has shut since is treated as shut for the whole
	## replay. That is safe while doors stay open longer than the replayed
	## stretch: see Doors.HOLD_TICKS.)
	if not _have_auth:
		return
	var st := Mover.State.new()
	st.copy_from(_auth)
	var table := Doors.new()
	table.copy_from(doors)
	if pred_tick < _auth_tick:
		pred_tick = _auth_tick       # our predicted clock was behind the server
	var t := _auth_tick
	var k := 0
	while t < pred_tick:
		t += 1
		while k < _inputs.size() and int(_inputs[k][1]) <= t:
			Mover.apply_input(st, _inputs[k][2])
			k += 1
		Mover.step(st, map, table, t)
	table.bumped.clear()
	pred_doors = table
	for i in _inputs.size():
		_inputs[i][3] = i < k
	if not _have_self:
		_have_self = true
		pred.copy_from(st)
		return
	if st.same_as(pred):
		return
	if (st.x != pred.x or st.y != pred.y) and map.deck_of(st.y) == map.deck_of(pred.y) and not st.down:
		mispredicts += 1                 # (a change of deck is never predicted, nor is being hauled: not mistakes)
	var tnow := pred_time()
	var before := Mover.visual_pos(pred, tnow) + _corr
	pred.copy_from(st)
	_corr = before - Mover.visual_pos(pred, tnow)
	if _corr.length() > 2.5:
		_corr = Vector2.ZERO


# ---------------------------------------------------------------- drawing

func sample(id: int) -> Array:
	## Where to draw a character right now:
	## [position in tiles, facing, is moving, tick its current step started on, condition].
	## Empty if the character is not known.
	if id == my_id and predict and _have_self:
		_simulate_to_now()
		var t := pred_time()
		return [Mover.visual_pos(pred, t) + _corr, pred.facing, Mover.is_sliding(pred, t), pred.move_tick, my_cond]
	var e: Ent = ents.get(id)
	if e == null:
		return []
	if id == drag_id and predict and dragging():
		# Whoever we haul moves into the cell we have just left, as we leave it.
		# The server's word on that arrives late; our own steps we know at once.
		_simulate_to_now()
		if _haul_id != id:
			_haul_id = id
			_haul_to = Vector2(e.x, e.y)
			_haul_from = _haul_to
			_haul_seen = pred.move_tick
		elif _haul_seen != pred.move_tick:
			_haul_seen = pred.move_tick
			_haul_from = _haul_to
			_haul_to = Vector2(pred.fx, pred.fy)
		var t := pred_time()
		var k := clampf((t - float(pred.move_tick)) / float(pred.span), 0.0, 1.0)
		if _haul_from.distance_to(_haul_to) > 1.5:
			k = 1.0                          # a ladder, or a correction: no slide across the ship
		return [_haul_from.lerp(_haul_to, k), e.facing, false, pred.move_tick, e.cond]
	if id == _haul_id:
		_haul_id = -1
	var rt := render_tick()
	var last := e.steps.size() - 1
	for i in range(last, -1, -1):
		var s: Array = e.steps[i]
		if rt >= float(s[0]):
			var k := (rt - float(s[0])) / float(s[6])
			if k < 1.0:
				return [Vector2(lerpf(s[1], s[3], k), lerpf(s[2], s[4], k)), s[5], true, s[0], e.cond]
			return [Vector2(s[3], s[4]), e.facing if i == last else int(s[5]), false, s[0], e.cond]
	if last >= 0:
		var first: Array = e.steps[0]
		return [Vector2(first[1], first[2]), first[5], false, first[0], e.cond]
	return [Vector2(e.x, e.y), e.facing, false, 0, e.cond]
