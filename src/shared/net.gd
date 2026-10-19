extends RefCounted
## Constants shared by the server and the client: simulation rates and the
## network protocol. Change PROTOCOL whenever a packet layout changes, so old
## clients are refused with a clear message instead of misreading data.

const PROTOCOL := 42
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
const C_HELLO := 1                  # u16 protocol, u8 name length, name, u8 job (JOB_*)
const C_INPUT := 2                  # u16 seq, u32 apply tick, u8 direction
const C_CHAT := 3                   # u16 length, text
const C_SHUTDOWN := 4               # secret text: the hosting player's game stops the server it started
const C_ADMIN := 5                  # u8 command, u8 argument, u16 target id, then the secret text (the hosting
                                    # player's game) or nothing (a player the host made an admin): see ADMIN_*
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
const S_WELCOME := 10               # u16 your id, u32 tick, u32 map crc, u16 id of your ship, u8 name length, map name
const S_REJECT := 11                # u8 reason
const S_ROSTER := 12                # u16 count, then roster entries: u16 id, u8 colour, u8 kind (KIND_*), u8 job, u8 name length, name
const S_JOIN := 13                  # one roster entry
const S_LEAVE := 14                 # u16 id
const S_WORLD := 15                 # u32 tick, then sections
const S_CHAT := 16                  # u16 from id, u8 channel (CHAT_*), u16 length, text
const S_SECTORS := 17               # the part of space around the ship (see Sectors.pack); sent anew on every arrival
# Packets about one ship (S_NAV, S_HELM, S_DEVICES, S_POWER, S_STORE, S_GUNS) carry its id
# (u16) right after the packet's kind; the layouts below are what follows the id.
const S_NAV := 18                   # u8 sector the ship is in, u8 sector it is jumping to (NO_SECTOR = none),
                                    # both as numbers in the window last sent; u32 tick the jump lands on,
                                    # u32 tick the drive is ready from

# --- sections inside S_WORLD ---
const SEC_ENT := 1                  # u16 count, then 7-byte records: u16 id, s16 x, s16 y, u8 look (see pack_look;
                                    # FACING_GONE = gone, FACING_HIDDEN = out of sight now: x, y is where it was last seen)
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
const ITEM_FUEL := 8                # a can of fuel: a jump burns one from the supply locker
const ITEM_RADIO := 9               # a radio: what is said into it with ";" in front reaches every radio
const ITEM_MEDKIT := 20             # a first-aid kit with no uses left; ITEM_MEDKIT + n has n left
const MEDKIT_USES := 5
const ITEM_SUIT := 30               # a spacesuit with an empty tank; ITEM_SUIT + n has n tenths of a tank
const SUIT_TANK_STEPS := 10
const ITEM_JUMPSUIT := 41
const ITEM_BACKPACK := 42
const ITEM_GUN := 50                # a ship's weapon in the cargo: ITEM_GUN + Weapons.* (51..60; later ones ITEM_GUN_MORE); kept in the
                                    # supply locker only, never carried (Items "cargo")
const ITEM_ROCKET := 61             # a rocket for the rocket launcher (cargo)
const ITEM_EMP_ROCKET := 62         # an EMP rocket for the EMP launcher (cargo)
const ITEM_PROBE := 63              # (v53) a scanning probe, launched from the gun console: shows the enemy's rooms (cargo)
const ITEM_DRONE := 64              # (v54) a scouting drone, launched and steered from the drone monitor (cargo)
const ITEM_GUN_MORE := 60           # (v50) weapons from Weapons.TRACTOR on: ITEM_GUN_MORE + Weapons.* (71..82)
const ITEM_SHELL := 83              # (v58) a shell for the autocannon and the «Молот» (cargo)
const ITEM_GUN_PARTS := 84          # (v58) parts of a gun's kind: ITEM_GUN_PARTS + Weapons.KIND_* (84..88; cargo)
const ITEM_GUN_FX := 100            # (v58) a tier 3 gun with its effect: see Weapons.item_of (100..134; cargo)
const ITEM_GUN_DAMAGED := 140       # (v58) a damaged gun, mended at the workbench: ITEM_GUN_DAMAGED + Weapons.* (cargo)
const ITEM_GEAR := 170             # (v59) a crate of ship gear: ITEM_GEAR + Gear.* (171..190; carried, kept in the locker)
const ITEM_ROBOT := 195             # (v62) a security robot in its crate: set down on the floor, it switches on and guards
const ITEM_GUN_LATE := 200          # (v62) weapons from Weapons.HORNET on: ITEM_GUN_LATE + (w - Weapons.HORNET) (200..203; cargo)
const ITEM_SEED := 204              # (v63) a packet of seeds: ITEM_SEED + Plants.seed_item (204..227; carried, kept in the locker)
const ITEM_FOOD := 230              # (v63) a ration: the crew eats them from the supply locker at every jump (see Garden)
const ITEM_CARGO := 231             # (v63) a quest's crate of cargo, for a station (cargo: kept in the locker)
const ITEM_BLACKBOX := 232          # (v63) a wreck's black box, carried home to the supply locker for a quest
const ITEM_PISTOL := 10             # a pistol with no rounds in it; ITEM_PISTOL + n holds n rounds
const PISTOL_ROUNDS := 8
const NOBODY := 65535               # "no character" where an id is expected

const FACING_GONE := 255
const FACING_HIDDEN := 254
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

