extends ColorRect
## GPU light stamps + world-anchored wisps. Never writes to the simulation.
const Terrain = preload("res://engine/expedition_terrain.gd")
static var FIELD_EXTENT: float = float(Terrain.MAP_RADIUS) * 2.0
static var FIELD_MIN: Vector2 = Vector2(-FIELD_EXTENT, -FIELD_EXTENT)
static var FIELD_SIZE: Vector2 = Vector2(FIELD_EXTENT * 2, FIELD_EXTENT * 2)
const MASK_SIZE := 768
var game: Node2D
var mask_viewport: SubViewport
var light_stamps: LightMask
var clock := 0.0
var field_revision := -1

class LightMask extends Node2D:
	var field_min := Vector2.ZERO
	var field_size := Vector2.ONE
	var sources: Array = []
	var field: Dictionary = {}
	var multimesh: MultiMesh
	func _init() -> void:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = preload("res://view/shaders/light_mask.gdshader")
		material = shader_material
		var corners := PackedVector2Array()
		for i in range(6): corners.append(Vector2(cos(i * TAU / 6 + PI / 6), sin(i * TAU / 6 + PI / 6)) * 1.001)
		var vertices := PackedVector2Array()
		for i in range(1, 5):
			for index in [0, i, i + 1]: vertices.append(corners[index])
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
		var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		multimesh = MultiMesh.new(); multimesh.transform_format = MultiMesh.TRANSFORM_2D
		multimesh.use_colors = true; multimesh.mesh = mesh
	func set_field(values: Dictionary) -> void:
		field = values.duplicate()
		var buffer := PackedFloat32Array(); buffer.resize(field.size() * 12)
		var index := 0; var scale_value := MASK_SIZE / field_size.x
		for cell in field:
			var point: Vector3 = preload("res://engine/hex_grid.gd").to_world(cell, Terrain.CELL)
			var center := (Vector2(point.x, point.z) - field_min) / field_size * MASK_SIZE
			var offset := index * 12
			buffer[offset] = scale_value; buffer[offset + 3] = center.x
			buffer[offset + 5] = scale_value; buffer[offset + 7] = center.y
			for color_index in range(3): buffer[offset + 8 + color_index] = float(field[cell])
			buffer[offset + 11] = 1; index += 1
		multimesh.instance_count = field.size()
		if not field.is_empty(): multimesh.buffer = buffer
		queue_redraw()
	func _draw() -> void:
		if multimesh != null: draw_multimesh(multimesh, null)

func setup(world: Node2D) -> void:
	game = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100 # World overlay; the HUD's separate CanvasLayer stays above it.
	mask_viewport = SubViewport.new()
	mask_viewport.size = Vector2i(MASK_SIZE, MASK_SIZE)
	mask_viewport.transparent_bg = true
	mask_viewport.disable_3d = true
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(mask_viewport)
	light_stamps = LightMask.new(); light_stamps.field_min = FIELD_MIN; light_stamps.field_size = FIELD_SIZE; mask_viewport.add_child(light_stamps)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://view/shaders/darkness.gdshader")
	shader_material.set_shader_parameter("light_field", mask_viewport.get_texture())
	shader_material.set_shader_parameter("field_min", FIELD_MIN)
	shader_material.set_shader_parameter("field_size", FIELD_SIZE)
	material = shader_material
	sync()

func _process(dt: float) -> void:
	if game == null: return
	if game.started and not game.simulation.paused and not game.simulation.ended: clock += dt
	sync()

func sync() -> void:
	if game == null: return
	size = game.get_viewport_rect().size
	material.set_shader_parameter("viewport_size", size)
	material.set_shader_parameter("camera_focus", game.focus)
	material.set_shader_parameter("camera_angle", game.camera_angle)
	material.set_shader_parameter("camera_zoom", game.zoom)
	material.set_shader_parameter("visual_time", clock)
	game.simulation.light.ensure_field()
	var revision := hash([game.simulation.light.sources, game.simulation.navigation.revision])
	if revision != field_revision:
		field_revision = revision
		light_stamps.sources = game.simulation.light.sources.duplicate(true)
		light_stamps.set_field(game.simulation.light.field)
		mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
