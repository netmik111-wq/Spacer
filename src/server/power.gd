extends RefCounted
## (v61, the author's SMES answers P1-P9) The ship's power: the engine that makes
## it, the SMES that stores it, and what everything aboard draws. Server only.
##
## The engine gives the ship its own draw (BASE_LOAD: the air plant, lights,
## doors, consoles, pumps) and the reactor's power for the guns and the shield
## (Outfit.reactor; half of it inside an ion storm, see Hazards). What the guns
## and the shield leave of the reactor's power charges the SMES ('S' in the map,
## in the engine room), up to its input target a second; it never takes power
## from a gun (my V2 pick). The SMES gives power back in two ways:
##   with the engine going, up to BOOST more for the guns and the shield (the
##     author's P2), paying only for what is used above the reactor;
##   with the engine out (or stalled by a power fault), the whole ship: the
##     ship's own draw and the guns and the shield, up to its output target, until
##     it is empty (the author's P1). Full, it carries a fully armed ship 3 minutes (P4).
## The author's rule since v61: no engine and an empty SMES means no power, and
## nothing breaks from it. An SMES that is hit breaks like any machine and loses
## its whole charge (P7, his correction); a spare part mends it.
##
## The bridge has a small backup SMES ('Q', P3): it charges itself while the ship
## has power and, when the ship is dark, keeps the room it faces lit and the
## consoles there working (ShipMap.on_backup) for a few minutes. It cannot make a
## jump: a jump needs the engine.
##
## Every SMES has an SS13 terminal (P5): charging on or off, output on or off,
## the input and output targets, the charge and what it is doing. The lower half
## of the main one's screen is the power monitor (P6), and the holomap shows it too.
##
## (v68, the author's F2) The main SMES's terminal is also the engineer's power
## panel: the guns', the point defence's and the shield's switches moved here
## from the gun console; the engines take power for more dodge (ENGINE_POWER a
## level); the ship's own draw can be cut by its breakers (lights, the air
## plant, the hydroponic trays: 1 each, freed for the guns); and the reactor
## can be overcharged for OVER_SECONDS (OVER_POWER more), each second of it with
## an OVER_RISK chance that the engine breaks.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Gear := preload("res://src/shared/gear.gd")
const Player := preload("res://src/server/player.gd")

const BASE_LOAD := 4                 # the ship's own draw, besides the guns and the shield, every breaker on:
const CORE_LOAD := 1                 # (v68) consoles, doors and pumps (never switched off), and 1 each for
const BREAKERS := 3                  # the lights, the air plant and the trays (Net.BREAKER_*)
const ENGINE_POWER := 2              # (v68) what each level of power for the engines takes...
const ENGINE_DODGE := 0.05           # ... and the dodge it adds while somebody flies
const ENGINE_LEVELS := 2
const OVER_POWER := 4                # (v68) the reactor overcharged gives this much more...
const OVER_SECONDS := 20.0           # ... this long...
const OVER_REST := 40.0              # ... then rests this long
const OVER_RISK := 0.03              # the chance each second of it that the engine breaks
const BOOST := 3                     # the most the SMES adds to the reactor's power in a fight
const CAPACITY := 2160.0             # a full SMES with its built-in coils: 3 minutes of 12 (Gear.COIL_CAPACITY scales it)
const INPUT_MAX := 6                 # the most it takes a second with its built-in coils (Gear.COIL_CHARGE adds to it)
const OUTPUT_MAX := 15
const OUTPUT_START := 12             # enough for the whole ship: the ship's own draw and a full reactor's worth
const SMALL_CAPACITY := 360.0        # the bridge's backup: 6 minutes of its draw
const SMALL_LOAD := 1                # what the bridge draws from it
const SMALL_INPUT := 2
const SMALL_OUTPUT := 2
const SEND_EVERY := 10               # the terminals and the holomap are told twice a second
const WARN_AT: Array[float] = [0.5, 0.2, 0.05]   # shares of a charge at which the crew is told it is running out

