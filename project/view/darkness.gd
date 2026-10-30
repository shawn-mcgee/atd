extends ColorRect
## GPU light stamps + world-anchored wisps. Never writes to the simulation.
const Terrain = preload("res://engine/expedition_terrain.gd")
const FIELD_EXTENT := float(Terrain.MAP_RADIUS) * 2.0
const FIELD_MIN := Vector2(-FIELD_EXTENT, -FIELD_EXTENT)
const FIELD_SIZE := Vector2(FIELD_EXTENT * 2, FIELD_EXTENT * 2)
const MASK_SIZE := 768
var game: Node2D
var mask_viewport: SubViewport
var light_stamps: LightMask
var clock := 0.0
var field_revision := -1

class LightMask extends Node2D:
	var sources: Array = []
	func _init() -> void:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = preload("res://view/shaders/light_mask.gdshader")
		material = shader_material
	func _draw() -> void:
		var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		for source in sources:
			var point := Vector2(source.position.x, source.position.z)
			var center := (point - FIELD_MIN) / FIELD_SIZE * MASK_SIZE
			var radius := float(source.radius) / FIELD_SIZE.x * MASK_SIZE
			var vertices := PackedVector2Array([center + Vector2(-radius, -radius), center + Vector2(radius, -radius), center + Vector2(radius, radius), center + Vector2(-radius, radius)])
			var direction: Vector3 = source.direction
			var parameters := Color(direction.x * 0.5 + 0.5, direction.z * 0.5 + 0.5, float(source.cone) * 0.5 + 0.5, float(source.intensity) * 0.25)
			draw_polygon(vertices, PackedColorArray([parameters]), uvs)

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
	light_stamps = LightMask.new(); mask_viewport.add_child(light_stamps)
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
	var revision := hash(game.simulation.light.sources)
	if revision != field_revision:
		field_revision = revision
		light_stamps.sources = game.simulation.light.sources.duplicate(true)
		light_stamps.queue_redraw()
		mask_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
