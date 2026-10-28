extends RefCounted
## What each client is told about the world, and when.
##
## Doors, holes in the hull, things on the floor and air go out in 16x16 chunks:
## a client is told everything in a chunk when it comes into its view (the 3x3
## chunks around its character, on every deck), then only the changes.
##
## Characters go out differently: each client is told only about those its
## character can actually see (the same rules of sight the client draws by:
## walls and shut doors in the way, the dark; since v69 all round, not only the
## cone ahead, which the client applies itself so a turn shows at once), those right next
## to it (felt, if not seen: needed to search or drag somebody), and those
## holding a lit flashlight on its deck (the beam gives them away). Anybody
## else is not sent at all, so a client cannot peek at what its player should
## not see. The server keeps, per client, what it last told it about each
## character (Player.known) and sends only the differences; one going out of
## sight is sent as Net.FACING_HIDDEN, so the client leaves a fading silhouette
## where it was last seen.
##
## Every CHECK_TICKS a client gets checksums of what it should know, to catch
## anything that went astray.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Doors := preload("res://src/shared/doors.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Sight := preload("res://src/shared/sight.gd")

const HEARTBEAT_TICKS := 10         # a client hears from the server at least this often
const SELF_REFRESH_TICKS := 20      # own state is re-confirmed at least this often
const CHECK_TICKS := 40             # how often a client gets a checksum of what it should know
const CONTACT := 1.5                # this close on the same deck somebody is felt, if not seen
const THERMAL_REACH := 7.0           # (v93) thermal goggles show the living through walls this far, on one's own deck
const SEEN_GRACE := 4               # ticks somebody stays sent after going out of sight: the client
                                    # judges sight by its own clock, a little apart from ours
const MARGIN_DEG := 12.0            # the cone is judged this much wider each side, for the same reason

var server: GameServer
var see_all := false                # tests: send every character in view, as before v39
var all_round := true               # (v69) send those behind us too; the client hides them (see set_round)

var _cw := 1                        # chunks across
var _ch := 1                        # chunk rows of one deck
var _deck_rows := 1                 # chunk rows from one deck to the next
var _doors_in: Array = []           # per chunk: the doors in it
var _door_change: Array = []        # per chunk: door records changed this tick
var _hull_change: Array = []        # per chunk: hull records changed this tick
var _air_change: Array = []         # per chunk: (cell, air) pairs changed since the last air send
var _floor_change: Array = []       # per chunk: floor records changed this tick
var _air_sent := PackedByteArray()  # per cell: the air level clients were last told
var _ship_sums := PackedInt64Array()   # per chunk: checksum of doors, hull and air as clients know them
var _ship_sums_tick := -1
var _sight_epoch := 0               # goes up whenever what blocks sight may have changed (doors, power, the other ship)
var _lit := {}                      # cells a flashlight lights this tick (worked out only when needed)
var _lit_tick := -1
var lines := {}                     # lines of sight between cells, as Sight.clear_cached keeps them
var _prep_tick := -1                # what every character looks like this tick (see _prepare)
var _now := PackedInt64Array()      # per slot: place and look, packed as Player.known keeps them
var _chunk := PackedInt32Array()    # per slot: the chunk it is in (x, and the row inside its deck << 16)
var _shines := PackedInt32Array()   # per slot: 1 = it holds a lit flashlight
var _dark_now := false              # no power: sight is worked out anew every tick (flashlights move)
var _dark_ship := false             # a dark ship alongside: the same for whoever is on it or looks at it
var _arcs_light: Array = []
var _arcs_dark: Array = []


func setup(p_server: GameServer) -> void:
	server = p_server
	var map := server.map
	_cw = map.chunks_wide()
	_ch = map.chunks_high()
	_deck_rows = map.deck_stride >> Net.CHUNK_SHIFT
	var chunks := _cw * map.chunk_rows()
	_doors_in.clear()
	_door_change.clear()
	_hull_change.clear()
	_air_change.clear()
	_floor_change.clear()
	for c in chunks:
		_doors_in.append(PackedInt32Array())
		_door_change.append(PackedByteArray())
		_hull_change.append(PackedByteArray())
		_air_change.append(PackedByteArray())
		_floor_change.append(PackedByteArray())
	_ship_sums.resize(chunks)
	_ship_sums_tick = -1
	_air_sent = server.air.level.duplicate()
	set_round(all_round)
	index_doors()


