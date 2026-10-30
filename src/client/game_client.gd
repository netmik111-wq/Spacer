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
signal shot(kind: int, hit: int, from: Vector2, to: Vector2, delay: float, flight: float, by: int)   # a shot or a blow, in cells; (v83) by: the shooter's id or -1
	# of the whole grid; (v56) a ship's shot shows `delay` seconds from now and flies `flight` seconds
signal jolt(kind: int, shot: int, at: Vector2)   # (v56) a sound of the ship fight (Net.JOLT_*), in cells
signal hit(blood: int, id: int, x: int, y: int)   # (v75) somebody near was hurt (see Net.S_HIT)
signal heard(kind: int, x: int, y: int)   # a sound reached our character (see Net.SOUND_*)
signal arrived                       # the ship has just landed in another sector

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Mover := preload("res://src/shared/mover.gd")
const Doors := preload("res://src/shared/doors.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Gear := preload("res://src/shared/gear.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Sight := preload("res://src/shared/sight.gd")
const ArenaSeen := preload("res://src/client/arena_seen.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")

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
	var steps: Array = []            # recent steps: [start tick, from x, from y, to x, to y, facing, ticks it takes] (x, y in tiles)
	var ox := 0                      # (v78) quarters off the centre of tile x, y
	var oy := 0
	var prone := false               # (v78) lying down
	var hold := false                # (v81) holding its position (the human wall): nobody walks through it


var phase := IDLE
var my_id := -1
var map := ShipMap.new()
var roster := {}                     # id -> {"name": String, "colour": int, "kind": Net.KIND_*}
var ents := {}                       # id -> Ent, exactly as the server reported
var hidden := {}                     # id -> the cell it was last seen in: the server stopped telling us about it because we no longer
                                     # see it (Net.FACING_HIDDEN); its silhouette may still fade where it was
var my_ship := Net.CREW_SHIP         # the network id of the ship we are on (see Net.S_SHIPS)
var my_fleet := 0                    # (v85) its number in our fleet (Net.S_BOARD); 0 with one ship
var wanted_ship := 0                 # (v85) the ship of our fleet asked for on joining: 1.., 0 = any
var woman := false                   # (v87) our character is a woman (sent on joining)
var board_changes := 0               # (v85) counts the times we went aboard another ship of our fleet
var ships := {}                      # id -> {"kind": Net.SHIP_*, "docked": bool, "at": Vector2i, "name": String}
var predict := true                  # predict our own character (false = wait for the server)
var admin_token := ""                # set when this game started the server: unlocks the host's test tools
var is_admin := false                # the server lets us use the admin panel (see Net.ME_ADMIN)
var is_host := false                 # we are the hosting player: we may make others admins

# the ship itself, as the server last described it
var doors := Doors.new()
var air := PackedByteArray()         # per cell: 0..Net.AIR_FULL (cells outside our view keep their last value)
var holes := {}                      # breached hull cell -> true
var shut_panes := {}                 # (v91) window cell -> true: its shutter is down (it stops sight as a wall)
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
var scrap := 0                       # (v67) and scrap
var parts := 0                       # and spare parts
var search_id := -1                  # the lying character whose pockets we are going through (-1 = nobody)
var search_hurt := 0                 # how hurt they look (see Combat.hurt_level)
var search_slots := PackedByteArray()  # what they carry
var search_worn := PackedByteArray()   # and what they wear
var worn := PackedByteArray()        # what our character wears (Net.WEAR_*)
var looks := {}                      # id -> how that character is dressed (Net.LOOKS); not there = in a suit
var holding := {}                    # (v74) id -> the thing in that character's hand (Net.ITEM_*; not there = nothing)
var gear := {}                       # (v100) id -> what it wears over its clothes (Net.GEAR_* bits; not there = nothing)
var drag_id := -1                    # the lying character we last took hold of (who we haul, while dragging() is true)
var store := {}                      # the ship's supplies in the locker: thing -> how many
var other_docked := false           # the derelict alongside is docked (where it lies is in map.other_at)
var other_wreck := false            # the ship alongside is a pirate ship our guns wrecked: dark and dead
var other_rock := false             # (v81) what lies alongside is an asteroid (Net.SHIP_ROCK)
var other_derelict := false         # (v84) what lies alongside is a derelict (Net.SHIP_DERELICT), whatever its drawing
var _glows := {}                     # pools of light worked out lately (see glow)
var other_changes := 0               # goes up whenever the other ship comes, goes or moves: views redraw on it
var gun_weapon := PackedByteArray()  # per gun mount: the weapon on it (Weapons.*; see Net.S_GUNS)
var gun_charge := PackedByteArray()  # per gun mount: 0..100, Net.GUN_BROKEN, Net.GUN_JAMMED
var gun_flags := PackedByteArray()   # per gun mount: Net.GUNF_*
var gun_fx := PackedByteArray()      # (v58) per gun mount: the effect of the (tier 3) gun on it, Weapons.FX_*
var guard := 0                       # (v58) the point defence fitted (Weapons.GUARD, or NONE)
var guard_charge := 0                # its charge, 0..100
var guard_flags := 0                 # Net.GUNF_ARMED when it is on
var enemy_guard := false             # (v58) the enemy has point defence
var enemy_fx := PackedByteArray()    # (v58) per enemy gun: its effect
var enemy_charge := PackedByteArray() # (v59) per enemy gun: its charge 0..100 as our top sensors see it (255 = not seen)
# (v59) our ship's gear (Net.S_GEAR)
var gear_tiers := PackedByteArray([1, 1, 1, 1, 1])   # per Gear.SYS_*: its tier
var mount_gunner := PackedByteArray()  # (v60) per gun mount: 1 = somebody stands at it as its gunner (Net.S_MOUNTS)
var mount_wanted := PackedByteArray()  # (v60) per gun mount: the gun the console ordered onto it, 0 = none, 255 = take it down
var gear_modules := PackedByteArray([0, 0])       # per slot of the module bay: the crate in it (Gear.*)
var phase_left := 0                  # seconds until the phase drive is charged (0 = ready, or none)
var gear_flags := 0                  # Net.GEARF_*
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
var crew_bots: Array = []            # per bot of ours: [id, order (POST_*), what it does (DOING_*), (v86) its ship of our fleet, (v89) fights boarders]
var alert := Net.ALERT_GREEN         # (v68) the ship's alert level
var bot_log: Array = []              # (v72) the bots' log for this game: per line [seconds since the game began, bot's name, text]
var bot_log_count := 0               # lines received in all (the crew window adds the new ones)
var _log_file: FileAccess = null     # (v72) and crew_log.txt, where the same lines go
var evade_left := 0.0                # (v68) seconds of the pilot's evade still going
var evade_rest := 0                  # and seconds until it can be pressed again
var meteor_left := 0.0               # (v70) seconds until a meteor seen coming strikes (0 = none)
var meteor_tried := false            # the pilot has steered for it already
var alert_changes := 0               # goes up whenever the alert changes (sounds, the HUD)
var goal := Net.GOAL_NONE            # (v68) what this fight is for (Net.S_GUNS)
var foe := 0                         # (v86) the enemy our guns aim at: 0 the ship alongside, 1 its wingman (Net.S_GUNS)
var arena := ArenaSeen.new()         # (v92) the fight in real time: ships and shots in space (Net.S_ARENA, S_ARENA_SHOT)
var _pilot_sent := -1                # (v92) the pilot's keys last sent, and when
var _pilot_ms := 0
# (v86, the author's N1) the fleet's shuttle (Net.S_SHUTTLE)
var shuttle_docks: Array = []        # per ship of our fleet: ShipMap.shuttle_docks()
var shuttle_at := -1                 # the dock it stands at or left (-1: no shuttle in this game)
var shuttle_to := -1                 # the dock it flies to (-1: it stands)
var shuttle_done := 0.0              # the share of the flight done, moved on between the server's word
var shuttle_riders: Array[int] = []  # the ids of those aboard
var tele_state := Net.TELE_NONE      # (v97) the teleporter that serves us (Net.TELE_*) and its seconds to ready
var tele_secs := 0
var pods := {}                       # (v96) our boarding pods: the bay's wall cell -> {"state": POD_*, "secs", "stuck": cell or -1, "riders": ids}
var foes: Array = [PackedByteArray([0, 0, 0, 0, 255]), PackedByteArray([0, 0, 0, 0, 255])]   # per enemy: in the fight 1/0, hull, full, class, drawing
var goal_flags := 0                  # Net.GOALF_*
var cargo_room := 255                # the room of the enemy's drawing with its cargo pod (255 = none)
var goal_pay := 0
var mount_loaded := PackedByteArray() # (v68) per gun mount: rounds loaded into its breech by hand
var panel := {"breakers": 7, "engines": 0, "over": 0, "rest": 0}   # (v68) the power panel (Net.S_SMES)
var _lights := true                  # (v68) the lights' breaker is on (Net.S_POWER)
var trade := {}                      # what the trader alongside sells: thing -> price (empty = no trader)
var trade_flags := 0                 # Net.TRADE_*
var trade_deal := 0                  # (v58) what the trader alongside deals in (Sectors.DEAL_*)
var trade_shares := PackedByteArray([50, 50, 50])   # (v58) % it pays for plain things, guns, ammunition and parts
var trade_back: Array = []           # (v58) [thing, price] it would sell back to us (what we sold it)
var trade_wants := PackedByteArray() # (v67) the things it looks for and pays Sectors.WANT_PAYS for
var enemy_hull := 0                  # hits the pirate ship off the airlock can still take (0 = none)
var enemy_full := 0
var volleys: Array = []              # (v56) ship's shots for the gun console's plan: [whose, kind, how it ends, room,
                                     # second it is fired (by the clock below), seconds it flies, a number of its own]
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
var fuel := Net.FUEL_START           # (v67) fuel in the ship's tank, in units
var jump_cost := 40                  # (v67) what a lane jump burns from it
var fuel_max := Net.FUEL_MAX
# the campaign (see Net.S_CAMPAIGN)
var hull := Net.HULL_MAX
var reserve := 0
var over := Net.OVER_NONE
var sectors_seen := 0
var farthest := 0
var jumps := 0
var voyage_seconds := 0
var won := false                     # (v57) the flagship is beaten: the game is won, the voyage goes on
var hull_max := Net.HULL_MAX          # (v63) the hull's top strength (the easy mode lowers it)
var mode := Net.MODE_NORMAL           # (v63) how hard this game is
# our own job and skills (see Net.S_ME)
var job := Net.JOB_CREWMAN
var skills := PackedByteArray([0, 0, 0, 0])
var _power := true                   # the ship has power (see powered)
var _backup := false                 # (v61) the ship is dark but the bridge's backup SMES keeps its room lit (see power_at)
var smes: Array = []                 # (v61) per SMES, as Net.S_SMES tells: {small, cell, charge, capacity, charging, output,
                                     # input, level, input_max, output_max, in_now, out_now, status}
var power_mon := {}                  # (v61) the power monitor: {made, base, used, budget, flags, seconds, reactor}
var comms := {}                      # (v63) the comms console's screen (Net.S_COMMS): {state, seconds, at (msec), title, text,
                                     # choices: [[flags, text], ...]}
var story := {}                      # (v63) Net.S_STORY: {flags, flagship (Vector2i), growth, grow_s, quests: [{kind, at,
                                     # reward, title, text}], marks: [[kind, Vector2i]]}
var garden := {}                     # (v63) the hydroponic trays (Net.S_GARDEN): cell -> [seed, stage, growth, flags]
var comms_seen := 0                  # (v63) calls heard since joining (the HUD blinks while one waits)
var road := {"fog": false, "hunter_s": 65535, "hunters": [], "known": PackedByteArray(), "places": []}
                                     # (v64) Net.S_ROAD: hunters [[system, coming]], what the chart shows per system,
                                     # places found here [[kind, Vector2, taken]]

# our own character's body
var health := 100                    # 100 = unhurt, 0 and below = unconscious, Net.HEALTH_DEAD = dead
var my_cond := 0                     # Net.COND_*
var tank := Net.TANK_FULL            # oxygen left in the suit's tank, 0..Net.TANK_FULL
var supply := false                  # breathing from the tank
var bleeding := false                # (v70) our character's injuries (SEC_VITALS)
var arm_broken := false
var leg_broken := false
var concussed := false
var weak := false                    # (v71) weak with long hunger: we walk slowly (SEC_VITALS)
var meal := 0                        # (v71) the galley's dish at work on us (Net.ITEM_STEW.., 0 = none)...
var meal_left := 0                   # ... and about how many seconds it has left
var deflated := false                # (v98) our suit is let down (SEC_VITALS flags bit 7)
var eshield := 0                     # (v98) the charge of the energy shield we wear (0..Net.SHIELD_FULL)
var boards := 0                      # (v71) circuit boards we carry
var toolbox := false                 # (v71) we carry a toolbox
var summary := {}                    # (v75, the author's E1) the run's story at its end (Net.S_SUMMARY): ships, boarders, earned, deaths
var complex_repairs := false         # (v71) the game was made with complex repairs (S_CAMPAIGN)
var hauling := false                 # (v70) the server says we hold somebody (with a broken leg pred.slow alone does not tell)
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
var _turn_to := 0                     # (v77.1) the last turn sent, and the tick it takes effect on
var _turn_at := -1
var _last_apply := 0
var _corr := Vector2.ZERO            # leftover of a correction, eased out so the sprite does not jump
var _repeat_msg := PackedByteArray() # the newest input change, repeated in case the first copy is lost
var _repeat_left := 0
var _haul_from := Vector2.ZERO       # the one we haul is drawn sliding between these two cells, in step with
var _haul_to := Vector2.ZERO         # our own predicted character rather than a moment behind it
var _haul_seen := -1                 # the tick our step left that cell on
var _prone_to := false               # (v78) lying down or getting up as last asked (see toggle_prone)
var _prone_at := -1
var _hold_to := false                # (v81) holding the position or letting go, as last asked (see toggle_hold)
var _hold_at := -1
var _haul_cell := Vector2i.ZERO      # (v78) the tile we were last in
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
	_auth.access = Net.access_of(job)     # until the server says otherwise (see Net.S_ME)
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
	_turn_at = -1
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
	shut_panes.clear()
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
	scrap = 0
	parts = 0
	slots = PackedByteArray()
	slots.resize(Net.SLOTS)
	worn.resize(Net.WORN)
	looks.clear()
	gear.clear()
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


func send_swap(a: int, b: int) -> void:
	## (v73) Swaps what is in two of our slots; the hand goes along with its thing.
	if phase != PLAYING or a == b or a < 0 or b < 0 or a >= Net.SLOTS or b >= Net.SLOTS or not usable(a) or not usable(b):
		return
	_peer.send(0, PackedByteArray([Net.C_SWAP, a, b]), ENetPacketPeer.FLAG_RELIABLE)
	var keep := slots[a]
	slots[a] = slots[b]
	slots[b] = keep
	if hand == a:
		send_hand(b)
	elif hand == b:
		send_hand(a)


func riding() -> bool:
	## (v86) Are we in the fleet's shuttle?
	return my_id >= 0 and shuttle_riders.has(my_id)


func shuttle_dock_here() -> int:
	## (v86) The dock whose console we face (-1: none).
	var cell := use_cell()
	for i in shuttle_docks.size():
		if int((shuttle_docks[i] as Dictionary).get("console", -1)) == cell:
			return i
	return -1


func in_pod() -> int:
	## (v96) The bay of the boarding pod we sit in (-1: none).
	for bay: int in pods.keys():
		if (pods[bay]["riders"] as Array).has(my_id):
			return bay
	return -1


func pod_at(cell: int) -> int:
	## (v96) The bay whose pod is there: its bay in our hull, or stuck in the pirate's hull (-1: none).
	if pods.has(cell):
		return cell
	for bay: int in pods.keys():
		if int(pods[bay]["stuck"]) == cell:
			return bay
	return -1


func send_teleport(action: int) -> void:
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_TELEPORT, action]), ENetPacketPeer.FLAG_RELIABLE)


