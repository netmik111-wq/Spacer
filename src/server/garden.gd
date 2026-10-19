extends RefCounted
## (v63, the author's R1, and his notebook: "hydroponics must be tended by a
## bot or a person; a variety of plants, mutations and combinatorics") Food and
## the hydroponic trays. Server only.
##
## Food: the crew eat rations (Net.ITEM_FOOD) from the supply locker at every
## jump, one for every two of them (players and bots; the reserve sleeps in the
## cryopods and eats nothing). With the locker empty the crew starve: their
## health sinks slowly, down to STARVE_FLOOR, never lower (nobody dies of
## hunger, the author's rule of no two obstacles at once), and comes back once
## there is food again.
##
## The trays ('P'): hold "use" at one. An empty tray takes the seed in hand, or
## else a packet from the locker (PLANT_SECONDS). A plant wants tending every
## CARE_FROM..CARE_TO seconds (TEND_SECONDS of work, by anybody, or a bot on
## «Работы»); left wanting it grows at half pace, and after WITHER_SECONDS it
## withers and must be cleared. Without power it stands still (mushrooms grow
## anyway). A ripe tray is harvested: its rations (and the herb's plasters) go
## to the supply locker, its seed comes back now and then (Plants.SEED_BACK),
## sometimes mutated, and two neighbouring trays ripe together with the right
## pair in them may give a hybrid seed (Plants.CROSSES).

const Net := preload("res://src/shared/net.gd")
const Plants := preload("res://src/shared/plants.gd")
const Player := preload("res://src/server/player.gd")

const PLANT_SECONDS := 2.0
const TEND_SECONDS := 2.0
const HARVEST_SECONDS := 2.0
const CLEAR_SECONDS := 2.0
const CARE_FROM := 60.0              # a plant wants tending after this long...
const CARE_TO := 90.0                # ... up to this long
const NEGLECT_PACE := 0.5            # wanting care, it grows this much slower
const WITHER_SECONDS := 300.0        # wanting care this long, it withers
const EAT_SHARE := 2                 # one ration for this many of the crew at every jump
const STARVE_RATE := 0.1             # health the hungry lose per second...
const STARVE_FLOOR := 30.0           # ... down to here, never lower
const FED_RATE := 1.0                # what hunger takes back per second once there is food
const NOT_HERE := "-"

var server: GameServer
var plants := PackedInt32Array()     # per tray: its plant (Plants.seed_item), 0 = empty
var stage := PackedByteArray()       # per tray: Net.GROW_*
var growth := PackedFloat32Array()   # per tray: 0..1 of the way to ripe
var care_at := PackedFloat32Array()  # per tray: the growth seconds when it next wants tending
var neglect := PackedFloat32Array()  # per tray: seconds it has wanted tending
var hunger := 0.0                    # health the crew's hunger takes off what they can have
var _hungry := false                 # the last meal was short: they starve until food comes
var _sent := PackedByteArray()
var _rng := RandomNumberGenerator.new()


func setup(p_server: GameServer) -> void:
	server = p_server
	var n: int = server.map.trays.size()
	plants.resize(n)
	plants.fill(0)
	stage.resize(n)
	stage.fill(Net.GROW_EMPTY)
	growth.resize(n)
	growth.fill(0.0)
	care_at.resize(n)
	care_at.fill(0.0)
	neglect.resize(n)
	neglect.fill(0.0)
	hunger = 0.0
	_sent = PackedByteArray()
	_rng.randomize()


func tray_of(cell: int) -> int:
	return server.map.trays.find(cell)


func wants_care(t: int) -> bool:
	return stage[t] == Net.GROW_GROWING and growth[t] * Plants.seconds(plants[t]) >= care_at[t]


func _powered(t: int) -> bool:
	return server.power.at(server.map.trays[t]) or Plants.dark(plants[t])


# --------------------------------------------------------------- food

func eaters() -> int:
	var n := 0
	for p: Player in server.players:
		if p != null and not p.pirate and not p.ally and not p.robot and not p.corpse and p.cond != Net.COND_DEAD:
			n += 1
	return n


func jumped() -> void:
	## (Navigation) A jump: the crew eat.
	var need := ceili(float(eaters()) / EAT_SHARE)
	var have := int(server.ship.store.get(Net.ITEM_FOOD, 0))
	server.ship.store[Net.ITEM_FOOD] = maxi(have - need, 0)
	_hungry = have < need
	if have < need:
		server.chat.say("Пайки кончились: экипаж голодает. Здоровье будет медленно падать (но не ниже %d). Купите пайки у торговца или вырастите в гидропонике." % int(STARVE_FLOOR))
	elif have - need <= need * 2:
		server.chat.say("Пайков осталось на %d прыжк(а/ов)." % ((have - need) / maxi(need, 1)))
	server.supplies.tell_store()
	server.story.changed()


func starving() -> bool:
	return _hungry


