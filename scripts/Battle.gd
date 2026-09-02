extends Control
## Confrontation Phase. Four word types are checked against the current enemy's
## weakness table; each enemy answers with its own signature skill.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const PROMOTION := "res://scenes/Promotion.tscn"
const ENDING := "res://scenes/Ending.tscn"
const WORK_PHASE := "res://scenes/WorkPhase.tscn"
const GAME_OVER := "res://scenes/GameOver.tscn"

## Energy regained whenever the enemy lands a hit, per the design's
## "energy builds when you are insulted" rule.
const ENERGY_ON_HIT := 12

## Floor for word uses this fight, applied even if WorkPhase's typing quota
## handed over fewer than this (or nothing at all, e.g. an old save). Scaled
## by how effective that word is against THIS enemy (see _base_uses_for()):
## a word this enemy resists barely gets any free uses since spamming it is
## already a bad idea, while a word that's a weakness gets a generous floor
## so it can actually carry the fight even off a weak typing run.
const BASE_USES_BY_EFFECTIVENESS := {
	"immune": 1,
	"resisted": 2,
	"neutral": 2,
	"weakness": 3,
	"critical": 4,
}
## Hard ceiling on a word's uses this fight regardless of how high WorkPhase's
## typing quota pushes it - a very good typing run shouldn't be able to make
## a word effectively unlimited.
const WORD_USES_CAP := 15
const APOLOGIZE_COST := 30
const APOLOGIZE_BONUS_USES := 2

@onready var enemy_sprite: TextureRect = $Enemy
@onready var enemy_shadow: TextureRect = $EnemyShadow
@onready var player_sprite: TextureRect = $Player
@onready var player_shadow: TextureRect = $PlayerShadow

@onready var enemy_name: Label = $EnemyPanel/Rows/TitleRow/EnemyName
@onready var enemy_role: Label = $EnemyPanel/Rows/TitleRow/EnemyRole
@onready var enemy_bar: ProgressBar = $EnemyPanel/Rows/BarRow/EnemyHPBar
@onready var enemy_hp_label: Label = $EnemyPanel/Rows/BarRow/EnemyHPLabel

@onready var patience_bar: ProgressBar = $PlayerPanel/Cols/Bars/HPRow/PatienceBar
@onready var patience_label: Label = $PlayerPanel/Cols/Bars/HPRow/PatienceLabel
@onready var energy_bar: ProgressBar = $PlayerPanel/Cols/Bars/MPRow/EnergyBar
@onready var energy_label: Label = $PlayerPanel/Cols/Bars/MPRow/EnergyLabel
@onready var rank_label: Label = $PlayerPanel/Cols/Bars/BottomRow/RankLabel
@onready var coin_label: Label = $PlayerPanel/Cols/Bars/BottomRow/CoinLabel

@onready var word_grid: GridContainer = $ActionPanel/Rows/WordGrid
@onready var item_row: HBoxContainer = $ActionPanel/Rows/ItemRow
@onready var bite_button: Button = $ActionPanel/Rows/BiteButton
@onready var hint_label: Label = $ActionPanel/Rows/HintLabel

const BITE_ENERGY := 15
@onready var message_label: Label = $MessagePanel/MessageLabel
@onready var popup_label: Label = $DamagePopup
@onready var flash_overlay: ColorRect = $FlashOverlay
@onready var background: TextureRect = $Background

var _enemy: Dictionary = {}
var _enemy_hp := 0
var _enemy_max := 0

var _busy := false
var _over := false
## Headphones halve the next hit for this many of the enemy's turns (only
## ticks down on a turn that actually lands damage - see _consume_guard()).
var _guard_turns_left := 0
var _silenced := ""
var _interrupted := false
var _enemy_guarding := false