func send_pod(action: int) -> void:
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_POD, action]), ENetPacketPeer.FLAG_RELIABLE)


func send_shuttle(action: int, arg: int = 0) -> void:
	## (v86) Get into the shuttle, call it, fly it to that ship (a passenger), get out (Net.SHUTTLE_*).
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_SHUTTLE, action, arg]), ENetPacketPeer.FLAG_RELIABLE)


func turn_to(at: Vector2) -> void:
	## Turns our character to face a place (in cells of the whole grid), the way a
	## click does: sent as an input like walking, so it is predicted at once.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK:
		return
	var d := at - Vector2(pred.x, pred.y)
	if d.length() < 0.3:
		return
	# (v74) 8 ways: a slant within 22.5 degrees of the diagonal
	var sx := signi(roundi(signf(d.x))) if absf(d.x) >= absf(d.y) * 0.4142 else 0
	var sy := signi(roundi(signf(d.y))) if absf(d.y) >= absf(d.x) * 0.4142 else 0
	face(Net.dir_of(sx, sy))


func face(facing: int) -> void:
	## Turns our character to face that way (Net.DIR_*), predicted at once.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK or facing == facing_soon() or riding() or in_pod() >= 0:
		return
	_send_input(Mover.TURN + facing)
	_turn_to = facing
	_turn_at = _last_apply


func toggle_prone() -> void:
	## (v78, the author's C1 "B") Lie down, or get up: predicted as walking is.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK:
		return
	# (v82) C while getting up stays down
	var lying := _prone_to if _prone_at > pred_tick else pred.prone and pred.rise == 0
	_send_input(Mover.RISE if lying else Mover.LIE)
	_prone_to = not lying
	_prone_at = _last_apply


func facing_soon() -> int:
	## (v77.1) The way we face once the turn already sent is applied. A turn takes effect on a
	## later tick; asking again on every frame until then queued turn after turn, each a tick
	## further on, until the turns (and the walking queued behind them) never came.
	return _turn_to if _turn_at > pred_tick else pred.facing


