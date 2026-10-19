extends RefCounted
## Everything the server keeps about one character: a connected player or a bot.

const Mover := preload("res://src/shared/mover.gd")
const Net := preload("res://src/shared/net.gd")
const Items := preload("res://src/shared/items.gd")

var slot := 0
var peer: ENetPacketPeer = null      # null for bots
var name := ""
var colour := 0
var bot := false
var corpse := false                  # a body left behind: it only lies there
var admin := false                   # may use the admin panel (see Admin)
var host := false                    # is the hosting player (proved with the server's secret text)
var pirate := false                  # an enemy the server moves (see Pirates)
var robot := false                   # (v62) a machine (an assault drone, a guard, our security robot): it needs no air
var ally := false                    # (v62) our security robot: the server moves it against pirates; it is not crew
var toughness := 1.0                 # (v62) the share of a wound's damage it takes (heavy armour: half)
var ready_tick := 0                  # its hands are free again from this tick (after a shot, a blow, a reload)
var history := PackedVector2Array()  # where it was drawn on each of the last HISTORY ticks (see Combat.place_at)
# what a pirate has in mind (see Pirates)
var ai_target := -1                  # the slot of the one it is after
var ai_goal := Vector2i(-1, -1)      # where it is going
var ai_step := 0                     # its next step: a direction, or -1 for the ladder underfoot
var ai_plan_tick := 0                # when it last worked out its way
var ai_fire_tick := 0                # when it may shoot next
var st := Mover.State.new()

var inputs: Array = []               # queued input changes, oldest first: [apply tick, direction, seq]
var last_seq := 0                    # last input change applied, echoed back to the client

var view_cx := -100                  # chunk this client's view is centred on (the row is counted inside its deck)
var view_cy := -100
var known := {}                      # its client's characters: slot -> place and look as last sent (see Replication)
var vis_a := PackedInt64Array()      # per slot: whether it saw that one, and on what (see Replication._seen_now)
var vis_b := PackedInt64Array()
var vis_r := PackedByteArray()
var vis_until := PackedInt32Array()  # per slot: it counts as seen until this tick

var wounds := 0.0                    # of the health lost, what wounds took: it does not come back by itself
var treating := -1                   # the slot of the one it is treating with a first-aid kit (-1 = nobody)
var health := 100.0                  # 100 = unhurt; 0 and below = unconscious; Net.HEALTH_DEAD = dead
var cond := 0                        # Net.COND_*
var tank := 1.0                      # oxygen left in the suit's tank, 1.0 = full
var supply := false                  # breathing from the tank instead of the air around
var slots := PackedByteArray()       # what it carries: one item per slot (Net.ITEM_*), Net.SLOTS of them
var slots_sent := PackedByteArray()  # the same as last told to its client (with what it wears after)
var worn := PackedByteArray()        # what it wears (Net.WEAR_*); a worn suit is ITEM_SUIT and its oxygen is `tank`
var look_sent := -1                  # how it was last shown dressed (see Net.LOOKS)
var hand := 0                        # the slot whose thing is in the hand (its player chooses it)
var dragging := -1                   # the slot of the lying character it hauls along (-1 = nobody)
var dragged_by := -1                 # the slot of whoever hauls it
var searching := -1                  # the slot of the lying character whose pockets it is going through
var search_sent := PackedByteArray() # those pockets as last told to its client
var want_kind := 0                   # a press of "search" or "drag" waiting for its tick (0 = none)
var want_id := 0
var want_tick := 0
var using := false                   # holds the "use" key
var work := 0                        # ticks spent on the thing in front of it (mending a hole)
var work_cell := -1
var bench := PackedByteArray()      # (v58) the job at the workbench: [BENCH_*, thing], empty = none
var work_total := 1                  # ticks the job in hand takes (the progress shown is work / work_total)
var vitals_sent := -1                # health, tank, supply and work as last told to the client, packed
var died_tick := 0
var heard: Array = []                # sounds sent to it, [kind, x, y] (kept only for tests: see GameServer.keep_heard)
var steps := 0                       # steps taken (every other one is heard)
var climbs := 0                      # times it has gone up or down a ladder (for tests)
var climb_tick := -1                 # a press of "use" waiting for its tick, in case it is on a ladder (-1 = none)

var self_dirty := true               # own state changed and must be confirmed to the client
var last_self_tick := -1000
var last_packet_tick := -1000
var chat_times: Array[int] = []
var said: Array = []                 # [channel, from, text] this one heard, kept only for tests (see GameServer.keep_heard)
var bot_until := 0
var order := 0                       # (v55) a bot's standing order from the captain (Net.POST_*)
var order_by := -1                   # the slot of whoever gave it (a bot told to follow goes after them)
var doing := 0                       # what the bot does about it now (Net.DOING_*)
var bot_goal := -1                   # the cell it is making for (-1 = none)
var bot_face := 0                    # and which way it faces there
var bot_plan_tick := -1000           # when it last worked out its way
var bot_from := -1                   # the cell it worked it out from
var bot_step := 0                    # its next step: a direction, -1 for the ladder underfoot, 0 = none
var bot_lock := -1                   # (v66) the airlock door it is getting past (Systems.get_past), or -1
var bot_task := 0                    # (v60) what the bot's way leads to (Stations.TASK_*)
var haul := -1                       # (v60) the gun mount whose order the bot is carrying out (-1 = none)
var bot_healing := false             # (v60) the bot lies in the autodoc until it is whole enough
var home := -1                       # (v55) a pirate on its own ship: its post, a cell of that ship's drawing
var hold := -1                       # (v57) a pirate the flagship put aboard: the cell of our bridge it holds
var job := 0                         # Net.JOB_*: its access (st.access) and which skills grow quickly
var skills := PackedByteArray([0, 0, 0, 0])   # per Net.SKILL_*, 0..Net.SKILL_MAX
var slow_work := 0                   # pieces of work outside its job (every Net.SKILL_SLOW_EVERY-th one teaches)
var me_sent := PackedByteArray()     # job and skills as last told to its client


