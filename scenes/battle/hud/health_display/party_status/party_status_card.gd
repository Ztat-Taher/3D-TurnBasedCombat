class_name PartyStatusCard
extends Control

@onready var name_label: Label = $BackgroundContainer/NameLabel
@onready var active_tag: Label = $BackgroundContainer/ActiveTag
@onready var hp_bar: TextureProgressBar = $BackgroundContainer/HPContainer/HPBar
@onready var hp_damage_bar: TextureProgressBar = $BackgroundContainer/HPContainer/HPDamageBar
@onready var hp_num_label: Label = $BackgroundContainer/HPContainer/HPBar/HPNumLabel
@onready var ap_bar_container: HBoxContainer = $BackgroundContainer/APContainer/APBarContainer
@onready var ap_num_label: Label = $BackgroundContainer/APContainer/APNumContainer/APNumBackground/APNumLabel
@onready var portrait_background: TextureRect = $BackgroundContainer/PortraitBackground
@onready var status_icons_container: StatusIconsContainer = $BackgroundContainer/StatusIconsContainer
@onready var status_icon_template: TextureRect = $BackgroundContainer/StatusIconsContainer/StatusIconTemplate

@onready var hp_juice: ProgressBarJuice = $BackgroundContainer/HPContainer/HPJuice
@onready var shield_container: HBoxContainer = $BackgroundContainer/HPContainer/HPBar/ShieldContainer
@onready var shield_template: TextureRect = $BackgroundContainer/HPContainer/HPBar/ShieldContainer/Shield

@export var ap_bar_template: PackedScene # If you want to use a template, otherwise we'll duplicate the existing child

var is_active: bool = false
var current_ally: Battler = null

func setup(ally: Battler) -> void:
	if not ally:
		return
	
	current_ally = ally
	
	# Ensure nodes are ready before accessing them
	if not name_label:
		await ready
	
	if name_label:
		name_label.text = ally.character_name
	
	# Setup juice components if they exist
	if hp_juice:
		hp_juice.setup(hp_bar, hp_damage_bar, hp_num_label)
		hp_juice.enable_healing_feedback = true
		hp_juice.enable_critical_health = true
	
	update_hp(ally.current_health, ally.max_health)
	
	# Read AP directly from ally battler
	var current_ap = 3
	var max_ap = 3
	if "current_ap" in ally:
		current_ap = ally.current_ap
	if "max_ap" in ally:
		max_ap = ally.max_ap
	elif ally.has_method("get_max_ap"):
		max_ap = ally.get_max_ap()
	
	update_ap(current_ap, max_ap)
	
	# Connect to ally AP changes if signal exists
	if ally.has_signal("ap_changed") and not ally.ap_changed.is_connected(update_ap):
		ally.ap_changed.connect(update_ap)
	
	# Connect to ally shield changes if signal exists
	if ally.has_signal("shield_changed") and not ally.shield_changed.is_connected(_on_shield_changed):
		ally.shield_changed.connect(_on_shield_changed)
	
	# Connect to ally state changes if signal exists (for initial state application)
	if ally.has_signal("state_applied") and not ally.state_applied.is_connected(_on_state_applied):
		ally.state_applied.connect(_on_state_applied)
	
	# Setup status icons container with the reusable component
	if status_icons_container and status_icon_template:
		status_icons_container.setup(ally, status_icon_template)
	
	# Initial shield update
	update_shields()
	
	# Entrance animation
	modulate.a = 0.0
	scale = Vector2(0.7, 0.7)
	
	# Set pivot to bottom center for proper scaling
	pivot_offset = Vector2(size.x / 2, size.y)
	
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2(1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	
	# Apply initial inactive state
	set_active(false)

func set_active(is_active_battler: bool) -> void:
	is_active = is_active_battler
	if active_tag:
		active_tag.visible = is_active
	
	var target_scale: Vector2
	var target_modulate: Color
	
	if is_active:
		# Active: larger scale from bottom center
		target_scale = Vector2(1.1, 1.1)
		target_modulate = Color.WHITE
	else:
		# Inactive: smaller scale, slightly translucent
		target_scale = Vector2(1.0, 1.0)
		target_modulate = Color(0.8, 0.8, 0.8, 0.85)
	
	# Animate the transitions
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", target_scale, 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", target_modulate, 0.2).set_ease(Tween.EASE_OUT)

func update_hp(current_health: int, max_health: int) -> void:
	if hp_juice:
		hp_juice.update_value(float(current_health), float(max_health))
	elif hp_bar:
		hp_bar.max_value = max_health
		hp_bar.value = float(current_health)
		if hp_damage_bar:
			hp_damage_bar.max_value = max_health
			hp_damage_bar.value = float(current_health)
		if hp_num_label:
			hp_num_label.text = "%d/%d" % [current_health, max_health]

func update_ap(current_ap: int, max_ap: int) -> void:
	if ap_num_label:
		ap_num_label.text = str(current_ap)
	
	if ap_bar_container:
		# Ensure we have the correct number of AP bar nodes
		var current_child_count = ap_bar_container.get_child_count()
		
		# If no children, we can't do anything unless we have a template
		if current_child_count == 0:
			return
			
		# Adjust number of bars to match max_ap
		if current_child_count < max_ap:
			var template = ap_bar_container.get_child(0)
			for i in range(max_ap - current_child_count):
				var new_bar = template.duplicate()
				ap_bar_container.add_child(new_bar)
		elif current_child_count > max_ap:
			for i in range(current_child_count - 1, max_ap - 1, -1):
				var child = ap_bar_container.get_child(i)
				child.queue_free()
		
		# Update visibility/tint of bars based on current_ap
		# Wait a frame if we just added/removed children to ensure count is correct
		# Or just use the children we have now and assume the next call will fix it
		for i in range(ap_bar_container.get_child_count()):
			var bar = ap_bar_container.get_child(i) as CanvasItem
			if bar:
				if i < current_ap:
					bar.modulate = Color.WHITE
					bar.show()
				else:
					# Dim or hide inactive AP bars
					bar.modulate = Color(0.3, 0.3, 0.3, 0.5)
					# bar.hide() # Or keep them visible but dimmed

func set_portrait_texture(texture: Texture2D) -> void:
	if portrait_background:
		portrait_background.texture = texture

func update_shields() -> void:
	if not shield_container or not current_ally:
		return
	
	# Clear existing shields
	for child in shield_container.get_children():
		if child != shield_template:
			child.queue_free()
	
	# Check for Protected state
	if current_ally.active_states.has("Protected"):
		var protected_state = current_ally.active_states["Protected"] as ProtectedState
		if protected_state and protected_state.has_shield():
			var shield_count = protected_state.get_remaining_shields()
			# Add shield icons for each remaining shield
			for i in range(shield_count):
				var shield = shield_template.duplicate()
				shield.visible = true
				shield_container.add_child(shield)

func _on_shield_changed(shield_count: int) -> void:
	update_shields()

func _on_state_applied(state_name: String) -> void:
	# Update shields when Protected state is applied
	if state_name == "Protected":
		update_shields()
