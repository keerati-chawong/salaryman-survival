extends Control
## Work Phase. Collect documents to fill the work quota while insults fly in.
## Taking a hit builds Anger but costs Patience, so the player chooses how much
## of a beating to absorb before the confrontation.

const BATTLE_SCENE := "res://scenes/Battle.tscn"
const MAIN_MENU := "res://scenes/MainMenu.tscn"

const ARENA := Rect2(150.0, 210.0, 1240.0, 620.0)
const PLAYER_SPEED := 420.0
const QUOTA := 6

const INSULT_INTERVAL := Vector2(0.85, 1.6)
const INSULT_SPEED := Vector2(230.0, 360.0)
const INSULT_ANGER := 9
const INSULT_DAMAGE := 7

const DOC_ANGER := 4
const QTE_INTERVAL := Vector2(7.0, 11.0)
const QTE_WINDOW := 2.2
const QTE_FAIL_DAMAGE := 14
const QTE_KEYS := ["Q", "W", "E", "R", "A", "S", "D", "F"]

const INSULT_TEXTS := [
	"Did you even read the brief?",
	"Quick question...",
	"Can you stay late?",
	"Per my last email",
	"This should be easy",
	"Small change, sorry!",
	"Circling back on this",
	"Just a quick sync?",
]

@onready var player: TextureRect = $Player
@onready var docs_layer: Control = $DocsLayer
@onready var insult_layer: Control = $InsultLayer
@onready var patience_bar: ProgressBar = $HUD/Stats/PatienceRow/PatienceBar
@onready var patience_label: Label = $HUD/Stats/PatienceRow/PatienceValue
@onready var anger_bar: ProgressBar = $HUD/Stats/AngerRow/AngerBar
@onready var anger_label: Label = $HUD/Stats/AngerRow/AngerValue
@onready var quota_label: Label = $HUD/Stats/QuotaRow/QuotaValue
@onready var objective_label: Label = $HUD/Objective
@onready var hint_label: Label = $HUD/Hint
@onready var qte_panel: PanelContainer = $QtePanel
@onready var qte_key_label: Label = $QtePanel/Rows/KeyLabel
@onready var qte_timer_bar: ProgressBar = $QtePanel/Rows/TimeBar
@onready var flash: ColorRect = $Flash

var _docs_collected := 0
var _insult_timer := 0.0
var _qte_timer := 0.0
var _qte_active := false
var _qte_key := ""
var _qte_remaining := 0.0
var _finished := false
var _invulnerable := 0.0


func _ready() -> void:
	randomize()
	player.position = Vector2(ARENA.position.x + 80.0, ARENA.position.y + ARENA.size.y * 0.5)
	qte_panel.visible = false
	_insult_timer = randf_range(INSULT_INTERVAL.x, INSULT_INTERVAL.y)
	_qte_timer = randf_range(QTE_INTERVAL.x, QTE_INTERVAL.y)

	var enemy := GameState.current_enemy()
	objective_label.text = "Shift %d - %s is waiting for you" % [GameState.stage_index + 1, enemy["name"]]
	hint_label.text = "WASD / Arrows to move   -   grab %d documents   -   let the insults land to build Anger" % QUOTA

	for i: int in 4:
		_spawn_document()
	_refresh_hud()


func _refresh_hud() -> void:
	patience_bar.max_value = GameState.MAX_PATIENCE
	patience_bar.value = GameState.patience
	patience_label.text = "%d / %d" % [GameState.patience, GameState.MAX_PATIENCE]

	anger_bar.max_value = GameState.MAX_ANGER
	anger_bar.value = GameState.anger
	anger_label.text = "%d / %d" % [GameState.anger, GameState.MAX_ANGER]

	quota_label.text = "%d / %d" % [_docs_collected, QUOTA]


func _process(delta: float) -> void:
	if _finished:
		return

	_invulnerable = maxf(0.0, _invulnerable - delta)
	_move_player(delta)
	_tick_insults(delta)
	_tick_documents()
	_tick_qte(delta)


