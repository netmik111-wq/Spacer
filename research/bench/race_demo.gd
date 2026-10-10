extends SceneTree
## Two threads add 1 to the same number a million times each.
var counter := 0
var m := Mutex.new()

func _add(n: int) -> void:
	for i in n:
		counter += 1

func _add_locked(n: int) -> void:
	for i in n:
		m.lock()
		counter += 1
		m.unlock()

func _run2(fn: Callable, n: int) -> float:
	counter = 0
	var a := Thread.new()
	var b := Thread.new()
	var t0 := Time.get_ticks_usec()
	a.start(fn.bind(n))
	b.start(fn.bind(n))
	a.wait_to_finish()
	b.wait_to_finish()
	return (Time.get_ticks_usec() - t0) / 1000.0

func _initialize() -> void:
	var n := 1000000
	counter = 0
	var t0 := Time.get_ticks_usec()
	_add(2 * n)
	print("one thread:              result=%d (expected %d)  time=%.0f ms" % [counter, 2 * n, (Time.get_ticks_usec() - t0) / 1000.0])
	for attempt in 3:
		var ms := _run2(_add, n)
		print("two threads, no lock:    result=%d  lost=%d (%.1f%%)  time=%.0f ms" % [counter, 2 * n - counter, 100.0 * (2 * n - counter) / (2 * n), ms])
	var ms2 := _run2(_add_locked, n)
	print("two threads, with lock:  result=%d (expected %d)  time=%.0f ms" % [counter, 2 * n, ms2])
	quit()
