extends RefCounted
## The ship's supplies in the supply locker: taking, putting back, buying from a
## trader, and counting what is aboard (for the director).
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")
const Sectors := preload("res://src/shared/sectors.gd")
const Items := preload("res://src/shared/items.gd")
const Weapons := preload("res://src/shared/weapons.gd")
const Gear := preload("res://src/shared/gear.gd")

const LOOT: Array[int] = [Net.ITEM_SCRAP, Net.ITEM_ORE, Net.ITEM_DATA]   # (v67) what is found, not bought

var server: GameServer
var _offers := {}                    # what the trader alongside sells: thing -> price ("harden" -> true if it offers that)
var _offers_for := -1                # the place in space (Sectors.key) _offers were made for
var _trade_told := PackedByteArray()
# (v58) a trader has one of each ship gun and upgrade: what was bought from it is gone for good.
# And what we sold one can be bought back from it at the price it paid (the author: a guard against misclicks).
var bought := {}                     # Sectors.key -> Array of things bought there (-1: the shield hardening)
var sold := {}                       # Sectors.key -> Array of [thing, the price paid for it]


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


func _key() -> int:
	return Sectors.key(server.sectors.cell[server.ship.sector])


func deal() -> int:
	## What the trader alongside deals in (Sectors.DEAL_*).
	return int(server.sectors.deal[server.ship.sector]) if server.sectors.deal.size() > server.ship.sector else Sectors.DEAL_ARMS


static func is_ammo(item: int) -> bool:
	return item == Net.ITEM_ROCKET or item == Net.ITEM_EMP_ROCKET or item == Net.ITEM_SHELL \
		or (item >= Net.ITEM_GUN_PARTS and item < Net.ITEM_GUN_PARTS + Weapons.KINDS)


func offers() -> Dictionary:
	## What the trader alongside sells and for how much (empty while we cannot trade).
	## (v58) Every trader has the plain things; what else depends on what it deals
	## in (Sectors.DEAL_*): an arms dealer 3..5 ship guns, tiered by how far out it
	## is, ammunition, and the shield hardening now and then; a black market one or
	## two guns a tier above that, and ammunition; a junk dealer neither, but its
	## things are cheaper. Always the same at the same place, less what was bought there.
	if not can_trade():
		return {}
	var key := _key()
	if key == _offers_for:
		return _offers
	_offers_for = key
	_offers = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([server.space_seed, key, "trader"])
	var kind := deal()
	var gone: Array = bought.get(key, [])
	if server.navigation.sector_kind() == Sectors.STATION:
		# (v62, the author's K3 and K11) a supply station sells only what a trader does not:
		# the module bay's extender (while the bay has not got its third slot) and security robots
		var bay := Gear.item_of(Gear.BAY_SLOT)
		if server.ship.modules.size() < Gear.MODULE_SLOTS_MAX:
			_offers[bay] = Items.price(bay)
		_offers[Net.ITEM_ROBOT] = Items.price(Net.ITEM_ROBOT)
		return _offers
	for item in Items.kept_in_locker():
		if Items.price(item) <= 0 or Weapons.of_item(item) != Weapons.NONE or Items.gear_of(item) != Gear.NONE:
			continue
		if item >= Net.ITEM_GUN_PARTS and item < Net.ITEM_GUN_PARTS + Weapons.KINDS:
			continue                         # (parts come from guns taken apart, not from traders)
		if LOOT.has(item):
			continue                         # (v67) scrap, ore and scan data are found, never sold
		if is_ammo(item):
			if kind != Sectors.DEAL_JUNK:
				_offers[item] = Items.price(item)
		else:
			_offers[item] = maxi(roundi(Items.price(item) * Sectors.JUNK_PRICES), 1) if kind == Sectors.DEAL_JUNK else Items.price(item)
	var far: int = server.sectors.far_from_start(server.ship.sector)
	var guns: Array[int] = []
	if kind == Sectors.DEAL_ARMS:
		for t in Weapons.tiers_for(far, rng.randi_range(3, 5), rng):
			guns.append(t)
	elif kind == Sectors.DEAL_BLACK:
		for i in rng.randi_range(1, 2):
			guns.append(mini(Weapons.top_tier(far) + 1, 3))
	var pool: Array = Weapons.OURS.filter(func(w: int) -> bool: return not Weapons.unique(w))
	for t in guns:
		var choice: Array = pool.filter(func(w: int) -> bool: return Weapons.tier(w) == t)
		if choice.is_empty():
			continue
		var w: int = choice[rng.randi_range(0, choice.size() - 1)]
		pool.erase(w)                        # (no two of one gun at one trader)
		var item := Weapons.item_of(w, Weapons.roll_fx(w, rng))
		if not gone.has(item):
			_offers[item] = Items.price(item) * 3 / 2 if kind == Sectors.DEAL_BLACK else Items.price(item)   # (rare, and dear)
	# (v59, the author's S1: guns and gear modules) crates of ship gear, one of each:
	# an arms dealer 1..2 as tiered as its guns, a black market one a tier above,
	# a junk dealer one, cheap. (The shield hardening is now the top shield generator.)
	var crates := 0
	match kind:
		Sectors.DEAL_ARMS:
			crates = rng.randi_range(1, 2)
		Sectors.DEAL_BLACK, Sectors.DEAL_JUNK:
			crates = 1
	for i in crates:
		var g := Gear.roll(far, rng, kind == Sectors.DEAL_BLACK)
		var item := Gear.item_of(g)
		if gone.has(item) or _offers.has(item):
			continue
		match kind:
			Sectors.DEAL_BLACK:
				_offers[item] = Items.price(item) * 3 / 2
			Sectors.DEAL_JUNK:
				_offers[item] = maxi(roundi(Items.price(item) * Sectors.JUNK_PRICES), 1)
			_:
				_offers[item] = Items.price(item)
	return _offers


