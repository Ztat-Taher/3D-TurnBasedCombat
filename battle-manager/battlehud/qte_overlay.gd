class_name QTEOverlay
extends Panel

var title_label: Label
var key_label: Label
var progress_bar: ProgressBar

func _ready() -> void:
	title_label = $VBox/TitleLabel
	key_label = $VBox/KeyLabel
	progress_bar = $VBox/ProgressBar
	
	apply_panel_style()
	apply_progress_bar_style()

func setup(input_key: String, time_limit: float) -> void:
	if not title_label:
		await ready
	
	title_label.text = "ATTACK QTE!"
	key_label.text = "[ " + input_key.to_upper() + " ]"
	progress_bar.max_value = time_limit
	progress_bar.value = time_limit

func update_progress(time_left: float) -> void:
	if progress_bar:
		progress_bar.value = time_left

func apply_panel_style() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.9, 0.7, 0.2, 1.0)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	add_theme_stylebox_override("panel", style)

func apply_progress_bar_style() -> void:
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.9, 0.7, 0.2, 0.9)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_right = 3
	fill_style.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_right = 3
	bg_style.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("background", bg_style)