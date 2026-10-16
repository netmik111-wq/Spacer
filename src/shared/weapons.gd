extends RefCounted
## Ship weapons (v49, the author's request): what each kind of gun does, for
## our guns and the enemy's alike. The server (Gunnery) fights with these
## numbers and the client explains them on the gun console and at the trader.
##
## A gun mount ('T' in the map) holds one weapon or none. A weapon off its
## mount is a thing in the ship's cargo (the supply locker): Net.ITEM_GUN + its
## number. Every armed weapon draws power from the reactor (REACTOR); the
## shield generator draws SHIELD_POWER while it is on.
##
## Shields (the author's rule, not FTL's): a shield is a pool of 0..100 that
## refills by itself. A shot that meets it while it is at 50 or more is stopped
## and takes some of it away; below 50 a shot may get through, the more likely
## the lower it is (at 0, always). What meets the shield:
##   lasers and the beam: always;
##   the blaster: half its pellets slip through as if there were no shield;
##   rockets: never, unless the shield is hardened (a rare upgrade);
##   ion: always, and it only wears the shield down; what gets through puts the
##        system it lands on out for a few seconds instead of doing damage;
##   the tractor beam: always, like the cutter (stopped, it takes BEAM_SHIELD);
##   the siphon beam: it is not stopped, it feeds on the shield itself.

const Net := preload("res://src/shared/net.gd")

const NONE := 0
const LASER := 1
const HEAVY := 2                     # a heavy laser: double damage, slow, hungry for power
const SIEGE := 3                     # a siege laser: triple damage, slower and hungrier still
const RAPID := 4                     # a rapid-fire laser: six shots that mostly miss
const BEAM := 5                      # the cutting beam (see BEAM_* below)
const BLASTER := 6                   # a plasma blaster: a shotgun burst
const ROCKET := 7                    # a rocket launcher
const EMP := 8                       # an EMP launcher
const ION := 9                       # an ion gun
const ION_CANNON := 10               # an ion cannon
const TRACTOR := 11                  # (v50) the tractor beam: holds the enemy, no damage
const SIPHON := 12                   # (v50) the siphon beam: drains the enemy's shield into ours
const COUNT := 13

const CLASS_LASER := 0
const CLASS_BEAM := 1
const CLASS_BLASTER := 2
const CLASS_ROCKET := 3
const CLASS_ION := 4
const CLASS_TRACTOR := 5
const CLASS_SIPHON := 6

const REACTOR := 8                   # power the reactor gives the guns and the shield
const SHIELD_POWER := 2
const SHIELD_FULL := 100.0
const SHIELD_HOLDS := 50.0           # at this and above nothing that meets the shield gets through
const SHIELD_REGEN := 2.5            # points a second it refills (with the generator whole and powered)
const SHIELD_PER_DAMAGE := 25.0      # a shot the shield stops takes this much per point of its damage
const BLASTER_SLIP := 0.5            # share of blaster pellets that go through as if there were no shield
const ROCKET_HOLE := 0.5             # a rocket that gets through holes the hull this often
const BLIND_BONUS := 0.2             # our shots hit this much more often while the enemy's bridge is out
const BEST_HIT := 0.95
const SELL_SHARE := 0.5              # a trader buys things back at this share of their price

# The cutting beam ("Резак"): it never misses and burns the room it is aimed
# at for BEAM_PULSES seconds, a point of damage a second; the aim may be moved
# while it burns. Shields stop it outright while they hold, and each pulse
# stopped wears them only a little (BEAM_SHIELD), so it is the gun to finish a
# ship whose shield is down, not to bring the shield down.
const BEAM_PULSES := 4
const BEAM_PULSE_TICKS := Net.TICK_HZ
const BEAM_SHIELD := 10.0

# The tractor and siphon beams (v50, the author chose both of my other beam
# ideas). The tractor does no damage: it holds the enemy for TRACTOR_HOLD
# seconds, and while it holds the enemy cannot dodge (our shots hit
# TRACTOR_BONUS more often, up to BEST_HIT), cannot charge its jump to run and
# cannot close in to dock. The siphon burns SIPHON_PULSES seconds like the
# cutter, and each second takes SIPHON_DRAIN from the enemy's shield and puts it
# into ours (if our generator works); it does nothing to the hull.
const TRACTOR_HOLD := 8.0
const TRACTOR_BONUS := 0.25
const SIPHON_PULSES := 4
const SIPHON_DRAIN := 12.0

