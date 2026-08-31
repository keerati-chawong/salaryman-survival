extends Control
## Work Phase. A typing test: type the target word to earn Energy and Coins
## (a perfect, mistake-free word builds a Combo that multiplies the Energy
## payout), while toxic "distraction" pop-ups periodically demand a quick
## office-shortcut key (Space/Alt/Ctrl/Enter) to dodge. Mistyping a character
## costs Patience, and that penalty gets harsher every stage. Which word
## category gets drilled - and unlocked for Battle, if it isn't already -
## depends on GameState.stage_index; see GameData.STAGE_FOCUS_WORD.
##
## GameState.energy carries straight into Battle as the starting Energy
## resource (see the comment on GameState.energy) - there's no conversion
## step, so everything earned here is available from Battle's first turn.

const BATTLE_SCENE := "res://scenes/Battle.tscn"
const MAIN_MENU := "res://scenes/MainMenu.tscn"
const GAME_OVER := "res://scenes/GameOver.tscn"

## Flat round length for every stage.
const ROUND_DURATION := 40.0

## Flat Energy per completed word, before the Combo multiplier.
const BASE_WORD_ENERGY := 5
const COIN_PER_WORD := 2
## Each correctly typed word banks this many word-uses toward Battle's
## per-word floor (GameState.word_quota, read by Battle.gd's
## _init_word_uses()) - raised from 1 so a solid typing run meaningfully
## outpaces the plain effectiveness-based floor there.
const QUOTA_PER_WORD := 2
## Each consecutive perfect (no-mistake) word raises the multiplier by this
## much, capped at COMBO_MAX_MULT - a long clean streak pays off a lot more
## than a single lucky word, which is the point (rewards touch-typing).
const COMBO_STEP := 0.25
const COMBO_MAX_MULT := 3.0

## Patience lost per mistyped character, scaled by stage: -2 on stage 1 up
## to -10 by the final stage (see _mistype_penalty()).
const MISTYPE_PENALTY_START := 2
const MISTYPE_PENALTY_END := 10

const QTE_SUCCESS_PATIENCE := 20
const QTE_FAIL_PATIENCE_PENALTY := 10
const QTE_INTERVAL := Vector2(5.0, 8.5)
## Spec calls for a 1.0-1.5s dodge window.
const QTE_WINDOW := 1.3

## Office "shortcut key" flavours for the distraction QTE - varies which key
## is needed and why, instead of always the same generic prompt.
const QTE_TYPES := [
	{"keycode": KEY_SPACE, "label": "SPACE", "prompt": "Duck the insult - press SPACE!"},
	{"keycode": KEY_ALT, "label": "ALT", "prompt": "Swat the interruption away - press ALT!"},
	{"keycode": KEY_CTRL, "label": "CTRL", "prompt": "Bat it down - press CTRL!"},
	{"keycode": KEY_ENTER, "label": "ENTER", "prompt": "Close the spam pop-up - press ENTER!"},
]
## Alt/Ctrl/Enter never count as a typed character - no target word contains
## one. Space is NOT in this list: several target words are multi-word
## phrases (e.g. "touch base") that need a literal space, so it's only
## intercepted while a Space-flavoured QTE is actually active (see
## _unhandled_input()) and types normally the rest of the time.
const RESERVED_KEYS := [KEY_ALT, KEY_CTRL, KEY_ENTER]

const DISTRACTION_TEXTS := [
	"What kind of work is this?!",
	"Redo it again!",
	"You can't even do this much?",
	"Can't you go faster?",
	"Why so slow?",
	"What is this supposed to be?",
]
## Distraction pop-ups drift across the screen well after their QTE window
## closes, so they're a lingering visual instead of a blink-and-miss-it.
const DISTRACTION_FLOAT_DURATION := 4.5

@onready var distraction_layer: Control = $DistractionLayer
@onready var objective_label: Label = $HUD/Objective