func set_round(on: bool) -> void:
	## (v69, the author's video: people turned to appeared only after a ping) With `on`,
	## everyone our character could see by turning (walls, doors and the dark still
	## hide them) is sent, and the client hides those behind it by its own facing at
	## once. Off: only the cone ahead, as before v69.
	all_round = on
	_arcs_light = [[-180.0, 180.0]] if on else _widen(Sight.eye_arcs(false))
	_arcs_dark = [[-180.0, 180.0]] if on else _widen(Sight.eye_arcs(true))


func _widen(arcs: Array) -> Array:
	var out: Array = []
	for arc: Array in arcs:
		out.append([float(arc[0]) - MARGIN_DEG, float(arc[1]) + MARGIN_DEG])
	return out


func chunk_of(x: int, y: int) -> int:
	return (y >> Net.CHUNK_SHIFT) * _cw + (x >> Net.CHUNK_SHIFT)


func index_doors() -> void:
	## Which doors are in which chunk (the other ship's doors move with it).
	## Called whenever the grid changes shape, so the lines of sight are forgotten too.
	lines.clear()
	for c in _doors_in.size():
		_doors_in[c] = PackedInt32Array()
	for d in server.map.doors.size():
		if server.map.door_here(d):
			var c := chunk_of(server.map.doors[d].x, server.map.doors[d].y)
			var in_chunk: PackedInt32Array = _doors_in[c]
			in_chunk.append(d)
			_doors_in[c] = in_chunk
	sight_changed()


func sight_changed() -> void:
	## Something that stops sight may have changed: who sees whom is worked out anew.
	_sight_epoch += 1


func forget(slot: int) -> void:
	## A character has left the world: clients are told so by Net.S_LEAVE and forget it themselves.
	for q: Player in server.players:
		if q != null:
			q.known.erase(slot)


func hull_record(cell: int, state: int) -> void:
	var x := cell % server.map.width
	var y := cell / server.map.width
	var buf: PackedByteArray = _hull_change[chunk_of(x, y)]
	var o := buf.size()
	buf.resize(o + Net.HULL_BYTES)
	buf.encode_s16(o, x)
	buf.encode_s16(o + 2, y)
	buf.encode_u8(o + 4, state)
	_ship_sums_tick = -1


func door_record(d: int) -> void:
	## The door changed (opened, shut, its troubles): clients that see its chunk are told.
	sight_changed()
	if not server.map.door_here(d):
		return
	var buf: PackedByteArray = _door_change[chunk_of(server.map.doors[d].x, server.map.doors[d].y)]
	put_door(buf, d)
	_ship_sums_tick = -1


func floor_record(cell: int) -> void:
	var buf: PackedByteArray = _floor_change[chunk_of(cell % server.map.width, cell / server.map.width)]
	put_floor(buf, cell)
	_ship_sums_tick = -1


func put_floor(buf: PackedByteArray, cell: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.FLOOR_BYTES)
	buf.encode_s16(o, cell % server.map.width)
	buf.encode_s16(o + 2, cell / server.map.width)
	var things: PackedByteArray = server.floor_things.get(cell, PackedByteArray())
	for k in Net.FLOOR_STACK:
		buf[o + 4 + k] = things[k] if k < things.size() else Net.ITEM_NONE


func look(p: Player) -> int:
	## Facing, condition, light and "moves slowly" as one byte (see Net.pack_look).
	return Net.pack_look(p.st.facing, p.cond, p.st.slow, not Items.light(p.in_hand()).is_empty())


func put_door(buf: PackedByteArray, d: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.DOOR_BYTES)
	buf.encode_u16(o, d)
	buf.encode_s32(o + 2, -1 if server.doors.ready[d] == Doors.CLOSED else server.doors.ready[d])
	buf.encode_u8(o + 6, server.doors.flags(d))


