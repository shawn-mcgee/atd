extends Node3D
## Own-grid planning information remains visible over unlit terrain.
const Power = preload("res://scripts/expedition_power.gd")
const Visual = preload("res://scripts/expedition_visuals.gd")
const READY := Color("7bf4d0")
const CAUTION := Color("efbd77")
const PLANNED := Color("7faaca")
var preview_ring: MeshInstance3D
var connector: MeshInstance3D
var source_rings: Dictionary = {}
var status: Dictionary = {}
var connector_key := ""
var ready_material: StandardMaterial3D
var caution_material: StandardMaterial3D
var planned_material: StandardMaterial3D
var ghost_material: StandardMaterial3D

func setup() -> void:
	ready_material = ring_material(Color(READY, 0.42))
	caution_material = ring_material(Color(CAUTION, 0.45))
	planned_material = ring_material(Color(PLANNED, 0.32))
	ghost_material = ring_material(READY)
	preview_ring = Visual.ring(self, Power.LINK_RANGE, READY, 192)
	preview_ring.material_override = ghost_material
	connector = MeshInstance3D.new(); add_child(connector)
	visible = false

func ring_material(color: Color) -> StandardMaterial3D:
	var mat := Visual.material(color, true)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func status_color() -> Color:
	return READY if status.get("state", "") in ["ready", "source"] else PLANNED if status.get("state", "") == "planned" else CAUTION

func update_preview(kind: String, point: Vector3, structures: Array) -> Dictionary:
	if not Power.is_electrical(kind):
		visible = false; status = {}; return status
	visible = true
	status = Power.placement_connection(kind, point, structures)
	preview_ring.position = point + Vector3.UP * 0.12
	ghost_material.albedo_color = status_color()
	var live: Dictionary = {}
	for b in structures:
		if b.kind not in ["generator", "repeater"] or b.hp <= 0: continue
		var id: int = b.get_instance_id()
		live[id] = true
		if not source_rings.has(id): source_rings[id] = Visual.ring(self, Power.LINK_RANGE, READY, 192)
		var ring: MeshInstance3D = source_rings[id]
		ring.position = b.position + Vector3.UP * 0.08
		ring.material_override = planned_material if not b.complete else ready_material if b.powered and b.enabled else caution_material
	for id in source_rings.keys():
		if not live.has(id): source_rings[id].queue_free(); source_rings.erase(id)
	var source = status.get("source")
	connector.visible = source != null
	if source != null:
		var key := "%s/%s/%s" % [point, source.position, status.state]
		if key != connector_key:
			connector_key = key
			var mesh := ImmediateMesh.new()
			mesh.surface_begin(Mesh.PRIMITIVE_LINES, Visual.material(status_color(), true))
			mesh.surface_add_vertex(point + Vector3.UP * 0.36)
			mesh.surface_add_vertex(source.position + Vector3.UP * 0.36)
			mesh.surface_end(); connector.mesh = mesh
	else: connector_key = ""
	return status
