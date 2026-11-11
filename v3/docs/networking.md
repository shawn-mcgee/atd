# Player-hosted networking

The game uses Godot **WebRTCMultiplayerPeer** in both browser builds and the native Windows/Linux x86_64 editor/runtime. It no longer depends on Trystero, Nostr, or browser JavaScript for networking. Native runtime support does not add downloadable desktop exports to the release workflow.

## Coordinator and ICE setup

`config/networking.json` points to Shawn's Cloudflare Worker coordinator at `wss://webrtc-coordinator.s-mcgeek07.workers.dev`. Its Metered STUN/TURN configuration was adapted from [multiplayer-experiment/game2.gd](https://github.com/shawn-mcgee/multiplayer-experiment/blob/ec8a6ee175df1f16e529cd0d21302c8e5e708a19/game2.gd). The pinned reference commit is `ec8a6ee175df1f16e529cd0d21302c8e5e708a19`. TURN credentials are client-consumed settings, matching the experiment; they are not coordinator administration keys. Update or rotate them in the JSON when the subscription changes. Do not put administrative provider secrets in the client.

Room setup is asynchronous. Host opens `/host`; guests open `/join/<room_id>`. Coordinator responses use `v1-host-room` and `v1-join-room`, with `ok`, `room_id`, `host_id`, and a guest `peer_id`. Guests initiate `v1-webrtc-offer`; hosts answer with `v1-webrtc-answer`. `v1-webrtc-ice-candidate` carries `media`, `index`, and `name`. Signaling forwards `from_id` and `to_id`; ICE received before the remote description is buffered within bounded per-peer limits.

The coordinator assigns signaling IDs. Godot's built-in server ID remains **1**, so the session maps that ID to the coordinator's host ID for signaling only. Guest IDs remain their coordinator-assigned IDs. Displayed invitations contain only `room_id`, with host identity resolved by the coordinator. Older `room_id:coordinator_host_id` invitations remain accepted for compatibility. Old Trystero invitations are incompatible. The game protocol is now version 3.

Host/Join work directly when running `project.godot`, as well as in the exported web game. Native WebRTC comes from the Windows/Linux x86_64 GDExtension in `addons/webrtc_native/`, copied with license notices and provenance from the reference repository. The bundled libjuice backend supports UDP TURN only; native clients omit the unsupported TCP/TLS ICE entries. Browsers retain UDP, TCP and TLS endpoints. UDP-blocked native networks need a different native WebRTC backend. The extension is non-reloadable to avoid Windows editor shadow-library locking and is excluded from browser exports, which use Godot's built-in browser WebRTC implementation. Restart an already-running editor if it has not registered the newly installed extension.

## Transport and performance

`NetworkSession` uses `WebSocketPeer` for coordinator signaling, `WebRTCPeerConnection` for negotiation, and **WebRTCMultiplayerPeer** for channel creation, peer events, sender identity and packet delivery. The browser JavaScript bridge is limited to diagnostics and test input. No gameplay packets cross JavaScriptBridge.

Packets use Godot's binary Variant encoding with object decoding disabled. Payloads at least 1,024 bytes are Zstandard-compressed. Commands use the default reliable channel, snapshots use a separate reliable channel, and heartbeats have their own reliable channel. This avoids sharing one reliable stream for all three workloads. Snapshots waiting to send are coalesced per recipient; commands use a bounded FIFO.

Godot reports a 1,200-byte WebRTC packet limit, so larger encoded payloads use a 16-byte framing header and 1,184-byte payload chunks under that engine limit. Receivers check serial, contiguous offsets and declared size before reassembly, with a 4 MiB ceiling and bounded decompression. Objects cannot be instantiated through decoded packets. This small framing layer preserves native peer/channel handling while supporting existing large terrain snapshots.

The `limits` configuration defines maximum peers (4 guests), frame payload bytes (1,184), packet bytes (4,194,304), buffered bytes (262,144), send timeout (10,000 ms), receive frames per poll (256), send frames per channel per poll (16), compression threshold (1,024 bytes), and command queue length (256). `signaling.connectTimeoutMs` is 20,000. These are transport limits, separate from gameplay balance. Full snapshot generation still needs measurement before claiming a late-game bandwidth/frame-time target is met.

## Authority and lifecycle

The hosting player runs WorldState and Lightless simulation. Guests send orders and display host-filtered state. Ownership, payload, build/protocol, gameplay configuration, match identity and command sequencing checks remain in the game. Transport connection alone does not admit a player to a match. Up to five players can participate; the host may assign one existing slot to Lightless before launch. That peer is authoritatively mapped to owner `-1`; all others remain Commonwealth. Guests receive the same role assignment at startup and filtered role-specific snapshots. With no assigned player, the Lightless use the CPU. A departing Lightless guest returns the colony to CPU control; host loss remains terminal. Late join is rejected after launch.

Host loss ends every guest's match without migration, retries or resumption. Host gameplay elimination is independent of hosting while still connected. A departing guest is eliminated while retaining surviving assets and orders; vehicles unload under the existing rules. Signals, connections, pending packets, ICE and deadlines are cleared on leaving a session.

`liveness.heartbeatIntervalMs` (1,000) and `liveness.peerTimeoutMs` (10,000) use monotonic real time, independently of simulation pause and speed. Any incoming peer traffic refreshes liveness. Missing peers expire once; stale traffic cannot reopen an ended match. If coordinator signaling closes after setup, existing WebRTC connections continue; the lobby reports that new invitations require reopening the room.

## Local verification

`npm run serve` and `npm run serve:site` start a protocol-compatible local coordinator on port 8081. Use `?coordinator=ws://127.0.0.1:8081` in browser tests. The old `relay` query name remains a development alias. Local overrides disable paid ICE servers for localhost testing; normal sessions use the configured coordinator and Metered servers. `?relayOnly=1` filters signaling to relay candidates for an explicit subscription check.

`npm test` includes five real headless native Godot peers using this coordinator, large mixed binary packets, compression/reassembly, guest-to-host commands, guest departure and terminal host loss. Browser integration tests verify the exported game, cross-origin clients and host-confirmed movement. These checks do not establish universal Internet reachability; different-network, restrictive-network, hosted Pages/itch.io and full five-player gameplay acceptance remain separate tests.

The earlier [multiplayer options research](multiplayer-options.md) is historical. This custom coordinator/Metered integration supersedes its proposed Cloudflare TURN migration.

Verified in this workspace: five native peers with the local coordinator, mixed binary payloads larger than one frame, and terminal host loss; two native peers against the live Worker with relay-only ICE and the configured Metered subscription. Native-to-browser admission and browser-host loss also passed against the local coordinator, along with the exported browser host-confirmed movement test. Different-device/network coverage remains unverified.
