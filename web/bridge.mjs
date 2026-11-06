import {joinRoom as joinNostr, selfId} from 'trystero'
import {joinRoom as joinLocal} from '@trystero-p2p/ws-relay'

// The browser transport never owns simulation state. Godot polls queued events.
export function createBridge() {
  let room = null
  let action = null
  let hostId = ''
  let mode = ''
  let active = false
  let events = []
  let outbound = []
  let snapshots = new Map()
  let sending = false
  const parameters = new URLSearchParams(location.search)
  const emit = event => events.push(event)
  async function drain() {
    if (sending) return
    sending = true
    try {
      while (active && action && (outbound.length || snapshots.size)) {
        let packet = outbound.shift()
        if (!packet) {
          const [key, value] = snapshots.entries().next().value
          snapshots.delete(key)
          packet = value
        }
        const current = action
        await current.send(new TextEncoder().encode(packet.value), packet.peer ? {target: packet.peer} : {})
      }
    } catch (error) { emit({type: 'error', message: String(error)}) }
    finally { sending = false }
  }
  const api = {
    diagnostics: {},
    start(role, invite, configuration) {
      api.leave()
      const config = JSON.parse(configuration)
      mode = role
      const roomId = role === 'host' ? crypto.randomUUID() : invite.split(':')[0]
      hostId = role === 'host' ? selfId : invite.split(':')[1]
      if (!roomId || !hostId) return JSON.stringify({error: 'Paste the complete room invitation'})
      const localRelay = parameters.get('relay')
      const join = localRelay ? joinLocal : joinNostr
      const options = {appId: config.applicationId, ...(localRelay ? {relayConfig: {urls: [localRelay]}, rtcConfig: {iceServers: []}} : {})}
      if (config.ice?.turnServers?.length) options.turnConfig = config.ice.turnServers
      active = true
      try {
        room = join(options, roomId, {onJoinError: error => emit({type: 'error', message: String(error.error || error)})})
      } catch (error) {
        api.leave()
        return JSON.stringify({error: String(error)})
      }
      action = room.makeAction('atd-packet-v1')
      action.onReceive = ({byteLength}) => byteLength <= 4 * 1024 * 1024
      action.onMessage = (payload, {peerId}) => {
        if (!active) return
        try {
          const message = typeof payload === 'string' ? JSON.parse(payload) : JSON.parse(new TextDecoder().decode(payload))
          emit({type: 'packet', peer: peerId, message})
        } catch { emit({type: 'error', message: 'Malformed network packet ignored'}) }
      }
      room.onPeerJoin = peer => emit({type: 'peer_join', peer})
      room.onPeerLeave = peer => {
        if (!active) return
        if (mode === 'guest' && peer === hostId) {
          // Discard even the final in-flight state: it must never reopen an ended match.
          api.leave()
          emit({type: 'host_lost'})
        } else emit({type: 'peer_leave', peer})
      }
      return JSON.stringify({self: selfId, host: hostId, invitation: `${roomId}:${hostId}`})
    },
    send(peer, packet) {
      if (!action || !active) return
      const message = {peer, value: packet}
      if (JSON.parse(packet).kind === 'state') snapshots.set(peer, message)
      else if (outbound.length < 256) outbound.push(message)
      else emit({type: 'error', message: 'Network command queue is full; order was not sent'})
      void drain()
    },
    poll() {
      const latest = new Map()
      const batch = []
      for (const event of events) {
        if (event.type === 'packet' && event.message.kind === 'state') latest.set(event.peer, event)
        else batch.push(event)
      }
      events = []
      return JSON.stringify([...batch, ...latest.values()])
    },
    leave(clearEvents = true) {
      active = false
      room?.leave()
      room = null
      action = null
      outbound = []
      snapshots.clear()
      if (clearEvents) events = []
    },
    inspect() { return api.diagnostics },
    updateDiagnostics(value) { api.diagnostics = JSON.parse(value) },
    test(command, value = '') {
      if (!parameters.has('test')) throw new Error('Test controls are disabled')
      emit({type: 'test', command, value})
    },
    binaryProbe(peer, text) { api.send(peer, JSON.stringify({kind: 'probe', bytes: [...new TextEncoder().encode(text)]})) }
  }
  addEventListener('pagehide', () => api.leave(false))
  return api
}

window.ATDNetwork = createBridge()
