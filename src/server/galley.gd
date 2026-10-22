extends RefCounted
## (v71, the author's L2: "a galley with meals that give short effects") The
## galley's stove ('G' in the map, by the hydroponic trays) and the dishes cooked
## on it. Server only.
##
## Anybody stands at the stove and picks a dish on its screen (the workbench's
## packet, Net.BENCH_STEW..): it is cooked from the rations (and plasters) in the
## supply locker while the cook stays there (COOK_SECONDS), and goes into the
## locker. The stove needs power. Bots do not cook: a meal is a person's work
## (the author's G2, people over bots).
## A dish is eaten by hand: a click on oneself (or Z) or on a neighbour, like a patch.
##   Рагу (stew, 2 rations): for Items "meal" seconds the eater's wounds close by
##     STEW_HEAL a second (up to 30 in all).
##   Кофе (coffee, 1 ration): for its seconds every piece of work by hand takes
##     Player.COFFEE_PACE of its time (Player.pace).
##   Травяной отвар (broth, 1 ration and 1 plaster): at once, stops bleeding,
##     eases a concussion and closes BROTH_HEAL wounds.
## One effect at a time: a new dish replaces the one at work.
## The crew's rations at jumps are Garden's; dishes are never eaten there.

const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Player := preload("res://src/server/player.gd")

const COOK_SECONDS := 5.0
const RECIPES := Items.DISHES         # a dish: what it is cooked from (taken from the locker)
const STEW_HEAL := 0.1               # wounds a stew closes per second while it is at work
const BROTH_HEAL := 15.0

var server: GameServer


func setup(p_server: GameServer) -> void:
	server = p_server


static func cooks(action: int) -> bool:
	return RECIPES.has(action)


func at_stove(p: Player) -> int:
	## The stove in front of it (-1 = none).
	var cell := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	return cell if cell >= 0 and server.map.stove.has(cell) else -1


func can(action: int, cell: int) -> String:
	## "" if that dish may be cooked at that stove now, or why not (in the player's words).
	if not RECIPES.has(action):
		return "?"
	if cell >= 0 and not server.power.at(cell):
		return "Плита обесточена."
	var need: Dictionary = RECIPES[action][1]
	var lack := PackedStringArray()
	for item: int in need.keys():
		if int(server.ship.store.get(item, 0)) < int(need[item]):
			lack.append("%s ×%d" % [Items.name_of(item).to_lower(), int(need[item])])
	return "" if lack.is_empty() else "Нужно в шкафу снабжения: %s." % ", ".join(lack)


func asked(p: Player, action: int) -> void:
	## (Workshop.asked passes the galley's dishes on here.)
	if p.cond != Net.COND_OK:
		return
	var cell := at_stove(p)
	if cell < 0:
		return
	var why := can(action, cell)
	if why != "":
		server.chat.tell(p, why)
		return
	p.bench = PackedByteArray([action, 0])
	p.work = 0
	p.work_cell = -2
	p.work_total = maxi(roundi(COOK_SECONDS * Net.TICK_HZ * p.pace(server.tick)), 1)


func update(p: Player) -> void:
	## One more tick of cooking (Workshop.update passes it on here).
	var action := p.bench[0]
	var cell := at_stove(p)
	if p.cond != Net.COND_OK or cell < 0 or p.st.dir != Net.DIR_NONE:
		p.bench = PackedByteArray()
		p.work = 0
		return
	var why := can(action, cell)
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
	cook(p, action)


func cook(p: Player, action: int) -> void:
	var store := server.ship.store
	var dish: int = RECIPES[action][0]
	var need: Dictionary = RECIPES[action][1]
	for item: int in need.keys():
		store[item] = int(store.get(item, 0)) - int(need[item])
	store[dish] = int(store.get(dish, 0)) + 1
	server.supplies.tell_store()
	server.usage.note(p, "galley")         # (v82)
	server.chat.say("%s готовит на камбузе: %s. Блюдо в шкафу снабжения." % [p.name, Items.name_of(dish).to_lower()])


func eat(p: Player, who: Player) -> void:
	## The dish in p's hand eaten by `who` (p itself, or a neighbour).
	var dish := p.in_hand()
	if who == null:
		server.chat.tell(p, "Щёлкните по себе (или Z) или по тому, кто стоит рядом.")
		return
	if who.prisoner:
		server.chat.tell(p, "%s в наручниках: пленных не кормят с камбуза." % who.name)
		return
	p.slots[p.hand] = Net.ITEM_NONE
	p.self_dirty = true
	match dish:
		Net.ITEM_BROTH:
			who.bleeding = 0
			who.concussed = 0
			server.combat.heal(who, BROTH_HEAL)
		_:
			who.meal = dish
			who.meal_until = server.tick + roundi(float(Items.INFO[dish]["meal"]) * Net.TICK_HZ)
	who.self_dirty = true
	var what := Items.name_of(dish).to_lower()
	if who == p:
		server.chat.tell(p, {Net.ITEM_STEW: "Вы съедаете рагу: раны понемногу затягиваются.",
			Net.ITEM_COFFEE: "Вы выпиваете кофе: работа пойдёт быстрее.",
			Net.ITEM_BROTH: "Вы выпиваете травяной отвар: стало легче."}.get(dish, "Вы едите: %s." % what))
	else:
		server.chat.say("%s угощает: %s, %s." % [p.name, who.name, what])


func tick() -> void:
	## Once a second: a stew at work closes wounds; a spent effect ends.
	if server.tick % Net.TICK_HZ != 0:
		return
	for q: Player in server.players:
		if q == null or q.meal == 0:
			continue
		if server.tick >= q.meal_until or q.corpse or q.cond == Net.COND_DEAD:
			q.meal = 0
			q.self_dirty = true
			continue
		if q.meal == Net.ITEM_STEW and q.wounds > 0.0:
			server.combat.heal(q, STEW_HEAL)