func _send_input(value: int) -> void:
	## An input that is not a held direction (a turn, how we look), stamped and predicted as walking is.
	var at_tick := maxi(pred_tick + 1, _last_apply + 1)
	_seq += 1
	_inputs.append([_seq, at_tick, value, false])
	_last_apply = at_tick
	var msg := PackedByteArray()
	msg.resize(8)
	msg.encode_u8(0, Net.C_INPUT)
	msg.encode_u16(1, _seq & 0xFFFF)
	msg.encode_u32(3, at_tick)
	msg.encode_u8(7, value)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
	_host.flush()
	_repeat_msg = msg
	_repeat_left = INPUT_COPIES


# (v77, the author's V1..V4) The view follows the mouse: the cone turns smoothly towards it,
# half a turn in LOOK_TURN_SEC, and the body (what others see) takes the nearest of the 8 ways.
const LOOK_TURN_SEC := 1.0 / 3.0     # (his V2) how long half a turn takes
const LOOK_STICK_DEG := 6.0          # the body keeps its way this much past the half-way line, so it does not flicker
const LOOK_STILL := 0.8              # (v83, his note) the mouse this close to us (cells) moves neither eyes nor body
const LOOK_NEAR := 2.0               # (v83) and up to this far the body needs a wider margin to turn
var want_free_look := true           # the player's setting (GameScreen sets it every frame)
var look_angle := PI * 0.5           # where the eyes point, radians on screen (0 = right, PI/2 = down)
var _look_sent_ms := -100000         # when the setting was last sent (sent again if the server did not take it)


func free_looking() -> bool:
	## Does our character look where the mouse is (rather than where it walks)?
	return _have_self and pred.free_look


func look_way() -> Vector2:
	## (v77) Which way our eyes point: the mouse's way (smooth), or the way we face.
	return Vector2.from_angle(look_angle) if free_looking() else Net.way(pred.facing)


func aim_at(at: Vector2, delta: float) -> void:
	## (v77) Every frame: the place the mouse points at (in cells of the whole grid, or INF when it
	## points nowhere). The eyes turn towards it; the body follows them in 8 ways.
	if phase != PLAYING or not _have_self:
		return
	if want_free_look != pred.free_look and Time.get_ticks_msec() - _look_sent_ms > 1000:
		_look_sent_ms = Time.get_ticks_msec()
		_send_input(Mover.LOOK_FREE if want_free_look else Mover.LOOK_WALK)
	if not pred.free_look or my_cond != Net.COND_OK:
		look_angle = Net.way(pred.facing).angle()
		return
	var d := at - Mover.visual_pos(pred, pred_time())
	# (v83, his note: "when I put the mouse in the middle of the screen it gets buggy") right by us a
	# pixel of the mouse swings the way by many degrees, so the eyes and the body shook; near us they wait
	# (measured from the middle of the drawn body, a third of a cell above where it stands)
	var near := (d + Vector2(0, 0.3)).length()
	if not at.is_finite() or near < LOOK_STILL:
		return
	var turn := angle_difference(look_angle, d.angle())
	var most := PI / LOOK_TURN_SEC * delta
	look_angle = wrapf(look_angle + clampf(turn, -most, most), -PI, PI)
	if _turn_at > pred_tick:
		return                       # (v77.1) one turn at a time: the next once this one is applied
	var now := Net.way(pred.facing)
	var stick := LOOK_STICK_DEG * (3.0 if near < LOOK_NEAR else 1.0)
	if absf(rad_to_deg(angle_difference(now.angle(), look_angle))) > 22.5 + stick:
		var way := Vector2.from_angle(look_angle)
		var best := pred.facing
		var best_dot := -2.0
		for k in range(1, Net.DIRS + 1):
			var dot := Net.way(k).dot(way)
			if dot > best_dot:
				best_dot = dot
				best = k
		face(best)


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
	## A pirate, free or (v70) in our handcuffs.
	return roster.has(id) and (int(roster[id]["kind"]) == Net.KIND_PIRATE or int(roster[id]["kind"]) == Net.KIND_PRISONER)


func is_prisoner(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_PRISONER


func send_drop() -> void:
	## Puts the thing in the hand down here.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_DROP]), ENetPacketPeer.FLAG_RELIABLE)


func send_inflate() -> void:
	## (v98) Let the suit down, or seal it again.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_INFLATE]), ENetPacketPeer.FLAG_RELIABLE)


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


func gear_of(id: int) -> int:
	## (v100) Net.GEAR_* bits: what that character wears over its clothes.
	return int(gear.get(id, 0))


func held_by(id: int) -> int:
	## (v74) The thing in that character's hand, as it is drawn: our own at once, others' as told.
	if id == my_id:
		return slots[hand] if hand >= 0 and hand < slots.size() else Net.ITEM_NONE
	return int(holding.get(id, Net.ITEM_NONE))


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


const SPACE_SCALE := 4.0             # (v95) as Arena.SCALE: cells of space per unit of the system's map


func arena_on() -> bool:
	## (v92) Is a fight going on in real time (the ships flying in space)?
	return arena.on()


func send_pilot(keys: int) -> void:
	## (v92) The pilot's keys at the ship's controls in the fight (Arena.KEY_* bits): sent when they
	## change, and again now and then while held (the server lets go of them after 2 s).
	var now := Time.get_ticks_msec()
	if _peer == null or (keys == _pilot_sent and now - _pilot_ms < 500):
		return
	_pilot_sent = keys
	_pilot_ms = now
	_peer.send(0, PackedByteArray([Net.C_PILOT, keys]), ENetPacketPeer.FLAG_RELIABLE)


func send_turret(gun: int, aim: Vector2, fire: bool) -> void:
	## (v92) Aims the gun of the mount we stand at on that point of the fight's space (and holds its trigger).
	if _peer == null:
		return
	var msg := PackedByteArray([Net.C_TURRET, gun, 0, 0, 0, 0, 1 if fire else 0])
	msg.encode_s16(2, clampi(roundi(aim.x * 8.0), -32768, 32767))
	msg.encode_s16(4, clampi(roundi(aim.y * 8.0), -32768, 32767))
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func send_shield(up: bool, dir: float, vent: bool) -> void:
	## (v94) The pilot's shield (Arena.shield_asked): up or down, its arc to that heading, and venting now.
	if _peer == null:
		return
	var msg := PackedByteArray([Net.C_SHIELD, (1 if up else 0) | (2 if vent else 0), 0, 0])
	msg.encode_s16(2, clampi(roundi(wrapf(dir, -PI, PI) * 1000.0), -32768, 32767))
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


func send_evade() -> void:
	## (v68) The pilot's evade; only from the ship's controls in a fight.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_EVADE]), ENetPacketPeer.FLAG_RELIABLE)


func send_alert(level: int) -> void:
	## (v68) The alert level (Net.ALERT_*); only from the ship's controls.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_ALERT, level]), ENetPacketPeer.FLAG_RELIABLE)


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
	## (v86) Docked to the other ship of our fleet, it is still a target for ours; and a wingman may fight us.
	return lead_fighting() or wing_fighting()


func lead_fighting() -> bool:
	## (v86) The pirate ship alongside fights the ship of our fleet we are aboard.
	## (The server says so: not while it is docked to this very ship.)
	return int((foes[0] as PackedByteArray)[0]) == 1 and pirates_alongside()


func wing_fighting() -> bool:
	## (v86, the author's E1) A second pirate ship fights us from the dark.
	return int((foes[1] as PackedByteArray)[0]) == 1


func send_drone(action: int, a: int = 0) -> void:
	## Launches, steers or blows up the scouting drone (Net.DRONE_*); only from the drone monitor.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_DRONE, action, a]), ENetPacketPeer.FLAG_RELIABLE)


func send_bench(action: int, item: int) -> void:
	## (v58) Starts (or puts down) work at the workbench on a gun in the locker.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_BENCH, action, item]), ENetPacketPeer.FLAG_RELIABLE)


func send_smes(which: int, action: int, value: int) -> void:
	## (v61) A change at an SMES's terminal (see Power.asked).
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_SMES, which, action, clampi(value, 0, 255)]), ENetPacketPeer.FLAG_RELIABLE)


func smes_at(cell: int) -> int:
	## (v61) The number of the SMES in that wall cell (in `smes`), or -1.
	for i in smes.size():
		if int(smes[i]["cell"]) == cell:
			return i
	return -1


func send_comms(choice: int) -> void:
	## (v63) Answers the call on the comms console our character stands at.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_COMMS, choice]), ENetPacketPeer.FLAG_RELIABLE)


func send_holo(on: bool) -> void:
	## Starts or stops watching the holomap our character stands at.
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_HOLO, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


func send_blast(which: int) -> void:
	## (v60) At a holomap: locks a door against boarders (or unlocks it), or all of them (Net.BLAST_ALL, Net.BLAST_NONE).
	if _peer != null:
		_peer.send(0, PackedByteArray([Net.C_BLAST, which]), ENetPacketPeer.FLAG_RELIABLE)


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


func _shut_pane(cell: int, down: bool) -> void:
	## (v91) A window's shutter comes down or goes up: it stops sight and light as the server's does.
	if shut_panes.has(cell) == down or not map.panes.has(cell):
		return
	if down:
		shut_panes[cell] = true
	else:
		shut_panes.erase(cell)
	map.set_pane(cell, down)
	other_changes += 1                   # (what light and sight draw is made again)


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
	return other_here() and not other_derelict and not other_wreck and not other_rock


