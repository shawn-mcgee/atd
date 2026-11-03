extends RefCounted
## Scene-free capability state. The simulation coordinator supplies fixed ticks.
## Enabled capabilities come from content; no component runs its own process loop.

class Motion:
	extends RefCounted
	var enabled := false
	var velocity: Array = [0, 0, 0]
	var facing: Array = [0, 0, -1024]
	var navigation: Dictionary = {}
	var avoidance: Dictionary = {}

class Combat:
	extends RefCounted
	var enabled := false
	var ready_tick := 0

class Production:
	extends RefCounted
	var enabled := false
	var queue: Array = []
	var spawn_source := 0
	var passive_started_tick := 0
	var passive_remaining := 0

class Cargo:
	extends RefCounted
	var enabled := false
	var chyme := 0
	var nacre := 0
	var next_chyme_tick := 0
	var mining_ready_tick := 0
