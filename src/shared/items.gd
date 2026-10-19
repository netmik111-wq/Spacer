extends RefCounted
## What every thing that can be carried is, and what it can do. The server
## and the client read the same table, so a new thing is added here once:
## a number in Net.ITEM_*, a line in INFO, a picture in ItemArt, and its use
## wherever it is used.
##
## Properties of a thing (all but "name" may be left out):
##   name     what it is called on screen
##   about    one line on what it is for
##   price    what a trader asks for it (0 = traders do not sell it)
##   stock    how many the ship sets out with in its supply locker (0 = none,
##            and the locker does not keep it)
##   kind     the thing it is a state of (a lit flashlight is a flashlight):
##            counted, stored and sold as that
##   switch   what it turns into when used in the hand (Z)
##   light    [cone width in degrees, reach in cells]: it shines while in the hand
##   cargo    true: kept in the supply locker as the ship's cargo, never carried
##            (ship weapons and their rockets)
##   gun      the ship weapon (Weapons.*) it is: its name, words and price come from there
##   gear     (v59) the crate of ship gear (Gear.*) it is: the same; carried, and kept in the locker
##   keep     (v63) kept in the supply locker though the ship sets out with none (seeds, a black box)
##   seed     (v63) the packet of seeds it is (Plants): its name, words and price come from there
## Later things will add their own properties here (damage, what it protects
## from, which layer of clothing it is), so a new kind of thing does not need
## new code where things are moved about.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")
const Plants := preload("res://src/shared/plants.gd")

const PISTOL_ABOUT := "Стреляет туда, куда щёлкнули. Перезаряжается магазином."
const MEDKIT_ABOUT := "Лечит раны: себе или соседу, три секунды не сходя с места. Пять раз."
const MEDKIT_HEAL := 30

const SUIT_ABOUT := "Шлем и баллон с кислородом. Без него подача кислорода (Q) не работает. Z: надеть."

