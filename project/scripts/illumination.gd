extends RefCounted
## Authoritative visibility, shared by combat, creatures and the terrain shader.
var sources: Array[Dictionary] = []

func add_source(point: Vector3, radius: float, direction: Vector3 = Vector3.ZERO, cone_cos: float = -1.0, intensity: float = 1.0, deters: bool = true) -> void:
	sources.append({"position": point, "radius": radius, "direction": direction, "cone": cone_cos, "intensity": intensity, "deters": deters})

func sample(point: Vector3, deterrence_only: bool = false) -> float:
	var total := 0.0
	for source in sources:
		if deterrence_only and not source.deters: continue
		var offset: Vector3 = point - source.position
		offset.y = 0
		var radius: float = source.radius
		var squared := offset.length_squared()
		if squared >= radius * radius: continue
		var distance := sqrt(squared)
		var strength := 1.0 - smoothstep(radius * 0.55, radius, distance)
		if float(source.cone) > -0.5 and distance > 0.01:
			var alignment := (offset / distance).dot(source.direction)
			strength *= smoothstep(float(source.cone), float(source.cone) + 0.12, alignment)
		total += strength * float(source.intensity)
		if total >= 1.0: return 1.0
	return minf(1.0, total)

static func source_strength(point: Vector3, source: Dictionary) -> float:
	var offset: Vector3 = point - source.position
	offset.y = 0
	var radius: float = source.radius
	var squared := offset.length_squared()
	if squared >= radius * radius: return 0.0
	var distance := sqrt(squared)
	var strength := 1.0 - smoothstep(radius * 0.55, radius, distance)
	if float(source.cone) > -0.5 and distance > 0.01:
		var alignment := (offset / distance).dot(source.direction)
		strength *= smoothstep(float(source.cone), float(source.cone) + 0.12, alignment)
	return strength * float(source.intensity)

func deterrence(point: Vector3) -> float:
	return sample(point, true)
