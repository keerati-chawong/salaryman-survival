extends Node
## Global settings singleton. Owns the audio buses, the brightness overlay and
## the shared theme's font scale, so every scene picks up option changes.

const SAVE_PATH := "user://settings.cfg"
const SAVE_GAME_PATH := "user://save.dat"
const THEME: Theme = preload("res://theme/ui_theme.tres")

const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1366, 768),
	Vector2i(1280, 720),
]

## Brightness is neutral at this value so the art's default of 75% looks correct.
const BRIGHTNESS_NEUTRAL := 75.0

## Base font sizes; UI scale multiplies these. Keys are theme types/variations.
const BASE_FONT_SIZES := {
	"Label": 18,
	"Button": 18,
	"OptionButton": 18,
	"PopupMenu": 18,
	"CheckButton": 18,
	"SmallLabel": 15,
	"StatLabel": 22,
	"BigStatLabel": 26,
	"HeaderLabel": 28,
}

signal changed

var resolution_index := 0
## 0 = fullscreen, 1 = windowed, 2 = borderless. Windowed by default so the
## prototype never traps the player in an exclusive-fullscreen window.
var window_mode := 1
var brightness := 75.0
var master_volume := 80.0
var music_volume := 60.0
var sfx_volume := 80.0
var screen_shake := true
var show_damage := true
var tutorial_tips := true
var language_index := 0
var difficulty := 1
var ui_scale := 100.0

var _tint: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_ensure_theme_variations()
	_build_tint_layer()
	load_settings()
	apply_all()


## Web builds cannot resize or fullscreen their own window reliably.
func is_window_locked() -> bool:
	return OS.has_feature("web")


func _ensure_buses() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func _ensure_theme_variations() -> void:
	for variation: String in ["SmallLabel", "StatLabel", "BigStatLabel", "HeaderLabel"]:
		THEME.set_type_variation(variation, "Label")


func _build_tint_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	_tint = ColorRect.new()
	_tint.color = Color(0, 0, 0, 0)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_tint)


func apply_all() -> void:
	apply_audio()
	apply_brightness()
	apply_ui_scale()
	apply_window()
	changed.emit()


func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)


func _set_bus_volume(bus_name: String, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, percent <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(percent / 100.0, 0.0001, 1.0)))


func apply_brightness() -> void:
	if _tint == null:
		return
	if brightness <= BRIGHTNESS_NEUTRAL:
		var t := (BRIGHTNESS_NEUTRAL - brightness) / BRIGHTNESS_NEUTRAL
		_tint.color = Color(0, 0, 0, t * 0.75)
	else:
		var t := (brightness - BRIGHTNESS_NEUTRAL) / (100.0 - BRIGHTNESS_NEUTRAL)
		_tint.color = Color(1, 1, 1, t * 0.22)


func apply_ui_scale() -> void:
	var factor := clampf(ui_scale / 100.0, 0.8, 1.2)
	for type_name: String in BASE_FONT_SIZES:
		var base: int = BASE_FONT_SIZES[type_name]
		THEME.set_font_size("font_size", type_name, int(round(base * factor)))


func apply_window() -> void:
	if is_window_locked():
		return
	var win := get_window()
	match window_mode:
		0:
			win.mode = Window.MODE_FULLSCREEN
		1:
			win.mode = Window.MODE_WINDOWED
			win.borderless = false
			win.size = _fitted_size()
			_center_window()
		2:
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
			win.size = _fitted_size()
			_center_window()


## Shrink the requested resolution so it always fits the usable desktop area.
func _fitted_size() -> Vector2i:
	var wanted := RESOLUTIONS[resolution_index]
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var shrink := minf(1.0, minf(float(usable.x) / wanted.x, float(usable.y) / wanted.y))
	return Vector2i(wanted) * shrink if shrink < 1.0 else wanted


func _center_window() -> void:
	var win := get_window()
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	win.position = usable.position + (usable.size - win.size) / 2


func reset_defaults() -> void:
	resolution_index = 0
	window_mode = 1
	brightness = 75.0
	master_volume = 80.0
	music_volume = 60.0
	sfx_volume = 80.0
	screen_shake = true
	show_damage = true
	tutorial_tips = true
	language_index = 0
	difficulty = 1
	ui_scale = 100.0


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_GAME_PATH)


func write_save() -> void:
	var f := FileAccess.open(SAVE_GAME_PATH, FileAccess.WRITE)
	if f:
		f.store_string("1")
		f.close()


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_GAME_PATH)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "resolution", resolution_index)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "brightness", brightness)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("gameplay", "screen_shake", screen_shake)
	cfg.set_value("gameplay", "show_damage", show_damage)
	cfg.set_value("gameplay", "tutorial_tips", tutorial_tips)
	cfg.set_value("gameplay", "difficulty", difficulty)
	cfg.set_value("misc", "language", language_index)
	cfg.set_value("misc", "ui_scale", ui_scale)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	resolution_index = cfg.get_value("display", "resolution", resolution_index)
	window_mode = cfg.get_value("display", "window_mode", window_mode)
	brightness = cfg.get_value("display", "brightness", brightness)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	screen_shake = cfg.get_value("gameplay", "screen_shake", screen_shake)
	show_damage = cfg.get_value("gameplay", "show_damage", show_damage)
	tutorial_tips = cfg.get_value("gameplay", "tutorial_tips", tutorial_tips)
	difficulty = cfg.get_value("gameplay", "difficulty", difficulty)
	language_index = cfg.get_value("misc", "language", language_index)
	ui_scale = cfg.get_value("misc", "ui_scale", ui_scale)
