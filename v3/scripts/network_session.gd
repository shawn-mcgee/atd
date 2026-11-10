class_name NetworkSession
extends Node

signal received(event: Dictionary)
var bridge
var role := "solo"
var self_id := ""
var host_id := ""
var invitation := ""
var available := false
var terminal := false
var diagnostics_enabled := false
var configuration: Dictionary = {}
var socket: WebSocketPeer
var peer: WebRTCMultiplayerPeer
var connections: Dictionary = {}
var pending_ice: Dictionary = {}
var last_seen: Dictionary = {}
var outgoing: Dictionary = {}
var incoming: Dictionary = {}
var coordinator_id := 0
var coordinator_host := 0
var expected_host := 0
var room_code := ""
var room_ready := false
var deadline := 0
var heartbeat_at := 0
var serial := 0
var signaling_warning := false
const MAGIC := 0x41544433
const RELIABLE_CHANNELS := [MultiplayerPeer.TRANSFER_MODE_RELIABLE, MultiplayerPeer.TRANSFER_MODE_RELIABLE]

func _ready() -> void:
	configuration = get_node("/root/Settings").network.duplicate(true)
	available = OS.has_feature("web") or ClassDB.class_exists("WebRTCLibPeerConnection")
	if OS.has_feature("web"):
		bridge = JavaScriptBridge.get_interface("ATDNetwork")
		if bridge != null:
			diagnostics_enabled = bool(bridge.diagnosticsEnabled)
			var options = JSON.parse_string(str(bridge.options()))
			if options is Dictionary:
				var url := str(options.get("coordinator", ""))
				if not url.is_empty():
					configuration.signaling.url = url
					if url.begins_with("ws://127.0.0.1:") or url.begins_with("ws://localhost:"): configuration.ice.servers = []
				if options.get("relayOnly", false): configuration.ice.transportPolicy = "relay"

func start(mode: String, code: String = "") -> String:
	if not available: return "WebRTC extension is unavailable on this platform"
	leave()
	if not mode in ["host", "guest"]: return "Invalid network role"
	role = mode
	if mode == "guest":
		var parts := code.strip_edges().split(":")
		room_code = parts[0]
		if parts.size() > 2 or room_code.is_empty() or room_code.length() > 128 or not ("r" + room_code.replace("-", "").replace("_", "")).is_valid_identifier():
			role = "solo"; return "Paste a valid room invitation or room code"
		if parts.size() == 2:
			if not parts[1].is_valid_int() or int(parts[1]) <= 0: role = "solo"; return "Invalid invitation host"
			expected_host = int(parts[1])
	var url := str(configuration.signaling.url).trim_suffix("/")
	if not url.begins_with("wss://") and not url.begins_with("ws://"): role = "solo"; return "Coordinator URL must use WebSocket"
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 1048576; socket.outbound_buffer_size = 1048576
	var error := socket.connect_to_url(url + ("/host" if mode == "host" else "/join/" + room_code.uri_encode()))
	if error != OK: leave(); return "Cannot connect to the multiplayer coordinator"
	deadline = Time.get_ticks_msec() + int(configuration.signaling.connectTimeoutMs)
	heartbeat_at = Time.get_ticks_msec()
	return ""

func _process(_delta: float) -> void:
	if socket != null and role != "solo": _poll_network()
	if bridge != null:
		var events = JSON.parse_string(str(bridge.poll()))
		if events is Array:
			for event in events: received.emit(event)

