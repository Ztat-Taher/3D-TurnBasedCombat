class_name BattleHud
extends CanvasLayer

signal action_selected(action: String, item: Item)
signal menu_opened
signal card_selected(card: CardData)
signal end_turn_pressed

@onready var item_button_scene: PackedScene = preload("res://battle-manager/battlehud/item-button-preset.tscn")
@onready var item_container = $Control/Items/ScrollContainer/BoxContainer

@onready var action_buttons: BoxContainer = $Control/ActionButtons
@onready var attack_button: Button = $Control/ActionButtons/Attack
@onready var items_button: Button = $Control/ActionButtons/Items
@onready var run_button: Button = $Control/ActionButtons/Run
@onready var end_turn_button: Button = $Control/ActionButtons/EndTurnButton
@onready var global_back_button: Button = $Control/BackButton
@onready var battle_text_display: RichTextLabel = $Control/BattleTextDisplay/Text
@onready var item_select: Control = $Control/Items
@onready var card_ui: Control = $Control/CardUI
@onready var party_status_panel: HBoxContainer = $Control/PartyStatusPanel
@onready var boss_bar = $Control/BossBar
@onready var enemy_overhead_bars_container: Control = $Control/EnemyOverheadBarsContainer
@onready var move_banner: Control = $Control/MoveBanner
@onready var move_banner_actor: Label = $Control/MoveBanner/Panel/VBox/ActorLabel
@onready var move_banner_label: Label = $Control/MoveBanner/Panel/VBox/MoveLabel

var aoe_confirm_button: Button = null

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
	if battle_manager and battle_manager.is_animating:
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
	
	# Setup input prompts
	_setup_input_prompts()
	
	# Slide in from right with fade animation
	# Show attack button initially, hide card UI
	if attack_button:
		attack_button.visible = true
	if card_ui:
		card_ui.visible = false
	
	_update_back_button_visibility()
	
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

func _update_back_button_visibility():
	# Systematic back button visibility management
	var should_show = false
	
	# Show back button if items menu is open
	if item_select and item_select.visible:
		should_show = true
	
	# Show back button if card UI is open
	elif card_ui and card_ui.visible:
		should_show = true
	
	# Show back button if in targeting mode
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.in_target_selection:
		should_show = true
	
	if global_back_button:
		global_back_button.visible = should_show

func _setup_input_prompts():
	# Setup input prompts for action buttons
	if attack_button:
		var attack_prompt = attack_button.get_node_or_null("AttackPrompt")
		if attack_prompt:
			attack_prompt.set_meta("action_name", "attack")
	
	if items_button:
		var items_prompt = items_button.get_node_or_null("ItemsPrompt")
		if items_prompt:
			items_prompt.set_meta("action_name", "toggle_items")
	
	if run_button:
		var run_prompt = run_button.get_node_or_null("RunPrompt")
		if run_prompt:
			run_prompt.set_meta("action_name", "toggle_run")
	
	if end_turn_button:
		var end_turn_prompt = end_turn_button.get_node_or_null("EndTurnPrompt")
		if end_turn_prompt:
			end_turn_prompt.set_meta("action_name", "ui_cancel")
	
	if global_back_button:
		var back_prompt = global_back_button.get_node_or_null("BackPrompt")
		if back_prompt:
			back_prompt.set_meta("action_name", "ui_cancel")

func update_character_info():
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
	_close_items_menu()

func _close_items_menu():
	item_select.visible = false
	# Show items button again when closing items menu
	if items_button:
		items_button.visible = true
	if activeBattler:
		show_action_buttons(activeBattler)
	_update_back_button_visibility()

func _close_card_menu():
	close_card_ui()
	if activeBattler:
		show_action_buttons(activeBattler)
	_update_back_button_visibility()

func _on_item_selected(item: Item) -> void:
	item_select.visible = false
	if card_ui:
		card_ui.visible = true
	action_selected.emit("item", item)
	_update_back_button_visibility()

func _on_attack_pressed() -> void:
	# Show card UI and hide attack button
	if card_ui:
		card_ui.visible = true
	if attack_button:
		attack_button.visible = false
	# Keep other action buttons visible
	if items_button:
		items_button.visible = true
	if run_button:
		run_button.visible = true
	if end_turn_button:
		end_turn_button.visible = true
	_update_back_button_visibility()

