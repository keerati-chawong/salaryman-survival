extends Control
## Confrontation Phase. Four word types are checked against the current enemy's
## weakness table; each enemy answers with its own signature skill.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const PROMOTION := "res://scenes/Promotion.tscn"
const WORK_PHASE := "res://scenes/WorkPhase.tscn"

## Anger regained whenever the enemy lands a hit, per the design's
## "anger builds when you are insulted" rule.
const ANGER_ON_HIT := 12

@onready var enemy_sprite: TextureRect = $Enemy
@onready var enemy_shadow: TextureRect = $EnemyShadow
@onready var player_sprite: TextureRect = $Player
@onready var player_shadow: TextureRect = $PlayerShadow

@onready var enemy_name: Label = $EnemyPanel/Rows/TitleRow/EnemyName
@onready var enemy_role: Label = $EnemyPanel/Rows/TitleRow/EnemyRole
@onready var enemy_health_percent: Label = $EnemyPanel/Rows/TitleRow/EnemyHealthPercent
@onready var enemy_bar: ProgressBar = $EnemyPanel/Rows/BarRow/EnemyHPBar
@onready var enemy_hp_label: Label = $EnemyPanel/Rows/BarRow/EnemyHPLabel
@onready var enemy_bar_visual: ProgressBar = $EnemyHealthBarVisual

@onready var patience_bar: ProgressBar = $PlayerPanel/Cols/Bars/HPRow/PatienceBar
@onready var patience_label: Label = $PlayerPanel/Cols/Bars/HPRow/PatienceLabel
@onready var anger_bar: ProgressBar = $PlayerPanel/Cols/Bars/MPRow/AngerBar
@onready var anger_label: Label = $PlayerPanel/Cols/Bars/MPRow/AngerLabel
@onready var rank_label: Label = $PlayerPanel/Cols/Bars/RankLabel
@onready var patience_bar_visual: ProgressBar = $PatienceBarVisual
@onready var anger_bar_visual: ProgressBar = $AngerBarVisual

@onready var enemy_cells: Control = $EnemyCells
@onready var patience_cells: Control = $PatienceCells
@onready var anger_cells: Control = $AngerCells
@onready var patience_title: Label = $PatienceTitle
@onready var anger_title: Label = $AngerTitle

@onready var word_grid: GridContainer = $ActionPanel/Rows/WordGrid
@onready var item_row: HBoxContainer = $UtilityRow/ItemRow
@onready var bite_button: Button = $UtilityRow/BiteButton
@onready var hint_label: Label = $ActionPanel/Rows/HintLabel
@onready var utility_hint: PanelContainer = $UtilityHint
@onready var utility_hint_text: Label = $UtilityHint/Text

const BITE_ANGER := 15
@onready var message_label: Label = $MessagePanel/MessageLabel
@onready var popup_label: Label = $DamagePopup
@onready var flash_overlay: ColorRect = $FlashOverlay
@onready var background: TextureRect = $Background

var _enemy: Dictionary = {}
var _enemy_hp := 0
var _enemy_max := 0

var _busy := false
var _over := false
var _guard_next := false
var _silenced := ""
var _interrupted := false

var _word_buttons: Dictionary = {}
var _item_buttons: Dictionary = {}

var _player_home: Vector2
var _enemy_home: Vector2
var _player_shadow_home: Vector2
var _enemy_shadow_home: Vector2
var _player_offset := Vector2.ZERO
var _enemy_offset := Vector2.ZERO
var _idle := 0.0
var _player_down := false
var _enemy_down := false

var _hp_fill := StyleBoxFlat.new()
var _enemy_fill := StyleBoxFlat.new()
var _anger_fill := StyleBoxFlat.new()
var _enemy_cells: Array[TextureRect] = []
var _patience_cells: Array[TextureRect] = []
var _anger_cells: Array[TextureRect] = []


