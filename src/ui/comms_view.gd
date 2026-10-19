extends VBoxContainer
## (v63) The comms console's screen: the call waiting for an answer (its story
## and the answers; blue ones are open thanks to somebody aboard or something in
## the locker, grey ones cannot be taken now), or the last call's outcome; below,
## the quests taken and what is known of the pirates' flagship. The server runs
## it all (see Story). Shown inside the console frame of GameScreen.

const Net := preload("res://src/shared/net.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const GameClient := preload("res://src/client/game_client.gd")

const INK := Color(0.86, 0.9, 0.95)
const DIM := Color(0.58, 0.62, 0.7)
const BLUE := Color(0.45, 0.75, 1.0)
const WARN := Color(0.95, 0.75, 0.3)
const QUEST_NAMES: Array[String] = ["груз", "охота", "чёрный ящик", "сюжет"]

var client: GameClient
var _title: Label
var _text: Label
var _timer: Label
var _choices: VBoxContainer
var _quests: Label
var _flagship: Label
var _shown_at := -1


func setup(p_client: GameClient) -> void:
	client = p_client
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(640, 0)
	_title = _label(17, INK)
	add_child(_title)
	_text = _label(14, INK)
	add_child(_text)
	_timer = _label(13, DIM)
	add_child(_timer)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	add_child(_choices)
	add_child(HSeparator.new())
	_quests = _label(13, INK)
	add_child(_quests)
	_flagship = _label(13, WARN)
	add_child(_flagship)


func _label(size: int, colour: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(620, 0)
	return l


func refresh() -> void:
	var c: Dictionary = client.comms
	var calling := int(c.get("state", Net.COMMS_QUIET)) == Net.COMMS_CALL
	if int(c.get("at", -1)) != _shown_at:
		_shown_at = int(c.get("at", -1))
		_build(c, calling)
	if calling:
		var left := maxi(int(c["seconds"]) - (Time.get_ticks_msec() - int(c["at"])) / 1000, 0)
		_timer.text = "Без ответа через %d с будет выбран обычный ответ." % left
	_quests.text = _quest_text()
	_flagship.text = _flagship_text()


func _build(c: Dictionary, calling: bool) -> void:
	for b in _choices.get_children():
		b.queue_free()
	if c.is_empty() or (not calling and str(c.get("title", "")) == ""):
		_title.text = "Эфир молчит"
		_text.text = "Вызовы приходят сами, когда корабль прибывает в спокойные места, на сигнал SOS и по заданиям."
		_timer.text = ""
		return
	_title.text = str(c["title"]) if calling else "Последний вызов: " + str(c["title"])
	_text.text = str(c["text"])
	_timer.text = ""
	if not calling:
		return
	var i := 0
	for ch: Array in c["choices"]:
		var b := Button.new()
		var flags := int(ch[0])
		b.text = "%d. %s" % [i + 1, ch[1]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = flags & Net.CHOICE_SHUT != 0
		if flags & Net.CHOICE_BLUE:
			b.add_theme_color_override("font_color", BLUE)
		if b.disabled:
			b.tooltip_text = "Нельзя: на борту нет того, что для этого нужно."
		var k := i
		b.pressed.connect(func() -> void: client.send_comms(k))
		_choices.add_child(b)
		i += 1


func choose(n: int) -> void:
	## A number key: that answer (GameScreen passes keys 1..4 here while the screen is open).
	var c: Dictionary = client.comms
	if int(c.get("state", Net.COMMS_QUIET)) == Net.COMMS_CALL and n < (c["choices"] as Array).size() \
			and int(c["choices"][n][0]) & Net.CHOICE_SHUT == 0:
		client.send_comms(n)


func _quest_text() -> String:
	var s: Dictionary = client.story
	var qs: Array = s.get("quests", [])
	if qs.is_empty():
		return "Заданий нет."
	var here: Vector2i = client.sectors.cell[client.sectors.here] if client.sectors.count > 0 else Vector2i.ZERO
	var lines: Array[String] = ["Задания:"]
	for q: Dictionary in qs:
		var d: int = client.sectors.hops_between(here, q["at"])
		lines.append("• %s (%s, %d кр.): %s Прыжков до цели: %d." % [q["title"], QUEST_NAMES[clampi(int(q["kind"]), 0, 3)],
			int(q["reward"]), q["text"], d])
	return "\n".join(lines)


func _where(at: Vector2i) -> String:
	var sec = client.sectors
	for i in sec.count:
		if sec.cell[i] == at:
			return "в секторе %s" % sec.names[i] + (" (мы здесь)" if i == sec.here else "")
	return "в другом скоплении"


func _flagship_text() -> String:
	var s: Dictionary = client.story
	var f := int(s.get("flags", 0))
	var lines: Array[String] = []
	if f & Net.STORY_STARVING:
		lines.append("Пайков нет: экипаж голодает.")
	if f & Net.STORY_CODES:
		lines.append("Коды флагмана у нас: в бою видны все его отсеки.")
	if client.won:
		lines.append("Флагман разбит.")
	elif f & Net.STORY_FLAGSHIP:
		var grow := int(s["grow_s"])
		lines.append("Флагман пиратов рыщет %s. Рост: %d из 4%s." % [_where(s["flagship"]), int(s["growth"]),
			(", следующий шаг через %d:%02d" % [grow / 60, grow % 60]) if grow != 65535 else ""])
	else:
		lines.append("Флагман пиратов ждёт в своём логове, в %d-м скоплении пути. Он выйдет на охоту, когда мы войдём туда." % (Sectors.FLAG_DEPTH + 1))
	return "\n".join(lines)
