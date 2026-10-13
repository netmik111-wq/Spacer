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

const INFO := {
	Net.ITEM_PATCH: {"name": "Заплатка", "about": "Лист обшивки: заделывает пробоину.",
		"price": 5, "stock": 8},
	Net.ITEM_PART: {"name": "Запчасть", "about": "Ускоряет ремонт машин и дверей втрое.",
		"price": 10, "stock": 5},
	Net.ITEM_FLASHLIGHT: {"name": "Фонарик", "about": "Светит узким лучом. Свет видно издалека.",
		"price": 8, "stock": 4, "switch": Net.ITEM_FLASHLIGHT_ON},
	Net.ITEM_FLASHLIGHT_ON: {"name": "Фонарик (горит)", "about": "Светит узким лучом. Свет видно издалека.",
		"kind": Net.ITEM_FLASHLIGHT, "switch": Net.ITEM_FLASHLIGHT, "light": [25.0, 9]},
}


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