func other_dark() -> bool:
	## Is the ship alongside one without light of its own (a derelict, or a wreck)?
	return other_here() and (other_derelict or other_wreck or other_rock)


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
	## Where the ship is inside its sector right now: (v95) where the first ship of our fleet flies in space
	## (Arena.SCALE cells to a unit); with no space (an old server's way) in a straight line at a fixed speed.
	if arena.flying():
		var s: Dictionary = arena.state(0, render_tick())
		if not s.is_empty():
			return (s["pos"] as Vector2) / SPACE_SCALE
	if not ship_moving:
		return ship_from
	return ship_from.move_toward(ship_dest, Sectors.SHIP_SPEED * maxf(server_now() - ship_tick, 0.0) / Net.TICK_HZ)


func ship_under_way() -> bool:
	if arena.flying():
		var s: Dictionary = arena.state(0, render_tick())
		return arena.course or (not s.is_empty() and (s["vel"] as Vector2).length() > 0.05)
	return ship_moving and not ship_pos().is_equal_approx(ship_dest)


func space_on() -> bool:
	## (v95) Our ships are bodies in space (the helm flies them with WASD, the guns fire with no enemy near).
	return arena.flying()


func server_now() -> float:
	## Our best guess of the server's tick right now.
	return now_ticks() + _recv_offset


func knows_sector(id: int) -> bool:
	## The crew knows what is in a sector the server's chart shows (v64, the author's C7:
	## where we have been, what the sensors reach, traders and stations; not inside a nebula).
	var known: PackedByteArray = road["known"]
	if known.size() == sectors.count:
		return known[id] == 1
	return sectors.visited[id] == 1 or sectors.linked(sector, id) or sectors.kind[id] == Sectors.FLAGSHIP


func send_suit(on: bool) -> void:
	## Turns the suit's oxygen supply on or off.
	if phase == PLAYING:
		_peer.send(0, PackedByteArray([Net.C_SUIT, 1 if on else 0]), ENetPacketPeer.FLAG_RELIABLE)


static func _text_at(pkt: PackedByteArray, o: int) -> Array:
	## [the text, where the next field starts] (u16 length, UTF-8), or ["", -1] if the packet is short.
	if o + 2 > pkt.size():
		return ["", -1]
	var n := pkt.decode_u16(o)
	if o + 2 + n > pkt.size():
		return ["", -1]
	return [pkt.slice(o + 2, o + 2 + n).get_string_from_utf8(), o + 2 + n]


func _read_comms(pkt: PackedByteArray) -> void:
	if pkt.size() < 4:
		return
	var got := {"state": pkt[1], "seconds": pkt.decode_u16(2), "at": Time.get_ticks_msec(), "choices": []}
	var t := _text_at(pkt, 4)
	if int(t[1]) < 0:
		return
	got["title"] = t[0]
	t = _text_at(pkt, int(t[1]))
	if int(t[1]) < 0:
		return
	got["text"] = t[0]
	var o: int = t[1]
	if o >= pkt.size():
		return
	var n := pkt[o]
	o += 1
	for i in n:
		if o >= pkt.size():
			return
		var f := pkt[o]
		t = _text_at(pkt, o + 1)
		if int(t[1]) < 0:
			return
		got["choices"].append([f, t[0]])
		o = t[1]
	if got["state"] == Net.COMMS_CALL and comms.get("state", Net.COMMS_QUIET) != Net.COMMS_CALL:
		comms_seen += 1
	comms = got


func _read_road(pkt: PackedByteArray) -> void:
	## (v64) The hunters, what the chart shows, the places found in our system.
	if pkt.size() < 5:
		return
	var got := {"fog": pkt[1] & 1 != 0, "hunter_s": pkt.decode_u16(2), "hunters": [], "known": PackedByteArray(), "places": []}
	var o := 5
	for i in pkt[4]:
		if o + 2 > pkt.size():
			return
		got["hunters"].append([pkt[o], pkt[o + 1] != 0])
		o += 2
	if o >= pkt.size():
		return
	var n := pkt[o]
	got["known"] = pkt.slice(o + 1, o + 1 + n)
	o += 1 + n
	if o >= pkt.size():
		return
	for i in pkt[o]:
		var at := o + 1 + i * 5
		if at + 5 > pkt.size():
			break
		# (v96) kind, where, taken, the drawing it is seen by in space (255: none)
		got["places"].append([pkt[at], Vector2(pkt[at + 1], pkt[at + 2]), pkt[at + 3] != 0, pkt[at + 4]])
	var end := o + 1 + pkt[o] * 5
	got["main_look"] = pkt[end] if end < pkt.size() else 255
	road = got
	ship_changes += 1


func _read_story(pkt: PackedByteArray) -> void:
	if pkt.size() < 10:
		return
	var got := {"flags": pkt[1], "flagship": Vector2i(pkt.decode_s16(2), pkt.decode_s16(4)), "growth": pkt[6],
		"grow_s": pkt.decode_u16(7), "quests": [], "marks": []}
	var o := 10
	for i in pkt[9]:
		if o + 7 > pkt.size():
			return
		var q := {"kind": pkt[o], "at": Vector2i(pkt.decode_s16(o + 1), pkt.decode_s16(o + 3)), "reward": pkt.decode_u16(o + 5)}
		var t := _text_at(pkt, o + 7)
		if int(t[1]) < 0:
			return
		q["title"] = t[0]
		t = _text_at(pkt, int(t[1]))
		if int(t[1]) < 0:
			return
		q["text"] = t[0]
		o = t[1]
		got["quests"].append(q)
	if o < pkt.size():
		var n := pkt[o]
		o += 1
		for i in n:
			if o + 5 > pkt.size():
				break
			got["marks"].append([pkt[o], Vector2i(pkt.decode_s16(o + 1), pkt.decode_s16(o + 3))])
			o += 5
	story = got
	ship_changes += 1


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
	## 19 = an intercom, 20 = a holomap monitor, 21 = the drone monitor (v54), 22 = the workbench (v58),
	## 23 = (v59) where the crate of gear in hand goes (or the module bay, with empty hands): hold to install,
	## 24 = the module bay with something else in hand,
	## 25 = (v60) a gun mount where the gun in hand goes up (or, with empty hands, its gun comes down),
	## 26 = an autodoc, 27 = the body scanner, 28 = (v61) an SMES's terminal,
	## 29 = (v61) our hull from outside, out in space: its strength is mended with patches,
	## 30 = (v63) the comms console, 31 = a hydroponic tray, 32 = a cryopod,
	## 33 = (v67) the engine with a can of fuel in hand, 34 = a wall of a dark ship alongside (scrap to cut),
	## 40 = (v69) a door whose broken lock can be mended,
	## 41 = (v70) a pirates' bomb in front or underfoot (held E disarms it), 42 = a shut door with a welder in hand,
	## 43 = a welded door (nothing to do without a welder), 44 = (v71) the galley's stove,
	## 45 = (v81) an ore vein of the asteroid alongside (held E digs ore out), 46 = (v86) the shuttle's dock console,
	## 47 = (v91) a first-aid box, 48 = a spare parts box, 49 = (v92) a gun mount in a fight in real time
	## (no gun or round for it in hand): its controls (aim with the mouse, fire with the button),
	## 50 = (v93) our shield generator in working order: a press turns the shield's shape (a bubble or an arc),
	## 51 = (v96) our boarding pod at its bay, or stuck in the pirate's hull: a press sits one in.
	## `facing`: as if our character faced that way (a click turns it first).
	if phase != PLAYING or my_cond != Net.COND_OK:
		return 0
	var f := pred.facing if facing < 0 else facing
	var bomb := floor_cell(f)
	if bomb >= 0 and top_thing(bomb) == Net.ITEM_BOMB:
		return 41                            # (v70) as Repairs.usable_ahead: a bomb comes first
	var cell := map.use_ahead(pred.x, pred.y, f, holes)
	if cell >= 0:
		if holes.has(cell):
			return 1
		if map.oxygen.has(cell):
			return 2
		if broken.has(cell):
			return 5
		if map.floats(pred.x, pred.y) and map.hull.has(cell) and not map.is_other(cell):
			return 29
		if gear_here(cell) != "-":
			return 23
		if map.bay.has(cell):
			return 24
		if map.chart.has(cell):
			return 3
		if map.helm.has(cell):
			return 4
		if map.smes.has(cell) or map.smes_small.has(cell):
			return 28
		if map.engine.has(cell) and hand < slots.size() and slots[hand] == Net.ITEM_FUEL:
			return 33
		if map.engine.has(cell) or map.air_plant.has(cell):
			return 8
		if map.is_other(cell) and other_rock and map.cells[cell] == int(map.tile_ids.get("rock_ore", -2)):
			return 45                        # (v81) an ore vein of the asteroid alongside
		if map.is_other(cell) and other_dark() and not other_rock and map.walk[cell] == 0 and map.door_of[cell] < 0:
			return 34
		if map.locker.has(cell):
			return 12
		if map.lock_pump.has(cell):
			return 15
		if map.gun_console.has(cell):
			return 17
		if turret_here(cell) >= 0:
			return 49                        # (v92) in a fight, empty hands at a mount with a gun take its controls
		if mount_here(cell) != "-":
			return 25
		if map.guns.has(cell):
			return 8
		if map.autodoc.has(cell):
			return 26
		if map.scanner.has(cell):
			return 27
		if map.intercom.has(cell):
			return 19
		if map.holo.has(cell):
			return 20
		if map.drone_console.has(cell):
			return 21
		if map.bench.has(cell):
			return 22
		if map.comms.has(cell):
			return 30
		if map.dock.has(cell):
			return 46                        # (v86) the shuttle's dock console
		if pod_at(cell) >= 0:
			return 51                        # (v96) our boarding pod: at its bay, or stuck in the pirate's hull
		if map.teleporter.has(cell):
			return 52                        # (v97) the teleporter's pad: a press beams whoever stands by it
		if map.trays.has(cell):
			return 31
		if map.cryo.has(cell):
			return 32
		if map.shield.has(map.machine_of(cell)) and not map.is_other(cell):
			return 50                        # (v93) the shield's shape
		if map.med_box.has(cell):
			return 47
		if map.tech_box.has(cell):
			return 48
		if map.stove.has(cell):
			return 44                        # (v71) the galley's stove
		var door := map.door_of[cell]
		if door >= 0:
			if hand < slots.size() and slots[hand] == Net.ITEM_WELDER and doors.is_shut(door):
				return 42
			if doors.welded[door] == 1:
				return 43                    # (v70) welded shut: only said so
			if doors.is_shut(door) and doors.held_by_partner(door):
				return 16
			if doors.jammed[door] == 1:
				return 10
			if doors.faulty[door] == 1:
				return 11
			if doors.is_sealed(door):
				return 9
			if doors.picked[door] == 1:
				return 40
			if doors.barred(door, map.door_access[door], pred.access) and not map.leaving(pred.x, pred.y, door):
				return 18
	if lying_near(f) >= 0:
		return 13
	if floor_cell(f) >= 0:
		return 14
	var here := pred.y * map.width + pred.x
	if map.climb[here] >= 0:
		return 6 if map.climb[here] > here else 7
	return 0


