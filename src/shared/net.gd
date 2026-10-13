extends RefCounted
## Constants shared by the server and the client: simulation rates and the
## network protocol. Change PROTOCOL whenever a packet layout changes, so old
## clients are refused with a clear message instead of misreading data.

const PROTOCOL := 21
const DEFAULT_PORT := 24500

const TICK_HZ := 20                 # server steps per second
const TICK_SEC := 1.0 / TICK_HZ
const MOVE_TICKS := 4               # one tile step lasts 4 ticks = 0.2 s (5 tiles per second)
const DRAG_TICKS := 8               # and twice as long while hauling somebody
const CHUNK_SHIFT := 4              # the world is replicated in 16x16-tile chunks
const AIR_EVERY := 2                # the air is recalculated every 2nd tick (10 times a second)
const AIR_SEND_EVERY := 4           # and its changes are sent every 4th tick (5 times a second)
const AIR_FULL := 200               # air in a cell as sent over the network: 200 = normal pressure, 0 = vacuum
const KPA_FULL := 101.0             # normal pressure in kilopascals, for display

const MAX_NAME := 16
const MAX_CHAT := 160

# Directions. 0 means "not moving".
const DIR_NONE := 0
const DIR_UP := 1
const DIR_DOWN := 2
const DIR_LEFT := 3
const DIR_RIGHT := 4
const DX: Array[int] = [0, 0, 0, -1, 1]
const DY: Array[int] = [0, -1, 1, 0, 0]

# --- packets, client -> server (first byte) ---
const C_HELLO := 1                  # u16 protocol, u8 name length, name
const C_INPUT := 2                  # u16 seq, u32 apply tick, u8 direction
const C_CHAT := 3                   # u16 length, text
const C_SHUTDOWN := 4               # secret text: the hosting player's game stops the server it started
const C_ADMIN := 5                  # u8 command, u8 argument, secret text: the hosting player's tools (see ADMIN_*)
const C_RESPAWN := 6                # nothing else: a dead player asks to come back as a new crew member
const C_USE := 7                    # u8 held, u32 tick: the "use" key went down (1) or up (0) on that tick of
                                    # the client's predicted clock. Pressing it on a ladder climbs; the tick lets
                                    # the server judge that where the client saw its character, not where the
                                    # character was when the packet arrived.
const C_SUIT := 8                   # u8 on: turn the suit's oxygen supply on (1) or off (0)
const C_JUMP := 9                   # u8 sector: start a jump there (the player must stand at the sector console)
const C_HELM := 10                  # u8 go (1 = set course, 0 = stop), u8 x, u8 y: steer inside the sector
                                    # (the player must stand at the ship's controls)
const C_SEARCH := 12                # u16 id (NOBODY = stop), u32 tick: go through the pockets of somebody lying next to us
const C_DRAG := 13                  # u16 id (NOBODY = let go), u32 tick: take hold of somebody lying next to us
                                    # (both carry the tick of the client's predicted clock, like C_USE)
const C_LOOT := 14                  # u8 theirs (1 = take from them, 0 = give them ours), u8 slot: while searching
const C_STORE := 11                 # u8 action (STORE_*), u8 thing (ITEM_*): take from the supply locker,
                                    # put back, or buy from a trader (the player must stand at the locker)
const C_HAND := 15                  # u8 slot: the slot whose thing is in the hand
const C_DROP := 16                  # nothing else: put the thing in the hand down on the floor here
const C_FIRE := 18                  # u32 tick the player saw the others on (see GameClient.render_tick),
                                    # s16 x * 16, s16 y * 16: the place clicked, in cells of the whole grid.
                                    # Uses the thing in the hand on that place: shoot, strike, bandage.
const C_DOCK := 19                  # u8 on: bring the derelict alongside up against the airlock (1) or draw it off (0)
const C_ACT := 17                   # nothing else: use the thing in the hand by itself (switch a flashlight)

