extends RefCounted
## Predict missing frames as no new commands. AI runs inside the restored simulation.
signal frame_ready(frame: Dictionary)
signal confirmed(tick: int, state_hash: String)
signal events_confirmed(events: Array)
const Simulation = preload("res://core/simulation.gd")
const Canonical = preload("res://core/canonical.gd")
var simulation = Simulation.new()
var local_id := 1
var human_ids: Array[int] = []
var frames: Dictionary = {}
var checkpoints: Dictionary = {}
var hashes: Dictionary = {}
var pending: Array = []
var confirmed_tick := -1
var rollbacks := 0
var replayed_ticks := 0
var error := ""
var window := 120
var input_delay := 2

func initialize(content: Dictionary, players: Array, seed_value: int, own_id: int) -> void:
	local_id = own_id
	window = int(content.settings.rollback_ticks)
	input_delay = int(content.settings.input_delay)
	human_ids.clear(); frames.clear(); checkpoints.clear(); hashes.clear(); pending.clear()
	confirmed_tick = -1; rollbacks = 0; replayed_ticks = 0; error = ""
	for player in players:
		if player.controller == "human": human_ids.append(int(player.id))
	human_ids.sort()
	simulation.initialize(content, players, seed_value)
	for tick in input_delay:
		frames[tick] = {}
		for id in human_ids: frames[tick][id] = []
	checkpoints[0] = simulation.checkpoint()
	hashes[0] = simulation.state_hash()

func queue(command: Dictionary) -> bool:
	if not human_ids.has(local_id) or not error.is_empty(): return false
	var command_list = _sanitize([command])
	if command_list == null: return false
	if pending.size() >= 32: return false
	pending.append(command_list[0])
	return true

func advance() -> bool:
	if not error.is_empty(): return false
	var tick := int(simulation.state.tick)
	# A slow/missing peer stalls the session before unconfirmed history is discarded.
	if tick - confirmed_tick > window: return false
	var future := tick + input_delay
	if human_ids.has(local_id) and not frames.get(future, {}).has(local_id):
		var commands := pending.duplicate(true)
		pending.clear()
		if not receive(local_id, future, commands): return false
		frame_ready.emit({"tick": future, "commands": commands})
	simulation.step(_commands_at(tick))
	_save()
	_confirm()
	_trim()
	return true

func receive(sender: int, tick: int, commands: Array) -> bool:
	if not error.is_empty(): return false
	if not human_ids.has(sender) or tick < 0 or tick > int(simulation.state.tick) + window * 2:
		error = "Invalid player or frame tick"; return false
	var clean = _sanitize(commands)
	if clean == null:
		error = "Invalid command payload"; return false
	if frames.get(tick, {}).has(sender):
		if Canonical.text(frames[tick][sender]) != Canonical.text(clean):
			error = "Conflicting input for player %d at tick %d" % [sender, tick]
		return error.is_empty()
	if tick <= confirmed_tick:
		error = "Input older than retained confirmed history"; return false
	if not frames.has(tick): frames[tick] = {}
	frames[tick][sender] = clean
	if tick < int(simulation.state.tick) and not clean.is_empty():
		if not checkpoints.has(tick):
			error = "Rollback window exceeded"; return false
		var end := int(simulation.state.tick)
		simulation.restore(checkpoints[tick])
		rollbacks += 1
		while int(simulation.state.tick) < end:
			simulation.step(_commands_at(int(simulation.state.tick)))
			_save()
			replayed_ticks += 1
	_confirm()
	return true

func _commands_at(tick: int) -> Array:
	var result: Array = []
	for player in human_ids:
		for command in frames.get(tick, {}).get(player, []):
			var entry: Dictionary = command.duplicate(true)
			entry.player = player
			result.append(entry)
	return result

func _save() -> void:
	var tick := int(simulation.state.tick)
	checkpoints[tick] = simulation.checkpoint()
	hashes[tick] = simulation.state_hash()

func _confirm() -> void:
	while confirmed_tick + 1 < int(simulation.state.tick):
		var next := confirmed_tick + 1
		var complete := true
		for id in human_ids:
			if not frames.get(next, {}).has(id): complete = false
		if not complete: return
		confirmed_tick = next
		events_confirmed.emit(checkpoints[next + 1].events.duplicate(true))
		confirmed.emit(next + 1, hashes[next + 1])

func _trim() -> void:
	var oldest := maxi(0, int(simulation.state.tick) - window - 1)
	for table in [frames, checkpoints, hashes]:
		for tick in table.keys():
			if int(tick) < oldest: table.erase(tick)

func _sanitize(commands: Array):
	if commands.size() > 32: return null
	var result: Array = []
	for raw in commands:
		if not raw is Dictionary: return null
		var command: Dictionary = Canonical.normalize(raw)
		if not command.get("kind") in ["move", "attack", "stop", "train", "attack_veil", "veil_stance"] or not command.get("actors") is Array or command.actors.size() > 64: return null
		var actors: Array = []
		for id in command.actors:
			if not id is int or id < 1 or id > 1000000: return null
			if not actors.has(id): actors.append(id)
		actors.sort()
		var clean := {"kind": command.kind, "actors": actors}
		match command.kind:
			"move", "attack_veil":
				if not simulation.valid_point(command.get("point")): return null
				clean.point = command.point.duplicate()
			"veil_stance":
				if not command.get("stance") in ["neutral", "defensive", "offensive"]: return null
				clean.stance = command.stance
				if command.stance == "offensive":
					if not simulation.valid_point(command.get("point")): return null
					clean.point = command.point.duplicate()
			"attack":
				if not command.get("target") is int or command.target < 1 or command.target > 1000000: return null
				clean.target = command.target
			"train":
				if not command.get("definition") is String or not simulation.content.units.has(command.definition): return null
				clean.definition = command.definition
		result.append(clean)
	return result
