## EnemyHealthBar
## A static health bar for enemy battlers displayed in a top panel
## Shows HP, shields, and status effects with juice animations
extends Control

## Emitted after death fade-out finishes so parent containers can clean up.
signal bar_died

var enemy_battler: Battler = null
var _is_dying: bool = false

@onready var name_label: Label = $VBox/NameLabel
@onready var hp_bar: ProgressBar = $VBox/HPContainer/HPBar
@onready var hp_damage_bar: ProgressBar = $VBox/HPContainer/HPDamageBar
@onready var hp_label: Label = $VBox/HPContainer/HPBar/HPBarOverlaysContainer/HPNumLabel
@onready var hp_juice: ProgressBarJuice = $VBox/HPContainer/HPJuice
@onready var status_icons_container: StatusIconsContainer = $VBox/StatusIconsContainer
@onready var status_icon_template: TextureRect = $VBox/StatusIconsContainer/StatusIconTemplate
@onready var shield_container: HBoxContainer = $VBox/HPContainer/HPBar/HPBarOverlaysContainer/ShieldContainer
@onready var shield_template: TextureRect = $VBox/HPContainer/HPBar/HPBarOverlaysContainer/ShieldContainer/Shield

func _ready() -> void:
	# Start invisible until setup
	modulate.a = 0.0

func setup(battler: Battler) -> void:
	enemy_battler = battler
	# Connect to health signal
	if not battler.health_changed.is_connected(_on_health_changed):
		battler.health_changed.connect(_on_health_changed)
	
	# Connect to shield changes
	if battler.has_signal("shield_changed") and not battler.shield_changed.is_connected(_on_shield_changed):
		battler.shield_changed.connect(_on_shield_changed)
	
	# Setup status icons container with the reusable component
	if status_icons_container and status_icon_template:
		status_icons_container.setup(battler, status_icon_template)
	
	# Initial shield update
	update_shields()
	
	# Setup juice component if it exists
	if hp_juice:
		hp_juice.setup(hp_bar, hp_damage_bar, hp_label)
		hp_juice.enable_healing_feedback = true
		hp_juice.enable_critical_health = true
	
	# Initialize values
	hp_bar.max_value = battler.max_health
	hp_bar.value = battler.current_health
	if hp_damage_bar:
		hp_damage_bar.max_value = battler.max_health
		hp_damage_bar.value = battler.current_health
	name_label.text = battler.character_name
	_update_hp_label(battler.current_health, battler.max_health)
	
	# Fade in animation
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)

func _on_health_changed(current: int, maximum: int) -> void:
	if not is_instance_valid(self):
		return
	
	if hp_juice:
		hp_juice.update_value(float(current), float(maximum))
	elif hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = float(current)
		if hp_damage_bar:
			hp_damage_bar.max_value = maximum
			hp_damage_bar.value = float(current)
		_update_hp_label(current, maximum)
	
	# Hide when dead
	if current <= 0:
		_is_dying = true
		var out := create_tween()
		out.tween_property(self, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN)
		out.tween_callback(func() -> void:
			bar_died.emit()
			queue_free()
		)

func _update_hp_label(current: int, maximum: int) -> void:
	if hp_label:
		hp_label.text = "%d / %d" % [current, maximum]

func update_shields() -> void:
	if not shield_container or not enemy_battler:
		return
	
	# Clear existing shields
	for child in shield_container.get_children():
		if child != shield_template:
			child.queue_free()
	
	# Check for Protected state
	if enemy_battler.active_states.has("Protected"):
		var protected_state = enemy_battler.active_states["Protected"] as ProtectedState
		if protected_state and protected_state.has_shield():
			var shield_count = protected_state.get_remaining_shields()
			# Add shield icons for each remaining shield
			for i in range(shield_count):
				var shield = shield_template.duplicate()
				shield.visible = true
				shield_container.add_child(shield)

func _on_shield_changed(shield_count: int) -> void:
	update_shields()
