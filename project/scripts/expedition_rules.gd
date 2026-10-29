extends RefCounted
## Internal currency keys stay stable; UI names are Materials and Methane.
const STRUCTURES := {
	"core": {"name": "Command Center", "minerals": 0, "gas": 0, "hp": 700, "time": 0, "power": 2},
	"wall": {"name": "Wall", "minerals": 10, "gas": 0, "hp": 420, "time": 3, "power": 0},
	"platform": {"name": "Elevated Platform", "minerals": 35, "gas": 0, "hp": 380, "time": 6, "power": 0},
	"ramp": {"name": "Ramp", "minerals": 30, "gas": 0, "hp": 300, "time": 6, "power": 0},
	"gate": {"name": "Gate", "minerals": 20, "gas": 0, "hp": 340, "time": 5, "power": 1},
	"depot": {"name": "Material Depot", "minerals": 40, "gas": 0, "hp": 240, "time": 7, "power": 0},
	"gas_tank": {"name": "Methane Tank", "minerals": 40, "gas": 0, "hp": 240, "time": 7, "power": 0},
	"generator": {"name": "Generator", "minerals": 80, "gas": 25, "hp": 260, "time": 9, "power": 0},
	"repeater": {"name": "Repeater", "minerals": 15, "gas": 0, "hp": 140, "time": 4, "power": 0},
	"turret": {"name": "Turret", "minerals": 45, "gas": 0, "hp": 220, "time": 8, "power": 3},
	"floodlight": {"name": "Spotlight", "minerals": 25, "gas": 0, "hp": 160, "time": 6, "power": 2},
	"barracks": {"name": "Barracks", "minerals": 90, "gas": 0, "hp": 360, "time": 12, "power": 0},
	"garage": {"name": "Garage", "minerals": 120, "gas": 30, "hp": 440, "time": 15, "power": 0},
	"extractor": {"name": "Extractor", "minerals": 70, "gas": 10, "hp": 220, "time": 9, "power": 2},
	"beacon": {"name": "Extraction Beacon", "minerals": 0, "gas": 0, "hp": 280, "time": 12, "power": 0},
	"hive": {"name": "Lightless Hive", "minerals": 0, "gas": 0, "hp": 1600, "time": 0, "power": 0},
	"scanner": {"name": "Scanner", "minerals": 60, "gas": 20, "hp": 180, "time": 9, "power": 2}
}
const UNITS := {
	"engineer": {"name": "Engineer", "minerals": 35, "gas": 0, "hp": 80.0, "speed": 3.1, "time": 7.0, "factory": "barracks"},
	"marine": {"name": "Marine", "minerals": 45, "gas": 0, "hp": 110.0, "speed": 3.5, "time": 8.0, "factory": "barracks"},
	"flamer": {"name": "Flamer", "minerals": 65, "gas": 20, "hp": 140.0, "speed": 3.1, "time": 11.0, "factory": "barracks"},
	"scout": {"name": "Scout", "minerals": 60, "gas": 25, "hp": 150.0, "speed": 8.0, "time": 10.0, "factory": "garage"},
	"drill": {"name": "Drill", "minerals": 140, "gas": 45, "hp": 320.0, "speed": 4.5, "time": 16.0, "factory": "garage"},
	"jeep": {"name": "Jeep", "minerals": 100, "gas": 35, "hp": 260.0, "speed": 6.2, "time": 13.0, "factory": "garage"}
}
const PREDATORS := {
	"runner": {"name": "Runner", "hp": 42.0, "speed": 4.8, "retreat_speed": 6.2, "damage": 6.0, "attack_delay": 0.8, "sight": 15.0, "probe_light": 0.18},
	"stalker": {"name": "Stalker", "hp": 65.0, "speed": 3.8, "retreat_speed": 4.8, "damage": 9.0, "attack_delay": 1.1, "sight": 14.0, "probe_light": 0.24},
	"brute": {"name": "Brute", "hp": 145.0, "speed": 2.7, "retreat_speed": 3.5, "damage": 18.0, "attack_delay": 1.6, "sight": 12.0, "probe_light": 0.38}
}

static func cost(kind: String) -> Dictionary:
	var data: Dictionary = STRUCTURES[kind] if STRUCTURES.has(kind) else UNITS[kind]
	return {"minerals": data.minerals, "gas": data.gas}

static func title(kind: String) -> String:
	return STRUCTURES[kind].name if STRUCTURES.has(kind) else UNITS[kind].name
