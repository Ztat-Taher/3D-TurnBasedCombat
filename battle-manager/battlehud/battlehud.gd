class_name BattleHud
extends CanvasLayer

signal action_selected(action: String, item:Item)
signal menu_opened
signal card_selected(card: CardData)
signal end_turn_pressed

@onready var item_button_scene: PackedScene = preload("res://battle-manager/battlehud/item-button-preset.tscn")
@onready var item_container = $Control/Items/ScrollContainer/BoxContainer

@onready var action_buttons: BoxContainer = $Control/ActionButtons
@onready var ally_stats: BoxContainer = $Control/Players/AllAllies/AllyStats
@onready var enemy_stats: BoxContainer = $Control/Enemies/AllEnemies/EnemyStats
@onready var battle_text_display: RichTextLabel = $Control/BattleTextDisplay/Text
@onready var item_select: Control = $Control/Items
@onready var card_ui: Control = $Control/CardUI

var activeBattler: Node = null
var enemy: Node = null

var active_allies = []
var active_enemies = []

# Health bar-related nodes
@onready var player_health_bar = $Control/Players/AllAllies/AllyStats/PlayerHealthBar
@onready var enemy_health_bar = $Control/Enemies/AllEnemies/EnemyStats/EnemyHealthBar

# Add SP bar reference
@onready var player_sp_bar = $Control/Players/AllAllies/AllyStats/PlayerSPBar

func _ready():
	print("Inside BattleHUD _ready()")
	print("ActionButtons: ", action_buttons)
	print("ActionButtons visible: ", str(action_buttons.visible) if action_buttons else "null")
	
	# Connect CardUI signals if it exists
	if card_ui:
		if card_ui.has_signal("card_selected"):
			card_ui.card_selected.connect(func(card): card_selected.emit(card))
		if card_ui.has_signal("end_turn_pressed"):
			card_ui.end_turn_pressed.connect(func(): end_turn_pressed.emit())
	item_select.visible = false
	hide_action_buttons()
	# Initialize health bars
	if player_health_bar and enemy_health_bar:
		player_health_bar.value = 0
		enemy_health_bar.value = 0

func on_start_combat(enemy_node: Node):
	enemy = enemy_node
	update_health_bars()

func on_add_character(character: Node):
	if character.is_in_group("players"):
		if ally_stats.has_method("update_player_stats"):
			ally_stats.update_player_stats(character)
	else:
		if ally_stats.has_method("update_enemy_stats"):
			enemy_stats.update_enemy_stats(character)

# Modify update_health_bars
func update_health_bars():
	for i in range(active_allies.size()):
		var ally = active_allies[i]
		var container = $Control/Players/AllAllies.get_child(i)
		container.update_character_info(ally)
		
	for i in range(active_enemies.size()):
		var target_enemy = active_enemies[i]
		var container = $Control/Enemies/AllEnemies.get_child(i)
		container.update_character_info(target_enemy)

func set_activebattler(character: Node):
	activeBattler = character

func show_action_buttons(_character: Node):
	action_buttons.show()
	var end_btn = action_buttons.get_node_or_null("EndTurnButton")
	if end_btn:
		end_btn.disabled = false
	# Focus on Items button since Attack/Skills/Defend are removed
	var items_button = action_buttons.get_node_or_null("Items")
	if items_button and not items_button.disabled and not items_button.visible:
		items_button.call_deferred("grab_focus")
	# You can customize this part to show different actions based on the character

func hide_action_buttons():
	action_buttons.hide()

func update_character_info():
	if enemy and enemy_stats:
		enemy_stats.update_enemy_stats(enemy)
		
	if ally_stats.has_method("update_player_stats") and activeBattler:
		ally_stats.update_player_stats(activeBattler)
	if ally_stats.has_method("update_enemy_stats") and enemy:
		enemy_stats.update_enemy_stats(enemy)

# Health bar update functions
func update_player_health_bar():
	if activeBattler:
		# Health bar
		player_health_bar.max_value = activeBattler.max_health
		player_health_bar.value = activeBattler.current_health
		player_health_bar.show()
		
		# SP bar
		player_sp_bar.max_value = activeBattler.max_sp
		player_sp_bar.value = activeBattler.current_sp
		player_sp_bar.show()

func update_enemy_health_bar():
	if enemy:
		enemy_health_bar.max_value = enemy.max_health
		enemy_health_bar.value = enemy.current_health
		enemy_health_bar.show()

# Action button signals
func setup_item_list(battler: Battler) -> void:
	# Clear existing item buttons
	for child in item_container.get_children():
		child.queue_free()
	
	var has_items = false
	if battler and battler.inventory and !battler.inventory.collection.is_empty():
		for item:Item in battler.inventory.collection.keys():
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

# Add other action button handlers as needed (Skills, Item, Run)

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

# Function to update all UI elements
func update_ui():
	update_character_info()
	update_player_health_bar()
	update_enemy_health_bar()

# Call this function when the battle starts or when switching to 3D
func prepare_for_3d():
# Create a new SubViewport
	var viewport = SubViewport.new()
	viewport.size = Vector2(1024, 600)  # Adjust size as needed
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Move all children of this CanvasLayer to the SubViewport
	for child in get_children():
		remove_child(child)
		viewport.add_child(child)

	# Add the SubViewport to a new TextureRect
	var texture_rect = TextureRect.new()
	texture_rect.texture = viewport.get_texture()
	add_child(texture_rect)
