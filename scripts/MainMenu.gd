extends Control

const WORK_PHASE := "res://scenes/WorkPhase.tscn"
const OPTIONS_SCENE := "res://scenes/OptionsMenu.tscn"
const CREDITS_SCENE := "res://scenes/CreditsMenu.tscn"

@onready var button_new_start: TextureButton = $ButtonNewStart
@onready var button_continue: TextureButton = $ButtonContinue
@onready var button_option: TextureButton = $ButtonOption
@onready var button_credit: TextureButton = $ButtonCredit
@onready var progress_label: Label = $ProgressLabel


func _ready() -> void:
	button_continue.disabled = not GameState.has_save()
	_show_progress()

	for b: TextureButton in [button_new_start, button_continue, button_option, button_credit]:
		b.pivot_offset = b.size / 2.0
		b.mouse_entered.connect(_on_button_hover.bind(b))
		b.mouse_exited.connect(_on_button_unhover.bind(b))


## Peek at the save without disturbing the live run state.
func _show_progress() -> void:
	if not GameState.has_save():
		progress_label.text = ""
		return
	var restored := GameState.load_game()
	if not restored:
		progress_label.text = ""
		return
	var enemy := GameState.current_enemy()
	progress_label.text = "Saved run - %s, facing %s (%d/%d)" % [
		GameState.rank, String(enemy["name"]),
		GameState.stage_index + 1, GameData.enemy_count(),
	]


func _on_button_hover(button: TextureButton) -> void:
	if button.disabled:
		return
	create_tween().tween_property(button, "scale", Vector2(1.03, 1.03), 0.08)


func _on_button_unhover(button: TextureButton) -> void:
	create_tween().tween_property(button, "scale", Vector2.ONE, 0.08)


func _on_button_new_start_pressed() -> void:
	GameState.start_new_run()
	get_tree().change_scene_to_file(WORK_PHASE)


func _on_button_continue_pressed() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file(WORK_PHASE)


func _on_button_option_pressed() -> void:
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func _on_button_credit_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)
