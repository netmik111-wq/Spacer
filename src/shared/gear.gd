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
const MODULE_SLOTS_MAX := 3          # (v62, the author's K3) with the bay's extender, bought at a station

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
const JAMMER := 16                   # (v62, the author's K2: passive gear, no respirators) the jump jammer
const WELDER := 17                   # the welding drone: mends the hull after every jump
const SALVAGE := 18                  # the salvage arm: wrecks and captures pay more
const LOADER := 19                   # the auto-loader: guns with nobody at them charge faster
const BAY_SLOT := 20                 # (v62, K3) the bay's extender: a third slot, for good (sold only at stations)
const TELEPORT := 21                 # (v97, the author's 3.2: "the teleporter as a late tech") a rare find in derelicts' vaults
const COUNT := 22                    # every crate's number is below this (TELEPORT's thing is Net.ITEM_TELEPORTER)

const MOD_ARMOUR := 0                # the sorts of module: one of each sort may be in the bay
const MOD_FOCUS := 1
const MOD_PHASE := 2
const MOD_JAMMER := 3                # (v62)
const MOD_WELDER := 4
const MOD_SALVAGE := 5
const MOD_LOADER := 6
const MOD_EXTENDER := 7              # (v62) not a module that takes a slot: it adds one

# --- what each system does by its tier (index 1..3; 0 unused)
const REACTOR_POWER: Array[int] = [0, 8, 10, 12]
const SHIELD_REGEN: Array[float] = [0.0, 2.5, 3.5, 4.5]   # points a second (the top one also stops rockets)
const ENGINE_DODGE: Array[float] = [0.0, 0.0, 0.05, 0.10] # added to our dodge while somebody flies the ship
const ENGINE_JUMP: Array[float] = [0.0, 1.0, 0.75, 0.5]   # share of the jump's charge and the drive's rest
const JUMP_FUEL: Array[int] = [40, 40, 35, 30]             # (v67, the author's numbers) fuel a lane jump burns (the long jump twice)
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
# --- (v62) the passive modules
const JAMMER_SHARE := 0.5            # the enemy's escape jump charges at this share of its pace
const WELDER_HULL := 5               # hull strength mended after every jump
const SALVAGE_SHARE := 1.3           # wrecks and captures pay this much of their reward...
const SALVAGE_PARTS := 1             # ... and give this many spare parts more
const LOADER_PACE := 1.1             # a gun with no gunner charges this much faster
# --- (v97) the teleporter (his T1 C: a machine of its own, the pad 't'; my T2-T3 picks): it sends whoever stands
# by its pad to the ship alongside and back
const TELEPORT_SECONDS := 20.0       # its recharge
const TELEPORT_HUM := 2.0            # the hum before a beam
const TELEPORT_REACH := 4            # cells from the pad's front: who stands this close goes along (bots told «К оружию»)
const TELEPORT_PARTY := 3            # at most, the sender included
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
		"about": "Уклонение от выстрелов +5% (пока кто-то за штурвалом), прыжок заряжается на четверть быстрее и берёт 35 единиц топлива вместо 40."},
	ENGINE_3: {"name": "Двигатель «Сокол»", "sys": SYS_ENGINE, "tier": 3, "price": 180,
		"about": "Уклонение +10% (пока кто-то за штурвалом), прыжок заряжается вдвое быстрее и берёт 30 единиц топлива вместо 40."},
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
	JAMMER: {"name": "Глушитель прыжка", "mod": MOD_JAMMER, "tier": 2, "price": 110,
		"about": "Модуль. Гипердвигатель врага заряжается вдвое медленнее: побитому пирату труднее сбежать."},
	WELDER: {"name": "Сварочный дрон", "mod": MOD_WELDER, "tier": 2, "price": 120,
		"about": "Модуль. После каждого прыжка дрон заваривает обшивку снаружи: прочность корпуса +5."},
	SALVAGE: {"name": "Сборщик", "mod": MOD_SALVAGE, "tier": 2, "price": 100,
		"about": "Модуль. Манипулятор разбирает обломки: за разбитый или захваченный корабль на 30% больше кредитов и ещё одна запчасть."},
	LOADER: {"name": "Автозарядчик", "mod": MOD_LOADER, "tier": 2, "price": 100,
		"about": "Модуль. Орудия, у которых никто не стоит, заряжаются на 10% быстрее."},
	BAY_SLOT: {"name": "Расширитель стойки", "mod": MOD_EXTENDER, "tier": 0, "price": 150,
		"about": "Третья ячейка модульной стойки, навсегда. Продаётся только на станциях. Ставится в модульную стойку, ячейку не занимает."},
	TELEPORT: {"name": "Телепорт «Шаг»", "pad": true, "tier": 0, "price": 400,
		"about": "Редкая находка из хранилищ брошенных кораблей. E у платформы телепорта: через 2 с вы и до двух ботов «К оружию» рядом с ней оказываетесь на корабле у нашего борта. Назад: правая кнопка мыши по себе там. Перезарядка 20 с, нужна энергия."},
}
const WHERE_ABOUT: Array[String] = ["Ставится у генератора щита.", "Ставится у двигателя.", "Ставится у двигателя.",
	"Ставится у голокарты.", "Ставится в СМЭС в машинном отделении."]
const BAY_ABOUT := "Ставится в модульную стойку в машинном отделении."
const PAD_ABOUT := "Ставится в платформу телепорта («t» в редакторе кораблей)."


static func of_item(item: int) -> int:
	## The crate that thing is, or NONE.
	if item == Net.ITEM_TELEPORTER:
		return TELEPORT
	var g := item - Net.ITEM_GEAR
	return g if g > NONE and g < TELEPORT else NONE


static func item_of(g: int) -> int:
	return Net.ITEM_TELEPORTER if g == TELEPORT else Net.ITEM_GEAR + g   # (v97: the things after 190 were taken)


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
	var where := WHERE_ABOUT[system_of(g)] if system_of(g) >= 0 else (PAD_ABOUT if g == TELEPORT else BAY_ABOUT)
	return "%s %s Ставит инженер (держать E)." % [str(INFO[g]["about"]), where]


static func armour_tier(modules: PackedByteArray) -> int:
	for g in modules:
		if module_of(g) == MOD_ARMOUR:
			return tier(g)
	return 0


static func extender(g: int) -> bool:
	## (v62) Is it the bay's extender (it adds a slot, it does not take one)?
	return module_of(g) == MOD_EXTENDER


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
