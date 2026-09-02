extends Control
## Shown between fights. Reports the promotion and previews the next opponent's
## weakness table, or rolls the ending once the CEO is beaten.

const WORK_PHASE := "res://scenes/WorkPhase.tscn"
const MAIN_MENU := "res://scenes/MainMenu.tscn"
const SHOP := "res://scenes/Shop.tscn"

@onready var title: Label = $Panel/Rows/Title
@onready var subtitle: Label = $Panel/Rows/Subtitle
@onready var next_box: VBoxContainer = $Panel/Rows/NextBox
@onready var next_title: Label = $Panel/Rows/NextBox/NextTitle
@onready var next_intro: Label = $Panel/Rows/NextBox/NextIntro
@onready var chart: GridContainer = $Panel/Rows/NextBox/Chart
@onready var continue_button: Button = $Panel/Rows/Buttons/ContinueButton
@onready var shop_button: Button = $"Panel/Rows/Buttons/Go_to_shop"
@onready var menu_button: Button = $Panel/Rows/Buttons/MenuButton

var _finished := false


func _ready() -> void:
	## Otherwise this recap screen just keeps whatever track Battle left
	## playing, which is the tense combat theme - swap to the calmer menu
	## track now that the fight is actually over.
	SoundManager.play_music("menu")

	# advance_stage() already ran, so stage_index points at the next opponent.
	_finished = GameState.stage_index >= GameData.enemy_count()

	if _finished:
		_show_ending()
	else:
		_show_promotion()

	continue_button.pressed.connect(_on_continue)
	shop_button.pressed.connect(_on_shop)
	menu_button.pressed.connect(_on_menu)


func _show_promotion() -> void:
	title.text = "PROMOTED"
	subtitle.text = "You are now %s. Someone upstairs already resents it." % GameState.rank

	var enemy := GameState.current_enemy()
	next_title.text = "Next: %s  (%s)" % [String(enemy["name"]), String(enemy["role"])]
	next_intro.text = String(enemy["intro"])

	var mult: Dictionary = enemy["mult"]
	for word: Dictionary in GameData.WORDS:
		var id := String(word["id"])
		var value := float(mult.get(id, 1.0))

		var name_label := Label.new()
		name_label.text = String(word["name"])
		name_label.add_theme_color_override("font_color", word["color"])
		chart.add_child(name_label)

		var verdict := Label.new()
		var text := GameData.effectiveness_label(value)
		verdict.text = text if text != "" else "Neutral"
		verdict.add_theme_color_override("font_color", GameData.effectiveness_color(value))
		verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chart.add_child(verdict)

	continue_button.text = "Start next shift"


func _show_ending() -> void:
	title.text = "YOU WIN"
	subtitle.text = "The CEO has no comeback. You walk out as %s - and hand in your notice anyway." % GameState.rank
	next_box.visible = false
	continue_button.text = "New run"
	GameState.delete_save()


func _on_continue() -> void:
	SoundManager.play_sfx("click")
	if _finished:
		GameState.start_new_run()
	get_tree().change_scene_to_file(WORK_PHASE)

func _on_shop() -> void:
	SoundManager.play_sfx("click")
	get_tree().change_scene_to_file(SHOP)

func _on_menu() -> void:
	SoundManager.play_sfx("click")
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_menu()
