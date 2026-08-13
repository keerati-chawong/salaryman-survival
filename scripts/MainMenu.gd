extends Control

const GAME_SCENE := "res://scenes/CombatDemo.tscn"
const OPTIONS_SCENE := "res://scenes/OptionsMenu.tscn"
const CREDITS_SCENE := "res://scenes/CreditsMenu.tscn"
const SAVE_PATH := "user://save.dat"

@onready var button_new_start: TextureButton = $ButtonNewStart
@onready var button_continue: TextureButton = $ButtonContinue
@onready var button_option: TextureButton = $ButtonOption
@onready var button_credit: TextureButton = $ButtonCredit


func _ready() -> void:
	button_continue.disabled = not FileAccess.file_exists(SAVE_PATH)

	for b: TextureButton in [button_new_start, button_continue, button_option, button_credit]:
		b.pivot_offset = b.size / 2.0
		b.mouse_entered.connect(_on_button_hover.bind(b))
		b.mouse_exited.connect(_on_button_unhover.bind(b))


func _on_button_hover(button: TextureButton) -> void:
	if button.disabled:
		return
	create_tween().tween_property(button, "scale", Vector2(1.03, 1.03), 0.08)


func _on_button_unhover(button: TextureButton) -> void:
	create_tween().tween_property(button, "scale", Vector2.ONE, 0.08)


func _on_button_new_start_pressed() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_button_continue_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_button_option_pressed() -> void:
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func _on_button_credit_pressed() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)
