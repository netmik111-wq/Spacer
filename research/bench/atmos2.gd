class_name Atmos2
extends RefCounted
## Same model as atmos.gd, restructured for threads:
##  - the inner loop reads the front buffers and writes only the back buffers,
##    so row bands can run on several threads at once (step_bands), or the
##    whole step can run on a worker while the main thread keeps serving the
##    network (compute_back + publish);
##  - optionally records which tiles changed their quantised pressure, per
##    16x16 chunk, so the network layer can send only the changes.

var w: int
var h: int
var walls: PackedByteArray
var o2: PackedFloat32Array
var n2: PackedFloat32Array
var co2: PackedFloat32Array
var o2_b: PackedFloat32Array
var n2_b: PackedFloat32Array
var co2_b: PackedFloat32Array
var pressure_q: PackedByteArray
var pressure_b: PackedByteArray
var breach: int = -1
var chunk_w: int = 0
var delta_bufs: Array = []

var _k := 0.2
var _bands := 1

func _init(width: int, height: int, seed_value: int) -> void:
	w = width
	h = height
	chunk_w = (w + 15) / 16
	var n := w * h
	walls = PackedByteArray(); walls.resize(n)
	o2 = PackedFloat32Array(); o2.resize(n)
	n2 = PackedFloat32Array(); n2.resize(n)
	co2 = PackedFloat32Array(); co2.resize(n)
	o2_b = PackedFloat32Array(); o2_b.resize(n)
	n2_b = PackedFloat32Array(); n2_b.resize(n)
	co2_b = PackedFloat32Array(); co2_b.resize(n)
	pressure_q = PackedByteArray(); pressure_q.resize(n)
	pressure_b = PackedByteArray(); pressure_b.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in h:
		for x in w:
			var i := y * w + x
			var border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			var grid_wall := (x % 16 == 0 or y % 16 == 0) and not (x % 16 == 8 or y % 16 == 8)
			if border or grid_wall:
				walls[i] = 1
			else:
				o2[i] = 21.0 + rng.randf() * 4.0
				n2[i] = 79.0 + rng.randf() * 4.0
				co2[i] = rng.randf()
				var p := int((o2[i] + n2[i] + co2[i]) * 2.0)
				pressure_q[i] = p if p < 255 else 255

func total_gas() -> float:
	var t := 0.0
	for i in o2.size():
		t += o2[i] + n2[i] + co2[i]
	return t

## Core loop over rows [y0, y1). Reads front buffers, writes back buffers only.
func _rows(y0: int, y1: int, k: float, deltas: bool) -> void:
	var ww := w
	var wl := walls
	var a := o2
	var b := n2
	var c := co2
	var ab := o2_b
	var bb := n2_b
	var cb := co2_b
	var pf := pressure_q
	var pb := pressure_b
	var br := breach
	var cw := chunk_w
	var dbufs := delta_bufs
	for y in range(y0, y1):
		var i := y * ww + 1
		for x in range(1, ww - 1):
			if wl[i] == 0:
				var va := a[i]
				var vb := b[i]
				var vc := c[i]
				var da := 0.0
				var db := 0.0
				var dc := 0.0
				var j := i - 1
				if wl[j] == 0:
					da += a[j] - va; db += b[j] - vb; dc += c[j] - vc
				j = i + 1
				if wl[j] == 0:
					da += a[j] - va; db += b[j] - vb; dc += c[j] - vc
				j = i - ww
				if wl[j] == 0:
					da += a[j] - va; db += b[j] - vb; dc += c[j] - vc
				j = i + ww
				if wl[j] == 0:
					da += a[j] - va; db += b[j] - vb; dc += c[j] - vc
				va += k * da
				vb += k * db
				vc += k * dc
				if i == br:
					va = 0.0; vb = 0.0; vc = 0.0
				ab[i] = va
				bb[i] = vb
				cb[i] = vc
				var p := int((va + vb + vc) * 2.0)
				if p > 255:
					p = 255
				pb[i] = p
				if deltas and p != pf[i]:
					var buf: PackedByteArray = dbufs[(y >> 4) * cw + (x >> 4)]
					buf.append(((y & 15) << 4) | (x & 15))
					buf.append(p)
			i += 1

func _swap() -> void:
	var t := o2; o2 = o2_b; o2_b = t
	t = n2; n2 = n2_b; n2_b = t
	t = co2; co2 = co2_b; co2_b = t
	var q := pressure_q; pressure_q = pressure_b; pressure_b = q

## Single-threaded step on the calling thread.
func step(k: float) -> void:
	_rows(1, h - 1, k, false)
	_swap()

## Step split into row bands that run on the engine's worker threads.
func step_bands(k: float, bands: int) -> void:
	_k = k
	_bands = bands
	var gid := WorkerThreadPool.add_group_task(_band, bands, bands, true)
	WorkerThreadPool.wait_for_group_task_completion(gid)
	_swap()

func _band(idx: int) -> void:
	var y0 := 1 + (h - 2) * idx / _bands
	var y1 := 1 + (h - 2) * (idx + 1) / _bands
	_rows(y0, y1, _k, false)

## For running the whole step off the main thread: fills the back buffers and
## the per-chunk change lists, touches nothing the main thread reads.
func compute_back(k: float) -> void:
	var nchunks := chunk_w * ((h + 15) / 16)
	var fresh: Array = []
	fresh.resize(nchunks)
	for ci in nchunks:
		fresh[ci] = PackedByteArray()
	delta_bufs = fresh
	_rows(1, h - 1, k, true)

## Main thread, after compute_back finished: make the new state current and
## hand over the change lists.
func publish() -> Array:
	_swap()
	return delta_bufs
