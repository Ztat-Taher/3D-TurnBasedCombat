class_name AllyDisplayModel
extends RefCounted
## Builds and drives out-of-battle copies of an ally's battle model (party
## screen preview, recruit room, ...).
##
## The ally scene is the real battle scene, so [method build] removes the
## [Battler] script before the model enters the tree: it would otherwise join
## the "players" group and connect to SignalBus targeting, which a live battle
## (e.g. behind the pause menu) would pick up. Only the skeleton/mesh hierarchy
## and the animation nodes are kept.
##
## Resting: every ally AnimationTree has [constant REST_STATE] and
## [constant STAND_UP_STATE] in [constant STATE_MACHINE]. Their clips are
## assigned per ally in the tree resource; while a clip is unassigned the ally
## simply stays in its idle.

const STATE_MACHINE : StringName = &"BaseSM"
const REST_STATE : StringName = &"rest"
const STAND_UP_STATE : StringName = &"rest_stand_up"
const IDLE_STATE : StringName = &"idle1"
## Cross-fade used by the rest -> idle shortcut when no stand-up clip is set
## (matches the "rest_to_idle" transition in the trees).
const INSTANT_STAND_UP_TIME : float = 0.4
## Humanoid bones used to find where the feet touch the ground.
const FOOT_BONES : Array[StringName] = [&"LeftToes", &"RightToes", &"LeftFoot", &"RightFoot"]


## Instantiates [param member]'s battle model with battle logic removed and
## the equipped weapon attached. Returns null when the scene can't be loaded.
static func build(member : AllyPartyMember) -> Node3D:
	if member == null or member.ally_scene_path.is_empty() or not ResourceLoader.exists(member.ally_scene_path):
		return null
	var packed := load(member.ally_scene_path) as PackedScene
	var instance := packed.instantiate() if packed != null else null
	if not (instance is Node3D):
		if instance != null:
			instance.free()
		return null
	var model := instance as Node3D
	var socket_path : NodePath = model.get("weapon_socket_path") if "weapon_socket_path" in model else NodePath("")
	_strip_battle_logic(model)
	_attach_weapon(model, socket_path, member.equipped_weapon)
	return model


## Lowest foot/toe bone height (meters, in [param model]'s parent space) in
## the current pose, or NAN when the skeleton has no foot bones. Subtract it
## from the model's Y to stand it on the ground.
static func get_foot_height(model : Node3D) -> float:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return NAN
	var skeleton := skeletons[0] as Skeleton3D
	var lowest := INF
	for bone in FOOT_BONES:
		var index := skeleton.find_bone(bone)
		if index >= 0:
			var world := skeleton.global_transform * skeleton.get_bone_global_pose(index)
			lowest = minf(lowest, world.origin.y)
	if is_inf(lowest):
		return NAN
	var parent := model.get_parent() as Node3D
	return lowest - (parent.global_position.y if parent != null else 0.0)


## True when [param state] in the model's tree has a clip that actually exists.
static func has_state_clip(model : Node3D, state : StringName) -> bool:
	var tree := get_animation_tree(model)
	if tree == null:
		return false
	var root := tree.tree_root as AnimationNodeBlendTree
	if root == null or not root.has_node(STATE_MACHINE):
		return false
	var machine := root.get_node(STATE_MACHINE) as AnimationNodeStateMachine
	if machine == null or not machine.has_node(state):
		return false
	var node := machine.get_node(state) as AnimationNodeAnimation
	return node != null and node.animation != &"" and tree.has_animation(node.animation)


## Puts the model straight into its resting loop. Returns false (model stays
## idle) when this ally has no rest clip assigned yet.
static func start_resting(model : Node3D) -> bool:
	if not has_state_clip(model, REST_STATE):
		return false
	var playback := _get_playback(model)
	if playback == null:
		return false
	# A previous stand_up() leaves these set; clear them or the rest state's
	# Auto transitions would stand the model straight back up.
	var tree := get_animation_tree(model)
	var conditions := "parameters/%s/conditions/" % STATE_MACHINE
	tree.set(conditions + "is_standing_up", false)
	tree.set(conditions + "is_standing_up_instant", false)
	playback.start(REST_STATE)
	return true


## Gets a resting model back on its feet. Returns how long (seconds) until it
## is back in its idle; 0 when it wasn't resting.
static func stand_up(model : Node3D) -> float:
	var tree := get_animation_tree(model)
	var playback := _get_playback(model)
	if tree == null or playback == null or playback.get_current_node() != REST_STATE:
		return 0.0
	var conditions := "parameters/%s/conditions/" % STATE_MACHINE
	if has_state_clip(model, STAND_UP_STATE):
		tree.set(conditions + "is_standing_up", true)
		var clip := ((tree.tree_root as AnimationNodeBlendTree).get_node(STATE_MACHINE) as AnimationNodeStateMachine) \
			.get_node(STAND_UP_STATE) as AnimationNodeAnimation
		return tree.get_animation(clip.animation).length
	tree.set(conditions + "is_standing_up_instant", true)
	return INSTANT_STAND_UP_TIME


static func get_animation_tree(model : Node3D) -> AnimationTree:
	if model == null:
		return null
	var found := model.find_children("*", "AnimationTree", true, false)
	return found[0] as AnimationTree if not found.is_empty() else null


static func _get_playback(model : Node3D) -> AnimationNodeStateMachinePlayback:
	var tree := get_animation_tree(model)
	if tree == null:
		return null
	return tree.get("parameters/%s/playback" % STATE_MACHINE) as AnimationNodeStateMachinePlayback


## Removes everything that only makes sense inside a battle.
static func _strip_battle_logic(root : Node3D) -> void:
	root.set_script(null)
	for group in root.get_groups():
		root.remove_from_group(group)
	root.transform = Transform3D.IDENTITY
	for child in root.get_children():
		if child is AnimationMixer or child is Skeleton3D:
			continue
		if not child.find_children("*", "Skeleton3D", true, false).is_empty():
			continue
		root.remove_child(child)
		child.free()


## Same placement rule as WeaponSystem: a "Weapon" child of the socket,
## copying the authored "WeaponSocket" marker transform when present.
static func _attach_weapon(model : Node3D, socket_path : NodePath, weapon : Weapon) -> void:
	if weapon == null or weapon.model_scene == null or socket_path.is_empty():
		return
	var socket := model.get_node_or_null(socket_path)
	if socket == null:
		return
	WeaponSystem.attach_model_to_socket(socket, weapon.model_scene)

