extends Control

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const SAVE_PATH := "user://settings.cfg"

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
]

@onready var tab_display: Button = $TabDisplay
@onready var tab_audio: Button = $TabAudio
@onready var tab_controls: Button = $TabControls
@onready var tab_gameplay: Button = $TabGameplay
@onready var tab_language: Button = $TabLanguage
@onready var tab_others: Button = $TabOthers

@onready var resolution_option: OptionButton = $ResolutionOption
@onready var windowmode_option: OptionButton = $WindowModeOption
@onready var brightness_slider: HSlider = $BrightnessSlider
@onready var brightness_label: Label = $BrightnessLabel

@onready var master_slider: HSlider = $MasterSlider
@onready var master_label: Label = $MasterLabel
@onready var music_slider: HSlider = $MusicSlider
@onready var music_label: Label = $MusicLabel
@onready var sfx_slider: HSlider = $SfxSlider
@onready var sfx_label: Label = $SfxLabel

@onready var screenshake_prev: Button = $ScreenShakePrev
@onready var screenshake_next: Button = $ScreenShakeNext
@onready var screenshake_label: Label = $ScreenShakeLabel
@onready var showdmg_prev: Button = $ShowDmgPrev
@onready var showdmg_next: Button = $ShowDmgNext
@onready var showdmg_label: Label = $ShowDmgLabel
@onready var tutorial_prev: Button = $TutorialPrev
@onready var tutorial_next: Button = $TutorialNext
@onready var tutorial_label: Label = $TutorialLabel

@onready var language_option: OptionButton = $LanguageOption
@onready var uiscale_slider: HSlider = $UiScaleSlider
@onready var uiscale_label: Label = $UiScaleLabel

@onready var reset_btn: Button = $ResetButton
@onready var apply_btn: Button = $ApplyButton
@onready var back_btn: Button = $BackButton

@onready var brightness_overlay: ColorRect = $BrightnessOverlay
@onready var toast: Label = $Toast

var screenshake := true
var show_damage := true
var tutorial_tips := true


func _ready() -> void:
	resolution_option.clear()
	for r: Vector2i in RESOLUTIONS:
		resolution_option.add_item("%d x %d" % [r.x, r.y])

	windowmode_option.clear()
	windowmode_option.add_item("Fullscreen")
	windowmode_option.add_item("Windowed")
	windowmode_option.add_item("Borderless")

	language_option.clear()
	language_option.add_item("English")
	language_option.add_item("ไทย")

	toast.visible = false

	for tab: Button in [tab_display, tab_audio, tab_controls, tab_gameplay, tab_language, tab_others]:
		tab.self_modulate = Color(1, 1, 1, 0)
		tab.mouse_entered.connect(_hover_overlay.bind(tab, true))
		tab.mouse_exited.connect(_hover_overlay.bind(tab, false))

	for arrow: Button in [screenshake_prev, screenshake_next, showdmg_prev, showdmg_next, tutorial_prev, tutorial_next]:
		arrow.self_modulate = Color(1, 1, 1, 0)
		arrow.mouse_entered.connect(_hover_overlay.bind(arrow, true))
		arrow.mouse_exited.connect(_hover_overlay.bind(arrow, false))

	for btn: Button in [reset_btn, apply_btn, back_btn]:
		btn.self_modulate = Color(1, 1, 1, 0)
		btn.mouse_entered.connect(_hover_overlay.bind(btn, true))
		btn.mouse_exited.connect(_hover_overlay.bind(btn, false))

	_load_settings()
	_sync_all_labels()


func _hover_overlay(b: Control, enter: bool) -> void:
	create_tween().tween_property(b, "self_modulate:a", 0.14 if enter else 0.0, 0.1)


func _reset_defaults() -> void:
	resolution_option.selected = 0
	windowmode_option.selected = 0
	brightness_slider.value = 75
	master_slider.value = 80
	music_slider.value = 60
	sfx_slider.value = 80
	screenshake = true
	show_damage = true
	tutorial_tips = true
	language_option.selected = 0
	uiscale_slider.value = 100


func _sync_all_labels() -> void:
	_on_brightness_changed(brightness_slider.value)
	_on_master_changed(master_slider.value)
	_on_music_changed(music_slider.value)
	_on_sfx_changed(sfx_slider.value)
	_on_uiscale_changed(uiscale_slider.value)
	_update_toggle_labels()


