extends RefCounted
## Canonical diagnostics/replay format; derived navigation caches are rebuilt.
static func encode(value):
	if value is StringName: return String(value)
	if value is SimEntity: return {"entity": value.simulation_id}
	if value is WeakRef: return encode(value.get_ref())
	if value is RandomNumberGenerator: return {"seed": value.seed, "state": value.state}
	if value is Vector3: return {"v3": [value.x, value.y, value.z]}
	if value is Vector2i: return {"v2i": [value.x, value.y]}
	if value is Color: return {"color": [value.r, value.g, value.b, value.a]}
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return var_to_str(encode(a)) < var_to_str(encode(b)))
		var result: Array = []
		for key in keys: result.append([encode(key), encode(value[key])])
		return {"dictionary": result}
	if value is Array or value is PackedVector3Array:
		var result: Array = []
		for item in value: result.append(encode(item))
		return result
	if value is Object:
		if value.has_method("diagnostic_state"): return encode(value.diagnostic_state())
		var result: Dictionary = {}
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: result[property.name] = encode(value.get(property.name))
		return result
	if value is float and not is_finite(value): return str(value)
	return value

static func actor_state(actor: SimEntity) -> Dictionary:
	var result: Dictionary = {}
	for property in actor.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE: result[property.name] = encode(actor.get(property.name))
	return result

static func decode(value):
	if value is Dictionary:
		if value.has("v3"): return Vector3(value.v3[0], value.v3[1], value.v3[2])
		if value.has("v2i"): return Vector2i(value.v2i[0], value.v2i[1])
		if value.has("dictionary"):
			var result: Dictionary = {}
			for pair in value.dictionary: result[decode(pair[0])] = decode(pair[1])
			return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(decode(item))
		return result
	return value
