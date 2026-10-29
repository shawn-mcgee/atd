extends SceneTree
## Run with --script and three user arguments: model resource, wrapper resource, report path.

func _initialize() -> void:
	call_deferred("_verify")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		_fail("Expected model resource, wrapper scene resource, and report path.")
		return
	var resources: Array[Dictionary] = []
	for resource_path in [args[0], args[1]]:
		var packed := load(resource_path) as PackedScene
		if packed == null:
			_fail("Cannot load PackedScene: " + resource_path)
			return
		var instance := packed.instantiate()
		root.add_child(instance)
		var pending: Array[Node] = [instance]
		var mesh_count := 0
		var surface_count := 0
		var vertex_count := 0
		var bounds := AABB()
		var have_bounds := false
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			for child in node.get_children():
				pending.append(child)
			if node is MeshInstance3D and node.mesh != null:
				mesh_count += 1
				for surface in range(node.mesh.get_surface_count()):
					surface_count += 1
					vertex_count += node.mesh.surface_get_array_len(surface)
				var transformed: AABB = node.global_transform * node.get_aabb()
				bounds = bounds.merge(transformed) if have_bounds else transformed
				have_bounds = true
		if mesh_count == 0 or vertex_count == 0 or bounds.size.length_squared() <= 0:
			instance.free()
			_fail("Scene contains no usable 3D mesh geometry: " + resource_path)
			return
		resources.append({
			"resource": resource_path,
			"meshes": mesh_count,
			"surfaces": surface_count,
			"vertices": vertex_count,
			"bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z],
			"bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]
		})
		instance.free()
	var report := FileAccess.open(args[2], FileAccess.WRITE)
	if report == null:
		_fail("Cannot write verification report: " + args[2])
		return
	report.store_string(JSON.stringify({"success": true, "resources": resources}, "\t"))
	report.close()
	quit(0)