# --- packets, server -> client ---
const S_WELCOME := 10               # u16 your id, u32 tick, u32 map crc, u8 name length, map name
const S_REJECT := 11                # u8 reason
const S_ROSTER := 12                # u16 count, then roster entries: u16 id, u8 colour, u8 kind (KIND_*), u8 name length, name
const S_JOIN := 13                  # one roster entry
const S_LEAVE := 14                 # u16 id
const S_WORLD := 15                 # u32 tick, then sections
const S_CHAT := 16                  # u16 from id, u16 length, text
const S_SECTORS := 17               # the part of space around the ship (see Sectors.pack); sent anew on every arrival
const S_NAV := 18                   # u8 sector the ship is in, u8 sector it is jumping to (NO_SECTOR = none),
                                    # both as numbers in the window last sent; u32 tick the jump lands on,
                                    # u32 tick the drive is ready from

# --- sections inside S_WORLD ---
const SEC_ENT := 1                  # u16 count, then 7-byte records: u16 id, s16 x, s16 y, u8 look (255 = gone; see pack_look)
const SEC_DOOR := 2                 # u16 count, then 7-byte records: u16 door, s32 tick it is passable from (-1 = shut),
                                    # u8 flags (bit 0: its emergency shutter is down, bit 1: the door is
                                    # jammed open, bit 2: the shutter is faulty; see Doors.flags)
const SEC_HULL := 3                 # u16 count, then 5-byte records: s16 x, s16 y, u8 state (1 = breached, 0 = whole)
const SEC_VIEW := 4                 # u8 chunk x, u8 chunk row inside the deck: the centre of what this client is
                                    # shown. It is shown those chunks on every deck (rows count through all decks
                                    # everywhere else: see ShipMap).
const SEC_CHECK := 5                # u32 checksum of the entities this client should know, u32 of doors, hull and air
const SEC_AIR := 6                  # u8 chunk x, u8 chunk y, u16 count, then pairs: u8 cell in the chunk (y*16+x), u8 air
const SEC_SELF := 7                 # authoritative state of the client's own character (see pack_self)
const SEC_AIR_FULL := 8             # u8 chunk x, u8 chunk y, then the air of all 256 cells of the chunk
const SEC_FLOOR := 10               # u16 count, then FLOOR_BYTES-byte records: s16 x, s16 y, then FLOOR_STACK
                                    # bytes: the things lying in that cell, bottom first (ITEM_NONE = none)
const SEC_VITALS := 9               # the client's own character: s16 health (100 = unhurt, 0 and below =
                                    # unconscious, HEALTH_DEAD = dead), u8 oxygen tank (0..TANK_FULL),
                                    # u8 flags (bit 0: supply on), u8 work done on what it is using (0..100),
                                    # then SLOTS bytes: what it carries, one item per slot (ITEM_*),
                                    # then WORN bytes: what it wears (WEAR_*)
const SLOTS := 12                   # slots for things: BASE_SLOTS always, POCKETS with a jumpsuit, PACK_SLOTS with a backpack
const BASE_SLOTS := 6
const POCKETS := 2                  # slots BASE_SLOTS .. BASE_SLOTS + POCKETS - 1
const PACK_SLOTS := 4               # the last ones
const WORN := 3                     # what is worn, one thing each:
const WEAR_SUIT := 0                #   a spacesuit (helmet and oxygen tank): without it there is no supply
const WEAR_JUMPSUIT := 1            #   a jumpsuit: its pockets
const WEAR_PACK := 2                #   a backpack
const VITALS_BYTES := 5 + SLOTS + WORN
# how a character looks (S_OUTFIT): outfit * 2 + 1 with a backpack; a row of assets/chars.png per colour and look
const OUTFIT_SUIT := 0
const OUTFIT_JUMPSUIT := 1
const OUTFIT_BARE := 2
const LOOKS := 6

# things that can be carried
const ITEM_NONE := 0
const ITEM_PATCH := 1               # closes a hole in the hull
const ITEM_PART := 2                # a spare part: mends a machine or a door quickly
const ITEM_FLASHLIGHT := 3
const ITEM_FLASHLIGHT_ON := 4       # the same, switched on (what things are and do: see Items)
const ITEM_MAG := 5                 # a pistol magazine
const ITEM_BATON := 6
const ITEM_MEDPATCH := 7            # a patch that closes wounds at once
const ITEM_MEDKIT := 20             # a first-aid kit with no uses left; ITEM_MEDKIT + n has n left
const MEDKIT_USES := 5
const ITEM_SUIT := 30               # a spacesuit with an empty tank; ITEM_SUIT + n has n tenths of a tank
const SUIT_TANK_STEPS := 10
const ITEM_JUMPSUIT := 41
const ITEM_BACKPACK := 42
const ITEM_PISTOL := 10             # a pistol with no rounds in it; ITEM_PISTOL + n holds n rounds
const PISTOL_ROUNDS := 8
const NOBODY := 65535               # "no character" where an id is expected

