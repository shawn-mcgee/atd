extends SceneTree
## Companion process for test-rewrite-browser.cjs --godot.
const Session = preload("res://net/match_session.gd")
const Content = preload("res://core/content.gd")
const Transport = preload("res://net/coordinator_transport.gd")
var session = Session.new()
var started_at := 0
var accumulator := 0.0
var prepared := false
var finished := false

func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	session.transport.identity_ready.connect(func(_id, code): print("ATD_ROOM " + code))
	session.transport.message_received.connect(_received)
	session.match_started.connect(_started)
	session.connect_room(Transport.DEFAULT_URL, true, "", "human", [])

func _process(dt: float) -> bool:
	if finished: return false
	session.poll()
	if not session.error.is_empty(): _finish(false, session.error); return false
	if session.roster.size() == 2 and not prepared:
		var content = Content.new()
		content.load_file("res://content/default.json")
		prepared = session.start_network(content.data, 42)
	if session.running:
		accumulator = minf(accumulator + dt, 0.2)
		while accumulator >= 0.05:
			if not session.advance(): break
			accumulator -= 0.05
	if Time.get_ticks_msec() - started_at > 45000: _finish(false, "Browser did not complete the match check")
	return false

func _started() -> void:
	session.rollback.confirmed.connect(func(tick, hash_value):
		if tick % 20 == 0: print("ATD_CROSS_HASH " + JSON.stringify({"tick": tick, "hash": hash_value})))

func _received(_sender: int, message: Dictionary) -> void:
	if message.get("type") == "test_done": _finish(true, "Native/browser peer completed")

func _finish(ok: bool, message: String) -> void:
	finished = true
	session.close()
	print("ATD_CROSS_DONE " + JSON.stringify({"ok": ok, "message": message}))
	quit(0 if ok else 1)