func _update_toggle_labels() -> void:
	screenshake_label.text = "ON" if screenshake else "OFF"
	showdmg_label.text = "ON" if show_damage else "OFF"
	tutorial_label.text = "ON" if tutorial_tips else "OFF"


func _on_brightness_changed(v: float) -> void:
	brightness_label.text = "%d%%" % int(v)
	brightness_overlay.color.a = clamp((100.0 - v) / 100.0 * 0.6, 0.0, 0.6)


func _on_master_changed(v: float) -> void:
	master_label.text = "%d%%" % int(v)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(max(v / 100.0, 0.0001)))


func _on_music_changed(v: float) -> void:
	music_label.text = "%d%%" % int(v)


func _on_sfx_changed(v: float) -> void:
	sfx_label.text = "%d%%" % int(v)


func _on_uiscale_changed(v: float) -> void:
	uiscale_label.text = "%d%%" % int(v)
	get_window().content_scale_factor = v / 100.0


func _on_resolution_selected(_idx: int) -> void:
	_apply_window()


func _on_windowmode_selected(_idx: int) -> void:
	_apply_window()


func _apply_window() -> void:
	var res: Vector2i = RESOLUTIONS[resolution_option.selected]
	match windowmode_option.selected:
		0:
			get_window().mode = Window.MODE_FULLSCREEN
		1:
			get_window().mode = Window.MODE_WINDOWED
			get_window().borderless = false
			get_window().size = res
		2:
			get_window().mode = Window.MODE_WINDOWED
			get_window().borderless = true
			get_window().size = res


func _on_screenshake_toggle() -> void:
	screenshake = not screenshake
	_update_toggle_labels()


func _on_showdmg_toggle() -> void:
	show_damage = not show_damage
	_update_toggle_labels()


func _on_tutorial_toggle() -> void:
	tutorial_tips = not tutorial_tips
	_update_toggle_labels()


func _on_tab_display_pressed() -> void:
	pass


func _on_tab_other_pressed(tab_name: String) -> void:
	_show_toast(tab_name + " settings coming soon")


func _show_toast(msg: String) -> void:
	toast.text = msg
	toast.visible = true
	toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(toast, "modulate:a", 0.0, 0.5)
	t.tween_callback(func() -> void: toast.visible = false)


func _on_reset_pressed() -> void:
	_reset_defaults()
	_sync_all_labels()
	_apply_window()
	_show_toast("Reset to default")


func _on_apply_pressed() -> void:
	_apply_window()
	_save_settings()
	_show_toast("Settings applied!")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution", resolution_option.selected)
	cfg.set_value("display", "window_mode", windowmode_option.selected)
	cfg.set_value("display", "brightness", brightness_slider.value)
	cfg.set_value("audio", "master", master_slider.value)
	cfg.set_value("audio", "music", music_slider.value)
	cfg.set_value("audio", "sfx", sfx_slider.value)
	cfg.set_value("others", "screenshake", screenshake)
	cfg.set_value("others", "show_damage", show_damage)
	cfg.set_value("others", "tutorial_tips", tutorial_tips)
	cfg.set_value("others", "language", language_option.selected)
	cfg.set_value("others", "ui_scale", uiscale_slider.value)
	cfg.save(SAVE_PATH)


func _load_settings() -> void:
	_reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		resolution_option.selected = cfg.get_value("display", "resolution", 0)
		windowmode_option.selected = cfg.get_value("display", "window_mode", 0)
		brightness_slider.value = cfg.get_value("display", "brightness", 75)
		master_slider.value = cfg.get_value("audio", "master", 80)
		music_slider.value = cfg.get_value("audio", "music", 60)
		sfx_slider.value = cfg.get_value("audio", "sfx", 80)
		screenshake = cfg.get_value("others", "screenshake", true)
		show_damage = cfg.get_value("others", "show_damage", true)
		tutorial_tips = cfg.get_value("others", "tutorial_tips", true)
		language_option.selected = cfg.get_value("others", "language", 0)
		uiscale_slider.value = cfg.get_value("others", "ui_scale", 100)
