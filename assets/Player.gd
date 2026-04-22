extends CharacterBody3D

@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var AIR_JUMP = 3.5

#Multiple jumps
@export var MAX_JUMPS = 1  #jumps in air
var jump_count = 0.0

@export var Sensitivity = 0.03
@onready var head = $Head
@onready var camera = $Head/Camera3D

#head shake Variables
const Shake_freq = 2.0
const Shake_amp = 0.08
var Shake_Time = 0.0

#Field of view Variables
@export var Current_FOV = 75.0
const FOV_Change = 1.5
 

#Coyote Variables
@export var coyote_time = .5
var was_on_floor: bool = false
var can_coyote_jump: bool = false

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	process_mode = Node.PROCESS_MODE_ALWAYS
	

var paused : bool = false	
func _unhandled_input(event):
	#makes it possible to get the mouse movement
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * Sensitivity)
		camera.rotate_x(-event.relative.y * Sensitivity)
		camera.rotation.x = clamp (camera.rotation.x , deg_to_rad(-40), deg_to_rad(60))
	
	# can pause the game and show the cursor
	if event.is_action_pressed("Exit"):
		paused = !paused
		get_tree().paused = paused
		
		if paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			

func headShake(time):
	var current_position = Vector3.ZERO
	current_position.y = sin(time * Shake_freq) * Shake_amp
	current_position.x = cos(time * Shake_freq / 2) * Shake_amp
	return current_position



func _physics_process(delta: float) -> void:
	was_on_floor = is_on_floor()
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
		#coyote
		if was_on_floor and velocity.y >= 0:
			can_coyote_jump = true
			get_tree().create_timer(coyote_time).timeout.connect(func(): can_coyote_jump = false)


	var jump = Input.is_action_just_pressed("jump")
	var SPRINT = Input.is_action_pressed("Sprint")
	
	
	if jump:
		if  is_on_floor() or can_coyote_jump:
			velocity.y = JUMP_VELOCITY
			jump_count += 1
			can_coyote_jump = false
		
		elif not is_on_floor() and jump_count < MAX_JUMPS:
			velocity.y = AIR_JUMP
			jump_count += 1
	if  is_on_floor():
		jump_count = 0
 		
	
	if SPRINT:
		SPEED = 9.0
	else:
		SPEED = 5.0
		
	# Get the input direction and handle the movement/deceleration.
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction : Vector3 = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if is_on_floor():
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			#adds inertia after leaving the controls
			var inertia_percentage = delta * 10
			velocity.x = lerp(velocity.x , direction.x * SPEED, inertia_percentage)
			velocity.z = lerp(velocity.z , direction.z * SPEED, inertia_percentage)
	else:
		#adds inertia after leaving the controls
		var air_inertia_percentage = 7	 # keep in mind delta is 0.05 
		velocity.x = lerp(velocity.x , direction.x * SPEED, delta * air_inertia_percentage)
		velocity.z = lerp(velocity.z , direction.z * SPEED, delta * air_inertia_percentage)
	
	#head shake
	Shake_Time += delta * velocity.length() * float(is_on_floor())
	camera.transform.origin = headShake(Shake_Time)
	move_and_slide()
	
	#controls the FOV each tick
	var Area_Covered_Percentage = delta * 6.0
	var velocity_clamped = clamp(velocity.length(), 0.5, SPEED* 2 )
	var Variable_FOV = Current_FOV + FOV_Change * velocity_clamped
	camera.fov = lerp(camera.fov , Variable_FOV, Area_Covered_Percentage)
	