func _poll_network() -> void:
	var now := Time.get_ticks_msec()
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		for i in range(mini(socket.get_available_packet_count(), 128)):
			var bytes := socket.get_packet()
			if bytes.size() > 1048576: continue
			var message = JSON.parse_string(bytes.get_string_from_utf8())
			if message is Dictionary: _signal(message)
			if socket == null: return
	elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if not room_ready: _failure("Coordinator closed before room setup completed"); return
		if not signaling_warning:
			signaling_warning = true
			received.emit({"type": "error", "message": "Coordinator disconnected. Existing peers remain connected; reopen the lobby to invite more players."})
	if not room_ready and now >= deadline: _failure("Coordinator connection timed out"); return
	if peer == null: return
	peer.poll()
	if peer == null: return
	for i in range(mini(peer.get_available_packet_count(), int(configuration.limits.receiveFramesPerPoll))):
		var sender := peer.get_packet_peer()
		var channel := peer.get_packet_channel()
		var bytes := peer.get_packet()
		if last_seen.has(sender):
			last_seen[sender] = now
			if channel != 2: _receive(sender, channel, bytes)
		if peer == null: return
	for id in connections.keys():
		if not last_seen.has(id) and now > int(connections[id].deadline):
			received.emit({"type": "error", "message": "WebRTC connection timed out. Check the room code and TURN availability."})
			_lost(id)
		if peer == null: return
	for id in last_seen.keys():
		if now - int(last_seen[id]) >= int(configuration.liveness.peerTimeoutMs): _lost(id)
		if peer == null: return
	if now >= heartbeat_at:
		heartbeat_at = now + int(configuration.liveness.heartbeatIntervalMs)
		for id in last_seen: _put(id, 2, PackedByteArray([104]))
	_flush(now)

func _signal(m: Dictionary) -> void:
	var kind := str(m.get("is", ""))
	if kind in ["v1-host-room", "v1-join-room"]:
		if room_ready or kind != ("v1-host-room" if role == "host" else "v1-join-room"): return
		if not m.get("ok", false): _failure(str(m.get("error", "Room rejected"))); return
		coordinator_host = int(m.get("host_id", 0))
		coordinator_id = coordinator_host if role == "host" else int(m.get("peer_id", 0))
		if coordinator_host <= 0 or coordinator_id <= (0 if role == "host" else 1) or coordinator_id > 2147483647 or not m.get("room_id") is String: _failure("Invalid coordinator room response"); return
		if expected_host > 0 and expected_host != coordinator_host: _failure("Invitation host does not match this room"); return
		room_code = str(m.room_id)
		peer = WebRTCMultiplayerPeer.new()
		var error := peer.create_server(RELIABLE_CHANNELS) if role == "host" else peer.create_client(coordinator_id, RELIABLE_CHANNELS)
		if error != OK: _failure("Cannot initialize Godot multiplayer peer"); return
		peer.peer_connected.connect(_joined); peer.peer_disconnected.connect(_lost)
		self_id = "1" if role == "host" else str(coordinator_id); host_id = "1"
		invitation = "%s:%d" % [room_code, coordinator_host]
		room_ready = true
		received.emit({"type": "room_ready", "self": self_id, "host": host_id, "invitation": invitation})
		if role == "guest":
			var connection := _create_connection(1)
			if connection != null and connection.create_offer() != OK: _failure("Cannot create WebRTC offer")
		return
	if not room_ready or not m.get("from_id") is float and not m.get("from_id") is int: return
	var sender := int(m.from_id)
	if int(m.get("to_id", 0)) != coordinator_id or sender <= 0: return
	if role == "guest" and sender != coordinator_host: return
	var id := 1 if role == "guest" else sender
	if id == int(self_id): return
	if kind == "v1-webrtc-offer" and role == "host" and m.get("type") == "offer" and m.get("sdp") is String:
		if connections.has(id) or connections.size() >= int(configuration.limits.maxPeers): return
		var connection := _create_connection(id)
		if connection != null: _remote(id, "offer", str(m.sdp))
	elif kind == "v1-webrtc-answer" and role == "guest" and m.get("type") == "answer" and m.get("sdp") is String:
		if connections.has(id): _remote(id, "answer", str(m.sdp))
	elif kind == "v1-webrtc-ice-candidate" and m.get("name") is String and str(m.name).length() < 8192:
		if configuration.ice.transportPolicy == "relay" and not str(m.name).contains(" typ relay "): return
		if connections.has(id) and connections[id].remote:
			connections[id].pc.add_ice_candidate(str(m.get("media", "")), int(m.get("index", 0)), str(m.name))
		elif pending_ice.size() < int(configuration.limits.maxPeers) or pending_ice.has(id):
			if not pending_ice.has(id): pending_ice[id] = []
			if pending_ice[id].size() < 128: pending_ice[id].append(m)

