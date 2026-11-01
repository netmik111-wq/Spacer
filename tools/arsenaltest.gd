extends SceneTree
## (v98) Checks the arsenal and body armour (the author's arsenal step and his armour, helmet and suit
## ideas) on a real server stepped by hand:
##   godot --headless --path . --script res://tools/arsenaltest.gd
## The laser rifle and the plasma gun shoot, run down and take energy cells; a vest and a helmet take
## their share of every kind of harm but plasma and never go on with a suit; a suit takes 10% sealed
## and 30% let down (B, two seconds), and let down it keeps no vacuum off the body; an energy shield
## soaks up shots (plasma twice over, never blows) and charges again after a quiet while; a hand
## shield on the arm stops what comes from the front and lets no gun fire, though a baton still
## strikes; boarders down the road carry the new guns; the two new ship guns are known everywhere.
## Fails with exit code 1.

const GameServer := preload("res://src/server/game_server.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Armour := preload("res://src/shared/armour.gd")
const Vitals := preload("res://src/server/vitals.gd")

var failed := 0
var server: GameServer


func _initialize() -> void:
	server = GameServer.new()
	get_root().add_child(server)
	var problem := server.start(26398, "ship02", 0)
	if problem != "":
		print(problem)
		quit(1)
		return
	server.director.auto = false
	server.road.auto = false
	server.story.auto = false
	server.stations.volunteers = false
	server.defence.on = false

	# the things themselves
	for item in [Net.ITEM_VEST, Net.ITEM_HELMET, Net.ITEM_RIOT, Net.ITEM_ESHIELD, Net.ITEM_CELL, Net.ITEM_LASER_GUN, Net.ITEM_PLASMA_GUN]:
		_expect(Items.known(item) and Items.price(item) > 0 and Items.kept_in_locker().has(item), "%s is known, sold and kept in the locker" % Items.name_of(item))
	_expect(Items.worn_as(Net.ITEM_VEST) == Net.WEAR_BODY and Items.worn_as(Net.ITEM_HELMET) == Net.WEAR_HEAD
		and Items.worn_as(Net.ITEM_ESHIELD) == Net.WEAR_BELT and Items.worn_as(Net.ITEM_RIOT) == Net.WEAR_SHIELD, "each is worn in its own place")
	_expect(Items.rounds(Net.ITEM_LASER_GUN + Net.LASER_ROUNDS) == Net.LASER_ROUNDS and Items.ammo_of(Net.ITEM_LASER_GUN) == Net.ITEM_CELL
		and Items.ammo_of(Net.ITEM_PLASMA_GUN + 2) == Net.ITEM_CELL and Items.loaded(Net.ITEM_PLASMA_GUN) == Net.ITEM_PLASMA_GUN + Net.PLASMA_ROUNDS,
		"both energy guns count their charges and take a cell")
	var seen := {}
	for item: int in Items.INFO.keys():
		_expect(item > 0 and item < 256, "(item %d fits a byte)" % item)
		seen[item] = true
	for w in [Weapons.PULSE, Weapons.PLASMA_CANNON]:
		var it := Weapons.item_of(w)
		_expect(Weapons.of_item(it) == w and Weapons.of_item(Weapons.item_of(w, Weapons.FX_NONE, true)) == w and Items.known(it)
			and Weapons.in_space(w) and not Items.INFO.has(it) == false, "%s is a ship gun in the cargo, whole and damaged, with space numbers" % Weapons.name_of(w))
		_expect(not Items.is_seed(it) and Items.gear_of(it) == 0, "(%s takes no seed's or crate's number)" % Weapons.name_of(w))
	_expect(not Weapons.fits(Weapons.PLASMA_CANNON, 2) and Weapons.fits(Weapons.PLASMA_CANNON, 0) and Weapons.fits(Weapons.PULSE, 2),
		"the plasma cannon wants the bow or a side, the pulse laser goes anywhere")
	_expect(Weapons.PIRATE_GUNS[2].has(Weapons.PULSE) and Weapons.PIRATE_GUNS[3].has(Weapons.PLASMA_CANNON), "pirates carry them by tier")

	var a = server.crew.new_player("Стрелок")
	var b = server.crew.new_player("Цель")
	var line := _line(5)
	_expect(line.x >= 0, "(a straight open stretch of floor)")
	a.st.place(line.x, line.y)
	b.st.place(line.x + 4, line.y)
	a.st.facing = Net.DIR_RIGHT
	b.st.facing = Net.DIR_LEFT

	# what is worn: a suit and armour never together
	_expect(b.has_suit(), "(a fresh one wears a suit)")
	b.slots[b.hand] = Net.ITEM_VEST
	_expect(not server.inventory.act(b) and b.worn[Net.WEAR_BODY] == Net.ITEM_NONE and b.in_hand() == Net.ITEM_VEST, "a vest does not go on over a suit (his A2)")
	b.slots[b.hand] = Net.ITEM_HELMET
	_expect(not server.inventory.act(b) and b.worn[Net.WEAR_HEAD] == Net.ITEM_NONE, "nor a helmet: the suit has its own")
	b.slots[b.hand] = Net.ITEM_NONE
	var suit := b.take_off(Net.WEAR_SUIT)
	b.slots[b.hand] = Net.ITEM_VEST
	_expect(server.inventory.act(b) and b.worn[Net.WEAR_BODY] == Net.ITEM_VEST, "without a suit the vest goes on")
	b.slots[b.hand] = Net.ITEM_HELMET
	_expect(server.inventory.act(b) and b.worn[Net.WEAR_HEAD] == Net.ITEM_HELMET, "and the helmet")
	b.slots[b.hand] = suit
	_expect(not server.inventory.act(b) and not b.has_suit(), "and then no suit goes on over them")
	b.slots[b.hand] = Net.ITEM_NONE

	# armour by the kind of harm (his numbers)
	_expect(_wound(b, 30, a, server.combat.CAUSE_SHOT) == _near(30.0 * 0.55 * 0.55), "a vest and a helmet take 45%% each off a bullet (%.1f)" % _wound(b, 30, a, server.combat.CAUSE_SHOT))
	_expect(_wound(b, 30, a, server.combat.CAUSE_BLOW) == _near(30.0 * 0.4 * 0.4), "60% each off a blow")
	_expect(_wound(b, 30, null, server.combat.CAUSE_BLAST) == _near(30.0 * 0.7 * 0.7), "30% each off a blast")
	_expect(_wound(b, 30, a, server.combat.CAUSE_PLASMA) == _near(30.0), "nothing off plasma")
	b.worn[Net.WEAR_BODY] = Net.ITEM_NONE
	b.worn[Net.WEAR_HEAD] = Net.ITEM_NONE
	b.put_on(Net.ITEM_SUIT + Net.SUIT_TANK_STEPS)
	_expect(b.has_suit() and not b.deflated, "(the suit back on, sealed)")
	_expect(_wound(b, 30, a, server.combat.CAUSE_PLASMA) == _near(27.0), "a sealed suit takes 10% off anything, plasma too")

	# letting the suit down (B) takes two seconds; then it takes 30%
	server.inventory.inflate(b)
	_run(roundi(Armour.SWITCH_SECONDS * Net.TICK_HZ) - 5)
	_expect(not b.deflated, "it is still sealed before the two seconds are up")
	_run(10)
	_expect(b.deflated, "then it is let down")
	_expect(_wound(b, 30, a, server.combat.CAUSE_SHOT) == _near(21.0), "a let-down suit takes 30% off")
	# in a vacuum, on the tank: sealed nothing hurts, let down the body suffers though the mask feeds it
	var cell: int = b.st.y * server.map.width + b.st.x
	var kept: float = server.air.air[cell]
	b.health = 100.0
	b.wounds = 0.0
	b.supply = true
	b.tank = 1.0
	server.air.air[cell] = 0.0
	server.crew.update_vitals(b)
	_expect(b.health < 100.0 - Vitals.DECOMPRESSION * Net.TICK_SEC * 0.9, "let down in a vacuum, the body takes the pressure's harm (%.2f)" % b.health)
	_expect(b.health > 100.0 - (Vitals.DECOMPRESSION + Vitals.SUFFOCATION) * Net.TICK_SEC * 0.9, "but the mask still gives breath")
	server.inventory.inflate(b)
	_run(roundi(Armour.SWITCH_SECONDS * Net.TICK_HZ) + 2)
	_expect(not b.deflated, "B again seals it")
	b.health = 90.0
	server.air.air[cell] = 0.0
	server.crew.update_vitals(b)
	_expect(b.health >= 90.0, "sealed, a vacuum does nothing on the tank")
	server.air.air[cell] = kept
	b.supply = false
	var off := b.take_off(Net.WEAR_SUIT)
	_expect(off != Net.ITEM_NONE and not b.deflated, "a suit taken off is folded sealed")
	b.put_on(off)

	# the energy shield: soaks up shots, plasma twice over, never a blow; charges again after a quiet while
	b.take_off(Net.WEAR_SUIT)
	b.worn[Net.WEAR_BELT] = Net.ITEM_ESHIELD
	b.shield = float(Net.SHIELD_FULL)
	_expect(_wound(b, 30, a, server.combat.CAUSE_SHOT) == _near(0.0) and absf(b.shield - 20.0) < 0.01, "a full energy shield soaks a whole bullet")
	_expect(_wound(b, 30, a, server.combat.CAUSE_SHOT) == _near(10.0) and b.shield == 0.0, "and lets through what its charge cannot hold")
	b.shield = 20.0
	_expect(_wound(b, 30, a, server.combat.CAUSE_PLASMA) == _near(20.0), "plasma drains it twice over")
	b.shield = float(Net.SHIELD_FULL)
	_expect(_wound(b, 20, a, server.combat.CAUSE_BLOW) == _near(20.0) and b.shield == Net.SHIELD_FULL, "a blow passes it untouched")
	b.shield = 10.0
	b.shield_hit = server.tick
	_run(roundi(Armour.SHIELD_WAIT * Net.TICK_HZ) - 4)
	_expect(b.shield == 10.0, "it does not charge while hits are fresh")
	_run(Net.TICK_HZ * 2 + 4)
	_expect(b.shield > 10.0 + Armour.SHIELD_RATE, "then it charges (%.1f)" % b.shield)
	b.worn[Net.WEAR_BELT] = Net.ITEM_NONE
	b.shield = 0.0

	# the energy guns: they hit, run down, take a cell
	_expect(_shot(a, b, Net.ITEM_LASER_GUN + Net.LASER_ROUNDS) == _near(float(Items.LASER_DAMAGE)), "a laser rifle hits for %d" % Items.LASER_DAMAGE)
	_expect(a.in_hand() == Net.ITEM_LASER_GUN + Net.LASER_ROUNDS - 1, "and spends a charge")
	_expect(b.bleeding == 0, "a laser wound never bleeds")
	_expect(_shot(a, b, Net.ITEM_PLASMA_GUN + 1) == _near(float(Items.PLASMA_DAMAGE)), "a plasma gun hits for %d" % Items.PLASMA_DAMAGE)
	a.slots[a.hand] = Net.ITEM_PLASMA_GUN
	a.add(Net.ITEM_CELL)
	a.ready_tick = 0
	server.combat.use_at(a, server.tick, Vector2(b.st.x, b.st.y))
	_expect(a.in_hand() == Net.ITEM_PLASMA_GUN + Net.PLASMA_ROUNDS and not a.slots.has(Net.ITEM_CELL), "an empty one takes an energy cell")
	b.worn[Net.WEAR_BODY] = Net.ITEM_VEST
	_expect(_shot(a, b, Net.ITEM_LASER_GUN + 3) == _near(Items.LASER_DAMAGE * 0.55), "a vest holds a laser")
	_expect(_shot(a, b, Net.ITEM_PLASMA_GUN + 3) == _near(float(Items.PLASMA_DAMAGE)), "but not plasma")
	b.worn[Net.WEAR_BODY] = Net.ITEM_NONE

	# the hand shield on the arm (his S1 note)
	b.worn[Net.WEAR_SHIELD] = Net.ITEM_RIOT
	server.combat.riot_block = 1.0       # ((v101) it stops 35% by chance: pinned here, counted below)
	_expect(_shot(a, b, Net.ITEM_PISTOL + 3) == _near(0.0), "a hand shield facing the shooter stops the bullet")
	server.combat.riot_block = Armour.RIOT_BLOCK
	var stopped := 0
	for k in 2000:
		if server.combat.blocked(b, Vector2(a.st.x, a.st.y)):
			stopped += 1
	_expect(absf(stopped / 2000.0 - Armour.RIOT_BLOCK) < 0.04, "(v101, his note) it stops about 35%% of what comes at it (%d of 2000)" % stopped)
	server.combat.riot_block = 1.0
	b.st.facing = Net.DIR_RIGHT
	_expect(_shot(a, b, Net.ITEM_PISTOL + 3) > 1.0, "but not one from behind")
	b.st.facing = Net.DIR_LEFT
	b.slots[b.hand] = Net.ITEM_PISTOL + 3
	b.ready_tick = 0
	server.combat.use_at(b, server.tick, Vector2(a.st.x, a.st.y))
	_expect(b.in_hand() == Net.ITEM_PISTOL + 3, "with a hand shield on, no gun fires")
	a.st.place(b.st.x - 1, b.st.y)
	b.slots[b.hand] = Net.ITEM_BATON
	b.ready_tick = 0
	var before: float = a.health
	server.combat.use_at(b, server.tick, Vector2(a.st.x, a.st.y))
	_expect(a.health < before, "though a baton still strikes")
	b.worn[Net.WEAR_SHIELD] = Net.ITEM_NONE

	# boarders down the road (his H4)
	server.road.depth = 2
	var lasers := 0
	var plasma := 0
	var vests := 0
	for k in 60:
		var pirate = server.pirates.spawn_boarder(line.x, line.y, true, 7)
		lasers += 1 if pirate.slots.has(Net.ITEM_LASER_GUN + Net.LASER_ROUNDS) else 0
		plasma += 1 if pirate.slots.has(Net.ITEM_PLASMA_GUN + Net.PLASMA_ROUNDS) else 0
		vests += 1 if pirate.worn[Net.WEAR_BODY] == Net.ITEM_VEST else 0
		if pirate.slots.has(Net.ITEM_LASER_GUN + Net.LASER_ROUNDS) or pirate.slots.has(Net.ITEM_PLASMA_GUN + Net.PLASMA_ROUNDS):
			_expect(pirate.slots.has(Net.ITEM_CELL) and not pirate.slots.has(Net.ITEM_MAG), "(one with an energy gun carries a cell, not a magazine)")
		_expect(not (pirate.has_suit() and pirate.worn[Net.WEAR_BODY] != Net.ITEM_NONE), "(no boarder wears a vest over a suit)")
		server.crew.remove(pirate)
	_expect(lasers > 0 and plasma > 0 and vests > 0, "boarders in the third cluster carry lasers (%d), plasma (%d) and vests (%d)" % [lasers, plasma, vests])
	server.road.depth = 0
	var plain := 0
	for k in 30:
		var pirate = server.pirates.spawn_boarder(line.x, line.y, true, 0)
		plain += 1 if pirate.slots.has(Net.ITEM_PISTOL + Net.PISTOL_ROUNDS) else 0
		server.crew.remove(pirate)
	_expect(plain == 30, "in the first cluster they keep their pistols")

	# (v101, his Notebook note) a shot at the one standing flies over the one knocked down at his feet
	var row := _line(7)
	var c = server.crew.new_player("Сбитый")
	b.worn[Net.WEAR_SHIELD] = Net.ITEM_NONE
	a.st.place(row.x, row.y)
	c.st.place(row.x + 4, row.y)
	b.st.place(row.x + 5, row.y)
	a.st.facing = Net.DIR_RIGHT
	b.st.facing = Net.DIR_LEFT
	server.combat.stun_for(c, 10.0)
	c.health = 100.0
	var hurt_b := _shot(a, b, Net.ITEM_PISTOL + 3)
	_expect(hurt_b > 1.0 and c.health == 100.0, "a shot at the one standing hits him, not the one knocked down before him (%.1f)" % hurt_b)
	b.st.place(row.x + 6, row.y)
	a.slots[a.hand] = Net.ITEM_PISTOL + 3
	a.ready_tick = 0
	server.combat.use_at(a, server.tick, Vector2(c.st.x, c.st.y))
	_expect(c.health < 100.0, "aimed at the one down, it hits him")

	print("arsenaltest: %s" % ("ok" if failed == 0 else "%d failed" % failed))
	quit(1 if failed > 0 else 0)


func _wound(q, damage: int, by, cause: int) -> float:
	## What a wound of that much and that cause takes off q's health.
	q.health = 100.0
	q.wounds = 0.0
	q.bleeding = 0
	q.cond = Net.COND_OK
	server.combat.hurt(q, damage, by, cause)
	var lost: float = 100.0 - q.health
	q.health = 100.0
	q.wounds = 0.0
	return snappedf(lost, 0.01)


func _near(x: float) -> float:
	return snappedf(x, 0.01)


func _shot(p, q, gun: int) -> float:
	## p fires that gun at q: what q's health lost.
	q.health = 100.0
	q.wounds = 0.0
	q.bleeding = 0
	q.cond = Net.COND_OK
	p.slots[p.hand] = gun
	p.ready_tick = 0
	server.combat.use_at(p, server.tick, Vector2(q.st.x, q.st.y))
	var lost: float = 100.0 - q.health
	q.health = 100.0
	q.wounds = 0.0
	return snappedf(lost, 0.01)


func _line(n: int) -> Vector2i:
	## A cell with n walkable cells in a row to its right on one deck (no doors among them).
	var map = server.map
	for y in map.height:
		for x in range(1, map.width - n - 1):
			var ok := true
			for k in n:
				if not map.walkable(x + k, y) or map.door_at(x + k, y) >= 0 or not map.on_ship(y * map.width + x + k):
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _run(ticks: int) -> void:
	for i in ticks:
		server._tick()


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ok    " + what)
	else:
		failed += 1
		print("  FAIL  " + what)
