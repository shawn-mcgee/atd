extends RefCounted
const Rules = preload("res://engine/expedition_rules.gd")

func reload(game, turret: SimStructure) -> bool:
	if not Rules.TURRETS.has(turret.kind) or not turret.complete or turret.hp <= 0 or not turret.enabled or not turret.powered or turret.reload_remaining > 0: return false
	var stats: Dictionary = Rules.TURRETS[turret.kind]
	if stats.magazine == 0 or turret.ammo >= int(stats.magazine) or not game.economy.spend(stats.reload_cost): return false
	turret.reload_remaining = float(stats.reload_time)
	turret.state_changed()
	return true

func tick(game, dt: float) -> void:
	for turret in game.structures:
		if not Rules.TURRETS.has(turret.kind) or not turret.complete or turret.hp <= 0 or not turret.powered or not turret.enabled: continue
		var stats: Dictionary = Rules.TURRETS[turret.kind]
		if turret.reload_remaining > 0:
			turret.reload_remaining = maxf(0, turret.reload_remaining - dt)
			if turret.reload_remaining == 0: turret.ammo = int(stats.magazine)
			turret.state_changed(); continue
		if int(stats.magazine) > 0 and turret.ammo <= 0:
			if turret.auto_reload: reload(game, turret)
			continue
		if turret.cooldown > 0: continue
		var enemy: SimPredator = game.visible_target(turret.position, float(stats.range))
		if enemy == null: continue
		if int(stats.magazine) > 0: turret.ammo -= 1
		if float(stats.splash) > 0:
			for other in game.creatures:
				if other.hp > 0 and other.position.distance_to(enemy.position) <= float(stats.splash) and game.light.sample(other.position) >= 0.065 and game.navigation.can_see(turret.position, other.position): other.hurt(float(stats.damage))
		else: enemy.hurt(float(stats.damage))
		turret.cooldown = float(stats.delay)
		game.shot(turret.position + Vector3.UP * 1.5, enemy.position + Vector3.UP * 0.7, Color("f28a42") if turret.kind == "flame_turret" else Color("e96fee") if turret.kind == "laser_turret" else game.AMBER, turret)
