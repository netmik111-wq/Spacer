extends RefCounted
## Constants shared by the server and the client: simulation rates and the
## network protocol. Change PROTOCOL whenever a packet layout changes, so old
## clients are refused with a clear message instead of misreading data.

const PROTOCOL := 30
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
const ITEM_GUN_MORE := 60           # (v50) weapons from Weapons.TRACTOR on: ITEM_GUN_MORE + Weapons.* (71, 72)
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

const S_POWER := 21                 # u8 on: the ship has power (1) or every system stands still (0)

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
                                    # u8 count, then u8 per weapon the enemy carries (Weapons.*)
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
const GUNSET_MOUNT := 3             # a = mount, b = the weapon from the cargo to put on it (Weapons.*; NONE = take it
                                    # down into the cargo)
const C_GUNS := 21                  # u8 gun (255 = all that are ready): fire at the enemy, from the gun console
const C_AIM := 22                   # u8 ESYS_* or AIM_ANY: where on the enemy the guns aim, from the gun console
const C_HOLO := 23                  # u8 on: start (1) or stop (0) watching the holomap the player stands at
const S_HOLO := 31                  # the holomap (only to those watching it), after the ship's id: u16 count, then
                                    # the air (0..AIR_FULL) of every cell of the ship's floor in order (see
                                    # ShipMap.on_ship), u16 count, u16 per hole in the hull, u8 count, then per door
                                    # of the ship u8: bit 0 open, the rest Doors.flags shifted up by one
# The enemy ship's systems: each stands in a room of its drawing (ShipMap.zones). A hit
# there wears it down; at nothing it stops working until the enemy's crew mends it.
const ESYS_WEAPONS := 0             # its guns: down, it does not shoot
const ESYS_HELM := 1                # its bridge: down, it shoots wide and cannot dodge
const ESYS_ENGINE := 2              # its engine: down, it cannot close in to dock, nor jump away
const ESYS_CREW := 3                # its quarters: every few hits there kill one of its crew
const ESYS_JUMP := 4                # its jump drive: worn, it charges a jump slower; down, it cannot jump away
const ESYS_SHIELDS := 5             # its shield generator: worn, the shield refills slower; down, it has none
const ESYS_COUNT := 6
const ESYS_NAMES: Array[String] = ["Орудия", "Рубка", "Двигатель", "Кубрик", "Гипердвигатель", "Щиты"]
const ENEMY_RAID := 1               # (S_GUNS flags) it fights at a distance and does not mean to dock
const ENEMY_FLEEING := 2            # it is charging its jump drive to get away
const ENEMY_HELD := 4               # (v50) our tractor beam holds it
const AIM_ANY := 255                # the guns hit wherever they hit
const C_WEAR := 20                  # u8 WEAR_*: take that off, into the hand (or a free slot)
const S_SHOT := 25                  # u8 kind (SHOT_*), u8 hit (1 = somebody was hit), s16 from x * 16,
                                    # s16 from y * 16, s16 to x * 16, s16 to y * 16: for drawing
const SHOT_BULLET := 1
const SHOT_BLOW := 2
const SHOT_CANNON := 3              # a ship's gun firing, or the enemy's shot landing on us
const SHOT_ION := 4                 # (v49) an ion shot: blue
const SHOT_ROCKET := 5              # a rocket: a smoky trail
const SHOT_PLASMA := 6              # a blaster's pellet: green
const SHOT_BEAM := 7                # a pulse of the cutting beam: a thin white-violet line
const SHOT_TRACTOR := 8             # (v50) the tractor beam: a pale green line
const SHOT_SIPHON := 9              # (v50) a pulse of the siphon beam: a cyan line
# (for a ship's shot, hit 0 = it was stopped by a shield short of the hull)
const S_SHIPS := 26                 # every ship in the world: u8 count, then per ship u16 id, u8 kind (SHIP_*),
                                    # u8 docked, s16 x, s16 y of its corner in the grid, u8 name length, name.
                                    # A ship other than the client's own is the one alongside (see ShipMap.place_other).
const CREW_SHIP := 1                # the network id of the crew's own ship (another ship gets a new one each time)
const SHIP_CREW := 0                # kinds of ship
const SHIP_DERELICT := 1
const SHIP_PIRATE := 2
const SHIP_WRECK := 3               # a pirate ship our guns have wrecked: dark and dead, but it can be boarded
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
const STORE_PUT_ONE := 9            # the thing in one slot (the thing byte names the slot) goes back into it
const STORE_BUY := 4                # one of the thing named; this and the one below only while docked with a trader
const STORE_BUY_AIR := 6
const STORE_HIRE := 7               # take on one more crew member for the reserve (from a trader)
const STORE_BUY_HULL := 8           # have the hull patched up by HULL_LOT (from a trader)
const STORE_SELL := 10              # sell one of the thing named from the locker to a trader (Weapons.SELL_SHARE of its price)
const STORE_HARDEN := 11            # buy the shield hardening from a trader who offers it
const S_TRADE := 32                 # what the trader alongside offers (sent when it changes): u8 count, then per thing
                                    # u8 ITEM_*, u16 price; then u8 TRADE_* flags. Count 0 = no trader.
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
                                    # (jumps from the start), u16 jumps made, u32 seconds the voyage has lasted
const OVER_NONE := 0
const OVER_WRECKED := 1             # the hull gave way
const OVER_CREW_LOST := 2           # everyone dead, nobody left in the reserve
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
const SOUND_RANGE: Array[int] = [0, 6, 8, 12, 10, 5, 7, 18, 8, 12]
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
const ADMIN_CREDITS_GIVEN := 100

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
const SKILL_GUNS := 2
const SKILLS := 3
const SKILL_NAMES: Array[String] = ["ремонт", "медицина", "стрельба"]
const SKILL_MAX := 100
const JOB_SKILL: Array[int] = [-1, -1, -1, SKILL_REPAIR, SKILL_MEDICINE, SKILL_GUNS]   # the skill a job is about
const JOB_START_SKILL := 50          # where a job's own skill starts
const SKILL_GAIN := 2                # what one piece of work adds to its job's own skill
const SKILL_GAIN_OTHER := 1          # and, every SKILL_SLOW_EVERY such pieces, to any other skill
const SKILL_SLOW_EVERY := 3
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
