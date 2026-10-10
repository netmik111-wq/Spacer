extends RefCounted
## Constants shared by the server and the client: simulation rates and the
## network protocol. Change PROTOCOL whenever a packet layout changes, so old
## clients are refused with a clear message instead of misreading data.

const PROTOCOL := 1
const DEFAULT_PORT := 24500

const TICK_HZ := 20                 # server steps per second
const TICK_SEC := 1.0 / TICK_HZ
const MOVE_TICKS := 4               # one tile step lasts 4 ticks = 0.2 s (5 tiles per second)
const CHUNK_SHIFT := 4              # the world is replicated in 16x16-tile chunks

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

# --- packets, server -> client ---
const S_WELCOME := 10               # u16 your id, u32 tick, u32 map crc, u8 name length, map name
const S_REJECT := 11                # u8 reason
const S_ROSTER := 12                # u16 count, then roster entries
const S_JOIN := 13                  # one roster entry
const S_LEAVE := 14                 # u16 id
const S_WORLD := 15                 # u32 tick, then sections
const S_CHAT := 16                  # u16 from id, u16 length, text

# --- sections inside S_WORLD ---
const SEC_ENT := 1                  # u16 count, then 7-byte records: u16 id, s16 x, s16 y, u8 facing (255 = gone)
const SEC_VIEW := 4                 # u8 chunk x, u8 chunk y: the centre of what this client is shown
const SEC_CHECK := 5                # u32 checksum of the entities this client should know
const SEC_SELF := 7                 # authoritative state of the client's own character (see pack_self)

const FACING_GONE := 255
const ENT_BYTES := 7
const SELF_BYTES := 17

const REJECT_VERSION := 1
const REJECT_FULL := 2
const REJECT_BAD_HELLO := 3

const SUIT_COLOURS := 8             # rows in assets/chars.png


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
static func ent_hash(id: int, x: int, y: int, facing: int) -> int:
	return id * 31 + x * 17 + y * 13 + facing * 7 + 1
