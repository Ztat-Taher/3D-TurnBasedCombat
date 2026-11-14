@tool
class_name VestigeIconsContainer
extends HBoxContainer
## Container for displaying vestige icons for a battler
## Shows all acquired vestiges (global and per-character)

var vestige_icon_template: TextureRect = null
var battler: Battler = null
var vestige_info_popup_scene: PackedScene = null
var active_vestige_popups: Array[Control] = []
var popup_container: VBoxContainer = null

func _ready():
	# Load vestige info popup scene (reuse status info popup for now)
	var popup_path = "res://scenes/battle/hud/vestiges/vestige_tooltip.tscn"
	if ResourceLoader.exists(popup_path):
		vestige_info_popup_scene = load(popup_path)
	
	# Set up container-level hover detection
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_container_hovered)
	mouse_exited.connect(_on_container_exited)

func setup(battler_node: Battler, template: TextureRect) -> void:
	battler = battler_node
	vestige_icon_template = template
	
	if not battler:
		return
	
	# Get reference to PopUpContainer from parent scene
	if get_parent():
		popup_container = get_parent().get_node_or_null("PopUpContainer")
	
	# Connect to vestige changes if signal exists
	if battler.has_signal("vestige_added") and not battler.vestige_added.is_connected(_on_vestige_added):
		battler.vestige_added.connect(_on_vestige_added)
	if battler.has_signal("vestige_removed") and not battler.vestige_removed.is_connected(_on_vestige_removed):
		battler.vestige_removed.connect(_on_vestige_removed)
	
	# Initial vestige icons update
	update_vestige_icons()

func update_vestige_icons() -> void:
	if not vestige_icon_template or not battler:
		return
	
	# Clear existing icons
	for child in get_children():
		if child != vestige_icon_template:
			child.queue_free()
	
	# Get all vestiges for this battler (global + per-character)
	var all_vestiges: Array = []
	
	# Add global vestiges
	var global_vestiges = GameState.get_global_vestiges()
	all_vestiges.append_array(global_vestiges)
	
	# Add per-character vestiges if battler has active_vestiges
	if "active_vestiges" in battler:
		for vestige in battler.active_vestiges:
			if vestige and vestige not in all_vestiges:
				all_vestiges.append(vestige)
	
	# Add icons for each vestige
	for vestige in all_vestiges:
		var icon = vestige_icon_template.duplicate()
		icon.visible = true
		icon.custom_minimum_size = Vector2(16, 16)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		# Use the vestige's icon texture if available
		if vestige.icon:
			icon.texture = vestige.icon
		
		# Apply shader-based rarity effects
		_apply_rarity_shader(icon, vestige.rarity)
		
		add_child(icon)