# name, short name, about, class, charge seconds, shots, hit chance, damage per hit,
# power, price, ammo (Net.ITEM_* or 0), shield it takes when stopped (ion: its whole effect),
# seconds a system is put out by what gets through (ion, EMP)
const INFO := {
	LASER: {"name": "Лазер", "short": "Лазер", "class": CLASS_LASER, "charge": 8.0, "shots": 1, "hit": 0.75, "damage": 1,
		"power": 1, "price": 30,
		"about": "Обычный лазер: выстрел раз в 8 с, 75% попаданий, 1 урона. Щит его останавливает."},
	HEAVY: {"name": "Тяжёлый лазер", "short": "Тяж. лазер", "class": CLASS_LASER, "charge": 14.0, "shots": 1, "hit": 0.7, "damage": 2,
		"power": 3, "price": 60,
		"about": "Двойной урон, но заряжается 14 с и берёт 3 энергии. Стоящий выстрел сбивает щит на 50."},
	SIEGE: {"name": "Осадный лазер", "short": "Осадный", "class": CLASS_LASER, "charge": 20.0, "shots": 1, "hit": 0.65, "damage": 3,
		"power": 4, "price": 90,
		"about": "Тройной урон, заряжается 20 с и берёт 4 энергии: половина всего реактора."},
	RAPID: {"name": "Скорострельный лазер", "short": "Скорострел", "class": CLASS_LASER, "charge": 12.0, "shots": 6, "hit": 0.35, "damage": 1,
		"power": 2, "price": 55,
		"about": "Шесть выстрелов очередью, но попадает лишь треть. Хорошо сбивает щит."},
	BEAM: {"name": "Резак", "short": "Резак", "class": CLASS_BEAM, "charge": 16.0, "shots": 1, "hit": 1.0, "damage": 1,
		"power": 2, "price": 70,
		"about": "Луч, который не промахивается: 4 с жжёт наведённый отсек, по 1 урона в секунду; наводку можно менять, пока он горит. Щит выше 50 его не пускает и почти не теряет: добивает корабль без щита."},
	BLASTER: {"name": "Плазменный бластер", "short": "Бластер", "class": CLASS_BLASTER, "charge": 11.0, "shots": 4, "hit": 0.55, "damage": 1,
		"power": 2, "price": 55,
		"about": "Залп плазмы дробью: 4 заряда, половина из них проходит сквозь щит, как будто его нет."},
	ROCKET: {"name": "Ракетная установка", "short": "Ракеты", "class": CLASS_ROCKET, "charge": 10.0, "shots": 1, "hit": 0.85, "damage": 2,
		"power": 1, "price": 50, "ammo": Net.ITEM_ROCKET,
		"about": "Ракета проходит сквозь щит (кроме закалённого): 2 урона корпусу и в половине случаев пробоина. Тратит ракеты из трюма."},
	EMP: {"name": "ЭМИ-установка", "short": "ЭМИ", "class": CLASS_ROCKET, "charge": 12.0, "shots": 1, "hit": 0.85, "damage": 0,
		"power": 1, "price": 60, "ammo": Net.ITEM_EMP_ROCKET, "disable": 6.0,
		"about": "ЭМИ-ракета проходит сквозь щит (кроме закалённого) и на 6 с выключает систему в отсеке, куда попала. Урона не наносит."},
	ION: {"name": "Ионная пушка", "short": "Ион. пушка", "class": CLASS_ION, "charge": 7.0, "shots": 1, "hit": 0.8, "damage": 0,
		"power": 1, "price": 40, "shield": 35.0, "disable": 3.0,
		"about": "Бьёт только по щиту: снимает 35. Если попала в корпус (щит пропустил), на 3 с выключает систему. Корпусу урона нет."},
	ION_CANNON: {"name": "Ионное орудие", "short": "Ион. орудие", "class": CLASS_ION, "charge": 13.0, "shots": 1, "hit": 0.75, "damage": 0,
		"power": 2, "price": 70, "shield": 70.0, "disable": 3.0,
		"about": "Ионное орудие: снимает со щита 70. Если попало в корпус, на 3 с выключает систему. Корпусу урона нет."},
	TRACTOR: {"name": "Захватный луч", "short": "Захват", "class": CLASS_TRACTOR, "charge": 15.0, "shots": 1, "hit": 1.0, "damage": 0,
		"power": 2, "price": 60,
		"about": "Луч без урона, не промахивается: держит корабль врага 8 с. Пока держит, враг не уклоняется (наши попадания +25%, до 95%), не заряжает прыжок, чтобы сбежать, и не подходит к шлюзу. Щит выше 50 его не пускает."},
	SIPHON: {"name": "Сифон", "short": "Сифон", "class": CLASS_SIPHON, "charge": 12.0, "shots": 1, "hit": 1.0, "damage": 0,
		"power": 2, "price": 65,
		"about": "Луч-насос: 4 с тянет щит врага, по 12 в секунду, и отдаёт взятое нашему щиту (если наш генератор работает). Корпусу урона нет; по кораблю без щита бесполезен."},
}

