extends Node3D
## Visual-only copies; visibility follows the original actor's gameplay visibility.
var entries: Array[Dictionary] = []
var friendly_material: ShaderMaterial
var creature_material: ShaderMaterial
var occluders: Array[Dictionary] = []
var depth_view: SubViewport
var depth_camera: Camera3D
var source_camera: Camera3D
var depth_material: ShaderMaterial

func _init() -> void:
	friendly_material = material(Color(0.35, 1.0, 0.8, 0.75))
	creature_material = material(Color(1.0, 0.42, 0.48, 0.8))

func material(color: Color) -> ShaderMaterial:
	var result := ShaderMaterial.new(); result.shader = load("res://shaders/occluded_unit.gdshader")
	result.set_shader_parameter("highlight_color", color); result.render_priority = 10
	return result

func setup(camera: Camera3D) -> void:
	source_camera = camera
	depth_view = SubViewport.new(); depth_view.world_3d = World3D.new()
	depth_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if DisplayServer.get_name() != "headless" else SubViewport.UPDATE_DISABLED
	depth_view.msaa_3d = Viewport.MSAA_DISABLED; depth_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	depth_view.use_debanding = false; depth_view.gui_disable_input = true
	var environment := Environment.new(); environment.background_mode = Environment.BG_COLOR; environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR; depth_view.world_3d.environment = environment
	add_child(depth_view)
	depth_camera = Camera3D.new(); depth_view.add_child(depth_camera); depth_camera.current = true
	depth_material = ShaderMaterial.new(); depth_material.shader = load("res://shaders/occluder_depth.gdshader")
	for mat in [friendly_material, creature_material]: mat.set_shader_parameter("occluder_depth", depth_view.get_texture())

func register_occluder(owner: Node3D) -> void:
	remove_occluder(owner)
	register_occluder_meshes(owner.model if owner is ExpeditionStructure else owner, owner)

func register_occluder_meshes(node: Node, owner: Node3D) -> void:
	if node is Label3D or node is SubViewport: return
	if node is MeshInstance3D and node.mesh != null and not node.mesh is ImmediateMesh:
		var proxy := MeshInstance3D.new(); proxy.mesh = node.mesh; proxy.material_override = depth_material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; depth_view.add_child(proxy)
		occluders.append({"owner": owner, "source": node, "proxy": proxy})
	for child in node.get_children(): register_occluder_meshes(child, owner)

func remove_occluder(owner: Node3D) -> void:
	for i in range(occluders.size() - 1, -1, -1):
		if occluders[i].owner == owner: occluders[i].proxy.queue_free(); occluders.remove_at(i)

func register_actor(actor: Node3D) -> void:
	register_meshes(actor.visual, actor)

func register_meshes(node: Node, actor: Node3D) -> void:
	if node is MeshInstance3D and node.mesh != null and not node.mesh is ImmediateMesh:
		var proxy := MeshInstance3D.new(); proxy.mesh = node.mesh
		proxy.material_override = creature_material if actor is ExpeditionPredator else friendly_material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.ignore_occlusion_culling = true
		add_child(proxy); entries.append({"actor": actor, "source": node, "proxy": proxy})
	for child in node.get_children(): register_meshes(child, actor)

func sync(illumination) -> void:
	depth_view.size = Vector2i(source_camera.get_viewport().get_visible_rect().size)
	depth_camera.projection = source_camera.projection; depth_camera.keep_aspect = source_camera.keep_aspect
	depth_camera.size = source_camera.size; depth_camera.fov = source_camera.fov
	depth_camera.near = source_camera.near; depth_camera.far = source_camera.far
	depth_camera.global_transform = source_camera.global_transform
	depth_material.set_shader_parameter("camera_far", source_camera.far)
	for mat in [friendly_material, creature_material]: mat.set_shader_parameter("camera_far", source_camera.far)
	for i in range(occluders.size() - 1, -1, -1):
		var entry: Dictionary = occluders[i]
		if not is_instance_valid(entry.source) or not is_instance_valid(entry.owner):
			entry.proxy.queue_free(); occluders.remove_at(i); continue
		entry.proxy.visible = entry.source.is_visible_in_tree() and (not entry.owner is ExpeditionStructure or entry.owner.hp > 0)
		entry.proxy.global_transform = entry.source.global_transform
	for i in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[i]
		if not is_instance_valid(entry.actor) or not is_instance_valid(entry.source):
			entry.proxy.queue_free(); entries.remove_at(i); continue
		var visible: bool = entry.actor.hp > 0 and entry.source.is_visible_in_tree()
		if entry.actor is ExpeditionUnit: visible = visible and entry.actor.aboard == null
		else: visible = visible and illumination.sample(entry.actor.position) > 0.065
		entry.proxy.visible = visible
		if visible: entry.proxy.global_transform = entry.source.global_transform
