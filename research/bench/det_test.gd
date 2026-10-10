extends SceneTree
## Same world, same 200 server ticks. Does the atmosphere end up in the same
## state every time?  mode=sync: stepped inside the tick.  mode=async: stepped
## on a worker thread, result taken whenever it happens to be ready.
## mode=asyncwait: worker thread, but the tick that needs the result waits for it.
var mode := "sync"
var gw := 128
var gh := 96
var atmos
var task := -1
var tick := 0
var steps := 0
var t0 := 0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv[0] == "mode": mode = kv[1]
		if kv[0] == "w": gw = int(kv[1])
		if kv[0] == "h": gh = int(kv[1])
	Engine.physics_ticks_per_second = 20
	Engine.max_fps = 60
	atmos = load("res://atmos2.gd").new(gw, gh, 1234)
	atmos.breach = 40 * gw + 20
	t0 = Time.get_ticks_msec()

func _physics_process(_d: float) -> bool:
	tick += 1
	if mode == "sync":
		if tick % 2 == 0:
			atmos.compute_back(0.2); atmos.publish(); steps += 1
	elif mode == "async":
		if task >= 0 and WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task); task = -1
			atmos.publish(); steps += 1
		if tick % 2 == 0 and task < 0:
			task = WorkerThreadPool.add_task(atmos.compute_back.bind(0.2))
	else:  # asyncwait: started on even ticks, must be in by the next tick
		if task >= 0:
			WorkerThreadPool.wait_for_task_completion(task); task = -1
			atmos.publish(); steps += 1
		if tick % 2 == 0:
			task = WorkerThreadPool.add_task(atmos.compute_back.bind(0.2))
	if tick == 200:
		var pq: PackedByteArray = atmos.pressure_q
		var sum := 0
		for i in pq.size():
			sum += pq[i] * (i % 251 + 1)
		print("DET map=%dx%d mode=%s ticks=200 wall=%.1f s atmosphere steps applied=%d state checksum=%d" % [gw, gh, mode, (Time.get_ticks_msec() - t0) / 1000.0, steps, sum])
		if task >= 0:
			WorkerThreadPool.wait_for_task_completion(task)
		return true
	return false
