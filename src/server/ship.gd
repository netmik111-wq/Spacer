extends RefCounted
## A ship in the world, as one object with its own network id: the crew's own
## ship, or another one alongside (a derelict, a pirate ship). Server only.
##
## Everything the server tells clients about a ship carries its id (see
## Net.S_SHIPS and the packets after it), so that one day there can be more
## than one crewed ship in the world. For now the crew's ship is always
## Net.CREW_SHIP, and another ship alongside gets a fresh id each time one comes.
##
## The crew's ship keeps here what belongs to it alone: where it is in space
## and where it is going, its power, what is broken on it, its airlock pumps,
## its supplies and money, and the strength of its hull. Another ship alongside
## only has the plain facts (what it is, where it lies in the grid, docked or not);
## the rest of it lives in Derelict.

const Net := preload("res://src/shared/net.gd")
const ShipMap := preload("res://src/shared/ship_map.gd")
const Sectors := preload("res://src/shared/sectors.gd")

var id := Net.CREW_SHIP
var kind := Net.SHIP_CREW             # Net.SHIP_*
var name := ""
var at := Vector2i.ZERO               # the corner of its drawing in the grid
var docked := false                   # (another ship) right up against our airlock
var layout := 0                       # (another ship) its drawing: its number in Net.OTHER_MAPS

# where it is
var sector := 0                       # the sector it is in: its number in the window GameServer.sectors holds
var jump_to := Net.NO_SECTOR          # the sector it is jumping to, if any
var jump_tick := 0                    # the tick the jump lands on
var drive_ready := 0                  # the tick from which the drive can be used again
var pos := Vector2.ZERO               # where it is inside its sector (see Sectors.SPAN)
var dest := Vector2.ZERO              # where it is heading
var moving := false
var in_reach := false                 # inside the sector's meteor stream, or docked at its station or trader

# its machines
var map: ShipMap                      # the grid it lies in (the crew's ship: the cells of `map` that are not another ship)
var broken := {}                      # things out of order (bridge consoles, the engine, the air plant, guns): wall cell -> true
var pumps := {}                       # airlock pumps at work: wall cell -> Systems.PUMP_OUT or PUMP_IN
var power_out_until := 0              # a passing power failure lasts until this tick
var power_told := true                # the state of the power as clients were last told
var backup_told := false              # (v61) and of the bridge's backup SMES

# its supplies, kept in the supply locker
var store := {}                       # thing (Net.ITEM_*) -> how many
var store_air := 0.0                  # air the air plant still has to give, in cells' worth
var earned := 0                      # (v75, the author's E1) every credit that came in, for the run's summary
var purse = null                     # (v85, the author's FS7) another ship of our fleet whose credits these are (one purse)
var _credits := 0
var credits: int:
	get:
		return purse.credits if purse != null else _credits
	set(v):
		if purse != null:
			purse.credits = v
			return
		if v > _credits:
			earned += v - _credits
		_credits = v
var tank := float(Net.FUEL_START)     # (v67) fuel in the tank, in units (Net.FUEL_MAX at most)
var jump_cost := 40                   # (v67) what a lane jump burns from it (Outfit sets it by the engine's tier)
var store_told := PackedByteArray()   # the supplies as clients were last told
var hull := Net.HULL_MAX              # strength of the hull, 0..hull_max
var hull_max := Net.HULL_MAX          # (v63) its top strength: Net.HULL_MAX, less what the easy mode took for each wreck

# its guns and shield (see Gunnery, Weapons)
var mounts := PackedByteArray()       # per gun mount (ShipMap.guns): the weapon on it (Weapons.*; NONE = empty)
var mount_fx := PackedByteArray()     # (v58) per gun mount: the effect its tier 3 gun carries (Weapons.FX_*)
var armed := PackedByteArray()        # per gun mount: 1 = it draws power and charges
var shield := 0.0                     # the shield, 0..Weapons.SHIELD_FULL
var lights_off := false              # (v68) the lights' breaker on the power panel is off (Power.breaker)
var shield_on := true                 # the shield generator is switched on (it draws power)
var hardened := false                 # the shield stops rockets too (the rare upgrade from a trader)
var jammed := {}                      # a gun or the shield generator put out by ion or EMP: wall cell -> the tick it is back
var guard := 0                        # (v58) the point defence in its own mount (Weapons.GUARD, or NONE)
var guard_armed := false              # it draws power and charges
var armour := 0.0                     # (v58) the share of kinetic shells its armour turns aside (ours: by its armour plating, see Outfit)
# (v59) its gear (see Gear, Outfit)
var gear := PackedByteArray([1, 1, 1, 1, 1])   # per Gear.SYS_*: the tier of that system (1 = built in)
var modules := PackedByteArray([0, 0])      # per slot of the module bay: the crate in it (Gear.*; NONE = empty)
var phase_ready := 0                  # the tick its phase drive is charged again


