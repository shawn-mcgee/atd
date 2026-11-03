extends RefCounted
const Actor = preload("res://core/actor.gd")
## Stable wire/checkpoint representation. Gameplay stores only integer scalar state.

static func normalize(value):
	if value is Actor: return normalize(value.to_dict())
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
