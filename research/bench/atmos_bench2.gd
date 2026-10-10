extends SceneTree
## Atmosphere step: original loop vs restructured loop vs row bands on worker threads.

func _median(fn: Callable, steps: int) -> float:
	for i in 5:
		fn.call()
	var s := PackedFloat64Array()
	for i in steps:
		var t0 := Time.get_ticks_usec()
		fn.call()
		s.append((Time.get_ticks_usec() - t0) / 1000.0)
	s.sort()
	return s[steps / 2]

func _initialize() -> void:
	var A1 := load("res://atmos.gd")
	var A2 := load("res://atmos2.gd")
	print("godot ", Engine.get_version_info().string, " | logical cores: ", OS.get_processor_count())
	for size in [[60, 40], [128, 96], [255, 255]]:
		var ref = A1.new(size[0], size[1], 1234)
		var one = A2.new(size[0], size[1], 1234)
		var two = A2.new(size[0], size[1], 1234)
		var four = A2.new(size[0], size[1], 1234)
		var steps := 40
		var m_ref := _median(func() -> void: ref.step(0.2), steps)
		var m_one := _median(func() -> void: one.step(0.2), steps)
		var m_two := _median(func() -> void: two.step_bands(0.2, 2), steps)
		var m_four := _median(func() -> void: four.step_bands(0.2, 4), steps)
		# all variants ran the same number of steps on the same map: results must match exactly
		var same := true
		for i in ref.o2.size():
			if ref.o2[i] != one.o2[i] or ref.o2[i] != two.o2[i] or ref.o2[i] != four.o2[i] or ref.co2[i] != two.co2[i]:
				same = false
				break
		print("grid %dx%d: original=%.3f ms | restructured 1 thread=%.3f ms | 2 bands=%.3f ms (x%.2f) | 4 bands=%.3f ms (x%.2f) | identical results=%s" % [
			size[0], size[1], m_ref, m_one, m_two, m_one / m_two, m_four, m_one / m_four, same])
	quit()
