extends Node
## TEMPORARY - A/B test to see whether OGG playback produces real audio on
## Web when the project's normal MP3 tracks come out silent. Delete before
## shipping; this is not part of the game.

func _ready() -> void:
	var player := AudioStreamPlayer.new()
	add_child(player)
	player.stream = load("res://assets/audio/music/_test_audio.ogg")
	player.volume_db = 0.0
	player.play()