## Sandwich's percentage guard - stacks on top of headphones' halving (see
## _consume_guard_pct()), independently tracked, same "only ticks down on a
## turn that actually lands damage" rule.
var _guard_pct_amount := 0.0
var _guard_pct_turns_left := 0
## Apple's on-hit Energy bonus (see _apply_energy_on_hit_bonus()).
var _energy_on_hit_bonus := 0
var _energy_on_hit_turns_left := 0
## Banana/Cola/Energy Bar's one-shot next-attack buffs, consumed the next
## time a word attack actually lands damage (see _on_word_pressed()) - not
## spent on an attack an enemy guard stance fully blocks.
var _next_atk_pct := 0.0
var _next_atk_flat := 0

var _word_buttons: Dictionary = {}
var _word_uses: Dictionary = {}
var _word_max_uses: Dictionary = {}
var _apologize_button: Button

var _backpack_button: Button
var _backpack_overlay: Control
var _backpack_hint_label: Label
## id -> {"btn": Button, "icon": TextureRect, "count": Label}
var _backpack_slots: Dictionary = {}

var _pause: PauseOverlay

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


func _ready() -> void:
	randomize()
	SoundManager.play_music("battle")
	_enemy = GameState.current_enemy()
	_enemy_max = int(_enemy["hp"])
	_enemy_hp = _enemy_max

	_init_word_uses()
	_setup_enemy_visuals()
	_setup_bars()
	_build_word_buttons()
	_build_backpack_button()
	_build_backpack_overlay()
	_build_apologize_button()
	bite_button.mouse_entered.connect(_show_hint.bind("A free way to keep going when you're out of Energy and items."))
	bite_button.mouse_exited.connect(_clear_hint)
	_setup_sprites()

	## Must exist before the first _refresh(true) below - _refresh_buttons()
	## reads _pause.is_open() to keep every action button disabled while paused.
	_pause = PauseOverlay.attach(self, _quit_to_menu)
	_pause.state_changed.connect(_on_pause_state_changed)

	_refresh(true)

	_say("%s\n%s" % [String(_enemy["intro"]), "Pick your words carefully."])


## Only words unlocked so far (GameState.unlocked_words - "Polite" from the
## start, the rest unlocked one per stage by WorkPhase's typing test) are
## usable at all. Each unlocked word's uses this fight come from how many of
## that category were typed correctly in WorkPhase (GameState.word_quota),
## floored at a per-enemy amount based on that word's effectiveness this
## fight (see _base_uses_for()) so an empty/old save can't hard-lock a fight,
## and capped at WORD_USES_CAP so a very strong typing run can't make a word
## effectively unlimited.
func _init_word_uses() -> void:
	var mult_table: Dictionary = _enemy.get("mult", {})
	for word: Dictionary in GameData.WORDS:
		var id := String(word["id"])
		if not GameState.is_word_unlocked(id):
			continue
		var mult := float(mult_table.get(id, 1.0))
		var base := _base_uses_for(mult)
		var uses := mini(maxi(int(GameState.word_quota.get(id, 0)), base), WORD_USES_CAP)
		_word_uses[id] = uses
		_word_max_uses[id] = uses


## Mirrors GameData.effectiveness_label()'s thresholds so the floor tracks
## the same "immune/resisted/neutral/weakness/critical" bands shown in the
## damage popup and Promotion's reaction chart.
func _base_uses_for(mult: float) -> int:
	if is_equal_approx(mult, GameData.IMMUNE):
		return int(BASE_USES_BY_EFFECTIVENESS["immune"])
	if mult >= GameData.CRITICAL_AT:
		return int(BASE_USES_BY_EFFECTIVENESS["critical"])
	if mult > 1.0:
		return int(BASE_USES_BY_EFFECTIVENESS["weakness"])
	if mult < 1.0:
		return int(BASE_USES_BY_EFFECTIVENESS["resisted"])
	return int(BASE_USES_BY_EFFECTIVENESS["neutral"])


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

	_hp_fill.bg_color = Color(0.78, 0.2, 0.24)
	_hp_fill.set_corner_radius_all(2)
	patience_bar.add_theme_stylebox_override("fill", _hp_fill)

	enemy_bar.max_value = _enemy_max
	patience_bar.max_value = GameState.MAX_PATIENCE
	energy_bar.max_value = GameState.MAX_ENERGY


