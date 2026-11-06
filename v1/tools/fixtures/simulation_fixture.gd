extends "res://engine/simulation.gd"
const DEPOSIT := Vector3(32, 0, -24)
const GAS_DEPOSIT := Vector3(51, 3, 7)
func _init() -> void:
	layout = preload("res://tools/fixtures/mechanics_layout.gd").new()
	initialize(1)
func select_actor(actor: SimEntity, append: bool = false) -> void:
	if not append: selected.clear()
	if actor != null and not selected.has(actor): selected.append(actor)
