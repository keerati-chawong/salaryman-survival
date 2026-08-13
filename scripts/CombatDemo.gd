extends Control

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const SAVE_PATH := "user://save.dat"

const BOSS_MAX := 800
const PLAYER_HP_MAX := 320
const PLAYER_MP_MAX := 120
const ITEM_MP_COST := 20

@onready var atk_btn: Button = $AtkButton
@onready var item_btn: Button = $ItemButton
@onready var def_btn: Button = $DefButton
@onready var run_btn: Button = $RunButton
@onready var back_btn: Button = $BackButton

@onready var boss_bar: ProgressBar = $BossHPBar
@onready var player_hp_bar: ProgressBar = $PlayerHPBar
@onready var player_mp_bar: ProgressBar = $PlayerMPBar

@onready var boss_hp_label: Label = $BossHPLabel
@onready var player_hp_label: Label = $PlayerHPLabel
@onready var player_mp_label: Label = $PlayerMPLabel
@onready var message_label: Label = $MessageLabel
@onready var background: TextureRect = $Background
@onready var flash_overlay: ColorRect = $FlashOverlay

var boss_hp := BOSS_MAX
var player_hp := PLAYER_HP_MAX
var player_mp := PLAYER_MP_MAX
var defending := false
var busy := false
var battle_over := false


func _ready() -> void:
	_refresh_ui(true)
	_set_message("What will you do?")
	background.pivot_offset = background.size / 2.0
	for b: Button in [atk_btn, item_btn, def_btn, run_btn]:
		b.mouse_entered.connect(_hover_overlay.bind(b, true))
		b.mouse_exited.connect(_hover_overlay.bind(b, false))


func _hover_overlay(b: Button, enter: bool) -> void:
	create_tween().tween_property(b, "self_modulate:a", 0.14 if enter else 0.0, 0.1)


func _shake(strength: float = 10.0, duration: float = 0.3) -> void:
	var tween := create_tween()
	var steps := 6
	for i: int in steps:
		var offset := Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		tween.tween_property(self, "position", offset, duration / steps)
	tween.tween_property(self, "position", Vector2.ZERO, duration / steps)


func _punch(amount: float = 1.04, duration: float = 0.18) -> void:
	var tween := create_tween()
	tween.tween_property(background, "scale", Vector2(amount, amount), duration * 0.35)
	tween.tween_property(background, "scale", Vector2.ONE, duration * 0.65)


func _flash(color: Color, peak_alpha: float = 0.35, duration: float = 0.35) -> void:
	flash_overlay.color = Color(color.r, color.g, color.b, peak_alpha)
	var tween := create_tween()
	tween.tween_property(flash_overlay, "color:a", 0.0, duration)


func _refresh_ui(instant := false) -> void:
	boss_hp_label.text = "%d / %d" % [max(boss_hp, 0), BOSS_MAX]
	player_hp_label.text = "%d / %d" % [max(player_hp, 0), PLAYER_HP_MAX]
	player_mp_label.text = "%d / %d" % [max(player_mp, 0), PLAYER_MP_MAX]
	if instant:
		boss_bar.value = boss_hp
		player_hp_bar.value = player_hp
		player_mp_bar.value = player_mp
	else:
		create_tween().tween_property(boss_bar, "value", max(boss_hp, 0), 0.3)
		create_tween().tween_property(player_hp_bar, "value", max(player_hp, 0), 0.3)
		create_tween().tween_property(player_mp_bar, "value", max(player_mp, 0), 0.3)


func _set_message(msg: String) -> void:
	message_label.text = msg


func _set_buttons_enabled(enabled: bool) -> void:
	atk_btn.disabled = not enabled
	item_btn.disabled = not enabled
	def_btn.disabled = not enabled
	run_btn.disabled = not enabled


func _on_atk_pressed() -> void:
	if busy or battle_over:
		return
	busy = true
	var dmg := randi_range(60, 110)
	boss_hp = max(boss_hp - dmg, 0)
	_set_message("You attack the manager for %d damage!" % dmg)
	_refresh_ui()
	_punch(1.05, 0.18)
	_flash(Color.WHITE, 0.3, 0.2)
	_shake(6.0, 0.2)
	await get_tree().create_timer(0.5).timeout
	await _boss_turn()


func _on_def_pressed() -> void:
	if busy or battle_over:
		return
	busy = true
	defending = true
	_set_message("You brace yourself, guarding against the next attack.")
	_flash(Color(0.3, 0.55, 0.9), 0.28, 0.3)
	_punch(0.97, 0.2)
	await get_tree().create_timer(0.5).timeout
	await _boss_turn()


func _on_item_pressed() -> void:
	if busy or battle_over:
		return
	if player_mp < ITEM_MP_COST:
		_set_message("Not enough MP for a coffee break! (needs %d MP)" % ITEM_MP_COST)
		return
	busy = true
	player_mp -= ITEM_MP_COST
	var heal := 50
	player_hp = min(player_hp + heal, PLAYER_HP_MAX)
	_set_message("You grab a coffee and recover %d HP." % heal)
	_refresh_ui()
	_flash(Color(0.5, 0.9, 0.5), 0.25, 0.35)
	_punch(1.02, 0.25)
	await get_tree().create_timer(0.5).timeout
	await _boss_turn()


func _on_run_pressed() -> void:
	if busy or battle_over:
		return
	busy = true
	battle_over = true
	_set_message("You clock out early and head for the exit...")
	_set_buttons_enabled(false)
	var tween := create_tween()
	tween.tween_property(self, "position:x", 120.0, 0.5)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.8)
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file(MAIN_MENU)


func _boss_turn() -> void:
	if boss_hp <= 0:
		await _win()
		return
	var dmg := randi_range(40, 70)
	if defending:
		dmg = int(dmg * 0.5)
	player_hp = max(player_hp - dmg, 0)
	var msg := "The manager dumps %d damage worth of paperwork on you!" % dmg
	if defending:
		msg += " (Guard reduced the damage)"
	_set_message(msg)
	defending = false
	_refresh_ui()
	_flash(Color(0.9, 0.2, 0.2), 0.32, 0.3)
	_shake(10.0, 0.3)
	await get_tree().create_timer(0.6).timeout
	if player_hp <= 0:
		await _lose()
	else:
		busy = false


func _win() -> void:
	battle_over = true
	_set_message("The Overworked Manager collapses! You survived the shift.")
	_set_buttons_enabled(false)
	_flash(Color(1.0, 0.85, 0.3), 0.4, 0.6)
	_punch(1.08, 0.5)
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file(MAIN_MENU)


func _lose() -> void:
	battle_over = true
	_set_message("You couldn't keep up with the workload... Game over.")
	_set_buttons_enabled(false)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_flash(Color(0.1, 0.1, 0.1), 0.6, 1.2)
	await get_tree().create_timer(1.8).timeout
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)
