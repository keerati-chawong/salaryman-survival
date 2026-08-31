extends Control
## Confrontation Phase. Four word types are checked against the current enemy's
## weakness table; each enemy answers with its own signature skill.

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const PROMOTION := "res://scenes/Promotion.tscn"
const WORK_PHASE := "res://scenes/WorkPhase.tscn"

## Anger regained whenever the enemy lands a hit, per the design's
## "anger builds when you are insulted" rule.
const ANGER_ON_HIT := 12

## Floor for word uses this fight, applied even if WorkPhase handed over
## fewer documents than this (or nothing at all, e.g. an old save).
const BASE_WORD_USES := 2
const APOLOGIZE_COST := 30

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
@onready var anger_bar: ProgressBar = $PlayerPanel/Cols/Bars/MPRow/AngerBar
@onready var anger_label: Label = $PlayerPanel/Cols/Bars/MPRow/AngerLabel
@onready var rank_label: Label = $PlayerPanel/Cols/Bars/BottomRow/RankLabel
@onready var coin_label: Label = $PlayerPanel/Cols/Bars/BottomRow/CoinLabel

@onready var word_grid: GridContainer = $ActionPanel/Rows/WordGrid
@onready var item_row: HBoxContainer = $ActionPanel/Rows/ItemRow
@onready var bite_button: Button = $ActionPanel/Rows/BiteButton
@onready var hint_label: Label = $ActionPanel/Rows/HintLabel

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
var _enemy_guarding := false

var _word_buttons: Dictionary = {}
var _word_uses: Dictionary = {}
var _word_max_uses: Dictionary = {}
var _apologize_button: Button

var _backpack_button: Button
var _backpack_overlay: Control
var _backpack_hint_label: Label
## id -> {"btn": Button, "icon": TextureRect, "count": Label}
var _backpack_slots: Dictionary = {}

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
	bite_button.mouse_entered.connect(_show_hint.bind("A free way to keep going when you're out of Anger and items."))
	bite_button.mouse_exited.connect(_clear_hint)
	_setup_sprites()
	_refresh(true)

	_say("%s\n%s" % [String(_enemy["intro"]), "Pick your words carefully."])


## Every word starts this fight with the same number of uses: whatever
## quota WorkPhase handed over (GameState.attack_quota), floored at
## BASE_WORD_USES so an empty/old save can't hard-lock a fight.
func _init_word_uses() -> void:
	var uses := maxi(GameState.attack_quota, BASE_WORD_USES)
	for word: Dictionary in GameData.WORDS:
		var id := String(word["id"])
		_word_uses[id] = uses
		_word_max_uses[id] = uses


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
	anger_bar.max_value = GameState.MAX_ANGER


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
		btn.custom_minimum_size = Vector2(0, 74)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.text = "%s\n%d Anger" % [String(word["short"]), int(word["cost"])]
		btn.add_theme_color_override("font_color", word["color"])
		btn.pressed.connect(_on_word_pressed.bind(String(word["id"])))
		# a shared hint line avoids tooltips popping over neighbouring buttons
		btn.mouse_entered.connect(_show_hint.bind("%s - %s" % [String(word["name"]), String(word["blurb"])]))
		btn.mouse_exited.connect(_clear_hint)
		word_grid.add_child(btn)
		_word_buttons[String(word["id"])] = btn


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
	if _busy or _over:
		return
	_backpack_overlay.visible = true
	_refresh_backpack()


func _close_backpack() -> void:
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
		var blocked := _over or _busy or count <= 0
		btn.disabled = blocked
		icon.modulate = Color(1, 1, 1, 1) if not blocked else Color(1, 1, 1, 0.35)


## Hidden until every word is out of uses - the crisis fallback: trade
## Patience to keep the fight going instead of being locked out entirely.
func _build_apologize_button() -> void:
	_apologize_button = Button.new()
	_apologize_button.text = "Apologize  (-%d Patience, +1 use each)" % APOLOGIZE_COST
	_apologize_button.custom_minimum_size = bite_button.custom_minimum_size
	_apologize_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apologize_button.visible = false
	_apologize_button.pressed.connect(_on_apologize_pressed)
	_apologize_button.mouse_entered.connect(_show_hint.bind("Only appears when every word is out of uses. Costly, but keeps you in the fight."))
	_apologize_button.mouse_exited.connect(_clear_hint)
	bite_button.get_parent().add_child(_apologize_button)


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
		var blocked := _over or _busy or _silenced == id or uses <= 0 or GameState.anger < int(word["cost"])
		btn.disabled = blocked
		var suffix := "  (silenced)" if _silenced == id else ""
		btn.text = "%s%s  (%d/%d)\n%d Anger" % [
			String(word["short"]), suffix, uses, int(_word_max_uses.get(id, uses)), int(word["cost"]),
		]

	var total_items := 0
	for id: String in GameData.ITEMS:
		total_items += GameState.item_count(id)
	_backpack_button.text = "Open Backpack  (%d items)" % total_items
	_backpack_button.disabled = _over or _busy
	if _backpack_overlay.visible:
		_refresh_backpack()

	bite_button.disabled = _over or _busy

	_apologize_button.visible = out_of_words
	_apologize_button.disabled = _over or _busy or GameState.patience <= APOLOGIZE_COST


