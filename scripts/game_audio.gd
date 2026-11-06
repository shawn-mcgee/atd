class_name GameAudio
extends Node

const SOUNDS := {
	"select": preload("res://assets/audio/select.wav"), "order": preload("res://assets/audio/order.wav"),
	"error": preload("res://assets/audio/error.wav"), "rifle": preload("res://assets/audio/rifle.wav"),
	"laser": preload("res://assets/audio/laser.wav"), "impact": preload("res://assets/audio/impact.wav"),
	"cannon": preload("res://assets/audio/cannon.wav"), "flame": preload("res://assets/audio/flame.wav"),
	"shield": preload("res://assets/audio/shield.wav"), "collapse": preload("res://assets/audio/collapse.wav"), "deposit": preload("res://assets/audio/deposit.wav"),
	"mining": preload("res://assets/audio/mining.wav"), "complete": preload("res://assets/audio/complete.wav")}
var muted := false
var enabled := false
var voices: Array[AudioStreamPlayer3D] = []
var ui_voice := AudioStreamPlayer.new()
var ambience := AudioStreamPlayer.new()
var cursor := 0
var extra_sounds: Dictionary = {}
var feedback_cursor := 0
var sound_times: Dictionary = {}
var last_ui := -1000
var known: Dictionary = {}
var update_timer := 0.0

func _ready() -> void:
	muted = not bool(Settings.data.presentation.soundEnabled)
	add_child(ui_voice); add_child(ambience)
	var stream := preload("res://assets/audio/ambience.wav").duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD; stream.loop_end = stream.data.size() / 2
	ambience.stream = stream; ambience.volume_db = float(Settings.data.presentation.ambienceVolumeDb)
	for i in range(int(Settings.data.presentation.feedback.audioVoiceCount)):
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = float(Settings.data.presentation.feedback.audioUnitSizeTiles); voice.max_distance = float(Settings.data.presentation.feedback.audioMaxDistanceTiles); voice.volume_db = float(Settings.data.presentation.effectsVolumeDb)
		add_child(voice); voices.append(voice)

func start() -> void:
	enabled = true; known.clear(); sound_times.clear(); feedback_cursor = 0
	if not muted: ambience.play()

func stop() -> void:
	enabled = false; ambience.stop()
	for voice in voices: voice.stop()

func toggle() -> void:
	muted = not muted
	if muted:
		ambience.stop(); ui_voice.stop()
		for voice in voices: voice.stop()
	elif enabled: ambience.play()

func cue(kind: String) -> void:
	if muted or not enabled or not SOUNDS.has(kind): return
	var now := Time.get_ticks_msec()
	if now - last_ui < 55 and kind != "error": return
	last_ui = now
	ui_voice.stream = SOUNDS[kind]; ui_voice.volume_db = float(Settings.data.presentation.uiVolumeDb); ui_voice.play()

func spatial(kind: String, at: Vector2, gain: float = 0.0) -> void:
	if muted or not enabled: return
	var stream: AudioStream = SOUNDS.get(kind)
	if stream == null:
		if not extra_sounds.has(kind):
			var path := "res://assets/audio/%s.wav" % kind
			if not ResourceLoader.exists(path): return
			extra_sounds[kind] = load(path) as AudioStream
		stream = extra_sounds[kind]
	if stream == null: return
	var voice := voices[cursor % voices.size()]; cursor += 1
	voice.stream = stream; voice.position = Vector3(at.x, 0.4, at.y)
	voice.volume_db = float(Settings.data.presentation.effectsVolumeDb) + gain
	voice.pitch_scale = 0.94 + fposmod(cursor * 0.073, 0.12)
	voice.play()

func update(world: WorldState, owner_id: int, delta: float) -> void:
	if not enabled: return
	for event in world.feedback_for(owner_id, feedback_cursor):
		feedback_cursor = maxi(feedback_cursor, int(event.serial))
		if world.tick - int(event.tick) > int(world.cfg.presentation.feedback.maxCatchupTicks): continue
		match str(event.kind):
			"fire":
				var profile := WorldState.FeedbackRules.profile(world.cfg, str(event.weapon))
				var key := "%s/%s" % [event.attacker, event.weapon]
				if _sound_due(key, float(profile.soundIntervalSeconds)): spatial(str(profile.sound), event.from, float(profile.gainDb))
			"hit":
				if event.shielded and _sound_due("shield/%s" % event.target, float(world.cfg.presentation.feedback.shieldSoundIntervalSeconds)): spatial("shield", event.at, -6)
			"destroy": spatial("collapse", event.at, -2)
			"ready": cue("complete")
			"deposit":
				if _sound_due("deposit/%s" % event.get("target", 0), float(world.cfg.presentation.feedback.depositSoundIntervalSeconds)): spatial("deposit", event.at, -4)
	update_timer += delta
	if update_timer < 0.2: return
	update_timer = 0
	for e in world.units.values() + world.structures.values():
		if e.owner != owner_id: continue
		var record := {"cargo": world.cargo_amount(e) if e.has("cargo") else 0}
		if known.has(e.id):
			if record.cargo > known[e.id].cargo: spatial("mining", world.entity_position(e), -7)
		known[e.id] = record
	for id in known.keys():
		if world.entity(int(id)).is_empty(): known.erase(id)
	var now := Time.get_ticks_msec()
	for key in sound_times.keys():
		if now - int(sound_times[key]) > 10000: sound_times.erase(key)

func _sound_due(key: String, seconds: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(sound_times.get(key, -10000)) < seconds * 1000: return false
	sound_times[key] = now
	return true
