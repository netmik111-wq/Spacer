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
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")

const APART_TICKS := 6 * Net.TICK_HZ
const MEND_TICKS := 10 * Net.TICK_HZ
const UPGRADE_TICKS := 15 * Net.TICK_HZ

var server: GameServer
var _rng := RandomNumberGenerator.new()   # only for the effect a tier 3 gun gets: the game's own lots stay as they were


func setup(p_server: GameServer) -> void:
	server = p_server
	_rng.randomize()


static func ticks_for(action: int) -> int:
	return {Net.BENCH_APART: APART_TICKS, Net.BENCH_MEND: MEND_TICKS, Net.BENCH_UPGRADE: UPGRADE_TICKS}.get(action, 0)


func can(action: int, item: int) -> String:
	## "" if that work may start on that gun from the locker now, or why not (in the player's words).
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
	p.work_total = roundi(ticks_for(action) * (1.0 - 0.5 * p.skill(Net.SKILL_REPAIR)))


func update(p: Player) -> void:
	## One more tick of the work at the bench, called right after Repairs.update so
	## the progress it leaves in Player.work is what the client is told.
	if p.bench.is_empty():
		return
	var action := p.bench[0]
	var item := p.bench[1]
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
