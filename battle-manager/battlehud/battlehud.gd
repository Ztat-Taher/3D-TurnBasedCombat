class_name BattleHud
extends CanvasLayer

signal action_selected(action: String, item: Item)
signal menu_opened
signal card_selected(card: CardData)
signal end_turn_pressed

@onready var item_button_scene: PackedScene = preload("res://battle-manager/battlehud/item-button-preset.tscn")
@onready var item_container = $Control/Items/ScrollContainer/BoxContainer

@onready var action_buttons: BoxContainer = $Control/ActionButtons
@onready var enemy_stats: BoxContainer = $Control/Enemies/AllEnemies/EnemyStats
@onready var battle_text_display: RichTextLabel = $Control/BattleTextDisplay/Text
@onready var item_select: Control = $Control/Items
@onready var card_ui: Control = $Control/CardUI
@onready var party_status_panel: HBoxContainer = $Control/PartyStatusPanel
@onready var target_back_button: Button = $Control/TargetBackButton
@onready var boss_bar = $Control/BossBar
@onready var enemy_overhead_bars_container: Control = $Control/EnemyOverheadBarsContainer

const ENEMY_OVERHEAD_BAR_SCENE: PackedScene = preload("res://battle-manager/battlehud/EnemyOverheadBar.tscn")

# Maps enemy battler -> overhead bar node
var enemy_overhead_bar_map: Dictionary = {}

var activeBattler: Node = null
var enemy: Node = null

var active_allies: Array = []
var active_enemies: Array = []

# Tracks last known AP for each ally: { Battler -> { "current": int, "max": int } }
var last_ap_by_battler: Dictionary = {}
var ally_cards_map: Dictionary = {} # Battler -> PanelContainer

var _action_buttons_tween: Tween
var _target_screen_pos: Vector2 = Vector2.ZERO

func _ready():
	print("Inside BattleHUD _ready()")
	
	# Connect CardUI signals if it exists
	if card_ui:
		if card_ui.has_signal("card_selected"):
			card_ui.card_selected.connect(func(card): card_selected.emit(card))
		if card_ui.has_signal("end_turn_pressed"):
			card_ui.end_turn_pressed.connect(func(): end_turn_pressed.emit())
	
	item_select.visible = false
	hide_action_buttons()
	
	# Listen for card battle manager AP changes
	call_deferred("_connect_card_battle_manager")

func _connect_card_battle_manager() -> void:
	var cbm = get_tree().get_first_node_in_group("card_battle_manager")
	if cbm and cbm.has_signal("ap_changed"):
		if not cbm.ap_changed.is_connected(_on_cbm_ap_changed):
			cbm.ap_changed.connect(_on_cbm_ap_changed)

func _on_cbm_ap_changed(current_ap: int, max_ap: int) -> void:
	if activeBattler and is_instance_valid(activeBattler):
		last_ap_by_battler[activeBattler] = { "current": current_ap, "max": max_ap }
	update_party_status()

func _process(_delta: float) -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and (battle_manager.is_animating or battle_manager.in_target_selection):
		if action_buttons and action_buttons.visible:
			hide_action_buttons()
		return
	
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager and card_battle_manager.is_executing_card:
		if action_buttons and action_buttons.visible:
			hide_action_buttons()
		return
	
	if action_buttons and action_buttons.visible and activeBattler and is_instance_valid(activeBattler):
		var cam = get_viewport().get_camera_3d()
		if cam:
			# Project 3D position (chest/head height) to 2D screen coordinate
			var world_pos = activeBattler.global_position + Vector3(0, 1.2, 0)
			# Only position if in front of camera
			if not cam.is_position_behind(world_pos):
				var screen_pos = cam.unproject_position(world_pos)
				# Position action buttons to the RIGHT of the character
				var target_pos = screen_pos + Vector2(70.0, -50.0)
				# Clamp to screen margins
				var vp_size = get_viewport().get_visible_rect().size
				target_pos.x = clamp(target_pos.x, 20.0, vp_size.x - action_buttons.size.x - 20.0)
				target_pos.y = clamp(target_pos.y, 20.0, vp_size.y - action_buttons.size.y - 120.0)
				
				# Smooth follow or direct snap
				action_buttons.position = action_buttons.position.lerp(target_pos, 0.25)

