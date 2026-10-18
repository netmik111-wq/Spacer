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
##   the siphon beam: it is not stopped, it feeds on the shield itself;
##   (v58) kinetic shells: the shield never stops them, it takes KINETIC_SHIELD off
##        each one's damage instead (and wears by KINETIC_WEAR); the railgun and
##        the flagship's gun pass any shield. A ship with armour turns kinetic
##        shells aside now and then (a ricochet).

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
const PHOENIX := 13                  # (v58) «Феникс»: the top laser, two heavy bolts
const STORM := 14                    # (v58) «Буря»: the top ion gun, two charges that put systems out long
const DEVASTATOR := 15               # (v58) «Опустошитель»: the top launcher, a heavy rocket that always holes
const REAPER := 16                   # (v58) «Жнец»: the top beam, burns longer and wears the shield harder
const AUTOCANNON := 17               # (v58) a kinetic autocannon: three shells from the cargo
const RAILGUN := 18                  # (v58) a kinetic railgun: passes the shield, pierces a second room
const HAMMER := 19                   # (v58) «Молот»: the top kinetic gun, a heavy shell
const NEURAL := 20                   # (v57) the boarding flagship's neural emitter: stuns the crew in the room, no damage
const GUARD := 21                    # (v58) «Заслон»: point defence in its own mount, shoots down rockets and drones
const NOVA := 22                     # (v58) «Сверхновая»: the flagship's own gun, found nowhere else
const HORNET := 23                   # (v62) «Шершень»: a bomb teleported into a room: wears its system, wounds whoever is there
const DAMPER := 24                   # (v62) «Глушилка»: an ion bomb: puts the system out and stuns the room
const THERMITE := 25                 # (v62) «Термит»: the top bomb: burns the system through, holes the hull, kills one
const SHRAPNEL := 26                 # (v62) «Шрапнель»: kinetic fragments over the room aimed at and those beside it
const COUNT := 27                    # every weapon's number is below this

const CLASS_LASER := 0
const CLASS_BEAM := 1
const CLASS_BLASTER := 2
const CLASS_ROCKET := 3
const CLASS_ION := 4
const CLASS_TRACTOR := 5
const CLASS_SIPHON := 6
const CLASS_NEURAL := 7
const CLASS_KINETIC := 8             # (v58) the shield takes KINETIC_SHIELD off its damage, the rest goes through; armour may turn it
const CLASS_GUARD := 9               # (v58) point defence: it never fires at the enemy
const CLASS_BOMB := 10               # (v62) a bomb: teleported straight into the room, past any shield and point
                                     # defence; it does not hurt the hull (but «Термит»), only what is in the room

# (v58, the author's tiers) A tier is a hidden rating of how strong a gun is:
# 1, 2 or 3. It is never shown: players learn guns by their names, looks and
# sounds. Every kind of gun has something in each tier, and the parts a gun is
# taken apart into are of its kind (KIND_*): it is upgraded with parts of the
# same kind into the gun named in its "next". A tier 3 gun found or made has an
# effect rolled for it (FX_*), shown on its card, and costs one more power than
# the tier below.
const KIND_LASER := 0
const KIND_ION := 1
const KIND_MISSILE := 2
const KIND_BEAM := 3
const KIND_KINETIC := 4
const KINDS := 5
const KIND_NAMES: Array[String] = ["лазерные", "ионные", "ракетные", "лучевые", "кинетические"]
const UPGRADE_PARTS: Array[int] = [0, 2, 4]   # parts of its kind to take a gun of tier 1 (2) to the next
const PRICE_SHARE: Array[float] = [1.0, 2.5, 5.0]   # (the author's numbers; what each gun asks is in INFO)