func _ready() -> void:
	randomize()
	_enemy = GameState.current_enemy()
	_enemy_max = int(_enemy["hp"])
	_enemy_hp = _enemy_max

	_setup_enemy_visuals()
	_setup_bars()
	_build_word_buttons()
	_build_item_buttons()
	bite_button.mouse_entered.connect(_show_utility_hint.bind("Bite Tongue: gain 15 Anger. Free to use, but ends your turn."))
	bite_button.mouse_exited.connect(_hide_utility_hint)
	_setup_sprites()
	_refresh(true)

	_say("%s\n%s" % [String(_enemy["intro"]), "Pick your words carefully."])


func _setup_enemy_visuals() -> void:
	enemy_sprite.texture = load(String(_enemy["sprite"]))
	enemy_name.text = String(_enemy["name"]).to_upper()
	enemy_role.text = String(_enemy["role"])
	var s := float(_enemy["scale"])
	enemy_sprite.scale = Vector2(s, s)


func _setup_bars() -> void:
	_enemy_fill.bg_color = Color(0.78, 0.2, 0.24)
	_enemy_fill.set_corner_radius_all(2)
	enemy_bar.add_theme_stylebox_override("fill", _enemy_fill)
	enemy_bar_visual.add_theme_stylebox_override("fill", _enemy_fill)

	_hp_fill.bg_color = Color(0.78, 0.2, 0.24)
	_hp_fill.set_corner_radius_all(2)
	patience_bar.add_theme_stylebox_override("fill", _hp_fill)
	patience_bar_visual.add_theme_stylebox_override("fill", _hp_fill)

	_anger_fill.bg_color = Color(0.28, 0.52, 0.62)
	_anger_fill.set_corner_radius_all(2)
	anger_bar_visual.add_theme_stylebox_override("fill", _anger_fill)
	var transparent_bar := StyleBoxEmpty.new()
	enemy_bar_visual.add_theme_stylebox_override("background", transparent_bar)
	patience_bar_visual.add_theme_stylebox_override("background", transparent_bar)
	anger_bar_visual.add_theme_stylebox_override("background", transparent_bar)

	enemy_bar.max_value = _enemy_max
	patience_bar.max_value = GameState.MAX_PATIENCE
	anger_bar.max_value = GameState.MAX_ANGER
	enemy_bar_visual.max_value = _enemy_max
	patience_bar_visual.max_value = GameState.MAX_PATIENCE
	anger_bar_visual.max_value = GameState.MAX_ANGER


func _make_health_cells(holder: Control, texture_path: String, positions: Array[Vector2], cell_size: Vector2) -> Array[TextureRect]:
	var cells: Array[TextureRect] = []
	var fill_texture := load(texture_path) as Texture2D
	for index: int in 4:
		var cell := TextureRect.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.texture = fill_texture
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_SCALE
		cell.position = positions[index]
		cell.size = cell_size
		holder.add_child(cell)
		cells.append(cell)
	return cells


func _refresh_health_cells(cells: Array[TextureRect], current: float, maximum: float) -> void:
	var visible_count := 0 if maximum <= 0.0 else clampi(ceili(clampf(current / maximum, 0.0, 1.0) * 4.0), 0, 4)
	for index: int in cells.size():
		cells[index].visible = index < visible_count


func _setup_sprites() -> void:
	_player_home = player_sprite.position
	_enemy_home = enemy_sprite.position
	_player_shadow_home = player_shadow.position
	_enemy_shadow_home = enemy_shadow.position
	player_sprite.pivot_offset = Vector2(player_sprite.size.x * 0.5, player_sprite.size.y)
	enemy_sprite.pivot_offset = Vector2(enemy_sprite.size.x * 0.5, enemy_sprite.size.y)


# ------------------------------------------------------------ ui building ---