func on_start_combat(enemy_node: Node):
	enemy = enemy_node
	if not active_enemies.has(enemy_node):
		active_enemies.append(enemy_node)
	_spawn_enemy_overhead_bar(enemy_node)
	_check_boss_bar(enemy_node)
	update_health_bars()

func on_add_character(character: Node):
	if character.is_in_group("players"):
		if not active_allies.has(character):
			active_allies.append(character)
			if not last_ap_by_battler.has(character):
				last_ap_by_battler[character] = { "current": 3, "max": 3 }
		_rebuild_party_status_panel()
	else:
		if not active_enemies.has(character):
			active_enemies.append(character)
		_spawn_enemy_overhead_bar(character)
		_check_boss_bar(character)

func _rebuild_party_status_panel() -> void:
	if not party_status_panel:
		return
	
	for child in party_status_panel.get_children():
		child.queue_free()
	ally_cards_map.clear()
	
	for ally in active_allies:
		if not is_instance_valid(ally):
			continue
		var card = _create_ally_status_card(ally)
		party_status_panel.add_child(card)
		ally_cards_map[ally] = card
	
	update_party_status()

func _create_ally_status_card(ally: Battler) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 95)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.16, 0.88)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.45, 0.7, 0.6)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	
	# Name & Active Indicator
	var header_hbox = HBoxContainer.new()
	vbox.add_child(header_hbox)
	
	var name_lbl = Label.new()
	name_lbl.name = "NameLabel"
	name_lbl.text = ally.character_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header_hbox.add_child(name_lbl)
	
	var active_tag = Label.new()
	active_tag.name = "ActiveTag"
	active_tag.text = "●"
	active_tag.add_theme_font_size_override("font_size", 10)
	active_tag.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	active_tag.visible = (ally == activeBattler)
	header_hbox.add_child(active_tag)
	
	# HP Section (Label + Bar)
	var hp_hbox = HBoxContainer.new()
	vbox.add_child(hp_hbox)
	
	var hp_tag = Label.new()
	hp_tag.text = "HP"
	hp_tag.custom_minimum_size = Vector2(24, 0)
	hp_tag.add_theme_font_size_override("font_size", 10)
	hp_tag.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	hp_hbox.add_child(hp_tag)
	
	var hp_bar = ProgressBar.new()
	hp_bar.name = "HPBar"
	hp_bar.custom_minimum_size = Vector2(0, 10)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	
	var hp_fill = StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.85, 0.22, 0.22, 0.95)
	hp_fill.corner_radius_top_left = 3
	hp_fill.corner_radius_top_right = 3
	hp_fill.corner_radius_bottom_right = 3
	hp_fill.corner_radius_bottom_left = 3
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	
	var hp_bg = StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.18, 0.08, 0.08, 0.8)
	hp_bg.corner_radius_top_left = 3
	hp_bg.corner_radius_top_right = 3
	hp_bg.corner_radius_bottom_right = 3
	hp_bg.corner_radius_bottom_left = 3
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	hp_hbox.add_child(hp_bar)
	
	var hp_num = Label.new()
	hp_num.name = "HPNumLabel"
	hp_num.text = "%d/%d" % [ally.current_health, ally.max_health]
	hp_num.add_theme_font_size_override("font_size", 10)
	hp_num.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	hp_hbox.add_child(hp_num)
	
	# AP Section (Label + Bar)
	var ap_hbox = HBoxContainer.new()
	vbox.add_child(ap_hbox)
	
	var ap_tag = Label.new()
	ap_tag.text = "AP"
	ap_tag.custom_minimum_size = Vector2(24, 0)
	ap_tag.add_theme_font_size_override("font_size", 10)
	ap_tag.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
	ap_hbox.add_child(ap_tag)
	
	var ap_bar = ProgressBar.new()
	ap_bar.name = "APBar"
	ap_bar.custom_minimum_size = Vector2(0, 8)
	ap_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap_bar.show_percentage = false
	
	var ap_fill = StyleBoxFlat.new()
	ap_fill.bg_color = Color(0.2, 0.65, 1.0, 0.95)
	ap_fill.corner_radius_top_left = 3
	ap_fill.corner_radius_top_right = 3
	ap_fill.corner_radius_bottom_right = 3
	ap_fill.corner_radius_bottom_left = 3
	ap_bar.add_theme_stylebox_override("fill", ap_fill)
	
	var ap_bg = StyleBoxFlat.new()
	ap_bg.bg_color = Color(0.08, 0.12, 0.22, 0.8)
	ap_bg.corner_radius_top_left = 3
	ap_bg.corner_radius_top_right = 3
	ap_bg.corner_radius_bottom_right = 3
	ap_bg.corner_radius_bottom_left = 3
	ap_bar.add_theme_stylebox_override("background", ap_bg)
	ap_hbox.add_child(ap_bar)
	
	var ap_num = Label.new()
	ap_num.name = "APNumLabel"
	ap_num.text = "3/3"
	ap_num.add_theme_font_size_override("font_size", 10)
	ap_num.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	ap_hbox.add_child(ap_num)
	
	return card