func wanted() -> PackedByteArray:
	## (v67, the author's M3) The two things the trader alongside looks for.
	if server.navigation.sector_kind() != Sectors.TRADER:
		return PackedByteArray()
	return server.sectors.wanted(server.ship.sector)


func sell_share(item: int) -> float:
	## What the trader alongside pays for one of that thing, against its price.
	## (v67) What it looks for: WANT_PAYS; scrap, ore and scan data otherwise: LOOT_PAYS.
	if wanted().has(Items.kind_of(item)):
		return Sectors.WANT_PAYS
	if LOOT.has(item):
		return Sectors.LOOT_PAYS
	var shares: Array = Sectors.DEAL_SELL[deal()]
	if Weapons.of_item(item) != Weapons.NONE or Items.gear_of(item) != Gear.NONE:
		return shares[1]                     # (v59: gear goes as guns do)
	return shares[2] if is_ammo(item) else shares[0]


func sell_price(item: int) -> int:
	return Weapons.sell_price(Items.price(item), sell_share(item))


func trade_packet() -> PackedByteArray:
	## (v58) u8 count, pairs of u8 thing, u16 price; u8 TRADE_* flags; u8 deal (Sectors.DEAL_*);
	## u8 % it pays for plain things, for guns, for ammunition and parts; u8 count of things
	## it would sell back, pairs of u8 thing, u16 price.
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
	if now.is_empty():
		return out
	var shares: Array = Sectors.DEAL_SELL[deal()]
	out.append(deal())
	for k in 3:
		out.append(roundi(float(shares[k]) * 100.0))
	var back: Array = sold.get(_key(), [])
	out.append(mini(back.size(), 255))
	for e: Array in back.slice(0, 255):
		var o := out.size()
		out.resize(o + 3)
		out.encode_u8(o, int(e[0]))
		out.encode_u16(o + 1, int(e[1]))
	var w := wanted()                        # (v67) u8 count, the things it looks for (paid at WANT_PAYS)
	out.append(w.size())
	out.append_array(w)
	return out


func can_trade() -> bool:
	## Docked with a trader (or a supply station: it sells its few things), with power for the link.
	return server.powered() and (server.navigation.sector_kind() == Sectors.TRADER or server.navigation.sector_kind() == Sectors.STATION) \
		and server.ship.in_reach


func trader_here() -> bool:
	## (v69, the author's note "the supply station works like a trade post") Selling, buying
	## back, services and hiring are a trader's: a station only sells what offers() lists.
	return can_trade() and server.navigation.sector_kind() == Sectors.TRADER


func aboard(item: int) -> int:
	## Every one of that thing the crew could still use: in the locker, in pockets, on bodies and on the floor.
	var n: int = server.ship.store.get(item, 0)
	for p: Player in server.players:
		if p != null:
			n += p.count(item)
	for things: PackedByteArray in server.floor_things.values():
		n += things.count(item)
	return n


func patches_aboard() -> int:
	return aboard(Net.ITEM_PATCH)


func fuel_aboard() -> int:
	return aboard(Net.ITEM_FUEL)