const S_POWER := 21                 # u8 on: the ship has power (1) or every system stands still (0),
                                    # (v61) u8 1 if the ship is dark and the bridge's backup SMES keeps its room lit
const C_SMES := 30                  # (v61) u8 which SMES (its number in S_SMES), u8 action (Power.ACT_*), u8 value:
                                    # the SMES's terminal, from in front of it (it needs no power)
const S_SMES := 40                  # (v61) to all, after the ship's id: u8 count, then per SMES 15 bytes: u8 1 = the
                                    # bridge's backup, u16 cell, u16 charge, u16 capacity, u8 flags (1 charging on,
                                    # 2 output on), u8 input target, u8 output target, u8 most input, u8 most output,
                                    # u8 taking now * 10, u8 giving now * 10, u8 status (SMES_*); then the power
                                    # monitor: u8 the engine gives, u8 the ship's own draw, u8 the guns and shield draw,
                                    # u8 the power for the guns and shield now, u8 flags (POWF_*), u16 seconds the
                                    # SMES lasts at what it gives (65535 = it gives nothing), u16 the reactor's power
const SMES_IDLE := 0
const SMES_CHARGING := 1
const SMES_SENDING := 2
const SMES_FULL := 3
const SMES_EMPTY := 4
const SMES_BROKEN := 5
const SMES_JAMMED := 6
const SMES_STATUS: Array[String] = ["Ожидание", "Заряжается", "Отдаёт энергию", "Заряжен полностью", "Нет заряда",
	"Сломан", "Выбит ионным разрядом"]
const POWF_STORM := 1               # the ship is inside an ion storm: the reactor gives half
const POWF_ENGINE := 2              # the engine makes power
const POWF_CARRYING := 4            # the SMES carries the whole ship
const POWF_BACKUP := 8              # the ship is dark, the bridge's backup keeps its room lit

const S_SEARCH := 23                # u16 id of the character we are searching (NOBODY = not any more), then
                                    # SLOTS bytes: what they carry, WORN bytes: what they wear,
                                    # then u8 how hurt they are (0 = unhurt .. 4 = dying)
const S_OUTFIT := 27                # u16 id, u8 look (see LOOKS): how a character is dressed
const S_GUNS := 28                  # u8 count of mounts, per mount u8 weapon (Weapons.*), u8 charge (0..100,
                                    # GUN_BROKEN, GUN_JAMMED), u8 GUNF_* flags; u8 power drawn, u8 power the reactor
                                    # gives; u8 our shield (0..100), u8 SHF_* flags; then u8 enemy hull
                                    # left, u8 enemy hull full (0 = no enemy), u16 seconds until it docks (0 = not coming),
                                    # u8 where the guns aim (ESYS_* or AIM_ANY), u8 count of the enemy's systems
                                    # (0 = no enemy), then per system u8 strength left, u8 strength when whole,
                                    # u8 seconds it is still put out by ion or EMP,
                                    # then u8 ENEMY_* flags, u16 seconds until it jumps away (while it flees;
                                    # 65535 = its jump cannot charge now), u8 the enemy's shield (0..100),
                                    # (v53) u8 its class (ECLASS_*), u8 its temper (TEMPER_*, 255 = not known yet),
                                    # u8 count of its rooms (ShipMap.rooms of its drawing), then per room u8: the
                                    # system in it (ESYS_*), ROOM_EMPTY, or ROOM_UNKNOWN (not scanned yet);
                                    # u8 probes in the cargo, then
                                    # u8 count, then u8 per weapon the enemy carries (Weapons.*);
                                    # (v54) u8 credits of the ransom it offers (0 = none), u8 seconds the offer stands;
                                    # (v58) per mount u8 the effect of its gun (Weapons.FX_*); u8 our point defence
                                    # (Weapons.GUARD or NONE), u8 its charge (0..100, GUN_BROKEN, GUN_JAMMED), u8 GUNF_*;
                                    # u8 1 if the enemy has point defence; per enemy weapon u8 its effect
const ROOM_UNKNOWN := 255
const ROOM_EMPTY := 254
const GUN_BROKEN := 255
const GUN_JAMMED := 254             # put out for a few seconds by an enemy ion or EMP hit
const GUNF_ARMED := 1               # it draws power and charges
const GUNF_BEAM := 2                # (a cutting or siphon beam) it is burning now
const GUNF_NO_AMMO := 4             # (a launcher) no rockets for it in the cargo
const SHF_HAS := 1                  # the ship has a shield generator
const SHF_ON := 2                   # it is switched on
const SHF_BROKEN := 4
const SHF_JAMMED := 8
const SHF_HARDENED := 16            # the rare upgrade: it stops rockets too
const C_GUNSET := 24                # u8 action (GUNSET_*), u8 a, u8 b: set the guns up, from the gun console
const GUNSET_ARM := 1               # a = mount, b = 1 power it, 0 cut its power
const GUNSET_SHIELD := 2            # b = 1 switch the shield on, 0 off
const GUARD_MOUNT := 200            # (v58) as a mount number: the point defence's own mount
const GUNSET_MOUNT := 3             # a = mount, b = (v58) the thing from the cargo to put on it (ITEM_*; ITEM_NONE = take it
                                    # down into the cargo)