func _setup_sprites() -> void:
	_player_home = player_sprite.position
	_enemy_home = enemy_sprite.position
	_player_shadow_home = player_shadow.position
	_enemy_shadow_home = enemy_shadow.position
	player_sprite.pivot_offset = Vector2(player_sprite.size.x * 0.5, player_sprite.size.y)
	enemy_sprite.pivot_offset = Vector2(enemy_sprite.size.x * 0.5, enemy_sprite.size.y)


# ------------------------------------------------------------ ui building ---

## Locked words (GameState.unlocked_words) don't get a button at all - there's
## nothing useful to show for a skill you haven't earned yet.
func _build_word_buttons() -> void:
	for word: Dictionary in GameData.WORDS:
		var id := String(word["id"])
		if not GameState.is_word_unlocked(id):
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 74)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.text = "%s\n%d Energy" % [String(word["short"]), int(word["cost"])]
		btn.add_theme_color_override("font_color", word["color"])
		btn.pressed.connect(_on_word_pressed.bind(id))
		# a shared hint line avoids tooltips popping over neighbouring buttons
		btn.mouse_entered.connect(_show_hint.bind("%s - %s" % [String(word["name"]), String(word["blurb"])]))
		btn.mouse_exited.connect(_clear_hint)
		word_grid.add_child(btn)
		_word_buttons[id] = btn


## Nine items is too many to lay out inline in ItemRow, so it holds a single
## button that opens the backpack overlay instead.
func _build_backpack_button() -> void:
	_backpack_button = Button.new()
	_backpack_button.custom_minimum_size = Vector2(0, 52)
	_backpack_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backpack_button.pressed.connect(_open_backpack)
	_backpack_button.mouse_entered.connect(_show_hint.bind("Open your backpack to use a snack, drink, or your headphones."))
	_backpack_button.mouse_exited.connect(_clear_hint)
	item_row.add_child(_backpack_button)


## A modal grid of every item: a dim full-screen button (click outside to
## close) behind a panel of icon slots, built once and toggled with
## _open_backpack()/_close_backpack() instead of rebuilt each time.
func _build_backpack_overlay() -> void:
	_backpack_overlay = Control.new()
	_backpack_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backpack_overlay.visible = false
	add_child(_backpack_overlay)

	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_style := StyleBoxFlat.new()
	dim_style.bg_color = Color(0, 0, 0, 0.6)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		dim.add_theme_stylebox_override(state, dim_style)
	dim.pressed.connect(_close_backpack)
	_backpack_overlay.add_child(dim)

	var panel := PanelContainer.new()
	panel.position = Vector2(300, 210)
	panel.size = Vector2(936, 560)
	_backpack_overlay.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	panel.add_child(rows)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "BACKPACK"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(90, 40)
	close_button.pressed.connect(_close_backpack)
	header.add_child(close_button)
	rows.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	rows.add_child(grid)

	for id: String in GameData.ITEMS:
		grid.add_child(_build_backpack_slot(id, GameData.ITEMS[id]))

	## The overlay is drawn on top of ActionPanel/HintLabel, so hovering a
	## slot needs its own visible hint line instead of the hidden one behind it.
	_backpack_hint_label = Label.new()
	_backpack_hint_label.theme_type_variation = &"SmallLabel"
	_backpack_hint_label.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
	_backpack_hint_label.text = "Hover an item to see what it does."
	_backpack_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_backpack_hint_label)


