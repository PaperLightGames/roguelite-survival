extends Marker3D

@export var rotation_step: float = 45.0
@export var rotation_duration: float = 0.25

var _tween: Tween
var _target_y: float = 0.0


func _ready() -> void:
	_target_y = rotation_degrees.y


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("cam_left"):
		_rotate_to(_target_y + rotation_step)

	if Input.is_action_just_pressed("cam_right"):
		_rotate_to(_target_y - rotation_step)


func _rotate_to(target_y: float) -> void:
	_target_y = target_y
	if _tween:
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "rotation_degrees", Vector3(rotation_degrees.x, _target_y, rotation_degrees.z), rotation_duration)
