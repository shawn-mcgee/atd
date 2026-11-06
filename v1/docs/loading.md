# Loading and mission startup

The project main scene is `scenes/loading.tscn`. Its small console UI renders before heavy requests begin, matching the existing RTS theme without additional art.

`view/loading.gd` loads the game scene's scripts on the main thread after the console appears, then requests atlas textures through ResourceLoader's threaded API (background script compilation leaks script-default RefCounted objects in this Godot build). It retains loaded resources until the game owns them, then generates a scene-free Simulation on a dedicated Thread. The worker owns that core exclusively; no UI or scene nodes are touched there. After joining, the loader injects the prepared core into `view/game.gd` before `_ready`, preventing duplicate generation. The overlay remains through the first terrain/light frames, then opens the existing briefing. Both restart buttons return through the loading scene. `--seed=N` works as before.

Resource progress reflects completed loading requests. World generation uses an indeterminate indicator rather than invented percentages. Failures show a retry control. Closing during generation joins/disposes the worker. Single-threaded web exports show the console before synchronous generation; animation can pause during that stage because those builds cannot use a worker.

Running `top_down.tscn` directly still initializes synchronously for development, previews and existing tests. F5/project launch uses the loading screen. No simulation rules or fixed ticks change.

Validate with `--name loading --name top-down --name sprites`. The loading test checks that the console precedes world initialization, frames continue during generation, the prepared game starts at briefing/tick zero, and its state hash matches synchronous initialization with the same seed.