func _build_word_buttons() -> void:
	for word: Dictionary in GameData.WORDS:
		var btn := Button.new()
		# The illustrated HUD supplies the cards; the transparent controls keep
		# the interaction and live text on top of that artwork.
		btn.flat = true
		btn.custom_minimum_size = Vector2(0, 58)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 16)
		btn.text = "%s\n%d Anger" % [String(word["short"]), int(word["cost"])]
		btn.add_theme_color_override("font_color", word["color"])
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.42))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.72, 0.32))
		btn.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.03, 1.0))
		btn.add_theme_constant_override("outline_size", 5)
		btn.pressed.connect(_on_word_pressed.bind(String(word["id"])))
		# a shared hint line avoids tooltips popping over neighbouring buttons
		btn.mouse_entered.connect(_show_hint.bind("%s - %s" % [String(word["name"]), String(word["blurb"])]))
		btn.mouse_exited.connect(_clear_hint)
		word_grid.add_child(btn)
		_word_buttons[String(word["id"])] = btn


func _build_item_buttons() -> void:
	for id: String in GameData.ITEMS:
		var item: Dictionary = GameData.ITEMS[id]
		var btn := Button.new()
		btn.flat = false
		btn.custom_minimum_size = Vector2(82, 42)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.03, 1.0))
		btn.add_theme_constant_override("outline_size", 4)
		btn.pressed.connect(_on_item_pressed.bind(id))
		btn.mouse_entered.connect(_show_utility_hint.bind("%s: %s" % [String(item["name"]), String(item["blurb"])]))
		btn.mouse_exited.connect(_hide_utility_hint)
		item_row.add_child(btn)
		_item_buttons[id] = btn


func _show_hint(text: String) -> void:
	hint_label.text = text


func _clear_hint() -> void:
	hint_label.text = "Hover a line to see what it does."


func _show_utility_hint(text: String) -> void:
	utility_hint_text.text = text
	utility_hint.show()


func _hide_utility_hint() -> void:
	utility_hint.hide()


func _refresh_buttons() -> void:
	for id: String in _word_buttons:
		var word := GameData.word_by_id(id)
		var btn: Button = _word_buttons[id]
		var blocked := _over or _busy or _silenced == id or GameState.anger < int(word["cost"])
		btn.disabled = blocked
		var suffix := "  (silenced)" if _silenced == id else ""
		btn.text = "%s%s\n%d Anger" % [String(word["short"]), suffix, int(word["cost"])]

	for id: String in _item_buttons:
		var item: Dictionary = GameData.ITEMS[id]
		var btn: Button = _item_buttons[id]
		var count := GameState.item_count(id)
		var short_names := {"coffee": "COFFEE", "bubble_tea": "TEA", "headphones": "HEADPHONES"}
		btn.text = "%s x%d" % [String(short_names.get(id, item["name"])), count]
		btn.disabled = _over or _busy or count <= 0

	bite_button.disabled = _over or _busy


# ------------------------------------------------------------------ state ---

func _refresh(instant := false) -> void:
	enemy_hp_label.text = "%d / %d" % [maxi(_enemy_hp, 0), _enemy_max]
	patience_label.text = "%d / %d" % [maxi(GameState.patience, 0), GameState.MAX_PATIENCE]
	anger_label.text = "%d / %d" % [GameState.anger, GameState.MAX_ANGER]
	rank_label.text = "Rank: %s" % GameState.rank
	enemy_health_percent.text = "%d%%" % roundi(_percent(_enemy_hp, _enemy_max))
	patience_title.text = "PATIENCE  %d%%" % roundi(_percent(GameState.patience, GameState.MAX_PATIENCE))
	anger_title.text = "ANGER  %d%%" % roundi(_percent(GameState.anger, GameState.MAX_ANGER))

	if instant:
		enemy_bar.value = _enemy_hp
		patience_bar.value = GameState.patience
		anger_bar.value = GameState.anger
		enemy_bar_visual.value = _enemy_hp
		patience_bar_visual.value = GameState.patience
		anger_bar_visual.value = GameState.anger
	else:
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(enemy_bar, "value", maxf(_enemy_hp, 0), 0.3)
		t.tween_property(patience_bar, "value", maxf(GameState.patience, 0), 0.3)
		t.tween_property(anger_bar, "value", GameState.anger, 0.3)
		t.tween_property(enemy_bar_visual, "value", maxf(_enemy_hp, 0), 0.3)
		t.tween_property(patience_bar_visual, "value", maxf(GameState.patience, 0), 0.3)
		t.tween_property(anger_bar_visual, "value", GameState.anger, 0.3)

	_refresh_health_cells(_enemy_cells, _enemy_hp, _enemy_max)
	_refresh_health_cells(_patience_cells, GameState.patience, GameState.MAX_PATIENCE)
	_refresh_health_cells(_anger_cells, GameState.anger, GameState.MAX_ANGER)

	_recolour(_hp_fill, float(GameState.patience) / GameState.MAX_PATIENCE)
	_recolour(_enemy_fill, float(_enemy_hp) / _enemy_max)
	_refresh_buttons()