const BASE := {
	Net.ITEM_JUMPSUIT: {"name": "Комбинезон", "about": "Два кармана. Z: надеть.", "price": 8, "stock": 2, "wear": Net.WEAR_JUMPSUIT},
	Net.ITEM_BACKPACK: {"name": "Рюкзак", "about": "Четыре места для вещей. Z: надеть.", "price": 15, "stock": 2, "wear": Net.WEAR_PACK},
	Net.ITEM_PATCH: {"name": "Заплатка", "about": "Лист обшивки: заделывает пробоину.",
		"price": 5, "stock": 8},
	Net.ITEM_FUEL: {"name": "Топливо", "about": "Канистра топлива на один прыжок. Прыжок берёт её из шкафа снабжения.",
		"price": 6, "stock": 8},
	Net.ITEM_RADIO: {"name": "Рация", "about": "Сказанное с «;» в начале слышат все, у кого есть рация, где бы они ни были.",
		"price": 6, "stock": 4},
	Net.ITEM_PART: {"name": "Запчасть", "about": "Ускоряет ремонт машин и дверей втрое.",
		"price": 10, "stock": 5},
	Net.ITEM_FLASHLIGHT: {"name": "Фонарик", "about": "Светит мягким пятном вокруг и немного вперёд. Свет видно издалека.",
		"price": 8, "stock": 4, "switch": Net.ITEM_FLASHLIGHT_ON},
	Net.ITEM_FLASHLIGHT_ON: {"name": "Фонарик (горит)", "about": "Светит мягким пятном вокруг и немного вперёд. Свет видно издалека.",
		"kind": Net.ITEM_FLASHLIGHT, "switch": Net.ITEM_FLASHLIGHT, "light": [6.0, 1.5]},
	Net.ITEM_MAG: {"name": "Магазин", "about": "Восемь патронов к пистолету.", "price": 6, "stock": 2},
	Net.ITEM_BATON: {"name": "Дубинка", "about": "Бьёт того, кто рядом.", "price": 8, "stock": 1,
		"blow": 15},
	Net.ITEM_MEDPATCH: {"name": "Пластырь", "about": "Сразу закрывает раны: себе или соседу.", "price": 6, "stock": 2,
		"heal": 40},
	# a pistol's rounds are part of what it is: one number per load, so a pistol
	# keeps its rounds in a pocket, on the floor and on a body alike
	# a first-aid kit counts its uses the same way
	Net.ITEM_MEDKIT + 1: {"name": "Аптечка", "about": MEDKIT_ABOUT, "kind": Net.ITEM_MEDKIT + Net.MEDKIT_USES, "uses": 1, "treat": MEDKIT_HEAL},
	Net.ITEM_MEDKIT + 2: {"name": "Аптечка", "about": MEDKIT_ABOUT, "kind": Net.ITEM_MEDKIT + Net.MEDKIT_USES, "uses": 2, "treat": MEDKIT_HEAL},
	Net.ITEM_MEDKIT + 3: {"name": "Аптечка", "about": MEDKIT_ABOUT, "kind": Net.ITEM_MEDKIT + Net.MEDKIT_USES, "uses": 3, "treat": MEDKIT_HEAL},
	Net.ITEM_MEDKIT + 4: {"name": "Аптечка", "about": MEDKIT_ABOUT, "kind": Net.ITEM_MEDKIT + Net.MEDKIT_USES, "uses": 4, "treat": MEDKIT_HEAL},
	Net.ITEM_MEDKIT + 5: {"name": "Аптечка", "about": MEDKIT_ABOUT, "kind": Net.ITEM_MEDKIT + Net.MEDKIT_USES, "uses": 5, "treat": MEDKIT_HEAL, "price": 15, "stock": 2},
	# a spacesuit carries what is left in its tank, in tenths
	Net.ITEM_SUIT + 0: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 0},
	Net.ITEM_SUIT + 1: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 1},
	Net.ITEM_SUIT + 2: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 2},
	Net.ITEM_SUIT + 3: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 3},
	Net.ITEM_SUIT + 4: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 4},
	Net.ITEM_SUIT + 5: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 5},
	Net.ITEM_SUIT + 6: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 6},
	Net.ITEM_SUIT + 7: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 7},
	Net.ITEM_SUIT + 8: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 8},
	Net.ITEM_SUIT + 9: {"name": "Скафандр", "about": SUIT_ABOUT, "kind": Net.ITEM_SUIT + 10, "wear": Net.WEAR_SUIT, "tank": 9},
	Net.ITEM_SUIT + 10: {"name": "Скафандр", "about": SUIT_ABOUT, "wear": Net.WEAR_SUIT, "tank": 10, "price": 40, "stock": 2},
	# rockets and shells: cargo (the ship's weapons off their mounts are added by _made, below)
	Net.ITEM_ROCKET: {"name": "Ракета", "about": "Ракета для ракетной установки. Хранится в трюме.", "price": Weapons.ROCKET_PRICE, "cargo": true},
	Net.ITEM_EMP_ROCKET: {"name": "ЭМИ-ракета", "about": "Ракета для ЭМИ-установки. Хранится в трюме.", "price": Weapons.EMP_ROCKET_PRICE, "cargo": true},
	Net.ITEM_SHELL: {"name": "Снаряд", "about": "Снаряд для автопушки и «Молота». Хранится в трюме.", "price": Weapons.SHELL_PRICE, "cargo": true},
	Net.ITEM_PROBE: {"name": "Зонд-сканер", "about": "Запускается с пульта орудий: показывает все отсеки пиратского корабля, его экипаж и повадки. Хранится в трюме.",
		"price": 12, "stock": 1, "cargo": true},
	Net.ITEM_DRONE: {"name": "Дрон-разведчик", "about": "Запускается с монитора дрона на мостике: залетает внутрь пиратского корабля, им управляют клавишами движения. Показывает отсеки, где побывал, и пиратов рядом; может взорваться в отсеке и повредить систему сквозь щит. Хранится в трюме.",
		"price": 20, "stock": 1, "cargo": true},
	# (v62, the author's K11) a security robot in its crate: kept in the locker, carried, set down to switch on
	Net.ITEM_ROBOT: {"name": "Охранный робот", "about": "Робот в ящике. Поставьте его на пол (щёлкните по соседней клетке или нажмите E перед свободным местом): он включится и будет охранять этот отсек, стреляя по абордажникам. Воздух ему не нужен. На борту не больше двух.",
		"price": 120, "robot": true},
	# (v63, the author's R1) the crew's food, and what quests are about
	Net.ITEM_FOOD: {"name": "Паёк", "about": "Еда экипажа. Каждый прыжок экипаж съедает из шкафа снабжения по пайку на двоих; без еды все слабеют. Растёт в гидропонике.",
		"price": 3, "stock": 16},
	Net.ITEM_CARGO: {"name": "Груз по заданию", "about": "Опечатанный контейнер. Его ждут на станции снабжения, отмеченной на карте: подойдите к ней. Хранится в трюме.",
		"cargo": true},
	Net.ITEM_BLACKBOX: {"name": "Чёрный ящик", "about": "Бортовой самописец с обломков. Положите его в шкаф снабжения: заказчик заберёт запись по связи.",
		"keep": true},
	Net.ITEM_PISTOL + 0: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 0, "price": 25, "stock": 1},
	Net.ITEM_PISTOL + 1: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 1},
	Net.ITEM_PISTOL + 2: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 2},
	Net.ITEM_PISTOL + 3: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 3},
	Net.ITEM_PISTOL + 4: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 4},
	Net.ITEM_PISTOL + 5: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 5},
	Net.ITEM_PISTOL + 6: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 6},
	Net.ITEM_PISTOL + 7: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 7},
	Net.ITEM_PISTOL + 8: {"name": "Пистолет", "about": PISTOL_ABOUT, "kind": Net.ITEM_PISTOL, "rounds": 8},
}

