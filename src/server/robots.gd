extends RefCounted
## (v62, the author's K11: "the difference between robots and bots, we can work
## with that") Our security robots. Server only.
##
## A security robot is bought in a crate (Net.ITEM_ROBOT) and kept in the supply
## locker like a crate of gear. Set down on a free floor cell next to its
## carrier (a click there, or "use" facing it), it switches on and guards that
## place: it goes after any pirate it sees, the way pirates go after us (it is
## moved by the same mind, Pirates.think, with the sides turned round: see
## Pirates.foe), and goes back to its place when none is left in sight. It is a
## machine: it needs no air, wears nothing, takes wounds harder than a person
## (TOUGHNESS) and does no work. It is not crew (Player.ally): it fills no crew
## place, counts for nothing where the crew is counted, and can be ordered by
## nobody. At most MAX_ABOARD stand aboard; a saved game puts those still
## standing back into the locker in their crates.
## Part of the server: GameServer keeps one of these and calls into it.

const Net := preload("res://src/shared/net.gd")
const Player := preload("res://src/server/player.gd")

const MAX_ABOARD := 2
const TOUGHNESS := 1.4               # it takes this share of a wound: a robot is "70 health" against a person's 100
const MAGS := 2                      # magazines it starts with...
const RELOAD_SECONDS := 20           # ... and it makes one more this often while it has none

var server: GameServer
var count := 0                       # robots switched on so far (for their names)


func setup(p_server: GameServer) -> void:
	server = p_server
	count = 0


func aboard() -> Array:
	## Our robots still standing (not broken).
	var out: Array = []
	for q: Player in server.players:
		if q != null and q.ally and not q.corpse and q.cond != Net.COND_DEAD:
			out.append(q)
	return out


func can_set(p: Player, cell: Vector2i) -> String:
	## "" if `p` may set its robot down there; otherwise why not.
	var map = server.map
	if p.in_hand() != Net.ITEM_ROBOT:
		return "-"
	if absi(cell.x - p.st.x) > 1 or absi(cell.y - p.st.y) > 1 or cell == Vector2i(p.st.x, p.st.y) \
			or map.deck_of(cell.y) != map.deck_of(p.st.y):
		return "Робота ставят на соседнюю клетку."
	var c: int = cell.y * map.width + cell.x
	if not map.walkable(cell.x, cell.y) or map.door_at(cell.x, cell.y) >= 0 or not map.on_ship(c):
		return "Сюда робота не поставить: нужен свободный пол на нашем корабле."
	for q: Player in server.players:
		if q != null and q.st.x == cell.x and q.st.y == cell.y:
			return "Здесь кто-то есть."
	if aboard().size() >= MAX_ABOARD:
		return "На борту уже %d охранных робота: больше не нужно." % MAX_ABOARD
	return ""


func deploy(p: Player, cell: Vector2i) -> bool:
	## Sets the robot in `p`'s hand down there: it switches on.
	var why := can_set(p, cell)
	if why != "":
		if why != "-":
			server.chat.tell(p, why)
		return false
	p.slots[p.hand] = Net.ITEM_NONE
	var r := spawn(cell.x, cell.y)
	var room: int = server.map.room_of[cell.y * server.map.width + cell.x]
	server.chat.say("%s ставит охранного робота: %s включается и охраняет %s." % [p.name, r.name,
		"этот отсек" if room >= 0 else "это место"])
	return true


func spawn(x: int, y: int) -> Player:
	count += 1
	var r: Player = server.crew.alloc("Охранный робот %d" % count)
	r.robot = true
	r.ally = true
	r.colour = Net.OUR_ROBOT_COLOUR
	r.worn.fill(Net.ITEM_NONE)
	r.toughness = TOUGHNESS
	r.st.access = Net.ACCESS_ALL | Net.ACCESS_OURS
	r.st.place(x, y)
	r.hold = y * server.map.width + x
	r.add(Net.ITEM_PISTOL + Net.PISTOL_ROUNDS, true)
	for i in MAGS:
		r.add(Net.ITEM_MAG)
	server.crew.announce_join(r, null)
	return r


func tick() -> void:
	if server.tick % (RELOAD_SECONDS * Net.TICK_HZ) != 0:
		return
	for r: Player in aboard():
		if not r.slots.has(Net.ITEM_MAG):
			r.add(Net.ITEM_MAG)


func pack_up() -> int:
	## (saving) Our robots still standing, counted back into the locker as crates.
	return aboard().size()
