extends Control
## Shop. The vending machine background (assets/backgrounds/shop.png) already
## has all 8 snacks/drinks painted into its lit display row - hovering one of
## those spots shows its price, clicking buys it immediately. Headphones
## (armour, not sold from the machine) get their own row in the Accessories
## panel. See GameData.ITEMS for prices/effects and GameData.ENEMIES'
## coin_reward + Battle.gd's _win() for how coins are earned.

const PROMOTION := "res://scenes/Promotion.tscn"
const COIN_ICON := preload("res://assets/item/coin.png")

## shop.png is painted at 2528x1686 but the background is shown at 1536x1024 -
## every rect below was measured on the source art, so it's scaled down by
## this factor to line up with the shrunk texture.
const ART_SCALE := 1536.0 / 2528.0

## Food/drink id -> Rect2 (in source-art pixels) around that item's icon in
## the vending machine's lit display row. Measured directly on the art.
const FOOD_SLOTS := {
	"coffee": Rect2(743, 431, 86, 118),
	"noodles": Rect2(859, 434, 108, 114),
	"banana": Rect2(977, 445, 105, 100),
	"apple": Rect2(1103, 444, 90, 104),
	"energy_bar": Rect2(730, 623, 115, 118),
	"sandwich": Rect2(858, 634, 100, 110),
	"soda": Rect2(1001, 625, 66, 111),
	"water": Rect2(1116, 593, 64, 147),
}
## Extra reach around each slot so the clickable area is a little more
## forgiving than the icon's exact pixels.
const HOTSPOT_PAD := 10.0

var _coin_label: Label
var _message_label: Label
var _tooltip: PanelContainer
var _tooltip_label: Label
var _headphones_owned: Label
var _headphones_buy: Button
## id -> Label showing "Owned: N" in the bag panel.
var _bag_owned: Dictionary = {}


func _ready() -> void:
	GameState.stats_changed.connect(_refresh)
	_build_hotspots()
	_build_hud()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back()


# -------------------------------------------------------- vending hotspots --

func _build_hotspots() -> void:
	for id: String in FOOD_SLOTS:
		var rect: Rect2 = FOOD_SLOTS[id]
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.position = rect.position * ART_SCALE - Vector2.ONE * HOTSPOT_PAD
		btn.size = rect.size * ART_SCALE + Vector2.ONE * HOTSPOT_PAD * 2.0
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.mouse_entered.connect(_on_slot_enter.bind(btn, id))
		btn.mouse_exited.connect(_on_slot_exit.bind(btn))
		btn.pressed.connect(_on_buy.bind(id))
		add_child(btn)


func _on_slot_enter(btn: Button, id: String) -> void:
	btn.modulate = Color(1.35, 1.3, 0.8)
	var item: Dictionary = GameData.ITEMS[id]
	_tooltip_label.text = "%s\n%s\n%d coins" % [String(item["name"]), String(item["blurb"]), int(item["price"])]
	_tooltip.visible = true
	_tooltip.position = Vector2(
		clampf(btn.position.x + btn.size.x * 0.5 - 75.0, 8.0, 1536.0 - 158.0),
		maxf(btn.position.y - 92.0, 8.0),
	)


func _on_slot_exit(btn: Button) -> void:
	btn.modulate = Color.WHITE
	_tooltip.visible = false


# ---------------------------------------------------------------------- hud --

func _build_hud() -> void:
	_build_top_bar()
	_build_tooltip()
	_build_side_panel()
	_build_message_bar()


func _build_top_bar() -> void:
	var band := ColorRect.new()
	band.position = Vector2.ZERO
	band.size = Vector2(1536, 64)
	band.color = Color(0.03, 0.04, 0.06, 0.78)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	var row := HBoxContainer.new()
	row.position = Vector2(22, 10)
	row.size = Vector2(1492, 44)
	row.add_theme_constant_override("separation", 20)
	add_child(row)

	var title := Label.new()
	title.theme_type_variation = &"BigStatLabel"
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.38))
	title.text = "SHOP"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 8)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = COIN_ICON
	icon.custom_minimum_size = Vector2(30, 30)
	coin_box.add_child(icon)

	_coin_label = Label.new()
	_coin_label.theme_type_variation = &"BigStatLabel"
	_coin_label.add_theme_color_override("font_color", Color(1, 0.85, 0.38))
	_coin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_box.add_child(_coin_label)
	row.add_child(coin_box)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(90, 40)
	back_button.pressed.connect(_on_back)
	row.add_child(back_button)


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.custom_minimum_size = Vector2(150, 0)
	add_child(_tooltip)

	_tooltip_label = Label.new()
	_tooltip_label.theme_type_variation = &"SmallLabel"
	_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tooltip_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	_tooltip.add_child(_tooltip_label)


