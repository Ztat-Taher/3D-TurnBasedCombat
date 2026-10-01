@tool
class_name PartyData
extends Resource
## Player party template for the current run.
##
## A data-only container (e.g. res://database/party/player_party.tres) that
## stores the starting composition of the run party. GameState clones it into a
## fresh, mutable array of [AllyPartyMember] resources at the start of each new
## run so the saved progress always starts clean.

## The starting allies for this run, in battle order.
@export var allies: Array[AllyPartyMember] = []

## Add an ally to this template.
func add_ally(stats: BattlerStats, _deck_override: DeckResource = null) -> AllyPartyMember:
	assert(stats != null, "PartyData: add_ally requires a BattlerStats resource.")
	var member := AllyPartyMember.new()
	member.stats = stats
	member.deck_path = stats.deck.resource_path if stats.deck else ""
	member.current_health = -1  # fresh ally: full (max_health stays 0 until first battle).
	member.level = stats.level
	allies.append(member)
	return member

## Find a party member in this template by display name.
func get_member_by_name(name: String) -> AllyPartyMember:
	for member in allies:
		if member.display_name == name:
			return member
		if member.stats and member.stats.character_name == name:
			return member
	return null

## Number of allies stored in this template.
func ally_count() -> int:
	return allies.size()

## Reset all allies to full health (called before a fresh run starts).
func reset_to_full_health() -> void:
	for member in allies:
		if member.max_health <= 0:
			member.current_health = -1  # never fought: counts as full
		else:
			member.current_health = member.max_health  # healed to full
