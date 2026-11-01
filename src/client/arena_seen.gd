extends RefCounted
## (v92) What the client knows of the fight in real time (the server's Arena): the ships as bodies
## in space (Net.S_ARENA, every other tick, drawn a little in the past between two of them) and the
## shots flying (Net.S_ARENA_SHOT: each is told once, as it leaves its gun, and flies on by itself
## here until the server says where it ended). SpaceView draws it.
## (v95) Our own ships are bodies there always, flying round the system (Arena.SCALE cells to a unit of
## the system's map); `fight` says whether a fight goes on.

const Net := preload("res://src/shared/net.gd")
const ArenaShape := preload("res://src/shared/arena_shape.gd")

const KEEP := 4                      # snapshots kept per ship
const BURST_MS := 600                # how long a shot's end is drawn
const AHEAD_MAX := 6.0               # ticks a ship is carried on by its speed past the last snapshot

var map: RefCounted                  # the client's ShipMap (set by GameClient on joining)
var bodies := {}                     # body id -> {"layout", "snaps": [{tick, pos, vel, rot, spin, shield, flags, aims, gunf}]}
var shots := {}                      # shot id -> {"kind", "side", "tick", "pos", "vel", "ends"}
var bursts: Array = []               # {"at", "how", "kind", "born"} (msec)
var beams: Array = []                # {"from", "to", "kind", "until"} (msec)
var armour := {}                     # (v93) body id -> {the shape's cell: Vector2i(points left, most)} where worn
var changes := 0                     # counts packets (for a redraw)
var _shapes := {}                    # "f<ship>" / "o<layout>" -> ArenaShape
var _guns := {}                      # the same keys -> PackedInt32Array, the drawing's cells of its guns


var fight := false                   # (v95) a fight goes on (S_ARENA's ARENA_FIGHT): else our ships fly round the system
var course := false                  # (v95) the autopilot flies our fleet to its course


func on() -> bool:
	## A fight in real time goes on.
	return fight and not bodies.is_empty()


func flying() -> bool:
	## (v95) Our ships are in space (always while the server's Arena runs).
	return not bodies.is_empty()


func reset() -> void:
	fight = false
	course = false
	bodies.clear()
	shots.clear()
	bursts.clear()
	beams.clear()
	armour.clear()
	_shapes.clear()
	_guns.clear()


func read(pkt: PackedByteArray) -> void:
	## S_ARENA (Arena.packet).
	changes += 1
	var tick := pkt.decode_u32(1)
	fight = pkt[5] & Net.ARENA_FIGHT != 0
	course = pkt[5] & Net.ARENA_COURSE != 0
	var n: int = pkt[6]
	var at := 7
	var seen := {}
	for i in n:
		if at + 31 > pkt.size():
			break
		var id: int = pkt[at]
		var flags: int = pkt[at + 1]
		var layout := pkt.decode_s16(at + 2)
		var pos := Vector2(pkt.decode_s16(at + 4), pkt.decode_s16(at + 6)) / 8.0
		var vel := Vector2(pkt.decode_s16(at + 8), pkt.decode_s16(at + 10)) / 8.0
		var rot := pkt.decode_u16(at + 12) / 65535.0 * TAU
		var spin := pkt.decode_s16(at + 14) / 1000.0
		var shield: int = pkt[at + 16]
		# (v94) hull points, heat, the shield's state and its arc's way
		var hp := Vector2(pkt.decode_u16(at + 18), pkt.decode_u16(at + 20))
		var heat := Vector2(pkt.decode_u16(at + 22), pkt.decode_u16(at + 24))
		var hard: float = pkt[at + 26] / 200.0
		var sstate: int = pkt[at + 27]
		var sdir := pkt.decode_s16(at + 28) / 1000.0
		var guns: int = pkt[at + 30]
		at += 31
		var aims := PackedFloat32Array()
		var gunf := PackedByteArray()
		var charge := PackedFloat32Array()
		for k in guns:
			if at + 4 > pkt.size():
				break
			aims.append(pkt.decode_s16(at) / 1000.0)
			gunf.append(pkt[at + 2])
			charge.append(pkt[at + 3] / 200.0)
			at += 4
		seen[id] = true
		var b: Dictionary = bodies.get(id, {})
		if b.is_empty() or int(b["layout"]) != layout:
			b = {"layout": layout, "snaps": []}
			bodies[id] = b
			if layout >= 0:
				armour.erase(id)             # a new pirate: its armour whole
		var snaps: Array = b["snaps"]
		snaps.append({"tick": tick, "pos": pos, "vel": vel, "rot": rot, "spin": spin, "shield": shield, "flags": flags,
			"aims": aims, "gunf": gunf, "hp": hp, "heat": heat, "hard": hard, "sstate": sstate, "sdir": sdir, "charge": charge})
		if snaps.size() > KEEP:
			snaps.remove_at(0)
	for id: int in bodies.keys():
		if not seen.has(id):
			bodies.erase(id)
			armour.erase(id)
	if bodies.is_empty():
		shots.clear()