# (v58) Every thing: BASE, and the ship's weapons in all their states (whole, with
# a tier 3 effect, damaged) and the parts guns are taken apart into, made here
# once (there are too many to write out by hand).
static var INFO: Dictionary = _made()


static func _made() -> Dictionary:
	var out := BASE.duplicate()
	for item in Weapons.gun_items():
		var w := Weapons.of_item(item)
		var e := {"gun": w, "cargo": true}
		if Weapons.fx_of(item) != Weapons.FX_NONE:
			e["fx"] = Weapons.fx_of(item)
		if Weapons.damaged(item):
			e["damaged"] = true
		out[item] = e
	for g in Gear.all():
		out[Gear.item_of(g)] = {"gear": g}
	for kind in Plants.COUNT:
		for t in Plants.TRAITS:
			var e := {"seed": true, "keep": true}
			if t == Plants.PLAIN and kind < Plants.BOUGHT:
				e["price"] = int(Plants.KINDS[kind]["price"])
				if kind == Plants.MUSHROOM or kind == Plants.POTATO:
					e["stock"] = 2                   # the ship sets out with a little to plant
			out[Plants.seed_item(kind, t)] = e
	for k in Weapons.KINDS:
		out[Net.ITEM_GUN_PARTS + k] = {"name": "Детали: %s" % Weapons.KIND_NAMES[k], "cargo": true, "price": 12,
			"about": "Детали орудий, %s. Получаются, когда инженер разбирает такое орудие на верстаке; ими же он улучшает орудия этого рода. Хранятся в трюме." % Weapons.KIND_NAMES[k]}
	return out


const PISTOL_DAMAGE := 30
const PISTOL_RANGE := 14


static func carried_gun(item: int) -> bool:
	## (v60) A ship gun that may be taken out of the locker to carry to its mount (not
	## the point defence: it is set from the gun console, it has no mount in the hull).
	var w := Weapons.of_item(item) if INFO.has(item) else Weapons.NONE
	return w != Weapons.NONE and w != Weapons.GUARD


static func rounds(item: int) -> int:
	## Rounds in a pistol; -1 if it is not one.
	return int(INFO[item].get("rounds", -1)) if INFO.has(item) else -1


static func uses(item: int) -> int:
	## Uses left in a first-aid kit; -1 if it is not one.
	return int(INFO[item].get("uses", -1)) if INFO.has(item) else -1


static func whole(item: int) -> bool:
	## Is it as it came from the locker (a kit not started on, a suit with a full tank)? Only such things go back in.
	return (uses(item) < 0 or uses(item) == Net.MEDKIT_USES) and (tank_of(item) < 0 or tank_of(item) == Net.SUIT_TANK_STEPS)


