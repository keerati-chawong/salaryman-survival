extends Node
## Run state shared by the work phase, the battle and the promotion screen.

const SAVE_PATH := "user://save.dat"

const MAX_PATIENCE := 220
const MAX_ANGER := 100
## Anger the player keeps when a battle ends, so the work phase always matters.
const ANGER_CARRY := 0.5

signal stats_changed

var stage_index := 0
var patience := MAX_PATIENCE
var anger := 0
var rank := "Intern"
var inventory := {}
var coins := 0
## Word-attack uses per fight, carried over from the documents collected in
## WorkPhase. Battle.gd reads this once in _ready() and floors it itself.
var attack_quota := 0

## Movement actions are registered in code so the input map lives next to the
## gameplay that uses it instead of hand-edited into project.godot.
const MOVE_KEYS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
}


func _ready() -> void:
	for action: String in MOVE_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key: int in MOVE_KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	inventory = _default_inventory()


## Every item id starts at 0 so the shop's bag panel always has a row to show;
## the starter kit then tops up a few essentials.
func _default_inventory() -> Dictionary:
	var inv := {}
	for id: String in GameData.ITEMS:
		inv[id] = 0
	inv["coffee"] = 1
	inv["water"] = 1
	inv["headphones"] = 1
	return inv


func start_new_run() -> void:
	stage_index = 0
	patience = MAX_PATIENCE
	anger = 0
	rank = "Intern"
	inventory = _default_inventory()
	coins = 0
	attack_quota = 0
	save_game()
	stats_changed.emit()


func current_enemy() -> Dictionary:
	return GameData.enemy_at(stage_index)


func is_final_stage() -> bool:
	return stage_index >= GameData.enemy_count() - 1


func set_patience(value: int) -> void:
	patience = clampi(value, 0, MAX_PATIENCE)
	stats_changed.emit()


func add_patience(delta: int) -> void:
	set_patience(patience + delta)


func set_anger(value: int) -> void:
	anger = clampi(value, 0, MAX_ANGER)
	stats_changed.emit()


func add_anger(delta: int) -> void:
	set_anger(anger + delta)


func spend_anger(amount: int) -> bool:
	if anger < amount:
		return false
	set_anger(anger - amount)
	return true


func item_count(id: String) -> int:
	return int(inventory.get(id, 0))


func consume_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	inventory[id] = item_count(id) - 1
	stats_changed.emit()
	return true


func grant_item(id: String, amount: int = 1) -> void:
	inventory[id] = item_count(id) + amount
	stats_changed.emit()


func add_coins(delta: int) -> void:
	coins = maxi(0, coins + delta)
	stats_changed.emit()


func spend_coins(amount: int) -> bool:
	if coins < amount:
		return false
	coins -= amount
	stats_changed.emit()
	return true


## Called at the end of a WorkPhase run with the documents collected, so
## Battle.gd knows how many uses to hand out per word this fight.
func set_attack_quota(value: int) -> void:
	attack_quota = maxi(0, value)
	stats_changed.emit()


## Called after a win: promote, restock a little, and carry part of the anger.
func advance_stage() -> void:
	var enemy := current_enemy()
	rank = String(enemy.get("promotion", rank))
	stage_index += 1
	patience = MAX_PATIENCE
	anger = int(anger * ANGER_CARRY)
	attack_quota = 0
	grant_item("coffee", 1)
	grant_item("water", 1)
	if stage_index % 2 == 1:
		grant_item("headphones", 1)
	save_game()
	stats_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var payload := {
		"stage_index": stage_index,
		"patience": patience,
		"anger": anger,
		"rank": rank,
		"inventory": inventory,
		"coins": coins,
		"attack_quota": attack_quota,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
		f.close()


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false

	var data: Dictionary = parsed
	stage_index = clampi(int(data.get("stage_index", 0)), 0, GameData.enemy_count() - 1)
	patience = clampi(int(data.get("patience", MAX_PATIENCE)), 1, MAX_PATIENCE)
	anger = clampi(int(data.get("anger", 0)), 0, MAX_ANGER)
	rank = String(data.get("rank", "Intern"))
	coins = maxi(0, int(data.get("coins", 0)))
	attack_quota = maxi(0, int(data.get("attack_quota", 0)))
	var inv: Variant = data.get("inventory", {})
	inventory = _default_inventory()
	if typeof(inv) == TYPE_DICTIONARY:
		for id: String in GameData.ITEMS:
			inventory[id] = int((inv as Dictionary).get(id, 0))
	stats_changed.emit()
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)
