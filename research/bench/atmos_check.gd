extends SceneTree
func _initialize() -> void:
	var a = load("res://atmos.gd").new(60, 40, 1234)
	var i: int = 20 * 60 + 20
	var before: float = a.o2[i]
	var tot0: float = a.total_gas()
	a.breach = 5 * 60 + 5
	for s in 200:
		a.step(0.2)
	print("o2 at probe tile: before=%.4f after=%.4f" % [before, a.o2[i]])
	print("with a hull breach, total gas went %.1f -> %.1f (%.1f%% lost in 200 steps)" % [tot0, a.total_gas(), (tot0 - a.total_gas()) / tot0 * 100.0])
	print("pressure byte near breach=%d, far room=%d" % [a.pressure_q[5 * 60 + 6], a.pressure_q[35 * 60 + 55]])
	quit()