static func worn_as(item: int) -> int:
	## Where it is worn (Net.WEAR_*), or -1 if it is not something to wear.
	return int(INFO[item].get("wear", -1)) if INFO.has(item) else -1


static func tank_of(item: int) -> int:
	## Tenths of a tank in a spacesuit; -1 if it is not one.
	return int(INFO[item].get("tank", -1)) if INFO.has(item) else -1


static func suit_with(tank: float) -> int:
	## A spacesuit, as an item, holding that much oxygen (0..1).
	return Net.ITEM_SUIT + clampi(roundi(tank * Net.SUIT_TANK_STEPS), 0, Net.SUIT_TANK_STEPS)


static func is_weapon(item: int) -> bool:
	return rounds(item) >= 0 or (INFO.has(item) and INFO[item].has("blow"))


static func known(item: int) -> bool:
	return INFO.has(item)


static func name_of(item: int) -> String:
	if not INFO.has(item):
		return ""
	if INFO[item].has("gun"):
		var n := Weapons.full_name(int(INFO[item]["gun"]), int(INFO[item].get("fx", 0)))
		return ("Повреждённое орудие: " + Weapons.lower_name(int(INFO[item]["gun"]))) if INFO[item].has("damaged") else n
	if INFO[item].has("gear"):
		return Gear.name_of(int(INFO[item]["gear"]))
	return str(INFO[item]["name"])


static func about(item: int) -> String:
	if INFO.has(item) and INFO[item].has("gun"):
		var w := int(INFO[item]["gun"])
		if INFO[item].has("damaged"):
			return "Повреждено: прежде чем ставить, его чинит инженер на верстаке (одна запчасть). " + str(Weapons.info(w)["about"])
		var fx := int(INFO[item].get("fx", 0))
		return str(Weapons.info(w)["about"]) + " Энергия: %d." % Weapons.power(w) + ("" if fx == 0 else " " + Weapons.about_fx(fx))
	if INFO.has(item) and INFO[item].has("gear"):
		return Gear.about(int(INFO[item]["gear"]))
	if INFO.has(item) and INFO[item].has("seed"):
		var k: Dictionary = Plants.KINDS[Plants.kind_of(item)]
		return "%s Держите E у лотка гидропоники, чтобы посадить. Созревает за %d мин, урожай: %d пайк%s%s." % [
			k["about"], roundi(Plants.seconds(item) / 60.0), Plants.food(item), "а" if Plants.food(item) in [2, 3, 4] else ("" if Plants.food(item) == 1 else "ов"),
			(" и %d пластыря" % Plants.plasters(item)) if Plants.plasters(item) > 0 else ""]
	return str(INFO[item].get("about", "")) if INFO.has(item) else ""


static func cargo(item: int) -> bool:
	## Is it the ship's cargo (kept in the locker, never carried)?
	return INFO.has(item) and bool(INFO[item].get("cargo", false))


static func kind_of(item: int) -> int:
	## The thing this is a state of; itself for most things.
	return int(INFO[item].get("kind", item)) if INFO.has(item) else item


static func price(item: int) -> int:
	if INFO.has(item) and INFO[item].has("gun"):
		var w := int(INFO[item]["gun"])
		if Weapons.unique(w):
			return 0                         # (the flagship's gun: no trader deals in it)
		return int(Weapons.info(w)["price"]) / (3 if INFO[item].has("damaged") else 1)
	if INFO.has(item) and INFO[item].has("gear"):
		return Gear.price(int(INFO[item]["gear"]))
	return int(INFO[item].get("price", 0)) if INFO.has(item) else 0


static func stock(item: int) -> int:
	return int(INFO[item].get("stock", 0)) if INFO.has(item) else 0


static func switched(item: int) -> int:
	## What it turns into when used in the hand, or ITEM_NONE if using it does nothing.
	return int(INFO[item].get("switch", Net.ITEM_NONE)) if INFO.has(item) else Net.ITEM_NONE


static func light(item: int) -> Array:
	## [radius, cells ahead] of the pool of light it gives (Sight.glow), or [] if it gives none.
	return INFO[item].get("light", []) if INFO.has(item) else []


