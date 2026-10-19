extends RefCounted
## (v63, the author's R1 and his notebook: "hydroponics: a bot or a person must
## tend it; a variety of plants, mutations and combinatorics") What grows in the
## hydroponic trays, shared by the server and the client.
##
## A seed packet is a thing (Net.ITEM_SEED + kind * TRAITS + trait): the plant
## it grows and its trait. Four plants are bought from traders; two hybrids come
## only from two neighbouring trays ripe at the same time with the right pair in
## them. A harvested seed may come back with a mutation: "rich" (one ration more
## at every harvest), "early" (it ripens a third sooner), or both ("choice").
## What a plant does (grow times, harvests) is in KINDS; the trays themselves
## are the server's Garden.

const Net := preload("res://src/shared/net.gd")

const MUSHROOM := 0
const CHLORELLA := 1
const SOY := 2
const POTATO := 3
const TUBER := 4                     # a hybrid: potato and soy side by side
const HERB := 5                      # a hybrid: mushroom and chlorella side by side
const COUNT := 6
const BOUGHT := 4                    # the first four are sold by traders

const PLAIN := 0                     # traits of a seed
const RICH := 1                      # +1 ration at harvest
const EARLY := 2                     # ripens EARLY_SHARE as long
const CHOICE := 3                    # both
const TRAITS := 4
const TRAIT_NAMES: Array[String] = ["", "урожайный", "скороспелый", "отборный"]
const EARLY_SHARE := 0.67

## name, seconds to ripen (tended all the way), rations at harvest, plasters at harvest, grows without power,
## price of a packet (0 = not sold), what a tray of it looks like (leaf colour)
const KINDS: Array[Dictionary] = [
	{"name": "Грибы", "seconds": 240.0, "food": 2, "dark": true, "price": 4, "leaf": Color(0.82, 0.72, 0.58),
		"about": "Растут быстро и даже без света и энергии, но дают мало."},
	{"name": "Хлорелла", "seconds": 300.0, "food": 3, "price": 5, "leaf": Color(0.3, 0.85, 0.45),
		"about": "Водоросль: растёт быстро, кормит неплохо."},
	{"name": "Соя", "seconds": 420.0, "food": 4, "price": 6, "leaf": Color(0.55, 0.8, 0.3),
		"about": "Растёт дольше, кормит хорошо. Рядом с картофелем может дать гибрид."},
	{"name": "Картофель", "seconds": 540.0, "food": 6, "price": 8, "leaf": Color(0.4, 0.62, 0.3),
		"about": "Медленный, но самый сытный из покупных. Рядом с соей может дать гибрид."},
	{"name": "Сладкий клубень", "seconds": 480.0, "food": 8, "price": 0, "leaf": Color(0.85, 0.45, 0.6),
		"about": "Гибрид картофеля и сои: самый большой урожай."},
	{"name": "Целебная трава", "seconds": 360.0, "food": 1, "plasters": 2, "price": 0, "leaf": Color(0.5, 0.95, 0.85),
		"about": "Гибрид грибов и хлореллы: из неё делают пластыри."},
]
## the pairs that may cross: [plant, plant, the hybrid]
const CROSSES: Array = [[POTATO, SOY, TUBER], [MUSHROOM, CHLORELLA, HERB]]
const CROSS_CHANCE := 0.35           # two such neighbours ripe together give a hybrid seed this often
const MUTATE_CHANCE := 0.2           # a seed that comes back from a harvest mutates this often
const SEED_BACK := 0.6               # a harvest gives a seed of its plant back this often


static func seed_item(kind: int, trait_of: int = PLAIN) -> int:
	return Net.ITEM_SEED + kind * TRAITS + trait_of


static func is_seed(item: int) -> bool:
	return item >= Net.ITEM_SEED and item < Net.ITEM_SEED + COUNT * TRAITS


static func kind_of(item: int) -> int:
	return (item - Net.ITEM_SEED) / TRAITS


static func trait_of(item: int) -> int:
	return (item - Net.ITEM_SEED) % TRAITS


static func seconds(item: int) -> float:
	var t := trait_of(item)
	return float(KINDS[kind_of(item)]["seconds"]) * (EARLY_SHARE if t == EARLY or t == CHOICE else 1.0)


static func food(item: int) -> int:
	var t := trait_of(item)
	return int(KINDS[kind_of(item)]["food"]) + (1 if t == RICH or t == CHOICE else 0)


static func plasters(item: int) -> int:
	return int(KINDS[kind_of(item)].get("plasters", 0))


static func dark(item: int) -> bool:
	return bool(KINDS[kind_of(item)].get("dark", false))


static func name_of(item: int) -> String:
	## "Семена: соя (урожайный)".
	var t := trait_of(item)
	var n: String = KINDS[kind_of(item)]["name"]
	return "Семена: %s%s" % [n.to_lower(), "" if t == PLAIN else " (%s)" % TRAIT_NAMES[t]]


static func plant_name(item: int) -> String:
	return str(KINDS[kind_of(item)]["name"])


static func mutate(trait_now: int, roll: float) -> int:
	## A mutation adds what the seed lacks: plain becomes rich or early, either of those choice.
	match trait_now:
		PLAIN:
			return RICH if roll < 0.5 else EARLY
		RICH, EARLY:
			return CHOICE
	return CHOICE


static func cross(a: int, b: int) -> int:
	## The hybrid two plants side by side may give, or -1.
	for c: Array in CROSSES:
		if (int(c[0]) == a and int(c[1]) == b) or (int(c[0]) == b and int(c[1]) == a):
			return int(c[2])
	return -1
