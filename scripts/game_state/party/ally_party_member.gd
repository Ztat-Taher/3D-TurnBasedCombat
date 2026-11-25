class_name AllyPartyMember
extends Resource
## One ally in the run party.
##
## Stored inside [GameState] (persisted by GlobalState) so an ally's remaining
## HP, level/exp and card deck survive between run-map nodes (battles, rest
## sites, recruitments, ...).
##
## Battles copy these values onto the spawned [Battler] (see PartyBattleSync),
## while out-of-battle UIs (rest site, recruit screen) display the same data
## without loading a battle scene.

## The battler stats resource this ally is built from (e.g. PlayerData.tres).
## Used by battles to configure the spawned [Battler] and as the base for
## level-progression stat scaling. Always set for a valid party member.
@export var stats: BattlerStats = null

## Meta key used on a live [Battler] to link it back to its party member id.
const META_PARTY_MEMBER_ID : StringName = &"party_member_id"

## Unique id inside the run party (e.g. "ally_1").
@export var id : String = "ally_1"
## Display name shown in the party UI and the battle HUD.
@export var display_name : String = "Ally"
## Scene used to spawn this ally in battle.
@export_file("*.tscn") var ally_scene_path : String = "res://scenes/battle/core/allies/models/y_bot-ally.tscn"
## Deck resource used while [member deck] is unassigned.
@export_file("*.tres") var deck_path : String = "res://database/decks/player_deck.tres"
## This ally's own card deck. Kept per ally so card rewards can be applied to a
## single party member later. Null = load [member deck_path].
@export var deck : DeckResource
## Fallback portrait for out-of-battle UIs, used only when [member stats] has
## no [member BattlerStats.thumbnail] (set the portrait there, see [method get_portrait]).
@export_file("*.svg", "*.png") var portrait_path : String = "res://Placeholder.svg"

## This ally's weapon type — type-locks which [Weapon]s may be equipped.
@export var weapon_type : Weapon.WType = Weapon.WType.BLADE
## The currently equipped weapon (must be in [member inventory] and match
## [member weapon_type]). Null = fights unarmed.
@export var equipped_weapon : Weapon = null
## Per-ally item storage. Weapons are non-stackable [Weapon] items living here;
## battle items can share the same inventory.
@export var inventory : Inventory = null
## Character level, driving the level-progression stat scaling in battle.
@export var level : int = 1
## Accumulated experience, carried between battles.
@export var exp_total : int = 0
## Maximum HP, refreshed from the live battler after every battle (0 = unknown).
@export var max_health : int = 0
## Remaining HP carried between nodes. -1 = fresh ally at full HP, 0 = downed.
@export var current_health : int = -1


## True when the ally was downed (0 HP) during the previous battle.
func is_downed() -> bool:
	return current_health == 0


## True when the ally is at full health (a fresh, never-fought ally counts).
func has_full_health() -> bool:
	if max_health <= 0:
		return true
	return current_health >= max_health


## Max HP as a usable number, even before the ally has fought a battle.
## Single source of truth for UIs: the value the last battle wrote back
## (includes vestige bonuses), else the level-scaled base stat that battles
## start from (same formula as [method Battler.apply_level_progression]).
func get_max_health() -> int:
	if max_health > 0:
		return max_health
	return maxi(int(get_level_stats().get("max_health", 1)), 1)


## Current HP as a usable number ([code]-1[/code] = fresh ally = full HP).
func get_current_health() -> int:
	if current_health < 0:
		return get_max_health()
	return mini(current_health, get_max_health())


## Base stats scaled to this ally's level (HP, ATK, DEF, AGI, AP).
## Empty when [member stats] is unset.
func get_level_stats() -> Dictionary:
	if stats == null:
		return {}
	var base := {
		"max_health": stats.max_health,
		"attack": stats.attack,
		"defense": stats.defense,
		"agility": stats.agility,
		"max_ap": stats.max_ap,
	}
	var mults := {
		"max_health": stats.health_multiplier,
		"attack": stats.attack_multiplier,
		"defense": stats.defense_multiplier,
		"agility": stats.agility_multiplier,
		"max_ap": stats.ap_multiplier,
	}
	return LevelProgression.get_stats_at_level(base, mults, level)


## Name for UIs, falling back to [member id] when no display name is set.
func get_display_name() -> String:
	return display_name if not display_name.is_empty() else id


# ---------------------------------------------------------------------------
# Per-Character Vestiges system (ally-specific passive items)
# ---------------------------------------------------------------------------

## Per-character vestiges (ally-specific passive items)
@export var vestiges: Array[Vestige] = []
## Stack counts for vestiges (vestige_id -> stack_count)
@export var vestige_stacks: Dictionary = {}


