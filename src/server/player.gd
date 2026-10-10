extends RefCounted
## Everything the server keeps about one character: a connected player or a bot.

const Mover := preload("res://src/shared/mover.gd")

var slot := 0
var peer: ENetPacketPeer = null      # null for bots
var name := ""
var colour := 0
var bot := false
var st := Mover.State.new()

var inputs: Array = []               # queued input changes: [apply tick, direction, seq]
var last_seq := 0                    # last input change applied, echoed back to the client

var view_cx := -100                  # chunk this client's view is centred on
var view_cy := -100
var rep_x := -9999                   # position and facing as last sent to clients
var rep_y := -9999
var rep_facing := -1

var self_dirty := true               # own state changed and must be confirmed to the client
var last_self_tick := -1000
var last_packet_tick := -1000
var chat_times: Array[int] = []
var bot_until := 0