func shot(pkt: PackedByteArray, now_ms: int) -> void:
	## S_ARENA_SHOT (Arena._launch, _ended, draw_beam).
	changes += 1
	match int(pkt[1]):
		Net.ARENA_SHOT_FLY:
			if pkt.size() < 20:
				return
			var id := pkt.decode_u16(2)
			var t := pkt.decode_u32(6)
			shots[id] = {"kind": pkt[4], "side": pkt[5], "tick": t,
				"pos": Vector2(pkt.decode_s16(10), pkt.decode_s16(12)) / 8.0,
				"vel": Vector2(pkt.decode_s16(14), pkt.decode_s16(16)) / 8.0 * 4.0,
				"ends": t + pkt.decode_u16(18)}
		Net.ARENA_SHOT_END:
			if pkt.size() < 9:
				return
			var id := pkt.decode_u16(2)
			var at := Vector2(pkt.decode_s16(5), pkt.decode_s16(7)) / 8.0
			var kind: int = int((shots.get(id, {}) as Dictionary).get("kind", 0))
			shots.erase(id)
			bursts.append({"at": at, "how": pkt[4], "kind": kind, "born": now_ms})
		Net.ARENA_ARMOUR:
			if pkt.size() < 4:
				return
			var id: int = pkt[2]
			var n: int = pkt[3]
			if n == 255:
				armour.erase(id)             # made whole
				return
			var worn: Dictionary = armour.get(id, {})
			for k in n:
				var o := 4 + k * 4
				if o + 4 > pkt.size():
					break
				var i := pkt.decode_u16(o)
				if pkt[o + 2] >= pkt[o + 3]:
					worn.erase(i)
				else:
					worn[i] = Vector2i(pkt[o + 2], pkt[o + 3])
			armour[id] = worn
		Net.ARENA_SHOT_BEAM:
			if pkt.size() < 15:
				return
			var from := Vector2(pkt.decode_s16(6), pkt.decode_s16(8)) / 8.0
			var to := Vector2(pkt.decode_s16(10), pkt.decode_s16(12)) / 8.0
			beams.append({"from": from, "to": to, "kind": pkt[4], "until": now_ms + int(pkt[14]) * 1000 / Net.TICK_HZ})


func forget(now_ms: int, t: float) -> void:
	## Drops what has ended by now (bursts, beams, shots past their reach the server forgot to end).
	var keep: Array = []
	for b: Dictionary in bursts:
		if now_ms - int(b["born"]) < BURST_MS:
			keep.append(b)
	bursts = keep
	keep = []
	for b: Dictionary in beams:
		if now_ms < int(b["until"]):
			keep.append(b)
	beams = keep
	for id: int in shots.keys():
		if t > float((shots[id] as Dictionary)["ends"]) + 10.0:
			shots.erase(id)


func shot_at(s: Dictionary, t: float) -> Vector2:
	## Where a shot is at tick t (it flies straight on).
	return (s["pos"] as Vector2) + (s["vel"] as Vector2) * maxf(t - float(s["tick"]), 0.0) / Net.TICK_HZ