const HISTORY := 32


func _init() -> void:
	slots.resize(Net.SLOTS)
	worn.resize(Net.WORN)
	history.resize(HISTORY)


func take_job(which: int) -> void:
	## Takes a job: its access, and its own skill at least where a newcomer to it starts.
	job = clampi(which, 0, Net.JOBS - 1)
	st.access = Net.access_of(job)
	var own := Net.JOB_SKILL[job]
	if own >= 0:
		skills[own] = maxi(skills[own], Net.JOB_START_SKILL)


func skill(which: int) -> float:
	## 0..1
	return skills[which] / float(Net.SKILL_MAX)


func train(which: int) -> void:
	## A piece of work of that kind done: its job's own skill grows quickly, the others slowly.
	if Net.JOB_SKILL[job] == which:
		skills[which] = mini(skills[which] + Net.SKILL_GAIN, Net.SKILL_MAX)
	else:
		slow_work += 1
		if slow_work % Net.SKILL_SLOW_EVERY == 0:
			skills[which] = mini(skills[which] + Net.SKILL_GAIN_OTHER, Net.SKILL_MAX)


func count(item: int) -> int:
	## How many of that thing it carries (in any state).
	if item == Net.ITEM_NONE:
		var free := 0                        # free slots, of those it has
		for i in Net.SLOTS:
			if usable(i) and slots[i] == Net.ITEM_NONE:
				free += 1
		return free
	var n := 0
	for v in slots:
		if v != Net.ITEM_NONE and Items.kind_of(v) == Items.kind_of(item):
			n += 1
	return n


func in_hand() -> int:
	return slots[hand]


func usable(at: int) -> bool:
	## Is this slot there at all: pockets come with a jumpsuit, the last slots with a backpack.
	if at < Net.BASE_SLOTS:
		return true
	if at < Net.BASE_SLOTS + Net.POCKETS:
		return worn[Net.WEAR_JUMPSUIT] != Net.ITEM_NONE
	return worn[Net.WEAR_PACK] != Net.ITEM_NONE


func add(item: int, to_hand: bool = false) -> bool:
	## Puts a thing into the first free slot (into the hand if asked and it is
	## free). False if there is no room.
	var at := hand if to_hand and usable(hand) and slots[hand] == Net.ITEM_NONE else -1
	if at < 0:
		for i in Net.SLOTS:
			if usable(i) and slots[i] == Net.ITEM_NONE:
				at = i
				break
	if at < 0:
		return false
	slots[at] = item
	return true


func dress() -> void:
	## A fresh crew member: a spacesuit with a full tank and a jumpsuit, no backpack.
	worn.fill(Net.ITEM_NONE)
	worn[Net.WEAR_SUIT] = Net.ITEM_SUIT
	worn[Net.WEAR_JUMPSUIT] = Net.ITEM_JUMPSUIT
	tank = 1.0


func has_suit() -> bool:
	return worn[Net.WEAR_SUIT] != Net.ITEM_NONE


func look() -> int:
	## How it is dressed, as a row of the sheet (see Net.LOOKS).
	var outfit := Net.OUTFIT_SUIT if has_suit() else (Net.OUTFIT_JUMPSUIT if worn[Net.WEAR_JUMPSUIT] != Net.ITEM_NONE else Net.OUTFIT_BARE)
	return outfit * 2 + (1 if worn[Net.WEAR_PACK] != Net.ITEM_NONE else 0)


func holds_in(wear: int) -> bool:
	## Is anything kept in what is worn there (a jumpsuit's pockets, a backpack)?
	var from := Net.BASE_SLOTS if wear == Net.WEAR_JUMPSUIT else (Net.BASE_SLOTS + Net.POCKETS if wear == Net.WEAR_PACK else 0)
	var to := Net.BASE_SLOTS + Net.POCKETS if wear == Net.WEAR_JUMPSUIT else (Net.SLOTS if wear == Net.WEAR_PACK else 0)
	for i in range(from, to):
		if slots[i] != Net.ITEM_NONE:
			return true
	return false


func take_off(wear: int) -> int:
	## Takes off what is worn there, as an item (a suit keeps its oxygen); ITEM_NONE
	## if nothing is, or things are still kept in it.
	var item := worn[wear]
	if item == Net.ITEM_NONE or holds_in(wear):
		return Net.ITEM_NONE
	worn[wear] = Net.ITEM_NONE
	if wear == Net.WEAR_SUIT:
		item = Items.suit_with(tank)
		supply = false
		tank = 0.0
	return item


func put_on(item: int) -> bool:
	## Puts it on, if that place is free.
	var wear := Items.worn_as(item)
	if wear < 0 or worn[wear] != Net.ITEM_NONE:
		return false
	if wear == Net.WEAR_SUIT:
		tank = float(Items.tank_of(item)) / Net.SUIT_TANK_STEPS
		item = Net.ITEM_SUIT
	worn[wear] = item
	return true


func remove(item: int) -> bool:
	## Takes one such thing out (any state of it: a lit flashlight is a flashlight).
	## False if it carries none.
	for at in slots.size():
		if Items.kind_of(slots[at]) == Items.kind_of(item) and slots[at] != Net.ITEM_NONE:
			slots[at] = Net.ITEM_NONE
			return true
	return false