const FACING_GONE := 255
const ENT_BYTES := 7
const SELF_BYTES := 17
const DOOR_BYTES := 7
const HULL_BYTES := 5
const FLOOR_STACK := 4              # how many things can lie in one cell
const FLOOR_BYTES := 4 + FLOOR_STACK

const S_HELM := 19                  # the ship inside its sector: s16 x*10, s16 y*10 (where it was on that tick),
                                    # u8 under way, u8 destination x, u8 destination y, u32 tick
const S_DEVICES := 20               # u8 count, then per thing out of order (a bridge console, the engine,
                                    # the air plant): u16 cell

const S_POWER := 21                 # u8 on: the ship has power (1) or every system stands still (0)

const S_SEARCH := 23                # u16 id of the character we are searching (NOBODY = not any more), then
                                    # SLOTS bytes: what they carry, WORN bytes: what they wear,
                                    # then u8 how hurt they are (0 = unhurt .. 4 = dying)
const S_OUTFIT := 27                # u16 id, u8 look (see LOOKS): how a character is dressed
const C_WEAR := 20                  # u8 WEAR_*: take that off, into the hand (or a free slot)
const S_SHOT := 25                  # u8 kind (SHOT_*), u8 hit (1 = somebody was hit), s16 from x * 16,
                                    # s16 from y * 16, s16 to x * 16, s16 to y * 16: for drawing
const SHOT_BULLET := 1
const SHOT_BLOW := 2
const S_OTHER := 26                 # s16 x, s16 y of the other ship's corner in the grid (-9999 = none here),
                                    # u8 docked, u8 kind (OTHER_*): a ship alongside (see ShipMap.place_other)
# the kinds of other ship that may come alongside, and their maps (in this order: ShipMap.others)
const OTHER_DERELICT := 0
const OTHER_PIRATE := 1
const OTHER_MAPS: Array[String] = ["derelict01", "pirate01"]
const S_SOUND := 24                 # u8 kind (SOUND_*), s16 x, s16 y: something was heard there
const S_STORE := 22                 # the ship's supplies: u16 air for the air plant in tenths of a cell's
                                    # worth, u16 credits, u8 count, then pairs: u8 thing (ITEM_*), u16 how
                                    # many of it the locker holds

# what a player may ask of the supply locker (C_STORE)
const STORE_TAKE := 1               # one of the thing named
const STORE_PUT_BACK := 3           # everything carried that the locker keeps goes back into it
const STORE_BUY := 4                # one of the thing named; this and the one below only while docked with a trader
const STORE_BUY_AIR := 6

# supplies. Mending a hole takes a patch; mending a machine or a door takes a
# spare part, or three times as long without one.
const START_CREDITS := 30           # (what the locker starts with, and prices of things: see Items)
const STORE_AIR_FULL := 60.0        # air the air plant can give out before it must be restocked, in cells' worth
const PRICE_AIR := 5                # for AIR_LOT cells' worth
const AIR_LOT := 10.0
const EXPLORE_REWARD := 15          # credits for the first visit to a sector
const NO_PART_SLOWER := 3           # how many times longer a repair without a spare part takes

# Sounds. Each is heard this far, in cells, on its own deck; through air only:
# where either the one who hears or the sound itself is in a vacuum, only what
# happens right next to them is heard (through the suit and the floor).
const SOUND_STEP := 1               # footsteps
const SOUND_DOOR := 2               # a door sliding open
const SOUND_HISS := 3               # air rushing out of a hole in the hull
const SOUND_THUD := 4               # somebody falling
const SOUND_DROP := 5               # a thing put down
const SOUND_LADDER := 6             # somebody on a ladder
const SOUND_SHOT := 7               # a gunshot
const SOUND_BLOW := 8               # a blow struck
const SOUND_CRY := 9                # somebody hurt crying out
const SOUND_RANGE: Array[int] = [0, 6, 8, 12, 10, 5, 7, 18, 8, 12]
const SOUND_AIR := 0.2              # below this share of normal pressure there is no sound
const SOUND_CONTACT := 1.5          # this close a sound is felt even in a vacuum

