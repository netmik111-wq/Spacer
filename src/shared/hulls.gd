extends RefCounted
## The kinds of pirate ship (v53, the author's request: "many options of what we
## fight against, a different setup for each ship"). Shared, so that the client
## can name and explain what the server rolled.
##
## A pirate ship is one of four classes. Each class has one or more hand-drawn
## hulls (maps/pirate*.txt, by their number in Net.OTHER_MAPS) and a range of
## everything else; the server's Shipyard rolls the rest for every ship that
## comes: which of its rooms holds which system, its guns, whether it has a
## shield, its crew, its temper and its name. Bigger classes come only farther
## from the start. They are harder through what they carry and how they fight,
## not only through more hull (the author's vision: "not more HP just because").
##
## Properties of a class:
##   name      what it is called ("пиратский катер")
##   layouts   its hulls: numbers in Net.OTHER_MAPS
##   hull      damage it takes before it is wrecked
##   strength  damage that puts one of its systems out
##   guns      [guns near the start, guns from `more_from` jumps out]
##   more_from jumps from the start at which it carries its extra gun
##   pool      the guns it may roll (Weapons.*); the first gun is always its first
##   shield    chance it has a shield generator
##   regen     how fast its shield refills against the plain rate (1.0)
##   slower    its guns charge this much slower than ours
##   dodge     taken off our chance to hit it (negative: easier to hit)
##   crew      [fewest, most] of its crew in a raid (a boarding party is the director's)
##   from      jumps from the start before it may come at all
##   weight    how often it comes, against the others that may
##   reward    credits for wrecking it
##   loot      [fewest, most] things lying about aboard it

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const CLASSES := {
	Net.ECLASS_CUTTER: {"name": "пиратский катер", "layouts": [2, 6], "hull": 8, "strength": 2, "guns": [1, 2], "more_from": 4,
		"pool": [Weapons.LASER, Weapons.RAPID, Weapons.ION, Weapons.BLASTER], "shield": 0.4, "regen": 1.0, "slower": 1.15,
		"dodge": 0.12, "crew": [2, 3], "from": 0, "weight": 3, "reward": 25, "loot": [1, 3]},
	Net.ECLASS_RAIDER: {"name": "пиратский рейдер", "layouts": [1, 3], "hull": 12, "strength": 3, "guns": [2, 3], "more_from": 5,
		"pool": [Weapons.LASER, Weapons.RAPID, Weapons.BLASTER, Weapons.ION, Weapons.ROCKET, Weapons.HEAVY], "shield": 0.7,
		"regen": 1.0, "slower": 1.3, "dodge": 0.0, "crew": [2, 4], "from": 0, "weight": 4, "reward": 40, "loot": [2, 4]},
	Net.ECLASS_GUNSHIP: {"name": "пиратская канонерка", "layouts": [4, 7], "hull": 14, "strength": 3, "guns": [3, 4], "more_from": 8,
		"pool": [Weapons.LASER, Weapons.HEAVY, Weapons.RAPID, Weapons.BLASTER, Weapons.ROCKET, Weapons.ION, Weapons.EMP],
		"shield": 0.6, "regen": 1.0, "slower": 1.5, "dodge": 0.0, "crew": [3, 4], "from": 2, "weight": 3, "reward": 55, "loot": [3, 5]},
	Net.ECLASS_CRUISER: {"name": "пиратский крейсер", "layouts": [5], "hull": 20, "strength": 4, "guns": [3, 4], "more_from": 7,
		"pool": [Weapons.HEAVY, Weapons.LASER, Weapons.ION_CANNON, Weapons.ROCKET, Weapons.EMP, Weapons.SIEGE],
		"shield": 1.0, "regen": 1.4, "slower": 1.7, "dodge": -0.1, "crew": [4, 6], "from": 4, "weight": 2, "reward": 80, "loot": [4, 6]},
}

# How it fights (the old pirate's ways are "расчётливый"):
#   name     what the crew calls it, once its temper is known
#   about    one line on what that means
#   flee     share of its hull left at which it charges its jump and runs (0 = it never runs)
#   at_guns  share of its shots that go for our guns while one works
#   devices  of the rest, the share that goes for a console or the shield generator (else the hull)
#   pace     how fast its guns charge against its class's own pace
const TEMPERS := {
	Net.TEMPER_CALCULATING: {"name": "расчётливый", "about": "бьёт по орудиям, бежит, когда корпус на трети",
		"flee": 1.0 / 3.0, "at_guns": 0.55, "devices": 0.4, "pace": 1.0},
	Net.TEMPER_CAUTIOUS: {"name": "осторожный", "about": "бережёт себя: бежит уже на половине корпуса, первым делом гасит наши орудия",
		"flee": 0.5, "at_guns": 0.7, "devices": 0.3, "pace": 1.0},
	Net.TEMPER_RECKLESS: {"name": "отчаянный", "about": "не бежит никогда, стреляет чаще и бьёт по обшивке, где люди",
		"flee": 0.0, "at_guns": 0.3, "devices": 0.2, "pace": 1.15},
	Net.TEMPER_HUNTER: {"name": "охотник", "about": "выбивает щит и пульты мостика, бежит на трети корпуса",
		"flee": 1.0 / 3.0, "at_guns": 0.35, "devices": 0.75, "pace": 1.0},
}

const NAMES: Array[String] = ["Чёрная вдова", "Ржавый клинок", "Кровавая Мэри", "Последний вздох", "Гиена", "Шакал",
	"Костолом", "Беззвёздная ночь", "Пустота", "Мародёр", "Стервятник", "Ворон", "Сломанный зуб", "Красный прилив",
	"Барракуда", "Тёмная звезда", "Могильщик", "Злая удача", "Хромой пёс", "Ночная гостья", "Рваная рана", "Буря",
	"Крюк", "Пиранья", "Чума", "Медный лоб", "Острога", "Голодный", "Вдовий плач", "Безымянный", "Падальщик", "Ржавчина"]


static func info(klass: int) -> Dictionary:
	return CLASSES.get(klass, CLASSES[Net.ECLASS_RAIDER])


static func temper(t: int) -> Dictionary:
	return TEMPERS.get(t, TEMPERS[Net.TEMPER_CALCULATING])


static func class_of_layout(layout: int) -> int:
	## The class whose hull that drawing is (a raider's if none says so).
	for k: int in CLASSES.keys():
		if (CLASSES[k]["layouts"] as Array).has(layout):
			return k
	return Net.ECLASS_RAIDER


static func class_name_of(klass: int) -> String:
	return str(info(klass)["name"])