func _move_player(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length() > 0.0:
		player.position += dir.normalized() * PLAYER_SPEED * delta
		player.position.x = clampf(player.position.x, ARENA.position.x, ARENA.end.x - player.size.x)
		player.position.y = clampf(player.position.y, ARENA.position.y, ARENA.end.y - player.size.y)


# ------------------------------------------------------------- documents ----

func _spawn_document() -> void:
	var doc := Label.new()
	doc.text = "[  DOC  ]"
	doc.theme_type_variation = &"StatLabel"
	doc.add_theme_color_override("font_color", Color(0.95, 0.88, 0.6))
	doc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doc.position = Vector2(
		randf_range(ARENA.position.x + 60.0, ARENA.end.x - 180.0),
		randf_range(ARENA.position.y + 40.0, ARENA.end.y - 90.0)
	)
	docs_layer.add_child(doc)

	# Bound to doc, not self, so the infinite-loop bob tween is auto-killed
	# when the document is freed on pickup instead of erroring every frame
	# trying to animate a dangling reference (Godot detects this as an
	# "Infinite loop" tween error, which the Web export handles badly).
	var bob := doc.create_tween().set_loops()
	bob.tween_property(doc, "position:y", doc.position.y - 10.0, 0.7).set_trans(Tween.TRANS_SINE)
	bob.tween_property(doc, "position:y", doc.position.y, 0.7).set_trans(Tween.TRANS_SINE)


func _tick_documents() -> void:
	var reach := Rect2(player.position, player.size).grow(18.0)
	for doc: Node in docs_layer.get_children():
		var label := doc as Label
		if label == null:
			continue
		if reach.has_point(label.position + label.size * 0.5):
			_collect_document(label)


func _collect_document(doc: Label) -> void:
	_docs_collected += 1
	GameState.add_anger(DOC_ANGER)
	doc.queue_free()
	_popup("+%d Anger" % DOC_ANGER, doc.position, Color(0.95, 0.8, 0.4))
	_refresh_hud()

	if _docs_collected >= QUOTA:
		_finish()
	else:
		_spawn_document()


# --------------------------------------------------------------- insults ----

func _tick_insults(delta: float) -> void:
	_insult_timer -= delta
	if _insult_timer <= 0.0:
		_insult_timer = randf_range(INSULT_INTERVAL.x, INSULT_INTERVAL.y)
		_spawn_insult()

	var hit_box := Rect2(player.position, player.size).grow(-8.0)
	for node: Node in insult_layer.get_children():
		var label := node as Label
		if label == null:
			continue
		label.position.x += label.get_meta("vx", 0.0) * delta
		if label.position.x < ARENA.position.x - 400.0 or label.position.x > ARENA.end.x + 400.0:
			label.queue_free()
			continue
		if _invulnerable <= 0.0 and hit_box.intersects(Rect2(label.position, label.size)):
			_take_insult(label)


func _spawn_insult() -> void:
	var label := Label.new()
	label.text = INSULT_TEXTS[randi() % INSULT_TEXTS.size()]
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var from_left := randf() < 0.5
	var speed := randf_range(INSULT_SPEED.x, INSULT_SPEED.y)
	label.set_meta("vx", speed if from_left else -speed)
	label.position = Vector2(
		ARENA.position.x - 320.0 if from_left else ARENA.end.x + 60.0,
		randf_range(ARENA.position.y + 30.0, ARENA.end.y - 70.0)
	)
	insult_layer.add_child(label)


func _take_insult(label: Label) -> void:
	_invulnerable = 0.6
	GameState.add_anger(INSULT_ANGER)
	GameState.add_patience(-INSULT_DAMAGE)
	_popup("+%d Anger  -%d" % [INSULT_ANGER, INSULT_DAMAGE], player.position, Color(1.0, 0.5, 0.45))
	label.queue_free()
	_hit_feedback()
	_refresh_hud()
	if GameState.patience <= 0:
		_burn_out()


# ------------------------------------------------------------------- QTE ----

func _tick_qte(delta: float) -> void:
	if _qte_active:
		_qte_remaining -= delta
		qte_timer_bar.value = _qte_remaining
		if _qte_remaining <= 0.0:
			_end_qte(false)
		return

	_qte_timer -= delta
	if _qte_timer <= 0.0:
		_start_qte()


func _start_qte() -> void:
	_qte_active = true
	_qte_key = QTE_KEYS[randi() % QTE_KEYS.size()]
	_qte_remaining = QTE_WINDOW
	qte_key_label.text = _qte_key
	qte_timer_bar.max_value = QTE_WINDOW
	qte_timer_bar.value = QTE_WINDOW
	qte_panel.visible = true
	qte_panel.modulate.a = 0.0
	create_tween().tween_property(qte_panel, "modulate:a", 1.0, 0.12)


func _end_qte(success: bool) -> void:
	_qte_active = false
	_qte_timer = randf_range(QTE_INTERVAL.x, QTE_INTERVAL.y)
	qte_panel.visible = false

	if success:
		GameState.add_anger(6)
		_popup("Handled it!  +6 Anger", player.position, Color(0.6, 1.0, 0.6))
	else:
		GameState.add_patience(-QTE_FAIL_DAMAGE)
		_popup("Missed the deadline!  -%d" % QTE_FAIL_DAMAGE, player.position, Color(1.0, 0.45, 0.45))
		_hit_feedback()

	_refresh_hud()
	if GameState.patience <= 0:
		_burn_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		GameState.save_game()
		get_tree().change_scene_to_file(MAIN_MENU)
		return

	if not _qte_active:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if OS.get_keycode_string(key.physical_keycode).to_upper() == _qte_key:
			_end_qte(true)
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- fx -----

func _popup(text: String, at: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = at + Vector2(0.0, -30.0)
	add_child(label)

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 60.0, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8)
	t.chain().tween_callback(label.queue_free)


func _hit_feedback() -> void:
	flash.color = Color(0.9, 0.2, 0.2, 0.3)
	create_tween().tween_property(flash, "color:a", 0.0, 0.35)
	if Settings.screen_shake:
		var t := create_tween()
		for i: int in 4:
			t.tween_property(self, "position", Vector2(randf_range(-8, 8), randf_range(-8, 8)), 0.04)
		t.tween_property(self, "position", Vector2.ZERO, 0.04)


# ---------------------------------------------------------------- outcome ---

func _finish() -> void:
	_finished = true
	qte_panel.visible = false
	objective_label.text = "Quota met. Time for a word in private..."
	GameState.set_attack_quota(_docs_collected)
	GameState.save_game()
	var t := create_tween()
	t.tween_interval(0.9)
	t.tween_property(flash, "color", Color(0, 0, 0, 1), 0.5)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(BATTLE_SCENE))


func _burn_out() -> void:
	_finished = true
	qte_panel.visible = false
	objective_label.text = "You burned out before the meeting. Go home."
	GameState.delete_save()
	var t := create_tween()
	t.tween_interval(1.2)
	t.tween_property(flash, "color", Color(0, 0, 0, 1), 0.6)
	t.tween_callback(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
