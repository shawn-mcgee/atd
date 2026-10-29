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
var actor_groups: Dictionary = {}
var occluder_groups: Dictionary = {}
var depth_dirty := true
var camera_state := 0

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
	depth_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
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
	occluder_groups[owner.get_instance_id()] = {"owner": owner, "entries": [], "state": 0}
	register_occluder_meshes(owner.model if owner is ExpeditionStructure else owner, owner)
	depth_dirty = true

func register_occluder_meshes(node: Node, owner: Node3D) -> void:
	if node is Label3D or node is SubViewport: return
	if node is MeshInstance3D and node.mesh != null and not node.mesh is ImmediateMesh:
		var proxy := MeshInstance3D.new(); proxy.mesh = node.mesh; proxy.material_override = depth_material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; depth_view.add_child(proxy)
		var entry := {"owner": owner, "source": node, "proxy": proxy}
		occluders.append(entry); occluder_groups[owner.get_instance_id()].entries.append(entry)
	for child in node.get_children(): register_occluder_meshes(child, owner)

func remove_occluder(owner: Node3D) -> void:
	remove_occluder_id(owner.get_instance_id())

func remove_occluder_id(id: int) -> void:
	if not occluder_groups.has(id): return
	for entry in occluder_groups[id].entries:
		entry.proxy.queue_free(); occluders.erase(entry)
	occluder_groups.erase(id); depth_dirty = true

func register_actor(actor: Node3D) -> void:
	actor_groups[actor.get_instance_id()] = {"actor": actor, "entries": [], "visible": null, "transform": Transform3D()}
	register_meshes(actor.visual, actor)

func register_meshes(node: Node, actor: Node3D) -> void:
	if node is MeshInstance3D and node.mesh != null and not node.mesh is ImmediateMesh:
		var proxy := MeshInstance3D.new(); proxy.mesh = node.mesh
		proxy.material_override = creature_material if actor is ExpeditionPredator else friendly_material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.ignore_occlusion_culling = true
		var entry := {"actor": actor, "source": node, "proxy": proxy}
		add_child(proxy); entries.append(entry); actor_groups[actor.get_instance_id()].entries.append(entry)
	for child in node.get_children(): register_meshes(child, actor)

func sync(illumination) -> void:
	var viewport_size := Vector2i(source_camera.get_viewport().get_visible_rect().size)
	var next_camera := hash([viewport_size, source_camera.global_transform, source_camera.projection, source_camera.keep_aspect, source_camera.size, source_camera.fov, source_camera.near, source_camera.far])
	if next_camera != camera_state:
		camera_state = next_camera; depth_dirty = true
		depth_view.size = viewport_size
		depth_camera.projection = source_camera.projection; depth_camera.keep_aspect = source_camera.keep_aspect
		depth_camera.size = source_camera.size; depth_camera.fov = source_camera.fov
		depth_camera.near = source_camera.near; depth_camera.far = source_camera.far
		depth_camera.global_transform = source_camera.global_transform
		depth_material.set_shader_parameter("camera_far", source_camera.far)
		for mat in [friendly_material, creature_material]: mat.set_shader_parameter("camera_far", source_camera.far)
	# Terrain depth does not depend on actor movement. Static owners need neither
	# per-mesh transform uploads nor another full viewport render every frame.
	for id in occluder_groups.keys():
		var group: Dictionary = occluder_groups[id]
		var owner = group.owner
		if not is_instance_valid(owner): remove_occluder_id(id); continue
		var state := hash([owner.global_transform, owner.is_visible_in_tree(), owner.model.transform, owner.gate_open, owner.hp > 0]) if owner is ExpeditionStructure else hash([owner.global_transform, owner.is_visible_in_tree()])
		if state == group.state: continue
		group.state = state; depth_dirty = true
		for entry in group.entries.duplicate():
			if not is_instance_valid(entry.source):
				entry.proxy.queue_free(); occluders.erase(entry); group.entries.erase(entry); continue
			entry.proxy.visible = entry.source.is_visible_in_tree() and (not owner is ExpeditionStructure or owner.hp > 0)
			entry.proxy.global_transform = entry.source.global_transform
	if depth_dirty:
		if DisplayServer.get_name() != "headless": depth_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		depth_dirty = false
	for id in actor_groups.keys():
		var group: Dictionary = actor_groups[id]
		var actor = group.actor
		if not is_instance_valid(actor):
			for entry in group.entries: entry.proxy.queue_free(); entries.erase(entry)
			actor_groups.erase(id); continue
		var visible: bool = actor.hp > 0 and actor.is_visible_in_tree()
		if actor is ExpeditionUnit: visible = visible and actor.aboard == null
		else: visible = visible and illumination.sample(actor.position) > 0.065
		var transform: Transform3D = actor.visual.global_transform
		if group.visible == visible and (not visible or (group.transform == transform and actor is ExpeditionUnit)): continue
		group.visible = visible; group.transform = transform
		for entry in group.entries:
			entry.proxy.visible = visible and entry.source.is_visible_in_tree()
			if visible: entry.proxy.global_transform = entry.source.global_transform
