extends Control
class_name CursorDisplay

# Visual rendering component for custom cursor system
# Handles sprite display, particle effects, and visual feedback

signal cursor_clicked(position: Vector2)
signal cursor_hover_entered(target: Node)
signal cursor_hover_exited(target: Node)

# Cursor state enum (matches CursorManager for compatibility)
enum CursorState {
	DEFAULT = 0,
	ATTACK = 1,
	INTERACT = 2,
	TARGETING = 3,
	PRESS = 4
}

# Current cursor state
var current_state: CursorState = CursorState.DEFAULT
var is_initialized: bool = false

# Scene node references
@onready var cursor_sprite: TextureRect = $CursorSprite
@onready var cursor_juice: CursorJuice = $CursorJuice
@onready var trail_tracker: Node2D = $TrailTracker
@onready var cursor_trail: Line2D = $TrailTracker/CursorTrail



# Cursor textures (can be set in editor or loaded from assets)
@export var cursor_default_texture: Texture2D
@export var cursor_attack_texture: Texture2D
@export var cursor_interact_texture: Texture2D
@export var cursor_targeting_texture: Texture2D
@export var cursor_press_texture: Texture2D

# State-specific colors (configurable in editor)
@export var default_color: Color = Color(1, 1, 1, 1)
@export var attack_color: Color = Color(1, 0.3, 0.3, 1)
@export var interact_color: Color = Color(0.3, 1, 0.5, 1)
@export var targeting_color: Color = Color(0.8, 0.3, 1, 1)
@export var press_color: Color = Color(0.3, 1, 0.5, 1)

# Cursor scale factor
@export var cursor_scale: float = 1.0

# Fallback to file loading if exports not set
var cursor_textures: Dictionary = {}

# Procedural cursor generation
var use_procedural_cursors: bool = true

# State colors dictionary (built from exports)
var state_colors: Dictionary = {}

func _ready() -> void:
	# Prevent double initialization
	if is_initialized:
		return
	
	is_initialized = true
	
	# Build state colors dictionary from exports
	state_colors = {
		CursorState.DEFAULT: default_color,
		CursorState.ATTACK: attack_color,
		CursorState.INTERACT: interact_color,
		CursorState.TARGETING: targeting_color,
		CursorState.PRESS: press_color
	}
	
	# Load or generate cursor textures
	_load_cursor_textures()
	
	# Set initial state
	set_cursor_state(CursorState.DEFAULT)
	
	# Hide default OS cursor using both methods
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	# Make cursor visible
	visible = true
	
	# Set mouse filter to ignore so cursor doesn't block UI detection
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	if cursor_sprite:
		cursor_sprite.visible = true
	
	cursor_sprite.modulate = Color.WHITE
	
	# Setup cursor juice with the sprite and scale factor
	if cursor_juice:
		cursor_juice.setup(cursor_sprite, cursor_scale)
	
	# Apply cursor scale
	if cursor_sprite:
		cursor_sprite.scale = Vector2(cursor_scale, cursor_scale)
	
	# Connect to input signals for click detection
	set_process_input(true)

func _load_cursor_textures() -> void:
	# Load textures from export variables
	if cursor_default_texture:
		cursor_textures[CursorState.DEFAULT] = cursor_default_texture
		use_procedural_cursors = false
	
	if cursor_attack_texture:
		cursor_textures[CursorState.ATTACK] = cursor_attack_texture
		use_procedural_cursors = false
	
	if cursor_interact_texture:
		cursor_textures[CursorState.INTERACT] = cursor_interact_texture
		use_procedural_cursors = false
	
	if cursor_targeting_texture:
		cursor_textures[CursorState.TARGETING] = cursor_targeting_texture
		use_procedural_cursors = false
	
	if cursor_press_texture:
		cursor_textures[CursorState.PRESS] = cursor_press_texture
		use_procedural_cursors = false
	
	# Fallback to file loading if exports not set
	if not cursor_default_texture:
		cursor_textures[CursorState.DEFAULT] = _try_load_texture("res://assets/images/cursors/cursor_default.png")
	if not cursor_attack_texture:
		cursor_textures[CursorState.ATTACK] = _try_load_texture("res://assets/images/cursors/cursor_attack.png")
	if not cursor_interact_texture:
		cursor_textures[CursorState.INTERACT] = _try_load_texture("res://assets/images/cursors/cursor_interact.png")
	if not cursor_targeting_texture:
		cursor_textures[CursorState.TARGETING] = _try_load_texture("res://assets/images/cursors/cursor_targeting.png")
	if not cursor_press_texture:
		cursor_textures[CursorState.PRESS] = _try_load_texture("res://assets/images/cursors/hand_small_closed.png")

func _try_load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			use_procedural_cursors = false
			return texture
	return _generate_procedural_cursor(CursorState.DEFAULT)

func _generate_procedural_cursor(state: CursorState) -> Texture2D:
	# Generate procedural cursor texture based on state
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))  # Transparent background
	
	var color = state_colors.get(state, default_color)
	
	match state:
		CursorState.DEFAULT:
			# Simple arrow cursor
			_draw_arrow_cursor(image, color)
		CursorState.ATTACK:
			# Crosshair cursor
			_draw_crosshair_cursor(image, color)
		CursorState.INTERACT, CursorState.PRESS:
			# Hand pointer cursor
			_draw_hand_cursor(image, color)
		CursorState.TARGETING:
			# Targeting reticle cursor
			_draw_reticle_cursor(image, color)
	
	var texture = ImageTexture.create_from_image(image)
	return texture

