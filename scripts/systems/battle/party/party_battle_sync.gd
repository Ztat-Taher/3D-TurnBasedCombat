class_name PartyBattleSync
extends RefCounted
## Keeps the run party (GameState.party) and the live battle scene in sync.
##
## Battle scenes ship with a single hard-instanced ally. This helper
## - spawns/removes allies so the battlefield matches the party size,
## - gives every ally its own copy of the scene's shared [BattlerStats],
## - applies the HP the party carried into the node,
## - writes HP/level/exp/deck back into the roster when the battle ends.
##
## [BattleLevel] calls it from _enter_tree() (before the battle's _ready()),
## _ready() (once the battlers exist) and on battle_ended.

## Offset applied per extra ally, relative to the scene's sample ally. Only the
## X component is used, so every party member lines up on the same row as the
## scene's first ally (identical height and depth, side by side).
const SPAWN_OFFSET : Vector3 = Vector3(-4, 0.0, 0.0)
## A downed ally still takes the field with at least this much HP so the run can
## continue (and the ally can be healed by a rest site or a card).
const MIN_BATTLE_HP : int = 1


## Makes the battle scene's allies match the run party, then configures them.
## Must run before the battle manager's _ready() gathers the players.
static func prepare_party(level_root : Node) -> void:
	GameState.ensure_starter_party()
	var roster := GameState.get_party()
	if roster.is_empty():
		return
	var allies := get_ally_battlers(level_root)
	if allies.is_empty():
		push_warning("PartyBattleSync: no ally battlers found in the battle scene.")
		return

	# Drop the allies the roster no longer owns.
	while allies.size() > roster.size():
		var surplus : Battler = allies.pop_back()
		if not is_instance_valid(surplus):
			continue
		var parent := surplus.get_parent()
		if parent:
			parent.remove_child(surplus)
		surplus.queue_free()

	# Spawn the allies the scene does not provide yet.
	while allies.size() < roster.size():
		var member := roster[allies.size()]
		var spawned := spawn_ally_like(allies[0], member, allies.size())
		if spawned == null:
			break
		allies.append(spawned)

	for i in range(mini(allies.size(), roster.size())):
		configure_ally(allies[i], roster[i])


## Applies the HP, XP, and level the party carried into this node (and refreshes AP).
## Call once the battlers exist (i.e. after the battle's _ready()).
static func apply_saved_health(level_root : Node = null) -> void:
	var roster := GameState.get_party()
	if roster.is_empty():
		return
	var allies := get_ally_battlers(level_root)
	for i in range(mini(allies.size(), roster.size())):
		var battler := allies[i]
		var member := roster[i]
		if not is_instance_valid(battler) or member == null:
			continue
		
		# Restore HP
		var target := battler.max_health
		if member.current_health >= 0:
			target = clampi(member.current_health, MIN_BATTLE_HP, battler.max_health)
		battler.current_health = target
		
		# Restore XP and level from party member
		battler.current_level = member.level
		battler.current_exp = member.exp_total
		battler.calculate_exp_for_next_level()
		battler.apply_level_progression()
		
		battler.reset_ap()


## Writes the live battlers' HP/level/exp/deck back into the run party.
static func store_party_state(level_root : Node = null) -> void:
	var allies := get_ally_battlers(level_root)
	if allies.is_empty():
		return
	GameState.sync_from_battlers(allies)


## Every ally battler in the scene. Uses the "players" group once the battle is
## ready; falls back to scanning the subtree (used before _ready() runs).
static func get_ally_battlers(root : Node = null) -> Array[Battler]:
	var allies : Array[Battler] = []
	var scene_root := _resolve_root(root)
	if scene_root == null:
		return allies
	if scene_root.is_inside_tree():
		for node in scene_root.get_tree().get_nodes_in_group("players"):
			if node is Battler and not allies.has(node):
				allies.append(node)
	if allies.is_empty():
		_collect_ally_battlers(scene_root, allies)
	return allies


## The ally linked to a party member id, if it is on the field.
static func find_battler_for_member(member_id : String) -> Battler:
	if member_id.is_empty():
		return null
	for battler in get_ally_battlers():
		if str(battler.get_meta(AllyPartyMember.META_PARTY_MEMBER_ID, "")) == member_id:
			return battler
	return null


static func _resolve_root(root : Node) -> Node:
	if root != null:
		return root
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		return (main_loop as SceneTree).current_scene
	return null


static func _collect_ally_battlers(node : Node, out : Array[Battler]) -> void:
	for child in node.get_children():
		if child is Battler and (child as Battler).team == Battler.TEAM.ALLY:
			if not out.has(child):
				out.append(child)
		_collect_ally_battlers(child, out)


## Spawns an extra ally next to [param sample], using [param member]'s scene.
static func spawn_ally_like(sample : Battler, member : AllyPartyMember, index : int) -> Battler:
	if not is_instance_valid(sample) or member == null:
		return null
	var parent := sample.get_parent()
	if parent == null:
		return null
	var scene_path := member.ally_scene_path
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scene_path = sample.scene_file_path
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("PartyBattleSync: no ally scene available to spawn extra party members.")
		return null
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	var ally := packed.instantiate() as Battler
	if ally == null:
		return null
	ally.name = "Ally_%s" % member.id
	var spawn_transform := sample.transform
	# Shift only along X so the spawned ally keeps the sample's rotation and
	# shares its exact Y (height) and Z (depth): a straight row of allies.
	spawn_transform.origin.x += SPAWN_OFFSET.x * float(index)
	ally.transform = spawn_transform
	parent.add_child(ally)
	# The ally's own _ready() adds this group too; adding it here keeps the
	# battle's group-based setup working even if the ally is readied later.
	ally.add_to_group("players")
	return ally


## Copies the party member's data onto an ally battler before its _ready().
static func configure_ally(battler : Battler, member : AllyPartyMember) -> void:
	if not is_instance_valid(battler) or member == null:
		return
	battler.set_meta(AllyPartyMember.META_PARTY_MEMBER_ID, member.id)
	# The battle scene ships one shared BattlerStats sub-resource: give each ally
	# its own copy so name/level/deck never bleed between party members.
	if battler.stats:
		battler.stats = battler.stats.duplicate() as BattlerStats
		battler.stats.character_name = member.display_name
		battler.stats.level = maxi(member.level, 1)
		battler.stats.deck = member.get_deck()
	# Carry experience across nodes.
	var experience := battler.get_node_or_null("Experience") as Experience
	if experience:
		experience.exp_total = member.exp_total
