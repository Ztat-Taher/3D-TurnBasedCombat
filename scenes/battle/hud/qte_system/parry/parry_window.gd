class_name ParryWindow
extends PanelContainer

var title_label: Label
var parry_prompt: Label
var dodge_prompt: Label
var progress_bar: ProgressBar
var perfect_indicator: Panel
var hint_label: Label

func _ready() -> void:
	title_label = $VBox/Header/TitleLabel
	parry_prompt = $VBox/Header/ParryPrompt
	dodge_prompt = $VBox/Header/DodgePrompt
	progress_bar = $VBox/BarContainer/ProgressBar
	perfect_indicator = $VBox/BarContainer/PerfectIndicator
	hint_label = $VBox/HintLabel
	
	apply_base_style()
	apply_progress_bar_style()
	apply_perfect_indicator_style()

func setup(defender_name: String, duration: float, perfect_duration: float) -> void:
	if not title_label:
		await ready
	
	title_label.text = "DEFEND [%s]!" % defender_name.to_upper()
	progress_bar.max_value = duration
	progress_bar.value = duration
	
	var perfect_ratio = clampf(perfect_duration / max(duration, 0.001), 0.1, 0.9)
	perfect_indicator.set_anchor(SIDE_LEFT, 1.0 - perfect_ratio)

func update_progress(time_remaining: float) -> void:
	if progress_bar:
		progress_bar.value = time_remaining

func apply_base_style() -> void:
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
	add_theme_stylebox_override("panel", style)

func apply_progress_bar_style() -> void:
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.7, 1.0, 0.95)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_right = 3
	fill_style.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("fill", fill_style)
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.14, 0.2, 0.8)
	bg_style.corner_radius_top_left = 3
	bg_style.corner_radius_top_right = 3
	bg_style.corner_radius_bottom_right = 3
	bg_style.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("background", bg_style)

func apply_perfect_indicator_style() -> void:
	var perf_style = StyleBoxFlat.new()
	perf_style.bg_color = Color(1.0, 0.85, 0.2, 0.45)
	perf_style.border_width_left = 1
	perf_style.border_width_right = 1
	perf_style.border_color = Color(1.0, 0.9, 0.3, 0.9)
	perf_style.corner_radius_top_right = 3
	perf_style.corner_radius_bottom_right = 3
	perfect_indicator.add_theme_stylebox_override("panel", perf_style)