const GUNSET_PROBE := 4             # (v53) launch a scanning probe from the cargo at the enemy
const GUNSET_RANSOM := 5            # (v54) take the ransom a beaten pirate ship offers
const C_GUNS := 21                  # u8 gun (255 = all that are ready): fire at the enemy, from the gun console
const C_AIM := 22                   # u8 ESYS_*, AIM_ROOM + room or AIM_ANY: where on the enemy the guns aim, from the gun console
const C_HOLO := 23                  # u8 on: start (1) or stop (0) watching the holomap the player stands at
const S_HOLO := 31                  # the holomap (only to those watching it), after the ship's id: u16 count, then
                                    # the air (0..AIR_FULL) of every cell of the ship's floor in order (see
                                    # ShipMap.on_ship), u16 count, u16 per hole in the hull, u8 count, then per door
                                    # of the ship u8: bit 0 open, the rest Doors.flags shifted up by one
const C_DRONE := 25                 # (v54) u8 action (DRONE_*), u8 a: the scouting drone, from the drone monitor
const DRONE_LAUNCH := 1             # send one from the cargo at the enemy
const DRONE_STEER := 2              # a = the direction it is to go (DIR_*; DIR_NONE = stop)
const DRONE_BLOW := 3               # it blows itself up where it is
const S_DRONE := 33                 # (v54) the scouting drone, to all: u8 state (DRONE_*), u16 cell of the enemy's
                                    # drawing it is in, u8 seconds of battery left, u8 seconds until it gets there
                                    # (while flying), u8 drones in the cargo
const DRONE_NONE := 0
const DRONE_FLYING := 1             # on its way over
const DRONE_INSIDE := 2             # inside the enemy ship
const S_ECREW := 34                 # (v54) the enemy's crew we can see now (a probe shows them all for a while, the
                                    # drone those near it), after the ship's id: u8 seconds the probe still shows them
                                    # (0 = it does not), u8 count, then per one u16 the cell of the enemy's drawing it
                                    # stands in, u8 flags (ECREW_*)
const ECREW_MENDING := 1            # mending the system in its room
const ECREW_HURT := 2               # wounded: it goes to lie low in its quarters
# (v55) our own crew at their posts in a fight, bots under orders, the battle position (see Stations)
const C_ORDER := 26                 # u16 id of a bot (NOBODY = every bot: POST_ALL sends them to the posts
                                    # nobody mans, POST_FREE stands them all down), u8 POST_*: the captain's order
const C_POSITION := 27              # u8 POS_*: the pilot takes the ship to that battle position, from the ship's controls
const C_BENCH := 28                 # (v58) u8 action (BENCH_*), u8 thing (a gun in the locker): work at the workbench
const BENCH_STOP := 0               # put the work down
const BENCH_APART := 1              # take the gun apart into parts of its kind
const BENCH_MEND := 2               # mend a damaged gun (one spare part)
const BENCH_UPGRADE := 3            # make it the next gun of its line (parts of its kind)
const BENCH_SHELLS := 4             # (v60) make shells of a spare part (the thing byte is not used)
const BENCH_ROCKETS := 5            # (v60) make rockets of a spare part
const BENCH_EMP := 6                # (v60) make an EMP rocket of a spare part
const C_BLAST := 29                 # (v60) u8 door of the ship (BLAST_ALL / BLAST_NONE: every door): lock it as a blast
                                    # door, or unlock it, from the holomap the player watches
const BLAST_ALL := 255
const BLAST_NONE := 254
const S_MOUNTS := 39                # (v60) to all, after the ship's id: u8 count of mounts, then per mount u8 1 if a gunner
                                    # stands at it, u8 the gun the console ordered onto it (a thing; 0 = none, 255 = take it down)
const S_STATIONS := 35              # to all, after the ship's id: u8 position (POS_*), u8 the one it is going to
                                    # (POS_NONE = none), u8 seconds of the manoeuvre left, u8 our dodge in %, u8 our hit
                                    # +100 in %, u8 theirs +100 in %, u8 posts manned (STATION_* bits), u8 count,
                                    # then per bot u16 id, u8 order (POST_*), u8 what it does (DOING_*)
const POST_FREE := 0                # no order: it goes about as it likes
const POST_HELM := 1                # at the ship's controls (it dodges the enemy's shots)
const POST_GUNS := 2                # at the gun console (a bot there fires what is ready)
const POST_ENGINE := 3              # at the engine (a little more dodge)
const POST_SHIELD := 4              # at the shield generator (it refills faster)
const POST_REPAIR := 5              # mending what is broken, holes in the hull included
const POST_FOLLOW := 6              # after the one who gave the order
const POST_MOUNTS := 7              # (v60) at a gun mount in a gun bay (its gun charges faster)
const POSTS := 8
const POST_ALL := 255               # (with NOBODY) every bot to a post nobody mans
const POST_NAMES: Array[String] = ["Свободен", "Штурвал", "Пульт орудий", "Двигатель", "Щиты", "Работы", "За мной", "У орудия"]
const STATION_HELM := 1
const STATION_GUNS := 2
const STATION_ENGINE := 4
const STATION_SHIELD := 8
const DOING_IDLE := 0               # nothing to do (free, or no work for it)
const DOING_GOING := 1              # on its way
const DOING_POST := 2               # at its post
const DOING_WORK := 3               # mending
const DOING_DOWN := 4               # out cold or dead
const DOING_NO_WAY := 5             # it cannot get there
const DOING_CARRY := 6              # (v60) fetching from the supply locker or carrying a gun
const DOING_HEAL := 7               # (v60) wounded: gone to lie in the autodoc
const DOING_NAMES: Array[String] = ["ждёт", "идёт", "на посту", "чинит", "без сознания", "не может пройти", "носит", "лечится"]
const POS_CLOSE := 0                # close in: both fire as before; boarding either way
const POS_FAR := 1                  # at a distance: both hit less, their boarding comes slower
const POS_FLANK := 2                # on its flank: we hit better, but dodge worse
const POS_BEHIND := 3               # (v59) behind it, only by the phase drive: we hit better, it hits worse
const POS_NONE := 255
const POS_NAMES: Array[String] = ["Вплотную", "На дистанции", "С фланга", "В тыл"]
const S_GEAR := 38                  # (v59) the ship's gear, to all, after the ship's id: u8 SYSTEMS, then per system its tier,
                                    # u8 MODULE_SLOTS, then per slot the crate in it (Gear.*; NONE = empty), u8 seconds until
                                    # the phase drive is charged (0 = ready), u8 flags (GEARF_*)
