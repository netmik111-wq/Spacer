extends SceneTree
## Times the atmosphere step at several grid sizes.

func _initialize() -> void:
	var AtmosScript := load("res://atmos.gd")
	print("godot ", Engine.get_version_info().string)
	for size in [[60, 40], [128, 96], [255, 255]]:
		var a = AtmosScript.new(size[0], size[1], 1234)
		var open_tiles := 0
		for i in a.walls.size():
			if a.walls[i] == 0:
				open_tiles += 1
		var before: float = a.total_gas()
		# warm up
		for i in 5:
			a.step(0.2)
		var steps := 60
		var samples := PackedFloat64Array()
		for i in steps:
			var t0 := Time.get_ticks_usec()
			a.step(0.2)
			samples.append((Time.get_ticks_usec() - t0) / 1000.0)
		samples.sort()
		var after: float = a.total_gas()
		var med := samples[steps / 2]
		print("grid %dx%d tiles=%d open=%d  step median=%.3f ms  p95=%.3f ms  max=%.3f ms  | gas drift=%.5f%%  | at 10 Hz = %.2f%% of one core" % [
			size[0], size[1], size[0] * size[1], open_tiles, med, samples[int(steps * 0.95)], samples[steps - 1],
			absf(after - before) / before * 100.0, med * 10.0 / 10.0])
	quit()
