# Completed gameplay requests

- [x] Expeditions: deliver mineral and gas cargo independently, skip full storage while delivering the other type, then unload safely at HQ if the expedition resource is full. Retain undeliverable cargo.
- [x] Gates: friendly units open powered, unlocked gates when approaching along their path. Automatically opened gates close after traffic clears; manually open gates remain open. K toggles the lock.
- [x] Performance: replace whole-map navigation rebuilds with local updates, avoid unrelated unit/creature replanning, and look up wall neighbors by hex cell. Eight-blueprint benchmark improved from roughly 480 ms to 1–4 ms per placement on this machine.
- [x] Command Center: queue engineers using the production button or 1, alongside scanning; normal cost, production time, cancellation refunds and queue limits apply.

Validation: `test-todo-features.gd`, `test-expedition-delivery.gd`, existing gameplay suites, and `profile-placement.gd` (use `-- --complete` to measure completed walls).
