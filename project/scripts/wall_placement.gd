extends Node3D
const Terrain = preload("res://scripts/expedition_terrain.gd")
## A drag previews a straight, contiguous hex line. Nothing is funded until release.
const Hex = preload("res://scripts/hex_grid.gd")
const Visual = preload("res://scripts/expedition_visuals.gd")
var active := false
var start_screen := Vector2.ZERO
var start_world := Vector3.ZERO
var points: Array[Vector3] = []
var buildable: Array[bool] = []
var count := 0
var markers: Array[MeshInstance3D] = []
var marker_mesh: CylinderMesh
var ready_material: StandardMaterial3D
var blocked_material: StandardMaterial3D
var budget_material: StandardMaterial3D

func _ready() -> void:
	marker_mesh = CylinderMesh.new()
	marker_mesh.top_radius = Terrain.CELL * 0.92; marker_mesh.bottom_radius = Terrain.CELL * 0.92
	marker_mesh.radial_segments = 6; marker_mesh.height = 0.12
	ready_material = preview_material(Color("7bf4d0"))
	blocked_material = preview_material(Color("ed8278"))
	budget_material = preview_material(Color("efbd77"))

func preview_material(color: Color) -> StandardMaterial3D:
	var mat := Visual.material(Color(color, 0.55), true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func begin(screen: Vector2, point: Vector3) -> void:
	active = true; start_screen = screen; start_world = point

func cancel() -> void:
	active = false; visible = false
	points.clear(); buildable.clear(); count = 0

func update_preview(game, endpoint: Vector3) -> void:
	points.clear(); buildable.clear(); count = 0
	visible = active and endpoint.is_finite()
	if not visible: return
	var budget: int = game.economy.minerals
	var cost: int = game.Rules.cost("wall").minerals
	for point in Hex.line(start_world, endpoint, Terrain.CELL):
		point = game.navigation.terrain.surface(point)
		var valid: bool = game.valid_site("wall", point)
		var affordable := budget >= cost
		points.append(point); buildable.append(valid and affordable)
		if valid and affordable: budget -= cost; count += 1
		var index := points.size() - 1
		if index >= markers.size():
			var marker := MeshInstance3D.new(); marker.mesh = marker_mesh
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(marker); markers.append(marker)
		markers[index].visible = true
		markers[index].position = point + Vector3.UP * 0.15
		markers[index].material_override = blocked_material if not valid else ready_material if affordable else budget_material
	for i in range(points.size(), markers.size()): markers[i].visible = false