func hunger_of(p: Player) -> float:
	## What hunger takes off the health this one can have (Crew passes it to Vitals with the wounds).
	## Never below STARVE_FLOOR on top of the wounds: hunger alone must not keep someone out cold
	## for good (the playthrough found a starving crewman with light wounds who could never wake).
	if p.pirate or p.ally or p.robot:
		return 0.0
	return minf(hunger, maxf(Net.HEALTH_FULL - p.wounds - STARVE_FLOOR, 0.0))


func _feed_tick() -> void:
	## Once a second.
	var food := int(server.ship.store.get(Net.ITEM_FOOD, 0))
	var was := starving()
	if food > 0 and _hungry:
		_hungry = false                      # food again: the hunger passes
		server.chat.say("В шкафу снабжения снова есть пайки: голод отступает.")
	if _hungry and food <= 0:
		hunger = minf(hunger + STARVE_RATE, Net.HEALTH_FULL - STARVE_FLOOR)
	else:
		hunger = maxf(hunger - FED_RATE, 0.0)
	if hunger > 0.0:
		for p: Player in server.players:
			if p == null or p.corpse or p.cond == Net.COND_DEAD or hunger_of(p) <= 0.0:
				continue
			var cap := Net.HEALTH_FULL - p.wounds - hunger_of(p)
			if p.health > cap and p.health > STARVE_FLOOR:
				p.health = maxf(cap, STARVE_FLOOR)
				p.self_dirty = true
	if starving() != was:
		server.story.changed()


# --------------------------------------------------------------- trays

func can(p: Player, cell: int) -> String:
	## "" if holding "use" there does something now; NOT_HERE if it is no tray; else why not.
	var t := tray_of(cell)
	if t < 0:
		return NOT_HERE
	match stage[t]:
		Net.GROW_EMPTY:
			if Plants.is_seed(p.in_hand()) or _best_seed() > 0:
				return ""
			return "Нечего посадить: семена продают торговцы."
		Net.GROW_GROWING:
			if wants_care(t):
				return ""
			return "%s растёт: %d%%%s." % [Plants.plant_name(plants[t]), roundi(growth[t] * 100.0),
				"" if _powered(t) else ", но без энергии стоит"]
	return ""


func ticks(cell: int) -> int:
	var t := tray_of(cell)
	if t < 0:
		return 1
	match stage[t]:
		Net.GROW_EMPTY:
			return roundi(PLANT_SECONDS * Net.TICK_HZ)
		Net.GROW_GROWING:
			return roundi(TEND_SECONDS * Net.TICK_HZ)
		Net.GROW_RIPE:
			return roundi(HARVEST_SECONDS * Net.TICK_HZ)
	return roundi(CLEAR_SECONDS * Net.TICK_HZ)


func _best_seed() -> int:
	## The seed a tray takes from the locker: the best of what is there (hybrids, then mutated, then the biggest crop).
	var best := 0
	var score := -1
	for item: int in server.ship.store.keys():
		if Plants.is_seed(item) and int(server.ship.store[item]) > 0:
			var s := Plants.food(item) * 10 + Plants.plasters(item) * 5 + Plants.trait_of(item)
			if s > score:
				score = s
				best = item
	return best


func finish(p: Player, cell: int) -> void:
	## The work at the tray is done.
	var t := tray_of(cell)
	if t < 0:
		return
	var who := p.name
	match stage[t]:
		Net.GROW_EMPTY:
			var item := p.in_hand()
			if Plants.is_seed(item):
				p.slots[p.hand] = Net.ITEM_NONE
				p.self_dirty = true
			else:
				item = _best_seed()
				if item <= 0:
					return
				server.ship.store[item] = int(server.ship.store[item]) - 1
				server.supplies.tell_store()
			plant(t, item)
			server.chat.say("%s сажает в гидропонику: %s." % [who, Plants.plant_name(item).to_lower()])
		Net.GROW_GROWING:
			if wants_care(t):
				_tend(t)
		Net.GROW_RIPE:
			harvest(t, who)
		Net.GROW_DEAD:
			plants[t] = 0
			stage[t] = Net.GROW_EMPTY
			growth[t] = 0.0
			server.chat.say("%s расчищает лоток гидропоники." % who)


func ripen_all() -> void:
	## (admin) Every tray ripe now; an empty one gets potatoes first.
	for t in plants.size():
		if stage[t] == Net.GROW_EMPTY or stage[t] == Net.GROW_DEAD:
			plant(t, Plants.seed_item(Plants.POTATO if t % 2 == 0 else Plants.SOY))
		stage[t] = Net.GROW_RIPE
		growth[t] = 1.0


func plant(t: int, item: int) -> void:
	plants[t] = item
	stage[t] = Net.GROW_GROWING
	growth[t] = 0.0
	neglect[t] = 0.0
	care_at[t] = _rng.randf_range(CARE_FROM, CARE_TO)