func gear_here(cell: int) -> String:
	## (v59) As Outfit.can on the server: "" if the crate of gear in our hand goes
	## in at that wall cell (or, with empty hands at the module bay, a module comes
	## out), "-" if that is not the place for it, else why not, in the player's words.
	if cell < 0:
		return "-"
	var item: int = slots[hand] if hand < slots.size() else Net.ITEM_NONE
	var g := Items.gear_of(item)
	if g == Gear.TELEPORT:
		if not map.teleporter.has(cell):
			return "-"
		if tele_state != Net.TELE_NONE:
			return "Телепорт уже стоит в платформе."
	elif g != Gear.NONE:
		var sys := Gear.system_of(g)
		if sys >= 0:
			var machines: Dictionary = map.shield if sys == Gear.SYS_SHIELD else (map.holo if sys == Gear.SYS_SENSORS else
				(map.smes if sys == Gear.SYS_COILS else map.engine))
			if not machines.has(cell):
				return "-"
			if gear_tiers.size() > sys and gear_tiers[sys] == Gear.tier(g):
				return "Это уже установлено: %s." % Gear.name_of(g).to_lower()
		else:
			if not map.bay.has(cell):
				return "-"
			if Gear.extender(g):
				if gear_modules.size() >= Gear.MODULE_SLOTS_MAX:
					return "Стойка уже расширена: третья ячейка на месте."
			else:
				if gear_modules.has(g):
					return "Этот модуль уже стоит в стойке."
				var room := gear_modules.has(Gear.NONE)
				for m in gear_modules:
					room = room or (m != Gear.NONE and Gear.module_of(m) == Gear.module_of(g))
				if not room:
					return "Все ячейки стойки заняты: сначала выньте модуль (держите E с пустыми руками)."
	elif item == Net.ITEM_NONE and map.bay.has(cell):
		if gear_modules.count(Gear.NONE) == gear_modules.size():
			return "Модульная стойка пуста: модули в ящиках носят из шкафа снабжения."
	else:
		return "-"
	if job != Net.JOB_ENGINEER:
		return "Корабельные модули ставят и снимают только инженеры."
	return ""


func mount_here(cell: int) -> String:
	## (v60) As Mounts.can on the server: "" if the gun in our hand goes up on the
	## mount at that cell (or, with empty hands, the gun on it comes down), "-" if
	## there is nothing of that to do there, else why not, in the player's words.
	var i := map.guns.find(cell)
	if i < 0:
		return "-"
	var item: int = slots[hand] if hand < slots.size() else Net.ITEM_NONE
	var on: int = gun_weapon[i] if i < gun_weapon.size() else Weapons.NONE
	if item != Net.ITEM_NONE and on != Weapons.NONE and item == Weapons.ammo(on):
		# (v68) a round for its breech (Mounts.LOAD_MAX = 4)
		if broken.has(cell):
			return "-"
		var n: int = mount_loaded[i] if i < mount_loaded.size() else 0
		return "Казённик орудия полон: %d из %d." % [n, 4] if n >= 4 else ""
	if item != Net.ITEM_NONE and Weapons.of_item(item) != Weapons.NONE:
		if Weapons.of_item(item) == Weapons.GUARD:
			return "«Заслон» ставят в его собственное гнездо с пульта орудий."
		if Weapons.damaged(item):
			return "Орудие повреждено: сначала его чинят на верстаке."
		var kind := ArenaShape.kind_in_fleet(map, cell)
		if not Weapons.fits(Weapons.of_item(item), kind):     # (v94.1, as Mounts.misfit_of)
			return "%s не встаёт в гнездо «%s». %s" % [Weapons.name_of(Weapons.of_item(item)), ArenaShape.MOUNT_NAMES_OF[kind],
				Weapons.fit_words(Weapons.of_item(item))]
		return "-" if broken.has(cell) else ""
	if item == Net.ITEM_NONE and on != Weapons.NONE and not broken.has(cell) and not arena_on():
		return ""                            # (v92: in a fight, empty hands take the gun's controls instead)
	return "-"


func turret_here(cell: int) -> int:
	## (v92) The number of the gun at that mount, if "use" there takes its controls in a fight (anything
	## in hand but a gun or a round for it; Mounts.can refuses to take the gun down then), else -1.
	var i := map.guns.find(cell)
	if i < 0 or not space_on() or broken.has(cell):
		return -1
	var item: int = slots[hand] if hand < slots.size() else Net.ITEM_NONE
	if item == Net.ITEM_NONE and not arena_on():
		return -1                            # (v95) out of a fight empty hands take the gun down, as before
	var on: int = gun_weapon[i] if i < gun_weapon.size() else Weapons.NONE
	if on == Weapons.NONE or (item != Net.ITEM_NONE and (Weapons.of_item(item) != Weapons.NONE or item == Weapons.ammo(on))):
		return -1                            # (a gun in hand goes up, a round goes into the breech, as before)
	return i


func target_cell() -> int:
	## (v73) The cell of what the "use" key acts on now (see use_target): what is
	## in front, the thing on the floor, the one lying there, the ladder underfoot. -1: nothing.
	var t := use_target()
	if t == 0:
		return -1
	if t == 13:
		var id := lying_near()
		if ents.has(id):
			var e: Ent = ents[id]
			return e.y * map.width + e.x
		return -1
	if t == 14 or t == 41:
		return floor_cell()
	if t == 6 or t == 7:
		return pred.y * map.width + pred.x
	return use_cell()


func usable_at(cell: int) -> bool:
	## Is there something in that cell the "use" key (or a click) works on, near
	## or not: a thing on a wall, a door, a hole, things on the floor, somebody
	## lying, a ladder? For the outline under the mouse (WorldView._draw_hover).
	if cell < 0 or cell >= map.cells.size():
		return false
	cell = map.machine_of(cell)              # (v91) any piece of a wide machine
	if holes.has(cell) or floor_things.has(cell) or map.door_of[cell] >= 0 or map.climb[cell] >= 0 or map.guns.has(cell) \
			or gear_here(cell) != "-":
		return true
	for things: Dictionary in [map.oxygen, map.chart, map.helm, map.engine, map.air_plant, map.locker, map.lock_pump,
			map.gun_console, map.intercom, map.holo, map.drone_console, map.bench, map.bay, map.autodoc, map.scanner, map.stove,
			map.smes, map.smes_small, map.comms]:
		if things.has(cell):
			return true
	if map.trays.has(cell) or map.cryo.has(cell):
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
	var cell := map.machine_of(c.y * map.width + c.x)
	var here := pred.y * map.width + pred.x
	var order: Array[int] = [pred.facing]
	for f in range(1, Net.DIRS + 1):     # (v74) the slants too
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


func lock_inside_air(pump: int) -> float:
	## (v73) The air on our own side of that airlock's inner door (0..1).
	var c := map.lock_inside(pump)
	return float(air[c]) / Net.AIR_FULL if c >= 0 else 1.0


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
	## (v70) A broken leg slows it too: then only while it holds somebody.
	## (v71) Weak with hunger too.
	return _have_self and pred.slow and my_cond == Net.COND_OK and (not (leg_broken or weak) or hauling)


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


