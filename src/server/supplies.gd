extends RefCounted
## The ship's supplies in the supply locker: taking, putting back, buying from a
## trader, and counting what is aboard (for the director).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")

var server: GameServer
var _offers := {}                    # what the trader alongside sells: thing -> price ("harden" -> true if it offers that)
var _offers_for := -1                # the place in space (Sectors.key) _offers were made for
var _trade_told := PackedByteArray()


func setup(p_server: GameServer) -> void:
	server = p_server


func tell_store() -> void:
	## Tells everyone the ship's supplies, if they changed since the last time.
	var now := server.ship.store_packet()
	if now != server.ship.store_told:
		server.ship.store_told = now
		server.to_all(now)
	var trade := trade_packet()
	if trade != _trade_told:
		_trade_told = trade
		server.to_all(trade)


func offers() -> Dictionary:
	## What the trader alongside sells and for how much (empty while we cannot trade).
	## Every trader has every plain thing and rockets; ship weapons only TRADER_WEAPONS
	## kinds of them, and the shield hardening rarely: always the same at the same place.
	if not can_trade():
		return {}
	var key := Sectors.key(server.sectors.cell[server.ship.sector])
	if key == _offers_for:
		return _offers
	_offers_for = key
	_offers = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([server.space_seed, key, "trader"])
	var guns: Array = []
	for item in Items.kept_in_locker():
		if Items.price(item) <= 0:
			continue
		if Weapons.of_item(item) != Weapons.NONE:
			guns.append(item)
		else:
			_offers[item] = Items.price(item)
	for k in mini(Weapons.TRADER_WEAPONS, guns.size()):
		var pick: int = guns.pop_at(rng.randi_range(0, guns.size() - 1))
		_offers[pick] = Items.price(pick)
	if rng.randf() < Weapons.HARDEN_CHANCE:
		_offers["harden"] = true
	return _offers


func trade_packet() -> PackedByteArray:
	var now := offers()
	var out := PackedByteArray([Net.S_TRADE, 0])
	for item in now.keys():
		if item is int:
			var o := out.size()
			out.resize(o + 3)
			out.encode_u8(o, item)
			out.encode_u16(o + 1, now[item])
			out[1] += 1
	out.append(Net.TRADE_HARDEN if now.has("harden") else 0)
	return out


func can_trade() -> bool:
	## Docked with a trader, with power for the link.
	return server.powered() and server.navigation.sector_kind() == Sectors.TRADER and server.ship.in_reach


func patches_aboard() -> int:
	## Every patch the crew could still use: in the locker, in pockets, on bodies and on the floor.
	var n: int = server.ship.store.get(Net.ITEM_PATCH, 0)
	for p: Player in server.players:
		if p != null:
			n += p.count(Net.ITEM_PATCH)
	for things: PackedByteArray in server.floor_things.values():
		n += things.count(Net.ITEM_PATCH)
	return n


func fuel_aboard() -> int:
	## Every can of fuel on board, wherever it is: in the locker, in pockets, on bodies and on the floor.
	var n := server.ship.fuel()
	for p: Player in server.players:
		if p != null:
			n += p.count(Net.ITEM_FUEL)
	for things: PackedByteArray in server.floor_things.values():
		n += things.count(Net.ITEM_FUEL)
	return n


func find_fuel(cans: int) -> bool:
	## A drifting container of fuel is picked up: the cans go straight into the locker.
	server.ship.store[Net.ITEM_FUEL] = server.ship.fuel() + cans
	tell_store()
	server.chat.say("Радар засёк дрейфующий контейнер. Его подобрали: в шкафу снабжения %d канистры топлива." % cans)
	return true


func store_asked(p: Player, action: int, item: int) -> void:
	## A player at the supply locker takes something, puts it back, or buys from a trader.
	if p.cond != Net.COND_OK:
		return
	var ahead := server.map.use_ahead(p.st.x, p.st.y, p.st.facing)
	if ahead < 0 or not server.map.locker.has(ahead):
		return
	match action:
		Net.STORE_TAKE:
			if int(server.ship.store.get(item, 0)) > 0 and not Items.cargo(item) and p.add(item, true):
				server.ship.store[item] -= 1
		Net.STORE_PUT_BACK:
			for at in Net.SLOTS:
				_put_back(p, at)
		Net.STORE_PUT_ONE:
			if item < Net.SLOTS:
				_put_back(p, item)
		Net.STORE_BUY:
			var price: int = offers().get(item, 0)
			if server.ship.store.has(item) and price > 0 and server.ship.credits >= price:
				server.ship.credits -= price
				server.ship.store[item] += 1
		Net.STORE_SELL:
			var price := Weapons.sell_price(Items.price(item))
			if can_trade() and int(server.ship.store.get(item, 0)) > 0 and price > 0:
				server.ship.store[item] -= 1
				server.ship.credits = mini(server.ship.credits + price, 65535)
				server.chat.say("%s продаёт торговцу: %s, +%d кр." % [p.name, Items.name_of(item).to_lower(), price])
		Net.STORE_HARDEN:
			if offers().has("harden") and not server.ship.hardened and server.ship.credits >= Weapons.SHIELD_HARDEN_PRICE:
				server.ship.credits -= Weapons.SHIELD_HARDEN_PRICE
				server.ship.hardened = true
				server.chat.say("%s покупает закалку щита: теперь щит останавливает и ракеты." % p.name)
		Net.STORE_BUY_AIR:
			if can_trade() and server.ship.credits >= Net.PRICE_AIR and server.ship.store_air < Net.STORE_AIR_FULL:
				server.ship.credits -= Net.PRICE_AIR
				server.ship.store_air = minf(server.ship.store_air + Net.AIR_LOT, Net.STORE_AIR_FULL)
		Net.STORE_HIRE:
			if can_trade() and server.ship.credits >= Net.PRICE_CREW and server.reserve < Net.RESERVE_MAX and server.over == Net.OVER_NONE:
				server.ship.credits -= Net.PRICE_CREW
				server.reserve += 1
				server.chat.say("%s нанимает у торговца нового члена экипажа. В резерве: %d." % [p.name, server.reserve])
		Net.STORE_BUY_HULL:
			if can_trade() and server.ship.credits >= Net.PRICE_HULL and server.ship.hull < Net.HULL_MAX and server.over == Net.OVER_NONE:
				server.ship.credits -= Net.PRICE_HULL
				server.ship.hull = mini(server.ship.hull + Net.HULL_LOT, Net.HULL_MAX)
	tell_store()


func _put_back(p: Player, at: int) -> void:
	## The thing in that slot goes back into the locker, if the locker keeps it and it is whole.
	var kind := Items.kind_of(p.slots[at])
	if p.slots[at] != Net.ITEM_NONE and server.ship.store.has(kind) and Items.whole(p.slots[at]):
		server.ship.store[kind] += 1
		p.slots[at] = Net.ITEM_NONE


func weapons_aboard() -> int:
	## Weapons the crew could lay hands on: in the locker and in its pockets.
	var n: int = server.ship.store.get(Net.ITEM_PISTOL, 0) + server.ship.store.get(Net.ITEM_BATON, 0)
	for q: Player in server.players:
		if q != null and not q.pirate and not q.corpse:
			for v in q.slots:
				if Items.is_weapon(v):
					n += 1
	return n