func _tend(t: int) -> void:
	neglect[t] = 0.0
	care_at[t] = growth[t] * Plants.seconds(plants[t]) + _rng.randf_range(CARE_FROM, CARE_TO)


func harvest(t: int, who: String) -> void:
	var item := plants[t]
	var food := Plants.food(item)
	var plasters := Plants.plasters(item)
	_store(Net.ITEM_FOOD, food)
	if plasters > 0:
		_store(Net.ITEM_MEDPATCH, plasters)
	var got: Array[String] = ["пайков: %d" % food]
	if plasters > 0:
		got.append("пластырей: %d" % plasters)
	if _rng.randf() < Plants.SEED_BACK:
		var tr := Plants.trait_of(item)
		if _rng.randf() < Plants.MUTATE_CHANCE:
			tr = Plants.mutate(tr, _rng.randf())
		var back := Plants.seed_item(Plants.kind_of(item), tr)
		_store(back, 1)
		got.append(Plants.name_of(back).to_lower() + (" (мутация!)" if tr != Plants.trait_of(item) else ""))
	# a neighbour ripe at the same time with the right pair in it: a hybrid now and then
	for n in [t - 1, t + 1]:
		if n < 0 or n >= plants.size() or stage[n] != Net.GROW_RIPE or not _beside(t, n):
			continue
		var h := Plants.cross(Plants.kind_of(item), Plants.kind_of(plants[n]))
		if h >= 0 and _rng.randf() < Plants.CROSS_CHANCE:
			_store(Plants.seed_item(h), 1)
			got.append("гибрид: %s" % Plants.plant_name(Plants.seed_item(h)).to_lower())
			break
	plants[t] = 0
	stage[t] = Net.GROW_EMPTY
	growth[t] = 0.0
	server.supplies.tell_store()
	server.chat.say("%s собирает урожай (%s): %s. Всё в шкафу снабжения." % [who, Plants.plant_name(item).to_lower(), ", ".join(got)])


func _beside(a: int, b: int) -> bool:
	var w: int = server.map.width
	var ca: int = server.map.trays[a]
	var cb: int = server.map.trays[b]
	return absi(ca % w - cb % w) + absi(ca / w - cb / w) == 1


func _store(item: int, n: int) -> void:
	server.ship.store[item] = int(server.ship.store.get(item, 0)) + n


func tick() -> void:
	if server.tick % Net.TICK_HZ != 0:
		return
	_feed_tick()
	for t in plants.size():
		if stage[t] != Net.GROW_GROWING or not _powered(t):
			continue
		var pace := 1.0
		if wants_care(t):
			pace = NEGLECT_PACE
			neglect[t] += 1.0
			if neglect[t] >= WITHER_SECONDS:
				stage[t] = Net.GROW_DEAD
				server.chat.say("В гидропонике завял %s: за ним никто не ухаживал." % Plants.plant_name(plants[t]).to_lower())
				continue
		growth[t] = minf(growth[t] + pace / Plants.seconds(plants[t]), 1.0)
		if growth[t] >= 1.0:
			stage[t] = Net.GROW_RIPE
			server.chat.say("В гидропонике созрел урожай: %s." % Plants.plant_name(plants[t]).to_lower())
	var pkt := packet()
	if pkt != _sent:
		_sent = pkt
		server.to_all(pkt)


func packet() -> PackedByteArray:
	var out := PackedByteArray([Net.S_GARDEN, plants.size()])
	for t in plants.size():
		var n := out.size()
		out.resize(n + 6)
		out.encode_u16(n, server.map.trays[t])
		out[n + 2] = plants[t]
		out[n + 3] = stage[t]
		out[n + 4] = roundi(growth[t] * 100.0)
		var f := 0
		if wants_care(t):
			f |= Net.GARDEN_CARE
		if stage[t] == Net.GROW_GROWING and not _powered(t):
			f |= Net.GARDEN_DARK
		if neglect[t] >= WITHER_SECONDS * 0.5:
			f |= Net.GARDEN_NEGLECT
		out[n + 5] = f
	return out


# --------------------------------------------------------------- saving

func save() -> Dictionary:
	return {"seed": Array(plants), "stage": Array(stage), "growth": Array(growth), "care": Array(care_at),
		"neglect": Array(neglect), "hunger": hunger, "hungry": _hungry}


func load_from(d: Dictionary) -> void:
	if d.is_empty() or (d.get("seed", []) as Array).size() != plants.size():
		return
	for t in plants.size():
		plants[t] = int(d["seed"][t])
		stage[t] = int(d["stage"][t])
		growth[t] = float(d["growth"][t])
		care_at[t] = float(d["care"][t])
		neglect[t] = float(d["neglect"][t])
	hunger = float(d.get("hunger", 0.0))
	_hungry = bool(d.get("hungry", false))
