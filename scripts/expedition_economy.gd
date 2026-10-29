extends RefCounted
var minerals := 400
var gas := 140.0
var mineral_capacity := 500
var gas_capacity := 240

func recalculate(structures: Array) -> void:
	mineral_capacity = 0
	gas_capacity = 0
	for b in structures:
		if not b.complete or b.hp <= 0: continue
		if b.kind == "core": mineral_capacity += 100; gas_capacity += 40
		if b.kind == "depot": mineral_capacity += 400
		if b.kind == "gas_tank": gas_capacity += 200
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