const SHIELD_HARDEN_PRICE := 80      # the rare upgrade: the shield stops rockets too
const HARDEN_CHANCE := 0.3           # share of traders who offer it
const TRADER_WEAPONS := 4            # kinds of ship weapon a trader has on offer
const ROCKET_PRICE := 4
const EMP_ROCKET_PRICE := 6


static func known(w: int) -> bool:
	return INFO.has(w)


static func info(w: int) -> Dictionary:
	return INFO.get(w, {})


static func name_of(w: int) -> String:
	return str(INFO[w]["name"]) if INFO.has(w) else "пусто"


static func short_of(w: int) -> String:
	return str(INFO[w]["short"]) if INFO.has(w) else "пусто"


static func power(w: int) -> int:
	return int(INFO[w]["power"]) if INFO.has(w) else 0


static func charge_ticks(w: int) -> int:
	return roundi(float(INFO[w]["charge"]) * Net.TICK_HZ) if INFO.has(w) else 1


static func flight_ticks(w: int) -> int:
	## (v56) How long a shot of this weapon takes from the muzzle to where it lands:
	## lasers are quickest, ion slower, rockets slowest. Beams have no flight.
	match klass(w):
		CLASS_LASER:
			return 12 if w == RAPID else (16 if w == SIEGE else 14)
		CLASS_BLASTER:
			return 14
		CLASS_ION:
			return 18
		CLASS_ROCKET:
			return 26
	return 0


const BURST_GAP_TICKS := 3           # (v56) between the shots of one burst


static func ammo(w: int) -> int:
	return int(INFO[w].get("ammo", 0)) if INFO.has(w) else 0


static func klass(w: int) -> int:
	return int(INFO[w]["class"]) if INFO.has(w) else -1


static func item_of(w: int) -> int:
	## The thing a weapon off its mount is, in the cargo. The rockets took the
	## numbers after the first ten, so the later weapons go on from Net.ITEM_GUN_MORE.
	return Net.ITEM_GUN + w if w < TRACTOR else Net.ITEM_GUN_MORE + w


static func of_item(item: int) -> int:
	## The weapon a thing in the cargo is, or NONE.
	var w := item - Net.ITEM_GUN
	if w > NONE and w < TRACTOR:
		return w
	w = item - Net.ITEM_GUN_MORE
	return w if w >= TRACTOR and INFO.has(w) else NONE


static func shield_damage(w: int) -> float:
	## How much of a shield a shot of this weapon takes when the shield stops it.
	if not INFO.has(w):
		return 0.0
	if INFO[w].has("shield"):
		return float(INFO[w]["shield"])
	if klass(w) == CLASS_BEAM or klass(w) == CLASS_TRACTOR:
		return BEAM_SHIELD
	return SHIELD_PER_DAMAGE * maxf(float(INFO[w]["damage"]), 1.0)


static func through_chance(level: float) -> float:
	## The chance a shot that meets a shield at this level gets through it (the author's rule).
	if level >= SHIELD_HOLDS:
		return 0.0
	return clampf((SHIELD_HOLDS - level) / SHIELD_HOLDS, 0.0, 1.0)


static func sell_price(price: int) -> int:
	return maxi(int(price * SELL_SHARE), 1) if price > 0 else 0
