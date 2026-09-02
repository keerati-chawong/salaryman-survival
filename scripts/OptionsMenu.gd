extends Control
## Options screen. The whole layout is built from containers so controls can
## never overlap, and a ScrollContainer absorbs any overflow from UI scaling.

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const TAB_TITLE := preload("res://assets/ui/opt_title.png")
const MONITOR := preload("res://assets/ui/opt_monitor.png")

const TABS := [
	{"id": "display", "label": "DISPLAY"},
	{"id": "audio", "label": "AUDIO"},
	{"id": "controls", "label": "CONTROLS"},
	{"id": "gameplay", "label": "GAMEPLAY"},
	{"id": "language", "label": "LANGUAGE"},
	{"id": "others", "label": "OTHERS"},
]

var _tab_buttons: Array[TextureButton] = []
var _panes: Dictionary = {}
var _header: Label
var _pane_host: VBoxContainer
var _toast: Label
var _current := "display"


func _ready() -> void:
	_build_ui()
	_select_tab("display")
	_refresh_from_settings()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


# ---------------------------------------------------------------- layout ----

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	root.add_child(_build_title_row())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	body.add_child(_build_sidebar())
	body.add_child(_build_content())

	root.add_child(_build_footer())


func _build_title_row() -> Control:
	var row := HBoxContainer.new()

	var title := TextureRect.new()
	title.texture = TAB_TITLE
	title.custom_minimum_size = Vector2(360, 95)
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_toast = Label.new()
	_toast.theme_type_variation = &"StatLabel"
	_toast.add_theme_color_override("font_color", Color(1, 0.86, 0.42))
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	row.add_child(_toast)

	return row


func _build_sidebar() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	for tab: Dictionary in TABS:
		var id: String = tab["id"]
		var btn := TextureButton.new()
		btn.texture_normal = load("res://assets/ui/tab_%s.png" % id)
		btn.texture_hover = load("res://assets/ui/tab_%s_hover.png" % id)
		btn.texture_pressed = load("res://assets/ui/tab_%s_active.png" % id)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.custom_minimum_size = Vector2(0, 76)
		btn.pressed.connect(_on_tab_pressed.bind(id))
		col.add_child(btn)
		_tab_buttons.append(btn)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)

	return panel


func _build_content() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	_header = Label.new()
	_header.theme_type_variation = &"HeaderLabel"
	col.add_child(_header)
	col.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)

	_pane_host = VBoxContainer.new()
	_pane_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_pane_host)

	_panes["display"] = _build_display_pane()
	_panes["audio"] = _build_audio_pane()
	_panes["controls"] = _build_controls_pane()
	_panes["gameplay"] = _build_gameplay_pane()
	_panes["language"] = _build_language_pane()
	_panes["others"] = _build_others_pane()

	for pane: Control in _panes.values():
		pane.visible = false
		_pane_host.add_child(pane)

	return panel


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var reset := Button.new()
	reset.text = "Reset to Default"
	reset.pressed.connect(_on_reset)
	row.add_child(reset)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var apply := Button.new()
	apply.text = "Apply"
	apply.pressed.connect(_on_apply)
	row.add_child(apply)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_go_back)
	row.add_child(back)

	return row


# ------------------------------------------------------------- row helpers --

