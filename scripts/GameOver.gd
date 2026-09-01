extends Control
## Shown on a loss (WorkPhase burnout or a Battle defeat) instead of the old
## instant-permadeath redirect to MainMenu. GameState is NOT reset or deleted
## before this scene loads, so its fields still reflect the failed attempt -
## used here for the recap text - while the last checkpoint (written by
## GameState.advance_stage() on every stage win) remains on disk for
## "Continue from Checkpoint" to load.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const WORK_PHASE := "res://scenes/WorkPhase.tscn"

@onready var subtitle: Label = $Panel/Rows/Subtitle
@onready var continue_button: Button = $Panel/Rows/Buttons/ContinueButton
@onready var new_run_button: Button = $Panel/Rows/Buttons/NewRunButton
@onready var menu_button: Button = $Panel/Rows/Buttons/MenuButton


func _ready() -> void:
	var enemy := GameState.current_enemy()
	subtitle.text = "You reached %s - Stage %d, facing %s - before burning out." % [
		GameState.rank, GameState.stage_index + 1, String(enemy.get("name", "someone")),
	]

	continue_button.disabled = not GameState.has_save()
	continue_button.pressed.connect(_on_continue)
	new_run_button.pressed.connect(_on_new_run)
	menu_button.pressed.connect(_on_menu)


func _on_continue() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file(WORK_PHASE)


func _on_new_run() -> void:
	GameState.start_new_run()
	get_tree().change_scene_to_file(WORK_PHASE)


func _on_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_menu()