func close_card_ui() -> void:
	# Hide card UI and show attack button again
	if card_ui:
		card_ui.visible = false
	if attack_button:
		attack_button.visible = true

func _on_items_pressed() -> void:
	# Show items and hide only items button, keep others visible
	setup_item_list(activeBattler)
	item_select.visible = true
	if items_button:
		items_button.visible = false
	if card_ui:
		card_ui.visible = false
	# Keep other action buttons visible (including attack)
	if attack_button:
		attack_button.visible = true
	if run_button:
		run_button.visible = true
	if end_turn_button:
		end_turn_button.visible = true
	_update_back_button_visibility()

func _unhandled_input(event: InputEvent) -> void:
	var handled = false
	
	# Check if reactive defense is active (B button = dodge, not end turn)
	var qte_manager = get_tree().get_first_node_in_group("qte_manager")
	var qte_active = qte_manager.is_qte_active if qte_manager else false
	var qte_type = qte_manager.current_qte_type if qte_manager else ""
	var reactive_defense_active = qte_active and (qte_type == "REACTIVE_DODGE" or qte_type == "REACTIVE_PARRY")
	
	# Don't handle B button when in reactive defense mode - let QTE manager handle it
	if reactive_defense_active and event.is_action_pressed("ui_cancel"):
		return
	
	# Only process action buttons when action buttons list is visible
	if action_buttons and action_buttons.visible:
		if event.is_action_pressed("attack"):
			if attack_button and attack_button.visible:
				_on_attack_pressed()
			handled = true
		elif event.is_action_pressed("toggle_items"):
			if items_button and items_button.visible:
				_on_items_pressed()
			handled = true
		elif event.is_action_pressed("toggle_run"):
			if run_button and run_button.visible:
				_on_run_pressed()
			handled = true
		elif event.is_action_pressed("ui_cancel"):
			# Contextual: B button works for both end turn and cancel
			if end_turn_button and end_turn_button.visible:
				_on_end_turn_button_pressed()
			else:
				_on_global_back_pressed()
			handled = true
	
	# Handle cancel key for all menus via global back (B button also cancels)
	if not handled and event.is_action_pressed("ui_cancel"):
		_on_global_back_pressed()
		handled = true
	
	# Only consume input if we actually handled it
	if handled:
		get_viewport().set_input_as_handled()

func _on_run_pressed() -> void:
	hide_action_buttons()
	action_selected.emit("run", null)

func _on_end_turn_button_pressed() -> void:
	var end_btn = action_buttons.get_node_or_null("EndTurnButton")
	if end_btn:
		end_btn.disabled = true
	end_turn_pressed.emit()

func set_targeting_mode(enabled: bool) -> void:
	# Handle targeting mode visibility
	if enabled:
		hide_action_buttons()
	else:
		close_card_ui()
		if activeBattler:
			show_action_buttons(activeBattler)
	
	if card_ui:
		card_ui.visible = not enabled
	
	# Immediately update back button visibility
	_update_back_button_visibility()

func set_aoe_confirmation_mode(enabled: bool, card_name: String = "", target_count: int = 0) -> void:
	print("Setting AOE confirmation mode: ", enabled, " card: ", card_name, " targets: ", target_count)
	
	if enabled:
		hide_action_buttons()
		if card_ui:
			card_ui.visible = false
		
		# Show AOE confirmation UI
		if global_back_button:
			global_back_button.visible = true
			if global_back_button.has_method("set_text"):
				global_back_button.set_text("Cancel")
		
		# Create or show confirm button
		_ensure_aoe_confirm_button()
		if aoe_confirm_button:
			aoe_confirm_button.visible = true
			if aoe_confirm_button.has_method("set_text"):
				aoe_confirm_button.set_text("Execute " + card_name + " (" + str(target_count) + " targets)")
	else:
		hide_aoe_confirmation_mode()

func hide_aoe_confirmation_mode() -> void:
	print("Hiding AOE confirmation mode")
	
	if aoe_confirm_button:
		aoe_confirm_button.visible = false
	
	if global_back_button:
		global_back_button.visible = false

