extends RefCounted
## Immutable runtime default. Public checkpoints always contain ordinary data.
const mode := "neutral"
const network := 0
const order := 0
const target := []
const expires := 0
const CHECKPOINT := {"mode": "neutral", "network": 0, "order": 0, "target": [], "expires": 0}

func checkpoint() -> Dictionary:
	return CHECKPOINT
