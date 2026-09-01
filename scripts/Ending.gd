extends Control
## Final cutscene after the CEO is defeated. The scenery pulls back while the
## protagonist's conclusion appears one thought at a time.

const MAIN_MENU := "res://scenes/MainMenu.tscn"

@onready var background: TextureRect = $SceneFrame/Background
@onready var opening_line: Label = $Narration/OpeningLine
@onready var closing_line: Label = $Narration/ClosingLine
@onready var continue_hint: Label = $ContinueHint

var _can_leave := false


func _ready() -> void:
	GameState.delete_save()
	background.pivot_offset = background.size * 0.5
	background.scale = Vector2(1.30, 1.30)
	opening_line.modulate.a = 0.0
	closing_line.modulate.a = 0.0
	continue_hint.modulate.a = 0.0
	_play_cutscene()


func _play_cutscene() -> void:
	var camera_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	camera_tween.tween_property(background, "scale", Vector2.ONE, 10.5)

	var narration_tween := create_tween()
	narration_tween.tween_interval(0.7)
	narration_tween.tween_property(opening_line, "modulate:a", 1.0, 1.3)
	narration_tween.tween_interval(3.5)
	narration_tween.tween_property(closing_line, "modulate:a", 1.0, 1.3)
	narration_tween.tween_interval(2.4)
	narration_tween.tween_property(continue_hint, "modulate:a", 1.0, 0.6)
	narration_tween.tween_callback(func() -> void: _can_leave = true)


func _leave() -> void:
	if not _can_leave:
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_leave()