const ADMIN_BREACH := 1             # tear a hole in the hull near the player who asked (tests)
const ADMIN_SEAL := 2               # close every hole (tests)
const ADMIN_EVENT := 3              # make the director fire the event whose id is the argument
const ADMIN_AUTO := 4               # argument 1: the director runs events by itself; 0: only by hand

const NO_SECTOR := 255
const JUMP_TICKS := 160             # a jump takes 8 s to charge
const DRIVE_REST_TICKS := 300       # and the drive needs 15 s after landing
const SYSTEM_ID := 65535            # "from" of chat lines written by the ship itself

const REJECT_VERSION := 1
const REJECT_FULL := 2
const REJECT_BAD_HELLO := 3

const SUIT_COLOURS := 8             # rows in assets/chars.png

# Condition of a character. It travels in the same byte as the facing.
const COND_OK := 0
const COND_CRIT := 1                # unconscious on the floor
const COND_DEAD := 2
const HEALTH_FULL := 100
const HEALTH_DEAD := -100
const RESPAWN_TICKS := 100          # a dead player may come back after 5 s

# who a roster entry is
const KIND_PLAYER := 0
const KIND_BOT := 1
const KIND_CORPSE := 2              # a body left behind; nobody controls it
const KIND_PIRATE := 3              # an enemy the server moves
const PIRATE_COLOURS := 3           # rows of assets/chars.png after the crew's SUIT_COLOURS: pirates' suits

const TANK_FULL := 200              # a full oxygen tank as sent over the network
const REPAIR_TICKS := 120           # holding "use" on a hole for 6 s mends it
const FORCE_TICKS := 60             # holding "use" on an emergency shutter for 3 s forces it up
const FORCED_OPEN_TICKS := 100      # and it stays up for 5 s whatever the pressure
const SHUTTER_DROP := 0.25          # an emergency shutter drops when the two sides of its door differ by this
                                    # share of normal pressure, and lifts again below SHUTTER_LIFT
const SHUTTER_LIFT := 0.10


static func reject_text(reason: int) -> String:
	match reason:
		REJECT_VERSION:
			return "Версии игры не совпадают: у сервера и клиента должна быть одна сборка."
		REJECT_FULL:
			return "Сервер заполнен."
		REJECT_BAD_HELLO:
			return "Сервер не принял подключение."
	return "Сервер отклонил подключение (код %d)." % reason


## Entity checksum term, summed by the server and by the client over the same
## set of entities. Must stay identical on both sides.
static func ent_hash(id: int, x: int, y: int, look: int) -> int:
	return id * 31 + x * 17 + y * 13 + look * 7 + 1


## Facing, condition, "shines a light" (a lit flashlight in the hand) and
## "moves slowly" (hauling somebody, or being hauled) packed into the one byte
## sent for a character. The top bit is used only in SEC_SELF: the step in
## progress is a slow one.
const LOOK_LIGHT := 8
const LOOK_SLOW := 64
const LOOK_LONG_STEP := 128

static func pack_look(facing: int, cond: int, slow: bool = false, light: bool = false) -> int:
	return facing | (cond << 4) | (LOOK_SLOW if slow else 0) | (LOOK_LIGHT if light else 0)


static func look_light(look: int) -> bool:
	return (look & LOOK_LIGHT) != 0


static func look_slow(look: int) -> bool:
	return (look & LOOK_SLOW) != 0


static func look_facing(look: int) -> int:
	return look & 7


static func look_cond(look: int) -> int:
	return (look >> 4) & 3


## The same for the ship itself: doors, holes in the hull and air.
static func door_hash(door: int, ready: int, flags: int) -> int:
	return (door + 1) * 131 + (ready & 0xFFFF) * 7 + flags * 977 + 3


static func hull_hash(x: int, y: int) -> int:
	return x * 29 + y * 37 + 11


static func floor_hash(x: int, y: int, things: PackedByteArray) -> int:
	var h := x * 53 + y * 59 + 17
	for i in things.size():
		h += things[i] * (i * 7 + 3) * 101
	return h


static func air_hash(x: int, y: int, air: int) -> int:
	return air * ((x & 15) + (y & 15) * 16 + 1)