# terminal actions (Net.C_SMES)
const ACT_CHARGE := 1                # value 1 = charging on, 0 = off
const ACT_OUTPUT := 2                # value 1 = output on, 0 = off
const ACT_INPUT := 3                 # value = the input target
const ACT_LEVEL := 4                 # value = the output target
# (v68) the power panel (the main SMES only)
const ACT_GUARD := 5                 # value 1 = the point defence on, 0 = off
const ACT_SHIELD := 6                # value 1 = the shield on, 0 = off
const ACT_ENGINES := 7               # value = power for the engines, 0..ENGINE_LEVELS
const ACT_BREAKER := 8               # value = Net.BREAKER_* * 2 + 1 (on) or + 0 (off)
const ACT_OVERCHARGE := 9            # value 1 = overcharge the reactor now, 0 = stop it
const ACT_GUN := 16                  # + mount number: value 1 = that gun powered, 0 = cut

var server: GameServer
var units: Array = []                # per SMES: {cell, small, charge, charging, output, input, level, in_now, out_now, warned}
var _told := PackedByteArray()
var _was_on := true
var breaker := PackedByteArray([1, 1, 1])   # (v68) per Net.BREAKER_*: 1 = on
var engines := 0                     # (v68) power for the engines, 0..ENGINE_LEVELS
var over_until := 0                  # (v68) the tick the overcharge ends (past = not overcharged)
var over_rest_until := 0             # and the tick it may be started again
var over_risk := OVER_RISK           # (tests set it)
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	units = []
	for cell: int in server.map.smes.keys():
		units.append(_unit(cell, false))
	for cell: int in server.map.smes_small.keys():
		units.append(_unit(cell, true))
	_told = PackedByteArray()
	_was_on = true
	breaker = PackedByteArray([1, 1, 1])
	engines = 0
	over_until = 0
	over_rest_until = 0


func _unit(cell: int, small: bool) -> Dictionary:
	## A new SMES, full and set as my V4 pick: charging on, output on, enough for the whole ship.
	var u := {"cell": cell, "small": small, "charging": true, "output": true,
		"input": SMALL_INPUT if small else INPUT_MAX, "level": SMALL_OUTPUT if small else OUTPUT_START,
		"in_now": 0.0, "out_now": 0.0, "warned": 0}
	u["charge"] = capacity(u)
	return u


# ---------------------------------------------------------------- what there is

func capacity(u: Dictionary) -> float:
	if bool(u["small"]):
		return SMALL_CAPACITY
	return CAPACITY * Gear.COIL_CAPACITY[_coils()]


func input_max(u: Dictionary) -> int:
	if bool(u["small"]):
		return SMALL_INPUT
	return INPUT_MAX + Gear.COIL_CHARGE[_coils()]


func _coils() -> int:
	## The tier of the coils in the SMES (read from the ship: Power is set up before Outfit).
	var gear: PackedByteArray = server.ship.gear
	return clampi(gear[Gear.SYS_COILS], 1, 3) if gear.size() > Gear.SYS_COILS else 1


func output_max(u: Dictionary) -> int:
	return SMALL_OUTPUT if bool(u["small"]) else OUTPUT_MAX


func coils_changed() -> void:
	## Other coils went in: a smaller SMES holds what it can, and the input target fits.
	for u: Dictionary in units:
		u["charge"] = minf(float(u["charge"]), capacity(u))
		u["input"] = mini(int(u["input"]), input_max(u))


func works(u: Dictionary) -> bool:
	var cell: int = u["cell"]
	return not server.ship.broken.has(cell) and server.tick >= int(server.ship.jammed.get(cell, -1))


func gives(u: Dictionary) -> bool:
	## Can it give power now: whole, not put out by ion, its output on, some charge left.
	return works(u) and bool(u["output"]) and float(u["charge"]) > 0.0 and int(u["level"]) > 0 and not server.fleet.is_lost()


func main_units() -> Array:
	return units.filter(func(u: Dictionary) -> bool: return not bool(u["small"]))


func charge() -> float:
	## What the main SMES holds, all of them together.
	var n := 0.0
	for u: Dictionary in main_units():
		n += float(u["charge"])
	return n


func full() -> float:
	var n := 0.0
	for u: Dictionary in main_units():
		n += capacity(u)
	return n


func _offer() -> int:
	## The most the main SMES can give right now (the output targets of those that can give).
	var n := 0
	for u: Dictionary in main_units():
		if gives(u):
			n += int(u["level"])
	return n


func engine_running() -> bool:
	## The engine makes power: it is whole and has not stalled (a power fault, see Systems.power_glitch).
	## (v85) A ship of the fleet that is lost has none at all.
	return not server.ship.engine_down() and server.tick >= server.ship.power_out_until and not server.fleet.is_lost()