## Add a vestige to this ally
func add_vestige(vestige: Vestige, stacks: int = 1) -> void:
	if vestige == null:
		return
	
	# Check if already owned
	for existing in vestiges:
		if existing and existing.vestige_id == vestige.vestige_id:
			# Update stack count if stacking is allowed
			if vestige.can_stack_with(get_vestige_stack_count(vestige.vestige_id)):
				vestige_stacks[vestige.vestige_id] = \
					mini(get_vestige_stack_count(vestige.vestige_id) + stacks, vestige.max_stacks)
			return
	
	# Add new vestige
	vestiges.append(vestige)
	vestige_stacks[vestige.vestige_id] = stacks


## Remove a vestige from this ally
func remove_vestige(vestige_id: String) -> void:
	for i in range(vestiges.size() - 1, -1, -1):
		var vestige = vestiges[i]
		if vestige and vestige.vestige_id == vestige_id:
			vestiges.remove_at(i)
			vestige_stacks.erase(vestige_id)
			return


## Check if this ally owns a specific vestige
func has_vestige(vestige_id: String) -> bool:
	for vestige in vestiges:
		if vestige and vestige.vestige_id == vestige_id:
			return true
	return false


## Get stack count for a specific vestige
func get_vestige_stack_count(vestige_id: String) -> int:
	if vestige_id in vestige_stacks:
		return vestige_stacks[vestige_id]
	return 0


## Get all vestiges of a specific scope
func get_vestiges_by_scope(scope: Vestige.Scope) -> Array[Vestige]:
	var matching: Array[Vestige] = []
	for vestige in vestiges:
		if vestige and vestige.scope == scope:
			matching.append(vestige)
	return matching


## HP as a 0..1 ratio, for progress bars.
func get_hp_ratio() -> float:
	return clampf(float(get_current_health()) / float(get_max_health()), 0.0, 1.0)


## Human readable HP for labels ("72/100"; a fresh ally shows full HP).
func get_hp_text() -> String:
	return "%d/%d" % [get_current_health(), get_max_health()]


## Restores [param amount] HP, returning the amount actually healed.
## A downed ally (0 HP) is revived by healing, same as in battle.
func heal(amount : int) -> int:
	if amount <= 0:
		return 0
	if max_health <= 0:
		# Never fought: it already counts as full.
		current_health = -1
		return 0
	var from := maxi(current_health, 0)
	var to := mini(from + amount, max_health)
	current_health = to
	return to - from


## Fully heals the ally (also revives a downed one). Returns the HP restored.
func heal_to_full() -> int:
	if max_health <= 0:
		current_health = -1
		return 0
	return heal(max_health)


## Returns the deck to fight with, loading [member deck_path] on first use.
func get_deck() -> DeckResource:
	if deck == null and not deck_path.is_empty() and ResourceLoader.exists(deck_path):
		deck = load(deck_path) as DeckResource
	return deck


## A private copy of this ally's deck so changes stay local to this ally.
## (Resource.duplicate() may keep the same card array, so a fresh list is built.)
func duplicate_deck() -> DeckResource:
	var source := get_deck()
	if source == null:
		return null
	var copy := source.duplicate() as DeckResource
	if copy == null:
		return null
	var cards : Array[CardConfig] = []
	for card in source.cards:
		cards.append(card)
	copy.cards = cards
	return copy


## Portrait texture for out-of-battle UIs. Uses [member BattlerStats.thumbnail]
## (the same portrait battles show), falling back to [member portrait_path];
## null when neither is set.
func get_portrait() -> Texture2D:
	if stats != null and stats.thumbnail != null:
		return stats.thumbnail
	if portrait_path.is_empty() or not ResourceLoader.exists(portrait_path):
		return null
	return load(portrait_path) as Texture2D


# ---------------------------------------------------------------------------
# Equipment (weapons)
# ---------------------------------------------------------------------------

## True when [param w] is a weapon this ally's type allows.
func can_equip_weapon(w : Weapon) -> bool:
	return w != null and w.equip_kind() == weapon_type


## Equips [param w]. The weapon must already be in [member inventory] and match
## [member weapon_type]; returns false (with a warning) otherwise. The item is
## NOT consumed — unequipping just clears the reference.
func equip_weapon(w : Weapon) -> bool:
	if not can_equip_weapon(w):
		push_warning("AllyPartyMember '%s': cannot equip '%s' (type mismatch or null)." % [id, w.item_name if w else "null"])
		return false
	if inventory != null and not inventory.collection.has(w):
		push_warning("AllyPartyMember '%s': weapon '%s' is not in inventory." % [id, w.item_name])
		return false
	equipped_weapon = w
	return true


func unequip_weapon() -> void:
	equipped_weapon = null


## Standalone copy of this entry for a newly recruited ally of the same type.
func duplicate_as_new_ally(new_id : String) -> AllyPartyMember:
	var member := duplicate() as AllyPartyMember
	if member == null:
		return null
	member.id = new_id
	member.deck = duplicate_deck()
	member.exp_total = 0
	member.current_health = -1
	return member