## A slot is composed by hand (icon + count Label overlaid on a plain Button)
## rather than using Button.icon - at this size Button's built-in icon+text
## layout squeezes the icon down to an unreadable sliver.
func _build_backpack_slot(id: String, item: Dictionary) -> Control:
	const SLOT_SIZE := Vector2(96, 108)

	var btn := Button.new()
	btn.custom_minimum_size = SLOT_SIZE
	btn.pressed.connect(_on_backpack_item_pressed.bind(id))
	var hint := "%s - %s" % [String(item["name"]), String(item["blurb"])]
	btn.mouse_entered.connect(func() -> void: _backpack_hint_label.text = hint)
	btn.mouse_exited.connect(func() -> void: _backpack_hint_label.text = "Hover an item to see what it does.")

	## expand_mode/stretch_mode must be set BEFORE the texture: assigning the
	## texture while still on the default EXPAND_KEEP_SIZE locks the node's
	## minimum size to the full source image, and the size set below (a plain
	## Button isn't a Container, so nothing re-lays this out afterward) gets
	## clamped straight back up to that oversized minimum.
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(item["icon"]))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((SLOT_SIZE.x - 56.0) * 0.5, 10.0)
	icon.size = Vector2(56, 56)
	btn.add_child(icon)

	var count_label := Label.new()
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.theme_type_variation = &"SmallLabel"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.position = Vector2(0, SLOT_SIZE.y - 28.0)
	count_label.size = Vector2(SLOT_SIZE.x, 24)
	btn.add_child(count_label)

	_backpack_slots[id] = {"btn": btn, "icon": icon, "count": count_label}
	return btn


func _open_backpack() -> void:
	if _busy or _over or _pause.is_open():
		return
	SoundManager.play_sfx("click")
	_backpack_overlay.visible = true
	_refresh_backpack()


func _close_backpack() -> void:
	SoundManager.play_sfx("click")
	_backpack_overlay.visible = false
	_clear_hint()


func _on_backpack_item_pressed(id: String) -> void:
	_close_backpack()
	_on_item_pressed(id)


func _refresh_backpack() -> void:
	for id: String in _backpack_slots:
		var slot: Dictionary = _backpack_slots[id]
		var btn: Button = slot["btn"]
		var icon: TextureRect = slot["icon"]
		var count_label: Label = slot["count"]
		var count := GameState.item_count(id)
		count_label.text = "x%d" % count
		var blocked := _over or _busy or _pause.is_open() or count <= 0
		btn.disabled = blocked
		icon.modulate = Color(1, 1, 1, 1) if not blocked else Color(1, 1, 1, 0.35)


## Hidden until every word is out of uses - the crisis fallback: trade
## Energy to keep the fight going instead of being locked out entirely.
## Lives in the word grid (styled like a word button) so it drops into the
## empty slot next to the unlocked words instead of overflowing ActionPanel.
func _build_apologize_button() -> void:
	_apologize_button = Button.new()
	_apologize_button.text = "APOLOGIZE\n-%d Energy" % APOLOGIZE_COST
	_apologize_button.custom_minimum_size = Vector2(0, 74)
	_apologize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apologize_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_apologize_button.add_theme_color_override("font_color", Color(0.95, 0.78, 0.5))
	_apologize_button.visible = false
	_apologize_button.pressed.connect(_on_apologize_pressed)
	_apologize_button.mouse_entered.connect(_show_hint.bind("Only appears when every word is out of uses. Costs %d Energy for +%d uses on every word - keeps you in the fight." % [APOLOGIZE_COST, APOLOGIZE_BONUS_USES]))
	_apologize_button.mouse_exited.connect(_clear_hint)
	word_grid.add_child(_apologize_button)


func _show_hint(text: String) -> void:
	hint_label.text = text


func _clear_hint() -> void:
	hint_label.text = "Hover a line to see what it does."


func _refresh_buttons() -> void:
	var out_of_words := true
	for id: String in _word_buttons:
		var word := GameData.word_by_id(id)
		var btn: Button = _word_buttons[id]
		var uses := int(_word_uses.get(id, 0))
		if uses > 0:
			out_of_words = false
		var blocked := _over or _busy or _pause.is_open() or _silenced == id or uses <= 0 or GameState.energy < int(word["cost"])
		btn.disabled = blocked
		var suffix := "  (silenced)" if _silenced == id else ""
		btn.text = "%s%s  (%d/%d)\n%d Energy" % [
			String(word["short"]), suffix, uses, int(_word_max_uses.get(id, uses)), int(word["cost"]),
		]

	var total_items := 0
	for id: String in GameData.ITEMS:
		total_items += GameState.item_count(id)
	_backpack_button.text = "Open Backpack  (%d items)" % total_items
	_backpack_button.disabled = _over or _busy or _pause.is_open()
	if _backpack_overlay.visible:
		_refresh_backpack()

	bite_button.disabled = _over or _busy or _pause.is_open()

	_apologize_button.visible = out_of_words
	_apologize_button.disabled = _over or _busy or _pause.is_open() or GameState.energy < APOLOGIZE_COST


