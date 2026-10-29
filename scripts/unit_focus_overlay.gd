extends MeshInstance3D
## Thin relationship lines, updated with render-frame movement.
var segments: Array[Dictionary] = []
var lines := ImmediateMesh.new()

func setup() -> void:
	mesh = lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	material_override = mat

func update_focus(selection: Array, illumination: RefCounted) -> void:
	segments.clear(); lines.clear_surfaces()
	for actor in selection:
		if not is_instance_valid(actor) or not actor is ExpeditionUnit or actor.aboard != null or actor.hp <= 0: continue
		var point := Vector3.INF
		var target: Node3D
		var color := Color(0.48, 0.95, 0.82, 0.65)
		if is_instance_valid(actor.focus_target) and actor.focus_target.hp > 0 and illumination.sample(actor.focus_target.position) > 0.065:
			var radius := 5.5 if actor.kind == "flamer" else 11.0
			if actor.position.distance_to(actor.focus_target.position) < radius:
				target = actor.focus_target; point = target.position; color = Color(1.0, 0.65, 0.4, 0.65)
		if not point.is_finite():
			if actor.order.begins_with("convoy_"):
				target = actor.target if is_instance_valid(actor.target) else null
				point = target.position if target != null else actor.goal
			elif actor.order in ["board", "escort", "to_carrier", "build", "repair", "close_gate", "stock", "deliver", "deposit"] and is_instance_valid(actor.target):
				target = actor.target; point = target.position
			elif actor.order == "harvest": point = actor.harvest_origin
			elif actor.order == "move":
				target = actor.target if is_instance_valid(actor.target) else null
				point = target.position if target != null else actor.goal
				color = Color(0.55, 0.75, 0.95, 0.55)
		if not point.is_finite() or point.distance_to(actor.position) < 0.35: continue
		segments.append({"unit": actor, "target": target, "point": point})
		if segments.size() == 1: lines.surface_begin(Mesh.PRIMITIVE_LINES)
		lines.surface_set_color(color)
		lines.surface_add_vertex(actor.position + Vector3.UP * 0.3)
		lines.surface_add_vertex(point + Vector3.UP * 0.3)
	if not segments.is_empty(): lines.surface_end()
