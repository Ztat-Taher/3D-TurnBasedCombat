## [color=green]AI Manager[/color]
## [br][br]
## This class manages AI action selection based on Skills available to the battler,
## the battler's Intelligence, and AI Type.
## [br][br]
## Logic to handle decision-making for NPCs in combat should be put in here.
extends Node


# Pulled from Enemy (deprecated/removed class)
func choose_action(character:Battler, available_targets: Array, _all_enemies: Array, battle_manager:BattleManager) -> void:
	# Choose action based on AI type
	match character.ai_type:
		Battler.AIType.AGGRESSIVE:
			await aggressive_action(character, available_targets, battle_manager)
		Battler.AIType.DEFENSIVE:
			await defensive_action(character, available_targets, battle_manager)
		_:
			await aggressive_action(character, available_targets, battle_manager)

func aggressive_action(character:Battler, players: Array, battle_manager:BattleManager) -> void:
	var all_enemies = battle_manager.enemies if battle_manager else []
	var target = choose_target(character, players)
	if target:
		battle_manager.current_target = target
		battle_manager.current_character = character
		battle_manager.battler_attacking = true
		
		# ====================================================================
		# CINEMATIC ENEMY MOVE ANNOUNCEMENT SYSTEM
		# ====================================================================
		
		# STEP 1: Enemy Overview Camera
		if battle_manager.battle_camera and not all_enemies.is_empty():
			battle_manager.battle_camera.set_enemy_overview(all_enemies)
			await battle_manager.get_tree().create_timer(0.45).timeout
		
		# STEP 2: Move to Target Focus Camera on acting enemy & Announce Move
		var move_name = "Strike"
		if character.stats and character.stats.character_name:
			move_name = "%s's Attack" % character.stats.character_name
		
		if battle_manager.battle_camera:
			battle_manager.battle_camera.set_target_focus(character)
		
		if battle_manager.hud and battle_manager.hud.has_method("show_move_announcement"):
			battle_manager.hud.show_move_announcement(character.character_name, move_name, "attack")
		
		# Dramatic pause for announcement display
		await battle_manager.get_tree().create_timer(0.85).timeout
		
		# STEP 3: Transition to Over-the-Shoulder Camera of attacked player ally
		if battle_manager.hud and battle_manager.hud.has_method("hide_move_announcement"):
			battle_manager.hud.hide_move_announcement()
		
		if battle_manager.battle_camera and target in players:
			battle_manager.battle_camera.set_over_the_shoulder(target)
			await battle_manager.get_tree().create_timer(0.35).timeout
		
		# STEP 4: Execution
		# attack_anim handles movement, turns, contact-frame damage at hit_moment, and return-to-origin
		await character.attack_anim(target)


func defensive_action(character:Battler, players: Array, battle_manager:BattleManager) -> void:
	var all_enemies = battle_manager.enemies if battle_manager else []
	var health_percent = float(character.current_health) / character.max_health
	
	# Check if AI should use healing items (and has them)
	if health_percent < 0.4 and character.inventory and !character.inventory.collection.is_empty():
		var healing_item = find_best_healing_item(character.inventory)
		if healing_item:
			battle_manager.current_target = character
			battle_manager.current_character = character
			battle_manager.battler_attacking = true
			
			# STEP 1: Enemy Overview Camera
			if battle_manager.battle_camera and not all_enemies.is_empty():
				battle_manager.battle_camera.set_enemy_overview(all_enemies)
				await battle_manager.get_tree().create_timer(0.45).timeout
			
			# STEP 2: Target Focus Camera on acting enemy & Announce Item / Buff
			if battle_manager.battle_camera:
				battle_manager.battle_camera.set_target_focus(character)
			
			if battle_manager.hud and battle_manager.hud.has_method("show_move_announcement"):
				battle_manager.hud.show_move_announcement(character.character_name, healing_item.item_name, "heal")
			
			await battle_manager.get_tree().create_timer(0.9).timeout
			
			if battle_manager.hud and battle_manager.hud.has_method("hide_move_announcement"):
				battle_manager.hud.hide_move_announcement()
			
			character.battle_item(healing_item, character)
			return
	
	# Default to attacking
	await aggressive_action(character, players, battle_manager)

func choose_target(character:Battler, targets: Array) -> Node:
	# Filter out defeated targets
	var valid_targets = []
	for target:Battler in targets:
		if target != character and !target.is_defeated():
			valid_targets.append(target)
	
	if valid_targets.is_empty():
		return null
	
	# Use intelligence to determine targeting strategy
	var intelligence = character.intelligence
	var rand_value = randi() % 100
	
	if rand_value < intelligence:
		# Smart targeting - choose based on strategy
		var chosen = get_weakest_target(valid_targets)
		return chosen
	else:
		# Random targeting - choose any valid target
		var chosen = valid_targets[randi() % valid_targets.size()]
		return chosen

func get_weakest_target(targets: Array) -> Node:
	var weakest = null
	for target:Battler in targets:
		if target != self and (weakest == null or target.current_health < weakest.current_health):
			weakest = target
	return weakest

## Find the best healing item in inventory (prefers highest HP restore)
func find_best_healing_item(inventory: Inventory) -> Item:
	if not inventory or inventory.collection.is_empty():
		return null
	
	var best_item: Item = null
	var best_healing: int = 0
	
	for item in inventory.collection.keys():
		if item and item.is_battle_item and item.effect_type == "Heal":
			if item.hp_delta > best_healing:
				best_healing = item.hp_delta
				best_item = item
	
	return best_item
