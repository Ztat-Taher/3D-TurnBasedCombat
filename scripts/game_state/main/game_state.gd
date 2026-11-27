class_name GameState
extends Resource

const STATE_NAME : String = "GameState"
const FILE_PATH = "res://scripts/game_state/main/game_state.gd"

@export var level_states : Dictionary = {}
@export var current_level_path : String
@export var checkpoint_level_path : String
@export var total_games_played : int
@export var play_time : int
@export var total_time : int

# Run-map progress (Slay the Spire style path selection).
@export var current_node_id : String = ""
@export var completed_nodes : Array[String] = []
@export var run_map_serialized : String = ""  # Serialized procedural map for persistence

## Path to the PartyData resource used to (re)build the starter party each run.
const PARTY_TEMPLATE_PATH : String = "res://database/party/player_party.tres"
## Path to the PartyData resource listing allies that can be recruited at
## recruit nodes. Kept separate from the starter template so recruited types
## don't join the party automatically at run start.
const RECRUITABLES_PATH : String = "res://database/party/recruitables.tres"

## Default weapon granted to each weapon type when a member has none equipped.
## Keyed by Weapon.WType value (BLADE=0, ORB=1, GUN=2). Acquisition UI is deferred —
## these starters make the equipment layer testable immediately.
const DEFAULT_WEAPON_PATHS : Dictionary = {
	Weapon.WType.BLADE: "res://database/weapons/items/soldiers_blade.tres",
	Weapon.WType.ORB: "res://database/weapons/items/prism_circuit.tres",
	Weapon.WType.GUN: "res://database/weapons/items/flintlock_pistol.tres",
}

## Extra weapons granted to a member's inventory (not auto-equipped) once
## their default weapon is in place. Keyed by Weapon.WType.
const BONUS_WEAPON_PATHS : Dictionary = {
	Weapon.WType.BLADE: ["res://database/weapons/items/elf_leaf_blade.tres"],
}

## The run party roster. Each entry carries an ally's stats, deck and runtime HP
## between map nodes and battles. Persisted via GlobalState alongside the rest
## of the run state.
@export var party : Array[AllyPartyMember] = []

## Global vestiges (party-wide passive items). Affects entire party.
@export var global_vestiges : Array[Vestige] = []
## Stack counts for global vestiges (vestige_id -> stack_count)
@export var global_vestige_stacks : Dictionary = {}

static func get_level_state(level_state_key : String) -> LevelState:

	if not has_game_state(): 
		return
	var game_state := get_or_create_state()
	if level_state_key.is_empty() : return
	if level_state_key in game_state.level_states:
		return game_state.level_states[level_state_key] 
	else:
		var new_level_state := LevelState.new()
		game_state.level_states[level_state_key] = new_level_state
		GlobalState.save()
		return new_level_state

static func has_game_state() -> bool:
	return GlobalState.has_state(STATE_NAME)

static func get_or_create_state() -> GameState:
	return GlobalState.get_or_create_state(STATE_NAME, FILE_PATH)

static func get_current_level_path() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.current_level_path

static func get_checkpoint_level_path() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.checkpoint_level_path

static func get_levels_reached() -> int:
	if not has_game_state(): 
		return 0
	var game_state := get_or_create_state()
	return game_state.level_states.size()

static func set_checkpoint_level_path(level_path : String) -> void:
	var game_state := get_or_create_state()
	game_state.checkpoint_level_path = level_path
	get_level_state(level_path)
	GlobalState.save()

static func set_current_level_path(level_path : String) -> void:
	var game_state := get_or_create_state()
	game_state.current_level_path = level_path
	GlobalState.save()

static func get_current_node_id() -> String:
	if not has_game_state(): 
		return ""
	var game_state := get_or_create_state()
	return game_state.current_node_id

static func set_current_node_id(node_id : String) -> void:
	var game_state := get_or_create_state()
	game_state.current_node_id = node_id
	GlobalState.save()

static func get_completed_nodes() -> Array:
	if not has_game_state(): 
		return []
	var game_state := get_or_create_state()
	return game_state.completed_nodes.duplicate()

static func is_node_completed(node_id : String) -> bool:
	if not has_game_state(): 
		return false
	var game_state := get_or_create_state()
	return node_id in game_state.completed_nodes

