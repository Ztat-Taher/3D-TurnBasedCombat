extends ColorRect
class_name ScreenFlash

# Screen flash overlay system for game feel
# Provides different flash types for combat events

signal flash_started
signal flash_finished

var flash_tween: Tween
var is_flashing: bool = false

# Flash presets
enum FlashType {
	CRITICAL,    # White/yellow for critical hits
	DAMAGE,      # Red for damage
	BLOCK,       # Blue for block/parry
	AOE,         # Mixed colors for AOE attacks
	CUSTOM       # Custom color
}

func _ready() -> void:
	visible = false
	modulate = Color.TRANSPARENT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Ensure this renders on top of everything
	z_index = 1000

# Critical hit flash (white/yellow)
func critical_flash(duration: float = 0.15, intensity: float = 0.8) -> void:
	var flash_color: Color = Color(1.0, 1.0, 0.9, intensity)
	_start_flash(flash_color, duration)

# Damage flash (red)
func damage_flash(duration: float = 0.1, intensity: float = 0.5) -> void:
	print("ScreenFlash: damage_flash - duration: ", duration, " intensity: ", intensity, " visible: ", visible, " modulate: ", modulate)
	var flash_color: Color = Color(1.0, 0.2, 0.2, intensity)
	_start_flash(flash_color, duration)

# Block/parry flash (blue)
func block_flash(duration: float = 0.2, intensity: float = 0.6) -> void:
	var flash_color: Color = Color(0.2, 0.5, 1.0, intensity)
	_start_flash(flash_color, duration)

# AOE flash (mixed colors - purple/pink)
func aoe_flash(duration: float = 0.25, intensity: float = 0.7) -> void:
	var flash_color: Color = Color(1.0, 0.5, 0.8, intensity)
	_start_flash(flash_color, duration)

# Dodge flash (green/cyan)
func dodge_flash(duration: float = 0.1, intensity: float = 0.4) -> void:
	var flash_color: Color = Color(0.2, 1.0, 0.8, intensity)
	_start_flash(flash_color, duration)

# Custom flash with full control
func custom_flash(flash_color: Color, duration: float) -> void:
	_start_flash(flash_color, duration)

func _start_flash(flash_color: Color, duration: float) -> void:
	print("ScreenFlash: _start_flash called - color: ", flash_color, " duration: ", duration)
	# Cancel any existing flash
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	
	is_flashing = true
	flash_started.emit()
	
	visible = true
	modulate = flash_color
	print("ScreenFlash: After setting visible and modulate - visible: ", visible, " modulate: ", modulate)
	
	flash_tween = create_tween()
	
	# Fade out
	flash_tween.tween_property(self, "modulate:a", 0.0, duration)
	flash_tween.tween_callback(_on_flash_finished)

func _on_flash_finished() -> void:
	is_flashing = false
	visible = false
	modulate = Color.TRANSPARENT
	flash_finished.emit()

func stop_flash() -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	is_flashing = false
	visible = false
	modulate = Color.TRANSPARENT
	flash_finished.emit()

# Flash with custom curve for more control
func flash_with_curve(flash_color: Color, duration: float, curve: Tween.TransitionType) -> void:
	if flash_tween and flash_tween.is_valid():
		flash_tween.kill()
	
	is_flashing = true
	flash_started.emit()
	
	visible = true
	modulate = flash_color
	
	flash_tween = create_tween()
	flash_tween.set_trans(curve)
	flash_tween.tween_property(self, "modulate:a", 0.0, duration)
	flash_tween.tween_callback(_on_flash_finished)

# Quick flash for rapid-fire effects
func quick_flash(flash_color: Color) -> void:
	_start_flash(flash_color, 0.05)

# Sustained flash for longer effects
func sustained_flash(flash_color: Color, duration: float = 0.5) -> void:
	_start_flash(flash_color, duration)