@onready var patience_bar: ProgressBar = $HUD/Stats/PatienceRow/PatienceBar
@onready var patience_value: Label = $HUD/Stats/PatienceRow/PatienceValue
@onready var energy_bar: ProgressBar = $HUD/Stats/EnergyRow/EnergyBar
@onready var energy_value: Label = $HUD/Stats/EnergyRow/EnergyValue
@onready var timer_bar: ProgressBar = $HUD/Stats/TimerRow/TimerBar
@onready var timer_value: Label = $HUD/Stats/TimerRow/TimerValue

@onready var category_label: Label = $TypingPanel/Rows/CategoryLabel
@onready var word_label: RichTextLabel = $TypingPanel/Rows/WordLabel
@onready var combo_label: Label = $TypingPanel/Rows/ComboLabel

@onready var qte_panel: PanelContainer = $QtePanel
@onready var qte_title: Label = $QtePanel/Rows/Title
@onready var qte_key_label: Label = $QtePanel/Rows/KeyLabel
@onready var qte_time_bar: ProgressBar = $QtePanel/Rows/TimeBar

@onready var intro_overlay: Control = $IntroOverlay
@onready var intro_body: Label = $IntroOverlay/Panel/Rows/Body
@onready var intro_start_button: Button = $IntroOverlay/Panel/Rows/StartButton

@onready var flash: ColorRect = $Flash

## Category ids this run draws target words from - a single id for the
## stage's focus category, or every unlocked id once there's nothing left to
## unlock (see _build_word_pool()).
var _word_pool: Array = []
var _target_word := ""
var _target_category := ""
var _typed_index := 0
var _word_mistake := false

var _words_typed := 0
## Consecutive words completed with zero mistakes; resets to 0 on any typo.
var _combo_streak := 0
## Category id -> words typed correctly this run; handed to
## GameState.set_word_quota() when the phase ends successfully.
var _word_quota: Dictionary = {}
## Category id -> shuffled Array of words not yet drawn this run (see
## _draw_word()) - a "shuffle bag" so no word repeats until every word in its
## category has come up once, then it reshuffles and keeps going.
var _word_bags: Dictionary = {}

var _round_duration := ROUND_DURATION
var _time_remaining := ROUND_DURATION
var _mistype_penalty := MISTYPE_PENALTY_START

var _qte_active := false
var _qte_remaining := 0.0
var _qte_timer := 0.0
var _qte_keycode: int = KEY_SPACE

var _intro_visible := true
var _finished := false


func _ready() -> void:
	randomize()
	_round_duration = _compute_round_duration()
	_time_remaining = _round_duration
	_mistype_penalty = _compute_mistype_penalty()
	timer_bar.max_value = _round_duration
	timer_bar.value = _round_duration
	energy_bar.max_value = GameState.MAX_ENERGY

	_word_pool = _build_word_pool()
	_qte_timer = randf_range(QTE_INTERVAL.x, QTE_INTERVAL.y)

	var focus_short := String(GameData.word_by_id(_word_pool[0]).get("short", _word_pool[0].to_upper()))
	objective_label.text = "Shift %d - Testing: %s" % [GameState.stage_index + 1, focus_short]

	_refresh_hud()
	if Settings.tutorial_tips and not Settings.has_seen_workphase_intro:
		_show_intro()
	else:
		_begin_round()


func _compute_round_duration() -> float:
	return ROUND_DURATION


func _compute_mistype_penalty() -> int:
	var last := GameData.enemy_count() - 1
	if last <= 0:
		return MISTYPE_PENALTY_START
	var t := clampf(float(GameState.stage_index) / float(last), 0.0, 1.0)
	return int(round(lerpf(float(MISTYPE_PENALTY_START), float(MISTYPE_PENALTY_END), t)))