const GEARF_HARDENED := 1           # the shield stops rockets (the top shield generator, or the old hardening)
# The enemy ship's systems: each stands in a room of its drawing (ShipMap.rooms; which room is
# rolled for every ship, see Shipyard; a hand-made drawing may name them with ShipMap.zones). A hit
# there wears it down; at nothing it stops working until the enemy's crew mends it.
const ESYS_WEAPONS := 0             # its guns: down, it does not shoot
const ESYS_HELM := 1                # its bridge: down, it shoots wide and cannot dodge
const ESYS_ENGINE := 2              # its engine: down, it cannot close in to dock, nor jump away
const ESYS_CREW := 3                # its quarters: every few hits there kill one of its crew
const ESYS_JUMP := 4                # its jump drive: worn, it charges a jump slower; down, it cannot jump away
const ESYS_SHIELDS := 5             # its shield generator: worn, the shield refills slower; down, it has none
const ESYS_TELEPORT := 6           # (v57) the boarding flagship's teleporter (v62: and some pirates'): down, it sends nobody across
const ESYS_DRONES := 7              # (v62) a drone ship's control core: down, it sends no assault drones and mends nothing;
                                    # wrecked by our boarders, the ship is taken
const ESYS_COUNT := 8
const ESYS_NAMES: Array[String] = ["Орудия", "Рубка", "Двигатель", "Кубрик", "Гипердвигатель", "Щиты", "Телепорт", "Ядро дронов"]
const ENEMY_RAID := 1               # (S_GUNS flags) it fights at a distance and does not mean to dock
const ENEMY_FLEEING := 2            # it is charging its jump drive to get away
const ENEMY_HELD := 4               # (v50) our tractor beam holds it
const ENEMY_RANSOM := 8             # (v54) it offers a ransom to be let go (see the ransom byte at the end of S_GUNS)
const ENEMY_PHASE2 := 16            # (v62) the flagship has gone into its second phase
const ENEMY_CREWLESS := 32          # (v62) a drone ship: nobody aboard, a machine fights
const AIM_ANY := 255                # the guns hit wherever they hit
const AIM_ROOM := 64                # (v53) AIM_ROOM + n: the guns aim at room n of its drawing, whatever is in it
# (v53) the classes of pirate ship (see Hulls), and how they behave in a fight
const ECLASS_CUTTER := 0
const ECLASS_RAIDER := 1
const ECLASS_GUNSHIP := 2
const ECLASS_CRUISER := 3
const ECLASS_BATTLESHIP := 4        # (v57) the flagship at the goal point, first kind: guns that aim well
const ECLASS_CARRIER := 5           # (v57) the flagship, second kind: crew-hurting guns and a teleporter
const ECLASS_DRONE := 6             # (v62) a crewless drone ship: a machine, sends assault drones, airless inside
const TEMPER_CALCULATING := 0
const TEMPER_CAUTIOUS := 1
const TEMPER_RECKLESS := 2
const TEMPER_HUNTER := 3
const TEMPER_SIEGE := 4             # (v57) the battleship's: shield first, then the engine
const TEMPER_STORM := 5             # (v57) the carrier's: knocks the crew down, boards the bridge
const TEMPER_MACHINE := 6           # (v62) a drone ship's: never runs, never bargains
const TEMPER_UNKNOWN := 255
const C_WEAR := 20                  # u8 WEAR_*: take that off, into the hand (or a free slot)
const S_SHOT := 25                  # u8 kind (SHOT_*), u8 hit (1 = somebody was hit), s16 from x * 16,
                                    # s16 from y * 16, s16 to x * 16, s16 to y * 16: for drawing; (v56) then
                                    # u8 ticks before it shows, u8 ticks it flies (0 = a trace drawn at once)
