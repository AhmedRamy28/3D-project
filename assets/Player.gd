extends CharacterBody3D

# --- Movement Variables ---
@export var SPEED = 5.0
@export var SPRINT_SPEED = 9.0
@export var JUMP_VELOCITY = 4.5
@export var AIR_JUMP_VELOCITY = 3.5
@export var MAX_JUMPS = 2
var jump_count = 0

# --- Camera & Feel ---
@export var Sensitivity = 0.003
@onready var head = $Head
@onready var camera = $Head/Camera3D

# --- Head Shake (Bobbing) ---
const Shake_freq = 2.0
const Shake_amp = 0.08
var Shake_Time = 0.0

# --- FOV Logic ---
@export var Base_FOV = 75.0
@export var FOV_Multiplier = 1.5

# --- Coyote Time ---
@export var coyote_time = 0.15
var was_on_floor: bool = false
var can_coyote_jump: bool = false

# --- Wall Run Variables ---
@export var wall_jump_force = 6.0
@export var wall_run_gravity_mult = 0.15 
var is_wall_running : bool = false
@onready var left_ray = find_child("RayCastLeft")
@onready var right_ray = find_child("RayCastRight")

# --- Jump Buffering Variables --
@export var jump_buffer_time: float = 0.1
var jump_pressed = false
var jump_buffer_timer : Timer

var paused : bool = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Required to keep movement working while physics pauses
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	#Jump Buffering 
	jump_buffer_timer = Timer.new()
	jump_buffer_timer.one_shot = true
	jump_buffer_timer.timeout.connect(func(): jump_pressed = false)
	add_child(jump_buffer_timer)

func _unhandled_input(event):
	# Mouse Look
	if event is InputEventMouseMotion and not paused:
		head.rotate_y(-event.relative.x * Sensitivity)
		camera.rotate_x(-event.relative.y * Sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	
	# Pause Logic
	if event.is_action_pressed("Exit"):
		paused = !paused
		get_tree().paused = paused
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED)

func get_head_shake_pos(time):
	var pos = Vector3.ZERO
	pos.y = sin(time * Shake_freq) * Shake_amp
	pos.x = cos(time * Shake_freq / 2) * Shake_amp
	return pos

func get_side():
	if not left_ray or not right_ray: return "none"
	left_ray.force_raycast_update()
	right_ray.force_raycast_update()
	if left_ray.is_colliding(): return "left"
	if right_ray.is_colliding(): return "right"
	return "none"

func wall_run_logic(delta):
	var side = get_side()
	var moving_forward = Input.is_action_pressed("move_up")
	
	if not is_on_floor() and side != "none" and moving_forward:
		is_wall_running = true
		
		# Slide effect: slows falling
		velocity.y = lerp(velocity.y, 0.0, delta * 10.0)
		
		# Camera Tilt
		var target_tilt = 0.15 if side == "left" else -0.15
		camera.rotation.z = lerp_angle(camera.rotation.z, target_tilt, delta * 5.0)
		
		# Wall Jump
		if Input.is_action_just_pressed("jump"):
			var normal = left_ray.get_collision_normal() if side == "left" else right_ray.get_collision_normal()
			# Direction: Normal (away) + Up + Forward
			var jump_dir = (normal + Vector3.UP + head.global_transform.basis.z * -0.5).normalized()
			velocity = jump_dir * wall_jump_force
			is_wall_running = false
	else:
		is_wall_running = false
		camera.rotation.z = lerp_angle(camera.rotation.z, 0.0, delta * 5.0)

func _physics_process(delta):
	# 1. Coyote Time Logic
	if is_on_floor():
		can_coyote_jump = true
		jump_count = 0
	elif was_on_floor and not is_wall_running:
		# Start timer when leaving a ledge
		get_tree().create_timer(coyote_time).timeout.connect(func(): can_coyote_jump = false)

	# 2. Gravity
	if not is_on_floor():
		if is_wall_running:
			velocity.y -= 2.0 * delta # Slight manual sink for "manual" feel
		else:
			velocity += get_gravity() * delta
	else:
		if jump_pressed:
			velocity.y = JUMP_VELOCITY
			jump_pressed = false
			jump_buffer_timer.stop()
			jump_count = 1
	# 3. Jumping Logic
	if Input.is_action_just_pressed("jump"):
		if is_on_floor() or can_coyote_jump:
			velocity.y = JUMP_VELOCITY
			jump_count += 1
			can_coyote_jump = false
		elif jump_count < MAX_JUMPS: # Air Jump / Double Jump
			velocity.y = AIR_JUMP_VELOCITY
			jump_count += 1
		else: # Jump Buffering 
			jump_pressed = true
			jump_buffer_timer.start(jump_buffer_time)

	# 4. Movement Calculation
	var is_sprinting = Input.is_action_pressed("Sprint")
	var current_speed = SPRINT_SPEED if is_sprinting else SPEED
	
	var input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
			velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
	else:
		# Air control (smooth lerp so you don't snap directions in mid-air)
		velocity.x = lerp(velocity.x, direction.x * current_speed, delta * 3.0)
		velocity.z = lerp(velocity.z, direction.z * current_speed, delta * 3.0)

	# 5. Execute Mechanics
	wall_run_logic(delta)
	was_on_floor = is_on_floor()
	move_and_slide()

	# 6. Visuals (Headshake & FOV)
	# Only bob the head if on floor and moving
	if is_on_floor() and direction:
		Shake_Time += delta * velocity.length()
		camera.transform.origin = get_head_shake_pos(Shake_Time)
	else:
		camera.transform.origin = camera.transform.origin.lerp(Vector3.ZERO, delta * 10.0)
	
	# Dynamic FOV based on speed
	var speed_percent = clamp(velocity.length() / SPRINT_SPEED, 0.5, 2.0)
	var target_fov = Base_FOV + (FOV_Multiplier * speed_percent)
	camera.fov = lerp(camera.fov, target_fov, delta * 8.0)
