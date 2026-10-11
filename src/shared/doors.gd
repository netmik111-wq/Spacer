extends RefCounted
## The state of every door on the ship, and the rule for opening them.
##
## A door is described by one number: the tick from which it can be walked
## through. CLOSED means it is shut. Walking into a shut door starts it
## opening; OPEN_TICKS later it is passable. The server owns the real table;
## a client keeps a copy to draw from and another to predict its own walking,
## and both sides run the same `bump`, so they agree on the tick a door lets
## their character through.
##
## Closing is decided by the server alone (it knows who stands where) and
## reaches clients as an ordinary change.

const CLOSED := 0x7FFFFFFF
const OPEN_TICKS := 6                # 0.3 s from the push to an open door
const HOLD_TICKS := 40               # stays open at least 2 s after it was last used.
                                     # Must stay longer than the stretch of time a client
                                     # re-simulates when it corrects itself (see GameClient).

var ready := PackedInt32Array()      # per door: the tick it is passable from, or CLOSED
var bumped := PackedInt32Array()     # doors pushed since this list was last cleared (the server reads it)


func setup(count: int) -> void:
	ready.resize(count)
	ready.fill(CLOSED)
	bumped.clear()


func copy_from(o: RefCounted) -> void:
	ready = o.ready.duplicate()
	bumped.clear()


func passable(door: int, tick: int) -> bool:
	return tick >= ready[door]


func is_shut(door: int) -> bool:
	return ready[door] == CLOSED


func bump(door: int, tick: int) -> void:
	## Somebody walked into the door on this tick.
	if ready[door] == CLOSED:
		ready[door] = tick + OPEN_TICKS
	bumped.append(door)
