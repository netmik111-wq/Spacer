extends VBoxContainer
## (v71, the author's L2) The galley stove's screen: the three dishes, what each
## is cooked from (rations and plasters in the supply locker) and what it does.
## The server cooks (see Galley); the progress is shown like any other work.
## Shown inside the console frame of GameScreen.

const Net := preload("res://src/shared/net.gd")
const GameClient := preload("res://src/client/game_client.gd")
const Items := preload("res://src/shared/items.gd")

const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const WARN := Color(0.95, 0.75, 0.3)

var client: GameClient
var _top: Label
var _rows: VBoxContainer
var _work: Label
var _shown := ""
var working := false


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(640, 0)
	_top = _label(14, INK)
	add_child(_top)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)
	_work = _label(14, WARN)
	add_child(_work)


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func closed() -> void:
	if client.work > 0:
		client.send_bench(Net.BENCH_STOP, 0)


func refresh() -> void:
	var store: Dictionary = client.store
	_top.text = "В шкафу снабжения: пайков %d, пластырей %d. Готовые блюда тоже кладутся туда; съесть: щёлкните по себе (или Z) или по соседу." % [
		int(store.get(Net.ITEM_FOOD, 0)), int(store.get(Net.ITEM_MEDPATCH, 0))]
	working = client.work > 0
	_work.text = "Готовлю: %d%%" % client.work if working else ""
	var key := "%s|%s" % [store, working]
	if key == _shown:
		return
	_shown = key
	for c in _rows.get_children():
		c.queue_free()
	for action: int in Items.DISHES.keys():
		var d: Array = Items.DISHES[action]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name := _label(15, INK)
		var need: Dictionary = d[1]
		var parts := PackedStringArray()
		var enough := true
		for item: int in need.keys():
			parts.append("%s ×%d" % [Items.name_of(item).to_lower(), int(need[item])])
			enough = enough and int(store.get(item, 0)) >= int(need[item])
		name.text = "%s (в шкафу: %d). Из: %s" % [Items.name_of(d[0]), int(store.get(d[0], 0)), ", ".join(parts)]
		text.add_child(name)
		var about := _label(13, DIM)
		about.text = Items.about(d[0])
		text.add_child(about)
		row.add_child(text)
		var b := Button.new()
		b.text = "Приготовить"
		b.disabled = not enough or working
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			client.send_bench(action, 0))
		row.add_child(b)
		_rows.add_child(row)