static func kept_in_locker() -> PackedInt32Array:
	## The things the supply locker holds, in the order they are shown.
	var out := PackedInt32Array()
	for item: int in INFO.keys():
		if kind_of(item) == item and (stock(item) > 0 or cargo(item) or INFO[item].has("gear") or INFO[item].has("robot") or INFO[item].has("keep")) \
				and not INFO[item].has("fx") and not INFO[item].has("damaged"):
			out.append(item)                 # ((v58) a gun's other states get a place in the locker when one comes)
	return out


# The kinds of thing, as the supply locker and the trader show them: caption, the things in it.
static var CATEGORIES: Array = [
	["Ремонт и топливо", [Net.ITEM_PATCH, Net.ITEM_PART, Net.ITEM_FUEL]],
	["Снаряжение", [Net.ITEM_SUIT + Net.SUIT_TANK_STEPS, Net.ITEM_JUMPSUIT, Net.ITEM_BACKPACK, Net.ITEM_FLASHLIGHT, Net.ITEM_RADIO]],
	["Медицина", [Net.ITEM_MEDPATCH, Net.ITEM_MEDKIT + Net.MEDKIT_USES]],
	["Личное оружие", [Net.ITEM_PISTOL, Net.ITEM_MAG, Net.ITEM_BATON]],
	["Корабельное оружие", Array(Weapons.gun_items())],
	["Боеприпасы", [Net.ITEM_ROCKET, Net.ITEM_EMP_ROCKET, Net.ITEM_SHELL]],
	["Детали орудий", range(Net.ITEM_GUN_PARTS, Net.ITEM_GUN_PARTS + Weapons.KINDS)],
	["Модули корабля", Gear.all().map(func(g: int) -> int: return Gear.item_of(g))],
	["Разведка", [Net.ITEM_PROBE, Net.ITEM_DRONE]],
	["Охрана", [Net.ITEM_ROBOT]],
	["Провизия", [Net.ITEM_FOOD]],
	["Семена", range(Net.ITEM_SEED, Net.ITEM_SEED + Plants.COUNT * Plants.TRAITS)],
	["Задания", [Net.ITEM_CARGO, Net.ITEM_BLACKBOX]],
]


static func is_seed(item: int) -> bool:
	return INFO.has(item) and INFO[item].has("seed")


static func gear_of(item: int) -> int:
	## (v59) The crate of ship gear a thing is (Gear.*), or Gear.NONE.
	return int(INFO[item]["gear"]) if INFO.has(item) and INFO[item].has("gear") else Gear.NONE


static func gun_parts(kind: int) -> int:
	## (v58) The thing that parts of that kind of gun are.
	return Net.ITEM_GUN_PARTS + kind


static func spawnable() -> PackedInt32Array:
	## One of every thing, as it comes new (a pistol loaded, a kit full, a suit's
	## tank full, a flashlight off): for the admin panel.
	var out := PackedInt32Array()
	for item: int in INFO.keys():
		if kind_of(item) != item or not light(item).is_empty() or cargo(item):
			continue
		out.append(item + Net.PISTOL_ROUNDS if rounds(item) == 0 else item)
	return out


static func admin_sections() -> Array:
	## (v60.1) Every thing, as it comes new, under the captions the locker uses
	## (CATEGORIES), and whatever no caption holds under «Прочее»: for the admin
	## panel, so that a new thing shows up there by itself. Ship guns are given
	## whole and without an effect (the panel adds those).
	var left := {}
	for item in spawnable():
		left[item] = true
	for item: int in INFO.keys():
		if kind_of(item) == item and cargo(item) and not INFO[item].has("fx") and not INFO[item].has("damaged"):
			left[item] = true
	var out: Array = []
	for c: Array in CATEGORIES:
		var things := PackedInt32Array()
		for item: int in c[1]:
			var new := item + Net.PISTOL_ROUNDS if rounds(item) == 0 else item
			if left.has(new):
				things.append(new)
				left.erase(new)
		if not things.is_empty():
			out.append([c[0], things])
	if not left.is_empty():
		var rest := PackedInt32Array(left.keys())
		rest.sort()
		out.append(["Прочее", rest])
	return out