func reactor_now() -> int:
	## The reactor's power for the guns and the shield now: half inside an ion storm,
	## (v68) more while overcharged.
	var r: int = server.outfit.reactor()
	r = r / 2 if server.hazards != null and server.hazards.in_storm() else r
	return r + (OVER_POWER if overcharged() else 0)


func overcharged() -> bool:
	return server.tick < over_until and engine_running()


func base_load() -> int:
	## (v68) The ship's own draw now: consoles and doors, and what the breakers leave on.
	return CORE_LOAD + breaker.count(1)


func freed() -> int:
	## What the breakers switched off give to the guns and the shield.
	return BASE_LOAD - base_load()


func lights_on() -> bool:
	return breaker[Net.BREAKER_LIGHTS] == 1


func light_at(cell: int) -> bool:
	## (v68) Is there light in that cell: the ship's power and its lights on, or the bridge's backup?
	## With the lights' breaker off the bridge stays lit (its own lights, as the backup keeps them).
	return (on() and lights_on()) or ((on() or backup_on()) and server.map.on_backup(cell))


func air_on() -> bool:
	return breaker[Net.BREAKER_AIR] == 1


func trays_on() -> bool:
	return breaker[Net.BREAKER_TRAYS] == 1


func engines_draw() -> int:
	return engines * ENGINE_POWER


func engine_dodge() -> float:
	## (v68) What the power for the engines adds to our dodge (Stations.our_dodge).
	return ENGINE_DODGE * engines


func carrying() -> bool:
	## Does the SMES carry the whole ship now (the engine gives nothing, and it can give the ship's own draw)?
	return not engine_running() and _offer() >= base_load()


func on() -> bool:
	## Does the ship have power? The engine, or the SMES carrying it (the author's rule since v61).
	return engine_running() or _offer() >= base_load()


func backup_on() -> bool:
	## Is the ship dark and the bridge's backup keeping its room lit?
	if on():
		return false
	for u: Dictionary in units:
		if bool(u["small"]) and gives(u):
			return true
	return false


func at(cell: int) -> bool:
	## Has the thing in that cell (or that floor cell) power now: the ship's, or the bridge's backup?
	return on() or (backup_on() and server.map.on_backup(cell))


func boost() -> int:
	## What the SMES can add to the reactor's power with the engine going.
	return mini(BOOST, _offer()) if engine_running() else 0


func budget() -> int:
	## The power the guns and the shield may draw now.
	if engine_running():
		return reactor_now() + boost() + freed()
	if _offer() >= base_load():
		return mini(_offer() - base_load(), server.outfit.reactor() + BOOST + freed())
	return server.outfit.reactor()           # dark: nothing charges anyway, and nothing is switched off for it


func draw() -> int:
	## What the whole ship draws now: its own draw and the guns and the shield.
	return (base_load() + _load()) if on() else 0


func _load() -> int:
	## What the guns and the shield draw: only in a fight. Out of one they stand
	## ready and idle, so the SMES charges from the whole reactor and, with the
	## engine out, lasts BASE_LOAD's worth (9 minutes) instead of a fight's (3).
	return server.gunnery.power_used() if server.gunnery.fighting() else 0


func seconds_left() -> int:
	## How long the main SMES lasts at what it gives now (65535 = it gives nothing).
	var out := 0.0
	for u: Dictionary in main_units():
		out += float(u["out_now"])
	if out <= 0.0:
		return 65535
	return mini(int(charge() / out), 65534)


func seconds_left_at(load: int) -> int:
	## How long the main SMES would last giving `load` a second.
	return 65535 if load <= 0 else mini(int(charge() / load), 65534)


# ---------------------------------------------------------------- each tick