const FX_NONE := 0
const FX_PIERCE := 1                 # the shield it meets counts as FX_PIERCE_BY lower
const FX_STUN := 2                   # whoever is in the room hit is struck down (theirs wounded, ours stunned)
const FX_TWICE := 3                  # a volley fires again now and then (FX_TWICE_CHANCE)
const FX_KNOCK := 4                  # the system in the room hit goes out for FX_KNOCK_SECONDS
const FX_HOLE := 5                   # every hit holes the hull, and one more hole beside it
const FX_COUNT := 5
const FX_NAMES: Array[String] = ["", "пробивной", "оглушающий", "сдвоенный", "сбивающий", "рвущий"]
const FX_ABOUT: Array[String] = ["",
	"щит, который встречает его выстрел, для него слабее на 30",
	"попадание оглушает всех в отсеке (у пиратов ранит)",
	"иногда (каждый третий раз) даёт второй залп сразу за первым",
	"система в отсеке, куда попал, выключается на 2 с",
	"каждое попадание пробивает обшивку дважды"]
const FX_PIERCE_BY := 30.0
const FX_TWICE_CHANCE := 0.33
const FX_KNOCK_SECONDS := 2.0
const FX_STUN_HEALTH := 30.0
# the tier 3 guns that may carry an effect, in the order their things are numbered (item_of)
const FX_GUNS: Array[int] = [SIEGE, PHOENIX, STORM, DEVASTATOR, REAPER, HAMMER, NOVA, THERMITE]