## A stage still short of unlocking every category drills only that one
## category (so Battle actually rewards you for practicing it); once
## everything is unlocked, WorkPhase mixes every unlocked category instead.
func _build_word_pool() -> Array:
	var stage := GameState.stage_index
	if stage < GameData.STAGE_FOCUS_WORD.size():
		return [GameData.STAGE_FOCUS_WORD[stage]]
	return GameState.unlocked_words.duplicate()


# ---------------------------------------------------------------- intro -----

func _show_intro() -> void:
	var lines: Array[String] = [
		"Type each target word exactly as shown.",
		"",
		"- Every completed word: +%d Energy and +%d Coins." % [BASE_WORD_ENERGY, COIN_PER_WORD],
		"- Type it with ZERO mistakes to build a Combo - each consecutive perfect word raises an Energy multiplier (up to x%.1f). One typo resets the streak." % COMBO_MAX_MULT,
		"- A mistyped character costs Patience. The penalty gets harsher as the run goes on: -%d on Stage 1, up to -%d by the final stage. This shift: -%d per mistake." % [MISTYPE_PENALTY_START, MISTYPE_PENALTY_END, _mistype_penalty],
		"- Distraction pop-ups will demand a quick reflex key - SPACE to duck, ALT or CTRL to swat it away, or ENTER to close a spam pop-up. React in time for +%d Patience; miss it and lose %d Patience." % [QTE_SUCCESS_PATIENCE, QTE_FAIL_PATIENCE_PENALTY],
		"- Survive the clock (%ds this shift) to head into the confrontation." % int(_round_duration),
		"",
		"The Energy you build up here carries straight into Battle as your starting resource - type well and you start the fight already ahead.",
	]
	intro_body.text = "\n".join(lines)
	intro_overlay.visible = true
	intro_start_button.pressed.connect(_on_intro_start_pressed)


func _on_intro_start_pressed() -> void:
	Settings.has_seen_workphase_intro = true
	Settings.save_settings()
	_begin_round()


func _begin_round() -> void:
	intro_overlay.visible = false
	_intro_visible = false
	_next_word()


func _process(delta: float) -> void:
	if _finished or _intro_visible:
		return
	_tick_timer(delta)
	_tick_qte(delta)


func _tick_timer(delta: float) -> void:
	_time_remaining = maxf(0.0, _time_remaining - delta)
	timer_bar.value = _time_remaining
	timer_value.text = "%ds" % int(ceil(_time_remaining))
	if _time_remaining <= 0.0:
		_finish_phase()


# ------------------------------------------------------------------- QTE ----

func _tick_qte(delta: float) -> void:
	if _qte_active:
		_qte_remaining -= delta
		qte_time_bar.value = _qte_remaining
		if _qte_remaining <= 0.0:
			_resolve_qte(false)
		return

	_qte_timer -= delta
	if _qte_timer <= 0.0:
		_start_qte()


func _start_qte() -> void:
	var qte: Dictionary = QTE_TYPES[randi() % QTE_TYPES.size()]
	_qte_keycode = int(qte["keycode"])

	_qte_active = true
	_qte_remaining = QTE_WINDOW
	qte_time_bar.max_value = QTE_WINDOW
	qte_time_bar.value = QTE_WINDOW
	qte_title.text = String(qte["prompt"])
	qte_key_label.text = String(qte["label"])
	qte_panel.visible = true
	qte_panel.modulate.a = 0.0
	create_tween().tween_property(qte_panel, "modulate:a", 1.0, 0.1)

	_spawn_distraction_label(DISTRACTION_TEXTS[randi() % DISTRACTION_TEXTS.size()])


func _resolve_qte(success: bool) -> void:
	_qte_active = false
	qte_panel.visible = false
	_qte_timer = randf_range(QTE_INTERVAL.x, QTE_INTERVAL.y)

	if success:
		GameState.add_patience(QTE_SUCCESS_PATIENCE)
		_flash_message("Deflected! +%d Patience" % QTE_SUCCESS_PATIENCE, Color(0.6, 1.0, 0.6))
	else:
		GameState.add_patience(-QTE_FAIL_PATIENCE_PENALTY)
		_hit_feedback(Color(0.9, 0.2, 0.2, 0.4), 10.0)
		_flash_message("-%d Patience" % QTE_FAIL_PATIENCE_PENALTY, Color(1.0, 0.45, 0.45))
		_check_burnout()

	_refresh_hud()


