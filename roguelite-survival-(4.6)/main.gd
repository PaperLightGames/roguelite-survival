extends Node


@onready var scene_to_load: PackedScene = preload("res://levels/test_world.tscn")

func _ready() -> void:
	get_tree().call_deferred("change_scene_to_packed", scene_to_load)
	print("[Init] Loaded scene: %s" % scene_to_load)
	