# the kinetic guns (v58, the author's notebook): the shield takes this much off
# each shell's damage and wears by KINETIC_WEAR; armour on the ship hit turns a
# shell aside now and then (a ricochet: it does nothing)
const KINETIC_SHIELD := 1
const KINETIC_WEAR := 15.0
# point defence: charged, it shoots down one rocket coming at its ship (or a
# drone flying in) with this chance, then charges again
const GUARD_CHARGE := 5.0
const GUARD_HIT := 0.6
const GUARD_SHELL_HIT := 0.3         # (v60, the author's W3) and a slow shell (autocannon, «Молот») with this chance

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
# seconds a system is put out by what gets through (ion, EMP); (v58) tier, kind (KIND_*),
# next (the gun it is upgraded into), hole (the share of its hits that hole the hull: 1 if
# not said), no_shield (it passes any shield), pierce (rooms past the first that it hits too),
# pulses (a beam's seconds), unique (only the flagship carries it; never sold)
const INFO := {
	LASER: {"name": "Лазер", "short": "Лазер", "class": CLASS_LASER, "charge": 8.0, "shots": 1, "hit": 0.75, "damage": 1,
		"power": 1, "price": 30, "tier": 1, "kind": KIND_LASER, "next": HEAVY,
		"about": "Обычный лазер: выстрел раз в 8 с, 75% попаданий, 1 урона. Щит его останавливает."},
	RAPID: {"name": "Скорострельный лазер", "short": "Скорострел", "class": CLASS_LASER, "charge": 12.0, "shots": 6, "hit": 0.35, "damage": 1,
		"power": 2, "price": 40, "tier": 1, "kind": KIND_LASER, "next": BLASTER,
		"about": "Шесть выстрелов очередью, но попадает лишь треть. Хорошо сбивает щит."},
	HEAVY: {"name": "Тяжёлый лазер", "short": "Тяж. лазер", "class": CLASS_LASER, "charge": 14.0, "shots": 1, "hit": 0.7, "damage": 2,
		"power": 3, "price": 75, "tier": 2, "kind": KIND_LASER, "next": SIEGE,
		"about": "Двойной урон, но заряжается 14 с и берёт 3 энергии. Стоящий выстрел сбивает щит на 50."},
	BLASTER: {"name": "Плазменный бластер", "short": "Бластер", "class": CLASS_BLASTER, "charge": 11.0, "shots": 4, "hit": 0.55, "damage": 1,
		"power": 2, "price": 80, "tier": 2, "kind": KIND_LASER, "next": PHOENIX,
		"about": "Залп плазмы дробью: 4 заряда, половина из них проходит сквозь щит, как будто его нет."},
	SIEGE: {"name": "Осадный лазер", "short": "Осадный", "class": CLASS_LASER, "charge": 20.0, "shots": 1, "hit": 0.65, "damage": 3,
		"power": 4, "price": 150, "tier": 3, "kind": KIND_LASER,
		"about": "Тройной урон, заряжается 20 с и берёт 4 энергии: половина всего реактора."},
	PHOENIX: {"name": "Феникс", "short": "Феникс", "class": CLASS_LASER, "charge": 17.0, "shots": 2, "hit": 0.7, "damage": 2,
		"power": 4, "price": 170, "tier": 3, "kind": KIND_LASER,
		"about": "Два тяжёлых огненных заряда подряд, по 2 урона. Заряжается 17 с, берёт 4 энергии."},
	ION: {"name": "Ионная пушка", "short": "Ион. пушка", "class": CLASS_ION, "charge": 7.0, "shots": 1, "hit": 0.8, "damage": 0,
		"power": 1, "price": 35, "shield": 35.0, "disable": 3.0, "tier": 1, "kind": KIND_ION, "next": ION_CANNON,
		"about": "Бьёт только по щиту: снимает 35. Если попала в корпус (щит пропустил), на 3 с выключает систему. Корпусу урона нет."},
	ION_CANNON: {"name": "Ионное орудие", "short": "Ион. орудие", "class": CLASS_ION, "charge": 13.0, "shots": 1, "hit": 0.75, "damage": 0,
		"power": 2, "price": 90, "shield": 70.0, "disable": 3.0, "tier": 2, "kind": KIND_ION, "next": STORM,
		"about": "Ионное орудие: снимает со щита 70. Если попало в корпус, на 3 с выключает систему. Корпусу урона нет."},
	STORM: {"name": "Буря", "short": "Буря", "class": CLASS_ION, "charge": 14.0, "shots": 2, "hit": 0.75, "damage": 0,
		"power": 3, "price": 160, "shield": 50.0, "disable": 6.0, "tier": 3, "kind": KIND_ION,
		"about": "Два ионных разряда: каждый снимает со щита 50, а прошедший в корпус выключает систему на 6 с. Корпусу урона нет."},
	ROCKET: {"name": "Ракетная установка", "short": "Ракеты", "class": CLASS_ROCKET, "charge": 10.0, "shots": 1, "hit": 0.85, "damage": 2,
		"power": 1, "price": 40, "ammo": Net.ITEM_ROCKET, "hole": 0.5, "tier": 1, "kind": KIND_MISSILE, "next": EMP,
		"about": "Ракета проходит сквозь щит (кроме закалённого): 2 урона корпусу и в половине случаев пробоина. Тратит ракеты из трюма. Её может сбить «Заслон»."},
	EMP: {"name": "ЭМИ-установка", "short": "ЭМИ", "class": CLASS_ROCKET, "charge": 12.0, "shots": 1, "hit": 0.85, "damage": 0,
		"power": 1, "price": 85, "ammo": Net.ITEM_EMP_ROCKET, "disable": 6.0, "tier": 2, "kind": KIND_MISSILE, "next": DEVASTATOR,
		"about": "ЭМИ-ракета проходит сквозь щит (кроме закалённого) и на 6 с выключает систему в отсеке, куда попала. Урона не наносит."},
	DEVASTATOR: {"name": "Опустошитель", "short": "Опустош.", "class": CLASS_ROCKET, "charge": 16.0, "shots": 1, "hit": 0.85, "damage": 4,
		"power": 2, "price": 170, "ammo": Net.ITEM_ROCKET, "tier": 3, "kind": KIND_MISSILE,
		"about": "Тяжёлая ракета: проходит сквозь щит (кроме закалённого), 4 урона и всегда пробоина. Тратит ракеты из трюма."},
	TRACTOR: {"name": "Захватный луч", "short": "Захват", "class": CLASS_TRACTOR, "charge": 15.0, "shots": 1, "hit": 1.0, "damage": 0,
		"power": 2, "price": 45, "tier": 1, "kind": KIND_BEAM, "next": BEAM,
		"about": "Луч без урона, не промахивается: держит корабль врага 8 с. Пока держит, враг не уклоняется (наши попадания +25%, до 95%), не заряжает прыжок, чтобы сбежать, и не подходит к шлюзу. Щит выше 50 его не пускает."},
	SIPHON: {"name": "Сифон", "short": "Сифон", "class": CLASS_SIPHON, "charge": 12.0, "shots": 1, "hit": 1.0, "damage": 0,
		"power": 2, "price": 45, "tier": 1, "kind": KIND_BEAM, "next": BEAM,
		"about": "Луч-насос: 4 с тянет щит врага, по 12 в секунду, и отдаёт взятое нашему щиту (если наш генератор работает). Корпусу урона нет; по кораблю без щита бесполезен."},
	BEAM: {"name": "Резак", "short": "Резак", "class": CLASS_BEAM, "charge": 16.0, "shots": 1, "hit": 1.0, "damage": 1,
		"power": 2, "price": 95, "tier": 2, "kind": KIND_BEAM, "next": REAPER,
		"about": "Луч, который не промахивается: 4 с жжёт наведённый отсек, по 1 урона в секунду; наводку можно менять, пока он горит. Щит выше 50 его не пускает и почти не теряет: добивает корабль без щита."},
	REAPER: {"name": "Жнец", "short": "Жнец", "class": CLASS_BEAM, "charge": 18.0, "shots": 1, "hit": 1.0, "damage": 1,
		"power": 3, "price": 180, "pulses": 6, "shield": 25.0, "tier": 3, "kind": KIND_BEAM,
		"about": "Багровый луч: 6 с жжёт наведённый отсек, по 1 урона в секунду. Щит выше 50 его не пускает, но каждая остановленная секунда снимает с него 25."},
	AUTOCANNON: {"name": "Автопушка", "short": "Автопушка", "class": CLASS_KINETIC, "charge": 9.0, "shots": 3, "hit": 0.6, "damage": 1,
		"power": 1, "price": 35, "ammo": Net.ITEM_SHELL, "tier": 1, "kind": KIND_KINETIC, "next": RAILGUN,
		"about": "Очередь из 3 снарядов по 1 урона, каждый пробивает обшивку. Щит снимает с каждого 1 урона и теряет 15: по щиту она только изнашивает его. От брони снаряды бывают рикошетом. Тратит снаряды из трюма."},
	RAILGUN: {"name": "Рельсотрон", "short": "Рельса", "class": CLASS_KINETIC, "charge": 18.0, "shots": 1, "hit": 0.7, "damage": 3,
		"power": 3, "price": 110, "no_shield": true, "pierce": 1, "tier": 2, "kind": KIND_KINETIC, "next": HAMMER,
		"about": "Медленный выстрел болванкой: 3 урона, проходит сквозь любой щит и пробивает навылет ещё один отсек. От брони бывает рикошет. Снарядов не тратит."},
	HAMMER: {"name": "Молот", "short": "Молот", "class": CLASS_KINETIC, "charge": 16.0, "shots": 1, "hit": 0.7, "damage": 4,
		"power": 4, "price": 175, "ammo": Net.ITEM_SHELL, "tier": 3, "kind": KIND_KINETIC,
		"about": "Тяжёлый снаряд: 4 урона и пробоина. Щит снимает с него только 1 урона. От брони бывает рикошет. Тратит снаряд из трюма."},
	GUARD: {"name": "Заслон", "short": "Заслон", "class": CLASS_GUARD, "charge": GUARD_CHARGE, "shots": 1, "hit": GUARD_HIT, "damage": 0,
		"power": 1, "price": 50, "tier": 1, "kind": KIND_KINETIC,
		"about": "Точечная оборона в своём гнезде (не занимает орудие): заряженный, сбивает летящую в нас ракету или влетающий дрон в 60% случаев, потом 5 с заряжается. По кораблю врага не стреляет."},
	NOVA: {"name": "Сверхновая", "short": "Сверхновая", "class": CLASS_LASER, "charge": 25.0, "shots": 1, "hit": 0.9, "damage": 6,
		"power": 4, "price": 400, "no_shield": true, "pierce": 1, "tier": 3, "kind": KIND_LASER, "unique": true,
		"about": "Орудие флагмана, второго такого нет: сгусток света в 6 урона проходит сквозь любой щит и прожигает навылет ещё один отсек. Заряжается 25 с."},
	# (v62) bombs (the author's K1: a few tier 2 and 3 guns) and an area gun (W2: crew damage and an area only on a
	# few new guns). A bomb's "hull" is what it takes from the hull (most take nothing); "crew" is the chance that
	# each one in the room hit is wounded; "kill" kills one of them; "area" spreads a gun's shots over the room
	# aimed at and those beside it
	HORNET: {"name": "Бомбомёт «Шершень»", "short": "Шершень", "class": CLASS_BOMB, "charge": 13.0, "shots": 1, "hit": 0.9, "damage": 2,
		"power": 1, "price": 85, "ammo": Net.ITEM_ROCKET, "hull": 0, "crew": 1.0, "no_shield": true, "tier": 2, "kind": KIND_MISSILE, "next": THERMITE,
		"about": "Бомба телепортируется прямо в наведённый отсек: щит и «Заслон» её не останавливают, 90% доходят. 2 урона системе в отсеке и ранит всех, кто там стоит. Корпусу урона нет. Тратит ракету."},
	DAMPER: {"name": "Ионная бомба «Глушилка»", "short": "Глушилка", "class": CLASS_BOMB, "charge": 12.0, "shots": 1, "hit": 0.9, "damage": 0,
		"power": 1, "price": 80, "ammo": Net.ITEM_ROCKET, "hull": 0, "disable": 8.0, "stun": 30.0, "no_shield": true, "tier": 2, "kind": KIND_MISSILE, "next": THERMITE,
		"about": "Ионная бомба телепортируется в наведённый отсек мимо щита: выключает систему там на 8 с и оглушает всех в отсеке. Урона не наносит. Тратит ракету."},
	THERMITE: {"name": "Бомба «Термит»", "short": "Термит", "class": CLASS_BOMB, "charge": 16.0, "shots": 1, "hit": 0.9, "damage": 3,
		"power": 2, "price": 175, "ammo": Net.ITEM_ROCKET, "hull": 1, "crew": 1.0, "kill": true, "no_shield": true, "tier": 3, "kind": KIND_MISSILE,
		"about": "Зажигательная бомба телепортируется в наведённый отсек мимо щита: 3 урона системе, 1 корпусу и пробоина; одного из тех, кто в отсеке, убивает, остальных ранит. Тратит ракету."},
	SHRAPNEL: {"name": "Шрапнель", "short": "Шрапнель", "class": CLASS_KINETIC, "charge": 12.0, "shots": 4, "hit": 0.7, "damage": 1,
		"power": 2, "price": 90, "ammo": Net.ITEM_SHELL, "crew": 1.0, "area": true, "tier": 2, "kind": KIND_KINETIC, "next": HAMMER,
		"about": "Снаряд рвётся облаком осколков: 4 осколка ложатся в наведённый отсек и в соседние с ним, по 1 урона, и ранят всех, кого заденут. Щит снимает с осколка 1 урона, от брони бывает рикошет. Тратит один снаряд на залп."},
	# (v57) the flagship's only: never sold, never ours. "stun" is the health it takes from each one in the room hit
	NEURAL: {"name": "Нейроизлучатель", "short": "Нейро", "class": CLASS_NEURAL, "charge": 9.0, "shots": 1, "hit": 0.8, "damage": 0,
		"power": 2, "price": 0, "stun": 40.0, "tier": 2, "kind": KIND_ION,
		"about": "Оружие флагмана: заряд проходит сквозь обшивку и оглушает всех в отсеке, куда попал (корпус цел). Щит его останавливает."},
}