func _percent(current: float, maximum: float) -> float:
	return 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0) * 100.0


func _recolour(box: StyleBoxFlat, ratio: float) -> void:
	if ratio <= 0.25:
		box.bg_color = Color(0.55, 0.1, 0.13)
	elif ratio <= 0.5:
		box.bg_color = Color(0.85, 0.45, 0.15)
	else:
		box.bg_color = Color(0.78, 0.2, 0.24)


func _say(text: String) -> void:
	message_label.text = text


# ---------------------------------------------------------------- actions ---

func _on_word_pressed(id: String) -> void:
	if _busy or _over:
		return
	var word := GameData.word_by_id(id)
	if not GameState.spend_anger(int(word["cost"])):
		_say("Not enough Anger for that one.")
		return

	_busy = true
	_refresh_buttons()

	var mult := float((_enemy["mult"] as Dictionary).get(id, 1.0))
	var base := int(word["power"] * randf_range(0.85, 1.15))
	if _interrupted:
		base = int(base * 0.6)
		_interrupted = false
	var dealt := int(base * mult)

	var lines: Array = word["lines"]
	_say('"%s"' % String(lines[randi() % lines.size()]))

	_lunge("player", 330.0, -30.0)
	await get_tree().create_timer(0.22).timeout

	_enemy_hp = maxi(_enemy_hp - dealt, 0)
	_refresh()

	var label := GameData.effectiveness_label(mult)
	if is_equal_approx(mult, GameData.IMMUNE):
		_popup("IMMUNE", true, GameData.effectiveness_color(mult))
		_say("%s doesn't even register it." % String(_enemy["name"]))
	else:
		_popup("-%d %s" % [dealt, label], true, GameData.effectiveness_color(mult))
		_recoil("enemy", 34.0)
		if mult >= GameData.CRITICAL_AT:
			_flash(Color(1.0, 0.9, 0.4), 0.42, 0.3)
			_shake(12.0, 0.3)
		else:
			_flash(Color.WHITE, 0.26, 0.2)
			_shake(6.0, 0.2)

	await get_tree().create_timer(0.6).timeout
	await _enemy_turn()


func _on_bite_pressed() -> void:
	if _busy or _over:
		return

	_busy = true
	_refresh_buttons()

	GameState.add_anger(BITE_ANGER)
	_say("You bite your tongue and swallow it. The anger stays in the tank.")
	_tint(player_sprite, Color(0.85, 0.85, 0.85), 0.4)
	_popup("+%d Anger" % BITE_ANGER, false, Color(0.95, 0.66, 0.25))

	_refresh()
	await get_tree().create_timer(0.5).timeout
	await _enemy_turn()


