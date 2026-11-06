extends RefCounted
const NeutralStance = preload("res://core/neutral_stance.gd")
## Stable wire/checkpoint data, expanding compact runtime values into plain data.

static func normalize(value):
	if value is NeutralStance: return value.checkpoint().duplicate(true)
	if value is Vector3i: return [value.x, value.y, value.z]
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			result[str(key)] = normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize(item))
		return result
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value

static func text(value) -> String:
	return JSON.stringify(normalize(value), "", true, true)

static func hash_of(value) -> String:
	return text(value).sha256_text()
