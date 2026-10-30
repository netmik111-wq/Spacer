extends RefCounted
## (v99, the author: "simple monsters on the asteroids. Like centipedes but they have 10 legs and look like a
## praying mantis; melee damage 30; they move like characters and have a small leap toward an enemy when they
## have a 1 tile gap") The mantises of the campaign's made asteroids. My picks on the v99 page (all A):
##   M1  MANTIS_HEALTH, chitin that takes CHITIN off bullets and pellets (lasers and plasma go through whole)
##   M2  a blow of BLOW_DAMAGE every BLOW_SECONDS, a blow by kind (a vest and a helmet take their share)
##   M3  one empty cell between it and its target (straight or on a slant): it leaps over it in LEAP_TICKS and
##       strikes at once, then waits LEAP_SECONDS to leap again
##   M4  walks as people do, needs no air; asleep deep in the caves until it sees somebody (or is hurt)
##   M5  goes after one anywhere, through our airlock too: one left aboard stays until killed
##   M6  0-2 an asteroid (half of the caved ones), one more each cluster down the road, MANTISES_MAX at most
##       (Derelict); its body stays, and a claw («Коготь богомола») can be cut off it
## A mantis is a pirate Player with `monster` (so our people and robots fight it, and pirates leave it be),
## its claws (Net.ITEM_CLAWS) in its hand: Pirates.think walks it and strikes with them. Server only.

const Net := preload("res://src/shared/net.gd")
const Mover := preload("res://src/shared/mover.gd")
const Player := preload("res://src/server/player.gd")

const MANTIS_HEALTH := 80.0
const CHITIN := 0.8                  # the share of a bullet's or a pellet's wound it takes
const BLOW_DAMAGE := 30              # as Items' claws ("blow")
const BLOW_SECONDS := 1.2            # as Items' claws ("pace" x Combat.BLOW_TICKS)
const LEAP_TICKS := 4                # 0.2 s in the air
const LEAP_SECONDS := 4.0
const NAME := "Богомол"

var server: GameServer
var count := 0
var leaps := 0                       # (tests) how many leaps were made
var leaps_on := true                 # (tests may turn them off)


func setup(p_server: GameServer) -> void:
	server = p_server
	count = 0
	leaps = 0


func spawn(x: int, y: int) -> Player:
	## A mantis in that cell, asleep: it holds its place until it has somebody to go after.
	count += 1
	var p: Player = server.crew.alloc("%s %d" % [NAME, count])
	p.pirate = true
	p.monster = true
	p.colour = Net.MANTIS_COLOUR
	p.worn.fill(Net.ITEM_NONE)
	p.slots.fill(Net.ITEM_NONE)
	p.st.place(x, y)
	p.st.facing = server.rng.randi_range(1, 4)
	p.toughness = Net.HEALTH_FULL / MANTIS_HEALTH   # (health is 100 less the wounds: a wound weighs more instead)
	p.add(Net.ITEM_CLAWS, true)
	p.stays = true
	server.crew.announce_join(p, null)
	return p


func leap(p: Player, target: Player) -> bool:
	## (M3) One empty cell between it and its target, straight or on a slant, and its legs ready: it leaps
	## over that cell to the target's side and strikes as it lands. True if it leapt.
	if not leaps_on or p.st.cd > 1 or server.tick < p.leap_ready or p.st.prone or p.cond != Net.COND_OK:
		return false
	var map := server.map
	var dx := target.st.x - p.st.x
	var dy := target.st.y - p.st.y
	if map.deck_of(target.st.y) != map.deck_of(p.st.y) or maxi(absi(dx), absi(dy)) != 2 \
			or (absi(dx) == 1 or absi(dy) == 1):
		return false                         # only two cells off along a line: straight or a true slant
	var mid := Vector2i(p.st.x + signi(dx), p.st.y + signi(dy))
	if not map.walkable(mid.x, mid.y) or map.door_at(mid.x, mid.y) >= 0 or _taken(mid, p):
		return false
	if signi(dx) != 0 and signi(dy) != 0 and not Mover.slant_open(map, p.st.x, p.st.y, signi(dx), signi(dy)):
		return false                         # a slant past a wall's corner: no
	if map.held.has(mid.y * map.width + mid.x):
		return false
	var from_q := Vector2i(p.st.qx(), p.st.qy())
	p.st.place(mid.x, mid.y)
	p.st.fx = from_q.x
	p.st.fy = from_q.y
	p.st.move_tick = server.tick
	p.st.span = LEAP_TICKS
	p.st.cd = LEAP_TICKS
	p.st.dir = Net.DIR_NONE
	p.st.facing = Net.dir_of(signi(dx), signi(dy))
	p.leap_ready = server.tick + roundi(LEAP_SECONDS * Net.TICK_HZ)
	p.ready_tick = server.tick + LEAP_TICKS      # the blow comes as it lands
	p.self_dirty = true
	leaps += 1
	server.chat.sound(Net.SOUND_SWING, p.st.x, p.st.y, p.slot)
	return true


func _taken(c: Vector2i, by: Player) -> bool:
	for q: Player in server.players:
		if q != null and q != by and not q.in_shuttle and q.st.x == c.x and q.st.y == c.y and not q.corpse and q.cond != Net.COND_DEAD:
			return true
	return false


func dies(p: Player) -> void:
	## (M6) A dead mantis: its claws are no thing to take, but one can be cut off its body.
	p.slots.fill(Net.ITEM_NONE)
	p.add(Net.ITEM_MANTIS_CLAW)
