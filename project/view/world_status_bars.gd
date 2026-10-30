extends Control
const Rules = preload("res://engine/expedition_rules.gd")
var game: Node2D

func setup(world: Node2D) -> void:
	game = world; mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(_dt: float) -> void:
	queue_redraw()

func bar(point: Vector2, value: float, color: Color) -> void:
	draw_rect(Rect2(point - Vector2(18, 0), Vector2(36, 4)), Color("23313b"))
	draw_rect(Rect2(point - Vector2(18, 0), Vector2(36 * clampf(value, 0, 1), 4)), color)

func _draw() -> void:
	if game == null or not game.started: return
	for actor in game.units + game.structures + game.creatures + [game.mission.hive]:
		if not actor.visible or actor.hp <= 0 or (actor is SimUnit and actor.aboard != null): continue
		var point: Vector2 = game.world_to_screen(game.actor_position(actor))
		var maximum: float = actor.max_hp if actor is SimPredator else Rules.UNITS[actor.kind].hp if actor is SimUnit else Rules.STRUCTURES[actor.kind].hp
		if actor.hp < maximum: bar(point + Vector2(0, -22), actor.hp / maximum, Color("ecb881"))
		if actor is SimUnit and actor.is_vehicle(): bar(point + Vector2(0, 22), actor.battery / 100, Color("8ac7ed"))