func _draw_arrow_cursor(image: Image, color: Color) -> void:
	# Draw simple arrow shape
	for y in range(32):
		for x in range(32):
			# Simple arrow pointing up-right
			if y < 20 and x < 20 and (x + y < 20 or (y > 15 and x < 8)):
				image.set_pixel(x, y, color)

func _draw_crosshair_cursor(image: Image, color: Color) -> void:
	# Draw crosshair shape
	var center = 16
	for i in range(32):
		# Horizontal line
		if i != center:
			image.set_pixel(i, center, color)
		# Vertical line
		if i != center:
			image.set_pixel(center, i, color)
	
	# Center circle (simplified diamond shape for performance)
	for y in range(12, 20):
		for x in range(12, 20):
			var dx = abs(x - 16)
			var dy = abs(y - 16)
			if dx + dy <= 3 and dx + dy >= 1:
				image.set_pixel(x, y, color)

func _draw_hand_cursor(image: Image, color: Color) -> void:
	# Draw simple hand pointer shape
	for y in range(32):
		for x in range(32):
			# Simple hand shape
			if y < 18 and x < 18 and (x + y < 18 or (y > 12 and x < 6)):
				image.set_pixel(x, y, color)

func _draw_reticle_cursor(image: Image, color: Color) -> void:
	# Draw targeting reticle shape
	var center = 16
	
	# Outer ring (simplified square ring for better performance)
	for y in range(6, 26):
		for x in range(6, 26):
			var dx = abs(x - 16)
			var dy = abs(y - 16)
			# Draw ring corners
			if (dx >= 8 and dx <= 10 and dy >= 8 and dy <= 10) or (dx + dy >= 14 and dx + dy <= 16):
				image.set_pixel(x, y, color)
	
	# Inner cross
	for i in range(8, 24):
		if i != center:
			image.set_pixel(i, center, color)
		if i != center:
			image.set_pixel(center, i, color)
	
	# Center dot
	image.set_pixel(center, center, color)

func set_cursor_state(new_state: CursorState) -> void:
	if current_state == new_state:
		return
	
	var previous_state = current_state
	current_state = new_state
	
	# Update cursor texture - use exports directly
	var texture_to_set = null
	
	match new_state:
		CursorState.DEFAULT:
			texture_to_set = cursor_default_texture
		CursorState.ATTACK:
			texture_to_set = cursor_attack_texture
		CursorState.INTERACT:
			texture_to_set = cursor_interact_texture
		CursorState.TARGETING:
			texture_to_set = cursor_targeting_texture
		CursorState.PRESS:
			texture_to_set = cursor_press_texture
	
	if texture_to_set:
		cursor_sprite.texture = texture_to_set
	else:
		# Fallback to dictionary
		if cursor_textures.has(new_state) and cursor_textures[new_state]:
			texture_to_set = cursor_textures[new_state]
			cursor_sprite.texture = texture_to_set
		else:
			cursor_sprite.texture = _generate_procedural_cursor(new_state)
	
	# Update color
	var new_color = state_colors.get(new_state, default_color)
	cursor_sprite.modulate = new_color
	
	# Update trail color if it exists
	if has_node("TrailTracker/CursorTrail"):
		cursor_trail.default_color = Color(new_color.r, new_color.g, new_color.b, 0.5)
	
	# Animate state transition
	if cursor_juice:
		cursor_juice.animate_state_transition(Vector2.ONE * cursor_scale, Vector2.ONE * cursor_scale, 1.0)

func get_cursor_state() -> CursorState:
	return current_state

func _input(event: InputEvent) -> void:
	# Handle mouse input for cursor effects
	if event is InputEventMouseMotion:
		# Update cursor position
		global_position = event.position
	
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Switch to PRESS state if currently in INTERACT state
			if current_state == CursorState.INTERACT:
				set_cursor_state(CursorState.PRESS)
			_on_cursor_clicked(event.position)
		else:
			# Release back to INTERACT if we were in PRESS
			if current_state == CursorState.PRESS:
				set_cursor_state(CursorState.INTERACT)

func _process(_delta: float) -> void:
	# Ensure cursor follows mouse position every frame
	var mouse_pos = get_viewport().get_mouse_position()
	global_position = mouse_pos
	
	# Update trail tracker position
	if has_node("TrailTracker"):
		trail_tracker.global_position = mouse_pos
	
	# Ensure OS cursor stays hidden
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _on_cursor_clicked(position: Vector2) -> void:
	# Trigger click animation
	if cursor_juice:
		cursor_juice.animate_click()
		await get_tree().create_timer(0.1).timeout
		cursor_juice.animate_click_release()
	
	# Emit signal
	cursor_clicked.emit(position)

func set_custom_texture(state: CursorState, texture: Texture2D) -> void:
	cursor_textures[state] = texture
	
	# Also update the corresponding export variable
	match state:
		CursorState.DEFAULT:
			cursor_default_texture = texture
		CursorState.ATTACK:
			cursor_attack_texture = texture
		CursorState.INTERACT:
			cursor_interact_texture = texture
		CursorState.TARGETING:
			cursor_targeting_texture = texture
		CursorState.PRESS:
			cursor_press_texture = texture
	
	if current_state == state:
		cursor_sprite.texture = texture

func set_state_color(state: CursorState, color: Color) -> void:
	state_colors[state] = color
	
	# Also update the corresponding export variable
	match state:
		CursorState.DEFAULT:
			default_color = color
		CursorState.ATTACK:
			attack_color = color
		CursorState.INTERACT:
			interact_color = color
		CursorState.TARGETING:
			targeting_color = color
		CursorState.PRESS:
			press_color = color
	
	if current_state == state:
		cursor_sprite.modulate = color
