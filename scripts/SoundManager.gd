extends Node
## Central audio hub. One AudioStreamPlayer for music (crossfades between
## tracks, supports ducking) plus a small round-robin pool for one-shot SFX
## so overlapping sounds (rapid typing, back-to-back attacks) don't cut each
## other off. Everything routes through the "Music"/"SFX" buses Settings.gd
## already creates, so the Options volume sliders work with no extra wiring.

const SFX_POOL_SIZE := 8
const MUSIC_FADE := 0.6
const DUCK_DB := -14.0

const MUSIC := {
	"menu": preload("res://assets/audio/music/menu.mp3"),
	"battle": preload("res://assets/audio/music/battle.mp3"),
	"workphase": preload("res://assets/audio/music/workphase.mp3"),
}

## Every key holds an Array of AudioStream so play_sfx() can pick a random
## take - a little variety for lines that repeat a lot (clicks, voice barks).
const SFX := {
	"click": [
		preload("res://assets/audio/sfx/ui/click_1.mp3"),
		preload("res://assets/audio/sfx/ui/click_2.mp3"),
	],
	"block": [preload("res://assets/audio/sfx/battle/block.mp3")],
	"win": [preload("res://assets/audio/sfx/battle/win.mp3")],
	"item_use": [preload("res://assets/audio/sfx/battle/item_use.mp3")],
	"player_hit": [
		preload("res://assets/audio/sfx/battle/player_hit_1.mp3"),
		preload("res://assets/audio/sfx/battle/player_hit_2.mp3"),
		preload("res://assets/audio/sfx/battle/player_hit_3.mp3"),
	],
	"voice_ceo": [
		preload("res://assets/audio/sfx/battle/voice_ceo_1.mp3"),
		preload("res://assets/audio/sfx/battle/voice_ceo_2.mp3"),
		preload("res://assets/audio/sfx/battle/voice_ceo_3.mp3"),
	],
	"voice_dodger": [
		preload("res://assets/audio/sfx/battle/voice_dodger_1.mp3"),
		preload("res://assets/audio/sfx/battle/voice_dodger_2.mp3"),
		preload("res://assets/audio/sfx/battle/voice_dodger_3.mp3"),
	],
	"voice_hr": [
		preload("res://assets/audio/sfx/battle/voice_hr_1.mp3"),
		preload("res://assets/audio/sfx/battle/voice_hr_2.mp3"),
		preload("res://assets/audio/sfx/battle/voice_hr_3.mp3"),
	],
	"voice_rookie": [
		preload("res://assets/audio/sfx/battle/voice_rookie_1.mp3"),
		preload("res://assets/audio/sfx/battle/voice_rookie_2.mp3"),
		preload("res://assets/audio/sfx/battle/voice_rookie_3.mp3"),
	],
	"voice_senior": [
		preload("res://assets/audio/sfx/battle/voice_senior_1.mp3"),
		preload("res://assets/audio/sfx/battle/voice_senior_2.mp3"),
		preload("res://assets/audio/sfx/battle/voice_senior_3.mp3"),
		preload("res://assets/audio/sfx/battle/voice_senior_4.mp3"),
	],
	"typewriter": [preload("res://assets/audio/sfx/workphase/typewriter.mp3")],
	"doc_pickup": [preload("res://assets/audio/sfx/workphase/doc_pickup.mp3")],
	"qte_success": [preload("res://assets/audio/sfx/workphase/qte_success.mp3")],
	"qte_fail": [
		preload("res://assets/audio/sfx/workphase/qte_fail_1.mp3"),
		preload("res://assets/audio/sfx/workphase/qte_fail_2.mp3"),
		preload("res://assets/audio/sfx/workphase/qte_fail_3.mp3"),
	],
	"mistype_1": [preload("res://assets/audio/sfx/workphase/mistype_1.mp3")],
	"mistype_2": [preload("res://assets/audio/sfx/workphase/mistype_2.mp3")],
	"mistype_3": [preload("res://assets/audio/sfx/workphase/mistype_3.mp3")],
	"mistype_4": [preload("res://assets/audio/sfx/workphase/mistype_4.mp3")],
	"lose": [
		preload("res://assets/audio/sfx/lose/lose_1.mp3"),
		preload("res://assets/audio/sfx/lose/lose_2.mp3"),
		preload("res://assets/audio/sfx/lose/lose_3.mp3"),
		preload("res://assets/audio/sfx/lose/lose_4.mp3"),
	],
}

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _lose_player: AudioStreamPlayer
var _current_music := ""
var _duck_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	add_child(_music_player)

	for i: int in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)

	## Kept separate from the round-robin pool so a losing run's sting can't
	## get stolen by an SFX that happens to land on the same player right
	## after play_lose() silences everything else.
	_lose_player = AudioStreamPlayer.new()
	_lose_player.bus = "SFX"
	add_child(_lose_player)


# ------------------------------------------------------------------ music ---

## No-ops if this track is already playing so scene transitions between
## screens sharing a track (e.g. re-entering Options) don't restart it.
func play_music(key: String, fade: float = MUSIC_FADE) -> void:
	if key == _current_music and _music_player.playing:
		return
	var stream: AudioStream = MUSIC.get(key)
	if stream == null:
		return
	_current_music = key
	stream.loop = true

	if _music_player.playing:
		var t := create_tween()
		t.tween_property(_music_player, "volume_db", -40.0, fade * 0.5)
		t.tween_callback(_start_music.bind(stream, fade))
	else:
		_start_music(stream, fade)


func _start_music(stream: AudioStream, fade: float) -> void:
	_music_player.stream = stream
	_music_player.volume_db = -40.0
	_music_player.play()
	var target := DUCK_DB if _duck_count > 0 else 0.0
	create_tween().tween_property(_music_player, "volume_db", target, fade * 0.5)


func stop_music(fade: float = 0.4) -> void:
	_current_music = ""
	var t := create_tween()
	t.tween_property(_music_player, "volume_db", -40.0, fade)
	t.tween_callback(_music_player.stop)


## Reference-counted so an overlapping QTE-window duck and a mistake's brief
## duck don't stomp each other's restore.
func duck_music() -> void:
	_duck_count += 1
	_apply_duck()


func unduck_music() -> void:
	_duck_count = maxi(_duck_count - 1, 0)
	_apply_duck()


func duck_music_briefly(duration: float = 0.5) -> void:
	duck_music()
	get_tree().create_timer(duration).timeout.connect(unduck_music)


func _apply_duck() -> void:
	var target := DUCK_DB if _duck_count > 0 else 0.0
	create_tween().tween_property(_music_player, "volume_db", target, 0.25)


# -------------------------------------------------------------------- sfx ---

func play_sfx(key: String) -> void:
	var pool: Array = SFX.get(key, [])
	if pool.is_empty():
		return
	var player := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	player.stream = pool[randi() % pool.size()]
	player.play()


func play_enemy_voice(enemy_id: String) -> void:
	play_sfx("voice_%s" % enemy_id)


func play_mistype(streak: int) -> void:
	play_sfx("mistype_%d" % clampi(streak, 1, 4))


## The losing sting: cuts the music and every in-flight SFX so only one
## random line from the lose pool is heard.
func play_lose() -> void:
	stop_music(0.2)
	for p: AudioStreamPlayer in _sfx_players:
		p.stop()
	var pool: Array = SFX.get("lose", [])
	if pool.is_empty():
		return
	_lose_player.stream = pool[randi() % pool.size()]
	_lose_player.play()