func _on_item_pressed(id: String) -> void:
	if _busy or _over:
		return
	if not GameState.consume_item(id):
		return

	_busy = true
	_refresh_buttons()

	var item: Dictionary = GameData.ITEMS[id]
	match String(item["effect"]):
		"anger":
			GameState.add_anger(int(item["amount"]))
			_say("You down a black coffee. The rage sharpens.")
			_tint(player_sprite, Color(1.25, 0.95, 0.6), 0.5)
		"hp":
			GameState.add_patience(int(item["amount"]))
			_say("Bubble tea. Small joy, big recovery.")
			_tint(player_sprite, Color(0.6, 1.25, 0.7), 0.5)
		"guard":
			_guard_next = true
			_say("Headphones on. Whatever they say next lands softer.")
			_tint(player_sprite, Color(0.62, 0.78, 1.25), 0.5)

	var hop := create_tween()
	hop.tween_property(self, "_player_offset", Vector2(0.0, -28.0), 0.15).set_trans(Tween.TRANS_QUAD)
	hop.tween_property(self, "_player_offset", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BOUNCE)

	_refresh()
	await get_tree().create_timer(0.6).timeout
	await _enemy_turn()


# ------------------------------------------------------------- enemy turn ---

func _enemy_turn() -> void:
	if _enemy_hp <= 0:
		await _win()
		return

	_silenced = ""

	var used_skill := await _try_skill()
	if not used_skill:
		var dmg_range: Array = _enemy["damage"]
		var dmg := randi_range(int(dmg_range[0]), int(dmg_range[1]))
		dmg = int(dmg * [0.75, 1.0, 1.3][clampi(Settings.difficulty, 0, 2)])
		if _guard_next:
			dmg = int(dmg * 0.5)
			_guard_next = false

		var taunts: Array = _enemy["taunts"]
		_say('"%s"' % String(taunts[randi() % taunts.size()]))

		_lunge("enemy", -400.0, -10.0)
		await get_tree().create_timer(0.22).timeout

		GameState.add_patience(-dmg)
		GameState.add_anger(ANGER_ON_HIT)
		_popup("-%d" % dmg, false, Color(1.0, 0.5, 0.45))
		_recoil("player", -40.0)
		_flash(Color(0.9, 0.2, 0.2), 0.3, 0.3)
		_shake(10.0, 0.3)
		_refresh()

	await get_tree().create_timer(0.65).timeout

	if GameState.patience <= 0:
		await _lose()
	else:
		_busy = false
		_refresh_buttons()


## Returns true when a signature skill replaced the plain attack this turn.
func _try_skill() -> bool:
	var skill := String(_enemy.get("skill", "none"))
	if skill == "none" or randf() > 0.4:
		return false

	_lunge("enemy", -260.0, 0.0)
	await get_tree().create_timer(0.2).timeout

	match skill:
		"pile_on":
			var chip := 10
			GameState.add_patience(-chip)
			GameState.add_anger(ANGER_ON_HIT)
			_say("Pile On - another 'small favour' lands on your desk.")
			_popup("-%d" % chip, false, Color(1.0, 0.6, 0.4))
		"interrupt":
			_interrupted = true
			_say("Cut You Off - your next line loses its edge.")
			_popup("Interrupted", false, Color(0.8, 0.8, 0.9))
		"silence":
			var pool: Array = []
			for w: Dictionary in GameData.WORDS:
				pool.append(String(w["id"]))
			_silenced = String(pool[randi() % pool.size()])
			_say("Policy Citation - %s is off limits this turn." % GameData.word_by_id(_silenced)["name"])
			_popup("Silenced", false, Color(0.8, 0.8, 0.9))
		"gaslight":
			var drain := 18
			GameState.add_anger(-drain)
			_say("Gaslighting - \"I never said that.\" Your anger wavers.")
			_popup("-%d Anger" % drain, false, Color(0.85, 0.7, 1.0))

	_flash(Color(0.6, 0.4, 0.9), 0.28, 0.35)
	_refresh()
	return true


# ---------------------------------------------------------------- outcome ---

