extends RefCounted
## (v58) The workbench ('B' in the map, in the engine room): an engineer takes
## a ship's gun from the locker apart into parts of its kind, mends a damaged
## one with a spare part, or puts parts into it to make it the next gun of its
## line (see Weapons.next_of). The guns, the parts and the spare parts stay in
## the ship's locker (Ship.store): the bench works on what is there.
## Only an engineer may do it (the author's word). The work goes on by itself
## while the engineer stays at the bench, and its progress is shown like any
## other work (Player.work); stepping away, or the gun leaving the locker,
## puts it down. The bench needs no power and does not break.
## (v60, the author's W4) It also makes ammunition of a spare part from the
## locker: AMMO_MADE shells, rockets or EMP rockets (never cheaper than a
## trader's, so traders stay worth a visit; it is for when none is near).
## (v67, the author's R3) It also refines a can of fuel from scrap or ore (REFINE):
## dearer than buying the fuel, so it is for when no trader is near.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const APART_TICKS := 6 * Net.TICK_HZ
const MEND_TICKS := 10 * Net.TICK_HZ
const UPGRADE_TICKS := 15 * Net.TICK_HZ
const AMMO_TICKS := 6 * Net.TICK_HZ
# (v60) what one spare part makes: shells 3 x 3 cr, rockets 2 x 4 cr, an EMP rocket 6 cr (a part costs 10)
const AMMO_MADE := {Net.BENCH_SHELLS: [Net.ITEM_SHELL, 3], Net.BENCH_ROCKETS: [Net.ITEM_ROCKET, 2], Net.BENCH_EMP: [Net.ITEM_EMP_ROCKET, 1]}
# (v67, the author's R3: "a refinery that costs more than finding or buying fuel") what a can of fuel takes:
# 4 scrap (sold, 16 cr) or 3 ore (18 cr), against 12 cr for a can's worth at a trader
const REFINE := {Net.BENCH_FUEL_SCRAP: [Net.ITEM_SCRAP, 4], Net.BENCH_FUEL_ORE: [Net.ITEM_ORE, 3]}
const REFINE_TICKS := 10 * Net.TICK_HZ

var server: GameServer
var _rng := RandomNumberGenerator.new()   # only for the effect a tier 3 gun gets: the game's own lots stay as they were


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.randomize()


static func ticks_for(action: int) -> int:
	return {Net.BENCH_APART: APART_TICKS, Net.BENCH_MEND: MEND_TICKS, Net.BENCH_UPGRADE: UPGRADE_TICKS,
		Net.BENCH_SHELLS: AMMO_TICKS, Net.BENCH_ROCKETS: AMMO_TICKS, Net.BENCH_EMP: AMMO_TICKS,
		Net.BENCH_FUEL_SCRAP: REFINE_TICKS, Net.BENCH_FUEL_ORE: REFINE_TICKS}.get(action, 0)


func can(action: int, item: int) -> String:
	## "" if that work may start on that gun from the locker now, or why not (in the player's words).
	if AMMO_MADE.has(action):
		return "" if int(server.ship.store.get(Net.ITEM_PART, 0)) > 0 else "Нужна запчасть в шкафу снабжения."
	if REFINE.has(action):
		var need: Array = REFINE[action]
		return "" if int(server.ship.store.get(need[0], 0)) >= int(need[1]) else "Нужно в шкафу снабжения: %s ×%d." % [Items.name_of(need[0]).to_lower(), int(need[1])]
	var w := Weapons.of_item(item)
	if w == Weapons.NONE or int(server.ship.store.get(item, 0)) <= 0:
		return "Этого орудия нет в шкафу снабжения."
	match action:
		Net.BENCH_APART:
			if Weapons.parts_from(item) <= 0:
				return "Это орудие не разобрать."
		Net.BENCH_MEND:
			if not Weapons.damaged(item):
				return "Орудие исправно."
			if int(server.ship.store.get(Net.ITEM_PART, 0)) <= 0:
				return "Нужна запчасть в шкафу снабжения."
		Net.BENCH_UPGRADE:
			var need := Weapons.upgrade_cost(item)
			if need <= 0:
				return "Это орудие не улучшить." if not Weapons.damaged(item) else "Сначала почините орудие."
			if int(server.ship.store.get(Items.gun_parts(Weapons.kind(w)), 0)) < need:
				return "Нужно деталей (%s): %d." % [Weapons.KIND_NAMES[Weapons.kind(w)], need]
		_:
			return "?"
	return ""