## Marks the node the player is standing on as completed. The current node id
## is intentionally KEPT (not cleared) so the run map can restore the pawn and
## node availability to that node when the scene is reloaded after a battle or
## a stop-node UI (rest/recruit).
static func complete_current_node() -> void:
	var game_state := get_or_create_state()
	if game_state.current_node_id.is_empty():
		return
	if not game_state.current_node_id in game_state.completed_nodes:
		game_state.completed_nodes.append(game_state.current_node_id)
	GlobalState.save()


# ---------------------------------------------------------------------------
# Party system (ally roster persisted between combat nodes)
# ---------------------------------------------------------------------------

## The run party roster (Array[AllyPartyMember]). Empty when no run is active.
static func get_party() -> Array[AllyPartyMember]:
	var game_state := get_or_create_state()
	return game_state.party


## Build a fresh party from the PartyData template when starting a run or when
## the roster is missing. Each member is deep-duplicated so runtime changes
## (HP, level, deck rewards) never mutate the template .tres.
static func ensure_starter_party() -> void:
	if not has_game_state():
		return
	var game_state := get_or_create_state()
	if not game_state.party.is_empty():
		return
	var template := load(PARTY_TEMPLATE_PATH) as PartyData
	if template == null or template.allies.is_empty():
		push_error("GameState: starter party template missing or empty: %s" % PARTY_TEMPLATE_PATH)
		return
	var next_id : int = 1
	for member in template.allies:
		var copy : AllyPartyMember = (member as AllyPartyMember).duplicate(true) as AllyPartyMember
		if copy == null:
			continue
		copy.id = "ally_%d" % next_id
		copy.deck = copy.duplicate_deck()
		# Deep-copy the battler stats so level/deck rewards don't bleed between
		# party members or back into the template.
		if copy.stats != null:
			copy.stats = copy.stats.duplicate(true) as BattlerStats
		copy.current_health = -1  # fresh ally: full HP.
		copy.exp_total = 0
		copy.level = 1
		_prepare_member_equipment(copy)
		next_id += 1
		game_state.party.append(copy)
	GlobalState.save()