func _win() -> void:
	_over = true
	_refresh_buttons()
	_collapse("enemy")
	_flash(Color(1.0, 0.85, 0.3), 0.4, 0.6)
	_say("%s has nothing left to say." % String(_enemy["name"]))
	await get_tree().create_timer(1.8).timeout
	GameState.advance_stage()
	get_tree().change_scene_to_file(PROMOTION)


func _lose() -> void:
	_over = true
	_refresh_buttons()
	_collapse("player")
	_flash(Color(0.1, 0.1, 0.1), 0.6, 1.2)
	_say("Your patience is gone. You apologise and go back to your desk.")
	GameState.delete_save()
	await get_tree().create_timer(2.1).timeout
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _over:
		GameState.save_game()
		get_tree().change_scene_to_file(MAIN_MENU)
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------- fx ---

func _process(delta: float) -> void:
	_idle += delta
	var pb := 0.0 if _player_down else sin(_idle * 1.9) * 4.0
	player_sprite.position = _player_home + _player_offset + Vector2(0.0, pb)
	player_shadow.position = _player_shadow_home + Vector2(_player_offset.x, 0.0)

	var eb := 0.0 if _enemy_down else sin(_idle * 1.4 + 1.0) * 3.0
	enemy_sprite.position = _enemy_home + _enemy_offset + Vector2(0.0, eb)
	enemy_shadow.position = _enemy_shadow_home + Vector2(_enemy_offset.x, 0.0)


func _popup(text: String, at_enemy: bool, color: Color) -> void:
	if not Settings.show_damage:
		return
	popup_label.text = text
	popup_label.add_theme_color_override("font_color", color)
	popup_label.position = Vector2(940.0, 300.0) if at_enemy else Vector2(300.0, 560.0)
	popup_label.modulate.a = 1.0
	var start_y := popup_label.position.y
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(popup_label, "position:y", start_y - 62.0, 0.75)
	t.tween_property(popup_label, "modulate:a", 0.0, 0.75)


func _tint(sprite: TextureRect, color: Color, duration: float) -> void:
	sprite.modulate = color
	create_tween().tween_property(sprite, "modulate", Color.WHITE, duration)


func _lunge(who: String, distance: float, lift: float) -> void:
	var prop := "_player_offset" if who == "player" else "_enemy_offset"
	var sprite := player_sprite if who == "player" else enemy_sprite
	var rest: Vector2 = sprite.scale
	var t := create_tween()
	t.tween_property(self, prop, Vector2(distance, lift), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(sprite, "scale", rest * 1.05, 0.18)
	t.tween_interval(0.12)
	t.tween_property(self, prop, Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(sprite, "scale", rest, 0.3)


func _recoil(who: String, distance: float) -> void:
	var prop := "_player_offset" if who == "player" else "_enemy_offset"
	var sprite := player_sprite if who == "player" else enemy_sprite
	_tint(sprite, Color(1.0, 0.42, 0.42), 0.45)
	var t := create_tween()
	t.tween_property(self, prop, Vector2(distance, 0.0), 0.09).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, prop, Vector2.ZERO, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _collapse(who: String) -> void:
	var sprite := player_sprite if who == "player" else enemy_sprite
	var shadow := player_shadow if who == "player" else enemy_shadow
	if who == "player":
		_player_down = true
	else:
		_enemy_down = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(sprite, "rotation", deg_to_rad(-72.0 if who == "player" else 68.0), 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "modulate:a", 0.25, 0.9)
	t.tween_property(shadow, "modulate:a", 0.0, 0.7)


func _shake(strength: float, duration: float) -> void:
	if not Settings.screen_shake:
		return
	var t := create_tween()
	for i: int in 6:
		t.tween_property(self, "position",
			Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / 6.0)
	t.tween_property(self, "position", Vector2.ZERO, duration / 6.0)


func _flash(color: Color, peak: float, duration: float) -> void:
	flash_overlay.color = Color(color.r, color.g, color.b, peak)
	create_tween().tween_property(flash_overlay, "color:a", 0.0, duration)