## Keeps every action button's disabled state in sync the instant the pause
## panel opens/closes, rather than waiting for the next unrelated refresh -
## mirrors WorkPhase.gd's _on_pause_state_changed().
func _on_pause_state_changed(_is_open: bool) -> void:
	_refresh_buttons()


# ------------------------------------------------------------------ state ---

func _refresh(instant := false) -> void:
	enemy_hp_label.text = "%d / %d" % [maxi(_enemy_hp, 0), _enemy_max]
	patience_label.text = "%d / %d" % [maxi(GameState.patience, 0), GameState.MAX_PATIENCE]
	energy_label.text = "%d / %d" % [GameState.energy, GameState.MAX_ENERGY]
	rank_label.text = "Rank: %s" % GameState.rank
	coin_label.text = "%d coins" % GameState.coins

	if instant:
		enemy_bar.value = _enemy_hp
		patience_bar.value = GameState.patience
		energy_bar.value = GameState.energy
	else:
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(enemy_bar, "value", maxf(_enemy_hp, 0), 0.3)
		t.tween_property(patience_bar, "value", maxf(GameState.patience, 0), 0.3)
		t.tween_property(energy_bar, "value", GameState.energy, 0.3)

	_recolour(_hp_fill, float(GameState.patience) / GameState.MAX_PATIENCE)
	_recolour(_enemy_fill, float(_enemy_hp) / _enemy_max)
	_refresh_buttons()


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
	if _busy or _over or _pause.is_open():
		return
	var word := GameData.word_by_id(id)
	if int(_word_uses.get(id, 0)) <= 0:
		_say("You're out of ways to say that this fight.")
		return
	if not GameState.spend_energy(int(word["cost"])):
		_say("Not enough Energy for that one.")
		return

	_busy = true
	_word_uses[id] = int(_word_uses[id]) - 1
	_refresh_buttons()

	## The enemy telegraphed a guard stance last turn - the line is spent
	## for nothing, same as GameData's guard_chance comment describes.
	if _enemy_guarding:
		_enemy_guarding = false
		var blocked_lines: Array = word["lines"]
		_say('"%s"' % String(blocked_lines[randi() % blocked_lines.size()]))
		_lunge("player", 330.0, -30.0)
		await get_tree().create_timer(0.22).timeout
		SoundManager.play_sfx("block")
		_popup("BLOCKED", true, Color(0.6, 0.75, 1.0))
		_say("%s saw that coming. Fully blocked - the line doesn't land." % String(_enemy["name"]))
		await get_tree().create_timer(0.6).timeout
		await _enemy_turn()
		return

	var mult := float((_enemy["mult"] as Dictionary).get(id, 1.0))
	var base := int(word["power"] * randf_range(0.85, 1.15))
	if _interrupted:
		base = int(base * 0.6)
		_interrupted = false
	var dealt := int(base * mult)
	var buffed := false
	if not is_equal_approx(mult, GameData.IMMUNE) and (_next_atk_flat > 0 or _next_atk_pct > 0.0):
		dealt = int((dealt + _next_atk_flat) * (1.0 + _next_atk_pct))
		_next_atk_flat = 0
		_next_atk_pct = 0.0
		buffed = true

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
		SoundManager.play_sfx("player_hit")
		var parts: Array[String] = ["-%d" % dealt]
		if label != "":
			parts.append(label)
		if buffed:
			parts.append("Boosted!")
		_popup(" ".join(parts), true, GameData.effectiveness_color(mult))
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
	if _busy or _over or _pause.is_open():
		return

	SoundManager.play_sfx("click")
	_busy = true
	_refresh_buttons()

	GameState.add_energy(BITE_ENERGY)
	_say("You bite your tongue and swallow it. The energy stays in the tank.")
	_tint(player_sprite, Color(0.85, 0.85, 0.85), 0.4)
	_popup("+%d Energy" % BITE_ENERGY, false, Color(0.95, 0.66, 0.25))

	_refresh()
	await get_tree().create_timer(0.5).timeout
	await _enemy_turn()


