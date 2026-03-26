extends Camera3D

## How quickly the camera catches up to the player when following.
@export var follow_speed: float = 5.0
## Duration of the zoom and return-to-center transitions.
@export var transition_duration: float = 0.8

const SIZE_DEFAULT: float = 82.0 # 82
const SIZE_ZOOM: float = 45.0 # Default: 47

var _following: bool = false
var _initial_center: Vector3       # world point the camera orbits when static
var _camera_offset: Vector3        # initial vector from center → camera

var _zoom_tween: Tween


func _ready() -> void:
	# Detach from parent transform so the camera stays put by default.
	top_level = true
	_initial_center = get_parent().global_position
	_camera_offset = global_position - _initial_center


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("zoom_cam"):
		_toggle_zoom_cam()

	# Pick the orbit center: player when following, original spot when static.
	var center = get_parent().global_position if _following else _initial_center
	var target_pos = center + _camera_offset

	# Smooth movement — handles follow and return-to-center.
	global_position = global_position.lerp(target_pos, follow_speed * delta)


func _toggle_zoom_cam() -> void:
	_following = !_following

	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	if _following:
		_zoom_tween.tween_property(self, "size", SIZE_ZOOM, transition_duration)
	else:
		_zoom_tween.tween_property(self, "size", SIZE_DEFAULT, transition_duration)
