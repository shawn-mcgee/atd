extends RefCounted
## Signaling stays connected. Game packets travel on reliable ordered RTC channels.
signal status_changed(message: String)
signal identity_ready(id: int, room: String)
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal message_received(id: int, message: Dictionary)
const Canonical = preload("res://core/canonical.gd")
const DEFAULT_URL := "wss://webrtc-coordinator.s-mcgeek07.workers.dev"
var own_id := 0
var room := ""
var hosting := false
var error := ""
var socket: WebSocketPeer
var connections: Dictionary = {}
var channels: Dictionary = {}
var opened: Dictionary = {}
var ice_servers: Array = []
var _url := ""
var _token := ""
var _closed_reported := false

func connect_room(base_url: String, as_host: bool, room_id: String, servers: Array) -> Error:
	close()
	_url = base_url.trim_suffix("/")
	if not (_url.begins_with("wss://") or _url.begins_with("ws://")):
		_fail("Coordinator URL must start with wss:// or ws://")
		return ERR_INVALID_PARAMETER
	if not as_host and room_id.strip_edges().is_empty():
		_fail("Enter a room code before joining")
		return ERR_INVALID_PARAMETER
	if not OS.has_feature("web") and not ClassDB.class_exists("WebRTCLibPeerConnection"):
		_fail("Desktop WebRTC needs the native extension. Run tools/setup-webrtc.py, then restart Godot.")
		return ERR_UNAVAILABLE
	hosting = as_host
	room = room_id.strip_edges().to_lower()
	ice_servers = servers.duplicate(true)
	socket = WebSocketPeer.new()
	socket.heartbeat_interval = 10.0
	_closed_reported = false
	var path := "/host" if hosting else "/join"
	if not room.is_empty(): path += "/" + room.uri_encode()
	status_changed.emit("Connecting to coordinator…")
	return socket.connect_to_url(_url + path)

func poll() -> void:
	if socket != null:
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			while socket.get_available_packet_count() > 0:
				var packet := socket.get_packet()
				if packet.size() > 131072: _fail("Signaling packet too large"); return
				var data = JSON.parse_string(packet.get_string_from_utf8())
				if not data is Dictionary: _fail("Invalid coordinator response"); return
				_signal_message(data)
		elif socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and not _closed_reported:
			_closed_reported = true
			status_changed.emit("Signaling disconnected; use Reconnect signaling. " + socket.get_close_reason())
	for id in connections.keys():
		var peer: WebRTCPeerConnection = connections[id]
		peer.poll()
		var channel: WebRTCDataChannel = channels[id]
		var state := channel.get_ready_state()
		if state == WebRTCDataChannel.STATE_OPEN:
			if not opened.has(id):
				opened[id] = true
				peer_connected.emit(int(id))
			while channel.get_available_packet_count() > 0:
				var packet := channel.get_packet()
				if packet.size() > 60000: _fail("Game packet too large"); return
				var data = JSON.parse_string(packet.get_string_from_utf8())
				if not data is Dictionary: _fail("Invalid game packet"); return
				message_received.emit(int(id), Canonical.normalize(data))
		elif state == WebRTCDataChannel.STATE_CLOSED or peer.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
			connections.erase(id); channels.erase(id); opened.erase(id)
			peer.close()
			peer_disconnected.emit(int(id))

func send_to(id: int, message: Dictionary) -> bool:
	if not opened.has(id): return false
	var bytes := Canonical.text(message).to_utf8_buffer()
	if bytes.size() > 60000: _fail("Game packet exceeds 60KB; reduce content size"); return false
	var channel: WebRTCDataChannel = channels[id]
	if channel.get_buffered_amount() > 1048576: _fail("Peer is not consuming game traffic"); return false
	var result := channel.put_packet(bytes)
	if result != OK: _fail("WebRTC send failed: " + error_string(result))
	return result == OK

func broadcast(message: Dictionary, except_id: int = 0) -> void:
	for id in opened.keys():
		if int(id) != except_id: send_to(int(id), message)

func reconnect_signaling() -> Error:
	if own_id == 0 or _token.is_empty(): return ERR_UNCONFIGURED
	if socket != null: socket.close()
	socket = WebSocketPeer.new()
	socket.heartbeat_interval = 10.0
	_closed_reported = false
	var path := "/host/" if hosting else "/join/"
	return socket.connect_to_url(_url + path + room.uri_encode() + "?me=%d&re=%s" % [own_id, _token])

func _signal_message(data: Dictionary) -> void:
	var kind: String = data.get("is", "")
	if kind in ["v1-host-room", "v1-join-room"]:
		if not data.get("ok", false): _fail(str(data.get("error", "Room rejected"))); return
		own_id = int(data.get("host_id", 1)) if hosting else int(data.get("peer_id", 0))
		room = str(data.get("room_id", ""))
		_token = str(data.get("re", ""))
		identity_ready.emit(own_id, room)
		status_changed.emit("Room %s · peer %d" % [room, own_id])
		if not hosting and not connections.has(1):
			var peer = _connection(1)
			if peer != null: peer.create_offer()
		return
	if kind == "v1-error": status_changed.emit(str(data.get("error", "Signaling error"))); return
	var sender := int(data.get("from_id", 0))
	if sender <= 0 or int(data.get("to_id", 0)) != own_id or (not hosting and sender != 1): return
	if not kind in ["v1-webrtc-offer", "v1-webrtc-answer", "v1-webrtc-ice-candidate"]: return
	var peer = _connection(sender)
	if peer == null: return
	if kind == "v1-webrtc-ice-candidate":
		peer.add_ice_candidate(str(data.get("media", "")), int(data.get("index", 0)), str(data.get("name", "")))
	else:
		var result: Error = peer.set_remote_description(str(data.get("type", "")), str(data.get("sdp", "")))
		if result != OK: _fail("WebRTC rejected a remote description")

func _connection(id: int):
	if connections.has(id): return connections[id]
	var peer := WebRTCPeerConnection.new()
	if peer.initialize({"iceServers": ice_servers}) != OK:
		_fail("Could not initialize WebRTC"); return null
	peer.session_description_created.connect(_description.bind(id))
	peer.ice_candidate_created.connect(_candidate.bind(id))
	var channel := peer.create_data_channel("atd-v2", {"negotiated": true, "id": 0, "ordered": true})
	if channel == null: _fail("Could not create WebRTC channel"); return null
	connections[id] = peer; channels[id] = channel
	return peer

func _description(type: String, sdp: String, id: int) -> void:
	if not connections.has(id): return
	connections[id].set_local_description(type, sdp)
	_send_signal({"is": "v1-webrtc-" + type, "type": type, "sdp": sdp, "from_id": own_id, "to_id": id})

func _candidate(media: String, index: int, name: String, id: int) -> void:
	_send_signal({"is": "v1-webrtc-ice-candidate", "media": media, "index": index, "name": name, "from_id": own_id, "to_id": id})

func _send_signal(message: Dictionary) -> void:
	if socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		socket.send_text(Canonical.text(message))
	else: _fail("Signaling disconnected during WebRTC negotiation; reconnect the room")

func _fail(message: String) -> void:
	error = message
	status_changed.emit(message)

func close() -> void:
	if socket != null: socket.close()
	for peer in connections.values(): peer.close()
	connections.clear(); channels.clear(); opened.clear()
	socket = null; own_id = 0; _token = ""; error = ""
