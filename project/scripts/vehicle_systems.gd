extends RefCounted
const Power = preload("res://scripts/expedition_power.gd")
const DRILL_COST := 5.0

func tick(game, dt: float) -> void:
	for unit in game.units:
		if not unit.is_vehicle() or unit.hp <= 0: continue
		var charging := false
		for source in game.structures:
			if source.kind in ["generator", "repeater"] and source.complete and source.enabled and source.powered and Power.covers(source, unit.position):
				charging = true; break
		if charging: unit.battery = minf(100, unit.battery + 8 * dt)
		elif unit.motion_velocity.length_squared() > 0.01: unit.battery = maxf(0, unit.battery - 0.25 * dt)
		unit.update_lights()
		if unit.kind == "drill" and unit.order == "drill": drill(game, unit, dt)

func drill(game, unit: ExpeditionUnit, dt: float) -> void:
	var cell = game.Hex.to_axial(unit.goal, game.Terrain.CELL)
	var index := -1
	for i in range(game.rocks.size()):
		if game.rocks[i].cell == cell: index = i; break
	var mesa: bool = game.terrain_meshes.has(cell) and not game.navigation.terrain.cleared_cells.has(cell)
	if index < 0 and not mesa: unit.order = "idle"; unit.path.clear(); return
	var rock: Dictionary = game.rocks[index] if index >= 0 else {"position": game.Hex.to_world(cell, game.Terrain.CELL), "node": game.terrain_meshes[cell]}
	if Vector2(unit.position.x - rock.position.x, unit.position.z - rock.position.z).length() > 3.2:
		if not unit.moving(): unit.travel(rock.position, game.navigation)
		return
	unit.path.clear()
	if unit.battery <= 0 or not unit.has_driver(): return
	unit.work_clock += dt
	if unit.work_clock < 3: return
	if not game.economy.spend({"gas": DRILL_COST}):
		unit.work_clock = 3; return
	unit.work_clock = 0
	var mesh = rock.get("node")
	if is_instance_valid(mesh):
		if game.picker != null: game.picker.remove_owner(mesh)
		if game.occluded_units != null: game.occluded_units.remove_occluder(mesh)
		mesh.queue_free()
	if index >= 0: game.rocks.remove_at(index)
	else: game.navigation.terrain.cleared_cells[cell] = true; game.terrain_meshes.erase(cell)
	game.rebuild_navigation()
	unit.order = "idle"; unit.battery = maxf(0, unit.battery - 1)
	game.notify("Terrain cleared / 5 methane consumed")