func update_party_status() -> void:
	for ally in active_allies:
		if not is_instance_valid(ally) or not ally_cards_map.has(ally):
			continue
		
		var card = ally_cards_map[ally] as PanelContainer
		if not is_instance_valid(card):
			continue
		
		var is_active = (ally == activeBattler)
		
		# Card highlight style
		var style = card.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			if is_active:
				style.border_color = Color(0.3, 0.85, 1.0, 1.0)
				style.border_width_left = 3
				style.border_width_top = 3
				style.border_width_right = 3
				style.border_width_bottom = 3
				style.bg_color = Color(0.1, 0.18, 0.32, 0.95)
			else:
				style.border_color = Color(0.2, 0.35, 0.55, 0.5)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				style.bg_color = Color(0.06, 0.09, 0.16, 0.85)
		
		var active_tag = card.find_child("ActiveTag", true, false)
		if active_tag:
			active_tag.visible = is_active
		
		# Update HP
		var hp_bar = card.find_child("HPBar", true, false) as ProgressBar
		if hp_bar:
			hp_bar.max_value = ally.max_health
			hp_bar.value = ally.current_health
		var hp_num = card.find_child("HPNumLabel", true, false) as Label
		if hp_num:
			hp_num.text = "%d/%d" % [ally.current_health, ally.max_health]
		
		# Update AP (from last_ap_by_battler)
		var ap_data = last_ap_by_battler.get(ally, { "current": 3, "max": 3 })
		var cur_ap = ap_data.get("current", 3)
		var max_ap = ap_data.get("max", 3)
		
		var ap_bar = card.find_child("APBar", true, false) as ProgressBar
		if ap_bar:
			ap_bar.max_value = max_ap
			ap_bar.value = cur_ap
		var ap_num = card.find_child("APNumLabel", true, false) as Label
		if ap_num:
			ap_num.text = "%d/%d" % [cur_ap, max_ap]

func set_activebattler(character: Node):
	activeBattler = character
	update_party_status()

func update_health_bars():
	update_party_status()
	for i in range(active_enemies.size()):
		var target_enemy = active_enemies[i]
		var container = $Control/Enemies/AllEnemies.get_child(i)
		if container and container.has_method("update_character_info"):
			container.update_character_info(target_enemy)

