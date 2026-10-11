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
var manual := false                  # the ship has no power: doors are opened by hand
var bumped := PackedInt32Array()     # doors pushed since this list was last cleared (the server reads it)


func setup(count: int) -> void:
	ready.resize(count)
	ready.fill(CLOSED)
	locked.resize(count)
	locked.fill(0)
	manual = false
	bumped.clear()


func copy_from(o: RefCounted) -> void:
	ready = o.ready.duplicate()
	locked = o.locked.duplicate()
	manual = o.manual
	bumped.clear()


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


func bump(door: int, tick: int) -> void:
	## Somebody walked into the door on this tick.
	if ready[door] == CLOSED:
		if locked[door] == 1:
			return
		ready[door] = tick + open_ticks()
	bumped.append(door)
