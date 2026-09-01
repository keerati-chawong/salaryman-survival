extends Control

const MAIN_MENU := "res://scenes/MainMenu.tscn"


func _ready() -> void:
	var back := get_node_or_null("BackButton")
	if back and back.self_modulate.a < 0.01:
		back.mouse_entered.connect(_tween_alpha.bind(back, 0.14))
		back.mouse_exited.connect(_tween_alpha.bind(back, 0.0))


func _tween_alpha(node: Control, a: float) -> void:
	create_tween().tween_property(node, "self_modulate:a", a, 0.1)


func _on_back_pressed() -> void:
	SoundManager.play_sfx("click")
	get_tree().change_scene_to_file(MAIN_MENU)
