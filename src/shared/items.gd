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
## Later things will add their own properties here (damage, what it protects
## from, which layer of clothing it is), so a new kind of thing does not need
## new code where things are moved about.

const Net := preload("res://src/shared/net.gd")

const PISTOL_ABOUT := "Стреляет туда, куда щёлкнули. Перезаряжается магазином."
const MEDKIT_ABOUT := "Лечит раны: себе или соседу, три секунды не сходя с места. Пять раз."
const MEDKIT_HEAL := 30

const SUIT_ABOUT := "Шлем и баллон с кислородом. Без него подача кислорода (Q) не работает. Z: надеть."

const INFO := {
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
	Net.ITEM_FLASHLIGHT: {"name": "Фонарик", "about": "Светит узким лучом. Свет видно издалека.",
		"price": 8, "stock": 4, "switch": Net.ITEM_FLASHLIGHT_ON},
	Net.ITEM_FLASHLIGHT_ON: {"name": "Фонарик (горит)", "about": "Светит узким лучом. Свет видно издалека.",
		"kind": Net.ITEM_FLASHLIGHT, "switch": Net.ITEM_FLASHLIGHT, "light": [35.0, 9]},
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

const PISTOL_DAMAGE := 30
const PISTOL_RANGE := 14


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
	return str(INFO[item]["name"]) if INFO.has(item) else ""


static func about(item: int) -> String:
	return str(INFO[item].get("about", "")) if INFO.has(item) else ""


static func kind_of(item: int) -> int:
	## The thing this is a state of; itself for most things.
	return int(INFO[item].get("kind", item)) if INFO.has(item) else item


static func price(item: int) -> int:
	return int(INFO[item].get("price", 0)) if INFO.has(item) else 0


static func stock(item: int) -> int:
	return int(INFO[item].get("stock", 0)) if INFO.has(item) else 0


static func switched(item: int) -> int:
	## What it turns into when used in the hand, or ITEM_NONE if using it does nothing.
	return int(INFO[item].get("switch", Net.ITEM_NONE)) if INFO.has(item) else Net.ITEM_NONE


static func light(item: int) -> Array:
	## [cone width in degrees, reach in cells] of the light it gives, or [] if it gives none.
	return INFO[item].get("light", []) if INFO.has(item) else []


static func kept_in_locker() -> PackedInt32Array:
	## The things the supply locker holds, in the order they are shown.
	var out := PackedInt32Array()
	for item: int in INFO.keys():
		if kind_of(item) == item and stock(item) > 0:
			out.append(item)
	return out
