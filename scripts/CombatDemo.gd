extends Control
## Turn-based demo battle. All HUD widgets are real Control nodes laid out by
## containers, so nothing can overlap regardless of text length or UI scale.

const MAIN_MENU := "res://scenes/MainMenu.tscn"

const BOSS_MAX := 800
const PLAYER_HP_MAX := 320
const PLAYER_MP_MAX := 120
const ITEM_MP_COST := 20
const ITEM_HEAL := 50

## Multiplier applied to the manager's damage, indexed by Settings.difficulty.
const DIFFICULTY_DAMAGE := [0.7, 1.0, 1.35]

@onready var atk_btn: TextureButton = $ActionGrid/AtkButton
@onready var item_btn: TextureButton = $ActionGrid/ItemButton
@onready var def_btn: TextureButton = $ActionGrid/DefButton
@onready var run_btn: TextureButton = $ActionGrid/RunButton

@onready var boss_bar: ProgressBar = $BossPanel/Rows/BarRow/BossHPBar
@onready var boss_hp_label: Label = $BossPanel/Rows/BarRow/BossHPLabel
@onready var player_hp_bar: ProgressBar = $PlayerPanel/Cols/Bars/HPRow/PlayerHPBar
@onready var player_hp_label: Label = $PlayerPanel/Cols/Bars/HPRow/PlayerHPLabel
@onready var player_mp_bar: ProgressBar = $PlayerPanel/Cols/Bars/MPRow/PlayerMPBar
@onready var player_mp_label: Label = $PlayerPanel/Cols/Bars/MPRow/PlayerMPLabel

@onready var message_label: Label = $MessagePanel/MessageLabel
@onready var damage_popup: Label = $DamagePopup
@onready var flash_overlay: ColorRect = $FlashOverlay
@onready var background: TextureRect = $Background

@onready var player_sprite: TextureRect = $Player
@onready var boss_sprite: TextureRect = $Boss
@onready var player_shadow: TextureRect = $PlayerShadow
@onready var boss_shadow: TextureRect = $BossShadow

## Sprite motion is split into a resting position, an action offset driven by
## tweens, and a continuous idle bob applied every frame, so a lunge and the
## breathing animation never fight over the same property.
var _player_home: Vector2
var _boss_home: Vector2
var _player_shadow_home: Vector2
var _boss_shadow_home: Vector2
var _player_offset := Vector2.ZERO
var _boss_offset := Vector2.ZERO
var _idle_time := 0.0
var _player_down := false
var _boss_down := false

var boss_hp := BOSS_MAX
var player_hp := PLAYER_HP_MAX
var player_mp := PLAYER_MP_MAX
var defending := false
var busy := false
var battle_over := false

var _hp_fill := StyleBoxFlat.new()
var _boss_fill := StyleBoxFlat.new()


func _ready() -> void:
	_setup_bar_styles()
	background.pivot_offset = background.size / 2.0
	_setup_sprites()
	_refresh(true)
	_set_message("What will you do?")
	if Settings.tutorial_tips:
		_set_message("What will you do?  (ATK to strike, DEF to guard, ITEM for coffee, RUN to flee)")


## Each bar owns its own fill StyleBox so we can recolour it as HP drops
## without mutating the shared theme resource.
func _setup_bar_styles() -> void:
	_boss_fill.bg_color = Color(0.78, 0.2, 0.24)
	_boss_fill.set_corner_radius_all(2)
	boss_bar.add_theme_stylebox_override("fill", _boss_fill)

	_hp_fill.bg_color = Color(0.78, 0.2, 0.24)
	_hp_fill.set_corner_radius_all(2)
	player_hp_bar.add_theme_stylebox_override("fill", _hp_fill)


func _setup_sprites() -> void:
	_player_home = player_sprite.position
	_boss_home = boss_sprite.position
	_player_shadow_home = player_shadow.position
	_boss_shadow_home = boss_shadow.position
	# pivot at the feet so squash, lean and falling all rotate about the ground
	player_sprite.pivot_offset = Vector2(player_sprite.size.x * 0.5, player_sprite.size.y)
	boss_sprite.pivot_offset = Vector2(boss_sprite.size.x * 0.5, boss_sprite.size.y)