# (v58) What pirates may carry, by tier: every gun but the beams (theirs have no beam
# gear), the point defence (a mount of its own) and the flagship's own two.
const PIRATE_GUNS: Array = [[], [LASER, RAPID, ION, ROCKET, AUTOCANNON], [HEAVY, BLASTER, ION_CANNON, EMP, RAILGUN, HORNET, DAMPER, SHRAPNEL],
	[SIEGE, PHOENIX, STORM, DEVASTATOR, HAMMER, THERMITE]]
# the ship weapons a crew may own, in the order the cargo shows them
const OURS: Array[int] = [LASER, RAPID, HEAVY, BLASTER, SIEGE, PHOENIX, ION, ION_CANNON, STORM, ROCKET, EMP, DEVASTATOR,
	HORNET, DAMPER, THERMITE, TRACTOR, SIPHON, BEAM, REAPER, AUTOCANNON, SHRAPNEL, RAILGUN, HAMMER, GUARD, NOVA]

const SHIELD_HARDEN_PRICE := 80      # the rare upgrade: the shield stops rockets too
const HARDEN_CHANCE := 0.3           # share of traders who offer it
const ROCKET_PRICE := 4
const EMP_ROCKET_PRICE := 6
const SHELL_PRICE := 3


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
	match w:
		RAPID:
			return 12
		SIEGE, PHOENIX:
			return 16
		NOVA:
			return 22
		RAILGUN:
			return 8                             # (v58) the quickest shot there is
		DEVASTATOR:
			return 30
	match klass(w):
		CLASS_LASER:
			return 14
		CLASS_BLASTER:
			return 14
		CLASS_ION:
			return 18
		CLASS_ROCKET:
			return 26
		CLASS_NEURAL:
			return 16
		CLASS_KINETIC:
			return 12
		CLASS_BOMB:
			return 12                            # (v62) the time its teleport takes to put it there
	return 0