func engine_down() -> bool:
	## It has an engine and it is out of order: no way under its own power, no jump.
	if map.engine.is_empty():
		return false
	for cell: int in map.engine.keys():
		if not broken.has(cell):
			return false
	return true


func powered(tick: int) -> bool:
	## (Before v61, and still for a ship with no SMES; the crew's ship asks Power.on.)
	## The engine is what powers the ship. Without it every system stands still
	## (none of them breaks): the bridge consoles, the air plant, the oxygen
	## stations, the emergency shutters; doors have to be pushed open by hand.
	## The power can also fail for a few seconds by itself and come back.
	return not engine_down() and tick >= power_out_until


func fuel() -> int:
	## Cans of fuel in the supply locker (v67: each holds Net.CAN_FUEL; a jump burns from the tank, see `tank`).
	return int(store.get(Net.ITEM_FUEL, 0))


func can_jump(long_jump: bool = false) -> bool:
	## (v67) Is there fuel in the tank for a jump (the long jump burns twice as much)?
	return tank + 0.001 >= jump_cost * (Sectors.EXIT_FUEL if long_jump else 1)


# ---------------------------------------------------------------- packets
# Each begins with the packet's kind and the ship's id.

func _head(kind_of_packet: int, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	out.encode_u8(0, kind_of_packet)
	out.encode_u16(1, id)
	return out


func entry() -> PackedByteArray:
	## Its line in Net.S_SHIPS.
	var name_bytes := name.to_utf8_buffer()
	var out := PackedByteArray()
	out.resize(10)
	out.encode_u16(0, id)
	out.encode_u8(2, kind)
	out.encode_u8(3, 1 if docked else 0)
	out.encode_s16(4, at.x)
	out.encode_s16(6, at.y)
	out.encode_u8(8, layout)
	out.encode_u8(9, name_bytes.size())
	out.append_array(name_bytes)
	return out


func helm_packet(tick: int) -> PackedByteArray:
	var out := _head(Net.S_HELM, 14)
	out.encode_s16(3, roundi(pos.x * 10.0))
	out.encode_s16(5, roundi(pos.y * 10.0))
	out.encode_u8(7, 1 if moving else 0)
	out.encode_u8(8, roundi(dest.x))
	out.encode_u8(9, roundi(dest.y))
	out.encode_u32(10, tick)
	return out


func nav_packet() -> PackedByteArray:
	var out := _head(Net.S_NAV, 13)
	out.encode_u8(3, sector)
	out.encode_u8(4, jump_to)
	out.encode_u32(5, jump_tick)
	out.encode_u32(9, drive_ready)
	return out


func devices_packet() -> PackedByteArray:
	## What is broken, then which airlock pumps are at work and which way.
	var out := _head(Net.S_DEVICES, 3)
	out.append(broken.size())
	for cell: int in broken.keys():
		out.append(cell & 0xFF)
		out.append(cell >> 8)
	out.append(pumps.size())
	for cell: int in pumps.keys():
		out.append(cell & 0xFF)
		out.append(cell >> 8)
		out.append(int(pumps[cell]))
	return out


func power_packet() -> PackedByteArray:
	var out := _head(Net.S_POWER, 6)
	out.encode_u8(3, 1 if power_told else 0)
	out.encode_u8(4, 1 if backup_told else 0)
	out.encode_u8(5, 0 if lights_off else 1)
	return out


func store_packet() -> PackedByteArray:
	var out := _head(Net.S_STORE, 8)
	out.encode_u16(3, roundi(store_air * 10.0))
	out.encode_u16(5, credits)
	out.encode_u8(7, store.size())
	for item: int in store.keys():
		var o := out.size()
		out.resize(o + 3)
		out.encode_u8(o, item)
		out.encode_u16(o + 1, store[item])
	var o := out.size()                   # (v67) the tank
	out.resize(o + 5)
	out.encode_u16(o, floori(tank))
	out.encode_u8(o + 2, jump_cost)
	out.encode_u16(o + 3, Net.FUEL_MAX)
	return out