const SHOT_BULLET := 1
const SHOT_BLOW := 2
const SHOT_CANNON := 3              # a ship's gun firing, or the enemy's shot landing on us
const SHOT_ION := 4                 # (v49) an ion shot: blue
const SHOT_ROCKET := 5              # a rocket: a smoky trail
const SHOT_PLASMA := 6              # a blaster's pellet: green
const SHOT_BEAM := 7                # a pulse of the cutting beam: a thin white-violet line
const SHOT_TRACTOR := 8             # (v50) the tractor beam: a pale green line
const SHOT_SIPHON := 9              # (v50) a pulse of the siphon beam: a cyan line
const SHOT_NEURAL := 10             # (v57) the flagship's neural shot: a violet bolt that stuns whoever is in the room
# (v58) every new gun has a look of its own (the author: guns are learnt by look and sound)
const SHOT_SHELL := 11              # an autocannon's shell: a short yellow tracer
const SHOT_RAIL := 12               # a railgun's slug: a long white-blue streak, very quick
const SHOT_FLAK := 13               # point defence firing: a spray of small bursts
const SHOT_PHOENIX := 14            # the «Феникс»: a big orange-gold bolt with a fiery tail
const SHOT_STORM := 15              # the «Буря»: a crackling deep blue ball
const SHOT_HEAVY_ROCKET := 16       # the «Опустошитель»: a fat rocket, red flame, thick smoke
const SHOT_REAPER := 17             # the «Жнец»: a crimson beam
const SHOT_NOVA := 18               # the «Сверхновая»: a blinding white-violet ball
const SHOT_HAMMER := 19             # the «Молот»: a heavy glowing slug
const SHOT_BOMB := 20               # (v62) a bomb: no flight across, a shimmer where it is teleported in, then its burst
const SHOT_SHRAPNEL := 21           # (v62) «Шрапнель»: a cloud of small glowing fragments
# (for a ship's shot, hit 0 = it was stopped by a shield short of the hull, LANDED where it lands, MISSED: flies past)
const LANDED := 1
const MISSED := 2
const RICOCHET := 3                 # (v58) a kinetic shell turned aside by armour: it does nothing
const SHOT_DOWN := 4                # (v58) a rocket shot down by point defence on its way
const S_VOLLEY := 36                # (v56) a ship's shot, to all, for the gun console's plan: u8 whose (VOLLEY_*),
                                    # u8 kind (SHOT_*), u8 how it ends (0 shield, LANDED, MISSED), u8 room of the
                                    # enemy's drawing (ours: where it lands; theirs: where it was fired from;
                                    # 255 = none), u8 ticks before it is fired, u8 ticks it flies
const VOLLEY_OURS := 0
const VOLLEY_THEIRS := 1
const S_JOLT := 37                  # (v56) the sound of the ship fight, to everyone: u8 kind (JOLT_*),
                                    # u8 the shot's kind (SHOT_*; for JOLT_FIRE the weapon, Weapons.*), s16 x, s16 y of where it happened. Blows to our own
                                    # hull are felt everywhere aboard (the screen shakes); all of it is heard only where
                                    # there is air round the one who hears (the author asked for the fight to be heard)
const JOLT_HULL := 1                # a shot landing on our hull
const JOLT_HEAVY := 2               # a heavy blow to it: a rocket, a heavy laser, a meteor
const JOLT_SHIELD := 3              # our shield taking a shot
const JOLT_FIRE := 4                # one of our guns firing
const JOLT_THEIR_HIT := 5           # a shot of ours blowing up on the pirate ship
const JOLT_THEIR_SHIELD := 6        # its shield stopping one of ours
const S_SHIPS := 26                 # every ship in the world: u8 count, then per ship u16 id, u8 kind (SHIP_*),
                                    # u8 docked, s16 x, s16 y of its corner in the grid, u8 its drawing (its
                                    # number in OTHER_MAPS; 0 for our own), u8 name length, name.
                                    # A ship other than the client's own is the one alongside (see ShipMap.place_other).
const CREW_SHIP := 1                # the network id of the crew's own ship (another ship gets a new one each time)
const SHIP_CREW := 0                # kinds of ship
const SHIP_DERELICT := 1
const SHIP_PIRATE := 2
const SHIP_WRECK := 3               # a pirate ship our guns have wrecked: dark and dead, but it can be boarded
# the kinds of other ship that may come alongside, and their maps (in this order: ShipMap.others)
const OTHER_DERELICT := 0
const OTHER_PIRATE := 1
# (v53) every drawing from OTHER_PIRATE on is a pirate ship's: see Hulls for which class each is
const OTHER_MAPS: Array[String] = ["derelict01", "pirate01", "pirate02", "pirate03", "pirate04", "pirate05", "pirate06", "pirate07",
	"pirate08", "pirate09"]
# (v63) the road and its story (see Story, Garden)
const C_COMMS := 31                 # u8 choice (its number on the screen): answer the call on the comms console
const S_COMMS := 41                 # to all: the comms console's screen. u8 state (COMMS_*), u16 seconds left to answer,
                                    # u16 title length, title, u16 text length, text, u8 count of choices, then per
                                    # choice u8 flags (CHOICE_*), u16 length, its text
const COMMS_QUIET := 0              # nobody calls (the title and text are the last call's outcome, or empty)
const COMMS_CALL := 1               # a call waits for an answer
const CHOICE_BLUE := 1              # a blue option: open thanks to somebody's job, a skill, gear or cargo
const CHOICE_SHUT := 2              # cannot be taken now (it needs what the ship has not got)
const S_STORY := 42                 # to all: u8 flags (STORY_*), s16 x, s16 y of the flagship's sector, u8 its growth,
                                    # u16 seconds to its next step (65535 = none), u8 count of quests, then per quest
                                    # u8 kind (QUEST_*), s16 x, s16 y, u16 reward, u16 title length, title, u16 text
                                    # length, text; u8 count of marks, per mark u8 kind (MARK_*), s16 x, s16 y
