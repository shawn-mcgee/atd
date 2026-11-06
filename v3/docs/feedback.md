# Combat and work feedback

The feedback pass adds weapon-specific tracers and muzzle flashes, local recoil, short hit overlays, shield ripples, fragments, collapsing/sinking destruction, health-bar damage trails, grouped damage labels, delivery/ready cues, and additional original audio. It does not change weapon damage, attack eligibility, armor, resource yields, or firing restrictions.

## Events are the contract

`WorldState.emit_feedback(kind, at, payload, audience)` records a bounded presentation event with a monotonic serial and simulation tick. The renderer, tactical overlay and audio each keep an independent cursor and use `feedback_for(owner, after)`.

| Event | Authoritative trigger | Important payload |
| --- | --- | --- |
| `fire` | An attack passes targeting, obstruction and cooldown checks | `from`, `to`, muzzle `height`, `weapon`, visible source `attacker` |
| `hit` | Damage resolution, including a zero-damage armor block | `target`, actual `amount`, `shielded`, `biological` |
| `destroy` | Entity destruction, before removal | `target`, `owner`, `biological` |
| `ready` | Construction, Operator/vehicle production, or kit assembly finishes | `owner`, `target`, `label` |
| `deposit` | Cargo is actually accepted into global supply | `owner`, destination `target`, accepted `amount` |

A full Depot creates no delivery cue for resources it could not accept. A zero-damage attack shows ARMOR rather than inventing damage. Rampart flashes represent the existing flat armor bonus; they do not add a shield-health pool. Flame visuals use the weapon's range/cone and expire quickly; they do not create persistent damaging fire.

Audience eligibility is captured at event time. Hit/death events do not reveal concealed enemy identity or health. A visible Scout represents its firing passenger as the visible source vehicle. Snapshots serialize only the viewer's eligible events and omit the audience list. Vector positions round-trip explicitly through JSON.

The bounded history survives skipped render frames and coalesced snapshots. Consumers deduplicate serials. Events older than `maxCatchupTicks` are discarded during playback, preventing an old barrage from replaying after a long stall. Newly consumed short effects get at least one presentation frame. This is bounded catch-up, not an unbounded replay queue.

The renderer requires a destruction event before playing a death animation. A snapshot removing a unit because it left vision simply hides/removes its model. Feedback consumers may animate scene nodes and play sound, but must never mutate authoritative positions, HP, orders, or inventories.

## Tuning

All primary defaults appear in [the configuration reference](config-reference.md). In `config/prototype.json`:

- `presentation.feedback.weaponProfiles` maps a weapon ID to an effect profile. Supported visual families are rifle, heavy, laser, flame and melee.
- `profiles` controls lifetime, width, recoil, impact particle count, sound, gain and per-source sound interval. A new weapon without an explicit mapping uses the rifle profile.
- `muzzleHeights` aligns presentation with each known source model; target height stays generic so an unidentified radar target does not need type metadata.
- `creatureScales` differentiates Lightless silhouettes. These are art scales; collision radii remain in `units`. Keep the two consistent when changing proportions.
- `hitFlashesEnabled`, flash duration/gap, health-trail duration, label lifetime and damage-number grouping window control readability. `presentation.damageNumbers` can disable damage labels independently.
- Trace, ring, label, particle, voice and event-history limits bound presentation work. Catch-up uses simulation ticks. Audio throttles and visible fade use presentation time.

Rifle/laser profiles have different ribbons and recoil; flame geometry uses the real attack cone. Impact overlays are spaced so rapid flame ticks do not leave an enemy permanently white. Nearby hits group for a bounded interval rather than accumulating one endless damage total. Deposits arriving together can share a delivered-total label. There is no camera shake.

## Machinery and occupants

Factory gantries move only during powered, active vehicle assembly. Extractor drills stop when production is blocked or idle. A driven Excavator rotates its bit during cliff clearing. Fuelled generators have rotating machinery. Gates keep their frames while retracting the central panel, using opening progress where available.

An occupied Scout displays a seated passenger; armed passengers display/aim a weapon. This is a visual part of the vehicle, not a separately targetable actor. The established Scout stance, vision and firing-while-moving rules still apply.

Unpowered friendly structures have local warning marks; selected uncrewed vehicles explain that a driver is required. Health bars retain a short pale trail behind lost health, while selection/inspection uses actual HP.

## Audio assets and review

`tools/generate-feedback-audio.py` generates the original cannon, flame, shield, collapse and deposit WAVs using deterministic synthesis. No external recordings are used. Existing rifle, laser, UI, work and ambience clips remain. New custom profile sounds can be added as WAVs under `assets/audio/` and referenced by basename; the audio layer caches them. Configuration validation checks that profile audio resources exist.

Run the pinned Godot executable with `--path . --script tools/preview-vehicles.gd -- --combat` to stage actual attacks and shielded damage. It writes `build/visual-review/combat-feedback.png`. The fixture is excluded from editor scanning and browser exports; it is not a normal-game cheat or an end-to-end match test.

Headless checks cover retention, cursors, privacy, JSON round trips, bounds, model hit flashes, health trails, bounded number grouping, and fog disappearance. The browser suite issues a legal friendly-fire command to exercise actual fire/hit feedback in the exported renderer. Recheck the running scene and sound after tuning; passing tests alone does not establish game feel.
