extends RefCounted
const Actor = preload("res://core/actor.gd")
## Human blueprints are inert actors; one assigned engineer supplies work.
const Hex = preload("res://core/hex_cells.gd")
const Construction = preload("res://core/construction.gd")

static func order(game, worker: Actor, type: String, point: Array, rotation: int = 0) -> void:
	if not Construction.site_error(game, worker, type, point, false, rotation).is_empty(): return
	var cost := int(game.content.units[type].cost)
	var bank := str(worker.owner)
	if int(game.state.banks[bank]) < cost: return
	var cap: Dictionary = game.content.units[worker.definition].capabilities.builder
	game.state.banks[bank] = int(game.state.banks[bank]) - cost
	game._spawn(cap.blueprint, int(worker.owner), Hex.point(Hex.from_point(point)))
	var site = game.entity(int(game.state.next_id) - 1)
	site.rotation = rotation
	site.construction = {"kind": "blueprint", "definition": type, "cost": cost,
		"remaining": int(game.content.units[type].construction_ticks), "total": int(game.content.units[type].construction_ticks), "worker": int(worker.id)}
	worker.order = {"kind": "construct", "target": int(site.id), "manual": true}
	Construction._event(game, "construction_started", site, type, cost)

static func assign(game, worker: Actor, target: int) -> void:
	var site = game.entity(target)
	var cap: Dictionary = game.content.units[worker.definition].capabilities.get("builder", {})
	if site == null or int(site.hp) <= 0 or int(site.owner) != int(worker.owner) or cap.is_empty(): return
	if site.construction.get("kind") != "blueprint" or not site.construction.definition in cap.structures: return
	site.construction.worker = int(worker.id)
	worker.order = {"kind": "construct", "target": target, "manual": true}

static func work(game, worker: Actor) -> void:
	var site = game.entity(int(worker.order.target))
	if site == null or int(site.hp) <= 0 or site.construction.get("kind") != "blueprint" or int(site.construction.worker) != int(worker.id):
		worker.order = {}
		return
	var cap: Dictionary = game.content.units[worker.definition].capabilities.builder
	var range_fp := int(round(float(cap.work_range) * game.SCALE))
	if Construction.Geo.intersects_collision(game, worker, site) or game.interaction_distance(worker.position, site) > range_fp * range_fp:
		if not game._move(worker, site.position, site, range_fp, true):
			cancel(game, site)
			worker.order = {}
		return
	worker.motion.navigation = {}
	game._face(worker, site.position)
	site.construction.remaining = maxi(0, int(site.construction.remaining) - 1)
	if int(site.construction.remaining) > 0: return
	if not Construction.completion_clear(game, site):
		site.construction.blocked = true
		return
	var type: String = site.construction.definition
	var hp := Construction._scaled_hp(int(site.hp), int(game.content.units[site.definition].hp), int(game.content.units[type].hp))
	Construction._change(game, site, type)
	site.hp = hp
	worker.order = {}
	Construction._event(game, "construction_completed", site, type, 0)

static func cancel(game, actor: Actor) -> void:
	var site = actor
	if actor.order.get("kind") == "construct": site = game.entity(int(actor.order.target))
	if site == null or int(site.hp) <= 0 or int(site.owner) != int(actor.owner) or site.construction.get("kind") != "blueprint": return
	if actor != site and int(site.construction.worker) != int(actor.id):
		actor.order = {}
		return
	var work: Dictionary = site.construction
	game.state.banks[str(site.owner)] = int(game.state.banks[str(site.owner)]) + int(work.cost)
	Construction._event(game, "construction_cancelled", site, work.definition, int(work.cost))
	site.hp = 0
	for worker in game.state.actors:
		if worker.order.get("kind") == "construct" and int(worker.order.target) == int(site.id): worker.order = {}; worker.motion.navigation = {}