const STORY_FLAGSHIP := 1           # the flagship roams its area: its sector is known
const STORY_CAUGHT := 2             # it is fighting us now (its growth stands still)
const STORY_STARVING := 4           # the locker has no rations: the crew starve
const STORY_CODES := 8              # the flagship's codes are ours (the chapter's second mission)
const STORY_AWAKE := 16             # the flagship has woken: its growth clock runs
const QUEST_CARGO := 0              # carry a crate of cargo to a station
const QUEST_BOUNTY := 1             # a named pirate ship waits in a sector: beat it
const QUEST_BLACKBOX := 2           # a wreck's black box: bring it back to the supply locker
const QUEST_MISSION := 3            # a chapter of the story (it has a quest kind of its own inside)
const MARK_SOS := 0                 # a distress call comes from that sector
const MARK_QUEST := 1               # a quest's target
const S_GARDEN := 43                # to all: u8 count of trays, per tray u16 cell, u8 seed (ITEM_SEED + ...; 0 = empty),
                                    # u8 stage (GROW_*), u8 growth 0..100, u8 flags (GARDEN_*)
const GROW_EMPTY := 0
const GROW_GROWING := 1
const GROW_RIPE := 2
const GROW_DEAD := 3                # withered: cleared by hand
const GARDEN_CARE := 1              # it wants tending
const GARDEN_DARK := 2              # no power: it stands still (mushrooms grow anyway)
const GARDEN_NEGLECT := 4           # left untended too long: it grows at half pace and will wither
# (v63, the author's K23) how hard the game is, chosen when it is created
const MODE_NORMAL := 0
const MODE_EASY := 1                # hull at nothing costs the hull's top strength, not the voyage
const MODE_HARD := 2                # fiercer pirates, one more boarder, less money from loot, the flagship grows faster
const MODE_NAMES: Array[String] = ["Обычный", "Лёгкий", "Тяжёлый"]
const MODE_KEYS: Array[String] = ["normal", "easy", "hard"]
const EASY_HULL_LOSS := 50          # (easy) what a hull worn to nothing costs its top strength...
const EASY_HULL_LEAST := 50         # ... and below this top strength the ship is lost after all
const S_SOUND := 24                 # u8 kind (SOUND_*), s16 x, s16 y: something was heard there
const S_STORE := 22                 # the ship's supplies: u16 air for the air plant in tenths of a cell's
                                    # worth, u16 credits, u8 count, then pairs: u8 thing (ITEM_*), u16 how
                                    # many of it the locker holds

# what a player may ask of the supply locker (C_STORE)
const STORE_TAKE := 1               # one of the thing named
const STORE_PUT_BACK := 3           # everything carried that the locker keeps goes back into it
const STORE_PUT_ONE := 9            # the thing in one slot (the thing byte names the slot) goes back into it
const STORE_BUY := 4                # one of the thing named; this and the one below only while docked with a trader
const STORE_BUY_AIR := 6
const STORE_HIRE := 7               # take on one more crew member for the reserve (from a trader)
const STORE_BUY_HULL := 8           # have the hull patched up by HULL_LOT (from a trader)
const STORE_SELL := 10              # sell one of the thing named from the locker to a trader (at its share: Sectors.DEAL_SELL)
const STORE_HARDEN := 11            # buy the shield hardening from a trader who offers it
const STORE_BUY_BACK := 12          # (v58) buy back from a trader a thing we sold it, at the price it paid
const S_TRADE := 32                 # what the trader alongside offers (sent when it changes): u8 count, then per thing
                                    # u8 ITEM_*, u16 price; then u8 TRADE_* flags. Count 0 = no trader. (v58) Then, with
                                    # a trader: u8 deal (Sectors.DEAL_*), u8 x3 % it pays (plain, guns, ammunition),
                                    # u8 count of things it sells back, pairs u8 ITEM_*, u16 price (see Supplies.trade_packet).
const TRADE_HARDEN := 1             # it offers the shield hardening

# supplies. Mending a hole takes a patch; mending a machine or a door takes a
# spare part, or three times as long without one.
const START_CREDITS := 30           # (what the locker starts with, and prices of things: see Items)
const STORE_AIR_FULL := 60.0        # air the air plant can give out before it must be restocked, in cells' worth
const PRICE_AIR := 5                # for AIR_LOT cells' worth
const AIR_LOT := 10.0
const EXPLORE_REWARD := 15          # credits for the first visit to a sector
const NO_PART_SLOWER := 3           # how many times longer a repair without a spare part takes
const STATION_FUEL := 3             # a supply station tops the fuel in the locker up to this many cans
const WRECK_FUEL := 1               # cans of fuel salvaged from a wrecked pirate ship

# The campaign: what is at stake. The ship carries a reserve of crew: a dead
# player comes back only by taking one of them. The hull has a strength that
# every hole takes from; at nothing the ship breaks up. Either loss ends the campaign.
const S_CAMPAIGN := 29              # u8 hull, u8 reserve, u8 over (OVER_*), u16 sectors visited, u16 farthest
                                    # (jumps from the start), u16 jumps made, u32 seconds the voyage has lasted,
                                    # (v57) u8 1 = the flagship is beaten (the game is won; the voyage goes on),
                                    # (v63) u8 the hull's top strength, u8 the mode (MODE_*)
const OVER_NONE := 0
const OVER_WRECKED := 1             # the hull gave way
const OVER_CREW_LOST := 2           # everyone dead, nobody left in the reserve
const OVER_CAPTURED := 3            # (v57) the whole crew is down with the flagship's boarders aboard: the ship is theirs
const OVER_TEXT: Array[String] = ["", "Корабль разрушен: обшивка не выдержала.", "Экипаж погиб, и заменить его некем.",
	"Весь экипаж повержен, и абордажники флагмана захватили корабль."]
