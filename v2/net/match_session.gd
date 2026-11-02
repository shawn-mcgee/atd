extends RefCounted
## The host coordinates a lobby and relays authenticated input, not simulation state.
signal status_changed(message: String)
signal lobby_changed(players: Array)
signal match_started
const Content = preload("res://core/content.gd")
const Rules = preload("res://core/match_rules.gd")
const Canonical = preload("res://core/canonical.gd")
const Rollback = preload("res://net/rollback_session.gd")
const Transport = preload("res://net/coordinator_transport.gd")
const PROTOCOL := 22
var transport = Transport.new()
var rollback
var roster: Dictionary = {}
var running := false
var networked := false
var own_id := 1
var faction := "human"
var local_control := "human"
var error := ""
var descriptor: Dictionary = {}
var ready_peers: Dictionary = {}
var remote_hashes: Dictionary = {}

func _init() -> void:
	transport.status_changed.connect(_status)
	transport.identity_ready.connect(_identity)
	transport.peer_connected.connect(_connected)
	transport.peer_disconnected.connect(_disconnected)
	transport.message_received.connect(_message)

func start_local(content: Dictionary, seed_value: int, player_faction: String) -> void:
	close()
	own_id = 1
	faction = player_faction
	var other := "lightless" if faction == "human" else "human"
	var players := Rules.participants([{ "id": 1, "faction": faction, "controller": "human"}, {"id": 2, "faction": other, "controller": "human"}])
	_prepare(content, players, seed_value)
	rollback.local_ids.assign([1, 2])
	local_control = faction
	_begin()

func controls(player: int) -> bool:
	if networked: return player == own_id
	if rollback == null: return false
	for participant in rollback.simulation.state.players:
		if int(participant.id) == player: return local_control == "both" or participant.faction == local_control
	return false

func set_local_control(mode: String) -> void:
	if networked or rollback == null or not mode in ["human", "lightless", "both"]: return
	local_control = mode

func queue(command: Dictionary, player: int = -1) -> bool:
	if player == -1: player = own_id
	return rollback != null and controls(player) and rollback.queue(command, player)

func connect_room(url: String, host: bool, room: String, player_faction: String, ice: Array) -> Error:
	close()
	networked = true
	faction = player_faction
	return transport.connect_room(url, host, room, ice)

func poll() -> void:
	if networked: transport.poll()
	if networked and not transport.error.is_empty(): _fail(transport.error)
	if rollback != null and not rollback.error.is_empty(): _fail(rollback.error)

func start_network(content: Dictionary, seed_value: int) -> bool:
	if not transport.hosting or own_id != 1 or running or not descriptor.is_empty(): return false
	for id in transport.opened:
		if not roster.has(id):
			status_changed.emit("Wait for every connected peer to finish joining")
			return false
	var players := Rules.participants(roster.values())
	if players.is_empty():
		status_changed.emit("Requires at least one Human player and exactly one Lightless player (maximum 8 players)")
		return false
	var packet := {"type": "prepare", "descriptor": {"protocol": PROTOCOL, "engine": _engine(), "seed": seed_value, "content": content, "players": players}}
	if Canonical.text(packet).to_utf8_buffer().size() > 60000:
		status_changed.emit("Network content must fit in a 60KB match descriptor")
		return false
	_prepare(content, players, seed_value)
	ready_peers = {1: true}
	transport.broadcast({"type": "prepare", "descriptor": descriptor})
	_try_begin()
	return true

func advance() -> bool:
	if not running or rollback == null: return false
	var result: bool = rollback.advance()
	if not rollback.error.is_empty(): _fail(rollback.error)
	return result

func _identity(id: int, _room: String) -> void:
	own_id = id
	if transport.hosting:
		roster[own_id] = {"id": own_id, "faction": faction, "controller": "human"}
		_lobby()

func _status(message: String) -> void:
	status_changed.emit(message)

func _connected(id: int) -> void:
	if transport.hosting:
		if running or not descriptor.is_empty(): transport.send_to(id, {"type": "reject", "reason": "Match already started; join a fresh lobby"})
	else:
		transport.send_to(1, {"type": "hello", "protocol": PROTOCOL, "engine": _engine(), "faction": faction})

func _disconnected(id: int) -> void:
	if running or not descriptor.is_empty():
		_fail("Peer %d disconnected. This prototype requires a new match." % id)
	else:
		roster.erase(id)
		if transport.hosting: _lobby()