func collect_air() -> void:
	## Notes which cells' air differs from what clients were last told.
	if server.air.settled and _air_sent == server.air.level:
		return
	var level := server.air.level
	var w := server.map.width
	for i in level.size():
		if level[i] != _air_sent[i]:
			_air_sent[i] = level[i]
			var x := i % w
			var y := i / w
			var buf: PackedByteArray = _air_change[chunk_of(x, y)]
			buf.append((y & 15) * 16 + (x & 15))
			buf.append(level[i])
			_ship_sums_tick = -1


func _ensure_ship_sums() -> void:
	if _ship_sums_tick == server.tick:
		return
	_ship_sums_tick = server.tick
	_ship_sums.fill(0)
	for d in server.doors.ready.size():
		var at: Vector2i = server.map.doors[d]
		if not server.map.door_here(d):
			continue
		_ship_sums[chunk_of(at.x, at.y)] += Net.door_hash(d, -1 if server.door_sent[d] == Doors.CLOSED else server.door_sent[d], server.flags_sent[d])
	for cell: int in server.air.holes.keys():
		_ship_sums[chunk_of(cell % server.map.width, cell / server.map.width)] += Net.hull_hash(cell % server.map.width, cell / server.map.width)
	for cell: int in server.floor_things.keys():
		_ship_sums[chunk_of(cell % server.map.width, cell / server.map.width)] += Net.floor_hash(cell % server.map.width, cell / server.map.width, server.floor_things[cell])
	var w := server.map.width
	for i in _air_sent.size():
		if _air_sent[i] != 0:
			_ship_sums[chunk_of(i % w, i / w)] += Net.air_hash(i % w, i / w, _air_sent[i])


func _append_ship_full(out: PackedByteArray, c: int, cx: int, cy: int) -> void:
	## Everything about the ship in one chunk, for a client that has just come within sight of it.
	var in_chunk: PackedInt32Array = _doors_in[c]
	if not in_chunk.is_empty():
		var buf := PackedByteArray()
		for d in in_chunk:
			put_door(buf, d)
		_append_records(out, Net.SEC_DOOR, buf, Net.DOOR_BYTES)
	var holes := PackedByteArray()
	var told := {}
	for cell: int in server.air.holes.keys() + server.systems.panes_down.keys():    # (v91) shutters down too
		if chunk_of(cell % server.map.width, cell / server.map.width) == c and not told.has(cell):
			told[cell] = true
			var o := holes.size()
			holes.resize(o + Net.HULL_BYTES)
			holes.encode_s16(o, cell % server.map.width)
			holes.encode_s16(o + 2, cell / server.map.width)
			holes.encode_u8(o + 4, server.systems.pane_state(cell))
	if not holes.is_empty():
		_append_records(out, Net.SEC_HULL, holes, Net.HULL_BYTES)
	var things := PackedByteArray()
	for cell: int in server.floor_things.keys():
		if chunk_of(cell % server.map.width, cell / server.map.width) == c:
			put_floor(things, cell)
	if not things.is_empty():
		_append_records(out, Net.SEC_FLOOR, things, Net.FLOOR_BYTES)
	var o2 := out.size()
	out.resize(o2 + 3 + 256)
	out.encode_u8(o2, Net.SEC_AIR_FULL)
	out.encode_u8(o2 + 1, cx)
	out.encode_u8(o2 + 2, cy)
	for ly in 16:
		var y := cy * 16 + ly
		if y >= server.map.height:
			break
		for lx in 16:
			var x := cx * 16 + lx
			if x >= server.map.width:
				break
			out[o2 + 3 + ly * 16 + lx] = _air_sent[y * server.map.width + x]


func _append_records(out: PackedByteArray, section: int, records: PackedByteArray, record_bytes: int) -> void:
	var o := out.size()
	out.resize(o + 3)
	out.encode_u8(o, section)
	out.encode_u16(o + 1, records.size() / record_bytes)
	out.append_array(records)


# ------------------------------------------------------------- characters

func _dark_cell(cell: int) -> bool:
	## A cell on a derelict or a wreck, which have no light of their own (a pirate ship is lit).
	return server.map.is_other(cell) and server.derelict.dark()