func _apply_rarity_shader(icon: TextureRect, rarity: int) -> void:
	var shader_material = ShaderMaterial.new()
	
	match rarity:
		Vestige.Rarity.COMMON:
			# Subtle pulse effect
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec4 tex = texture(TEXTURE, UV);
					float pulse = 0.5 + 0.5 * sin(time * 2.0);
					vec3 glow = color.rgb * pulse * 0.3;
					COLOR = vec4(tex.rgb + glow, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(0.8, 0.8, 0.8, 1.0))
		
		Vestige.Rarity.UNCOMMON:
			# Cyan energy flow effect
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec4 tex = texture(TEXTURE, UV);
					float energy = 0.5 + 0.5 * sin(time * 3.0 + UV.x * 5.0);
					vec3 glow = color.rgb * energy * 0.5;
					float border = step(0.9, UV.x) + step(0.9, UV.y) + step(0.1, 1.0 - UV.x) + step(0.1, 1.0 - UV.y);
					COLOR = vec4(tex.rgb + glow * border, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(0.0, 0.9, 1.0, 1.0))
		
		Vestige.Rarity.RARE:
			# Golden shimmer effect
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec4 tex = texture(TEXTURE, UV);
					float shimmer = 0.5 + 0.5 * sin(time * 4.0 + UV.x * 10.0 + UV.y * 10.0);
					vec3 gold = color.rgb * shimmer * 0.6;
					float dist = distance(UV, vec2(0.5));
					float ring = smoothstep(0.4, 0.5, dist) * smoothstep(0.5, 0.4, dist);
					COLOR = vec4(tex.rgb + gold * ring, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(1.0, 0.85, 0.0, 1.0))
		
		Vestige.Rarity.BOSS:
			# Menacing red pulse with distortion
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec2 distorted_uv = UV;
					distorted_uv.x += sin(time * 5.0 + UV.y * 10.0) * 0.02;
					distorted_uv.y += cos(time * 5.0 + UV.x * 10.0) * 0.02;
					vec4 tex = texture(TEXTURE, distorted_uv);
					float pulse = 0.5 + 0.5 * sin(time * 3.0);
					vec3 menace = color.rgb * pulse * 0.7;
					float border = step(0.85, UV.x) + step(0.85, UV.y) + step(0.15, 1.0 - UV.x) + step(0.15, 1.0 - UV.y);
					COLOR = vec4(tex.rgb + menace * border, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(0.9, 0.1, 0.1, 1.0))
		
		Vestige.Rarity.EVENT:
			# Mystical purple particle effect
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec4 tex = texture(TEXTURE, UV);
					float particles = 0.0;
					for(float i = 0.0; i < 4.0; i++) {
						float x = 0.5 + 0.4 * sin(time * 2.0 + i * 1.57);
						float y = 0.5 + 0.4 * cos(time * 2.0 + i * 1.57);
						float dist = distance(UV, vec2(x, y));
						particles += smoothstep(0.1, 0.0, dist);
					}
					vec3 mystic = color.rgb * particles * 0.8;
					COLOR = vec4(tex.rgb + mystic, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(0.7, 0.3, 0.9, 1.0))
		
		Vestige.Rarity.SHOP:
			# Emerald premium smooth effect
			shader_material.shader = Shader.new()
			shader_material.shader.code = """
				shader_type canvas_item;
				uniform float time;
				uniform vec4 color;
				
				void fragment() {
					vec4 tex = texture(TEXTURE, UV);
					float shine = 0.5 + 0.5 * sin(time * 2.5 + UV.x * 8.0);
					vec3 premium = color.rgb * shine * 0.4;
					float dist = distance(UV, vec2(0.5));
					float glow = smoothstep(0.5, 0.0, dist) * 0.3;
					COLOR = vec4(tex.rgb + premium + color.rgb * glow, tex.a);
				}
			"""
			shader_material.set_shader_parameter("color", Color(0.0, 0.9, 0.5, 1.0))
	
	# Store material reference for time updates and initialize time
	shader_material.set_shader_parameter("time", 0.0)
	icon.set_meta("shader_material", shader_material)
	icon.material = shader_material


func _process(delta: float) -> void:
	# Update time parameter for all shader materials
	for child in get_children():
		if child != vestige_icon_template and child.has_meta("shader_material"):
			var shader_mat = child.get_meta("shader_material")
			if shader_mat and shader_mat.shader:
				var current_time = shader_mat.get_shader_parameter("time")
				shader_mat.set_shader_parameter("time", current_time + delta)

func _on_vestige_added(_vestige: Vestige) -> void:
	update_vestige_icons()

func _on_vestige_removed(_vestige: Vestige) -> void:
	update_vestige_icons()

func _on_container_hovered() -> void:
	_show_all_vestiges()

func _on_container_exited() -> void:
	_hide_vestige_popup()

func _show_all_vestiges() -> void:
	if not battler or not vestige_info_popup_scene:
		return
	
	# Clean up existing popups
	for popup in active_vestige_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_vestige_popups.clear()
	
	# Get all vestiges
	var all_vestiges: Array = []
	var global_vestiges = GameState.get_global_vestiges()
	all_vestiges.append_array(global_vestiges)
	
	if "active_vestiges" in battler:
		for vestige in battler.active_vestiges:
			if vestige and vestige not in all_vestiges:
				all_vestiges.append(vestige)
	
	# Only show popups if there are vestiges
	if all_vestiges.is_empty():
		return
	
	# Use the PopUpContainer from the scene if available
	var container = popup_container
	if not container:
		return
	
	# Create popup for each vestige
	for vestige in all_vestiges:
		var popup = vestige_info_popup_scene.instantiate()
		
		# Add popup to the PopUpContainer
		container.add_child(popup)
		
		# Setup popup with vestige info
		if popup.has_method("set_vestige"):
			var stack_count = 1
			if "vestige_stacks" in battler:
				stack_count = battler.vestige_stacks.get(vestige.vestige_id, 1)
			popup.set_vestige(vestige, stack_count)
		
		active_vestige_popups.append(popup)

func _hide_vestige_popup() -> void:
	# Clean up all popups
	for popup in active_vestige_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_vestige_popups.clear()

func _exit_tree():
	# Clean up popups when container is destroyed
	for popup in active_vestige_popups:
		if is_instance_valid(popup):
			popup.queue_free()
	active_vestige_popups.clear()