func send_take(cell: int, at: int) -> void:
	## (v80) Takes one chosen thing off the floor in our cell or one next to us (Net.C_TAKE).
	if phase != PLAYING:
		return
	var msg := PackedByteArray([Net.C_TAKE, 0, 0, 0, 0, at])
	msg.encode_u32(1, cell)
	_peer.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)


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
	## Docked with a trader or (v69) a supply station, with power for the link (the same rule as Supplies.can_trade).
	return powered() and sectors.count > 0 and (sectors.kind[sector] == Sectors.TRADER or sectors.kind[sector] == Sectors.STATION) \
		and sectors.within_reach(sector, ship_pos()) and not ship_moving   # (v96, my M3 pick) once stopped by it


func at_station() -> bool:
	## (v69) Trading with a supply station: it only sells its few things (see Supplies.trader_here).
	return sectors.count > 0 and sectors.kind[sector] == Sectors.STATION


func powered() -> bool:
	## The ship has power: the server says so (from the engine, or v61 the SMES carrying it).
	return _power


func power_at(cell: int) -> bool:
	## (v61) Does this cell have power: the whole ship's, or the bridge's backup in the room it keeps lit?
	return _power or _backup and map.on_backup(cell)


func light_at(cell: int) -> bool:
	## (v68) Is there light in that cell: power with the lights' breaker on, or the bridge (its backup keeps it lit).
	return (_power and _lights) or ((_power or _backup) and map.on_backup(cell))


func lights_on() -> bool:
	return _lights


func bridge_lit() -> bool:
	## (v61) The ship is dark, but the bridge's backup SMES keeps its room going.
	return not _power and _backup


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
		if int(roster[id]["kind"]) != Net.KIND_CORPSE and not is_pirate(id):
			n += 1
	return n


func prisoners() -> int:
	## (v70) Pirates in our handcuffs aboard.
	var n := 0
	for id: int in roster.keys():
		if is_prisoner(id):
			n += 1
	return n


func is_corpse(id: int) -> bool:
	return roster.has(id) and int(roster[id]["kind"]) == Net.KIND_CORPSE


func send_respawn() -> void:
	## Dead: ask to come back as a new crew member (the server allows it after a few seconds).
	## (v76) Out cold: give up (the character dies at once; R again brings a new one from the reserve).
	if phase == PLAYING and (my_cond == Net.COND_DEAD or my_cond == Net.COND_CRIT and health <= 0):
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
	if is_prisoner(id):
		return "%s (пленный)" % roster[id]["name"]
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
		if shuttle_to >= 0:
			shuttle_done = minf(shuttle_done + delta / Net.SHUTTLE_SECONDS, 1.0)


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
				hello.append(wanted_ship)        # (v85)
				hello.append(1 if woman else 0)  # (v87)
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
			at += 2
			gun_fx = pkt.slice(at, at + n)
			at += n
			if pkt.size() >= at + 4:
				guard = pkt[at]
				guard_charge = pkt[at + 1]
				guard_flags = pkt[at + 2]
				enemy_guard = pkt[at + 3] == 1
				enemy_fx = pkt.slice(at + 4, at + 4 + enemy_weapons.size())
				# (v59) its guns' charges, seen by the top sensors (255 = not seen)
				enemy_charge = pkt.slice(at + 4 + enemy_weapons.size(), at + 4 + enemy_weapons.size() * 2)
				# (v68) the fight's goal
				var g := at + 4 + enemy_weapons.size() * 2
				if pkt.size() >= g + 5:
					goal = pkt[g]
					goal_flags = pkt[g + 1]
					cargo_room = pkt[g + 2]
					goal_pay = pkt.decode_u16(g + 3)
				# (v86) which enemy our guns aim at, and both enemies at a glance
				if pkt.size() >= g + 16:
					foe = pkt[g + 5]
					foes = [pkt.slice(g + 6, g + 11), pkt.slice(g + 11, g + 16)]
		Net.S_GEAR:
			if not _ours(pkt) or pkt.size() < 4:
				return
			var at := 3
			var n: int = pkt[at]
			gear_tiers = pkt.slice(at + 1, at + 1 + n)
			at += 1 + n
			n = pkt[at]
			gear_modules = pkt.slice(at + 1, at + 1 + n)
			at += 1 + n
			phase_left = pkt[at] if pkt.size() > at else 0
			gear_flags = pkt[at + 1] if pkt.size() > at + 1 else 0
		Net.S_DRONE:
			drone_state = pkt[1]
			drone_at = pkt.decode_u16(2)
			drone_battery = pkt[4]
			drone_coming = pkt[5]
			drones = pkt[6]
		Net.S_MOUNTS:
			if not _ours(pkt) or pkt.size() < 4 + pkt[3] * 3:
				return
			mount_gunner = PackedByteArray()
			mount_wanted = PackedByteArray()
			mount_loaded = PackedByteArray()
			for i in pkt[3]:
				mount_gunner.append(pkt[4 + i * 3])
				mount_wanted.append(pkt[5 + i * 3])
				mount_loaded.append(pkt[6 + i * 3])
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
				var at := 11 + i * 5
				if pkt.size() >= at + 5:
					crew_bots.append([pkt.decode_u16(at), pkt[at + 2] & ~Net.ORDER_ARMS, pkt[at + 3], pkt[at + 4], pkt[at + 2] & Net.ORDER_ARMS != 0])
			var tail := 11 + pkt[10] * 5
			if pkt.size() >= tail + 3:
				if pkt[tail] != alert:
					alert = pkt[tail]
					alert_changes += 1
				evade_left = pkt[tail + 1] / 10.0
				evade_rest = pkt[tail + 2]
			if pkt.size() >= tail + 5:
				meteor_left = pkt[tail + 3] / 10.0
				meteor_tried = pkt[tail + 4] == 1
		Net.S_ECREW:
			ecrew_probe = pkt[3]
			ecrew = PackedInt32Array()
			ecrew_flags = PackedByteArray()
			for i in pkt[4]:
				ecrew.append(pkt.decode_u16(5 + i * 3))
				ecrew_flags.append(pkt[7 + i * 3])
		Net.S_TRADE:
			trade.clear()
			trade_wants = PackedByteArray()
			for i in pkt[1]:
				trade[pkt[2 + i * 3]] = pkt.decode_u16(3 + i * 3)
			var at := 2 + pkt[1] * 3
			trade_flags = pkt[at] if pkt.size() > at else 0
			trade_back = []
			if pkt.size() > at + 5:
				trade_deal = pkt[at + 1]
				trade_shares = pkt.slice(at + 2, at + 5)
				for i in pkt[at + 5]:
					var o := at + 6 + i * 3
					trade_back.append([pkt[o], pkt.decode_u16(o + 1)])
				var w := at + 6 + pkt[at + 5] * 3
				trade_wants = pkt.slice(w + 1, w + 1 + pkt[w]) if pkt.size() > w else PackedByteArray()
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
			if pkt.size() >= 5:
				holding[pkt.decode_u16(1)] = pkt[4]
			if pkt.size() >= 6:
				gear[pkt.decode_u16(1)] = pkt[5]
		Net.S_STORE:
			if not _ours(pkt):
				return
			store_air = pkt.decode_u16(3) / 10.0
			credits = pkt.decode_u16(5)
			store.clear()
			for i in pkt[7]:
				store[pkt[8 + i * 3]] = pkt.decode_u16(9 + i * 3)
			var t := 8 + pkt[7] * 3
			if pkt.size() >= t + 5:
				fuel = pkt.decode_u16(t)
				jump_cost = maxi(pkt[t + 2], 1)
				fuel_max = pkt.decode_u16(t + 3)
		Net.S_CAMPAIGN:
			if pkt.size() >= 20 and pkt.decode_u16(18) != my_ship:
				pass                         # (v85) another ship of our fleet's hull
			elif pkt.size() >= 14:
				hull = pkt[1]
				reserve = pkt[2]
				over = pkt[3]
				sectors_seen = pkt.decode_u16(4)
				farthest = pkt.decode_u16(6)
				jumps = pkt.decode_u16(8)
				voyage_seconds = pkt.decode_u32(10)
				won = pkt.size() > 14 and pkt[14] == 1
				if pkt.size() >= 17:
					hull_max = maxi(pkt[15], 1)
					mode = pkt[16]
				if pkt.size() > 17:
					complex_repairs = (pkt[17] & Net.CAMPAIGN_COMPLEX) != 0     # (v71)
		Net.S_ME:
			if pkt.size() >= 2 + Net.SKILLS:
				job = pkt[1]
				skills = pkt.slice(2, 2 + Net.SKILLS)
				var flags: int = pkt[2 + Net.SKILLS] if pkt.size() > 2 + Net.SKILLS else 0
				is_admin = flags & Net.ME_ADMIN != 0
				is_host = flags & Net.ME_HOST != 0
				if _auth.access != Net.access_of(job):
					_auth.access = Net.access_of(job)
					pred.access = _auth.access
					_rebuild_prediction()
		Net.S_POWER:
			if not _ours(pkt):
				return
			_power = pkt[3] != 0
			_backup = pkt.size() > 4 and pkt[4] != 0
			_lights = pkt.size() <= 5 or pkt[5] != 0
			ship_changes += 1
			# without power doors open by hand: that is part of the walking rule we predict
			doors.manual = not _power
			_rebuild_prediction()
		Net.S_SMES:
			if not _ours(pkt) or pkt.size() < 4:
				return
			var n := pkt[3]
			var o := 4
			var got: Array = []
			for i in n:
				if o + 15 > pkt.size():
					return
				got.append({"small": pkt[o] == 1, "cell": pkt.decode_u16(o + 1), "charge": pkt.decode_u16(o + 3),
					"capacity": pkt.decode_u16(o + 5), "charging": pkt[o + 7] & 1 != 0, "output": pkt[o + 7] & 2 != 0,
					"input": pkt[o + 8], "level": pkt[o + 9], "input_max": pkt[o + 10], "output_max": pkt[o + 11],
					"in_now": pkt[o + 12] / 10.0, "out_now": pkt[o + 13] / 10.0, "status": pkt[o + 14]})
				o += 15
			smes = got
			if o + 9 <= pkt.size():
				power_mon = {"made": pkt[o], "base": pkt[o + 1], "used": pkt[o + 2], "budget": pkt[o + 3], "flags": pkt[o + 4],
					"seconds": pkt.decode_u16(o + 5), "reactor": pkt.decode_u16(o + 7)}
			if o + 13 <= pkt.size():
				panel = {"breakers": pkt[o + 9], "engines": pkt[o + 10], "over": pkt[o + 11], "rest": pkt[o + 12]}
		Net.S_COMMS:
			_read_comms(pkt)
		Net.S_STORY:
			_read_story(pkt)
		Net.S_ROAD:
			_read_road(pkt)
		Net.S_GARDEN:
			if pkt.size() >= 2:
				var got := {}
				var o := 2
				for i in pkt[1]:
					if o + 6 > pkt.size():
						break
					got[pkt.decode_u16(o)] = [pkt[o + 2], pkt[o + 3], pkt[o + 4], pkt[o + 5]]
					o += 6
				garden = got
				ship_changes += 1
		Net.S_SHOT:
			if pkt.size() >= 15:
				var by := pkt.decode_u16(13)
				shot.emit(pkt[1], pkt[2], Vector2(pkt.decode_s16(3), pkt.decode_s16(5)) / 16.0,
					Vector2(pkt.decode_s16(7), pkt.decode_s16(9)) / 16.0, float(pkt[11]) / Net.TICK_HZ, float(pkt[12]) / Net.TICK_HZ,
					-1 if by == 0xFFFF else by)
		Net.S_VOLLEY:
			if pkt.size() >= 7:
				var now := Time.get_ticks_msec() / 1000.0
				volleys.append([pkt[1], pkt[2], pkt[3], pkt[4] if pkt[4] != 255 else -1, now + float(pkt[5]) / Net.TICK_HZ,
					maxf(float(pkt[6]) / Net.TICK_HZ, 0.05), randi()])
				for i in range(volleys.size() - 1, -1, -1):
					if float(volleys[i][4]) + float(volleys[i][5]) + 2.0 < now:
						volleys.remove_at(i)
		Net.S_JOLT:
			if pkt.size() >= 7:
				jolt.emit(pkt[1], pkt[2], Vector2(pkt.decode_s16(3), pkt.decode_s16(5)))
		Net.S_SOUND:
			if pkt.size() >= 6:
				heard.emit(pkt[1], pkt.decode_s16(2), pkt.decode_s16(4))
		Net.S_BOARD:
			# (v85) we are aboard another ship of our fleet: what we are told from now on is about it
			if pkt.size() >= 4:
				my_ship = pkt.decode_u16(1)
				my_fleet = pkt[3]
				map.use_ship(my_fleet)
				_holo_cells()
				board_changes += 1
				ship_changes += 1
		Net.S_ARENA:
			if pkt.size() >= 7:
				arena.read(pkt)
		Net.S_ARENA_SHOT:
			if pkt.size() >= 2:
				arena.shot(pkt, Time.get_ticks_msec())
		Net.S_SHUTTLE:
			if pkt.size() >= 5 and pkt.size() >= 5 + pkt[4] * 2:
				shuttle_at = -1 if pkt[1] == 255 else pkt[1]
				shuttle_to = -1 if pkt[2] == 255 else pkt[2]
				var done := pkt[3] / 255.0
				if shuttle_to < 0 or absf(done - shuttle_done) > 0.08 or done > shuttle_done:
					shuttle_done = done          # (between the server's words it is moved on here)
				shuttle_riders.clear()
				for i in pkt[4]:
					shuttle_riders.append(pkt.decode_u16(5 + i * 2))
		Net.S_TELEPORT:
			if pkt.size() >= 3:
				tele_state = pkt[1]
				tele_secs = pkt[2]
		Net.S_POD:
			# (v96) our boarding pods (Pods.packet)
			if pkt.size() >= 2:
				var got := {}
				var o := 2
				for i in pkt[1]:
					if o + 7 > pkt.size():
						break
					var riders: Array[int] = []
					var n: int = pkt[o + 6]
					for k in n:
						if o + 9 + k * 2 <= pkt.size():
							riders.append(pkt.decode_u16(o + 7 + k * 2))
					got[pkt.decode_u16(o)] = {"state": pkt[o + 2], "secs": pkt[o + 3],
						"stuck": -1 if pkt.decode_u16(o + 4) == 0xFFFF else pkt.decode_u16(o + 4), "riders": riders}
					o += 7 + n * 2
				pods = got
		Net.S_SUMMARY:
			if pkt.size() >= 10:
				var deaths: Array = []
				var at := 10
				for i in pkt[9]:
					var pair: Array = []
					for k in 2:
						if at >= pkt.size():
							break
						var n: int = pkt[at]
						pair.append(pkt.slice(at + 1, at + 1 + n).get_string_from_utf8())
						at += 1 + n
					if pair.size() == 2:
						deaths.append(pair)
				var used: Array = []         # (v82) [name, times] people used each system
				if at < pkt.size():
					var things: int = pkt[at]
					at += 1
					for i in things:
						if at >= pkt.size():
							break
						var n: int = pkt[at]
						if at + 3 + n > pkt.size():
							break
						used.append([pkt.slice(at + 1, at + 1 + n).get_string_from_utf8(), pkt.decode_u16(at + 1 + n)])
						at += 3 + n
				summary = {"ships": pkt.decode_u16(1), "boarders": pkt.decode_u16(3), "earned": pkt.decode_u32(5), "deaths": deaths, "used": used}
		Net.S_HIT:
			if pkt.size() >= 8:
				hit.emit(pkt[1], pkt.decode_u16(2), pkt.decode_s16(4), pkt.decode_s16(6))
		Net.S_CHAT:
			var n := pkt.decode_u16(4)
			chat.emit(pkt.decode_u16(1), pkt[3], pkt.slice(6, 6 + n).get_string_from_utf8())
		Net.S_BOTLOG:
			if pkt.size() >= 9:
				var n := pkt.decode_u16(7)
				_bot_line(pkt.decode_u32(3), player_name(pkt.decode_u16(1)), pkt.slice(9, 9 + n).get_string_from_utf8())