func _spawn_distraction_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var from_left := randf() < 0.5
	var y := randf_range(150.0, 360.0)
	label.position = Vector2(-320.0 if from_left else 1536.0 + 60.0, y)
	distraction_layer.add_child(label)

	var target_x := 1536.0 + 320.0 if from_left else -380.0
	var t := label.create_tween()
	t.tween_property(label, "position:x", target_x, DISTRACTION_FLOAT_DURATION).set_trans(Tween.TRANS_LINEAR)
	t.tween_callback(label.queue_free)


# --------------------------------------------------------------- typing -----

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_quit_to_menu()
		return

	if _finished or _intro_visible:
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if _qte_active:
		if key.physical_keycode == _qte_keycode:
			get_viewport().set_input_as_handled()
			_resolve_qte(true)
		return

	if RESERVED_KEYS.has(key.physical_keycode):
		get_viewport().set_input_as_handled()
		return

	if key.unicode == 0:
		return

	get_viewport().set_input_as_handled()
	_handle_typed_char(char(key.unicode).to_lower())


func _handle_typed_char(ch: String) -> void:
	if _target_word.is_empty():
		return
	var expected := _target_word.substr(_typed_index, 1).to_lower()
	if ch == expected:
		_typed_index += 1
		_update_word_display()
		if _typed_index >= _target_word.length():
			_complete_word()
	else:
		_register_mistake()


func _register_mistake() -> void:
	_word_mistake = true
	GameState.add_patience(-_mistype_penalty)
	_shake_word_label()
	_hit_feedback(Color(0.9, 0.2, 0.2, 0.22), 5.0)
	_flash_message("-%d Patience" % _mistype_penalty, Color(1.0, 0.5, 0.45))
	_refresh_hud()
	_check_burnout()


## Zero mistakes on this word extends the Combo streak and applies its
## multiplier; any mistake still lets the word count (it must be finished to
## move on), it just resets the streak and pays flat base Energy.
func _complete_word() -> void:
	var energy_gain := BASE_WORD_ENERGY
	var combo_mult := 1.0

	if _word_mistake:
		_combo_streak = 0
	else:
		_combo_streak += 1
		combo_mult = clampf(1.0 + float(_combo_streak - 1) * COMBO_STEP, 1.0, COMBO_MAX_MULT)
		energy_gain = int(round(BASE_WORD_ENERGY * combo_mult))

	GameState.add_energy(energy_gain)
	GameState.add_coins(COIN_PER_WORD)
	_word_quota[_target_category] = int(_word_quota.get(_target_category, 0)) + QUOTA_PER_WORD
	_words_typed += 1

	if _combo_streak > 1:
		combo_label.text = "Combo x%d  (Energy x%.2f)" % [_combo_streak, combo_mult]
	else:
		combo_label.text = "Words typed: %d" % _words_typed

	var flash_text := "+%d Energy, +%d Coins" % [energy_gain, COIN_PER_WORD]
	if combo_mult > 1.0:
		flash_text += "  (Combo x%d!)" % _combo_streak
	_flash_message(flash_text, Color(0.6, 1.0, 0.6))

	_refresh_hud()
	_next_word()


func _next_word() -> void:
	var category: String = _word_pool[randi() % _word_pool.size()]
	_target_category = category
	_target_word = _draw_word(category)
	_typed_index = 0
	_word_mistake = false

	category_label.text = String(GameData.word_by_id(category).get("short", category.to_upper()))
	_update_word_display()