func at_bench(p: Player) -> bool:
	var cell := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	return cell >= 0 and server.map.bench.has(cell)


func asked(p: Player, action: int, item: int) -> void:
	if action == Net.BENCH_STOP:
		p.bench = PackedByteArray()
		p.work = 0
		return
	if server.galley.cooks(action):
		server.galley.asked(p, action)       # (v71) the galley's stove uses the same packet
		return
	if p.cond != Net.COND_OK or not at_bench(p):
		return
	if p.job != Net.JOB_ENGINEER:
		server.chat.tell(p, "За верстаком работают только инженеры.")
		return
	var why := can(action, item)
	if why != "":
		server.chat.tell(p, why)
		return
	p.bench = PackedByteArray([action, item])
	p.work = 0
	p.work_cell = -2                     # (no cell: the bench's own work, see update)
	p.work_total = maxi(roundi(ticks_for(action) * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)) * p.pace(server.tick)), 1)


func update(p: Player) -> void:
	## One more tick of the work at the bench, called right after Repairs.update so
	## the progress it leaves in Player.work is what the client is told.
	if p.bench.is_empty():
		return
	var action := p.bench[0]
	var item := p.bench[1]
	if server.galley.cooks(action):
		server.galley.update(p)              # (v71) cooking at the galley's stove
		return
	if p.cond != Net.COND_OK or not at_bench(p) or p.st.dir != Net.DIR_NONE:
		p.bench = PackedByteArray()
		p.work = 0
		return
	var why := can(action, item)
	if why != "":
		p.bench = PackedByteArray()
		p.work = 0
		server.chat.tell(p, why)
		return
	p.work_cell = -2
	p.work += 1
	if p.work < p.work_total:
		return
	p.work = 0
	p.bench = PackedByteArray()
	p.train(Net.SKILL_REPAIR)
	_finish(p, action, item)


func _finish(p: Player, action: int, item: int) -> void:
	var store := server.ship.store
	if AMMO_MADE.has(action):
		var made: Array = AMMO_MADE[action]
		store[Net.ITEM_PART] = int(store[Net.ITEM_PART]) - 1
		store[made[0]] = int(store.get(made[0], 0)) + int(made[1])
		server.chat.say("%s делает на верстаке из запчасти: %s ×%d." % [p.name, Items.name_of(made[0]).to_lower(), int(made[1])])
		return
	if REFINE.has(action):
		var need: Array = REFINE[action]
		store[need[0]] = int(store[need[0]]) - int(need[1])
		store[Net.ITEM_FUEL] = int(store.get(Net.ITEM_FUEL, 0)) + 1
		server.chat.say("%s перегоняет на верстаке %s ×%d в канистру топлива." % [p.name, Items.name_of(need[0]).to_lower(), int(need[1])])
		return
	var w := Weapons.of_item(item)
	store[item] = int(store[item]) - 1
	var parts := Items.gun_parts(Weapons.kind(w))
	match action:
		Net.BENCH_APART:
			var n := Weapons.parts_from(item)
			store[parts] = int(store.get(parts, 0)) + n
			server.chat.say("%s разбирает на верстаке: %s. Детали (%s) в шкафу снабжения: +%d." % [p.name,
				Items.name_of(item).to_lower(), Weapons.KIND_NAMES[Weapons.kind(w)], n])
		Net.BENCH_MEND:
			store[Net.ITEM_PART] = int(store[Net.ITEM_PART]) - 1
			var made := Weapons.item_of(w, Weapons.roll_fx(w, _rng) if Weapons.tier(w) >= 3 else Weapons.FX_NONE)
			store[made] = int(store.get(made, 0)) + 1
			server.chat.say("%s чинит на верстаке: %s." % [p.name, Items.name_of(made).to_lower()])
		Net.BENCH_UPGRADE:
			store[parts] = int(store[parts]) - Weapons.upgrade_cost(item)
			var next := Weapons.next_of(w)
			var made := Weapons.item_of(next, Weapons.roll_fx(next, _rng) if Weapons.tier(next) >= 3 else Weapons.FX_NONE)
			store[made] = int(store.get(made, 0)) + 1
			server.chat.say("%s улучшает на верстаке %s: теперь это %s." % [p.name, Weapons.lower_name(w),
				Items.name_of(made).to_lower()])
