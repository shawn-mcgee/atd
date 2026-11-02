extends RefCounted
const Config = preload("res://engine/gameplay_config.gd")
var minerals: int = int(Config.value("economy", "starting_minerals"))
var gas: float = Config.value("economy", "starting_gas")
var mineral_capacity := 100
var gas_capacity := 100

func recalculate(structures: Array) -> void:
	mineral_capacity = 0
	gas_capacity = 0
	for b in structures:
		if not b.complete or b.hp <= 0: continue
		if b.kind == "core": mineral_capacity += int(Config.value("economy", "hq_capacity")); gas_capacity += int(Config.value("economy", "hq_capacity"))
		if b.kind == "depot": mineral_capacity += int(Config.value("economy", "mineral_depot_capacity"))
		if b.kind == "gas_tank": gas_capacity += int(Config.value("economy", "gas_tank_capacity"))
	# Storage loss never erases banked resources. New deliveries wait until there is room.

func can_spend(cost: Dictionary) -> bool:
	return minerals >= int(cost.get("minerals", 0)) and gas + 0.00001 >= float(cost.get("gas", 0))

func spend(cost: Dictionary) -> bool:
	if not can_spend(cost): return false
	minerals -= int(cost.get("minerals", 0))
	gas = maxf(0, gas - float(cost.get("gas", 0)))
	return true

func deposit(kind: String, amount: int) -> int:
	var accepted := mini(amount, maxi(0, mineral_capacity - minerals) if kind == "minerals" else maxi(0, floori(gas_capacity - gas)))
	if kind == "minerals": minerals += accepted
	else: gas += accepted
	return accepted

func space(kind: String) -> int:
	return maxi(0, mineral_capacity - minerals) if kind == "minerals" else maxi(0, floori(gas_capacity - gas))