# ------------------------------------------------------------------ state ---

func _refresh(instant := false) -> void:
	enemy_hp_label.text = "%d / %d" % [maxi(_enemy_hp, 0), _enemy_max]
	patience_label.text = "%d / %d" % [maxi(GameState.patience, 0), GameState.MAX_PATIENCE]
	anger_label.text = "%d / %d" % [GameState.anger, GameState.MAX_ANGER]
	rank_label.text = "Rank: %s" % GameState.rank
	coin_label.text = "%d coins" % GameState.coins

	if instant:
		enemy_bar.value = _enemy_hp
		patience_bar.value = GameState.patience
		anger_bar.value = GameState.anger
	else:
		var t := create_tween()
		t.set_parallel(true)
		t.tween_property(enemy_bar, "value", maxf(_enemy_hp, 0), 0.3)
		t.tween_property(patience_bar, "value", maxf(GameState.patience, 0), 0.3)
		t.tween_property(anger_bar, "value", GameState.anger, 0.3)

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
	if _busy or _over:
		return
	var word := GameData.word_by_id(id)
	if int(_word_uses.get(id, 0)) <= 0:
		_say("You're out of ways to say that this fight.")
		return
	if not GameState.spend_anger(int(word["cost"])):
		_say("Not enough Anger for that one.")
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


## Crisis fallback once every word is out of uses: burn Patience to keep
## the fight going rather than being stuck with only Bite/items.
func _on_apologize_pressed() -> void:
	if _busy or _over:
		return

	_busy = true
	_refresh_buttons()

	GameState.add_patience(-APOLOGIZE_COST)
	for id: String in _word_uses:
		_word_uses[id] = int(_word_uses[id]) + 1
	_say("You apologise for existing. It buys you one more line on everything.")
	_tint(player_sprite, Color(0.8, 0.8, 0.85), 0.4)
	_popup("-%d Patience, +1 use each" % APOLOGIZE_COST, false, Color(0.85, 0.6, 0.6))

	_refresh()
	if GameState.patience <= 0:
		await _lose()
		return
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
	var name := String(item["name"])
	var blurb := String(item["blurb"])
	match String(item["effect"]):
		"anger":
			GameState.add_anger(int(item["amount"]))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(1.25, 0.95, 0.6), 0.5)
		"hp":
			GameState.add_patience(int(item["amount"]))
			_say("%s. %s." % [name, blurb])
			_tint(player_sprite, Color(0.6, 1.25, 0.7), 0.5)
		"guard":
			_guard_next = true
			_say("%s on. Whatever they say next lands softer." % name)
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

	if _roll_guard_stance():
		_enter_guard_stance()
	else:
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


## Enemies with a "guard_chance" occasionally spend a whole turn setting up
## a shield instead of attacking, telegraphed one full player turn ahead so
## it can be read and played around rather than feeling like a coin flip.
func _roll_guard_stance() -> bool:
	var chance := float(_enemy.get("guard_chance", 0.0))
	return chance > 0.0 and not _enemy_guarding and randf() < chance


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
		"after_hours_ping":
			var chip := 12
			GameState.add_patience(-chip)
			GameState.add_anger(-8)
			_say("After-Hours Ping - \"Sorry to bug you at 9pm, quick one!\"")
			_popup("-%d, -8 Anger" % chip, false, Color(1.0, 0.55, 0.35))
		"urgent_no_brief":
			var pool: Array = []
			for w: Dictionary in GameData.WORDS:
				pool.append(String(w["id"]))
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
	var reward := int(_enemy.get("coin_reward", 20))
	GameState.add_coins(reward)
	coin_label.text = "%d coins" % GameState.coins
	_say(String(_enemy.get("defeat", "%s has nothing left to say." % String(_enemy["name"]))))
	_show_coin_reward(reward)
	await get_tree().create_timer(2.2).timeout
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
		get_viewport().set_input_as_handled()
		if _backpack_overlay.visible:
			_close_backpack()
			return
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
