extends "res://scripts/scenario_layout.gd"
## Stable, populated fixture for focused mechanics regressions.
const Visual = preload("res://scripts/expedition_visuals.gd")
func generate(terrain, _requested_seed: int = 0) -> void:
	seed_value = 1; base_grace = 55.0; terrain.natural_enabled = true
	beacon_position = Vector3(-45, 0, 14); hive_position = Vector3(64, 0, -42)
	fields = [{"kind": "minerals", "position": Vector3(32, 0, -24), "remaining": 1200}, {"kind": "gas", "position": Vector3(51, 3, 7), "remaining": 900}, {"kind": "minerals", "position": Vector3(-50, 0, 35), "remaining": 1600}, {"kind": "minerals", "position": Vector3(65, 0, 40), "remaining": 1800}, {"kind": "gas", "position": Vector3(-40, 0, -50), "remaining": 1100}, {"kind": "gas", "position": Vector3(15, 0, 68), "remaining": 1400}]
func setup_base(game) -> void:
	game.core = game.add_structure("core", game.HOME)
	game.home_depot = game.add_structure("depot", game.HOME + Vector3(7, 0, 0))
	game.add_structure("gas_tank", game.HOME + Vector3(-7, 0, 0))
	game.add_structure("generator", game.HOME + Vector3(0, 0, 6))
	game.add_structure("floodlight", game.HOME + Vector3(0, 0, -7))
	game.add_structure("barracks", game.HOME + Vector3(7, 0, 6))
	game.add_structure("garage", game.HOME + Vector3(-7, 0, 6))
	for i in range(2): game.add_unit("engineer", game.HOME + Vector3(-4 + i * 8, 0, -1))
	for i in range(4): game.add_unit("marine", game.HOME + Vector3(-5 + i * 2, 0, -5))
	game.jeep = game.add_unit("jeep", game.HOME + Vector3(9, 0, -2))
	game.economy.minerals = 400; game.economy.gas = 140
	for point in [Vector3(0, 0, 3), Vector3(0, 0, -3), Vector3(7, 0, 3), Vector3(-7, 0, 3)]: game.add_structure("repeater", point)
	game.core.lamp.omni_range = 14; game.core.lamp.light_energy = 2

func make_landscape(game) -> void:
	for r in range(-2, 15):
		for q in range(16, 42):
			var point := Hex.to_world(Vector2i(q, r), Terrain.CELL)
			if not Terrain.natural_mesa_cell(point): continue
			var mesa := MeshInstance3D.new(); mesa.mesh = Terrain.hex_mesh(3); mesa.position = point; game.add_child(mesa)
			mesa.material_override = game.fog_material(Color("566e70")); mesa.set_meta("pick_occluder", true); game.add_terrain_collider(mesa)
			game.terrain_meshes[Hex.to_axial(point, Terrain.CELL)] = mesa
	var ramp := MeshInstance3D.new(); ramp.mesh = Terrain.ramp_mesh()
	ramp.position = Hex.snap(Vector3(43.3, 0, 6), Terrain.CELL); ramp.material_override = game.fog_material(Color("69847c"))
	ramp.set_meta("pick_occluder", true); game.add_child(ramp); game.add_terrain_collider(ramp)
	# Alternating gaps make connected canyon passages instead of a clear diagonal.
	for i in range(-56, 57):
		var z := i * Terrain.CELL * 1.5
		if z < -35 or z > -23: game.add_natural_obstacle(Vector3(18, 0, z), i)
		if z < 2 or z > 14: game.add_natural_obstacle(Vector3(35, 0, z), i + 71)
		if z < 20 or z > 32: game.add_natural_obstacle(Vector3(-24, 0, z), i + 137)
	for i in range(-44, -4):
		var x := i * Terrain.SPACING
		if x < -48 or x > -37: game.add_natural_obstacle(Vector3(x, 0, -30), i + 191)

