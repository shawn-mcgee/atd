extends Node
## On-demand, depth-tested ID render of real actor meshes. No per-frame readback.
class PickRequest:
	extends RefCounted
	signal completed
	var screen := Vector2.ZERO
	var actor: Node3D
	var finished := false

var source_camera: Camera3D
var view: SubViewport
var pick_camera: Camera3D
var entries: Array[Dictionary] = []
var actor_codes: Dictionary = {}
var code_actors: Dictionary = {}
var next_id := 1
var free_ids: Array[int] = []
var pending: Array[PickRequest] = []
var rendering := false
var gpu_enabled := false
var gpu_reads := 0
var cpu_queries := 0
var faces_cache: Dictionary = {}
var last_image: Image
var black_material: ShaderMaterial

func setup(camera: Camera3D) -> void:
	source_camera = camera
	gpu_enabled = DisplayServer.get_name() != "headless"
	view = SubViewport.new()
	view.name = "SelectionIDBuffer"
	view.world_3d = World3D.new()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	view.msaa_3d = Viewport.MSAA_DISABLED
	view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	view.use_taa = false
	view.use_debanding = false
	view.gui_disable_input = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	view.world_3d.environment = environment
	add_child(view)
	pick_camera = Camera3D.new(); view.add_child(pick_camera); pick_camera.current = true
	black_material = id_material(0)
	_sync_camera()

func register_actor(actor: Node3D) -> void:
	if actor_codes.has(actor.get_instance_id()): return
	var code := 0
	if not rendering and not free_ids.is_empty(): code = free_ids.pop_back()
	else:
		if next_id >= 4096: push_error("Selection ID buffer exceeded 4095 simultaneous actor IDs"); return
		code = next_id; next_id += 1
	actor_codes[actor.get_instance_id()] = code
	code_actors[code] = weakref(actor)
	_register_tree(actor, actor, id_material(code))

func register_occluder(node: Node3D) -> void:
	_register_tree(node, node, black_material)

func remove_owner(owner: Node3D) -> void:
	var id := owner.get_instance_id()
	if actor_codes.has(id):
		free_ids.append(actor_codes[id]); code_actors.erase(actor_codes[id]); actor_codes.erase(id)
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].owner == owner:
			entries[i].proxy.queue_free(); entries.remove_at(i)

func _register_tree(node: Node, owner: Node3D, material: Material) -> void:
	if node is Label3D: return
	if node is MeshInstance3D and node.mesh != null and not node.mesh is ImmediateMesh:
		var proxy := MeshInstance3D.new()
		proxy.mesh = node.mesh; proxy.material_override = material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.add_child(proxy)
		entries.append({"source": node, "owner": owner, "proxy": proxy})
	# Labels and other UI helpers are deliberately absent from the ID pass.
	for child in node.get_children(): _register_tree(child, owner, material)