func find_fuel(cans: int) -> bool:
	## A drifting container of fuel is picked up: the cans go straight into the locker.
	server.ship.store[Net.ITEM_FUEL] = server.ship.fuel() + cans
	tell_store()
	server.chat.say("Радар засёк дрейфующий контейнер. Его подобрали: канистр топлива в шкафу снабжения +%d. Залейте её у двигателя." % cans)
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
			if int(server.ship.store.get(item, 0)) > 0 and (not Items.cargo(item) or Items.carried(item)) and p.add(item, true):
				server.ship.store[item] -= 1
				if Items.carried_gun(item):
					# (v60) a ship gun is carried by hand to its mount (see Mounts)
					server.chat.tell(p, "%s взято. С ним в руке подойдите к орудийной установке в орудийном отсеке и держите E, глядя на неё." % Items.name_of(item))
		Net.STORE_PUT_BACK:
			for at in Net.SLOTS:
				_put_back(p, at)
		Net.STORE_PUT_ONE:
			if item < Net.SLOTS:
				_put_back(p, item)
		Net.STORE_BUY:
			var price: int = offers().get(item, 0)
			if (server.ship.store.has(item) or Items.cargo(item)) and price > 0 and server.ship.credits >= price:
				server.ship.credits -= price
				server.ship.store[item] = int(server.ship.store.get(item, 0)) + 1
				if Weapons.of_item(item) != Weapons.NONE or Items.gear_of(item) != Gear.NONE:
					# (v58) a trader has one of each ship gun (v59: and crate of gear): it is gone once bought
					_gone(item)
					server.chat.say("%s покупает у торговца: %s." % [p.name, Items.name_of(item).to_lower()])
		Net.STORE_SELL:
			var price := sell_price(item)
			if trader_here() and int(server.ship.store.get(item, 0)) > 0 and price > 0:
				server.ship.store[item] -= 1
				server.ship.credits = mini(server.ship.credits + price, 65535)
				var back: Array = sold.get(_key(), [])
				back.append([item, price])
				sold[_key()] = back
				server.chat.say("%s продаёт торговцу: %s, +%d кр." % [p.name, Items.name_of(item).to_lower(), price])
		Net.STORE_BUY_BACK:
			# (v58) what we sold this trader comes back at the price it paid
			var back: Array = sold.get(_key(), []) if trader_here() else []
			for i in range(back.size() - 1, -1, -1):
				var e: Array = back[i]
				if int(e[0]) == item and server.ship.credits >= int(e[1]):
					server.ship.credits -= int(e[1])
					server.ship.store[item] = int(server.ship.store.get(item, 0)) + 1
					back.remove_at(i)
					server.chat.say("%s выкупает назад: %s, %d кр." % [p.name, Items.name_of(item).to_lower(), int(e[1])])
					break
		Net.STORE_HARDEN:
			if offers().has("harden") and not server.ship.hardened and server.ship.credits >= Weapons.SHIELD_HARDEN_PRICE:
				server.ship.credits -= Weapons.SHIELD_HARDEN_PRICE
				server.ship.hardened = true
				_gone(-1)
				server.chat.say("%s покупает закалку щита: теперь щит останавливает и ракеты." % p.name)
		Net.STORE_BUY_FUEL:
			# (v67) fuel straight into the tank
			if trader_here() and server.ship.credits >= Net.PRICE_FUEL and server.ship.tank <= Net.FUEL_MAX - Net.FUEL_LOT:
				server.ship.credits -= Net.PRICE_FUEL
				server.ship.tank += Net.FUEL_LOT
		Net.STORE_BUY_AIR:
			if trader_here() and server.ship.credits >= Net.PRICE_AIR and server.ship.store_air < Net.STORE_AIR_FULL:
				server.ship.credits -= Net.PRICE_AIR
				server.ship.store_air = minf(server.ship.store_air + Net.AIR_LOT, Net.STORE_AIR_FULL)
		Net.STORE_HIRE:
			if trader_here() and server.ship.credits >= Net.PRICE_CREW and server.reserve < Net.RESERVE_MAX and server.over == Net.OVER_NONE:
				server.ship.credits -= Net.PRICE_CREW
				server.reserve += 1
				server.chat.say("%s нанимает у торговца нового члена экипажа. В резерве: %d." % [p.name, server.reserve])
		Net.STORE_PRISONERS:
			if can_trade():
				server.prisons.sell(p)       # (v70, the author's J5) a station or a trader takes our prisoners
		Net.STORE_BUY_HULL:
			if trader_here() and server.ship.credits >= Net.PRICE_HULL and server.ship.hull < server.ship.hull_max and server.over == Net.OVER_NONE:
				server.ship.credits -= Net.PRICE_HULL
				server.ship.hull = mini(server.ship.hull + Net.HULL_LOT, server.ship.hull_max)
	tell_store()


func _gone(item: int) -> void:
	var gone: Array = bought.get(_key(), [])
	gone.append(item)
	bought[_key()] = gone
	_offers_for = -1                         # (made anew without it)


func _put_back(p: Player, at: int) -> void:
	## The thing in that slot goes back into the locker, if the locker keeps it and it is whole.
	## (v58) A ship gun carried in from a wreck goes into the cargo.
	var kind := Items.kind_of(p.slots[at])
	if p.slots[at] != Net.ITEM_NONE and (server.ship.store.has(kind) or Items.cargo(kind)) and Items.whole(p.slots[at]):
		server.ship.store[kind] = int(server.ship.store.get(kind, 0)) + 1
		if Weapons.of_item(kind) != Weapons.NONE or Items.gear_of(kind) != Gear.NONE:
			server.chat.say("%s убирает в трюм: %s." % [p.name, Items.name_of(kind).to_lower()])
		p.slots[at] = Net.ITEM_NONE


func weapons_aboard() -> int:
	## Weapons the crew could lay hands on: in the locker and in its pockets.
	var n: int = server.ship.store.get(Net.ITEM_PISTOL, 0) + server.ship.store.get(Net.ITEM_BATON, 0) \
		+ server.ship.store.get(Net.ITEM_SHOTGUN, 0) + server.ship.store.get(Net.ITEM_STUNNER, 0)
	for q: Player in server.players:
		if q != null and not q.pirate and not q.ally and not q.corpse:
			for v in q.slots:
				if Items.is_weapon(v):
					n += 1
	return n
