extends RefCounted
## What thin air does to a body. Server only.
##
## Health runs from 100 (unhurt) through 0 (unconscious) to -100 (dead).
## Two things hurt: not enough air to breathe, and, lower still, pressure too
## low for the body itself. In breathable air a conscious person slowly gets
## better; an unconscious one comes round more slowly still.
##
## All rates are per second and are the dials for how cruel space is.

const Net := preload("res://src/shared/net.gd")

const BREATH_MIN := 0.76             # below this share of normal pressure there is too little oxygen
const PRESSURE_MIN := 0.20           # below this the low pressure itself injures
const SUFFOCATION := 3.0             # health lost per second with nothing to breathe
const DECOMPRESSION := 2.0           # health lost per second in a vacuum, on top of that
const RECOVERY := 1.0                # health regained per second in good air, while conscious
const CRIT_RECOVERY := 0.5           # the same while unconscious
const WAKE_AT := 10.0                # an unconscious person comes round at this much health
const DYING := 0.5                   # (v75) health lost per second by one out cold whose wounds leave no health to come back to
const TANK_SECONDS := 120.0          # how long a full suit tank lasts with the supply on
const REFILL_SECONDS := 3.0          # how long an oxygen station takes to fill an empty tank


static func harm(air: float) -> float:
	## Health lost per second in air of this pressure (1.0 = normal).
	var loss := 0.0
	if air < BREATH_MIN:
		loss += SUFFOCATION * (1.0 - air / BREATH_MIN)
	if air < PRESSURE_MIN:
		loss += DECOMPRESSION * (1.0 - air / PRESSURE_MIN)
	return loss


static func advance(health: float, cond: int, air: float, seconds: float, wounds: float = 0.0) -> float:
	## Health after `seconds` in that air. Good air only gives back what thin air
	## took: `wounds` (cuts, bruises, bullet holes) do not close by themselves,
	## so health does not climb back above HEALTH_FULL - wounds.
	if cond == Net.COND_DEAD:
		return health
	var loss := harm(air)
	if loss > 0.0:
		return maxf(health - loss * seconds, Net.HEALTH_DEAD)
	var ceiling := Net.HEALTH_FULL - wounds
	if cond == Net.COND_CRIT and ceiling <= 0.0:
		# (v75, found by the playthrough: a captain lay at -5 for good, neither waking nor dying)
		# wounds this deep kill slowly unless they are treated (an autodoc, a medkit)
		return maxf(health - DYING * seconds, Net.HEALTH_DEAD)
	if health < ceiling:
		return minf(health + (RECOVERY if cond == Net.COND_OK else CRIT_RECOVERY) * seconds, ceiling)
	return health


static func condition(health: float, cond: int) -> int:
	## The condition that goes with this health, given what it was.
	if cond == Net.COND_DEAD or health <= Net.HEALTH_DEAD:
		return Net.COND_DEAD
	if health <= 0.0:
		return Net.COND_CRIT
	if cond == Net.COND_CRIT and health < WAKE_AT:
		return Net.COND_CRIT
	return Net.COND_OK
