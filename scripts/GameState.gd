extends Node
## Run state shared by the work phase, the battle and the promotion screen.

const SAVE_PATH := "user://save.dat"

const MAX_PATIENCE := 220
const MAX_ENERGY := 100
## Energy the player keeps when a battle ends, so the work phase always matters.
const ENERGY_CARRY := 0.5

signal stats_changed

var stage_index := 0
var patience := MAX_PATIENCE
## The WorkPhase -> Battle Energy pipeline: WorkPhase.gd calls add_energy()
## for every word typed (more for a clean, fast, combo'd word). There is no
## separate "starting_energy" - this field IS the Battle starting resource,
## carried over as-is: Battle.gd's word buttons spend directly out of this
## same value, so a strong typing run means Battle opens with Energy already
## banked instead of at zero. advance_stage() keeps ENERGY_CARRY (half) of
## whatever's left after a win, so it still matters going into the next fight.
var energy := 0
var rank := "Intern"
var inventory := {}
var coins := 0
## Word-attack uses per fight, per word id, earned by typing that category's
## words correctly in WorkPhase. Battle.gd reads this once in _ready() and
## floors each entry at BASE_WORD_USES itself.
var word_quota: Dictionary = {}
## Word ids unlocked for use in Battle - permanent progression, persisted to
## save. "passive" (Polite) starts unlocked; WorkPhase.gd unlocks the rest
## one per stage (see GameData.STAGE_FOCUS_WORD).
var unlocked_words: Array = ["passive"]

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
	energy = 0
	rank = "Intern"
	inventory = _default_inventory()
	coins = 0
	word_quota = {}
	unlocked_words = ["passive"]
	## A fresh run gets the WorkPhase briefing again, even if a previous run
	## already dismissed it - "seen it" is scoped to the run, not the install.
	Settings.has_seen_workphase_intro = false
	Settings.save_settings()
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


func set_energy(value: int) -> void:
	energy = clampi(value, 0, MAX_ENERGY)
	stats_changed.emit()


func add_energy(delta: int) -> void:
	set_energy(energy + delta)


func spend_energy(amount: int) -> bool:
	if energy < amount:
		return false
	set_energy(energy - amount)
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


## Called at the end of a WorkPhase run with how many words of each category
## were typed correctly, so Battle.gd knows how many uses to hand out per
## word this fight.
func set_word_quota(counts: Dictionary) -> void:
	word_quota = {}
	for id: String in counts:
		word_quota[id] = maxi(0, int(counts[id]))
	stats_changed.emit()


func is_word_unlocked(id: String) -> bool:
	return unlocked_words.has(id)


func unlock_word(id: String) -> void:
	if unlocked_words.has(id):
		return
	unlocked_words.append(id)
	stats_changed.emit()


## Called after a win: promote, restock a little, and carry part of the energy.
func advance_stage() -> void:
	var enemy := current_enemy()
	rank = String(enemy.get("promotion", rank))
	stage_index += 1
	patience = MAX_PATIENCE
	energy = int(energy * ENERGY_CARRY)
	word_quota = {}
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
		"energy": energy,
		"rank": rank,
		"inventory": inventory,
		"coins": coins,
		"word_quota": word_quota,
		"unlocked_words": unlocked_words,
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
	energy = clampi(int(data.get("energy", 0)), 0, MAX_ENERGY)
	rank = String(data.get("rank", "Intern"))
	coins = maxi(0, int(data.get("coins", 0)))

	word_quota = {}
	var quota: Variant = data.get("word_quota", {})
	if typeof(quota) == TYPE_DICTIONARY:
		for id: String in (quota as Dictionary):
			word_quota[id] = maxi(0, int((quota as Dictionary)[id]))

	unlocked_words = ["passive"]
	var unlocked: Variant = data.get("unlocked_words", [])
	if typeof(unlocked) == TYPE_ARRAY:
		for id: Variant in (unlocked as Array):
			if not unlocked_words.has(String(id)):
				unlocked_words.append(String(id))

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