## Spawn an overhead health bar for a given enemy (if not already spawned).
func _spawn_enemy_overhead_bar(enemy_node: Node) -> void:
	if not is_instance_valid(enemy_node):
		return
	if enemy_overhead_bar_map.has(enemy_node):
		return
	if not enemy_overhead_bars_container:
		return
	var bar = ENEMY_OVERHEAD_BAR_SCENE.instantiate()
	enemy_overhead_bars_container.add_child(bar)
	bar.setup(enemy_node as Battler)
	enemy_overhead_bar_map[enemy_node] = bar

## Check if enemy_node is a boss and show the boss bar if so.
func _check_boss_bar(enemy_node: Node) -> void:
	if not boss_bar or not is_instance_valid(enemy_node):
		return
	var is_boss_enemy := false
	if "is_boss" in enemy_node:
		is_boss_enemy = enemy_node.is_boss
	elif enemy_node.stats and "is_boss" in enemy_node.stats:
		is_boss_enemy = enemy_node.stats.is_boss
	if is_boss_enemy:
		boss_bar.show_boss(enemy_node as Battler)

func show_action_buttons(character: Node):
	if not character or not character.is_in_group("players"):
		hide_action_buttons()
		return
	
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and (battle_manager.is_animating or battle_manager.in_target_selection):
		hide_action_buttons()
		return
	
	var card_battle_manager = get_tree().get_first_node_in_group("card_battle_manager")
	if card_battle_manager and card_battle_manager.is_executing_card:
		hide_action_buttons()
		return
	
	activeBattler = character
	update_party_status()
	
	# Initial positioning near the battler
	if activeBattler and is_instance_valid(activeBattler):
		var cam = get_viewport().get_camera_3d()
		if cam:
			var world_pos = activeBattler.global_position + Vector3(0, 1.2, 0)
			if not cam.is_position_behind(world_pos):
				var screen_pos = cam.unproject_position(world_pos)
				var target_pos = screen_pos + Vector2(70.0, -50.0)
				# Start offset further to the right for slide-in
				action_buttons.position = target_pos + Vector2(40.0, 0.0)
	
	action_buttons.show()
	action_buttons.modulate.a = 0.0
	
	var end_btn = action_buttons.get_node_or_null("EndTurnButton")
	if end_btn:
		end_btn.disabled = false
	
	# Slide in from right with fade animation
	if _action_buttons_tween and _action_buttons_tween.is_running():
		_action_buttons_tween.kill()
	
	_action_buttons_tween = create_tween()
	_action_buttons_tween.set_parallel(true)
	_action_buttons_tween.set_ease(Tween.EaseType.EASE_OUT)
	_action_buttons_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	_action_buttons_tween.tween_property(action_buttons, "modulate:a", 1.0, 0.25)

func hide_action_buttons():
	if _action_buttons_tween and _action_buttons_tween.is_running():
		_action_buttons_tween.kill()
	action_buttons.hide()

func update_character_info():
	if enemy and enemy_stats:
		enemy_stats.update_enemy_stats(enemy)
	update_party_status()

# Action button signals
func setup_item_list(battler: Battler) -> void:
	for child in item_container.get_children():
		child.queue_free()
	
	var has_items = false
	if battler and battler.inventory and !battler.inventory.collection.is_empty():
		for item: Item in battler.inventory.collection.keys():
			if !item.is_battle_item:
				continue
			has_items = true
			var button = item_button_scene.instantiate()
			item_container.add_child(button)
			button.setup(item, battler.inventory.collection.get(item))
			button.item_selected.connect(_on_item_selected)
	
	if not has_items:
		var empty_lbl = Label.new()
		empty_lbl.text = "No usable battle items"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_container.add_child(empty_lbl)
	
	menu_opened.emit()

func _on_item_back_pressed() -> void:
	item_select.visible = false
	if card_ui:
		card_ui.visible = true
	if activeBattler:
		show_action_buttons(activeBattler)