func tick() -> void:
	var ship = server.ship
	for u: Dictionary in units:
		u["in_now"] = 0.0
		u["out_now"] = 0.0
		if ship.broken.has(int(u["cell"])) and float(u["charge"]) > 0.0:
			u["charge"] = 0.0                # (the author's P7) a hit takes its whole charge
			u["warned"] = 0
			server.chat.say("%s выбит: весь заряд потерян. Почините его запчастью." % _cap(server.map.device_name(int(u["cell"]))))
	var used := _load()
	if engine_running():
		# what is used above the reactor comes from the SMES; what is left of the reactor charges it
		var over := clampi(used - reactor_now() - freed(), 0, boost())
		_take(float(over))
		var spare := float(maxi(reactor_now() + freed() - used, 0))
		for u: Dictionary in main_units():
			if bool(u["charging"]) and works(u) and spare > 0.0 and float(u["charge"]) < capacity(u):
				var take := minf(minf(float(int(u["input"])), spare), (capacity(u) - float(u["charge"])) * Net.TICK_HZ)
				spare -= take
				u["charge"] = float(u["charge"]) + take / Net.TICK_HZ
				u["in_now"] = take
				if float(u["charge"]) > capacity(u) * WARN_AT[0]:
					u["warned"] = 0
	elif carrying():
		_take(float(base_load() + used))
	_small_tick()
	_overcharge_tick()
	if server.outfit.fit_power():
		server.chat.say("Не хватает энергии: часть орудий отключена%s." % (" (ионный шторм ослабил реактор)" if server.hazards.in_storm() else ""))
	var now := on()
	if now != _was_on:
		_was_on = now
		if not now and full() > 0.0:
			server.chat.say("СМЭС больше не держит корабль: питания нет. Двигатель на нижней палубе." if charge() <= 0.0
				else "СМЭС отключён: корабль обесточен.")
	if server.tick % SEND_EVERY == 0:
		_tell()


func _overcharge_tick() -> void:
	## (v68) The overcharged reactor may break the engine; it ends by itself.
	if over_until <= 0:
		return
	if server.tick >= over_until or not engine_running():
		over_until = 0
		over_rest_until = server.tick + roundi(OVER_REST * Net.TICK_HZ)
		server.chat.say("Перегрузка реактора закончилась: он снова даёт обычную мощность.")
		_tell(true)
		return
	if server.tick % Net.TICK_HZ == 0 and _rng.randf() < over_risk:
		over_until = 0
		over_rest_until = server.tick + roundi(OVER_REST * Net.TICK_HZ)
		if not server.systems.break_engine():
			server.systems.power_glitch()
		server.chat.say("Перегрузка сожгла двигатель! Почините его на нижней палубе; пока СМЭС держит корабль.")
		_tell(true)


func _take(amount: float) -> void:
	## Draws `amount` a second from the main SMES, from those that can give, in turn.
	var left := amount
	for u: Dictionary in main_units():
		if left <= 0.0:
			break
		if not gives(u):
			continue
		var give := minf(minf(left, float(int(u["level"]))), float(u["charge"]) * Net.TICK_HZ)
		u["charge"] = maxf(float(u["charge"]) - give / Net.TICK_HZ, 0.0)
		u["out_now"] = give
		left -= give
		_warn(u)


func _warn(u: Dictionary) -> void:
	## The crew hears it as it runs low (only while it carries the ship: a boost
	## running out shows on the gun console by itself).
	if not carrying():
		return
	var share := float(u["charge"]) / maxf(capacity(u), 1.0)
	var k: int = u["warned"]
	if k < WARN_AT.size() and share <= WARN_AT[k]:
		u["warned"] = k + 1
		server.chat.say("Заряд СМЭС: %d%%, его хватит примерно на %s. Почините двигатель на нижней палубе." % [roundi(share * 100.0), _time(seconds_left())])


func _small_tick() -> void:
	for u: Dictionary in units:
		if not bool(u["small"]):
			continue
		if on():
			if bool(u["charging"]) and works(u) and float(u["charge"]) < capacity(u):
				u["in_now"] = float(int(u["input"]))
				u["charge"] = minf(float(u["charge"]) + float(u["in_now"]) / Net.TICK_HZ, capacity(u))
		elif gives(u):
			u["out_now"] = float(SMALL_LOAD)
			u["charge"] = maxf(float(u["charge"]) - float(SMALL_LOAD) / Net.TICK_HZ, 0.0)
			if float(u["charge"]) <= 0.0:
				server.chat.say("Резервный СМЭС мостика разряжен: на мостике темно.")


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


static func _time(seconds: int) -> String:
	if seconds >= 65535:
		return "долго"
	if seconds >= 90:
		return "%d мин" % roundi(seconds / 60.0)
	return "%d с" % seconds


