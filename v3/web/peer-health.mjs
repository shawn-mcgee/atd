// Transport liveness uses monotonic real time, independent of simulation pause/speed.
export class PeerHealth {
  constructor(timeoutMs, onTimeout, now = () => performance.now()) {
    this.timeoutMs = timeoutMs
    this.onTimeout = onTimeout
    this.now = now
    this.seen = new Map()
  }
  observe(peer) { this.seen.set(peer, this.now()) }
  forget(peer) { this.seen.delete(peer) }
  clear() { this.seen.clear() }
  check() {
    const now = this.now()
    for (const [peer, lastSeen] of this.seen) {
      if (now - lastSeen < this.timeoutMs) continue
      this.seen.delete(peer)
      this.onTimeout(peer)
    }
  }
}