const BURST_GAP_TICKS := 3           # (v56) between the shots of one burst


static func ammo(w: int) -> int:
	return int(INFO[w].get("ammo", 0)) if INFO.has(w) else 0


static func slow_shell(w: int) -> bool:
	## (v60) A gun whose shells fly slowly enough for point defence to shoot at them
	## (the autocannon and the «Молот»; the railgun's slug is too quick).
	return klass(w) == CLASS_KINETIC and ammo(w) == Net.ITEM_SHELL


static func guard_chance(w: int) -> float:
	## (v60) The chance point defence shoots down one shot of that gun (0 = it does not try).
	if klass(w) == CLASS_ROCKET:
		return GUARD_HIT
	return GUARD_SHELL_HIT if slow_shell(w) else 0.0


static func klass(w: int) -> int:
	return int(INFO[w]["class"]) if INFO.has(w) else -1


static func tier(w: int) -> int:
	## (v58) Its hidden rating, 1..3 (0: no weapon).
	return int(INFO[w]["tier"]) if INFO.has(w) else 0


static func kind(w: int) -> int:
	## (v58) The kind of parts it is made of (KIND_*), -1 for none.
	return int(INFO[w]["kind"]) if INFO.has(w) else -1


static func next_of(w: int) -> int:
	## (v58) The gun it is upgraded into at the workbench, or NONE (the top of its line).
	return int(INFO[w].get("next", NONE)) if INFO.has(w) else NONE