func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(1080, 84)
	panel.size = Vector2(432, 916)
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	panel.add_child(rows)

	var accessories_header := Label.new()
	accessories_header.theme_type_variation = &"BigStatLabel"
	accessories_header.text = "Accessories"
	rows.add_child(accessories_header)

	rows.add_child(_build_headphones_row())
	rows.add_child(HSeparator.new())

	var bag_header := Label.new()
	bag_header.theme_type_variation = &"BigStatLabel"
	bag_header.text = "Your Bag"
	rows.add_child(bag_header)

	var bag_hint := Label.new()
	bag_hint.theme_type_variation = &"SmallLabel"
	bag_hint.add_theme_color_override("font_color", Color(0.74, 0.77, 0.83))
	bag_hint.text = "What you're carrying into the next fight."
	bag_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(bag_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.add_child(scroll)

	var bag_list := VBoxContainer.new()
	bag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_list.add_theme_constant_override("separation", 8)
	scroll.add_child(bag_list)

	for id: String in GameData.ITEMS:
		bag_list.add_child(_build_bag_row(id, GameData.ITEMS[id]))


func _build_headphones_row() -> Control:
	var item: Dictionary = GameData.ITEMS["headphones"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(item["icon"]))
	icon.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.theme_type_variation = &"StatLabel"
	name_label.text = String(item["name"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(name_label)

	var blurb_label := Label.new()
	blurb_label.theme_type_variation = &"SmallLabel"
	blurb_label.add_theme_color_override("font_color", Color(0.74, 0.77, 0.83))
	blurb_label.text = "%s - %d coins" % [String(item["blurb"]), int(item["price"])]
	text_col.add_child(blurb_label)

	_headphones_owned = Label.new()
	_headphones_owned.theme_type_variation = &"SmallLabel"
	text_col.add_child(_headphones_owned)

	row.add_child(text_col)

	_headphones_buy = Button.new()
	_headphones_buy.text = "Buy"
	_headphones_buy.custom_minimum_size = Vector2(74, 40)
	_headphones_buy.pressed.connect(_on_buy.bind("headphones"))
	row.add_child(_headphones_buy)

	return row


func _build_bag_row(id: String, item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(String(item["icon"]))
	icon.custom_minimum_size = Vector2(30, 30)
	row.add_child(icon)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.theme_type_variation = &"SmallLabel"
	name_label.text = "%s  (%s)" % [String(item["name"]), String(item["blurb"])]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(name_label)

	row.add_child(text_col)

	var owned_label := Label.new()
	owned_label.theme_type_variation = &"SmallLabel"
	owned_label.custom_minimum_size = Vector2(80, 0)
	owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(owned_label)

	_bag_owned[id] = owned_label
	return row


func _build_message_bar() -> void:
	var band := ColorRect.new()
	band.position = Vector2(0, 964)
	band.size = Vector2(1536, 60)
	band.color = Color(0.03, 0.04, 0.06, 0.78)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_message_label = Label.new()
	_message_label.position = Vector2(24, 964)
	_message_label.size = Vector2(1488, 60)
	_message_label.theme_type_variation = &"StatLabel"
	_message_label.add_theme_color_override("font_color", Color(1, 0.86, 0.42))
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.text = "Hover a snack to see its price, then click it to buy."
	add_child(_message_label)


# ---------------------------------------------------------------- actions ---

func _on_buy(id: String) -> void:
	var item: Dictionary = GameData.ITEMS[id]
	var price := int(item["price"])
	if GameState.spend_coins(price):
		GameState.grant_item(id)
		GameState.save_game()
		_message_label.text = "Bought %s for %d coins." % [String(item["name"]), price]
		_flash_coins("-%d" % price)
	else:
		_message_label.text = "Not enough coins for %s (need %d)." % [String(item["name"]), price]


func _on_back() -> void:
	get_tree().change_scene_to_file(PROMOTION)


func _flash_coins(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	label.position = _coin_label.get_global_rect().position + Vector2(-10.0, -34.0)
	add_child(label)

	var t := label.create_tween()
	t.set_parallel(true)
	t.tween_property(label, "position:y", label.position.y - 40.0, 0.8)
	t.tween_property(label, "modulate:a", 0.0, 0.8)
	t.chain().tween_callback(label.queue_free)


func _refresh() -> void:
	_coin_label.text = "%d" % GameState.coins

	var headphones: Dictionary = GameData.ITEMS["headphones"]
	_headphones_owned.text = "Owned: %d" % GameState.item_count("headphones")
	_headphones_buy.disabled = GameState.coins < int(headphones["price"])

	for id: String in _bag_owned:
		var owned: Label = _bag_owned[id]
		owned.text = "Owned: %d" % GameState.item_count(id)
