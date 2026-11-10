# Low-cost browser multiplayer recommendation

Historical research: the game now uses Shawn's custom coordinator and Metered TURN through Godot WebRTCMultiplayerPeer. See [current networking](networking.md). The proposal below is retained as research, not the active implementation.

Research checked 2026-11-10. This is a recommendation and implementation plan, not a deployed service or a claim of Internet connectivity. The current alpha must run in a browser on Pages/itch.io; native exports remain deferred.

## Recommendation

Keep the host-authoritative WorldState and browser WebRTC adapter. First prototype **Cloudflare Realtime TURN**, with short-lived credentials issued by a small backend, and retain Trystero for signaling during that experiment. Then replace dependence on public Nostr discovery with a controlled HTTPS/WSS room service if measured discovery failures warrant it. These are separate jobs: signaling introduces peers; TURN relays their WebRTC traffic when direct paths fail; neither runs the simulation.

Cloudflare currently offers **1,000 GB/month shared across TURN and SFU**, then **$0.05/GB egress**. Other Cloudflare products, including the credential endpoint's hosting, have separate pricing. This is the best apparent fit for a small browser alpha because the existing adapter can consume TURN ICE servers without a gameplay rewrite. It is an engineering recommendation inferred from the current architecture and the provider's documented interfaces, not a performance benchmark. [Cloudflare pricing](https://developers.cloudflare.com/realtime/sfu/platform/pricing/), [TURN service](https://developers.cloudflare.com/realtime/turn/).

## Alternatives

| Option | Current free offering / cost | Fit for this project |
| --- | --- | --- |
| Existing Trystero + public Nostr | No custom signaling host; no configured TURN | Keep as an experimental path. Public discovery and NAT traversal have separate failure modes. Local tests do not validate either on the Internet. |
| Cloudflare Realtime TURN | Shared 1,000 GB/month, then $0.05/GB egress | Preferred connectivity experiment. Standard WebRTC ICE support; needs a protected credential backend and usage controls. |
| Epic Online Services | Epic describes EOS as free | Candidate for a later native build. Epic's listed SDK platforms are PC, consoles and mobile; a browser P2P SDK is not documented in those sources. Do not plan a browser migration without a supported SDK and a successful exported-browser proof. EOS is not a generic TURN endpoint that can simply be inserted into Trystero. |
| Metered TURN / Open Relay | Main TURN pricing lists 500 MB/month free trial; 150 GB costs $99/month | Standards-based alternative for a comparison test. Open Relay separately advertises 20 GB/month; resolve that discrepancy with the provider before budgeting or relying on that allowance. |
| Photon Realtime | 20 CCU free for development/non-commercial use | Has a JavaScript client, but requires a new room/transport adapter. Check commercial terms and traffic allowances. The advertised free 100 CCU applies to Fusion/Quantum, not a blanket allowance for this Godot JavaScript integration. |
| Self-hosted coturn + WSS signaling | Software is free; compute, bandwidth and operations are not | More control, but requires a public server, TLS, credential rotation, abuse prevention and maintenance. Static Pages hosting alone cannot run either service. Consider only if existing infrastructure makes operations cheap. |

Sources: [Epic service description](https://www.epicgames.com/help/c-32735058/c-36403860/a14234863?lang=en-US), [Epic SDK platform reference](https://dev.epicgames.com/docs/epic-online-services/eos-get-started/eos-get-started-reference), [Epic P2P interface](https://dev.epicgames.com/docs/epic-online-services/multiplayer/nat-p2p-interface), [Metered pricing](https://www.metered.ca/stun-turn), [Open Relay offer](https://www.metered.ca/tools/openrelay/), [Photon plan terms](https://doc.photonengine.com/photon/current/pricing), [Photon JavaScript API](https://doc-api.photonengine.com/en/javascript/current/), [coturn project](https://github.com/coturn/coturn).

## Why transport alone will not fix multiplayer quality

The repository currently sends a full filtered snapshot about ten times a second to each guest. `WorldState.snapshot` includes all explored terrain cells as well as allowed entity state. The bridge encodes JSON into bytes; this is not a compact binary state schema. Commands and state share an action, and a large state send can still delay a later command even though unsent snapshots are coalesced. The logical host fan-out reaches four recipients in a five-player match. TURN improves reachability; it does not remove host upload, serialization, browser main-thread stalls, reliable-channel blocking, or an abusive host's authority.

Before changing services, collect connection success/failure by stage, time to first peer and admitted lobby, selected ICE candidate type, RTT, snapshot bytes per recipient, queue delay/age, host simulation time, and background-tab behavior. Record diagnostics without collecting credentials or IP addresses in public logs. Distinguish discovery failure, ICE failure, protocol rejection, liveness expiry and slow rendering in the lobby message.

## Concrete next implementation

1. Add a credential endpoint that keeps the provider TURN key in a server secret. Issue expiring credentials per admitted room participant, with rate limits and a bounded lifetime long enough for a match. Allow only the actual Pages/itch.io origins and apply admission checks; CORS alone is not authentication. Keep all long-lived secrets out of `config/networking.json`, exported files and invitations. [Cloudflare credential API and lifetime guidance](https://developers.cloudflare.com/realtime/turn/generate-credentials/).
2. Fetch ICE configuration before starting the browser room. Handle issuance errors and expiry explicitly. The current `start` bridge is synchronous and only accepts static `ice.turnServers`; a real integration needs asynchronous preparation. Keep static/local configuration for development. Verify pinned Trystero's TURN mapping and forced-relay behavior using an exported build.
3. Add an explicit connecting deadline and actionable room errors. Introduce a controlled signaling endpoint only after measuring Nostr failure rates; configure it for HTTPS/WSS public hosting, capacity limits and expiring rooms. Preserve invitation host identity, protocol/hash admission, command ownership/sequence checks and terminal host loss.
4. Measure state size before optimizing. Send terrain discoveries/changes incrementally; use periodic full baselines and bounded state ages. Consider independent command/state channels and compact payloads with explicit versioning, while preserving visibility filtering and recovery from skipped updates. Verify host command latency under large state sends.
5. Run the matrix below before declaring a provider selected. No account, billing plan, backend or provider deployment was created by this research.

## Verification and cost gate

Test actual Pages root and `/v3/`, itch.io's embedded frame, separate home networks, mobile hotspot, restrictive/corporate networks, and UDP-blocked TCP/TLS fallback. Include 2-player and 5-player matches; direct ICE and forced TURN; long matches; paused simulation; backgrounded host/guest; packet delay/loss; explicit leave and heartbeat timeout; eliminated host staying connected. Measure p50/p95 order-to-confirmation latency and host tick cost under a representative late-game army. Preserve end-on-host-loss and elimination-on-guest-loss policies. Record failures as well as successful connections.

Set a test acceptance target before measuring: at least 95% successful joins within 15 seconds across the chosen network matrix, no unexplained command loss/duplicates, and p95 command-to-confirmation below 250 ms on same-region test peers under the representative army. These are proposed product targets, not measured results or provider guarantees. Treat impossible network policies as explicit failures with a helpful message.

Budget from measured **provider-billed egress**, not player count alone. As an illustrative assumption, 50 kB/s of state per guest with four guests is about 0.72 GB per match-hour of host-to-guest payload when every path is relayed. At that assumed rate 1,000 GB corresponds to roughly 1,389 match-hours before overhead, return commands and other shared usage. At 1 MB/s per guest the same session costs about 14.4 GB/hour. These are decimal payload estimates, not measured traffic. Track actual billed bytes, set alerts below the allowance, bound credential issuance, and decide whether to reject relay-required joins when the project budget is exhausted. A free allowance is not an automatic spending cap or an availability guarantee.
