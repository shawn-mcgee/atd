extends Node2D
## Retained instanced terrain: one draw per texture, GPU light sampling.
const Hex = preload("res://engine/hex_grid.gd")
var game: Node2D
var known: Dictionary = {}
var batches: Dictionary = {}
var revision := -1
var count := -1
var upload_revision := 0
var resources: ResourceLayer
var coverage_viewport: SubViewport
var coverage_batches: Dictionary = {}

class ResourceLayer extends Node2D:
	var world: Node2D
	func _get(property: StringName): return world.get(property) if world != null else null
	func world_to_screen(point: Vector3) -> Vector2: return world.world_to_screen(point)
	func _draw() -> void:
		for patch in world.resource_nodes:
			if world.resource_visible(patch):
				world.sprites.draw_resource(self, patch, Color.WHITE * (0.35 + world.light.sample(patch.position) * 0.65))

class TileBatch extends Node2D:
	var multimesh: MultiMesh
	var texture: Texture2D
	func _draw() -> void:
		if multimesh != null: draw_multimesh(multimesh, texture)

func setup(world: Node2D) -> void:
	game = world; z_index = -3
	resources = ResourceLayer.new(); resources.world = world; resources.z_index = -2; world.add_child(resources)
	coverage_viewport = SubViewport.new()
	coverage_viewport.size = Vector2i(game.darkness.MASK_SIZE, game.darkness.MASK_SIZE)
	coverage_viewport.transparent_bg = true; coverage_viewport.disable_3d = true
	coverage_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(coverage_viewport)
	var coverage_root := Node2D.new(); coverage_viewport.add_child(coverage_root)
	coverage_root.scale = Vector2.ONE * game.darkness.MASK_SIZE / game.darkness.FIELD_SIZE.x
	coverage_root.position = -game.darkness.FIELD_MIN * coverage_root.scale
	var coverage_material := ShaderMaterial.new()
	coverage_material.shader = preload("res://view/shaders/terrain_coverage.gdshader")
	game.darkness.material.set_shader_parameter("terrain_field", coverage_viewport.get_texture())
	game.darkness.material.set_shader_parameter("use_terrain_field", true)
	for key in ["ground_a_fit", "ground_b_fit", "natural_ramp", "cliff_top_fit"]:
		var batch := TileBatch.new()
		if key == "cliff_top_fit": batch.z_index = 2
		var shader_material := ShaderMaterial.new()
		shader_material.shader = preload("res://view/shaders/terrain.gdshader")
		shader_material.set_shader_parameter("cliff", key == "cliff_top_fit")
		shader_material.set_shader_parameter("light_field", game.darkness.mask_viewport.get_texture())
		shader_material.set_shader_parameter("field_min", game.darkness.FIELD_MIN)
		shader_material.set_shader_parameter("field_size", game.darkness.FIELD_SIZE)
		batch.material = shader_material
		batch.texture = game.sprites.regions[key].atlas
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_2D
		batch.multimesh.use_custom_data = true
		batch.multimesh.mesh = tile_mesh(key)
		batches[key] = batch; add_child(batch)
		var coverage := TileBatch.new()
		coverage.multimesh = batch.multimesh; coverage.texture = batch.texture
		coverage.material = coverage_material; coverage_root.add_child(coverage)
		coverage_batches[key] = coverage

func tile_mesh(key: String) -> ArrayMesh:
	var corners := PackedVector2Array()
	if key == "natural_ramp":
		var rect: Rect2 = game.sprites.sprite_rect(key, 1)
		corners = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	else:
		for i in range(6):
			var angle := i * TAU / 6 + PI / 6
			var offset := Vector2(cos(angle), sin(angle)) * 1.001
			if key == "cliff_top_fit": offset.y = offset.y * 1.25 - 0.25
			corners.append(offset)
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner in corners: bounds = bounds.expand(corner)
	var region: AtlasTexture = game.sprites.regions[key]
	var vertices := PackedVector2Array(); var uvs := PackedVector2Array()
	for i in range(1, corners.size() - 1):
		for index in [0, i, i + 1]:
			vertices.append(corners[index])
			uvs.append((region.region.position + (corners[index] - bounds.position) / bounds.size * region.region.size) / region.atlas.get_size())
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func sync() -> void:
	resources.queue_redraw()
	position = game.get_viewport_rect().size * 0.5 - game.focus.rotated(game.camera_angle) * game.zoom
	rotation = game.camera_angle; scale = Vector2.ONE * game.zoom
	if count == game.simulation.explored.size() and revision == game.simulation.navigation.revision: return
	var dirty: bool = count > game.simulation.explored.size()
	if dirty: known.clear()
	for cell in game.simulation.explored:
		var kind: String = game.simulation.explored[cell]
		if known.get(cell, "") != kind: known[cell] = kind; dirty = true
	count = game.simulation.explored.size(); revision = game.simulation.navigation.revision
	if not dirty: return
	upload_revision += 1
	var groups: Dictionary = {}
	for key in batches: groups[key] = []
	for cell in known:
		var kind: String = known[cell]
		var key := "cliff_top_fit" if kind == "cliff" else "natural_ramp" if kind == "ramp" else "ground_b_fit" if posmod(cell.x + cell.y, 7) == 0 else "ground_a_fit"
		groups[key].append(cell)
	for key in batches:
		var batch: TileBatch = batches[key]
		var cells: Array = groups[key]
		# Extrusion is toward world +Z; camera rotation applies to the complete image.
		if key == "cliff_top_fit": cells.sort_custom(func(a, b): return a.y < b.y)
		var buffer := PackedFloat32Array(); buffer.resize(cells.size() * 12)
		for i in range(cells.size()):
			var point := Hex.to_world(cells[i], 1)
			var offset := i * 12
			buffer[offset] = 1; buffer[offset + 3] = point.x
			buffer[offset + 5] = 1; buffer[offset + 7] = point.z
			buffer[offset + 8] = point.x; buffer[offset + 9] = point.z
		batch.multimesh.instance_count = cells.size()
		if not cells.is_empty(): batch.multimesh.buffer = buffer
		batch.queue_redraw(); coverage_batches[key].queue_redraw()
	coverage_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