const START_RESERVE := 3
const RESERVE_MAX := 9
const PRICE_CREW := 30
const HULL_MAX := 200                # (v49: was 100, the author asked for more)
const HULL_PER_HOLE := 5            # strength a hole in the hull takes
const HULL_PER_SYSTEM_HIT := 3      # and a pirate shot that puts a gun or a console out of order
const HULL_LOT := 20                # a trader patches up this much
const PRICE_HULL := 10

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
const SOUND_PHASE := 10             # (v59) the phase drive throwing the ship to its new position: heard all over it
const SOUND_RANGE: Array[int] = [0, 6, 8, 12, 10, 5, 7, 18, 8, 12, 40]
const SOUND_AIR := 0.2              # below this share of normal pressure there is no sound
const SOUND_CONTACT := 1.5          # this close a sound is felt even in a vacuum

const ADMIN_BREACH := 1             # tear a hole in the hull near the player who asked (tests)
const ADMIN_SEAL := 2               # close every hole (tests)
const ADMIN_EVENT := 3              # make the director fire the event whose id is the argument
const ADMIN_AUTO := 4               # argument 1: the director runs events by itself; 0: only by hand
const ADMIN_SAVE := 5               # save the campaign now and say so
const ADMIN_HELLO := 6              # the hosting player's game makes itself known: its player is the host and an admin
const ADMIN_GIVE := 7               # the thing (argument) into the admin's hand or a free slot, else at its feet
const ADMIN_HEAL := 8               # the target is made whole: health, wounds, oxygen; the dead come back to life
const ADMIN_KILL := 9               # the target dies
const ADMIN_GOTO := 10              # the admin is put beside the target
const ADMIN_BRING := 11             # the target is put beside the admin
const ADMIN_GRANT := 12             # (host only) argument 1: the target becomes an admin, 0: no longer
const ADMIN_JOB := 13               # the target takes the job given as the argument (JOB_*)
const ADMIN_REPAIR := 14            # every hole closed, every machine and door mended, the power back
const ADMIN_AIR := 15               # normal air in every cell of the ship, the air plant's store full
const ADMIN_RESTOCK := 16           # the supply locker filled up to what a ship sets out with, at least
const ADMIN_CREDITS := 17           # +100 credits
const ADMIN_HULL := 18              # the hull as strong as new
const ADMIN_RESERVE := 19           # +1 in the crew reserve
const ADMIN_PIRATE := 20            # a pirate (argument 1: with a pistol, 0: with a baton) in front of the admin
const ADMIN_PLACE := 21             # the sector becomes one of that kind (Sectors.*) and the ship is put at its spot
const ADMIN_STORE := 22              # (v60.1) the thing (argument) into the supply locker
const ADMIN_FIT := 23               # (v60.1) gear put in at once: Gear.* (argument); ADMIN_FIT_BUILT_IN + system: back to
                                    # the built-in one; ADMIN_FIT_CLEAR_BAY: the module bay emptied
const ADMIN_FIT_BUILT_IN := 100
const ADMIN_FIT_CLEAR_BAY := 200
const ADMIN_CHARGE := 24            # (v60.1) shield full, guns charged, the jump drive and the phase drive ready
const ADMIN_SKILLS := 25            # (v60.1) every skill of the target at its best
const ADMIN_BOTS := 26              # (v60.1) argument 1: one bot more in the crew, 0: one less
const ADMIN_SMES := 28              # (v61) argument: every SMES charged to that many tenths (10 = full, 0 = empty)
const ADMIN_SURGE := 29             # (v61) an ion surge now: one of our things put out for a while (and theirs, in a fight)
const ADMIN_FIGHT := 27             # (v60.1) a pirate ship comes: argument = class * 16 + temper * 2 + (1: a fight at a
                                    # distance, 0: it docks to board); temper ADMIN_ANY_TEMPER = rolled
const ADMIN_ANY_TEMPER := 7
const ADMIN_TRADER_DEAL := 16       # (v60.1) ADMIN_PLACE of a trader + this * (1 + Sectors.DEAL_*): a trader of that kind
const ADMIN_CREDITS_GIVEN := 100
const ADMIN_TALE := 30              # (v63) the comms console takes the call of that event (Tales.ALL index; 255 = any that fits)
const ADMIN_GROW := 31              # (v63) the flagship wakes in its area (if not yet) and takes one more step of growth
const ADMIN_GARDEN := 32            # (v63) every tray ripe now

const NO_SECTOR := 255
const JUMP_TICKS := 160             # a jump takes 8 s to charge
const DRIVE_REST_TICKS := 300       # and the drive needs 15 s after landing
const SYSTEM_ID := 65535            # "from" of chat lines written by the ship itself
# who hears what is said (the channel of S_CHAT)
const CHAT_SHIP := 0                 # the ship's own messages, to everyone or one player
const CHAT_NEAR := 1                 # spoken aloud: those close by, on the same deck, with air to carry it
const CHAT_RADIO := 2                # by radio (";" in front): everyone with a radio, anywhere, in a vacuum too
const CHAT_INTERCOM := 3             # into an intercom ("!" in front): those near any intercom; needs power
const CHAT_DEAD := 4                 # between the dead only
const CHAT_RADIO_MARK := ";"
const CHAT_INTERCOM_MARK := "!"
const SPEECH_RANGE := 7.0            # cells a voice carries
const INTERCOM_REACH := 1.5          # how close to an intercom one speaks into it
const INTERCOM_HEAR := 6.0           # how far from an intercom it is heard