func _message(sender: int, message: Dictionary) -> void:
	if not message.get("type") is String:
		_fail("Invalid packet type"); return
	var type: String = message.get("type", "")
	if type == "hello" and transport.hosting:
		if running or not descriptor.is_empty(): return
		if message.get("protocol") != PROTOCOL or message.get("engine") != _engine() or not message.get("faction") in ["human", "lightless"]:
			transport.send_to(sender, {"type": "reject", "reason": "Protocol, engine version or faction mismatch"})
			return
		roster[sender] = {"id": sender, "faction": message.faction, "controller": "human"}
		_lobby()
	elif type == "lobby" and not transport.hosting and sender == 1 and message.get("players") is Array:
		lobby_changed.emit(message.players)
	elif type == "prepare" and not transport.hosting and sender == 1:
		if running or rollback != null: return
		var info = message.get("descriptor")
		if not info is Dictionary or info.get("protocol") != PROTOCOL or info.get("engine") != _engine() or not info.get("players") is Array or not info.get("content") is Dictionary or not info.get("seed") is int:
			_fail("Invalid match descriptor"); return
		var content = Content.new()
		if not content.load_text(Canonical.text(info.content)):
			_fail("Host content invalid: " + "; ".join(content.errors)); return
		var players := Rules.participants(info.players)
		if players.is_empty() or Canonical.text(players) != Canonical.text(info.players) or not players.any(func(player): return int(player.id) == own_id and player.controller == "human"):
			_fail("Invalid participant configuration"); return
		_prepare(content.data, players, int(info.get("seed", 0)))
		if Canonical.hash_of(descriptor) != Canonical.hash_of(info): _fail("Match descriptor mismatch"); return
		transport.send_to(1, {"type": "ready", "hash": Canonical.hash_of(descriptor)})
	elif type == "ready" and transport.hosting and roster.has(sender):
		if running or descriptor.is_empty(): return
		if message.get("hash") != Canonical.hash_of(descriptor): _fail("Peer content/configuration mismatch"); return
		ready_peers[sender] = true
		_try_begin()
	elif type == "begin" and not transport.hosting and sender == 1:
		if rollback == null or message.get("hash") != Canonical.hash_of(descriptor): _fail("Invalid match start"); return
		_begin()
	elif type == "frame" and running:
		if not message.get("player") is int:
			_fail("Invalid input player"); return
		var player := int(message.get("player", 0))
		if (transport.hosting and player != sender) or not message.get("commands") is Array or not message.get("tick") is int:
			_fail("Unauthenticated input frame"); return
		if not rollback.receive(player, int(message.tick), message.commands): _fail(rollback.error); return
		if transport.hosting: transport.broadcast(message, sender)
	elif type == "hash" and running:
		if not message.get("tick") is int or not message.get("hash") is String or str(message.hash).length() != 64: _fail("Invalid hash packet"); return
		if int(message.tick) < 0 or int(message.tick) > int(rollback.simulation.state.tick) + rollback.window * 2: _fail("Invalid hash tick"); return
		if remote_hashes.size() > 512: _fail("Too many pending hashes"); return
		remote_hashes["%d:%d" % [sender, message.tick]] = message
		_compare_hashes()
	elif type == "reject" and sender == 1: _fail(str(message.get("reason", "Match rejected")))

func _lobby() -> void:
	var players := roster.values()
	players.sort_custom(func(a, b): return int(a.id) < int(b.id))
	lobby_changed.emit(players)
	transport.broadcast({"type": "lobby", "players": players})

func _prepare(content: Dictionary, players: Array, seed_value: int) -> void:
	descriptor = {"protocol": PROTOCOL, "engine": _engine(), "seed": seed_value, "content": content.duplicate(true), "players": players.duplicate(true)}
	rollback = Rollback.new()
	rollback.initialize(content, players, seed_value, own_id, 20)
	rollback.frame_ready.connect(_send_frame)
	rollback.confirmed.connect(_confirmed)
	status_changed.emit("Content %s · waiting for matching peers" % Canonical.hash_of(descriptor).left(12))

func _try_begin() -> void:
	for player in descriptor.players:
		if player.controller == "human" and not ready_peers.has(int(player.id)): return
	transport.broadcast({"type": "begin", "hash": Canonical.hash_of(descriptor)})
	_begin()

func _begin() -> void:
	if running: return
	running = true
	match_started.emit()
	status_changed.emit("Match started · content/configuration verified")

func _send_frame(frame: Dictionary) -> void:
	if not networked: return
	var packet := {"type": "frame", "player": own_id, "tick": frame.tick, "commands": frame.commands}
	if transport.hosting: transport.broadcast(packet)
	else: transport.send_to(1, packet)

func _confirmed(tick: int, state_hash: String) -> void:
	if networked and tick % 20 == 0:
		var message := {"type": "hash", "tick": tick, "hash": state_hash}
		if transport.hosting: transport.broadcast(message)
		else: transport.send_to(1, message)
	_compare_hashes()

func _compare_hashes() -> void:
	for key in remote_hashes.keys():
		var message: Dictionary = remote_hashes[key]
		var tick := int(message.tick)
		if tick > rollback.confirmed_tick + 1: continue
		# Debug/diagnostic peers may request a retained non-periodic boundary.
		if not rollback.hashes.has(tick) and rollback.checkpoints.has(tick):
			rollback.hashes[tick] = JSON.stringify(rollback.checkpoints[tick], "", true, true).sha256_text()
		if rollback.hashes.has(tick) and rollback.hashes[tick] != message.hash:
			_fail("DESYNC at confirmed tick %d" % tick)
		remote_hashes.erase(key)

func _fail(message: String) -> void:
	error = message
	running = false
	status_changed.emit(message)

func _engine() -> String:
	var version := Engine.get_version_info()
	return "%s.%s.%s" % [version.major, version.minor, version.patch]

func close() -> void:
	transport.close()
	running = false; networked = false; rollback = null
	roster.clear(); descriptor.clear(); ready_peers.clear(); remote_hashes.clear(); error = ""