func _unlit(cell: int) -> bool:
	## (v61) No light of its own there now: a derelict or a wreck, or our ship with no
	## power (except the bridge while its backup SMES holds it).
	if server.map.is_other(cell):
		return _dark_cell(cell) or not server.powered()
	return not server.power.light_at(cell)      # (v68) the lights' breaker too


func _lit_cells() -> Dictionary:
	## Every cell a lit flashlight shines on, this tick (the same as GameClient.lit_cells).
	if _lit_tick == server.tick:
		return _lit
	_lit_tick = server.tick
	_lit = {}
	var pool := Items.light(Net.ITEM_FLASHLIGHT_ON)
	for q: Player in server.players:
		if q == null or Items.light(q.in_hand()).is_empty():
			continue
		var cells := Sight.glow(server.map, server.doors, Vector2(q.st.x, q.st.y), q.st.facing, float(pool[0]), float(pool[1]))
		for cell: int in cells.keys():
			_lit[cell] = true
	return _lit


func sees(p: Player, q: Player) -> bool:
	## Does p's player get to know about q: seen, felt right next to it, or
	## given away by its flashlight. The rules are GameClient's (WorldView.can_see),
	## a little more generous at the edges.
	if q == p:
		return true
	if p.cond != Net.COND_OK:
		return false                         # out cold, or dead: nothing is seen
	var map := server.map
	var my_deck := map.deck_of(p.st.y)
	var its_deck := map.deck_of(q.st.y)
	if its_deck != my_deck:
		# one deck up or down, only through a see-through floor (GameClient.seen_from)
		if its_deck == my_deck + 1:
			if map.see_through[(q.st.y - map.deck_stride) * map.width + q.st.x] != 1:
				return false
		elif its_deck == my_deck - 1:
			if map.see_through[q.st.y * map.width + q.st.x] != 1:
				return false
		else:
			return false
	var on_ours := Vector2i(q.st.x, q.st.y - (its_deck - my_deck) * map.deck_stride)
	var from := Vector2(p.st.x, p.st.y)
	var dist := from.distance_to(Vector2(on_ours))
	if its_deck == my_deck:
		if dist <= CONTACT:
			return true
		if not Items.light(q.in_hand()).is_empty():
			return true                      # its beam is seen from anywhere around
	var eyes := p.worn[Net.WEAR_EYES]
	if eyes == Net.ITEM_THERMAL and its_deck == my_deck and dist <= THERMAL_REACH and warm(q):
		return true                          # (v93, the author's O1) its heat shows through walls
	if dist > Sight.SIGHT_REACH + 1.5:
		return false
	var cell := q.st.y * map.width + q.st.x
	var dark := _unlit(p.st.y * map.width + p.st.x)
	if eyes == Net.ITEM_NVG or not dark and not _unlit(cell):   # (v93) night vision: the dark is as if lit
		return Sight.sees(map, server.doors, from, p.st.facing, on_ours, _arcs_light, Sight.SIGHT_REACH + 1, lines)
	if dist <= Sight.DARK_REACH + 1.5 and Sight.sees(map, server.doors, from, p.st.facing, on_ours, _arcs_dark, Sight.DARK_REACH + 1, lines):
		return true
	return _lit_cells().has(cell) and Sight.sees(map, server.doors, from, p.st.facing, on_ours, _arcs_dark, Sight.SIGHT_REACH + 1, lines)


static func _eyes_key(p: Player) -> int:
	return 1 if p.worn[Net.WEAR_EYES] == Net.ITEM_NVG else (2 if p.worn[Net.WEAR_EYES] == Net.ITEM_THERMAL else 0)


static func warm(q: Player) -> bool:
	## (v93) Does it show in thermal goggles: alive (awake or not), not a machine.
	return q.cond != Net.COND_DEAD and not q.robot and not q.corpse