func _ensure_aoe_confirm_button() -> void:
	if not aoe_confirm_button:
		# Create confirm button dynamically
		aoe_confirm_button = Button.new()
		aoe_confirm_button.name = "AOEConfirmButton"
		aoe_confirm_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		aoe_confirm_button.set_position(Vector2(0, 100))
		aoe_confirm_button.set_size(Vector2(200, 50))
		aoe_confirm_button.pressed.connect(_on_aoe_confirm_pressed)
		add_child(aoe_confirm_button)
		print("Created AOE confirm button")

func _on_aoe_confirm_pressed() -> void:
	print("AOE confirm button pressed")
	var battle_manager = get_tree().get_first_node_in_group("battle_manager")
	if battle_manager and battle_manager.has_method("confirm_aoe_execution"):
		battle_manager.confirm_aoe_execution()

func _on_global_back_pressed() -> void:
	# Handle different back contexts
	if item_select.visible:
		_close_items_menu()
	elif card_ui and card_ui.visible:
		_close_card_menu()
	elif global_back_button and global_back_button.visible:
		# Handle targeting mode
		var battle_manager = get_tree().get_first_node_in_group("battle_manager")
		if battle_manager and battle_manager.has_method("exit_targeting_mode"):
			battle_manager.exit_targeting_mode()
		set_targeting_mode(false)

@onready var turn_queue_container = $Control/TurnQueueUI/ScrollContainer/QueueContainer

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

# ============================================================================
# REACTIVE DEFENSE UI (DODGE / PARRY / PERFECT PARRY)
# ============================================================================
var _parry_panel: PanelContainer = null
var _parry_progress: ProgressBar = null
var _parry_perfect_indicator: Panel = null

func show_parry_window(duration: float, perfect_duration: float, defender_name: String) -> void:
	hide_parry_window()
	
	_parry_panel = PanelContainer.new()
	_parry_panel.name = "ParryPromptPanel"
	_parry_panel.custom_minimum_size = Vector2(340, 75)
	_parry_panel.anchors_preset = Control.PRESET_CENTER_BOTTOM
	_parry_panel.anchor_left = 0.5
	_parry_panel.anchor_right = 0.5
	_parry_panel.anchor_top = 1.0
	_parry_panel.anchor_bottom = 1.0
	_parry_panel.offset_left = -170.0
	_parry_panel.offset_right = 170.0
	_parry_panel.offset_top = -220.0
	_parry_panel.offset_bottom = -145.0
	_parry_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_parry_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.8, 0.2, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_parry_panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_parry_panel.add_child(vbox)
	
	# Header Row: Defender Name & Action Prompts
	var header = HBoxContainer.new()
	vbox.add_child(header)
	
	var title = Label.new()
	title.text = "DEFEND [%s]!" % defender_name.to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	header.add_child(title)
	
	var prompt_parry = Label.new()
	prompt_parry.text = "[Q] PARRY"
	prompt_parry.add_theme_font_size_override("font_size", 11)
	prompt_parry.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
	header.add_child(prompt_parry)
	
	var prompt_dodge = Label.new()
	prompt_dodge.text = "[E] DODGE"
	prompt_dodge.add_theme_font_size_override("font_size", 11)
	prompt_dodge.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	header.add_child(prompt_dodge)
	
	# Timing Bar Stack
	var bar_container = Control.new()
	bar_container.custom_minimum_size = Vector2(0, 14)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(bar_container)
	
	_parry_progress = ProgressBar.new()
	_parry_progress.anchors_preset = Control.PRESET_FULL_RECT
	_parry_progress.anchor_right = 1.0
	_parry_progress.anchor_bottom = 1.0
	_parry_progress.max_value = duration
	_parry_progress.value = duration
	_parry_progress.show_percentage = false
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.7, 1.0, 0.95)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_right = 3
	fill_style.corner_radius_bottom_left = 3
	_parry_progress.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.14, 0.2, 0.8)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_right = 3
	bg_style.corner_radius_bottom_left = 3
	_parry_progress.add_theme_stylebox_override("background", bg_style)
	bar_container.add_child(_parry_progress)
	
	# Perfect parry highlight zone (overlay at the right/start of progress drain)
	_parry_perfect_indicator = Panel.new()
	var perfect_ratio = clampf(perfect_duration / max(duration, 0.001), 0.1, 0.9)
	_parry_perfect_indicator.anchors_preset = Control.PRESET_FULL_RECT
	_parry_perfect_indicator.anchor_right = 1.0
	_parry_perfect_indicator.anchor_left = 1.0 - perfect_ratio
	_parry_perfect_indicator.anchor_bottom = 1.0
	
	var perf_style = StyleBoxFlat.new()
	perf_style.bg_color = Color(1.0, 0.85, 0.2, 0.45)
	perf_style.border_width_left = 1
	perf_style.border_width_right = 1
	perf_style.border_color = Color(1.0, 0.9, 0.3, 0.9)
	perf_style.corner_radius_top_right = 3
	perf_style.corner_radius_bottom_right = 3
	_parry_perfect_indicator.add_theme_stylebox_override("panel", perf_style)
	bar_container.add_child(_parry_perfect_indicator)
	
	# Subtitle / Hint
	var hint = Label.new()
	hint.text = "⚡ Golden zone = Perfect Parry Counterattack!"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 0.7))
	vbox.add_child(hint)
	
	$Control.add_child(_parry_panel)

