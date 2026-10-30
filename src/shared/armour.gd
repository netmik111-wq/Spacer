extends RefCounted
## (v98, the author's arsenal and body armour) What a body wears takes off part of a wound, by
## the kind of harm. Shared so that the client's hints say the same numbers the server uses.
##
## A spacesuit is armour too, and the author's idea: inflated (sealed) it keeps space out and
## takes little off; let down it keeps nothing out but takes more off every kind of harm.
## (his A2 and W1 answers) A vest takes off much of everything but plasma, and a helmet the
## same; neither goes on with a suit (armour is for fighting aboard, or boarding by pod). A
## helmet, and a suit's own, also halve concussions. What is worn multiplies.

const Net := preload("res://src/shared/net.gd")

const KINETIC := 0                   # bullets, pellets
const LASER := 1
const PLASMA := 2
const BLOW := 3                      # a baton, a stun baton
const BLAST := 4                     # bombs, a ship's hit inside
const OTHER := 5                     # nothing takes anything off it
const KINDS := 6
const NAMES: Array[String] = ["пули", "лазер", "плазма", "удары", "взрывы", ""]

# the share each takes off, by kind
const VEST: Array[float] = [0.45, 0.45, 0.0, 0.6, 0.3, 0.0]
const HELMET: Array[float] = [0.45, 0.45, 0.0, 0.6, 0.3, 0.0]
const SUIT_SEALED: Array[float] = [0.1, 0.1, 0.1, 0.1, 0.1, 0.0]
const SUIT_OPEN: Array[float] = [0.3, 0.3, 0.3, 0.3, 0.3, 0.0]
const HEAD_CONCUSS := 0.5            # a helmet (a suit's too) makes a concussion this much as likely
const HEAD_FLASH := 0.5              # and a flashbang's stun this much as long
const SWITCH_SECONDS := 2.0          # letting a suit down or sealing it again
# a personal energy shield (Net.SHIELD_FULL of charge)
const SHIELD_WAIT := 5.0             # seconds with no hit before it charges again
const SHIELD_RATE := 5.0             # then this much a second
const SHIELD_PLASMA := 2.0           # plasma drains it this many times over
# a hand shield on the arm stops what comes from within this angle of where one faces (each way)
const RIOT_ARC := PI / 3.0


static func taken(worn: PackedByteArray, deflated: bool, kind: int) -> float:
	## The share of a wound of that kind that gets through what is worn.
	var left := 1.0
	if worn.size() > Net.WEAR_SUIT and worn[Net.WEAR_SUIT] != Net.ITEM_NONE:
		left *= 1.0 - (SUIT_OPEN[kind] if deflated else SUIT_SEALED[kind])
	if worn.size() > Net.WEAR_BODY and worn[Net.WEAR_BODY] == Net.ITEM_VEST:
		left *= 1.0 - VEST[kind]
	if worn.size() > Net.WEAR_HEAD and worn[Net.WEAR_HEAD] == Net.ITEM_HELMET:
		left *= 1.0 - HELMET[kind]
	return left


static func headed(worn: PackedByteArray) -> bool:
	## Is the head covered (a helmet, or a suit's own)?
	return worn.size() > Net.WEAR_HEAD and (worn[Net.WEAR_SUIT] != Net.ITEM_NONE or worn[Net.WEAR_HEAD] == Net.ITEM_HELMET)


static func clash(worn: PackedByteArray, item: int) -> String:
	## Why that cannot be put on over what is worn ("" if it can): a suit has its own helmet.
	if item == Net.ITEM_HELMET and worn[Net.WEAR_SUIT] != Net.ITEM_NONE:
		return "У скафандра свой шлем: каску поверх не надеть."
	if item == Net.ITEM_VEST and worn[Net.WEAR_SUIT] != Net.ITEM_NONE:
		return "Бронежилет со скафандром не надеть: сначала снимите скафандр."
	if item >= Net.ITEM_SUIT and item <= Net.ITEM_SUIT + Net.SUIT_TANK_STEPS and (worn[Net.WEAR_HEAD] != Net.ITEM_NONE or worn[Net.WEAR_BODY] != Net.ITEM_NONE):
		return "Скафандр не надеть поверх брони: сначала снимите %s." % ("каску" if worn[Net.WEAR_HEAD] != Net.ITEM_NONE else "бронежилет")
	return ""