func _process(delta: float) -> void:
	_idle_time += delta

	var player_bob := 0.0 if _player_down else sin(_idle_time * 1.9) * 4.0
	player_sprite.position = _player_home + _player_offset + Vector2(0.0, player_bob)
	player_shadow.position = _player_shadow_home + Vector2(_player_offset.x, 0.0)

	var boss_bob := 0.0 if _boss_down else sin(_idle_time * 1.4 + 1.0) * 3.0
	boss_sprite.position = _boss_home + _boss_offset + Vector2(0.0, boss_bob)
	boss_shadow.position = _boss_shadow_home + Vector2(_boss_offset.x, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ character fx --

func _tint(sprite: TextureRect, color: Color, duration: float) -> void:
	sprite.modulate = color
	create_tween().tween_property(sprite, "modulate", Color.WHITE, duration)


func _squash(sprite: TextureRect, amount: Vector2, duration: float) -> void:
	var t := create_tween()
	t.tween_property(sprite, "scale", amount, duration * 0.4).set_trans(Tween.TRANS_QUAD)
	t.tween_property(sprite, "scale", Vector2.ONE, duration * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Dash toward the opponent, hang for the impact frame, then slide home.
func _lunge(who: String, distance: float, lift: float) -> void:
	var prop := "_player_offset" if who == "player" else "_boss_offset"
	var sprite := player_sprite if who == "player" else boss_sprite
	var t := create_tween()
	t.tween_property(self, prop, Vector2(distance, lift), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(sprite, "scale", Vector2(1.06, 0.96), 0.18)
	t.tween_interval(0.14)
	t.tween_property(self, prop, Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(sprite, "scale", Vector2.ONE, 0.3)


## Knock the victim back from the blow and tint them red.
func _recoil(who: String, distance: float) -> void:
	var prop := "_player_offset" if who == "player" else "_boss_offset"
	var sprite := player_sprite if who == "player" else boss_sprite
	_tint(sprite, Color(1.0, 0.42, 0.42), 0.45)
	var t := create_tween()
	t.tween_property(self, prop, Vector2(distance, 0.0), 0.09).set_trans(Tween.TRANS_QUAD)
	t.tween_property(self, prop, Vector2.ZERO, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Topple a defeated fighter onto the floor and fade them out.
func _collapse(who: String) -> void:
	var sprite := player_sprite if who == "player" else boss_sprite
	var shadow := player_shadow if who == "player" else boss_shadow
	if who == "player":
		_player_down = true
	else:
		_boss_down = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(sprite, "rotation", deg_to_rad(-72.0 if who == "player" else 68.0), 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "modulate:a", 0.25, 0.9)
	t.tween_property(shadow, "modulate:a", 0.0, 0.7)


# ------------------------------------------------------------------- ui -----

func _refresh(instant := false) -> void:
	boss_hp_label.text = "%d / %d" % [maxi(boss_hp, 0), BOSS_MAX]
	player_hp_label.text = "%d / %d" % [maxi(player_hp, 0), PLAYER_HP_MAX]
	player_mp_label.text = "%d / %d" % [maxi(player_mp, 0), PLAYER_MP_MAX]

	if instant:
		boss_bar.value = boss_hp
		player_hp_bar.value = player_hp
		player_mp_bar.value = player_mp
	else:
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(boss_bar, "value", maxf(boss_hp, 0), 0.3)
		t.tween_property(player_hp_bar, "value", maxf(player_hp, 0), 0.3)
		t.tween_property(player_mp_bar, "value", maxf(player_mp, 0), 0.3)

	_recolour(_hp_fill, float(player_hp) / PLAYER_HP_MAX)
	_recolour(_boss_fill, float(boss_hp) / BOSS_MAX)


## Red when healthy, amber under 50%, deep red under 25%.
func _recolour(box: StyleBoxFlat, ratio: float) -> void:
	if ratio <= 0.25:
		box.bg_color = Color(0.55, 0.1, 0.13)
	elif ratio <= 0.5:
		box.bg_color = Color(0.85, 0.45, 0.15)
	else:
		box.bg_color = Color(0.78, 0.2, 0.24)


func _set_message(msg: String) -> void:
	message_label.text = msg


func _set_actions_enabled(on: bool) -> void:
	for b: TextureButton in [atk_btn, item_btn, def_btn, run_btn]:
		b.disabled = not on


func _popup_damage(amount: int, at_top: bool) -> void:
	if not Settings.show_damage:
		return
	damage_popup.text = "-%d" % amount
	damage_popup.position = Vector2(950 if at_top else 300, 300 if at_top else 560)
	damage_popup.modulate.a = 1.0
	var start_y := damage_popup.position.y
	damage_popup.position.y = start_y
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(damage_popup, "position:y", start_y - 60.0, 0.7)
	t.tween_property(damage_popup, "modulate:a", 0.0, 0.7)


func _shake(strength: float, duration: float) -> void:
	if not Settings.screen_shake:
		return
	var t := create_tween()
	var steps := 6
	for i: int in steps:
		t.tween_property(self, "position",
			Vector2(randf_range(-strength, strength), randf_range(-strength, strength)),
			duration / steps)
	t.tween_property(self, "position", Vector2.ZERO, duration / steps)


func _punch(amount: float, duration: float) -> void:
	var t := create_tween()
	t.tween_property(background, "scale", Vector2(amount, amount), duration * 0.35)
	t.tween_property(background, "scale", Vector2.ONE, duration * 0.65)


func _flash(color: Color, peak: float, duration: float) -> void:
	flash_overlay.color = Color(color.r, color.g, color.b, peak)
	create_tween().tween_property(flash_overlay, "color:a", 0.0, duration)


# --------------------------------------------------------------- actions ----

func _on_atk_pressed() -> void:
	if busy or battle_over:
		return
	busy = true
	var dmg := randi_range(60, 110)
	boss_hp = maxi(boss_hp - dmg, 0)
	_set_message("You attack the manager for %d damage!" % dmg)

	# 330px stops the sprite just short of the action buttons on the right
	_lunge("player", 330.0, -30.0)
	await get_tree().create_timer(0.22).timeout

	_refresh()
	_popup_damage(dmg, true)
	_recoil("boss", 34.0)
	_punch(1.05, 0.18)
	_flash(Color.WHITE, 0.3, 0.2)
	_shake(6.0, 0.2)

	await get_tree().create_timer(0.55).timeout
	await _boss_turn()


func _on_def_pressed() -> void:
	if busy or battle_over:
		return
	busy = true
	defending = true
	_set_message("You brace yourself, guarding against the next attack.")
	_squash(player_sprite, Vector2(1.1, 0.88), 0.4)
	_tint(player_sprite, Color(0.62, 0.78, 1.25), 0.5)
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
	player_hp = mini(player_hp + ITEM_HEAL, PLAYER_HP_MAX)
	_set_message("You grab a coffee and recover %d HP." % ITEM_HEAL)
	_refresh()
	# a quick hop as the caffeine lands
	var hop := create_tween()
	hop.tween_property(self, "_player_offset", Vector2(0.0, -34.0), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hop.tween_property(self, "_player_offset", Vector2.ZERO, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tint(player_sprite, Color(0.6, 1.25, 0.7), 0.5)
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
	_set_actions_enabled(false)
	# the salaryman bolts off-screen to the left before the scene fades
	var run := create_tween()
	run.tween_property(self, "_player_offset", Vector2(-620.0, 0.0), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(player_sprite, "modulate:a", 0.0, 0.7)
	t.tween_property(player_shadow, "modulate:a", 0.0, 0.7)
	t.tween_property(self, "modulate:a", 0.0, 0.95)
	await get_tree().create_timer(1.1).timeout
	_leave()


func _boss_turn() -> void:
	if boss_hp <= 0:
		await _win()
		return

	var scale: float = DIFFICULTY_DAMAGE[clampi(Settings.difficulty, 0, 2)]
	var dmg := int(randi_range(40, 70) * scale)
	if defending:
		dmg = int(dmg * 0.5)
	player_hp = maxi(player_hp - dmg, 0)

	var msg := "The manager dumps %d damage worth of paperwork on you!" % dmg
	if defending:
		msg += "  (Guard halved it)"
	_set_message(msg)

	_lunge("boss", -400.0, -10.0)
	await get_tree().create_timer(0.22).timeout

	_refresh()
	_popup_damage(dmg, false)
	if defending:
		_squash(player_sprite, Vector2(1.12, 0.86), 0.35)
		_tint(player_sprite, Color(0.7, 0.85, 1.3), 0.4)
	else:
		_recoil("player", -40.0)
	defending = false
	_flash(Color(0.9, 0.2, 0.2), 0.32, 0.3)
	_shake(10.0, 0.3)

	await get_tree().create_timer(0.65).timeout
	if player_hp <= 0:
		await _lose()
	else:
		busy = false


func _win() -> void:
	battle_over = true
	_set_message("The Overworked Manager collapses! You survived the shift.")
	_set_actions_enabled(false)
	_collapse("boss")
	_flash(Color(1.0, 0.85, 0.3), 0.4, 0.6)
	_punch(1.08, 0.5)
	await get_tree().create_timer(1.9).timeout
	_leave()


func _lose() -> void:
	battle_over = true
	_set_message("You couldn't keep up with the workload... Game over.")
	_set_actions_enabled(false)
	Settings.delete_save()
	_collapse("player")
	_flash(Color(0.1, 0.1, 0.1), 0.6, 1.2)
	await get_tree().create_timer(2.1).timeout
	_leave()


func _leave() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)


func _on_back_pressed() -> void:
	_leave()
