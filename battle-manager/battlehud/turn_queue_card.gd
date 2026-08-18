class_name TurnQueueCard
extends Panel

var team_label: Label
var name_label: Label
var hp_bar: ProgressBar
var turn_label: Label

var is_player: bool = false
var is_current: bool = false

func _ready() -> void:
	# Get references to child nodes when scene is ready
	team_label = $VBox/TeamLabel
	name_label = $VBox/NameLabel
	hp_bar = $VBox/HPBar
	turn_label = $VBox/TurnLabel

func setup(battler: Battler, is_current_turn: bool = false) -> void:
	if not battler:
		return
	
	# Wait for scene to be ready if nodes aren't available yet
	if not team_label:
		await ready
	
	is_player = battler.is_in_group("players")
	is_current = is_current_turn
	
	# Set basic info
	team_label.text = "ALLY" if is_player else "ENEMY"
	name_label.text = battler.character_name
	
	# Update HP bar
	hp_bar.max_value = battler.max_health
	hp_bar.value = battler.current_health
	
	# Show/hide turn indicator
	turn_label.visible = is_current
	
	# Apply styling
	apply_style()

func apply_style() -> void:
	# Always create a new stylebox to avoid immutability issues
	var style = StyleBoxFlat.new()
	
	# Base colors
	if is_player:
		style.bg_color = Color(0.08, 0.12, 0.22, 0.9)
		team_label.modulate = Color(0.4, 0.8, 1.0)
	else:
		style.bg_color = Color(0.22, 0.08, 0.10, 0.9)
		team_label.modulate = Color(1.0, 0.4, 0.4)
	
	# Border settings
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	
	# Current turn styling
	if is_current:
		style.border_color = Color(1.0, 0.85, 0.2, 1.0)
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
		
		if is_player:
			style.bg_color = Color(0.15, 0.22, 0.38, 0.95)
		else:
			style.bg_color = Color(0.38, 0.12, 0.14, 0.95)
	else:
		style.border_color = Color(0.3, 0.6, 0.9, 0.7) if is_player else Color(0.9, 0.3, 0.3, 0.7)
	
	# Corner radius
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	
	add_theme_stylebox_override("panel", style)
	
	# HP bar styling
	apply_hp_bar_style()

func apply_hp_bar_style() -> void:
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

func update_hp(current_health: int, max_health: int) -> void:
	hp_bar.max_value = max_health
	hp_bar.value = current_health

func set_current_turn(is_current_turn: bool) -> void:
	is_current = is_current_turn
	turn_label.visible = is_current
	apply_style()