func _create_connection(id: int) -> WebRTCPeerConnection:
	var pc := WebRTCPeerConnection.new()
	var servers: Array = configuration.ice.servers
	if not OS.has_feature("web"):
		# The bundled native extension uses libjuice, which supports UDP TURN.
		servers = servers.filter(func(server): return not str(server.urls).begins_with("turns:") and not str(server.urls).contains("transport=tcp"))
	if pc.initialize({"iceServers": servers, "iceTransportPolicy": configuration.ice.transportPolicy}) != OK:
		_failure("Cannot initialize WebRTC connection"); return null
	connections[id] = {"pc": pc, "remote": false, "deadline": Time.get_ticks_msec() + int(configuration.signaling.connectTimeoutMs)}
	var weak_pc: WeakRef = weakref(pc)
	pc.session_description_created.connect(func(type: String, sdp: String):
		if not connections.has(id): return
		var connection: WebRTCPeerConnection = weak_pc.get_ref()
		if connection == null: return
		connection.set_local_description(type, sdp)
		_forward("v1-webrtc-offer" if type == "offer" else "v1-webrtc-answer", id, {"type": type, "sdp": sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, name: String):
		if configuration.ice.transportPolicy == "relay" and not name.contains(" typ relay "): return
		_forward("v1-webrtc-ice-candidate", id, {"media": media, "index": index, "name": name}))
	if peer.add_peer(pc, id) != OK: _failure("Cannot add Godot WebRTC peer"); return null
	return pc

func _remote(id: int, type: String, sdp: String) -> void:
	if connections[id].remote: return
	if connections[id].pc.set_remote_description(type, sdp) != OK: _lost(id); return
	connections[id].remote = true
	for m in pending_ice.get(id, []): connections[id].pc.add_ice_candidate(str(m.media), int(m.index), str(m.name))
	pending_ice.erase(id)

func _forward(kind: String, id: int, payload: Dictionary) -> void:
	if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN: return
	payload = payload.duplicate()
	payload["is"] = kind; payload.from_id = coordinator_id; payload.to_id = coordinator_host if role == "guest" else id
	socket.send_text(JSON.stringify(payload))

func _joined(id: int) -> void:
	if last_seen.has(id): return
	last_seen[id] = Time.get_ticks_msec()
	outgoing[id] = {"commands": [], "state": {}, "latest": {}, "sequence": 0}
	received.emit({"type": "peer_join", "peer": str(id)})

func send(target: String, packet: Dictionary) -> void:
	if terminal or peer == null: return
	var encoded := var_to_bytes(packet)
	if encoded.size() > int(configuration.limits.maxPacketBytes): received.emit({"type": "error", "message": "Network packet exceeds size limit"}); return
	var body := PackedByteArray(); body.resize(5); body[0] = 0; body.encode_u32(1, encoded.size())
	if encoded.size() >= int(configuration.limits.compressionThresholdBytes): body[0] = 1; body.append_array(encoded.compress(FileAccess.COMPRESSION_ZSTD))
	else: body.append_array(encoded)
	var recipients: Array = last_seen.keys() if target.is_empty() else [int(target)]
	for id in recipients:
		if not outgoing.has(id): continue
		serial += 1
		var item := {"bytes": body, "offset": 0, "serial": serial, "started": Time.get_ticks_msec()}
		if packet.get("kind", "") == "state": outgoing[id].latest = item
		elif outgoing[id].commands.size() < int(configuration.limits.commandQueueLimit): outgoing[id].commands.append(item)
		else: received.emit({"type": "error", "message": "Command queue is full; order was not sent"})

func _flush(now: int) -> void:
	for id in outgoing.keys():
		if peer == null or not peer.has_peer(id): continue
		var queue: Dictionary = outgoing[id]
		for channel in [0, 1]:
			if channel == 1 and queue.state.is_empty() and not queue.latest.is_empty(): queue.state = queue.latest; queue.latest = {}
			var frames := 0
			while frames < int(configuration.limits.sendFramesPerPoll):
				var item: Dictionary = queue.commands[0] if channel == 0 and not queue.commands.is_empty() else queue.state if channel == 1 else {}
				if item.is_empty(): break
				if now - int(item.started) > int(configuration.limits.sendTimeoutMs): _lost(id); break
				var channels: Array = peer.get_peer(id).channels
				if channels[0 if channel == 0 else 3].get_buffered_amount() > int(configuration.limits.bufferedAmountBytes): break
				var length := mini(int(configuration.limits.framePayloadBytes), item.bytes.size() - int(item.offset))
				var frame := PackedByteArray(); frame.resize(16)
				frame.encode_u32(0, MAGIC); frame.encode_u32(4, int(item.serial)); frame.encode_u32(8, int(item.offset)); frame.encode_u32(12, item.bytes.size())
				frame.append_array(item.bytes.slice(int(item.offset), int(item.offset) + length))
				if _put(id, channel, frame) != OK: _lost(id); break
				item.offset += length; frames += 1
				if item.offset == item.bytes.size():
					if channel == 0: queue.commands.pop_front()
					else: queue.state = {}; break
			if peer == null or not outgoing.has(id): break

func _put(id: int, channel: int, bytes: PackedByteArray) -> Error:
	if peer == null or not peer.has_peer(id): return ERR_UNAVAILABLE
	peer.set_target_peer(id); peer.transfer_channel = channel; peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return peer.put_packet(bytes)

func _receive(id: int, channel: int, frame: PackedByteArray) -> void:
	if frame.size() < 17 or frame.decode_u32(0) != MAGIC: _lost(id); return
	var sequence := frame.decode_u32(4); var offset := frame.decode_u32(8); var total := frame.decode_u32(12)
	if total <= 0 or total > int(configuration.limits.maxPacketBytes) + 5: _lost(id); return
	var key := "%d:%d" % [id, channel]
	if offset == 0: incoming[key] = {"serial": sequence, "total": total, "bytes": PackedByteArray()}
	var item: Dictionary = incoming.get(key, {})
	if item.is_empty() or item.serial != sequence or item.total != total or item.bytes.size() != offset or offset + frame.size() - 16 > total: _lost(id); return
	item.bytes.append_array(frame.slice(16))
	if item.bytes.size() != total: return
	incoming.erase(key)
	var body: PackedByteArray = item.bytes
	if body.size() < 5 or not body[0] in [0, 1]: _lost(id); return
	var expanded := body.decode_u32(1)
	if expanded <= 0 or expanded > int(configuration.limits.maxPacketBytes): _lost(id); return
	var encoded := body.slice(5).decompress(expanded, FileAccess.COMPRESSION_ZSTD) if body[0] == 1 else body.slice(5)
	if encoded.size() != expanded: _lost(id); return
	var value = bytes_to_var(encoded)
	if value is Dictionary: received.emit({"type": "packet", "peer": str(id), "message": value})

func _lost(id: int) -> void:
	if not connections.has(id) and not last_seen.has(id): return
	var connection: Dictionary = connections.get(id, {})
	connections.erase(id); pending_ice.erase(id); last_seen.erase(id); outgoing.erase(id)
	if not connection.is_empty(): connection.pc.close()
	for key in incoming.keys():
		if str(key).begins_with(str(id) + ":"): incoming.erase(key)
	if peer != null and peer.has_peer(id): peer.remove_peer(id)
	if role == "guest" and id == 1:
		leave(); terminal = true; received.emit({"type": "host_lost"})
	else: received.emit({"type": "peer_leave", "peer": str(id)})

func _failure(message: String) -> void:
	leave(); received.emit({"type": "connection_failed", "message": message})

func leave() -> void:
	if socket != null: socket.close(); socket = null
	for connection in connections.values(): connection.pc.close()
	if peer != null: peer.close(); peer = null
	connections.clear(); pending_ice.clear(); last_seen.clear(); outgoing.clear(); incoming.clear()
	role = "solo"; terminal = false; room_ready = false; signaling_warning = false
	self_id = ""; host_id = ""; invitation = ""; expected_host = 0; coordinator_id = 0; coordinator_host = 0

func diagnostics(value: Dictionary) -> void:
	if bridge != null:
		value.transport = {"active": room_ready, "engine": "WebRTCMultiplayerPeer", "peers": last_seen.keys(), "role": role}
		bridge.updateDiagnostics(JSON.stringify(value))

func _exit_tree() -> void:
	leave()
