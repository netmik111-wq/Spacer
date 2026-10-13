extends RefCounted
## The state of every door on the ship, and the rule for opening them.
##
## A door is described by one number: the tick from which it can be walked
## through. CLOSED means it is shut. Walking into a shut door starts it
## opening; a little later it is passable. The server owns the real table;
## a client keeps a copy to draw from and another to predict its own walking,
## and both sides run the same `bump`, so they agree on the tick a door lets
## their character through.
##
## Two things can get in the way, and both are part of the rule, so clients
## predict them too:
##  - every door has an emergency shutter. When the pressure on its two sides
##    differs too much the server drops it (`locked`), and walking into the
##    door does nothing until the difference is gone or somebody forces it;
##  - without power (`manual`) a door is pushed open by hand, which is slow.
## A door of an airlock chamber also stays shut while the other door of the
## same chamber is not (`partner`), so the chamber never opens both ways.
## Two more things can go wrong with a door; the server decides them and they
## reach clients with the rest:
##  - a door can jam open (`jammed`): it stays open until somebody mends it;
##  - its shutter can fail (`faulty`): it stays as it is, up or down, whatever
##    the pressure does, until somebody mends it.
##
## Closing is decided by the server alone (it knows who stands where) and
## reaches clients as an ordinary change.

const CLOSED := 0x7FFFFFFF
const OPEN_TICKS := 6                # 0.3 s from the push to an open door
const MANUAL_OPEN_TICKS := 30        # 1.5 s when it has to be pushed open by hand
const HOLD_TICKS := 40               # stays open at least 2 s after it was last used.
                                     # Must stay longer than the stretch of time a client
                                     # re-simulates when it corrects itself (see GameClient).

var ready := PackedInt32Array()      # per door: the tick it is passable from, or CLOSED
var locked := PackedByteArray()      # per door: 1 = its emergency shutter is down
var jammed := PackedByteArray()      # per door: 1 = stuck open
var faulty := PackedByteArray()      # per door: 1 = its emergency shutter no longer works by itself
var partner := PackedInt32Array()    # per door: the other door of its airlock, or -1 (set from ShipMap.door_partner)
var manual := false                  # the ship has no power: doors are opened by hand
var bumped := PackedInt32Array()     # doors pushed since this list was last cleared (the server reads it)


func setup(count: int) -> void:
	ready.resize(count)
	ready.fill(CLOSED)
	locked.resize(count)
	locked.fill(0)
	jammed.resize(count)
	jammed.fill(0)
	faulty.resize(count)
	faulty.fill(0)
	manual = false
	partner.resize(count)
	partner.fill(-1)
	bumped.clear()


func copy_from(o: RefCounted) -> void:
	ready = o.ready.duplicate()
	locked = o.locked.duplicate()
	jammed = o.jammed.duplicate()
	faulty = o.faulty.duplicate()
	partner = o.partner
	manual = o.manual
	bumped.clear()


func flags(door: int) -> int:
	## The door's troubles as one byte, the way they travel over the network.
	return locked[door] | (jammed[door] << 1) | (faulty[door] << 2)


func set_flags(door: int, value: int) -> void:
	locked[door] = value & 1
	jammed[door] = (value >> 1) & 1
	faulty[door] = (value >> 2) & 1


func open_ticks() -> int:
	## How long a door takes to open right now.
	return MANUAL_OPEN_TICKS if manual else OPEN_TICKS


func passable(door: int, tick: int) -> bool:
	return tick >= ready[door]


func is_shut(door: int) -> bool:
	return ready[door] == CLOSED


func is_sealed(door: int) -> bool:
	## Shut, with its emergency shutter down: walking into it does nothing.
	return ready[door] == CLOSED and locked[door] == 1


func held_by_partner(door: int) -> bool:
	## A door of an airlock stays shut while the other one is not.
	return partner[door] >= 0 and ready[partner[door]] != CLOSED


func bump(door: int, tick: int) -> void:
	## Somebody walked into the door on this tick.
	if ready[door] == CLOSED:
		if locked[door] == 1 or held_by_partner(door):
			return
		ready[door] = tick + open_ticks()
	bumped.append(door)
