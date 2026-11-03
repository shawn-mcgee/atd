extends SceneTree
const Actor = preload("res://core/actor.gd")
const Session = preload("res://net/match_session.gd")
const Content = preload("res://core/content.gd")
const Transport = preload("res://net/coordinator_transport.gd")
var host = Session.new()
var client = DelayedSession.new()
var start_time := 0
var started := false
var ordered := false
var finished := false
var room := ""

class DelayedSession extends "res://net/match_session.gd":
	var held: Dictionary = {}
	func _send_frame(frame: Dictionary) -> void:
		if int(frame.tick) == 22:
			held = frame.duplicate(true)
			return
		if int(frame.tick) == 30 and not held.is_empty():
			super._send_frame(held)
			held.clear()
		super._send_frame(frame)

func _initialize() -> void:
	start_time = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--room="): room = argument.trim_prefix("--room=")
	host.transport.identity_ready.connect(func(_id, code):
		room = code
		client.connect_room(Transport.DEFAULT_URL, false, room, "lightless", []))
	host.status_changed.connect(func(message): print("HOST ", message))
	client.status_changed.connect(func(message): print("CLIENT ", message))
	var result: Error = host.connect_room(Transport.DEFAULT_URL, true, room, "human", [])
	if result != OK: _finish(false, "Host connect: " + host.transport.error)

func _process(_dt: float) -> bool:
	if finished: return false
	host.poll(); client.poll()
	if not host.error.is_empty() or not client.error.is_empty():
		_finish(false, host.error + client.error)
		return false
	if host.roster.size() == 2 and not started:
		var content = Content.new()
		if not content.load_file("res://content/default.json"):
			_finish(false, "Content invalid"); return false
		started = host.start_network(content.data, 42)
	if host.running and client.running:
		if not ordered and int(client.rollback.simulation.state.tick) == 20:
			var ids: Array = []
			for actor: Actor in client.rollback.simulation.state.actors:
				if int(actor.owner) == client.own_id and actor.definition == "scavenger": ids.append(int(actor.id))
			client.rollback.queue({"kind": "move", "actors": ids, "point": [0, 0, 0]})
			ordered = true
		if int(host.rollback.simulation.state.tick) < 100: host.advance()
		if int(client.rollback.simulation.state.tick) < 100: client.advance()
		if host.rollback.confirmed_tick == 99 and client.rollback.confirmed_tick == 99:
			var equal: bool = host.rollback.simulation.state_hash() == client.rollback.simulation.state_hash()
			_finish(equal and host.rollback.rollbacks > 0, "WebRTC match, relayed late input, confirmed hash equality; rollbacks=%d" % host.rollback.rollbacks)
	if Time.get_ticks_msec() - start_time > 45000: _finish(false, "Network smoke test timed out")
	return false

func _finish(ok: bool, message: String) -> void:
	finished = true
	print("ATD_NETWORK " + JSON.stringify({"ok": ok, "message": message}))
	host.close(); client.close()
	quit(0 if ok else 1)