## Crisis fallback once every word is out of uses: burn Energy to keep the
## fight going rather than being stuck with only Bite/items. Guarded by
## spend_energy() rather than a flat subtract since - unlike the old Patience
## cost - going below the amount actually blocks the action instead of just
## clamping toward a loss.
##
## This refills uses back toward each word's existing max (set once in
## _init_word_uses()) - it does NOT raise the max itself. Bumping both
## together let repeated Apologizing inflate a word's ceiling indefinitely
## (e.g. 0/2 -> 2/4 -> 4/6...), which defeated the point of WORD_USES_CAP.
func _on_apologize_pressed() -> void:
	if _busy or _over or _pause.is_open():
		return
	if not GameState.spend_energy(APOLOGIZE_COST):
		return

	SoundManager.play_sfx("click")
	_busy = true
	_refresh_buttons()

	for id: String in _word_uses:
		var cap := int(_word_max_uses.get(id, 0))
		_word_uses[id] = mini(int(_word_uses[id]) + APOLOGIZE_BONUS_USES, cap)
	_say("You apologise for existing. It buys you a couple more lines on everything.")
	_tint(player_sprite, Color(0.8, 0.8, 0.85), 0.4)
	_popup("-%d Energy, +%d uses each" % [APOLOGIZE_COST, APOLOGIZE_BONUS_USES], false, Color(0.85, 0.6, 0.6))

	_refresh()
	await get_tree().create_timer(0.5).timeout
	await _enemy_turn()


func _on_item_pressed(id: String) -> void:
	if _busy or _over or _pause.is_open():
		return
	if not GameState.consume_item(id):
		return

	SoundManager.play_sfx("item_use")
	_busy = true
	_refresh_buttons()

	var item: Dictionary = GameData.ITEMS[id]
	var name := String(item["name"])
	var blurb := String(item["blurb"])
	match String(item["effect"]):
		"energy":
			GameState.add_energy(int(item["amount"]))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(1.25, 0.95, 0.6), 0.5)
		"hp":
			GameState.add_patience(int(item["amount"]))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(0.6, 1.25, 0.7), 0.5)
		"guard":
			_guard_turns_left = 2
			_say("%s on. Whatever they say for the next two turns lands softer." % name)
			_tint(player_sprite, Color(0.62, 0.78, 1.25), 0.5)
		"atk_pct":
			_next_atk_pct = float(item["amount"]) / 100.0
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(1.3, 0.65, 0.55), 0.5)
		"atk_flat":
			_next_atk_flat = int(item["amount"])
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(1.3, 0.65, 0.55), 0.5)
		"energy_on_hit":
			_energy_on_hit_bonus = int(item["amount"])
			_energy_on_hit_turns_left = int(item.get("duration", 3))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(1.1, 0.85, 1.3), 0.5)
		"guard_pct":
			_guard_pct_amount = float(item["amount"]) / 100.0
			_guard_pct_turns_left = int(item.get("duration", 4))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(0.7, 0.9, 1.25), 0.5)

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

	if _roll_guard_stance():
		_enter_guard_stance()
	else:
		var used_skill := await _try_skill()
		if not used_skill:
			var dmg_range: Array = _enemy["damage"]
			var dmg := randi_range(int(dmg_range[0]), int(dmg_range[1]))
			dmg = int(dmg * [0.75, 1.0, 1.3][clampi(Settings.difficulty, 0, 2)])
			dmg = int(dmg * _consume_guard() * _consume_guard_pct())
			var energy_bonus := _apply_energy_on_hit_bonus()

			var taunts: Array = _enemy["taunts"]
			_say('"%s"' % String(taunts[randi() % taunts.size()]))
			SoundManager.play_enemy_voice(String(_enemy["id"]))

			_lunge("enemy", -400.0, 30.0)
			await get_tree().create_timer(0.22).timeout

			GameState.add_patience(-dmg)
			GameState.add_energy(ENERGY_ON_HIT)
			var dmg_text := "-%d" % dmg
			if energy_bonus > 0:
				dmg_text += "  (+%d Energy)" % energy_bonus
			_popup(dmg_text, false, Color(1.0, 0.5, 0.45))
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


