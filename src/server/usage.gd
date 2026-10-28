extends RefCounted
## (v82, the author's worry "mechanics too deep, the game loses fun") How often the crew
## used each of the game's systems this run. Bots do not count: only what people chose
## to do. The end screen lists it (Net.S_SUMMARY), the campaign save keeps it, and
## usage.txt next to the game holds it after every save, so the author can send it
## and we cut or simplify what nobody touched (by real play, not by the simulator).
## Part of the server: GameServer keeps one of these.

const Player := preload("res://src/server/player.gd")

## Every counted thing, in the order shown, with its name for the player.
const NAMES := {
	"evade": "уклонение пилота", "panel": "щит питания", "overcharge": "форсаж реактора",
	"load": "снаряды вручную", "alert": "уровни тревоги", "galley": "камбуз",
	"tend": "присмотр за автодоком", "scan": "сканер тела", "treat": "аптечки и шины", "box": "ящики на стенах",
	"cuffs": "наручники", "sell_prisoners": "сдача пленных", "weld": "сварка дверей",
	"hold": "держать позицию", "crawl": "лечь (C)", "drone": "дрон-разведчик",
	"bench": "верстак", "comms": "ответы по связи", "trade": "торговля",
	"shuttle": "челнок флотилии",
	"shield_arc": "дуга щита", "aim_all": "огонь всеми орудиями", "goggles": "ночное видение и тепловизор",
}

var server: GameServer
var used := {}                       # key of NAMES -> times a person used it this run


func setup(p_server: GameServer) -> void:
	server = p_server


func note(p: Player, key: String) -> void:
	## A person (never a bot, a pirate or a robot) used that system once.
	if p == null or p.bot or p.pirate or p.ally:
		return
	used[key] = int(used.get(key, 0)) + 1


func lines() -> Array:
	## [name, times] for every counted thing, the unused ones too, most used first.
	var out: Array = []
	for key: String in NAMES.keys():
		out.append([str(NAMES[key]), int(used.get(key, 0))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	return out


func text() -> String:
	var out := "Чем экипаж пользовался за игру (Spacer %s, %s)\n" % [
		str(ProjectSettings.get_setting("application/config/version", "")), Time.get_datetime_string_from_system()]
	for line: Array in lines():
		out += "%5d  %s\n" % [int(line[1]), str(line[0])]
	return out


static func path() -> String:
	## Next to the game (run from the project: in user://), like crew_log.txt.
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("usage.txt")
	return "user://usage.txt"


func write() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f != null:
		f.store_string(text())
		f.close()


func load_from(d: Dictionary) -> void:
	used.clear()
	for key in d.keys():
		if NAMES.has(str(key)):
			used[str(key)] = int(d[key])
