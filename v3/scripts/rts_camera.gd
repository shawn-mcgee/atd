class_name RTSCamera
extends Camera3D

var focus := Vector3.ZERO
var bounds := 36
var target_distance := 24.0
var distance := 24.0
var yaw := 0.0
var drag := false
var previous_ground := Vector3.ZERO
var enabled := true
var pointer_captured := false
var pointer_seen := false
var letter_pan_blocked := false
var keyboard_pan_blocked := false
var suppressed_pan_keys: Dictionary = {}
var cfg: Dictionary
var edge_pan := Vector2.ZERO
var edge_indicator: EdgeIndicator

func _ready() -> void:
	cfg = Settings.data.camera
	fov = float(cfg.verticalFieldOfViewDegrees)
	target_distance = float(cfg.defaultDistanceTiles)
	distance = target_distance
	far = 200
	current = true
	var overlay := CanvasLayer.new(); overlay.layer = 2; add_child(overlay)
	edge_indicator = EdgeIndicator.new(); edge_indicator.camera = self; overlay.add_child(edge_indicator)
	edge_indicator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_transform()

func ground(screen: Vector2) -> Vector3:
	var hit = Plane(Vector3.UP, 0).intersects_ray(project_ray_origin(screen), project_ray_normal(screen))
	return hit if hit is Vector3 else focus

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: pointer_seen = true
	if event is InputEventKey and not event.pressed:
		var code: int = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		suppressed_pan_keys.erase(code)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or keyboard_pan_blocked:
		return
	if event is InputEventMouseMotion: pointer_seen = true
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE and bool(cfg.mouseDraggingEnabled):
			drag = event.pressed
			previous_ground = ground(event.position)
			get_viewport().set_input_as_handled()
		if event.pressed and bool(cfg.wheelZoomEnabled):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				target_distance -= float(cfg.wheelStepTiles)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				target_distance += float(cfg.wheelStepTiles)
			target_distance = clampf(target_distance, float(cfg.minimumDistanceTiles), float(cfg.maximumDistanceTiles))
	if event is InputEventMouseMotion and drag:
		var here := ground(event.position)
		focus += previous_ground - here
		_update_transform()
		previous_ground = ground(event.position)

func _process(delta: float) -> void:
	edge_pan = Vector2.ZERO
	edge_indicator.phase += delta
	edge_indicator.queue_redraw()
	if not enabled:
		return
	var presentation_delta := delta
	# Do not turn shader-compilation or a background-tab stall into a large pan jump.
	delta = minf(delta, float(cfg.get("maxFrameDeltaSeconds", 0.1)))
	var active := get_window().has_focus()
	if not active:
		drag = false
	var direction := Vector2.ZERO
	if active and not keyboard_pan_blocked and not (get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit):
		if bool(cfg.keyboardPanningEnabled):
			direction = Vector2(float(_pressed(cfg.panBindings.right)) - float(_pressed(cfg.panBindings.left)), float(_pressed(cfg.panBindings.down)) - float(_pressed(cfg.panBindings.up)))
		var pointer := get_viewport().get_mouse_position()
		var size := get_viewport().get_visible_rect().size
		if pointer_seen and bool(cfg.edgeScrollingEnabled) and not drag and not pointer_captured and Rect2(Vector2.ZERO, size).has_point(pointer):
			edge_pan = edge_direction(pointer, size)
			direction += edge_pan
		var target_yaw := 0.0
		if _pressed(cfg.rotateLeftBinding): target_yaw = deg_to_rad(float(cfg.rotationHoldDegrees))
		if _pressed(cfg.rotateRightBinding): target_yaw -= deg_to_rad(float(cfg.rotationHoldDegrees))
		yaw = lerp_angle(yaw, target_yaw, 1.0 - exp(-presentation_delta / float(cfg.rotationResponseSeconds)))
	if not drag:
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		var forward := Vector3(sin(yaw), 0, cos(yaw))
		var speed := float(cfg.panTilesPerRealSecondAtDefaultZoom) * (distance / float(cfg.defaultDistanceTiles) if cfg.scalePanWithZoom else 1.0)
		focus += (right * direction.normalized().x + forward * direction.normalized().y) * speed * delta
	var axial := HexGrid.cell(Vector2(focus.x, focus.z))
	if HexGrid.distance(axial) > bounds:
		var scale_by := float(bounds) / HexGrid.distance(axial)
		focus.x *= scale_by
		focus.z *= scale_by
	distance = lerpf(distance, target_distance, 1.0 - exp(-presentation_delta / float(cfg.zoomResponseSeconds)))
	_update_transform()

func edge_direction(pointer: Vector2, size: Vector2) -> Vector2:
	if not Rect2(Vector2.ZERO, size).has_point(pointer): return Vector2.ZERO
	var band := float(cfg.edgeBandLogicalPixels)
	return Vector2(float(pointer.x > size.x - band) - float(pointer.x < band), float(pointer.y > size.y - band) - float(pointer.y < band))

class EdgeIndicator:
	extends Control
	var camera: RTSCamera
	var phase := 0.0

	func _draw() -> void:
		if camera.edge_pan == Vector2.ZERO: return
		var pointer := get_viewport().get_mouse_position()
		var inset := float(camera.cfg.edgeBandLogicalPixels) * 0.5
		var color := Color("a9e8dc")
		color.a = 0.45 + 0.55 * (sin(phase * TAU / float(camera.cfg.edgeIndicatorPulseSeconds)) * 0.5 + 0.5)
		if camera.edge_pan.x != 0:
			_arrow(Vector2(inset if camera.edge_pan.x < 0 else size.x - inset, clampf(pointer.y, inset * 2, size.y - inset * 2)), Vector2(camera.edge_pan.x, 0), color)
		if camera.edge_pan.y != 0:
			_arrow(Vector2(clampf(pointer.x, inset * 2, size.x - inset * 2), inset if camera.edge_pan.y < 0 else size.y - inset), Vector2(0, camera.edge_pan.y), color)

	func _arrow(center: Vector2, direction: Vector2, color: Color) -> void:
		var length := float(camera.cfg.edgeIndicatorSizeLogicalPixels)
		var side := direction.orthogonal() * length * 0.6
		for offset in [-0.55, 0.55]:
			var point: Vector2 = center + direction * length * offset
			draw_polyline(PackedVector2Array([point - direction * length * 0.5 + side, point + direction * length * 0.5, point - direction * length * 0.5 - side]), Color(0, 0, 0, color.a), 5, true)
			draw_polyline(PackedVector2Array([point - direction * length * 0.5 + side, point + direction * length * 0.5, point - direction * length * 0.5 - side]), color, 2, true)

func _update_transform() -> void:
	var pitch := deg_to_rad(float(cfg.get("pitchBelowHorizontalDegrees", 55)))
	position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	look_at(focus, Vector3.UP)

func _pressed(binding: String) -> bool:
	for key in binding.split("|"):
		if letter_pan_blocked and key.length() == 1: continue
		var code := OS.find_keycode_from_string(key)
		if suppressed_pan_keys.has(code):
			if not Input.is_physical_key_pressed(code): suppressed_pan_keys.erase(code)
			else: continue
		if Input.is_physical_key_pressed(code): return true
	return false