func state(id: int, t: float) -> Dictionary:
	## A ship as it was at tick t: {"pos", "rot", "vel", "shield", "flags", "aims", "gunf"} (empty: not in the fight).
	var b: Dictionary = bodies.get(id, {})
	if b.is_empty():
		return {}
	var snaps: Array = b["snaps"]
	if snaps.is_empty():
		return {}
	var last: Dictionary = snaps[-1]
	if t >= float(last["tick"]):
		var ahead := minf(t - float(last["tick"]), AHEAD_MAX) / Net.TICK_HZ
		var s := last.duplicate()
		s["pos"] = (last["pos"] as Vector2) + (last["vel"] as Vector2) * ahead
		s["rot"] = float(last["rot"]) + float(last["spin"]) * ahead
		return s
	for k in range(snaps.size() - 1, 0, -1):
		var a: Dictionary = snaps[k - 1]
		var c: Dictionary = snaps[k]
		if t >= float(a["tick"]):
			var f := (t - float(a["tick"])) / maxf(float(c["tick"]) - float(a["tick"]), 1.0)
			var s := c.duplicate()
			s["pos"] = (a["pos"] as Vector2).lerp(c["pos"], f)
			s["rot"] = lerp_angle(float(a["rot"]), float(c["rot"]), f)
			var aims := PackedFloat32Array()
			var aa: PackedFloat32Array = a["aims"]
			var ca: PackedFloat32Array = c["aims"]
			for g in ca.size():
				aims.append(lerp_angle(aa[g], ca[g], f) if g < aa.size() else ca[g])
			s["aims"] = aims
			return s
	return snaps[0]


func layout_of(id: int) -> int:
	return int((bodies.get(id, {}) as Dictionary).get("layout", -1))


func forget_shapes() -> void:
	## (v101) A mount of ours moved: our ships' shapes and guns are made again when next asked.
	for key: String in _shapes.keys():
		if key.begins_with("f"):
			_shapes.erase(key)
			_guns.erase(key)


func shape_of(id: int) -> RefCounted:
	## The ArenaShape of that ship, built once from the same drawing as on the server.
	var layout := layout_of(id)
	var key := ("f%d" % id) if layout < 0 else ("o%d" % layout)
	if not _shapes.has(key):
		if layout < 0:
			_shapes[key] = ArenaShape.of_fleet(map, id)
			var was: int = map.fleet_on
			map.use_ship(id)
			_guns[key] = (map.guns as PackedInt32Array).duplicate()
			map.use_ship(was)
		elif layout < map.others.size():
			_shapes[key] = ArenaShape.of_layout(map.others[layout], true)
			_guns[key] = (map.others[layout].guns as PackedInt32Array).duplicate()
		else:
			return null
	return _shapes[key]


func gun_spot(id: int, k: int) -> Vector2:
	## Where gun k of that ship stands, in its body's frame (as Arena._gun).
	var s := shape_of(id)
	if s == null:
		return Vector2.ZERO
	var key := ("f%d" % id) if layout_of(id) < 0 else ("o%d" % layout_of(id))
	var guns: PackedInt32Array = _guns.get(key, PackedInt32Array())
	return s.local_of(guns[k]) if k < guns.size() and guns[k] >= 0 else Vector2.ZERO


func gun_kind(id: int, k: int) -> int:
	## (v94) That gun's mount kind (ArenaShape.MOUNT_*), as Arena._gun.
	var s := shape_of(id)
	if s == null:
		return ArenaShape.MOUNT_SIDE
	var key := ("f%d" % id) if layout_of(id) < 0 else ("o%d" % layout_of(id))
	var guns: PackedInt32Array = _guns.get(key, PackedInt32Array())
	return s.mount_kind(guns[k]) if k < guns.size() else ArenaShape.MOUNT_SIDE


func gun_out(id: int, k: int) -> float:
	## The angle that gun points when straight (as Arena._gun).
	var s := shape_of(id)
	if s == null:
		return 0.0
	var key := ("f%d" % id) if layout_of(id) < 0 else ("o%d" % layout_of(id))
	var guns: PackedInt32Array = _guns.get(key, PackedInt32Array())
	return s.mount_out(guns[k]) if k < guns.size() else 0.0
