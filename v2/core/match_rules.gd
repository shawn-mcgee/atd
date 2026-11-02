extends RefCounted
const Canonical = preload("res://core/canonical.gd")

static func participants(requested: Array) -> Array:
	var result: Array = []
	var humans := 0
	var lightless := 0
	var ids: Array = []
	for item in requested:
		if not item is Dictionary or not item.get("faction") in ["human", "lightless"] or not item.get("controller") in ["human", "ai"]:
			return []
		if not (item.get("id") is int or item.get("id") is float) or item.id != floor(item.id): return []
		var id := int(item.get("id", 0))
		if id <= 0 or id > 16777215 or ids.has(id): return []
		ids.append(id)
		if item.faction == "lightless": lightless += 1
		else: humans += 1
		result.append({"id": id, "faction": item.faction, "controller": item.controller})
	if lightless > 1 or result.size() > 8: return []
	for faction in ["human", "lightless"]:
		if (faction == "human" and humans > 0) or (faction == "lightless" and lightless > 0): continue
		var id := 1
		while ids.has(id): id += 1
		ids.append(id)
		result.append({"id": id, "faction": faction, "controller": "ai"})
	if result.size() > 8: return []
	result.sort_custom(func(a, b): return int(a.id) < int(b.id))
	return Canonical.normalize(result)
