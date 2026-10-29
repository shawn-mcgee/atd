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
		var distance := offset.length()
		if distance >= float(source.radius): continue
		var strength := 1.0 - smoothstep(float(source.radius) * 0.55, float(source.radius), distance)
		if float(source.cone) > -0.5 and distance > 0.01:
			var alignment := offset.normalized().dot(source.direction)
			strength *= smoothstep(float(source.cone), float(source.cone) + 0.12, alignment)
		total += strength * float(source.intensity)
	return minf(1.0, total)

func deterrence(point: Vector3) -> float:
	return sample(point, true)