const REJECT_VERSION := 1
const REJECT_FULL := 2
const REJECT_BAD_HELLO := 3
const REJECT_NO_CREW := 4           # the player's character is dead and the reserve is empty

const SUIT_COLOURS := 8             # rows in assets/chars.png

# Condition of a character. It travels in the same byte as the facing.
const COND_OK := 0
const COND_CRIT := 1                # unconscious on the floor
const COND_DEAD := 2
const HEALTH_FULL := 100
const HEALTH_DEAD := -100
const RESPAWN_TICKS := 100          # a dead player may come back after 5 s

# Jobs. Each gives access to some rooms (the doors of a restricted room open
# only for those who have its access, while the ship has power) and decides
# which skills grow quickly: the others grow slowly.
const ACCESS_BRIDGE := 1
const ACCESS_ENGINE := 2            # the engine room and life support
const ACCESS_MEDBAY := 4
const ACCESS_ARMORY := 8
const ACCESS_GUNS := 16             # the gun bays
const ACCESS_ALL := 31
const ACCESS_OURS := 32             # (v60) one of our own crew: blast doors open for them (pirates lack it); see access_of
const ACCESS_NAMES := {ACCESS_BRIDGE: "мостик", ACCESS_ENGINE: "машинное отделение", ACCESS_MEDBAY: "медблок",
	ACCESS_ARMORY: "арсенал", ACCESS_GUNS: "орудийный отсек"}
const JOB_CREWMAN := 0
const JOB_CAPTAIN := 1
const JOB_PILOT := 2
const JOB_ENGINEER := 3
const JOB_MEDIC := 4
const JOB_GUARD := 5
const JOBS := 6
const JOB_NAMES: Array[String] = ["Матрос", "Капитан", "Пилот", "Инженер", "Врач", "Охранник"]
const JOB_ABOUT: Array[String] = [
	"Без особых доступов. Учится всему понемногу.",
	"Доступ везде. Один на корабль.",
	"Мостик: карта сектора, управление, пульт орудий.",
	"Машинное отделение, жизнеобеспечение, орудийные отсеки. Быстро чинит.",
	"Медблок. Быстро лечит.",
	"Арсенал и орудийные отсеки. Метко стреляет.",
]
const JOB_ACCESS: Array[int] = [0, ACCESS_ALL, ACCESS_BRIDGE, ACCESS_ENGINE | ACCESS_GUNS, ACCESS_MEDBAY, ACCESS_ARMORY | ACCESS_GUNS]
# skills, 0..SKILL_MAX: how quickly one mends, treats, how well one shoots
const SKILL_REPAIR := 0
const SKILL_MEDICINE := 1
const SKILL_GUNS := 2                # (v60) also the ship's guns: at the gun console and at a mount
const SKILL_PILOT := 3               # (v60) at the ship's controls in a fight: dodging
const SKILLS := 4
const SKILL_NAMES: Array[String] = ["ремонт", "медицина", "стрельба", "пилотирование"]
const SKILL_MAX := 100
const JOB_SKILL: Array[int] = [-1, -1, SKILL_PILOT, SKILL_REPAIR, SKILL_MEDICINE, SKILL_GUNS]   # the skill a job is about
const JOB_START_SKILL := 50          # where a job's own skill starts
const SKILL_GAIN := 2                # what one piece of work adds to its job's own skill
const SKILL_GAIN_OTHER := 1          # and, every SKILL_SLOW_EVERY such pieces, to any other skill
const SKILL_SLOW_EVERY := 3
static func access_of(job: int) -> int:
	## (v60) The rooms a job lets one into, and the mark of our own crew.
	return JOB_ACCESS[clampi(job, 0, JOBS - 1)] | ACCESS_OURS


const HACK_TICKS := 100             # holding "use" on a door one has no access to for 5 s breaks its lock
const S_ME := 30                    # u8 job, then SKILLS bytes: our own character's job and skills, then u8 flags
                                    # (ME_ADMIN, ME_HOST)
const ME_ADMIN := 1                 # may use the admin panel
const ME_HOST := 2                  # is the hosting player: may make others admins

# who a roster entry is
const KIND_PLAYER := 0
const KIND_BOT := 1
const KIND_CORPSE := 2              # a body left behind; nobody controls it
const KIND_PIRATE := 3              # an enemy the server moves
const KIND_ROBOT := 4                # (v62) our security robot: a machine the server moves; not crew
const PIRATE_COLOURS := 3           # rows of assets/chars.png after the crew's SUIT_COLOURS: pirates' suits
const ROBOT_COLOUR := SUIT_COLOURS + PIRATE_COLOURS        # (v62) the row of an enemy robot (assault drone, guard)
const OUR_ROBOT_COLOUR := ROBOT_COLOUR + 1                 # (v62) the row of our security robot
const ARMOUR_COLOUR := ROBOT_COLOUR + 2                    # (v62) the row of a heavy-armoured boarder (steel plates, no suit)

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
		REJECT_NO_CREW:
			return "Ваш персонаж погиб, а резерв экипажа пуст. Вернуться можно, когда товарищи наймут людей у торговца."
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