static func unique(w: int) -> bool:
	return INFO.has(w) and bool(INFO[w].get("unique", false))


static func pulses(w: int) -> int:
	## A beam's seconds of burning.
	if not INFO.has(w):
		return 0
	if INFO[w].has("pulses"):
		return int(INFO[w]["pulses"])
	return SIPHON_PULSES if klass(w) == CLASS_SIPHON else BEAM_PULSES


static func hole_chance(w: int) -> float:
	return float(INFO[w].get("hole", 1.0)) if INFO.has(w) else 0.0


static func passes_shield(w: int) -> bool:
	return INFO.has(w) and bool(INFO[w].get("no_shield", false))


static func bomb(w: int) -> bool:
	## (v62) Is it a bomb: teleported into the room, past shields and point defence, not dodged?
	return klass(w) == CLASS_BOMB


static func area(w: int) -> bool:
	## (v62) Do its shots spread over the room aimed at and those beside it?
	return INFO.has(w) and bool(INFO[w].get("area", false))


static func crew_wound(w: int) -> float:
	## (v62) The chance its hit wounds each one in the room (0: the plain rule for hits that get through).
	return float(INFO[w].get("crew", 0.0)) if INFO.has(w) else 0.0


static func pierce(w: int) -> int:
	return int(INFO[w].get("pierce", 0)) if INFO.has(w) else 0


