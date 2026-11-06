extends SceneTree
const Content = preload("res://core/content.gd")
const Session = preload("res://net/match_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var content = Content.new()
	content.load_file("res://content/default.json")
	var session = Session.new()
	session.start_local(content.data, 42, "human")
	session.advance()
	session._message(1, {"type": "hash", "tick": 1, "hash": "0".repeat(64)})
	_check(not session.running and "DESYNC" in session.error, "confirmed hash mismatch halts the session")
	session.close()
	session.start_local(content.data, 42, "human")
	session.transport.hosting = true
	session._message(9, {"type": "frame", "player": 1, "tick": 2, "commands": []})
	_check(not session.running and "Unauthenticated" in session.error, "relay cannot impersonate another player")
	session.close()
	session = Session.new()
	session._message(1, {"type": []})
	_check("Invalid packet" in session.error, "non-string packet type is rejected without a script error")
	session.close()
	session.start_local(content.data, 42, "human")
	session._message(1, {"type": "frame", "player": {}, "tick": 2, "commands": []})
	_check("Invalid input player" in session.error, "non-numeric sender is rejected without a script error")
	session.close()
	session = Session.new()
	session._message(1, {"type": "prepare", "descriptor": {"protocol": -1}})
	_check(not session.error.is_empty() and session.rollback == null, "invalid handshake rejected before simulation")
	session.close()
	session.start_local(content.data, 42, "human")
	var older: Dictionary = session.descriptor.duplicate(true)
	older.protocol = 22
	session.close(); session = Session.new(); session.own_id = 1
	session._message(1, {"type": "prepare", "descriptor": older})
	_check(session.error == "Invalid match descriptor" and session.rollback == null, "JSON-hash protocol 22 peers are rejected before starting an ATD1 session")
	session.close()
	session = Session.new()
	session.transport.hosting = true
	session.roster = {1: {"id": 1, "faction": "human", "controller": "human"}}
	_check(not session.start_network(content.data, 42) and session.rollback == null, "network lobby cannot start without a Lightless player")
	session.roster[1].faction = "lightless"
	_check(not session.start_network(content.data, 42) and session.rollback == null, "network lobby cannot start without a Human player")
	session.close()
	session.start_local(content.data, 42, "human")
	session.networked = true
	session.set_local_control("both")
	_check(session.controls(1) and not session.controls(2) and not session.queue({"kind": "stop", "actors": [5]}, 2), "network ownership cannot use sandbox controls")
	session.close()
	print("ATD_PROTOCOL " + JSON.stringify({"ok": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