func _new_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _label_cell(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(250, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _value_cell(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"StatLabel"
	l.custom_minimum_size = Vector2(86, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _blank_cell() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(86, 0)
	return c


func _add_slider(grid: GridContainer, text: String, minimum: float, maximum: float) -> Array:
	grid.add_child(_label_cell(text))

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(240, 0)
	grid.add_child(slider)

	var value := _value_cell("")
	grid.add_child(value)
	return [slider, value]


func _add_option(grid: GridContainer, text: String, items: Array) -> OptionButton:
	grid.add_child(_label_cell(text))

	var opt := OptionButton.new()
	for item: String in items:
		opt.add_item(item)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.fit_to_longest_item = false
	grid.add_child(opt)

	grid.add_child(_blank_cell())
	return opt


func _add_check(grid: GridContainer, text: String) -> CheckButton:
	grid.add_child(_label_cell(text))

	var check := CheckButton.new()
	check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.add_child(check)

	grid.add_child(_blank_cell())
	return check


func _add_info(grid: GridContainer, text: String, value: String) -> void:
	grid.add_child(_label_cell(text))
	var l := Label.new()
	l.text = value
	l.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(l)
	grid.add_child(_blank_cell())


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SmallLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Color(0.65, 0.68, 0.74))
	return l


# ------------------------------------------------------------------ panes ---

var _res_opt: OptionButton
var _mode_opt: OptionButton
var _bright_slider: HSlider
var _bright_value: Label
var _master_slider: HSlider
var _master_value: Label
var _music_slider: HSlider
var _music_value: Label
var _sfx_slider: HSlider
var _sfx_value: Label
var _music_mute_check: CheckButton
var _sfx_mute_check: CheckButton
var _difficulty_opt: OptionButton
var _shake_check: CheckButton
var _damage_check: CheckButton
var _tutorial_check: CheckButton
var _lang_opt: OptionButton
var _scale_slider: HSlider
var _scale_value: Label


func _build_display_pane() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	row.add_child(grid)

	var res_labels: Array = []
	for r: Vector2i in Settings.RESOLUTIONS:
		res_labels.append("%d x %d" % [r.x, r.y])

	_res_opt = _add_option(grid, "Resolution", res_labels)
	_res_opt.item_selected.connect(_on_resolution_selected)

	_mode_opt = _add_option(grid, "Window Mode", ["Fullscreen", "Windowed", "Borderless"])
	_mode_opt.item_selected.connect(_on_window_mode_selected)

	var b := _add_slider(grid, "Brightness", 0, 100)
	_bright_slider = b[0]
	_bright_value = b[1]
	_bright_slider.value_changed.connect(_on_brightness_changed)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	var monitor := TextureRect.new()
	monitor.texture = MONITOR
	monitor.custom_minimum_size = Vector2(240, 142)
	monitor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	monitor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	side.add_child(monitor)
	row.add_child(side)

	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pane.add_child(row)

	if Settings.is_window_locked():
		_res_opt.disabled = true
		_mode_opt.disabled = true
		pane.add_child(_note("Resolution and window mode are controlled by your browser in the web version. Use F11 for fullscreen."))

	return pane


func _build_audio_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	pane.add_child(grid)

	var m := _add_slider(grid, "Master Volume", 0, 100)
	_master_slider = m[0]
	_master_value = m[1]
	_master_slider.value_changed.connect(_on_master_changed)

	var mu := _add_slider(grid, "Music Volume", 0, 100)
	_music_slider = mu[0]
	_music_value = mu[1]
	_music_slider.value_changed.connect(_on_music_changed)

	var s := _add_slider(grid, "SFX Volume", 0, 100)
	_sfx_slider = s[0]
	_sfx_value = s[1]
	_sfx_slider.value_changed.connect(_on_sfx_changed)

	_music_mute_check = _add_check(grid, "Mute Music")
	_music_mute_check.toggled.connect(_on_music_mute_toggled)

	_sfx_mute_check = _add_check(grid, "Mute Sound")
	_sfx_mute_check.toggled.connect(_on_sfx_mute_toggled)

	pane.add_child(_note("Volume changes apply immediately and are shared by every scene. Mute keeps your slider levels - toggling it back on restores them."))
	return pane


func _build_controls_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	pane.add_child(grid)
	_add_info(grid, "Navigate Menu", "Arrow Keys  /  Mouse")
	_add_info(grid, "Confirm", "Enter  /  Space  /  Left Click")
	_add_info(grid, "Back / Cancel", "Esc")
	_add_info(grid, "Battle Actions", "Click ATK / DEF / ITEM / RUN")

	pane.add_child(_note("Key rebinding is not implemented in this prototype."))
	return pane


func _build_gameplay_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	pane.add_child(grid)

	_difficulty_opt = _add_option(grid, "Difficulty", ["Easy", "Normal", "Hard"])
	_difficulty_opt.item_selected.connect(_on_difficulty_selected)

	_shake_check = _add_check(grid, "Screen Shake")
	_shake_check.toggled.connect(_on_shake_toggled)

	_damage_check = _add_check(grid, "Show Damage Number")
	_damage_check.toggled.connect(_on_damage_toggled)

	_tutorial_check = _add_check(grid, "Tutorial Tips")
	_tutorial_check.toggled.connect(_on_tutorial_toggled)

	pane.add_child(_note("Difficulty scales the manager's damage in battle."))
	return pane


func _build_language_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	pane.add_child(grid)

	_lang_opt = _add_option(grid, "Language", ["English", "Thai"])
	_lang_opt.item_selected.connect(_on_language_selected)

	pane.add_child(_note("Only English text is shipped in this prototype; the setting is saved for later."))
	return pane


func _build_others_pane() -> Control:
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", 14)
	pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := _new_grid()
	pane.add_child(grid)

	var u := _add_slider(grid, "UI Scale", 80, 120)
	_scale_slider = u[0]
	_scale_value = u[1]
	_scale_slider.value_changed.connect(_on_ui_scale_changed)

	pane.add_child(HSeparator.new())

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 14)

	var wipe := Button.new()
	wipe.text = "Delete Save Data"
	wipe.pressed.connect(_on_delete_save)
	actions.add_child(wipe)

	pane.add_child(actions)
	pane.add_child(_note("Salaryman Survival — prototype build. Deleting save data disables Continue on the main menu."))
	return pane


# ----------------------------------------------------------------- state ----

func _on_tab_pressed(id: String) -> void:
	SoundManager.play_sfx("click")
	_select_tab(id)


func _select_tab(id: String) -> void:
	_current = id
	for i: int in TABS.size():
		var tab: Dictionary = TABS[i]
		var active: bool = tab["id"] == id
		var suffix := "_active" if active else ""
		var btn := _tab_buttons[i]
		btn.texture_normal = load("res://assets/ui/tab_%s%s.png" % [tab["id"], suffix])
		btn.modulate = Color(1, 0.96, 0.82) if active else Color(0.74, 0.76, 0.8)
		if active:
			_header.text = tab["label"]

	for key: String in _panes:
		_panes[key].visible = key == id


func _refresh_from_settings() -> void:
	_res_opt.selected = Settings.resolution_index
	_mode_opt.selected = Settings.window_mode
	_bright_slider.value = Settings.brightness
	_master_slider.value = Settings.master_volume
	_music_slider.value = Settings.music_volume
	_sfx_slider.value = Settings.sfx_volume
	_difficulty_opt.selected = Settings.difficulty
	_shake_check.button_pressed = Settings.screen_shake
	_damage_check.button_pressed = Settings.show_damage
	_tutorial_check.button_pressed = Settings.tutorial_tips
	_lang_opt.selected = Settings.language_index
	_scale_slider.value = Settings.ui_scale

	_bright_value.text = "%d%%" % int(Settings.brightness)
	_master_value.text = "%d%%" % int(Settings.master_volume)
	_music_value.text = "%d%%" % int(Settings.music_volume)
	_sfx_value.text = "%d%%" % int(Settings.sfx_volume)
	_music_mute_check.button_pressed = Settings.music_muted
	_sfx_mute_check.button_pressed = Settings.sfx_muted
	_scale_value.text = "%d%%" % int(Settings.ui_scale)


func _on_resolution_selected(idx: int) -> void:
	Settings.resolution_index = idx
	Settings.apply_window()


func _on_window_mode_selected(idx: int) -> void:
	Settings.window_mode = idx
	Settings.apply_window()


func _on_brightness_changed(v: float) -> void:
	Settings.brightness = v
	Settings.apply_brightness()
	_bright_value.text = "%d%%" % int(v)


func _on_master_changed(v: float) -> void:
	Settings.master_volume = v
	Settings.apply_audio()
	_master_value.text = "%d%%" % int(v)


func _on_music_changed(v: float) -> void:
	Settings.music_volume = v
	Settings.apply_audio()
	_music_value.text = "%d%%" % int(v)


func _on_sfx_changed(v: float) -> void:
	Settings.sfx_volume = v
	Settings.apply_audio()
	_sfx_value.text = "%d%%" % int(v)


func _on_music_mute_toggled(on: bool) -> void:
	Settings.music_muted = on
	Settings.apply_audio()


func _on_sfx_mute_toggled(on: bool) -> void:
	Settings.sfx_muted = on
	Settings.apply_audio()


func _on_ui_scale_changed(v: float) -> void:
	Settings.ui_scale = v
	Settings.apply_ui_scale()
	_scale_value.text = "%d%%" % int(v)


func _on_difficulty_selected(idx: int) -> void:
	Settings.difficulty = idx


func _on_shake_toggled(on: bool) -> void:
	Settings.screen_shake = on


func _on_damage_toggled(on: bool) -> void:
	Settings.show_damage = on


func _on_tutorial_toggled(on: bool) -> void:
	Settings.tutorial_tips = on


func _on_language_selected(idx: int) -> void:
	Settings.language_index = idx


func _on_delete_save() -> void:
	SoundManager.play_sfx("click")
	GameState.delete_save()
	_show_toast("Save data deleted")


func _on_reset() -> void:
	SoundManager.play_sfx("click")
	Settings.reset_defaults()
	Settings.apply_all()
	_refresh_from_settings()
	_show_toast("Reset to default")


func _on_apply() -> void:
	SoundManager.play_sfx("click")
	Settings.apply_all()
	Settings.save_settings()
	_show_toast("Settings saved")


func _go_back() -> void:
	SoundManager.play_sfx("click")
	Settings.save_settings()
	get_tree().change_scene_to_file(MAIN_MENU)


func _show_toast(msg: String) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(_toast, "modulate:a", 0.0, 0.5)