## Ensures a party member has an inventory and a type-matched weapon equipped.
## Grants the default weapon for the member's weapon_type when none is owned.
static func _prepare_member_equipment(member : AllyPartyMember) -> void:
	if member.inventory == null:
		member.inventory = Inventory.new()
	if member.equipped_weapon != null and member.can_equip_weapon(member.equipped_weapon):
		return
	var path : String = DEFAULT_WEAPON_PATHS.get(member.weapon_type, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var template := load(path) as Weapon
	if template == null:
		return
	# Duplicate so each member owns an independent weapon instance (XP/level).
	var weapon := template.duplicate() as Weapon
	member.inventory.add_item_to_collection(weapon, 1)
	member.equip_weapon(weapon)
	# Grant bonus weapons for this weapon type into the inventory (un-equipped;
	# swapping happens through the party/equipment UI).
	for bonus_path in BONUS_WEAPON_PATHS.get(member.weapon_type, []):
		if not ResourceLoader.exists(bonus_path):
			continue
		var bonus := load(bonus_path) as Weapon
		if bonus == null:
			continue
		var owned := false
		for item in member.inventory.collection.keys():
			if item is Weapon and (item as Weapon).item_name == bonus.item_name:
				owned = true
				break
		if not owned:
			member.inventory.add_item_to_collection(bonus.duplicate() as Weapon, 1)


## Recruit a new ally cloned from [param source] (one of the recruit
## templates). Returns the new member or null on failure. The party must
## already exist. When [param source] is null the first starter template ally
## is used, preserving the original single-ally recruit behaviour.
static func recruit_ally(source : AllyPartyMember = null) -> AllyPartyMember:
	var game_state := get_or_create_state()
	if source == null:
		source = get_recruit_template()
	if source == null:
		push_error("GameState: cannot recruit, no recruit template available.")
		return null
	var new_id := "ally_%d" % (game_state.party.size() + 1)
	var member : AllyPartyMember = source.duplicate(true) as AllyPartyMember
	if member == null:
		return null
	member.id = new_id
	member.display_name = source.display_name
	member.ally_scene_path = source.ally_scene_path
	member.deck_path = source.deck_path
	member.portrait_path = source.portrait_path
	member.deck = member.duplicate_deck()
	if member.stats != null:
		member.stats = member.stats.duplicate(true) as BattlerStats
	member.current_health = -1
	member.exp_total = 0
	member.level = 1
	_prepare_member_equipment(member)
	game_state.party.append(member)
	GlobalState.save()
	return member


## All ally types offered at recruit nodes: the starter template's first ally
## (legacy behaviour) followed by every entry in the recruitables template.
static func get_recruit_templates() -> Array[AllyPartyMember]:
	var templates : Array[AllyPartyMember] = []
	"""var starter := get_recruit_template()
	if starter != null:
		templates.append(starter)"""
	var recruitables := load(RECRUITABLES_PATH) as PartyData
	if recruitables != null:
		for member in recruitables.allies:
			if member is AllyPartyMember:
				templates.append(member)
	return templates


## The ally "found" resting at the current recruit node: one recruit template
## whose type isn't in the party yet (types are matched by battle scene, which
## recruiting copies over). The pick is seeded by the run map and node id, so
## re-entering the same node shows the same ally. Null when everyone has
## already been recruited.
static func get_found_recruit() -> AllyPartyMember:
	var game_state := get_or_create_state()
	if game_state.party.is_empty():
		ensure_starter_party()
	var owned := {}
	for member in game_state.party:
		if member != null:
			owned[member.ally_scene_path] = true
	var candidates : Array[AllyPartyMember] = []
	for template in get_recruit_templates():
		if not owned.has(template.ally_scene_path):
			candidates.append(template)
	if candidates.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s" % [game_state.run_map_serialized.hash(), game_state.current_node_id])
	return candidates[rng.randi_range(0, candidates.size() - 1)]


## Returns the template ally used for recruiting (first entry of the PartyData
## template), or null if no template is available. The recruit screen previews
## this ally before joining the roster.
static func get_recruit_template() -> AllyPartyMember:
	var template := load(PARTY_TEMPLATE_PATH) as PartyData
	if template == null or template.allies.is_empty():
		return null
	return template.allies[0] as AllyPartyMember


## Get or save the procedural map to prevent regeneration mid-run
static func get_or_create_procedural_map(plane_size: int = 30, node_count: int = 90, path_count: int = 15, min_node_distance: float = 3.0, connection_distance: float = -1.0) -> RunMap:
	var game_state := get_or_create_state()
	
	# If we have a serialized map, try to restore it
	if not game_state.run_map_serialized.is_empty():
		var restored := RunMap.from_dict(JSON.parse_string(game_state.run_map_serialized))
		if restored != null:
			return restored
		# Unreadable save (older builds stored nodes as "<Resource#...>" text):
		# its progress points at a map that no longer exists, so start the map over
		push_warning("GameState: saved run map was unreadable; generating a new map.")
		game_state.completed_nodes.clear()
		game_state.current_node_id = ""
	
	# Generate new map and serialize it (nodes as plain data, see RunMap.to_dict)
	var new_map = RunMap.create_procedural(plane_size, node_count, path_count, min_node_distance, connection_distance)
	game_state.run_map_serialized = JSON.stringify(new_map.to_dict())
	GlobalState.save()
	return new_map

static func clear_procedural_map() -> void:
	var game_state := get_or_create_state()
	game_state.run_map_serialized = ""
	GlobalState.save()

## Find a party member by its unique ally id.
static func get_party_member(member_id : String) -> AllyPartyMember:
	var game_state := get_or_create_state()
	for member in game_state.party:
		if member and member.id == member_id:
			return member as AllyPartyMember
	return null


## Copy live battler state (HP/level/exp/deck) back onto the run party. Called by
## PartyBattleSync.store_party_state() when a battle ends.
static func sync_from_battlers(battlers : Array = []) -> void:
	var game_state := get_or_create_state()
	if game_state.party.is_empty() or battlers.is_empty():
		return
	for battler in battlers:
		if battler == null or not is_instance_valid(battler):
			continue
		if not (battler is Battler):
			continue
		var b := battler as Battler
		var member_id : String = str(b.get_meta(AllyPartyMember.META_PARTY_MEMBER_ID, ""))
		if member_id.is_empty():
			continue
		var member := get_party_member(member_id)
		if member == null:
			continue
		# Write the live battler's HP/level/exp/deck back onto the run party so
		# damage and progression persist across map nodes.
		member.max_health = b.max_health
		member.current_health = maxi(b.current_health, 0)
		member.level = b.current_level
		member.exp_total = b.current_exp
		if b.stats != null and b.stats.deck != null:
			member.deck = b.stats.deck
		# Equipment: inventory/weapon are shared refs so XP and the equipped slot
		# persist automatically; only cover cases where the battler carried a
		# different inventory than the member template.
		if b.inventory != null:
			member.inventory = b.inventory
		if b.weapon != null:
			member.equipped_weapon = b.weapon
	GlobalState.save()


static func start_game() -> void:
	var game_state := get_or_create_state()
	game_state.total_games_played += 1
	# Rebuild a fresh party for the new run (cloned from the PartyData template).
	ensure_starter_party()
	GlobalState.save()


static func continue_game() -> void:
	# Make sure the party roster exists on a continued game too.
	ensure_starter_party()
	var game_state := get_or_create_state()
	game_state.current_level_path = game_state.checkpoint_level_path
	GlobalState.save()


static func reset() -> void:
	var game_state := get_or_create_state()
	game_state.level_states = {}
	game_state.current_level_path = ""
	game_state.checkpoint_level_path = ""
	game_state.play_time = 0
	game_state.total_time = 0
	game_state.current_node_id = ""
	game_state.completed_nodes = []
	game_state.party = []
	game_state.run_map_serialized = ""  # Clear cached map
	game_state.global_vestiges = []
	game_state.global_vestige_stacks = {}
	GlobalState.save()


# ---------------------------------------------------------------------------
# Global Vestiges system (party-wide passive items)
# ---------------------------------------------------------------------------

## Get all global vestiges
static func get_global_vestiges() -> Array[Vestige]:
	var game_state := get_or_create_state()
	return game_state.global_vestiges


## Get stack count for a specific global vestige
static func get_global_vestige_stack_count(vestige_id: String) -> int:
	var game_state := get_or_create_state()
	if vestige_id in game_state.global_vestige_stacks:
		return game_state.global_vestige_stacks[vestige_id]
	return 0


## Check if a global vestige is owned
static func has_global_vestige(vestige_id: String) -> bool:
	var game_state := get_or_create_state()
	for vestige in game_state.global_vestiges:
		if vestige and vestige.vestige_id == vestige_id:
			return true
	return false


## Gives the party [param stacks] more of a party-wide [param vestige], up to
## its [member Vestige.max_stacks]. Returns false (and changes nothing) for a
## per-character vestige or when no more stacks fit.
static func add_global_vestige(vestige: Vestige, stacks: int = 1) -> bool:
	if vestige == null or vestige.scope != Vestige.Scope.GLOBAL \
			or not vestige.can_gain_stack(get_global_vestige_stack_count(vestige.vestige_id)):
		return false
	var game_state := get_or_create_state()
	var current := get_global_vestige_stack_count(vestige.vestige_id)
	if current == 0:
		game_state.global_vestiges.append(vestige)
	var total := current + stacks
	game_state.global_vestige_stacks[vestige.vestige_id] = total if vestige.max_stacks <= 0 else mini(total, vestige.max_stacks)
	GlobalState.save()
	return true


## True if the run can still gain [param vestige]: a party-wide one while the
## party can stack it; a per-character one while [param member] (or, if null,
## any ally) can.
static func can_gain_vestige(vestige: Vestige, member: AllyPartyMember = null) -> bool:
	if vestige == null:
		return false
	if vestige.scope == Vestige.Scope.GLOBAL:
		return vestige.can_gain_stack(get_global_vestige_stack_count(vestige.vestige_id))
	if member:
		return member.can_gain_vestige(vestige)
	return get_party().any(func(m): return m.can_gain_vestige(vestige))


## Awards [param vestige] where its scope says: party-wide ones to the party,
## per-character ones to [param member] (or the first ally that can take it).
## The single entry point for rewards; returns false if nothing was gained.
static func grant_vestige(vestige: Vestige, member: AllyPartyMember = null) -> bool:
	if vestige == null:
		return false
	if vestige.scope == Vestige.Scope.GLOBAL:
		return add_global_vestige(vestige)
	if member == null:
		for candidate in get_party():
			if candidate.can_gain_vestige(vestige):
				member = candidate
				break
	if member == null or not member.add_vestige(vestige):
		return false
	GlobalState.save()
	return true


## Remove a global vestige
static func remove_global_vestige(vestige_id: String) -> void:
	var game_state := get_or_create_state()
	for i in range(game_state.global_vestiges.size() - 1, -1, -1):
		var vestige = game_state.global_vestiges[i]
		if vestige and vestige.vestige_id == vestige_id:
			game_state.global_vestiges.remove_at(i)
			game_state.global_vestige_stacks.erase(vestige_id)
			GlobalState.save()
			return