const LOG_KEPT := 2000               # (v72) lines of the bots' log the crew window keeps (the file keeps all)
const LOG_FILE_MAX := 4 * 1024 * 1024


static func log_path() -> String:
	## (v72) crew_log.txt next to the game (run from the project: in user://), so the author can send it.
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("crew_log.txt")
	return "user://crew_log.txt"


func _bot_line(seconds: int, who: String, text: String) -> void:
	bot_log.append([seconds, who, text])
	bot_log_count += 1
	if bot_log.size() > LOG_KEPT:
		bot_log = bot_log.slice(bot_log.size() - LOG_KEPT)
	if DisplayServer.get_name() == "headless":
		return                               # (test clients and the server keep no file)
	if _log_file == null:
		var path := log_path()
		_log_file = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else null
		if _log_file != null and _log_file.get_length() > LOG_FILE_MAX:
			_log_file.close()
			_log_file = null
		if _log_file == null:
			_log_file = FileAccess.open(path, FileAccess.WRITE)
		if _log_file == null:
			return
		_log_file.seek_end()
		_log_file.store_line("=== Игра %s ===" % Time.get_datetime_string_from_system(false, true))
	_log_file.store_line("%s  %s: %s" % [clock(seconds), who, text])
	_log_file.flush()


static func clock(seconds: int) -> String:
	return "%d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]


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
	var rock := false
	var derelict := false
	other_docked = false
	for id: int in ships.keys():
		if id != my_ship and int(ships[id]["kind"]) != Net.SHIP_CREW:   # (v85: the fleet's ships are drawn in our grid)
			at = ships[id]["at"]
			wreck = int(ships[id]["kind"]) == Net.SHIP_WRECK
			rock = int(ships[id]["kind"]) == Net.SHIP_ROCK
			derelict = int(ships[id]["kind"]) == Net.SHIP_DERELICT   # (v84: an own derelict's drawing is not the first)
			kind = int(ships[id]["layout"]) if int(ships[id]["layout"]) < map.others.size() else Net.OTHER_DERELICT
			other_docked = ships[id]["docked"]
	if at != map.other_at or (at != ShipMap.NO_OTHER and kind != map.other_kind) or wreck != other_wreck or rock != other_rock \
			or derelict != other_derelict:
		if at != map.other_at or kind != map.other_kind:
			map.place_other(at, kind)
			for d in range(map.other_first_door, map.doors.size()):
				doors.ready[d] = Doors.CLOSED
				doors.set_flags(d, 0)
		other_wreck = wreck
		other_rock = rock
		other_derelict = derelict
		for d in range(map.other_first_door, map.doors.size()):
			doors.dead[d] = 1 if derelict or wreck or rock else 0
		other_changes += 1
		ship_changes += 1
		_rebuild_prediction()


