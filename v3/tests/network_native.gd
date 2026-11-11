extends SceneTree

var sessions: Array[NetworkSession] = []
var failures := 0
var ready_room := ""
var packets: Dictionary = {}
var host_lost := 0
var guest_lost := 0
var events: Array = []

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, message: String) -> void:
	if not condition: failures += 1; printerr("FAIL: ", message)

func wait_until(check: Callable, seconds: float = 12) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not check.call() and Time.get_ticks_msec() < end: await process_frame
	return bool(check.call())

func on_event(index: int, event: Dictionary) -> void:
	events.append({"index": index, "type": event.type})
	if event.type == "room_ready" and index == 0: ready_room = event.invitation
	if event.type == "packet": packets[index] = event.message
	if event.type == "host_lost": host_lost += 1
	if event.type == "peer_leave" and index == 0: guest_lost += 1
	if event.type in ["error", "connection_failed"]: printerr("NETWORK: ", event.get("message", ""))

func run() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/networking.json"))
	var count := 5
	var join_code := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--coordinator="):
			config.signaling.url = arg.trim_prefix("--coordinator="); config.ice.servers = []
		if arg == "--live": count = 2; config.ice.transportPolicy = "relay"
		if arg.begins_with("--join="): join_code = arg.trim_prefix("--join=")
	if "--main-host-lightless" in OS.get_cmdline_user_args():
		await main_host_lightless(config); return
	if not join_code.is_empty():
		await crossplay_guest(config, join_code); return
	for i in range(count):
		var session := NetworkSession.new(); root.add_child(session)
		session.configuration = config.duplicate(true)
		session.received.connect(func(event): on_event(i, event))
		sessions.append(session)
	verify(sessions[0].available, "Native WebRTC extension loads")
	verify(sessions[0].start("host") == "", "Native host can start without a browser")
	if not await wait_until(func(): return not ready_room.is_empty()): verify(false, "Coordinator creates the native room"); finish(); return
	for i in range(1, count): verify(sessions[i].start("guest", ready_room) == "", "Native guest starts")
	if not await wait_until(func(): return sessions[0].last_seen.size() == count - 1, 25):
		verify(false, "All native guests establish real WebRTC connections"); print("EVENT TYPES: ", events); finish(); return
	var random := RandomNumberGenerator.new(); random.seed = 472
	var blob := PackedByteArray(); blob.resize(100000)
	for i in range(blob.size()): blob[i] = random.randi_range(0, 255)
	var payload := {"blob": blob, "kind": "binary-check", "text": "Erebus".repeat(30000), "mixed": [0, 127, 128, 255], "integer_keys": {1: "preserved"}}
	sessions[0].send("", payload)
	verify(await wait_until(func(): return packets.size() == count - 1), "Large binary packets reach every guest")
	for i in range(1, count): verify(packets.get(i, {}) == payload, "Typed binary payload survives compression and fragmentation")
	packets.clear()
	sessions[1].send("1", {"kind": "order", "sequence": 1, "owner": 1})
	verify(await wait_until(func(): return packets.has(0)), "Guest orders reach the host")
	if count > 2:
		sessions[count - 1].leave()
		verify(await wait_until(func(): return guest_lost == 1), "Guest departure is reported once")
	sessions[0].leave()
	verify(await wait_until(func(): return host_lost == count - (2 if count > 2 else 1)), "Host loss ends every remaining guest session")
	finish()

func main_host_lightless(config: Dictionary) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted = true; game.network.configuration = config
	game._host()
	if not await wait_until(func(): return not game.network.invitation.is_empty(), 20): verify(false, "Main host starts"); finish(); return
	print("Lightless host ready: ", game.network.invitation)
	if not await wait_until(func(): return game.accepted_peers.size() == 1, 60): verify(false, "Main host admits guest"); finish(); return
	game._refresh_lobby_controls(); game.lightless_role.select(2)
	game._launch_hosted()
	verify(game.peer_owners.values().has(-1), "Host maps exactly one guest to the Lightless owner")
	if await wait_until(func(): return game.state.units.values().any(func(unit): return unit.kind == "father" and unit.get("manual_order", false)), 60):
		print("Native Lightless move accepted")
	else: verify(false, "Lightless guest sends an authoritative move"); finish(); return
	await wait_until(func(): return game.accepted_peers.is_empty(), 60)
	game._leave(); game.queue_free()
	finish()

func crossplay_guest(config: Dictionary, code: String) -> void:
	var session := NetworkSession.new(); root.add_child(session); sessions.append(session)
	session.configuration = config
	var state := {"admitted": false, "lost": false}
	session.received.connect(func(event):
		if event.type == "peer_join": session.send("1", {"kind": "hello", "hash": root.get_node("Settings").gameplay_hash, "protocol": int(config.gameProtocolVersion)})
		if event.type == "packet" and event.message.get("kind", "") == "welcome": state.admitted = true
		if event.type == "host_lost": state.lost = true)
	verify(session.start("guest", code) == "", "Native crossplay guest starts")
	verify(await wait_until(func(): return state.admitted), "Browser host admits the native guest")
	if state.admitted:
		print("Native guest admitted")
		verify(await wait_until(func(): return state.lost, 20), "Native guest detects browser host departure")
	finish()

func finish() -> void:
	for session in sessions: session.leave(); session.queue_free()
	await process_frame
	print("Native networking checks; failures: ", failures)
	quit(0 if failures == 0 else 1)
