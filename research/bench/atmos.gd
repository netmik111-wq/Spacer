class_name Atmos
extends RefCounted
## Tile atmosphere: three gases per tile, explicit diffusion between open
## neighbours, double-buffered. This is the naive worst case: every tile is
## processed every step (no "active tiles" optimisation).

var w: int
var h: int
var walls: PackedByteArray
var o2: PackedFloat32Array
var n2: PackedFloat32Array
var co2: PackedFloat32Array
var o2_b: PackedFloat32Array
var n2_b: PackedFloat32Array
var co2_b: PackedFloat32Array
var pressure_q: PackedByteArray  # total gas quantised to one byte, for the network
var breach: int = -1             # tile index open to vacuum, -1 = none

func _init(width: int, height: int, seed_value: int) -> void:
	w = width
	h = height
	var n := w * h
	walls = PackedByteArray(); walls.resize(n)
	o2 = PackedFloat32Array(); o2.resize(n)
	n2 = PackedFloat32Array(); n2.resize(n)
	co2 = PackedFloat32Array(); co2.resize(n)
	o2_b = PackedFloat32Array(); o2_b.resize(n)
	n2_b = PackedFloat32Array(); n2_b.resize(n)
	co2_b = PackedFloat32Array(); co2_b.resize(n)
	pressure_q = PackedByteArray(); pressure_q.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in h:
		for x in w:
			var i := y * w + x
			var border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			# room walls every 16 tiles with door gaps, so gas has to route through corridors
			var grid_wall := (x % 16 == 0 or y % 16 == 0) and not (x % 16 == 8 or y % 16 == 8)
			if border or grid_wall:
				walls[i] = 1
			else:
				o2[i] = 21.0 + rng.randf() * 4.0
				n2[i] = 79.0 + rng.randf() * 4.0
				co2[i] = rng.randf()

func total_gas() -> float:
	var t := 0.0
	for i in o2.size():
		t += o2[i] + n2[i] + co2[i]
	return t

func step(k: float) -> void:
	var ww := w
	for y in range(1, h - 1):
		var row := y * ww
		for x in range(1, ww - 1):
			var i := row + x
			if walls[i] != 0:
				continue
			var a := o2[i]
			var b := n2[i]
			var c := co2[i]
			var da := 0.0
			var db := 0.0
			var dc := 0.0
			var j := i - 1
			if walls[j] == 0:
				da += o2[j] - a; db += n2[j] - b; dc += co2[j] - c
			j = i + 1
			if walls[j] == 0:
				da += o2[j] - a; db += n2[j] - b; dc += co2[j] - c
			j = i - ww
			if walls[j] == 0:
				da += o2[j] - a; db += n2[j] - b; dc += co2[j] - c
			j = i + ww
			if walls[j] == 0:
				da += o2[j] - a; db += n2[j] - b; dc += co2[j] - c
			a += k * da
			b += k * db
			c += k * dc
			o2_b[i] = a
			n2_b[i] = b
			co2_b[i] = c
			var p := int((a + b + c) * 2.0)
			pressure_q[i] = p if p < 255 else 255
	var t := o2; o2 = o2_b; o2_b = t
	t = n2; n2 = n2_b; n2_b = t
	t = co2; co2 = co2_b; co2_b = t
	if breach >= 0:
		o2[breach] = 0.0; n2[breach] = 0.0; co2[breach] = 0.0
