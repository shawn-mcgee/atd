- [x] The game needs a tutorial that isn't strictly labelled as such. Add singleplayer missions that a player can complete to learn basic and advanced mechanics. These missions should not require unlocking and can be selected at any time from the mission menu. Pick which missions to implement and don't create missions focused around a single mechanic, instead group together multiple related mechanics.

- [x] The view is too dark. It is difficult to view what is in the fog of war at times.

- [x] Fix the bugs around building and construction. A unit pathing through a blueprint causes the blueprint to be deleted without refunding it, there are other conditions that will cancel a blueprint without refunding it.

- [x] Multiplayer is a huge issue currently, this needs some serious research and recommendation for how to pursue higher quality p2p hosting for very low cost (ideally free). Thinking about Epic Online Services, or maybe other hosts that offer a free tier.

Completed 2026-11-10:

- Added three always-available missions: First foothold, Supply and steel, and The last light. [Details](v3/docs/missions.md). Automated command-driven playthroughs pass; Shawn also played and successfully completed all three missions.
- Brightened explored terrain, resource silhouettes and remembered structures; reduced fog opacity while retaining hidden-enemy rules.
- Replaced automatic construction cancellation with waiting/retrying. Passing units keep their orders; explicit cancellation refunds unstarted sites exactly once. Construction already worked on and combat destruction retain their documented resource loss.
- Researched browser-compatible multiplayer options, including EOS, Cloudflare, Metered and Photon. [Recommendation and implementation plan](v3/docs/multiplayer-options.md): prototype managed TURN with expiring credentials, then measure signaling, bandwidth and host performance. Provider integration/deployment remains future work.

Multiplayer follow-up: integrated the custom Cloudflare coordinator and Metered ICE subscription from multiplayer-experiment using Godot WebRTCMultiplayerPeer. Networking now works in the native editor/runtime as well as browser builds. Five native peers and live relay-only TURN checks passed. [Current setup](v3/docs/networking.md).