static func can_fx(w: int) -> bool:
	return FX_GUNS.has(w)


static func fx_name(fx: int) -> String:
	return FX_NAMES[fx] if fx > 0 and fx <= FX_COUNT else ""


static func full_name(w: int, fx: int) -> String:
	## Its name with the effect it carries: «Феникс (сдвоенный)».
	return name_of(w) + (" (%s)" % FX_NAMES[fx] if fx > 0 and fx <= FX_COUNT else "")


static func lower_name(w: int, fx: int = FX_NONE) -> String:
	var n := full_name(w, fx)
	return n.substr(0, 1).to_lower() + n.substr(1)


static func about_fx(fx: int) -> String:
	return ("Особенность: %s." % FX_ABOUT[fx]) if fx > 0 and fx <= FX_COUNT else ""


# (v58) A ship weapon off its mount is a thing in the cargo: its number tells the
# weapon, and for a tier 3 gun the effect rolled for it, or that it is damaged
# (a looted gun that must be mended at the workbench before it can be mounted).
static func item_of(w: int, fx: int = FX_NONE, damaged: bool = false) -> int:
	## The thing a weapon off its mount is, in the cargo. The rockets took the
	## numbers after the first ten, so the later weapons go on from Net.ITEM_GUN_MORE.
	if damaged:
		return Net.ITEM_GUN_DAMAGED + w
	if fx > FX_NONE and FX_GUNS.has(w):
		return Net.ITEM_GUN_FX + FX_GUNS.find(w) * FX_COUNT + fx - 1
	if w >= HORNET:
		return Net.ITEM_GUN_LATE + w - HORNET    # (v62) the numbers after NOVA's were taken by the shells and parts
	return Net.ITEM_GUN + w if w < TRACTOR else Net.ITEM_GUN_MORE + w


static func of_item(item: int) -> int:
	## The weapon a thing in the cargo is (whole, with an effect or damaged), or NONE.
	if item >= Net.ITEM_GUN_DAMAGED and item < Net.ITEM_GUN_DAMAGED + COUNT:
		var d := item - Net.ITEM_GUN_DAMAGED
		return d if OURS.has(d) else NONE
	if item >= Net.ITEM_GUN_FX and item < Net.ITEM_GUN_FX + FX_GUNS.size() * FX_COUNT:
		return FX_GUNS[(item - Net.ITEM_GUN_FX) / FX_COUNT]
	if item >= Net.ITEM_GUN_LATE and item < Net.ITEM_GUN_LATE + COUNT - HORNET:
		return item - Net.ITEM_GUN_LATE + HORNET
	var w := item - Net.ITEM_GUN
	if w > NONE and w < TRACTOR:
		return w
	w = item - Net.ITEM_GUN_MORE
	return w if w >= TRACTOR and w < HORNET and OURS.has(w) else NONE


static func fx_of(item: int) -> int:
	## The effect a tier 3 gun in the cargo carries (FX_NONE for none).
	if item >= Net.ITEM_GUN_FX and item < Net.ITEM_GUN_FX + FX_GUNS.size() * FX_COUNT:
		return (item - Net.ITEM_GUN_FX) % FX_COUNT + 1
	return FX_NONE


