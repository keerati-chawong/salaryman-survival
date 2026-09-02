extends Control

## A short, skippable prologue shown before a fresh run begins.
const WORK_PHASE := "res://scenes/WorkPhase.tscn"

@onready var graduation: TextureRect = $SceneFrame/Graduation
@onready var job_offer: TextureRect = $SceneFrame/JobOffer
@onready var first_jobber: TextureRect = $SceneFrame/FirstJobber
@onready var narration: Label = $NarrationPanel/Narration
@onready var chapter: Label = $NarrationPanel/Chapter
@onready var continue_hint: Label = $ContinueHint

## Input is deliberately locked until all three story shots have played.
var can_continue := false
var is_leaving := false


func _ready() -> void:
	SoundManager.play_music("intro")
	graduation.modulate.a = 1.0
	job_offer.modulate.a = 0.0
	first_jobber.modulate.a = 0.0
	narration.modulate.a = 0.0
	chapter.modulate.a = 0.0
	continue_hint.modulate.a = 0.0
	_play_timeline()


func _play_timeline() -> void:
	await _show_narration(
		"PROLOGUE — DAY ONE",
		"I had only just graduated.\nThen I landed a job I never thought I could get."
	)
	await get_tree().create_timer(4.0).timeout

	await _fade_to(job_offer)
	await _show_narration(
		"AN UNEXPECTED OFFER",
		"Back then, I thought\nthis was the start of something beautiful."
	)
	await get_tree().create_timer(4.0).timeout

	await _fade_to(first_jobber)
	await _show_narration(
		"THE FIRST JOBBER REALITY",
		"But once I started working, I found the truth:\nit was nothing like I imagined.\nBeing a first jobber..."
	)

	## The final image deliberately keeps moving after the words appear.
	var zoom := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	zoom.tween_property(first_jobber, "scale", Vector2(1.48, 1.48), 8.0)
	await zoom.finished
	can_continue = true
	continue_hint.text = "Click or press Enter to start the first workday"
	var hint_tween := create_tween()
	hint_tween.tween_property(continue_hint, "modulate:a", 0.92, 0.25)


func _show_narration(new_chapter: String, new_text: String) -> void:
	chapter.text = new_chapter
	narration.text = new_text
	var tween := create_tween().set_parallel(true)
	tween.tween_property(chapter, "modulate:a", 1.0, 0.45)
	tween.tween_property(narration, "modulate:a", 1.0, 0.45)
	await tween.finished


func _fade_to(next_scene: TextureRect) -> void:
	var out_tween := create_tween().set_parallel(true)
	out_tween.tween_property(chapter, "modulate:a", 0.0, 0.25)
	out_tween.tween_property(narration, "modulate:a", 0.0, 0.25)
	await out_tween.finished

	var image_tween := create_tween().set_parallel(true)
	for scene: TextureRect in [graduation, job_offer, first_jobber]:
		image_tween.tween_property(scene, "modulate:a", 1.0 if scene == next_scene else 0.0, 0.75)
	await image_tween.finished


## Mouse input is received by the root Control itself.  Deferring the scene
## change keeps Godot from freeing this Control while it is dispatching a click.
func _on_gui_input(event: InputEvent) -> void:
	if not can_continue or is_leaving:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_queue_start_workday()
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and can_continue and not is_leaving and event.is_action_pressed("ui_accept"):
		_queue_start_workday()
		get_viewport().set_input_as_handled()


func _queue_start_workday() -> void:
	is_leaving = true
	call_deferred("_start_workday")


func _start_workday() -> void:
	var error := get_tree().change_scene_to_file(WORK_PHASE)
	if error != OK:
		is_leaving = false
		push_error("Could not load the first workday scene: %s" % error)