func id_material(code: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new(); mat.shader = load("res://shaders/selection_id.gdshader")
	# Spaced channel values tolerate the Compatibility renderer's approximate
	# color conversion without confusing ID pixels with black/background.
	var rgb := Vector3.ZERO if code == 0 else Vector3(32 + ((code >> 8) & 15) * 14, 32 + ((code >> 4) & 15) * 14, 32 + (code & 15) * 14) / 255.0
	mat.set_shader_parameter("pick_rgb", rgb)
	return mat

func warm_up() -> void:
	if not gpu_enabled: return
	_sync_scene(); view.render_target_update_mode = SubViewport.UPDATE_ONCE

func _sync_camera() -> void:
	view.size = Vector2i(source_camera.get_viewport().get_visible_rect().size)
	pick_camera.projection = source_camera.projection
	pick_camera.keep_aspect = source_camera.keep_aspect
	pick_camera.size = source_camera.size
	pick_camera.fov = source_camera.fov
	pick_camera.near = source_camera.near; pick_camera.far = source_camera.far
	pick_camera.h_offset = source_camera.h_offset; pick_camera.v_offset = source_camera.v_offset
	pick_camera.frustum_offset = source_camera.frustum_offset
	pick_camera.global_transform = source_camera.global_transform

func _sync_scene() -> void:
	_sync_camera()
	for i in range(entries.size() - 1, -1, -1):
		var entry := entries[i]
		if not is_instance_valid(entry.source) or not is_instance_valid(entry.owner):
			entry.proxy.queue_free(); entries.remove_at(i); continue
		entry.proxy.visible = entry.source.is_visible_in_tree()
		if not entry.proxy.visible: continue
		entry.proxy.mesh = entry.source.mesh
		entry.proxy.global_transform = entry.source.global_transform

func request_pick(screen: Vector2) -> PickRequest:
	var request := PickRequest.new(); request.screen = screen
	if not Rect2(Vector2.ZERO, source_camera.get_viewport().get_visible_rect().size).has_point(screen): request.finished = true; return request
	if not gpu_enabled: request.actor = _cpu_pick(screen); request.finished = true; return request
	pending.append(request)
	if not rendering:
		rendering = true; call_deferred("_render_pending")
	return request

func resolve_pick(request: PickRequest) -> Node3D:
	if not request.finished: await request.completed
	return request.actor if _live_actor(request.actor) else null

func pick_actor(screen: Vector2) -> Node3D:
	return await resolve_pick(request_pick(screen))

func _render_pending() -> void:
	while not pending.is_empty():
		var batch: Array[PickRequest] = pending.duplicate(); pending.clear()
		_sync_scene(); view.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		last_image = view.get_texture().get_image()
		gpu_reads += 1
		for request in batch:
			request.actor = actor_at_pixel(last_image, request.screen)
			request.finished = true
			request.completed.emit()
	rendering = false

func actor_at_pixel(buffer: Image, screen: Vector2) -> Node3D:
	if buffer == null or buffer.is_empty(): return null
	var point := Vector2i(floori(screen.x), floori(screen.y))
	var actor := _actor_at(buffer, point)
	if actor != null: return actor
	# A small rendered-edge allowance helps thin limbs without giant hit boxes.
	for radius in [1, 2, 3]:
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if absi(x) != radius and absi(y) != radius: continue
				actor = _actor_at(buffer, point + Vector2i(x, y))
				if actor != null: return actor
	return null

func _actor_at(buffer: Image, point: Vector2i) -> Node3D:
	if point.x < 0 or point.y < 0 or point.x >= buffer.get_width() or point.y >= buffer.get_height(): return null
	var color := buffer.get_pixelv(point)
	var channels := Vector3(color.r, color.g, color.b) * 255.0
	var r := roundi((channels.x - 32) / 14)
	var g := roundi((channels.y - 32) / 14)
	var b := roundi((channels.z - 32) / 14)
	if r < 0 or r > 15 or g < 0 or g > 15 or b < 0 or b > 15: return null
	if absf(channels.x - (32 + r * 14)) > 5 or absf(channels.y - (32 + g * 14)) > 5 or absf(channels.z - (32 + b * 14)) > 5: return null
	var code := (r << 8) | (g << 4) | b
	if not code_actors.has(code): return null
	var actor = code_actors[code].get_ref()
	return actor if _live_actor(actor) else null

func _live_actor(actor) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not actor.visible or actor.hp <= 0: return false
	return not actor is ExpeditionUnit or actor.aboard == null

func _cpu_pick(screen: Vector2) -> Node3D:
	# Graphics-free tests use the same mesh triangles, including depth occluders.
	# GPU misses never fall back to this path in normal play.
	cpu_queries += 1; _sync_scene()
	var start := source_camera.project_ray_origin(screen)
	var finish := start + source_camera.project_ray_normal(screen) * source_camera.far
	var nearest := INF
	var result: Node3D
	for entry in entries:
		if not entry.proxy.visible: continue
		var proxy: MeshInstance3D = entry.proxy
		var mesh_id := proxy.mesh.get_instance_id()
		if not faces_cache.has(mesh_id): faces_cache[mesh_id] = proxy.mesh.get_faces()
		var faces: PackedVector3Array = faces_cache[mesh_id]
		var inverse := proxy.global_transform.affine_inverse()
		var a := inverse * start; var b := inverse * finish
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i + 1], faces[i + 2])
			if hit == null: continue
			var distance := start.distance_squared_to(proxy.global_transform * hit)
			if distance < nearest:
				nearest = distance
				result = entry.owner if actor_codes.has(entry.owner.get_instance_id()) and _live_actor(entry.owner) else null
	return result
