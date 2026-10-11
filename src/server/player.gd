extends RefCounted
## Everything the server keeps about one character: a connected player or a bot.

const Mover := preload("res://src/shared/mover.gd")

var slot := 0
var peer: ENetPacketPeer = null      # null for bots
var name := ""
var colour := 0
var bot := false
var corpse := false                  # a body left behind: it only lies there
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
var patches := 0                     # hull patches carried
var parts := 0                       # spare parts carried
var using := false                   # holds the "use" key
var work := 0                        # ticks spent on the thing in front of it (mending a hole)
var work_cell := -1
var work_total := 1                  # ticks the job in hand takes (the progress shown is work / work_total)
var vitals_sent := -1                # health, tank, supply and work as last told to the client, packed
var died_tick := 0
var climbs := 0                      # times it has gone up or down a ladder (for tests)
var climb_tick := -1                 # a press of "use" waiting for its tick, in case it is on a ladder (-1 = none)

var self_dirty := true               # own state changed and must be confirmed to the client
var last_self_tick := -1000
var last_packet_tick := -1000
var chat_times: Array[int] = []
var bot_until := 0