## Draws from a per-category shuffle bag so words don't repeat within a run
## until the whole category has cycled through once; refills and reshuffles
## once a bag empties instead of ever running dry.
func _draw_word(category: String) -> String:
	var bag: Array = _word_bags.get(category, [])
	if bag.is_empty():
		bag = GameData.typing_words_for(category).duplicate()
		bag.shuffle()
		_word_bags[category] = bag
	return String(bag.pop_back()) if not bag.is_empty() else "please"


func _update_word_display() -> void:
	var done := _target_word.substr(0, _typed_index)
	var remaining := _target_word.substr(_typed_index)
	word_label.text = "[center][color=#7cfc9c]%s[/color][color=#9aa0aa]%s[/color][/center]" % [done, remaining]


func _shake_word_label() -> void:
	word_label.modulate = Color(1.0, 0.5, 0.5)
	var home := word_label.position
	var t := word_label.create_tween()
	t.tween_property(word_label, "modulate", Color.WHITE, 0.35)
	var shake := word_label.create_tween()
	for i: int in 4:
		shake.tween_property(word_label, "position", home + Vector2(randf_range(-6.0, 6.0), 0.0), 0.03)
	shake.tween_property(word_label, "position", home, 0.03)


# ------------------------------------------------------------------- hud ----

func _refresh_hud() -> void:
	patience_bar.value = GameState.patience
	patience_value.text = "%d / %d" % [maxi(GameState.patience, 0), GameState.MAX_PATIENCE]
	energy_bar.value = GameState.energy
	energy_value.text = "%d / %d" % [GameState.energy, GameState.MAX_ENERGY]


func _check_burnout() -> void:
	if GameState.patience <= 0:
		_burn_out()


# ---------------------------------------------------------------- outcome ---

func _finish_phase() -> void:
	_finished = true
	qte_panel.visible = false
	GameState.set_word_quota(_word_quota)

	var focus: String = _word_pool[0] if GameState.stage_index < GameData.STAGE_FOCUS_WORD.size() else ""
	if focus != "" and not GameState.is_word_unlocked(focus):
		GameState.unlock_word(focus)
		objective_label.text = "New skill unlocked: %s!" % String(GameData.word_by_id(focus).get("name", focus))
	else:
		objective_label.text = "Shift complete. Time for a word in private..."

	GameState.save_game()
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_property(flash, "color", Color(0, 0, 0, 1), 0.5)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(BATTLE_SCENE))


func _burn_out() -> void:
	_finished = true
	qte_panel.visible = false
	objective_label.text = "You burned out before the meeting. Go home."
	## No delete_save() here - the last stage-win checkpoint stays on disk so
	## GameOver's "Continue from Checkpoint" has something to load.
	var t := create_tween()
	t.tween_interval(1.1)
	t.tween_property(flash, "color", Color(0, 0, 0, 1), 0.6)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(GAME_OVER))


func _quit_to_menu() -> void:
	GameState.save_game()
	get_tree().change_scene_to_file(MAIN_MENU)


# ------------------------------------------------------------------- fx ----

func _flash_message(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(768.0 - 140.0, 640.0)
	add_child(label)

	var t := label.create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 50.0, 0.7)
	t.tween_property(label, "modulate:a", 0.0, 0.7)
	t.chain().tween_callback(label.queue_free)


## Shared by both penalty sources (mistyped character / failed QTE dodge) at
## different strengths. NOTE: this project has no audio bus/SFX assets wired
## up anywhere yet (Settings.gd only manages volume, no AudioStreamPlayer
## exists in any scene) - flash + shake stand in for the "audio cue"
## requirement until sound assets are added.
func _hit_feedback(color: Color, shake_strength: float) -> void:
	flash.color = color
	create_tween().tween_property(flash, "color:a", 0.0, 0.35)
	if Settings.screen_shake:
		var t := create_tween()
		for i: int in 4:
			t.tween_property(self, "position",
				Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength)),
				0.04)
		t.tween_property(self, "position", Vector2.ZERO, 0.04)