## Enemies with a "guard_chance" occasionally spend a whole turn setting up
## a shield instead of attacking, telegraphed one full player turn ahead so
## it can be read and played around rather than feeling like a coin flip.
func _roll_guard_stance() -> bool:
	var chance := float(_enemy.get("guard_chance", 0.0))
	return chance > 0.0 and not _enemy_guarding and randf() < chance


## Headphones halve whatever damage actually lands this turn, for the next
## two turns that land damage - a turn that doesn't hit at all (an enemy
## guard stance, or a non-damaging skill like Interrupt/Silence) doesn't
## burn one of those two turns.
func _consume_guard() -> float:
	if _guard_turns_left <= 0:
		return 1.0
	_guard_turns_left -= 1
	return 0.5


## Sandwich's percentage guard - stacks multiplicatively with _consume_guard()
## at every call site, ticking down independently under the same rule.
func _consume_guard_pct() -> float:
	if _guard_pct_turns_left <= 0:
		return 1.0
	_guard_pct_turns_left -= 1
	return 1.0 - _guard_pct_amount


## Apple's on-hit Energy bonus - triggers alongside guard mitigation, on any
## turn that actually lands Patience damage. Returns the bonus granted (0 if
## inactive) so call sites can fold it into their own damage popup rather than
## fighting the single shared DamagePopup label over the same turn.
func _apply_energy_on_hit_bonus() -> int:
	if _energy_on_hit_turns_left <= 0:
		return 0
	_energy_on_hit_turns_left -= 1
	GameState.add_energy(_energy_on_hit_bonus)
	return _energy_on_hit_bonus


func _enter_guard_stance() -> void:
	_enemy_guarding = true
	_say("%s squares up and stops listening. (Guarding - your next line will be fully blocked.)" % String(_enemy["name"]))
	_tint(enemy_sprite, Color(0.55, 0.75, 1.3), 1.6)
	_popup("Guarding", false, Color(0.6, 0.75, 1.0))