func status(u: Dictionary) -> int:
	## What it is doing, as the terminal says it (Net.SMES_*).
	if server.ship.broken.has(int(u["cell"])):
		return Net.SMES_BROKEN
	if not works(u):
		return Net.SMES_JAMMED
	if float(u["out_now"]) > 0.0:
		return Net.SMES_SENDING
	if float(u["in_now"]) > 0.0:
		return Net.SMES_CHARGING
	if float(u["charge"]) <= 0.0:
		return Net.SMES_EMPTY
	if float(u["charge"]) >= capacity(u) - 0.01:
		return Net.SMES_FULL
	return Net.SMES_IDLE


# ---------------------------------------------------------------- the terminal

func asked(p: Player, which: int, action: int, value: int) -> void:
	## Somebody facing an SMES works its terminal. It needs no power: it is the SMES's own.
	if p.cond != Net.COND_OK or which < 0 or which >= units.size():
		return
	var u: Dictionary = units[which]
	if server.map.use_ahead(p.st.x, p.st.y, p.st.facing) != int(u["cell"]):
		return
	if action >= ACT_GUARD and not bool(u["small"]):
		_panel(p, action, value)
		_tell(true)
		return
	match action:
		ACT_CHARGE:
			u["charging"] = value != 0
		ACT_OUTPUT:
			u["output"] = value != 0
		ACT_INPUT:
			u["input"] = clampi(value, 0, input_max(u))
		ACT_LEVEL:
			u["level"] = clampi(value, 0, output_max(u))
	_tell(true)
	server.systems.power_changed()


# ---------------------------------------------------------------- (v68) the power panel

func _panel(p: Player, action: int, value: int) -> void:
	var g = server.gunnery
	server.usage.note(p, "overcharge" if action == ACT_OVERCHARGE and value != 0 else "panel")   # (v82)
	if action >= ACT_GUN:
		g.arm(p, action - ACT_GUN, value != 0)
		return
	match action:
		ACT_GUARD:
			g.arm_guard(p, value != 0)
		ACT_SHIELD:
			g.switch_shield(p, value != 0)
		ACT_ENGINES:
			set_engines(p, value)
		ACT_BREAKER:
			set_breaker(value >> 1, value & 1 == 1, p)
		ACT_OVERCHARGE:
			overcharge(p, value != 0)


func set_engines(p: Player, level: int) -> void:
	level = clampi(level, 0, ENGINE_LEVELS)
	if level > engines and server.gunnery.power_used() + (level - engines) * ENGINE_POWER > budget():
		if p != null:
			server.chat.tell(p, "Не хватает энергии реактора на двигатели: нужно %d, свободно %d." % [(level - engines) * ENGINE_POWER,
				budget() - server.gunnery.power_used()])
		return
	engines = level


func set_breaker(which: int, on_now: bool, p: Player = null) -> void:
	## A breaker of the ship's own draw switched on or off (Net.BREAKER_*).
	if which < 0 or which >= BREAKERS or (breaker[which] == 1) == on_now:
		return
	if on_now and on() and engine_running() and server.gunnery.fighting() and server.gunnery.power_used() > budget() - 1:
		if p != null:
			server.chat.tell(p, "Не хватает энергии: сначала отключите орудие, щит или двигатели.")
		return
	breaker[which] = 1 if on_now else 0
	if which == Net.BREAKER_LIGHTS:
		server.ship.lights_off = not on_now
		server.replication.sight_changed()
		server.to_all(server.ship.power_packet())
	var who := "" if p == null else p.name + ": "
	server.chat.say("%s%s %s." % [who, Net.BREAKER_NAMES[which], "включено" if on_now else "отключено, энергия отдана орудиям"])


func overcharge(p: Player, start: bool) -> void:
	if not start:
		if over_until > 0:
			over_until = server.tick                 # it ends on the next tick, and rests
		return
	if overcharged():
		return
	if not engine_running():
		server.chat.tell(p, "Двигатель не работает: перегружать нечего.")
		return
	if server.tick < over_rest_until:
		server.chat.tell(p, "Реактор остывает после перегрузки: ещё %d с." % ceili(float(over_rest_until - server.tick) / Net.TICK_HZ))
		return
	over_until = server.tick + roundi(OVER_SECONDS * Net.TICK_HZ)
	server.chat.say("%s перегружает реактор: +%d энергии на %d с. Двигатель может не выдержать!" % [p.name if p != null else "Кто-то",
		OVER_POWER, int(OVER_SECONDS)])


