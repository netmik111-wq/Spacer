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
var pirate := false                  # an enemy the server moves (see Pirates)
var ready_tick := 0                  # its hands are free again from this tick (after a shot, a blow, a reload)
var history := PackedVector2Array()  # where it was drawn on each of the last HISTORY ticks (see GameServer.place_at)
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
var rep_x := -9999                   # position and facing as last sent to clients
var rep_y := -9999
var rep_look := -1
var left_chunk := -1                 # the chunk it last moved out of, and the send that happened in
var left_window := -1                # (see GameServer._record)

var health := 100.0                  # 100 = unhurt; 0 and below = unconscious; Net.HEALTH_DEAD = dead
var cond := 0                        # Net.COND_*
var tank := 1.0                      # oxygen left in the suit's tank, 1.0 = full
var supply := false                  # breathing from the tank instead of the air around
var slots := PackedByteArray()       # what it carries: one item per slot (Net.ITEM_*), Net.SLOTS of them
var slots_sent := PackedByteArray()  # the same as last told to its client
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
var bot_until := 0


const HISTORY := 32


func _init() -> void:
	slots.resize(Net.SLOTS)
	history.resize(HISTORY)


func count(item: int) -> int:
	## How many of that thing it carries (in any state).
	if item == Net.ITEM_NONE:
		return slots.count(Net.ITEM_NONE)
	var n := 0
	for v in slots:
		if v != Net.ITEM_NONE and Items.kind_of(v) == Items.kind_of(item):
			n += 1
	return n


func in_hand() -> int:
	return slots[hand]


func add(item: int, to_hand: bool = false) -> bool:
	## Puts a thing into the first free slot (into the hand if asked and it is
	## free). False if there is no room.
	var at := hand if to_hand and slots[hand] == Net.ITEM_NONE else slots.find(Net.ITEM_NONE)
	if at < 0:
		return false
	slots[at] = item
	return true


func remove(item: int) -> bool:
	## Takes one such thing out (any state of it: a lit flashlight is a flashlight).
	## False if it carries none.
	for at in slots.size():
		if Items.kind_of(slots[at]) == Items.kind_of(item) and slots[at] != Net.ITEM_NONE:
			slots[at] = Net.ITEM_NONE
			return true
	return false