func _on_item_selected(item: Item) -> void:
	item_select.visible = false
	if card_ui:
		card_ui.visible = true
	action_selected.emit("item", item)

func _on_items_pressed() -> void:
	hide_action_buttons()
	setup_item_list(activeBattler)
	item_select.visible = true
	if card_ui:
		card_ui.visible = false

func _on_run_pressed() -> void:
	hide_action_buttons()
	action_selected.emit("run", null)

func _on_end_turn_button_pressed() -> void:
	var end_btn = action_buttons.get_node_or_null("EndTurnButton")
	if end_btn:
		end_btn.disabled = true
	end_turn_pressed.emit()

func set_targeting_mode(enabled: bool) -> void:
	if target_back_button:
		target_back_button.visible = enabled
	if card_ui:
		card_ui.visible = not enabled
	if enabled:
		hide_action_buttons()
	elif activeBattler:
		show_action_buttons(activeBattler)

func _on_target_back_button_pressed() -> void:
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.has_method("exit_targeting_mode"):
		battle_manager.exit_targeting_mode()
	set_targeting_mode(false)

@onready var turn_queue_container = $Control/TurnQueueUI/QueueContainer

func update_turn_queue(turn_order: Array, current_turn_idx: int) -> void:
	if not turn_queue_container:
		return
	
	for child in turn_queue_container.get_children():
		child.queue_free()
	
	if turn_order.is_empty():
		return
	
	var total = turn_order.size()
	for i in range(total):
		var idx = (current_turn_idx + i) % total
		var battler = turn_order[idx]
		if not is_instance_valid(battler) or battler.is_defeated():
			continue
		
		var card_panel = Panel.new()
		card_panel.custom_minimum_size = Vector2(80, 75)
		
		var is_player = battler.is_in_group("players")
		var is_current = (i == 0)
		
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.12, 0.22, 0.9) if is_player else Color(0.22, 0.08, 0.10, 0.9)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		
		if is_current:
			style.border_color = Color(1.0, 0.85, 0.2, 1.0)
			style.border_width_left = 3
			style.border_width_top = 3
			style.border_width_right = 3
			style.border_width_bottom = 3
			style.bg_color = Color(0.15, 0.22, 0.38, 0.95) if is_player else Color(0.38, 0.12, 0.14, 0.95)
		else:
			style.border_color = Color(0.3, 0.6, 0.9, 0.7) if is_player else Color(0.9, 0.3, 0.3, 0.7)
			
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		style.corner_radius_bottom_left = 6
		card_panel.add_theme_stylebox_override("panel", style)
		
		var vbox = VBoxContainer.new()
		vbox.anchors_preset = Control.PRESET_FULL_RECT
		vbox.offset_left = 4
		vbox.offset_top = 4
		vbox.offset_right = -4
		vbox.offset_bottom = -4
		card_panel.add_child(vbox)
		
		# Team tag (ALLY / ENEMY)
		var team_label = Label.new()
		team_label.text = "ALLY" if is_player else "ENEMY"
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		team_label.add_theme_font_size_override("font_size", 8)
		team_label.add_theme_color_override("font_color",
			Color(0.4, 0.8, 1.0) if is_player else Color(1.0, 0.4, 0.4))
		vbox.add_child(team_label)
		
		# Actor name / number
		var name_label = Label.new()
		name_label.text = battler.character_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(name_label)
		
		var hp_bar = ProgressBar.new()
		hp_bar.custom_minimum_size = Vector2(0, 8)
		hp_bar.max_value = battler.max_health
		hp_bar.value = battler.current_health
		hp_bar.show_percentage = false
		vbox.add_child(hp_bar)
		
		if is_current:
			var turn_label = Label.new()
			turn_label.text = "► NOW"
			turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			turn_label.add_theme_font_size_override("font_size", 9)
			turn_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			vbox.add_child(turn_label)
		
		turn_queue_container.add_child(card_panel)

func update_ui():
	update_character_info()
	update_party_status()
