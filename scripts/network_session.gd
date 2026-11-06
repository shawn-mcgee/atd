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

func _ready() -> void:
	if OS.has_feature("web"):
		bridge = JavaScriptBridge.get_interface("ATDNetwork")
		available = bridge != null

func start(mode: String, code: String = "") -> String:
	if not available: return "Network play requires the browser export"
	role = mode
	terminal = false
	var response = JSON.parse_string(str(bridge.start(mode, code, JSON.stringify(Settings.network))))
	if not response is Dictionary: return "Cannot create room"
	if response.has("error"):
		role = "solo"
		return str(response.error)
	self_id = str(response.self)
	host_id = str(response.host)
	invitation = str(response.invitation)
	return ""

func send(peer: String, packet: Dictionary) -> void:
	if available: bridge.send(peer, JSON.stringify(packet))

func _process(_delta: float) -> void:
	if not available: return
	var events = JSON.parse_string(str(bridge.poll()))
	if events is Array:
		for event in events:
			if event.get("type", "") == "host_lost": terminal = true
			if terminal and event.get("type", "") == "packet": continue
			received.emit(event)

func leave() -> void:
	if available: bridge.leave()
	role = "solo"
	terminal = false

func diagnostics(value: Dictionary) -> void:
	if available: bridge.updateDiagnostics(JSON.stringify(value))