## Returns true when a signature skill replaced the plain attack this turn.
func _try_skill() -> bool:
	## Enemies with more than one signature move list them under "skills";
	## a single-move enemy keeps the older "skill" string field.
	var skill_pool: Array = _enemy.get("skills", [])
	var skill := String(skill_pool[randi() % skill_pool.size()]) if not skill_pool.is_empty() else String(_enemy.get("skill", "none"))
	if skill == "none" or randf() > 0.4:
		return false

	SoundManager.play_enemy_voice(String(_enemy["id"]))
	_lunge("enemy", -260.0, 20.0)
	await get_tree().create_timer(0.2).timeout

	match skill:
		"pile_on":
			var chip := int(10 * _consume_guard() * _consume_guard_pct())
			GameState.add_patience(-chip)
			GameState.add_energy(ENERGY_ON_HIT)
			var energy_bonus := _apply_energy_on_hit_bonus()
			_say("Pile On - another 'small favour' lands on your desk.")
			var chip_text := "-%d" % chip
			if energy_bonus > 0:
				chip_text += "  (+%d Energy)" % energy_bonus
			_popup(chip_text, false, Color(1.0, 0.6, 0.4))
		"interrupt":
			_interrupted = true
			_say("Cut You Off - your next line loses its edge.")
			_popup("Interrupted", false, Color(0.8, 0.8, 0.9))
		"silence":
			var pool: Array = []
			for w: Dictionary in GameData.WORDS:
				if GameState.is_word_unlocked(String(w["id"])):
					pool.append(String(w["id"]))
			if not pool.is_empty():
				_silenced = String(pool[randi() % pool.size()])
				_say("Policy Citation - %s is off limits this turn." % GameData.word_by_id(_silenced)["name"])
				_popup("Silenced", false, Color(0.8, 0.8, 0.9))
		"gaslight":
			var drain := 18
			GameState.add_energy(-drain)
			_say("Gaslighting - \"I never said that.\" Your energy wavers.")
			_popup("-%d Energy" % drain, false, Color(0.85, 0.7, 1.0))
		"after_hours_ping":
			var chip := int(12 * _consume_guard() * _consume_guard_pct())
			GameState.add_patience(-chip)
			GameState.add_energy(-8)
			var energy_bonus := _apply_energy_on_hit_bonus()
			_say("After-Hours Ping - \"Sorry to bug you at 9pm, quick one!\"")
			var chip_text := "-%d, -8 Energy" % chip
			if energy_bonus > 0:
				chip_text += "  (+%d Energy)" % energy_bonus
			_popup(chip_text, false, Color(1.0, 0.55, 0.35))
		"urgent_no_brief":
			var pool: Array = []
			for w: Dictionary in GameData.WORDS:
				if GameState.is_word_unlocked(String(w["id"])):
					pool.append(String(w["id"]))
			if not pool.is_empty():
				_silenced = String(pool[randi() % pool.size()])
				_say("Urgent, No Brief - \"Need this redone, can't explain why, just vibes.\"")
				_popup("Silenced", false, Color(0.8, 0.8, 0.9))

	_flash(Color(0.6, 0.4, 0.9), 0.28, 0.35)
	_refresh()
	return true


# ---------------------------------------------------------------- outcome ---

func _win() -> void:
	_over = true
	_refresh_buttons()
	_collapse("enemy")
	_flash(Color(1.0, 0.85, 0.3), 0.4, 0.6)
	SoundManager.play_sfx("win")
	var reward := int(_enemy.get("coin_reward", 20))
	GameState.add_coins(reward)
	coin_label.text = "%d coins" % GameState.coins
	_say(String(_enemy.get("defeat", "%s has nothing left to say." % String(_enemy["name"]))))
	_show_coin_reward(reward)
	await get_tree().create_timer(2.2).timeout
	GameState.advance_stage()
	if GameState.stage_index >= GameData.enemy_count():
		get_tree().change_scene_to_file(ENDING)
	else:
		get_tree().change_scene_to_file(PROMOTION)


func _lose() -> void:
	_over = true
	_refresh_buttons()
	_collapse("player")
	_flash(Color(0.1, 0.1, 0.1), 0.6, 1.2)
	_say("Your patience is gone. You apologise and go back to your desk.")
	## No delete_save() here - the last stage-win checkpoint stays on disk so
	## GameOver's "Continue from Checkpoint" has something to load.
	await get_tree().create_timer(2.1).timeout
	get_tree().change_scene_to_file(GAME_OVER)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _over:
		get_viewport().set_input_as_handled()
		if _backpack_overlay.visible:
			_close_backpack()
			return
		_pause.toggle()


func _quit_to_menu() -> void:
	GameState.save_game()
	get_tree().change_scene_to_file(MAIN_MENU)


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


## The regular _popup() fades out in 0.75s, which reads as a blink for a
## reward the player should actually register - this one pops bigger and
## holds long enough to be seen before the scene changes.
func _show_coin_reward(reward: int) -> void:
	if not Settings.show_damage:
		return
	var label := Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	label.add_theme_font_size_override("font_size", 64)
	label.text = "+%d COINS" % reward
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(500, 90)
	label.position = Vector2(768.0 - 250.0, 360.0)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.4, 0.4)
	label.modulate.a = 0.0
	add_child(label)

	var t := label.create_tween()
	t.tween_property(label, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(label, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(label, "scale", Vector2(1.0, 1.0), 0.15)
	t.tween_interval(1.2)
	t.tween_property(label, "modulate:a", 0.0, 0.4)
	t.tween_callback(label.queue_free)


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
