extends ColorRect
## Screen-space silhouette union: sprites, turret layers, wall arms and gate panels.
var game: Node2D
var mask_viewport: SubViewport
var mask_draw: SelectionMask

class SelectionMask extends Node2D:
	const Primitives = preload("res://view/primitives.gd")
	var world: Node2D
	func _get(property: StringName):
		return world.get(property) if world != null else null
	func world_to_screen(point: Vector3) -> Vector2:
		return world.world_to_screen(point)
	func actor_position(actor: SimEntity) -> Vector3:
		return world.actor_position(actor)
	func _draw() -> void:
		if world == null: return
		if not world.selected_resource.is_empty(): world.sprites.draw_resource(self, world.selected_resource)
		for actor in world.selected:
			if not SimEntity.valid(actor) or not actor.visible or actor.hp <= 0: continue
			if actor is SimStructure:
				for offset in actor.connections:
					world.sprites.draw(self, "wall_arm", actor.position + offset * 0.3, atan2(offset.z, offset.x))
				if actor.kind == "gate": world.sprites.draw_gate(self, actor)
				else: world.sprites.draw_building(self, actor, Primitives.structure_polygon(world, actor), Color.WHITE)
				if world.Rules.TURRETS.has(actor.kind):
					world.sprites.draw(self, actor.kind + "_head", actor.position, float(world.sprites.headings.get(actor.simulation_id, 0.0)))
			elif not actor is SimUnit or actor.aboard == null:
				world.sprites.draw(self, actor.kind, world.actor_position(actor), world.sprites.actor_angle(actor))

func setup(world: Node2D) -> void:
	game = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50 # Above world sprites, below darkness and the HUD.
	mask_viewport = SubViewport.new()
	mask_viewport.transparent_bg = true; mask_viewport.disable_3d = true
	add_child(mask_viewport)
	mask_draw = SelectionMask.new(); mask_draw.world = world
	var mask_material := ShaderMaterial.new()
	mask_material.shader = preload("res://view/shaders/selection_mask.gdshader")
	mask_draw.material = mask_material
	mask_viewport.add_child(mask_draw)
	var outline_material := ShaderMaterial.new()
	outline_material.shader = preload("res://view/shaders/selection_outline.gdshader")
	outline_material.set_shader_parameter("silhouette", mask_viewport.get_texture())
	material = outline_material
	sync()

func _process(_dt: float) -> void:
	if game != null: sync()

func sync() -> void:
	size = game.get_viewport_rect().size
	var dimensions := Vector2i(size)
	if mask_viewport.size != dimensions: mask_viewport.size = dimensions
	material.set_shader_parameter("pixel_size", Vector2.ONE / size)
	visible = not game.selected.is_empty() or not game.selected_resource.is_empty()
	mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	if visible: mask_draw.queue_redraw()