func _prepare() -> void:
	## What every character looks like this tick, worked out once for all the
	## clients rather than once for every pair of them.
	if _prep_tick == server.tick:
		return
	_prep_tick = server.tick
	var n := server.players.size()
	_now.resize(n)
	_chunk.resize(n)
	_shines.resize(n)
	_dark_now = not server.powered() or not server.power.lights_on()
	_dark_ship = server.derelict.dark()
	for q: Player in server.players:
		if q == null:
			continue
		var lit := not Items.light(q.in_hand()).is_empty()
		_shines[q.slot] = 1 if lit else 0
		_now[q.slot] = _pack(q.st.x, q.st.y, Net.pack_look(q.st.facing, q.cond, q.st.slow, lit)) | (Net.pack_off(q.st.ox, q.st.oy, q.st.prone, q.st.hold) << 40)
		_chunk[q.slot] = (q.st.x >> Net.CHUNK_SHIFT) | ((server.map.local_y(q.st.y) >> Net.CHUNK_SHIFT) << 16)


func _seen_now(p: Player, q: Player, a_mine: int) -> bool:
	## sees(), remembered while neither has moved, turned or changed, and nothing
	## that stops sight has changed either (in the dark it is worked out every tick).
	## `a_mine`: p's own part of the key (see _characters).
	if see_all:
		return true
	var at := q.slot
	var a := a_mine | (q.st.x << 32) | (q.st.y << 44)
	var b := _sight_epoch * 64 + _shines[at] * 8 + q.cond
	if p.vis_a.size() <= at:
		p.vis_a.resize(at + 1)
		p.vis_b.resize(at + 1)
		p.vis_r.resize(at + 1)
		p.vis_until.resize(at + 1)
	var seen: bool
	var redo := _dark_now or (_dark_ship and (_dark_cell(p.st.y * server.map.width + p.st.x) or _dark_cell(q.st.y * server.map.width + q.st.x)))
	if not redo and p.vis_a[at] == a and p.vis_b[at] == b:
		seen = p.vis_r[at] == 1
	else:
		seen = sees(p, q)
		p.vis_a[at] = a
		p.vis_b[at] = b
		p.vis_r[at] = 1 if seen else 0
	if seen:
		p.vis_until[at] = server.tick + SEEN_GRACE
		return true
	return server.tick <= p.vis_until[at]


func _in_view(p: Player, x: int, y: int) -> bool:
	## Is that cell in one of the chunks this client is shown?
	return absi((x >> Net.CHUNK_SHIFT) - p.view_cx) <= 1 and absi((server.map.local_y(y) >> Net.CHUNK_SHIFT) - p.view_cy) <= 1


static func _pack(x: int, y: int, look_byte: int) -> int:
	return x | (y << 16) | (look_byte << 32)


func _characters(p: Player, view_moved: bool) -> PackedByteArray:
	## The records of the characters this client should hear about now: the ones
	## it sees whose place or look changed, and the ones it has stopped seeing.
	_prepare()
	var recs := PackedByteArray()
	if view_moved:
		# the client forgets what is outside its new view by itself
		for slot: int in p.known.keys():
			var k: int = p.known[slot]
			if not _in_view(p, k & 0xFFFF, (k >> 16) & 0xFFFF):
				p.known.erase(slot)
	var a_mine := p.st.x | (p.st.y << 12) | (p.st.facing << 24) | (p.cond << 28) | (_eyes_key(p) << 56)   # (v93) goggles
	var known := p.known
	for q: Player in server.players:
		if q == null:
			continue
		var slot := q.slot
		var had: int = known.get(slot, -1)
		var now := _now[slot]
		var ch := _chunk[slot]
		if absi((ch & 0xFFFF) - p.view_cx) > 1 or absi((ch >> 16) - p.view_cy) > 1:
			if had >= 0:
				# it has gone out of the chunks shown: where it went (the client lets it go)
				_put_record(recs, slot, q.st.x, q.st.y, (now >> 32) & 0xFF, now >> 40)
				known.erase(slot)
			continue
		if (not q.taken and not q.in_shuttle or q == p) and _seen_now(p, q, a_mine):   # (v70) one dragged off is gone, (v86) one in the shuttle
			if now != had:
				_put_record(recs, slot, q.st.x, q.st.y, (now >> 32) & 0xFF, now >> 40)
				known[slot] = now
		elif had >= 0:
			# out of sight: the client is told where it last saw it, no more
			_put_record(recs, slot, had & 0xFFFF, (had >> 16) & 0xFFFF, Net.FACING_HIDDEN, had >> 40)
			known.erase(slot)
	return recs


