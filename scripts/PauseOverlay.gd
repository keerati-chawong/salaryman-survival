class_name PauseOverlay
extends CanvasLayer
## Reusable Esc-menu for gameplay scenes (WorkPhase, Battle) that previously
## only supported "press Esc to instantly quit" with no on-screen equivalent.
## Adds a small always-visible corner button plus a pause panel with Resume,
## a Music on/off toggle, a Sound (SFX) on/off toggle, and Exit to Main Menu -
## so leaving (or muting) is reachable by mouse as well as by keyboard.
##
## Usage: `_pause = PauseOverlay.attach(self, _quit_to_menu)` in _ready(),
## then call `_pause.toggle()` from the scene's own ui_cancel handler instead
## of quitting directly. Connect to `state_changed` if the scene needs to
## freeze its own logic (a running timer, typed input, ...) while paused.

signal state_changed(is_open: bool)

var _quit_callback: Callable
var _dim: Button
var _panel: PanelContainer
var _music_btn: Button
var _sfx_btn: Button


static func attach(parent: Node, quit_callback: Callable) -> PauseOverlay:
	var o := PauseOverlay.new()
	o.layer = 90
	o._quit_callback = quit_callback
	parent.add_child(o)
	return o


func _ready() -> void:
	_build_corner_button()
	_build_panel()


func _build_corner_button() -> void:
	var btn := Button.new()
	btn.text = "☰ Menu (Esc)"
	btn.custom_minimum_size = Vector2(132, 44)
	## Sits below the top-right "Esc" hint label every gameplay scene already
	## has, rather than on top of it.
	btn.position = Vector2(1480.0 - 144.0, 50.0)
	btn.pressed.connect(toggle)
	add_child(btn)


func _build_panel() -> void:
	_dim = Button.new()
	_dim.flat = true
	_dim.focus_mode = Control.FOCUS_NONE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_style := StyleBoxFlat.new()
	dim_style.bg_color = Color(0, 0, 0, 0.6)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_dim.add_theme_stylebox_override(state, dim_style)
	_dim.pressed.connect(_on_resume)
	_dim.visible = false
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(568, 332)
	_panel.size = Vector2(400, 360)
	_panel.visible = false
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	_panel.add_child(rows)

	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(0, 48)
	resume_btn.pressed.connect(_on_resume)
	rows.add_child(resume_btn)

	_music_btn = Button.new()
	_music_btn.custom_minimum_size = Vector2(0, 48)
	_music_btn.pressed.connect(_on_toggle_music)
	rows.add_child(_music_btn)

	_sfx_btn = Button.new()
	_sfx_btn.custom_minimum_size = Vector2(0, 48)
	_sfx_btn.pressed.connect(_on_toggle_sfx)
	rows.add_child(_sfx_btn)

	var exit_btn := Button.new()
	exit_btn.text = "Exit to Main Menu"
	exit_btn.custom_minimum_size = Vector2(0, 48)
	exit_btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
	exit_btn.pressed.connect(_on_exit)
	rows.add_child(exit_btn)


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	if _panel.visible:
		_on_resume()
	else:
		_open()


func _open() -> void:
	SoundManager.play_sfx("click")
	_refresh()
	_panel.visible = true
	_dim.visible = true
	state_changed.emit(true)


func _refresh() -> void:
	_music_btn.text = "Music: OFF" if Settings.music_muted else "Music: ON"
	_sfx_btn.text = "Sound: OFF" if Settings.sfx_muted else "Sound: ON"


func _on_resume() -> void:
	if not Settings.sfx_muted:
		SoundManager.play_sfx("click")
	_panel.visible = false
	_dim.visible = false
	state_changed.emit(false)


func _on_toggle_music() -> void:
	Settings.music_muted = not Settings.music_muted
	Settings.apply_audio()
	Settings.save_settings()
	_refresh()


func _on_toggle_sfx() -> void:
	Settings.sfx_muted = not Settings.sfx_muted
	Settings.apply_audio()
	Settings.save_settings()
	_refresh()
	if not Settings.sfx_muted:
		SoundManager.play_sfx("click")


func _on_exit() -> void:
	_panel.visible = false
	_dim.visible = false
	state_changed.emit(false)
	_quit_callback.call()