func _holo_cells() -> void:
	## The cells of our ship's floor, as the server sends their air (v86, the author's note: only the ship of
	## our fleet we are aboard, as Holomap.setup does for each).
	holo_cells = PackedInt32Array()
	for c in map.base_walk.size():
		if map.on_ship(c) and (map.fleet_size() < 2 or map.fleet_of(c) == my_fleet):
			holo_cells.append(c)


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
	# (v84, the author's H1) the server sends the drawings of its own the game is played with: nothing to copy by hand
	var maps := ShipMap.unpack_maps(pkt, 14 + n)
	var others: Array = maps.get("others", ShipMap.other_maps())
	if not maps.is_empty():
		ShipMap.drawings = maps["drawings"]
	map = ShipMap.new()
	var problem := map.load_from(map_name)
	for other_map: String in others:
		if problem == "" and map.add_other(other_map) < 0:
			problem = "Не найдена карта «%s»." % other_map
	_holo_cells()
	arena.reset()
	arena.map = map
	shuttle_docks = map.shuttle_docks()
	shuttle_at = -1
	shuttle_to = -1
	shuttle_riders.clear()
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
	other_rock = false
	other_derelict = false
	pumps.clear()
	air.resize(map.width * map.height)
	air.fill(0)
	holes.clear()
	shut_panes.clear()
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
				_apply_record(pkt.decode_u16(pos), pkt.decode_s16(pos + 2), pkt.decode_s16(pos + 4), pkt[pos + 6], s_tick, pkt[pos + 7])
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
			bleeding = (pkt[pos + 3] & 2) != 0
			arm_broken = (pkt[pos + 3] & 4) != 0
			leg_broken = (pkt[pos + 3] & 8) != 0
			concussed = (pkt[pos + 3] & 16) != 0
			hauling = (pkt[pos + 3] & 32) != 0
			weak = (pkt[pos + 3] & 64) != 0
			deflated = (pkt[pos + 3] & 128) != 0
			eshield = pkt[pos + 7 + Net.SLOTS + Net.WORN]
			meal = pkt[pos + 5 + Net.SLOTS + Net.WORN]
			meal_left = pkt[pos + 6 + Net.SLOTS + Net.WORN] * 5
			work = pkt[pos + 4]
			slots = pkt.slice(pos + 5, pos + 5 + Net.SLOTS)
			worn = pkt.slice(pos + 5 + Net.SLOTS, pos + 5 + Net.SLOTS + Net.WORN)
			patches = carried(Net.ITEM_PATCH)
			scrap = carried(Net.ITEM_SCRAP)
			parts = carried(Net.ITEM_PART)
			boards = carried(Net.ITEM_BOARD)
			toolbox = carried(Net.ITEM_TOOLBOX) > 0
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
				var state: int = pkt[pos + 4]        # (v91) 1 a hole, 2 a hole behind a window's shutter, 3 a shutter down
				if state == 1 or state == 2:
					holes[cell] = true
				else:
					holes.erase(cell)
				_shut_pane(cell, state >= 2)
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
			for cell: int in shut_panes.keys():
				if _outside_view(cell % map.width, cell / map.width):
					_shut_pane(cell, false)
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


func _apply_record(id: int, x: int, y: int, look: int, s_tick: int, off: int = 10) -> void:
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
	var ox := Net.off_x(off)
	var oy := Net.off_y(off)
	var e: Ent = ents.get(id)
	if e == null:
		e = Ent.new()
		e.id = id
		e.x = x
		e.y = y
		e.ox = ox
		e.oy = oy
		e.prone = Net.off_prone(off)
		e.hold = Net.off_hold(off)
		e.facing = facing
		e.look = look
		e.cond = Net.look_cond(look)
		e.light = Net.look_light(look)
		ents[id] = e
		return
	e.look = look
	e.cond = Net.look_cond(look)
	e.light = Net.look_light(look)
	e.prone = Net.off_prone(off)
	e.hold = Net.off_hold(off)
	var was_qx := e.x * 4 + e.ox
	var was_qy := e.y * 4 + e.oy
	var qx := x * 4 + ox
	var qy := y * 4 + oy
	if was_qx != qx or was_qy != qy:
		var far := maxi(absi(qx - was_qx), absi(qy - was_qy))
		if far == 4 or far == 1:
			# somebody hauling, or being hauled, takes longer over a step; (v74) a slant one too;
			# (v78) a player's step is a quarter of a tile, a quarter of the time (lying down: crawling)
			var span := Net.DRAG_TICKS if Net.look_slow(look) or e.prone else Net.MOVE_TICKS
			if far == 1:
				span = maxi(span / 4, 1)
			if qx != was_qx and qy != was_qy:
				span = Mover.slant_span(span, s_tick)
			e.steps.append([s_tick, was_qx * 0.25, was_qy * 0.25, qx * 0.25, qy * 0.25, facing, span])
			if e.steps.size() > 24:
				e.steps.pop_front()
		else:
			e.steps.clear()          # moved further than one step: place it there
		e.x = x
		e.y = y
		e.ox = ox
		e.oy = oy
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
	_mark_held()
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
	_auth.span = maxi(pkt[o + 6] >> 4, 1)
	_auth.dir = pkt[o + 6] & 15
	var ack := pkt.decode_u16(o + 7)
	_auth.move_tick = pkt.decode_s32(o + 9)
	_auth.fx = pkt.decode_s16(o + 13)
	_auth.fy = pkt.decode_s16(o + 15)
	_auth.free_look = (pkt[o + 17] & 1) != 0
	_auth.fine = (pkt[o + 17] & 2) != 0      # (v78)
	_auth.prone = (pkt[o + 17] & 4) != 0
	_auth.hold = (pkt[o + 17] & 8) != 0      # (v81)
	_auth.ox = Net.off_x(pkt[o + 18])
	_auth.oy = Net.off_y(pkt[o + 18])
	_auth.rise = pkt[o + 19]                 # (v82)
	_auth_tick = s_tick
	for i in _inputs.size():
		if (int(_inputs[i][0]) & 0xFFFF) == ack:
			_inputs = _inputs.slice(i + 1)
			break
	_have_auth = true
	_rebuild_prediction()


func _mark_held() -> void:
	## (v81) The tiles others hold (the human wall), as the server marks them (Movement.mark_held).
	map.held.clear()
	for id: int in ents.keys():
		var e: Ent = ents[id]
		if id == my_id or not e.hold:
			continue
		var bx := e.x + signi(e.ox)
		var by := e.y + signi(e.oy)
		for t: Vector2i in [Vector2i(e.x, e.y), Vector2i(bx, e.y), Vector2i(e.x, by), Vector2i(bx, by)]:
			map.held[t.y * map.width + t.x] = id


func holds_position() -> bool:
	## (v81) Does our character hold its position (as predicted)?
	return _have_self and pred.hold


func toggle_hold() -> void:
	## (v81, the author's human wall) Hold the position, or let go: predicted as lying down is.
	if phase != PLAYING or not _have_self or my_cond != Net.COND_OK:
		return
	var on := _hold_to if _hold_at > pred_tick else pred.hold
	_send_input(Mover.LET_GO if on else Mover.HOLD)
	_hold_to = not on
	_hold_at = _last_apply


func _rebuild_prediction() -> void:
	## Rebuilds the prediction from the server's last word: start from that
	## state and the doors as the server describes them, and replay the input
	## changes the server has not confirmed yet.
	## (A door the server has shut since is treated as shut for the whole
	## replay. That is safe while doors stay open longer than the replayed
	## stretch: see Doors.HOLD_TICKS.)
	if not _have_auth:
		return
	_mark_held()
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

func hold_of(id: int) -> bool:
	## (v81) Does that character hold its position (the human wall)?
	if id == my_id:
		return holds_position()
	var e: Ent = ents.get(id)
	return e != null and e.hold


func prone_of(id: int) -> bool:
	## (v78) Is this character lying low (by its own choice, not knocked down)?
	if id == my_id and _have_self:
		return pred.prone
	var e: Ent = ents.get(id)
	return e != null and e.prone


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
		# (v78) by the tile we leave: our own steps are quarters
		if _haul_id != id:
			_haul_id = id
			_haul_to = Vector2(e.x, e.y)
			_haul_from = _haul_to
			_haul_cell = Vector2i(pred.x, pred.y)
			_haul_seen = pred.move_tick
		elif _haul_cell != Vector2i(pred.x, pred.y):
			_haul_from = _haul_to
			_haul_to = Vector2(_haul_cell)
			_haul_cell = Vector2i(pred.x, pred.y)
			_haul_seen = pred.move_tick
		var t := pred_time()
		var k := clampf((t - float(_haul_seen)) / float(Net.DRAG_TICKS), 0.0, 1.0)
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
	return [Vector2(e.x + e.ox * 0.25, e.y + e.oy * 0.25), e.facing, false, 0, e.cond]