func _known_sum(p: Player) -> int:
	var sum := 0
	for slot: int in p.known.keys():
		var k: int = p.known[slot]
		sum += Net.ent_hash(slot, k & 0xFFFF, (k >> 16) & 0xFFFF, (k >> 32) & 0xFF)
	return sum


func _put_record(buf: PackedByteArray, slot: int, x: int, y: int, facing: int, off: int) -> void:
	var o := buf.size()
	buf.resize(o + Net.ENT_BYTES)
	buf.encode_u16(o, slot)
	buf.encode_s16(o + 2, x)
	buf.encode_s16(o + 4, y)
	buf.encode_u8(o + 6, facing)
	buf.encode_u8(o + 7, off & 0xFF)     # (v78) quarters off the tile's centre, lying down (Net.pack_off)


func _append_ents(out: PackedByteArray, records: PackedByteArray) -> void:
	var o := out.size()
	out.resize(o + 3)
	out.encode_u8(o, Net.SEC_ENT)
	out.encode_u16(o + 1, records.size() / Net.ENT_BYTES)
	out.append_array(records)


# -------------------------------------------------------------- sending

func send() -> void:
	for p: Player in server.players:
		if p == null or p.peer == null:
			continue
		# The view is centred on a chunk of the character's deck, and takes in the
		# same chunks of every other deck: what is seen through a glass floor is
		# straight below, and a change of deck brings nothing new into view.
		var st := p.st
		var cx := st.x >> Net.CHUNK_SHIFT
		var cy := server.map.local_y(st.y) >> Net.CHUNK_SHIFT
		var old_cx := p.view_cx
		var old_cy := p.view_cy
		var view_moved := cx != old_cx or cy != old_cy
		var check := (server.tick + p.slot) % CHECK_TICKS == 0
		var out := PackedByteArray()
		out.resize(5)
		out.encode_u8(0, Net.S_WORLD)
		out.encode_u32(1, server.tick)
		if view_moved:
			out.append(Net.SEC_VIEW)
			out.append(cx)
			out.append(cy)
			p.view_cx = cx
			p.view_cy = cy
		var t0 := Time.get_ticks_usec()
		var recs := _characters(p, view_moved)
		if server.lap_at >= 0:
			server.part_usec["send: sight"] = int(server.part_usec.get("send: sight", 0)) + Time.get_ticks_usec() - t0
		if not recs.is_empty():
			_append_ents(out, recs)
		if check:
			_ensure_ship_sums()
		var ship_sum := 0
		for deck in server.map.deck_count:
			for yy in range(maxi(cy - 1, 0), mini(cy + 2, _ch)):
				var row := deck * _deck_rows + yy          # the chunk row in the whole grid
				for xx in range(maxi(cx - 1, 0), mini(cx + 2, _cw)):
					var c := row * _cw + xx
					if view_moved and (absi(xx - old_cx) > 1 or absi(yy - old_cy) > 1):
						# this chunk just came into view: send everything in it
						_append_ship_full(out, c, xx, row)
					else:
						var door_changes: PackedByteArray = _door_change[c]
						if not door_changes.is_empty():
							_append_records(out, Net.SEC_DOOR, door_changes, Net.DOOR_BYTES)
						var hull_changes: PackedByteArray = _hull_change[c]
						if not hull_changes.is_empty():
							_append_records(out, Net.SEC_HULL, hull_changes, Net.HULL_BYTES)
						var floor_changes: PackedByteArray = _floor_change[c]
						if not floor_changes.is_empty():
							_append_records(out, Net.SEC_FLOOR, floor_changes, Net.FLOOR_BYTES)
						var air_changes: PackedByteArray = _air_change[c]
						if not air_changes.is_empty():
							var oa := out.size()
							out.resize(oa + 5)
							out.encode_u8(oa, Net.SEC_AIR)
							out.encode_u8(oa + 1, xx)
							out.encode_u8(oa + 2, row)
							out.encode_u16(oa + 3, air_changes.size() / 2)
							out.append_array(air_changes)
					if check:
						ship_sum += _ship_sums[c]
		var health_now := roundi(p.health)
		var tank_now := roundi(p.tank * Net.TANK_FULL)
		var work_now := p.work * 100 / maxi(p.work_total, 1)
		var marks := (1 if p.supply else 0) | (2 if p.bleeding > 0 else 0) | (4 if p.arm else 0) | (8 if p.leg else 0) | (16 if p.concussed > 0 else 0) | (32 if p.dragging >= 0 else 0) \
			| (64 if p.weak else 0)
		# (v71) the dish at work, and its seconds left in fives
		var meal_left := clampi(ceili((p.meal_until - server.tick) / float(Net.TICK_HZ * 5)), 0, 255) if p.meal != 0 else 0
		var vitals := ((health_now + 200) << 40) | (tank_now << 32) | (work_now << 24) | (marks << 16) | ((p.meal & 255) << 8) | meal_left
		var carried := p.slots.duplicate()
		carried.append_array(p.worn)
		if vitals != p.vitals_sent or carried != p.slots_sent:
			p.vitals_sent = vitals
			p.slots_sent = carried
			var ov := out.size()
			out.resize(ov + 1 + Net.VITALS_BYTES)
			out.encode_u8(ov, Net.SEC_VITALS)
			out.encode_s16(ov + 1, health_now)
			out.encode_u8(ov + 3, tank_now)
			out.encode_u8(ov + 4, marks)    # (v70) with the injuries
			out.encode_u8(ov + 5, work_now)
			for k in Net.SLOTS:
				out.encode_u8(ov + 6 + k, p.slots[k])
			for k in Net.WORN:
				out.encode_u8(ov + 6 + Net.SLOTS + k, p.worn[k])
			out.encode_u8(ov + 6 + Net.SLOTS + Net.WORN, p.meal & 255)
			out.encode_u8(ov + 7 + Net.SLOTS + Net.WORN, meal_left)
		if p.self_dirty or server.tick - p.last_self_tick >= SELF_REFRESH_TICKS:
			var o := out.size()
			out.resize(o + 1 + Net.SELF_BYTES)
			out.encode_u8(o, Net.SEC_SELF)
			out.encode_s16(o + 1, st.x)
			out.encode_s16(o + 3, st.y)
			out.encode_u8(o + 5, st.cd)
			out.encode_u8(o + 6, look(p))
			out.encode_u8(o + 7, st.dir | (st.span << 4))   # (v74) a step lasts 4 to 12 ticks
			out.encode_u16(o + 8, p.last_seq)
			out.encode_s32(o + 10, st.move_tick)
			out.encode_s16(o + 14, st.fx)
			out.encode_s16(o + 16, st.fy)
			# (v77) it looks where its mouse is; (v78) quarter steps, lying down
			out.encode_u8(o + 18, (1 if st.free_look else 0) | (2 if st.fine else 0) | (4 if st.prone else 0) | (8 if st.hold else 0))
			out.encode_u8(o + 19, Net.pack_off(st.ox, st.oy, st.prone))   # (v78) quarters off the tile's centre
			out.encode_u8(o + 20, st.rise)   # (v82) ticks left getting up
			p.self_dirty = false
			p.last_self_tick = server.tick
		if check:
			var o2 := out.size()
			out.resize(o2 + 9)
			out.encode_u8(o2, Net.SEC_CHECK)
			out.encode_u32(o2 + 1, _known_sum(p) & 0xFFFFFFFF)
			out.encode_u32(o2 + 5, ship_sum & 0xFFFFFFFF)
		if out.size() > 5 or server.tick - p.last_packet_tick >= HEARTBEAT_TICKS:
			p.peer.send(0, out, ENetPacketPeer.FLAG_RELIABLE)
			p.last_packet_tick = server.tick
	for c in _door_change.size():
		if not (_door_change[c] as PackedByteArray).is_empty():
			_door_change[c] = PackedByteArray()
		if not (_hull_change[c] as PackedByteArray).is_empty():
			_hull_change[c] = PackedByteArray()
		if not (_floor_change[c] as PackedByteArray).is_empty():
			_floor_change[c] = PackedByteArray()
		if not (_air_change[c] as PackedByteArray).is_empty():
			_air_change[c] = PackedByteArray()
