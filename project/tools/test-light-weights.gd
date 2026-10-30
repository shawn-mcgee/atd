extends SceneTree
const Navigation = preload("res://engine/expedition_navigation.gd")
const Illumination = preload("res://engine/illumination.gd")
var failures := 0
func check(ok: bool, text: String) -> void:
	if ok: print("PASS: ", text)
	else: failures += 1; push_error(text)
func _initialize() -> void: call_deferred("run")
func verify(nav, light) -> bool:
	nav.cache_light_weights(light)
	var weights: Dictionary = {}
	for i in range(nav.light_weight_ids.size()): weights[nav.light_weight_ids[i]] = nav.light_weight_values[i]
	for id in nav.graph.get_point_ids():
		if not is_equal_approx(float(weights.get(id, 1.0)), 1.0 + light.deterrence(nav.graph.get_point_position(id)) * 18.0): return false
	return true
func run() -> void:
	var nav := Navigation.new(); nav.rebuild([])
	var light := Illumination.new()
	light.add_source(Vector3.ZERO, 8)
	light.add_source(Vector3(4, 0, 3), 11, Vector3.RIGHT, 0.4, 0.7)
	light.add_source(Vector3(-40, 0, 0), 20, Vector3.ZERO, -1, 1, false)
	check(verify(nav, light), "sparse route costs match full-map lighting, overlapping cones and emergency lamps")
	check(nav.light_weight_ids.size() < nav.cells.size() / 10, "local lighting touches a small fraction of the expanded map")
	light.sources[0].position = Vector3(90, 0, -70)
	check(verify(nav, light), "moving light invalidates weights including distant cells")
	light.sources.clear()
	check(verify(nav, light) and nav.light_weight_ids.is_empty(), "removed lights leave no stale weighted cells")
	light.add_source(Vector3(8, 0, 0), 10)
	nav.path(Vector3(-12, 0, 0), Vector3(12, 0, 0), light, false)
	var reset := true
	for id in nav.graph.get_point_ids():
		if nav.graph.get_point_weight_scale(id) != 1.0: reset = false
	check(reset, "illuminated routes restore weights for subsequent ordinary paths")
	print("LIGHT_WEIGHT_TEST_RESULT: ", failures, " failures"); quit(1 if failures else 0)
