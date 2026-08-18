class_name PartyStatusCard
extends PanelContainer

var name_label: Label
var active_tag: Label
var hp_bar: ProgressBar
var hp_num_label: Label
var ap_bar: ProgressBar
var ap_num_label: Label

var is_active: bool = false

func _ready() -> void:
	# Get references to child nodes when scene is ready
	name_label = $VBox/HeaderHBox/NameLabel
	active_tag = $VBox/HeaderHBox/ActiveTag
	hp_bar = $VBox/HPHBox/HPBar
	hp_num_label = $VBox/HPHBox/HPNumLabel
	ap_bar = $VBox/APHBox/APBar
	ap_num_label = $VBox/APHBox/APNumLabel

func setup(ally: Battler) -> void:
	if not ally:
		return
	
	# Wait for scene to be ready if nodes aren't available yet
	if not name_label:
		await ready
	
	name_label.text = ally.character_name
	update_hp(ally.current_health, ally.max_health)
	update_ap(3, 3) # Default AP
	apply_style()

func set_active(is_active_battler: bool) -> void:
	is_active = is_active_battler
	active_tag.visible = is_active
	apply_style()

func update_hp(current_health: int, max_health: int) -> void:
	hp_bar.max_value = max_health
	hp_bar.value = current_health
	hp_num_label.text = "%d/%d" % [current_health, max_health]

func update_ap(current_ap: int, max_ap: int) -> void:
	ap_bar.max_value = max_ap
	ap_bar.value = current_ap
	ap_num_label.text = "%d/%d" % [current_ap, max_ap]

func apply_style() -> void:
	# Always create a new stylebox to avoid immutability issues
	var style = StyleBoxFlat.new()
	
	# Base styling
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
	
	# Active styling
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
	
	add_theme_stylebox_override("panel", style)
	
	# Apply HP bar styling
	apply_hp_bar_style()
	
	# Apply AP bar styling
	apply_ap_bar_style()

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

func apply_ap_bar_style() -> void:
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