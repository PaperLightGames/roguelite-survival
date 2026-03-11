extends CharacterBody3D


const SPEED = 5.0
const SPRINT_SPEED = 7.0
const JUMP_VELOCITY = 4.5


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get input direction relative to the camera's horizontal (Y-axis) rotation.
	# Using only the Y rotation ignores the camera tilt so movement stays on the XZ plane.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var cam_y_rot := get_viewport().get_camera_3d().global_rotation.y
	var cam_basis := Basis(Vector3.UP, cam_y_rot)
	var direction := (cam_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var current_speed := SPRINT_SPEED if Input.is_action_pressed("shift") else SPEED
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