func update_parry_window(time_remaining: float) -> void:
	if _parry_progress and is_instance_valid(_parry_progress):
		_parry_progress.value = time_remaining

func hide_parry_window() -> void:
	if _parry_panel and is_instance_valid(_parry_panel):
		_parry_panel.queue_free()
		_parry_panel = null
		_parry_progress = null
		_parry_perfect_indicator = null

# ============================================================================
# MOVE ANNOUNCEMENT BANNER
# ============================================================================
var _move_banner_tween: Tween

func show_move_announcement(actor_name: String, move_name: String, move_type: String = "attack") -> void:
	if not move_banner:
		return
	
	if _move_banner_tween and _move_banner_tween.is_running():
		_move_banner_tween.kill()
	
	if move_banner_actor:
		move_banner_actor.text = actor_name.to_upper()
	if move_banner_label:
		move_banner_label.text = "◆ %s ◆" % move_name.to_upper()
	
	# Apply rich styled panel box depending on move type
	var panel = $Control/MoveBanner/Panel as PanelContainer
	if panel:
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 10
		style.corner_radius_top_right = 10
		style.corner_radius_bottom_right = 10
		style.corner_radius_bottom_left = 10
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		
		match move_type:
			"buff", "heal":
				style.bg_color = Color(0.05, 0.12, 0.22, 0.92)
				style.border_color = Color(0.2, 0.8, 1.0, 0.9)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				if move_banner_actor:
					move_banner_actor.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
			_:
				style.bg_color = Color(0.18, 0.05, 0.06, 0.92)
				style.border_color = Color(1.0, 0.3, 0.25, 0.9)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				if move_banner_actor:
					move_banner_actor.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		
		panel.add_theme_stylebox_override("panel", style)
	
	move_banner.visible = true
	move_banner.modulate.a = 0.0
	move_banner.scale = Vector2(0.9, 0.9)
	move_banner.pivot_offset = move_banner.size / 2.0
	
	_move_banner_tween = create_tween()
	_move_banner_tween.set_parallel(true)
	_move_banner_tween.set_ease(Tween.EaseType.EASE_OUT)
	_move_banner_tween.set_trans(Tween.TransitionType.TRANS_BACK)
	_move_banner_tween.tween_property(move_banner, "modulate:a", 1.0, 0.25)
	_move_banner_tween.tween_property(move_banner, "scale", Vector2(1.0, 1.0), 0.25)

func hide_move_announcement() -> void:
	if not move_banner or not move_banner.visible:
		return
	
	if _move_banner_tween and _move_banner_tween.is_running():
		_move_banner_tween.kill()
	
	_move_banner_tween = create_tween()
	_move_banner_tween.set_parallel(true)
	_move_banner_tween.set_ease(Tween.EaseType.EASE_IN)
	_move_banner_tween.set_trans(Tween.TransitionType.TRANS_CUBIC)
	_move_banner_tween.tween_property(move_banner, "modulate:a", 0.0, 0.2)
	_move_banner_tween.tween_property(move_banner, "scale", Vector2(0.9, 0.9), 0.2)
	_move_banner_tween.chain().tween_callback(func(): move_banner.visible = false)