func spend(amount: float) -> bool:
	## (v68) Takes `amount` from the main SMES at once (the pilot's evade), if it holds that much.
	if charge() < amount:
		return false
	var left := amount
	for u: Dictionary in main_units():
		var take := minf(left, float(u["charge"]))
		u["charge"] = float(u["charge"]) - take
		left -= take
	_tell(true)
	return true


func set_charge(share: float) -> void:
	## (the admin panel, tests) Every SMES this full, 0..1.
	for u: Dictionary in units:
		u["charge"] = capacity(u) * clampf(share, 0.0, 1.0)
		u["warned"] = 0
	_tell(true)


# ---------------------------------------------------------------- telling

func packet() -> PackedByteArray:
	## Net.S_SMES: the terminals and the power monitor.
	var ship = server.ship
	var out := PackedByteArray([Net.S_SMES, ship.id & 0xFF, ship.id >> 8, units.size()])
	for u: Dictionary in units:
		var o := out.size()
		out.resize(o + 15)
		out.encode_u8(o, 1 if bool(u["small"]) else 0)
		out.encode_u16(o + 1, int(u["cell"]))
		out.encode_u16(o + 3, roundi(float(u["charge"])))
		out.encode_u16(o + 5, roundi(capacity(u)))
		out.encode_u8(o + 7, (1 if bool(u["charging"]) else 0) | (2 if bool(u["output"]) else 0))
		out.encode_u8(o + 8, int(u["input"]))
		out.encode_u8(o + 9, int(u["level"]))
		out.encode_u8(o + 10, input_max(u))
		out.encode_u8(o + 11, output_max(u))
		out.encode_u8(o + 12, clampi(roundi(float(u["in_now"]) * 10.0), 0, 255))
		out.encode_u8(o + 13, clampi(roundi(float(u["out_now"]) * 10.0), 0, 255))
		out.encode_u8(o + 14, status(u))
	# the power monitor
	var o := out.size()
	out.resize(o + 9)
	out.encode_u8(o, (reactor_now() + BASE_LOAD) if engine_running() else 0)
	out.encode_u8(o + 1, base_load() if on() else 0)
	out.encode_u8(o + 2, _load())
	out.encode_u8(o + 3, budget())
	out.encode_u8(o + 4, (1 if server.hazards.in_storm() else 0) | (2 if engine_running() else 0) | (4 if carrying() else 0) | (8 if backup_on() else 0))
	out.encode_u16(o + 5, seconds_left())
	out.encode_u16(o + 7, server.outfit.reactor())
	# (v68) the power panel: u8 breakers (bit per Net.BREAKER_* on), u8 power for the engines,
	# u8 seconds of the overcharge left, u8 seconds until it may be started again
	out.append(breaker[0] | breaker[1] << 1 | breaker[2] << 2)
	out.append(engines)
	out.append(clampi(ceili(float(over_until - server.tick) / Net.TICK_HZ), 0, 255) if overcharged() else 0)
	out.append(clampi(ceili(float(over_rest_until - server.tick) / Net.TICK_HZ), 0, 255))
	return out


func _tell(now: bool = false) -> void:
	var p := packet()
	if p != _told or now:
		_told = p
		server.to_all(p)


# ---------------------------------------------------------------- saving

func save_panel() -> Dictionary:
	## (v68) The breakers and the engines' power (an overcharge is not kept).
	return {"breaker": Array(breaker), "engines": engines}


func load_panel(d: Dictionary) -> void:
	var b: Array = d.get("breaker", [1, 1, 1])
	for i in mini(b.size(), BREAKERS):
		breaker[i] = 1 if int(b[i]) != 0 else 0
	engines = clampi(int(d.get("engines", 0)), 0, ENGINE_LEVELS)
	server.ship.lights_off = not lights_on()


func save() -> Array:
	var out: Array = []
	for u: Dictionary in units:
		out.append({"charge": u["charge"], "charging": u["charging"], "output": u["output"], "input": u["input"], "level": u["level"]})
	return out


func load_from(data: Array) -> void:
	for i in mini(data.size(), units.size()):
		var d: Dictionary = data[i]
		var u: Dictionary = units[i]
		u["charge"] = clampf(float(d.get("charge", capacity(u))), 0.0, capacity(u))
		u["charging"] = bool(d.get("charging", true))
		u["output"] = bool(d.get("output", true))
		u["input"] = clampi(int(d.get("input", u["input"])), 0, input_max(u))
		u["level"] = clampi(int(d.get("level", u["level"])), 0, output_max(u))
	_tell(true)
