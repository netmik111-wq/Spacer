extends RefCounted
## (v59, the author's tiers plan, part 2) Ship gear: modules in crates that an
## engineer carries to their machine and installs. The server (Outfit) works
## them and the client explains them in the locker, at the trader and on the
## holomap.
##
## Gear is of two sorts (the author's answer G2: "both"):
##   systems  the ship's own machines, each with a tier: the shield generator,
##            the reactor, the engine and the sensors. Tier 1 is what the ship
##            sets out with (built in, no crate); a crate of tier 2 or 3 is
##            installed at its machine (the reactor and the engine both at the
##            engine, the sensors at a holomap) and the one it replaces comes out
##            as a crate, unless it was the built-in one.
##   modules  armour plating, the focusing array, the phase drive: they go in one
##            of the MODULE_SLOTS free slots of the module bay ('U' in the map).
## A tier is hidden, as with guns: every crate has its own name, and its card
## tells what it does in numbers. Prices are x1 / x2.5 / x5 by tier (the
## author's T8); tiers come by distance like the guns' (Weapons.tiers_for).
## A crate is a plain thing (Net.ITEM_GEAR + its number here): carried in a
## hand, kept in the supply locker, sold and bought; it is not cargo.

const Net := preload("res://src/shared/net.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const SYS_SHIELD := 0
const SYS_REACTOR := 1
const SYS_ENGINE := 2
const SYS_SENSORS := 3
const SYS_COILS := 4                 # (v61, the author's P8) the SMES's storage coils
const SYSTEMS := 5
const SYS_NAMES: Array[String] = ["Генератор щита", "Реактор", "Двигатель", "Сканеры", "Катушки СМЭС"]
const SYS_BUILT_IN: Array[String] = ["штатный генератор щита", "штатный реактор", "штатный двигатель", "штатные сканеры",
	"штатные катушки СМЭС"]
const MODULE_SLOTS := 2              # free slots in the module bay

const NONE := 0
const SHIELD_2 := 1
const SHIELD_3 := 2
const REACTOR_2 := 3
const REACTOR_3 := 4
const ENGINE_2 := 5
const ENGINE_3 := 6
const SENSORS_2 := 7
const SENSORS_3 := 8
const ARMOUR_1 := 9
const ARMOUR_2 := 10
const ARMOUR_3 := 11
const FOCUS := 12
const PHASE := 13
const COILS_2 := 14                  # (v61)
const COILS_3 := 15
const COUNT := 16                    # every crate's number is below this

const MOD_ARMOUR := 0                # the sorts of module: one of each sort may be in the bay
const MOD_FOCUS := 1
const MOD_PHASE := 2

# --- what each system does by its tier (index 1..3; 0 unused)
const REACTOR_POWER: Array[int] = [0, 8, 10, 12]
const SHIELD_REGEN: Array[float] = [0.0, 2.5, 3.5, 4.5]   # points a second (the top one also stops rockets)
const ENGINE_DODGE: Array[float] = [0.0, 0.0, 0.05, 0.10] # added to our dodge while somebody flies the ship
const ENGINE_JUMP: Array[float] = [0.0, 1.0, 0.75, 0.5]   # share of the jump's charge and the drive's rest
const ENGINE_FREE_FUEL: Array[float] = [0.0, 0.0, 0.25, 0.5]   # chance a jump burns no fuel
const SENSOR_SECONDS: Array[float] = [0.0, 7.0, 4.0, 2.5]      # our sensors make out one of its rooms this often
const COIL_CAPACITY: Array[float] = [0.0, 1.0, 1.5, 2.0]      # (v61) the SMES holds this many times its built-in charge
const COIL_CHARGE: Array[int] = [0, 0, 2, 4]                  # and charges this much faster a second
# --- armour plating by its tier
const ARMOUR_RICOCHET: Array[float] = [0.0, 0.1, 0.2, 0.3]   # share of kinetic shells turned aside
const ARMOUR_HULL: Array[float] = [1.0, 0.85, 0.7, 0.55]     # share of the hull's strength a hit still takes
const ARMOUR_NO_HOLE: Array[float] = [0.0, 0.15, 0.3, 0.45]  # chance a hit that would hole the hull does not
# --- the focusing array (the author's mirror note): lasers fired in one volley at
# one room join into one stronger beam: for each laser past the first the shield
# counts this much weaker for all of them
const FOCUS_PIERCE := 45.0
# --- the phase drive (the author's G15/R7): the battle position changes at once,
# "behind them" opens, then it recharges this long; it needs no fuel
const PHASE_SECONDS := 60.0
const INSTALL_SECONDS := 10.0        # an engineer installs a crate (skill: up to twice as quick)
const REMOVE_SECONDS := 5.0          # and takes a module out of the bay

# name, about, system (SYS_*) or module (MOD_*), tier, price
const INFO := {
	SHIELD_2: {"name": "Генератор щита «Бастион»", "sys": SYS_SHIELD, "tier": 2, "price": 100,
		"about": "Щит восстанавливается быстрее: 3,5 в секунду вместо 2,5."},
	SHIELD_3: {"name": "Генератор щита «Эгида»", "sys": SYS_SHIELD, "tier": 3, "price": 200,
		"about": "Щит восстанавливается по 4,5 в секунду и останавливает ракеты и ЭМИ-ракеты, как лазеры."},
	REACTOR_2: {"name": "Реактор «Факел»", "sys": SYS_REACTOR, "tier": 2, "price": 120,
		"about": "Даёт орудиям и щиту 10 энергии вместо 8."},
	REACTOR_3: {"name": "Реактор «Солнце»", "sys": SYS_REACTOR, "tier": 3, "price": 240,
		"about": "Даёт орудиям и щиту 12 энергии вместо 8."},
	ENGINE_2: {"name": "Двигатель «Стриж»", "sys": SYS_ENGINE, "tier": 2, "price": 90,
		"about": "Уклонение от выстрелов +5% (пока кто-то за штурвалом), прыжок заряжается на четверть быстрее, каждый четвёртый прыжок в среднем без топлива."},
	ENGINE_3: {"name": "Двигатель «Сокол»", "sys": SYS_ENGINE, "tier": 3, "price": 180,
		"about": "Уклонение +10% (пока кто-то за штурвалом), прыжок заряжается вдвое быстрее, половина прыжков в среднем без топлива."},
	SENSORS_2: {"name": "Сканеры «Око»", "sys": SYS_SENSORS, "tier": 2, "price": 60,
		"about": "Отсеки пиратского корабля распознаются раз в 4 с вместо 7."},
	SENSORS_3: {"name": "Сканеры «Всевидящее око»", "sys": SYS_SENSORS, "tier": 3, "price": 120,
		"about": "Отсеки распознаются раз в 2,5 с, а на пульте орудий видно, как заряжаются орудия пиратов."},
	COILS_2: {"name": "Катушки «Ёмкость»", "sys": SYS_COILS, "tier": 2, "price": 80,
		"about": "СМЭС держит в полтора раза больше заряда (4,5 минуты всего корабля вместо 3) и заряжается на 2 в секунду быстрее."},
	COILS_3: {"name": "Катушки «Сверхпровод»", "sys": SYS_COILS, "tier": 3, "price": 160,
		"about": "СМЭС держит вдвое больше заряда (6 минут всего корабля вместо 3) и заряжается на 4 в секунду быстрее."},
	ARMOUR_1: {"name": "Броня «Стальные листы»", "mod": MOD_ARMOUR, "tier": 1, "price": 50,
		"about": "Модуль. Попадание снимает с корпуса на 15% меньше, 15% пробоин не случается, 10% кинетических снарядов уходят рикошетом."},
	ARMOUR_2: {"name": "Броня «Композит»", "mod": MOD_ARMOUR, "tier": 2, "price": 125,
		"about": "Модуль. Попадание снимает с корпуса на 30% меньше, 30% пробоин не случается, 20% кинетических снарядов уходят рикошетом."},
	ARMOUR_3: {"name": "Броня «Керамит»", "mod": MOD_ARMOUR, "tier": 3, "price": 250,
		"about": "Модуль. Попадание снимает с корпуса на 45% меньше, 45% пробоин не случается, 30% кинетических снарядов уходят рикошетом."},
	FOCUS: {"name": "Фокусирующая решётка", "mod": MOD_FOCUS, "tier": 2, "price": 120,
		"about": "Модуль. Лазеры, выпущенные одним залпом в один отсек, сводятся в общий луч: щит для них слабее на 45 за каждый лазер сверх первого."},
	PHASE: {"name": "Фазовый привод", "mod": MOD_PHASE, "tier": 2, "price": 150,
		"about": "Модуль. Позиция в бою меняется мгновенно, и открывается позиция «В тыл» (мы попадаем на 25% лучше, они на 20% хуже). Потом привод 60 с перезаряжается. Топлива не берёт."},
}
const WHERE_ABOUT: Array[String] = ["Ставится у генератора щита.", "Ставится у двигателя.", "Ставится у двигателя.",
	"Ставится у голокарты.", "Ставится в СМЭС в машинном отделении."]
const BAY_ABOUT := "Ставится в модульную стойку в машинном отделении."


static func of_item(item: int) -> int:
	## The crate that thing is, or NONE.
	var g := item - Net.ITEM_GEAR
	return g if g > NONE and g < COUNT else NONE


static func item_of(g: int) -> int:
	return Net.ITEM_GEAR + g


static func info(g: int) -> Dictionary:
	return INFO.get(g, {})


static func name_of(g: int) -> String:
	return str(INFO[g]["name"]) if INFO.has(g) else ""


static func tier(g: int) -> int:
	return int(INFO[g]["tier"]) if INFO.has(g) else 0


static func price(g: int) -> int:
	return int(INFO[g]["price"]) if INFO.has(g) else 0


static func system_of(g: int) -> int:
	## The system it is a tier of (SYS_*), or -1 for a module.
	return int(INFO[g].get("sys", -1)) if INFO.has(g) else -1


static func module_of(g: int) -> int:
	## The sort of module it is (MOD_*), or -1 for a system's crate.
	return int(INFO[g].get("mod", -1)) if INFO.has(g) else -1


static func for_system(sys: int, t: int) -> int:
	## The crate of that system at that tier (NONE for tier 1: built in).
	for g: int in INFO.keys():
		if system_of(g) == sys and tier(g) == t:
			return g
	return NONE


static func about(g: int) -> String:
	if not INFO.has(g):
		return ""
	var where := WHERE_ABOUT[system_of(g)] if system_of(g) >= 0 else BAY_ABOUT
	return "%s %s Ставит инженер (держать E)." % [str(INFO[g]["about"]), where]


static func armour_tier(modules: PackedByteArray) -> int:
	for g in modules:
		if module_of(g) == MOD_ARMOUR:
			return tier(g)
	return 0


static func has_module(modules: PackedByteArray, which: int) -> bool:
	for g in modules:
		if module_of(g) == which:
			return true
	return false


static func all() -> Array:
	var out: Array = INFO.keys()
	out.sort()
	return out


static func of_tier(t: int) -> Array:
	## The crates found or sold at that tier.
	return all().filter(func(g: int) -> bool: return tier(g) == t)


static func roll(far: int, rng: RandomNumberGenerator, higher: bool = false) -> int:
	## A crate found or sold this far out: its tier as a gun's would be there
	## (one tier higher if `higher`, up to 3).
	var t := Weapons.tiers_for(far, 1, rng)[0]
	if higher:
		t = mini(t + 1, 3)
	var choice := of_tier(t)
	return choice[rng.randi_range(0, choice.size() - 1)]
