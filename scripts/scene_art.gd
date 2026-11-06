class_name SceneArt
extends RefCounted

const STEEL := Color("35424a")
const DARK := Color("19242b")
const EDGE := Color("64747a")
const IVORY := Color("c3c5af")
const AMBER := Color("e5ad60")
const BONE := Color("a69c8c")
var materials: Dictionary = {}
var box: Mesh
var cylinder := CylinderMesh.new()
var sphere := SphereMesh.new()
var wedge := PrismMesh.new()

func _init() -> void:
	box = _beveled_box()
	cylinder.top_radius = 0.5; cylinder.bottom_radius = 0.5; cylinder.height = 1; cylinder.radial_segments = 8
	sphere.radial_segments = 12; sphere.rings = 6

func mat(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var key := str(color) + str(emissive)
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color; m.roughness = 0.68; m.metallic = 0.18
	if emissive: m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = m
	return m

func _beveled_box() -> ArrayMesh:
	var triangles: Array = []
	var h := 0.42
	for axis in range(3):
		for sign_value in [-1, 1]:
			var center := Vector3.ZERO; center[axis] = sign_value * 0.5
			var u := Vector3.ZERO; u[(axis + 1) % 3] = h
			var v := Vector3.ZERO; v[(axis + 2) % 3] = h
			var n := Vector3.ZERO; n[axis] = sign_value
			var points := [center - u - v, center + u - v, center + u + v, center - u + v]
			triangles.append([points[0], points[1], points[2], n]); triangles.append([points[0], points[2], points[3], n])
	for a in range(3):
		for b in range(a + 1, 3):
			var c := 3 - a - b
			for sa in [-1, 1]:
				for sb in [-1, 1]:
					var p := Vector3.ZERO; p[a] = sa * 0.5; p[b] = sb * h; p[c] = -h
					var q := Vector3.ZERO; q[a] = sa * h; q[b] = sb * 0.5; q[c] = -h
					var r := q; r[c] = h
					var s := p; s[c] = h
					var n := Vector3.ZERO; n[a] = sa; n[b] = sb; n = n.normalized()
					triangles.append([p, q, r, n]); triangles.append([p, r, s, n])
	for x in [-1, 1]:
		for y in [-1, 1]:
			for z in [-1, 1]:
				triangles.append([Vector3(x * 0.5, y * h, z * h), Vector3(x * h, y * 0.5, z * h), Vector3(x * h, y * h, z * 0.5), Vector3(x, y, z).normalized()])
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	for t in triangles:
		var cross_product: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		var indices := [0, 2, 1] if cross_product.dot(t[3]) > 0 else [0, 1, 2]
		for index in indices: vertices.append(t[index]); normals.append(t[3])
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func piece(parent: Node3D, mesh: Mesh, at: Vector3, scale_by: Vector3, color: Color, label: String = "", glow: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh; node.position = at; node.scale = scale_by; node.material_override = mat(color, glow)
	if label != "": node.name = label
	parent.add_child(node)
	return node

func create(e: Dictionary, team: Color, presentation: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.set_meta("kind", e.kind)
	var model := Node3D.new(); model.name = "Model"; root.add_child(model)
	if e.has("cell"): _structure(model, e, team)
	elif e.owner < 0: _creature(model, e, presentation)
	elif e.kind in ["scout", "ranger", "excavator", "reaper", "cremator", "javelin"]: _vehicle(model, e, team)
	else: _person(model, e, team)
	return root

func _vehicle(root: Node3D, e: Dictionary, team: Color) -> void:
	var mech: bool = e.kind in ["reaper", "cremator", "javelin"]
	if mech:
		for side in [-1, 1]:
			var leg := Node3D.new(); leg.name = "LegL" if side < 0 else "LegR"; leg.position = Vector3(side * 0.25, 0.65, 0); root.add_child(leg)
			piece(leg, box, Vector3(0, -0.24, 0), Vector3(0.22, 0.5, 0.28), STEEL)
			piece(leg, box, Vector3(0, -0.53, -0.1), Vector3(0.33, 0.15, 0.49), DARK)
		piece(root, box, Vector3(0, 0.93, 0), Vector3(0.83, 0.65, 0.65), STEEL)
		piece(root, box, Vector3(0, 1.12, -0.34), Vector3(0.47, 0.15, 0.06), team)
		var weapon := Node3D.new(); weapon.name = "Weapon"; root.add_child(weapon)
		for side in [-1, 1]:
			piece(weapon, box, Vector3(side * 0.5, 0.88, -0.27), Vector3(0.24, 0.27, 0.86 if e.kind == "javelin" else 0.62), EDGE)
			if e.kind == "cremator": piece(root, cylinder, Vector3(side * 0.24, 0.93, 0.45), Vector3(0.25, 0.56, 0.25), AMBER.darkened(0.3))
	else:
		var length := 1.1 if e.kind == "scout" else 1.6
		piece(root, box, Vector3(0, 0.35, 0), Vector3(0.85, 0.36, length), STEEL)
		piece(root, wedge, Vector3(0, 0.66, -0.23), Vector3(0.65, 0.35, 0.62), team.darkened(0.2))
		piece(root, box, Vector3(0, 0.68, -0.56), Vector3(0.49, 0.16, 0.05), Color("6b9b9f"))
		for side in [-1, 1]:
			for axle in [-1, 1]:
				var wheel := piece(root, cylinder, Vector3(side * 0.49, 0.23, axle * length * 0.32), Vector3(0.4, 0.22, 0.4), DARK)
				wheel.rotation.z = PI / 2
			piece(root, box, Vector3(side * 0.43, 0.47, 0), Vector3(0.14, 0.12, length), EDGE)
		if e.kind != "scout":
			piece(root, box, Vector3(0, 0.56, 0.49), Vector3(0.68, 0.34, 0.57), DARK)
			var cargo := piece(root, box, Vector3(0, 0.77, 0.47), Vector3(0.55, 0.2, 0.44), Color("927d58"), "Cargo"); cargo.visible = false
		if e.kind == "excavator":
			piece(root, box, Vector3(0, 0.45, -0.93), Vector3(0.22, 0.22, 0.75), AMBER.darkened(0.2))
			var drill := piece(root, cylinder, Vector3(0, 0.43, -1.32), Vector3(0.43, 0.57, 0.43), EDGE, "Drill"); drill.rotation.x = PI / 2
	if e.kind == "scout":
		var rider := Node3D.new(); rider.name = "Rider"; rider.position = Vector3(0, 0.67, 0.22); root.add_child(rider)
		piece(rider, box, Vector3(0, 0.1, 0), Vector3(0.24, 0.22, 0.2), STEEL)
		piece(rider, sphere, Vector3(0, 0.3, 0), Vector3(0.23, 0.23, 0.24), IVORY)
		piece(rider, box, Vector3(0, 0.31, -0.12), Vector3(0.16, 0.06, 0.03), Color("8bcecf"), "", true)
		var gun := Node3D.new(); gun.name = "Gun"; rider.add_child(gun)
		piece(gun, box, Vector3(0.12, 0.14, -0.19), Vector3(0.1, 0.1, 0.4), DARK)
	var lamps := Node3D.new(); lamps.name = "Headlights"; root.add_child(lamps)
	for side in [-1, 1]: piece(lamps, box, Vector3(side * 0.28, 0.6 if not mech else 1.2, -0.58 if not mech else -0.34), Vector3(0.15, 0.08, 0.04), Color("ffe5ad"), "", true)

func _person(root: Node3D, e: Dictionary, team: Color) -> void:
	var armored: bool = e.kind in ["marine", "flamer", "lancer"]
	var suit := STEEL if armored else IVORY.darkened(0.17)
	for side in [-1, 1]:
		var leg := Node3D.new(); leg.name = "LegL" if side < 0 else "LegR"; leg.position = Vector3(side * 0.095, 0.31, 0); root.add_child(leg)
		piece(leg, box, Vector3(0, -0.12, 0), Vector3(0.12, 0.25, 0.15), DARK)
		piece(leg, box, Vector3(0, -0.24, -0.03), Vector3(0.14, 0.1, 0.22), STEEL)
		piece(root, sphere, Vector3(side * 0.215, 0.47, 0), Vector3(0.18, 0.19, 0.22), team.darkened(0.24) if side < 0 else suit)
	piece(root, wedge, Vector3(0, 0.42, 0), Vector3(0.38, 0.38, 0.29), suit)
	piece(root, box, Vector3(0, 0.44, -0.155), Vector3(0.24, 0.17, 0.035), EDGE)
	piece(root, sphere, Vector3(0, 0.72, -0.02), Vector3(0.3, 0.30, 0.31), IVORY if armored else STEEL)
	piece(root, box, Vector3(0, 0.73, -0.165), Vector3(0.23, 0.085, 0.045), Color("8bcecf"), "Visor", true)
	piece(root, box, Vector3(0, 0.44, 0.19), Vector3(0.26, 0.32, 0.15), DARK)
	if e.kind == "engineer":
		piece(root, box, Vector3(0, 0.47, 0.27), Vector3(0.21, 0.23, 0.05), AMBER.darkened(0.15))
		piece(root, box, Vector3(0.23, 0.34, -0.21), Vector3(0.14, 0.13, 0.31), AMBER, "Tool")
	elif armored:
		var gun := Node3D.new(); gun.name = "Weapon"; root.add_child(gun)
		piece(gun, box, Vector3(0.2, 0.4, -0.24), Vector3(0.14, 0.13, 0.42), DARK)
		piece(gun, box, Vector3(0.2, 0.42, -0.49), Vector3(0.07, 0.07, 0.21 if e.kind == "lancer" else 0.11), EDGE)
		if e.kind == "flamer":
			for side in [-1, 1]: piece(root, cylinder, Vector3(side * 0.09, 0.46, 0.29), Vector3(0.14, 0.35, 0.14), AMBER.darkened(0.2))
		if e.kind == "lancer": piece(gun, box, Vector3(0.2, 0.5, -0.21), Vector3(0.1, 0.07, 0.2), team)
	var cargo := piece(root, box, Vector3(0, 0.45, 0.33), Vector3(0.27, 0.25, 0.2), Color("927d58"), "Cargo")
	cargo.visible = false

func _creature(root: Node3D, e: Dictionary, presentation: Dictionary) -> void:
	var scale_by: Array = presentation.get("creatureScales", {}).get(e.kind, [1, 1, 1])
	root.scale = Vector3(float(scale_by[0]), float(scale_by[1]), float(scale_by[2]))
	root.set_meta("base_scale", root.scale)
	var shell := Color("6f6d61")
	piece(root, sphere, Vector3(0, 0.22, 0.05), Vector3(0.45, 0.26, 0.63), shell)
	piece(root, wedge, Vector3(0, 0.24, -0.28), Vector3(0.27, 0.22, 0.32), BONE)
	for side in [-1, 1]:
		piece(root, sphere, Vector3(side * 0.085, 0.28, -0.42), Vector3(0.055, 0.04, 0.04), Color("e38c6c"), "", true)
		for i in range(3):
			var leg := piece(root, box, Vector3(side * 0.26, 0.11, (i - 1) * 0.19), Vector3(0.34, 0.055, 0.07), BONE.darkened(0.25), "Claw%d_%d" % [side, i])
			leg.rotation = Vector3(0, side * (i - 1) * -0.45, side * 0.38)

	if e.kind == "ravager":
		for side in [-1, 1]:
			piece(root, wedge, Vector3(side * 0.16, 0.34, -0.03), Vector3(0.26, 0.17, 0.47), BONE.darkened(0.14))
			var tusk := piece(root, wedge, Vector3(side * 0.17, 0.17, -0.47), Vector3(0.09, 0.19, 0.35), BONE)
			tusk.rotation.x = -0.5
		piece(root, box, Vector3(0, 0.18, -0.4), Vector3(0.19, 0.09, 0.13), Color("302c2a"))
	elif e.kind == "stalker":
		for side in [-1, 1]:
			var blade := piece(root, wedge, Vector3(side * 0.28, 0.27, -0.32), Vector3(0.07, 0.11, 0.5), BONE)
			blade.rotation.y = side * 0.45
	elif e.kind == "thresher":
		for i in range(5):
			var spine := piece(root, wedge, Vector3((i - 2) * 0.1, 0.35, 0.08), Vector3(0.075, 0.3, 0.22), BONE)
			spine.rotation.z = (i - 2) * -0.18

func _structure(root: Node3D, e: Dictionary, team: Color) -> void:
	var stripe := team.darkened(0.2)
	if e.kind == "anchor":
		piece(root, cylinder, Vector3(0, 0.08, 0), Vector3(2.75, 0.15, 2.75), DARK)
		var hull := CylinderMesh.new()
		hull.top_radius = 0.45; hull.bottom_radius = 0.76; hull.height = 1.2; hull.radial_segments = 8
		piece(root, hull, Vector3(0, 0.77, 0), Vector3(1.35, 1, 1.35), STEEL)
		piece(root, cylinder, Vector3(0, 1.43, 0), Vector3(1.22, 0.15, 1.22), DARK)
		piece(root, cylinder, Vector3(0, 1.55, 0), Vector3(0.92, 0.12, 0.92), EDGE)
		for i in range(8):
			var a := i * TAU / 8 + PI / 8
			var plate := piece(root, box, Vector3(sin(a) * 0.77, 0.83, cos(a) * 0.77), Vector3(0.48, 0.71, 0.075), IVORY.darkened(0.26) if i % 3 == 0 else STEEL.lightened(0.06))
			plate.rotation = Vector3(-0.3, a, 0)
			if i % 3 == 0:
				var marking := piece(root, box, Vector3(sin(a) * 0.79, 0.91, cos(a) * 0.79), Vector3(0.43, 0.065, 0.08), stripe)
				marking.rotation = Vector3(-0.3, a, 0)
		for i in range(3):
			var a := i * TAU / 3 + PI / 6
			var leg := piece(root, wedge, Vector3(cos(a) * 0.87, 0.39, sin(a) * 0.87), Vector3(0.55, 0.65, 1.0), STEEL)
			leg.rotation.y = -a + PI / 2
			piece(root, cylinder, Vector3(cos(a) * 1.1, 0.15, sin(a) * 1.1), Vector3(0.55, 0.22, 0.55), EDGE)
			piece(root, box, Vector3(cos(a) * 0.79, 0.72, sin(a) * 0.79), Vector3(0.2, 0.07, 0.2), Color("f6d58b"), "", true)
		piece(root, cylinder, Vector3(0.28, 1.9, 0.18), Vector3(0.035, 0.95, 0.035), EDGE)
		piece(root, sphere, Vector3(0.28, 2.39, 0.18), Vector3(0.12, 0.1, 0.12), AMBER, "Beacon", true)
		piece(root, box, Vector3(0, 0.76, -0.69), Vector3(0.48, 0.5, 0.08), DARK)
		piece(root, box, Vector3(0, 0.77, -0.75), Vector3(0.34, 0.035, 0.03), Color("f6d58b"), "", true)
	elif e.kind == "medusa":
		piece(root, sphere, Vector3(0, 0.61, 0), Vector3(2.65, 1.12, 2.4), Color("72635e"))
		piece(root, sphere, Vector3(0, 1.0, 0), Vector3(1.45, 0.55, 1.55), Color("b1a18a"))
		for i in range(8):
			var a := i * TAU / 8
			var rib := piece(root, wedge, Vector3(cos(a), 0.4, sin(a)), Vector3(0.4, 0.8, 1.35), BONE.darkened(0.24))
			rib.rotation.y = -a + PI / 2
			piece(root, sphere, Vector3(cos(a) * 0.7, 0.93, sin(a) * 0.7), Vector3(0.17, 0.12, 0.17), Color("ba796b"), "", true)
	elif e.kind == "gate":
		for side in [-1, 1]:
			piece(root, box, Vector3(side * 0.43, 0.5, 0), Vector3(0.16, 1, 0.78), STEEL)
			piece(root, box, Vector3(side * 0.43, 0.92, -0.4), Vector3(0.15, 0.09, 0.04), AMBER)
		var panel := Node3D.new(); panel.name = "GatePanel"; root.add_child(panel)
		piece(panel, box, Vector3(0, 0.45, 0), Vector3(0.66, 0.86, 0.65), EDGE)
		for i in range(3): piece(panel, box, Vector3(0, 0.23 + i * 0.2, -0.34), Vector3(0.58, 0.05, 0.03), stripe)
	elif e.kind == "wall":
		piece(root, wedge, Vector3(0, 0.5, 0), Vector3(0.96, 1, 0.88), STEEL)
		piece(root, box, Vector3(0, 0.86, -0.28), Vector3(0.82, 0.09, 0.1), stripe)
	elif e.kind == "depot":
		piece(root, box, Vector3(0, 0.06, 0), Vector3(0.95, 0.12, 0.88), DARK)
		for i in range(3):
			piece(root, box, Vector3((i - 1) * 0.28, 0.28, 0), Vector3(0.25, 0.38, 0.68), EDGE)
			piece(root, box, Vector3((i - 1) * 0.28, 0.48, 0), Vector3(0.18, 0.035, 0.58), AMBER.darkened(0.3))
	elif e.kind in ["sentry", "torch", "lance"]:
		piece(root, cylinder, Vector3(0, 0.15, 0), Vector3(0.95, 0.3, 0.95), DARK)
		piece(root, cylinder, Vector3(0, 0.51, 0), Vector3(0.36, 0.6, 0.36), EDGE)
		var gun := Node3D.new(); gun.name = "Turret"; root.add_child(gun)
		piece(gun, wedge, Vector3(0, 0.8, 0), Vector3(0.57, 0.35, 0.58), STEEL)
		for side in [-1, 1]: piece(gun, box, Vector3(side * 0.18, 0.83, -0.43), Vector3(0.1, 0.11, 0.58), EDGE)
		piece(gun, box, Vector3(0, 0.96, 0), Vector3(0.3, 0.04, 0.3), stripe)
	elif e.kind in ["relay", "floodlight", "radar"]:
		piece(root, cylinder, Vector3(0, 0.13, 0), Vector3(0.8, 0.25, 0.8), DARK)
		piece(root, box, Vector3(0, 0.45, 0), Vector3(0.34, 0.55, 0.34), STEEL)
		piece(root, cylinder, Vector3(0, 1.15, 0), Vector3(0.07, 1.5, 0.07), EDGE)
		piece(root, box, Vector3(0, 1.9, 0), Vector3(0.6, 0.22, 0.27), DARK)
		piece(root, box, Vector3(0, 1.9, -0.15), Vector3(0.48, 0.13, 0.025), Color("ffe5ad") if e.kind == "floodlight" else Color("8bcecf"), "Lamp", true)
		if e.kind == "radar":
			var dish := Node3D.new(); dish.name = "RadarDish"; dish.position.y = 1.97; root.add_child(dish)
			piece(dish, box, Vector3.ZERO, Vector3(1.15, 0.12, 0.2), EDGE)
			piece(dish, box, Vector3(0, 0.13, 0), Vector3(0.08, 0.3, 0.65), STEEL)
	elif e.kind == "rampart":
		piece(root, cylinder, Vector3(0, 0.12, 0), Vector3(1.05, 0.25, 1.05), DARK)
		for i in range(3):
			var angle := i * TAU / 3
			piece(root, box, Vector3(cos(angle) * 0.36, 0.49, sin(angle) * 0.36), Vector3(0.16, 0.75, 0.16), STEEL)
		piece(root, cylinder, Vector3(0, 0.89, 0), Vector3(0.81, 0.13, 0.81), EDGE)
		piece(root, sphere, Vector3(0, 0.58, 0), Vector3(0.34, 0.4, 0.34), Color("94d2c1"), "ShieldCore", true)
	elif e.kind in ["generator", "reactor"]:
		piece(root, box, Vector3(0, 0.12, 0), Vector3(0.9, 0.24, 0.86), DARK)
		for side in [-1, 1]: piece(root, cylinder, Vector3(side * 0.22, 0.53, 0), Vector3(0.34, 0.7, 0.46), STEEL)
		piece(root, box, Vector3(0, 0.8, 0), Vector3(0.7, 0.13, 0.63), EDGE)
		piece(root, cylinder, Vector3(0.25, 1.0, 0.15), Vector3(0.12, 0.55, 0.12), DARK)
		piece(root, box, Vector3(0, 0.54, -0.27), Vector3(0.4, 0.2, 0.04), AMBER.darkened(0.3))
		var rotor := Node3D.new(); rotor.name = "Rotor"; rotor.position = Vector3(0, 0.91, 0); root.add_child(rotor)
		for i in range(4):
			var blade := piece(rotor, box, Vector3(cos(i * PI / 2) * 0.17, 0, sin(i * PI / 2) * 0.17), Vector3(0.08, 0.05, 0.38), DARK)
			blade.rotation.y = -i * PI / 2
	elif e.kind == "factory":
		piece(root, box, Vector3(0, 0.08, 0), Vector3(2.7, 0.16, 2.5), DARK)
		for side in [-1, 1]:
			piece(root, box, Vector3(side * 1.02, 0.8, 0), Vector3(0.48, 1.45, 2.0), STEEL)
			piece(root, box, Vector3(side * 1.02, 1.5, 0), Vector3(0.52, 0.12, 2.12), team.darkened(0.2))
		var gantry := Node3D.new(); gantry.name = "Gantry"; root.add_child(gantry)
		piece(gantry, box, Vector3(0, 1.3, -0.2), Vector3(0.25, 0.2, 0.45), AMBER.darkened(0.25))
		piece(gantry, cylinder, Vector3(0, 0.99, -0.2), Vector3(0.06, 0.5, 0.06), EDGE)
		piece(root, box, Vector3(0, 1.58, 0.36), Vector3(2.55, 0.21, 1.4), EDGE)
		piece(root, box, Vector3(0, 0.75, 0.92), Vector3(1.7, 1.35, 0.15), DARK)
		for side in [-1, 1]: piece(root, box, Vector3(side * 0.75, 1.25, -0.97), Vector3(0.12, 0.15, 0.05), AMBER, "", true)
	elif e.kind == "extractor":
		for side in [-1, 1]: piece(root, wedge, Vector3(side * 0.34, 0.44, 0), Vector3(0.2, 0.85, 0.75), STEEL)
		piece(root, box, Vector3(0, 0.95, 0), Vector3(0.95, 0.17, 0.53), EDGE)
		piece(root, cylinder, Vector3(0, 0.44, 0), Vector3(0.24, 0.82, 0.24), AMBER.darkened(0.25), "Drill")
		piece(root, box, Vector3(0, 1.06, 0), Vector3(0.5, 0.05, 0.45), stripe)
	else:
		piece(root, box, Vector3(0, 0.12, 0), Vector3(0.94, 0.24, 0.94), DARK)
		piece(root, wedge, Vector3(0, 0.53, 0), Vector3(0.82, 0.82, 0.85), STEEL)
		piece(root, box, Vector3(0, 0.74, -0.35), Vector3(0.65, 0.11, 0.1), stripe)
		for side in [-1, 1]: piece(root, cylinder, Vector3(side * 0.27, 0.64, 0.2), Vector3(0.16, 0.75, 0.16), EDGE)
		piece(root, box, Vector3(0, 0.4, -0.43), Vector3(0.38, 0.25, 0.05), DARK)
		piece(root, box, Vector3(0, 0.54, -0.46), Vector3(0.3, 0.035, 0.025), Color("f0d193"), "", true)
