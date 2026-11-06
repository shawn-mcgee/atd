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

func _ready() -> void:
	cfg = Settings.data.camera
	fov = float(cfg.verticalFieldOfViewDegrees)
	target_distance = float(cfg.defaultDistanceTiles)
	distance = target_distance
	far = 200
	current = true
	_update_transform()

func ground(screen: Vector2) -> Vector3:
	var hit = Plane(Vector3.UP, 0).intersects_ray(project_ray_origin(screen), project_ray_normal(screen))
	return hit if hit is Vector3 else focus

func _input(event: InputEvent) -> void:
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
		var edge := float(cfg.edgeBandLogicalPixels)
		if pointer_seen and bool(cfg.edgeScrollingEnabled) and not drag and not pointer_captured and Rect2(Vector2.ZERO, size).has_point(pointer):
			if pointer.x < edge: direction.x -= 1
			if pointer.x > size.x - edge: direction.x += 1
			if pointer.y < edge: direction.y -= 1
			if pointer.y > size.y - edge: direction.y += 1
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