static func damaged(item: int) -> bool:
	return item >= Net.ITEM_GUN_DAMAGED and item < Net.ITEM_GUN_DAMAGED + COUNT and of_item(item) != NONE


static func gun_items() -> PackedInt32Array:
	## Every thing that is a ship weapon of ours: whole, with each effect, damaged.
	var out := PackedInt32Array()
	for w in OURS:
		out.append(item_of(w))
		if FX_GUNS.has(w):
			for fx in range(1, FX_COUNT + 1):
				out.append(item_of(w, fx))
		out.append(item_of(w, FX_NONE, true))
	return out


static func shield_damage(w: int) -> float:
	## How much of a shield a shot of this weapon takes when the shield stops it.
	if not INFO.has(w):
		return 0.0
	if INFO[w].has("shield"):
		return float(INFO[w]["shield"])
	if klass(w) == CLASS_BEAM or klass(w) == CLASS_TRACTOR:
		return BEAM_SHIELD
	if klass(w) == CLASS_KINETIC:
		return KINETIC_WEAR
	return SHIELD_PER_DAMAGE * maxf(float(INFO[w]["damage"]), 1.0)


static func through_chance(level: float) -> float:
	## The chance a shot that meets a shield at this level gets through it (the author's rule).
	if level >= SHIELD_HOLDS:
		return 0.0
	return clampf((SHIELD_HOLDS - level) / SHIELD_HOLDS, 0.0, 1.0)


static func sell_price(price: int, share: float = SELL_SHARE) -> int:
	return maxi(int(price * share), 1) if price > 0 else 0


# ---------------------------------------------------------------- (v58) tiers by distance

static func top_tier(far: int) -> int:
	## The best tier met this many jumps from the start (the author: "little by little").
	return 1 if far < 4 else (2 if far < 8 else 3)


static func tiers_for(far: int, count: int, rng: RandomNumberGenerator) -> Array[int]:
	## The tiers of `count` guns found this far out: jumps 0..3 all tier 1; 4..7 at
	## most one tier 2; from 8 up to half of them tier 2, and now and then one of
	## those tier 3.
	var out: Array[int] = []
	for i in count:
		out.append(1)
	if count <= 0 or far < 4:
		return out
	if far < 8:
		if rng.randf() < 0.5:
			out[rng.randi_range(0, count - 1)] = 2
		return out
	for i in maxi(count / 2, 1):
		if rng.randf() < 0.75:
			out[i] = 3 if rng.randf() < 0.15 else 2
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out


static func pick_of_tier(t: int, pool: Array, rng: RandomNumberGenerator) -> int:
	## A pirate gun of that tier: from `pool` if it has one of that tier, else from all of them.
	var choice: Array = pool.filter(func(w: int) -> bool: return tier(w) == t and (PIRATE_GUNS[t] as Array).has(w))
	if choice.is_empty():
		choice = PIRATE_GUNS[clampi(t, 1, 3)]
	return choice[rng.randi_range(0, choice.size() - 1)]


static func roll_fx(w: int, rng: RandomNumberGenerator) -> int:
	## The effect a tier 3 gun comes with (FX_NONE for a gun that has none).
	return rng.randi_range(1, FX_COUNT) if can_fx(w) else FX_NONE


static func parts_from(item: int) -> int:
	## (v58, the workbench) How many parts of its kind taking that gun apart gives: one per tier, one less if it is damaged.
	var w := of_item(item)
	if w == NONE or unique(w):
		return 0
	return maxi(tier(w) - (1 if damaged(item) else 0), 1)


static func upgrade_cost(item: int) -> int:
	## Parts of its kind it takes to make that gun the next of its line, 0 = it cannot be.
	var w := of_item(item)
	if w == NONE or damaged(item) or next_of(w) == NONE:
		return 0
	return UPGRADE_PARTS[tier(w)]
