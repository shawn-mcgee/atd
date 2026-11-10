// Local test implementation of the custom coordinator's /host and /join routes.
import {WebSocketServer, WebSocket} from 'ws'
import {randomUUID} from 'node:crypto'

export function createCoordinatorServer({port, host = '127.0.0.1'}) {
  const server = new WebSocketServer({port, host, maxPayload: 1024 * 1024})
  const rooms = new Map(), peers = new Map()
  let serial = 0
  const send = (socket, value) => { if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value)) }
  server.on('connection', (socket, request) => {
    const path = new URL(request.url, 'http://localhost').pathname
    const id = ++serial
    let room
    if (path === '/host') {
      room = {id: randomUUID(), host: id, members: new Set([id])}
      rooms.set(room.id, room)
      send(socket, {is: 'v1-host-room', ok: true, room_id: room.id, host_id: id})
    } else if (path.startsWith('/join/')) {
      room = rooms.get(decodeURIComponent(path.slice(6)))
      if (!room || room.members.size >= 5) {
        send(socket, {is: 'v1-join-room', ok: false, error: room ? 'Room is full' : 'Room does not exist'})
        socket.close(); return
      }
      room.members.add(id)
      send(socket, {is: 'v1-join-room', ok: true, room_id: room.id, host_id: room.host, peer_id: id})
    } else { socket.close(1008, 'Unknown coordinator route'); return }
    peers.set(id, {socket, room})
    socket.on('message', raw => {
      try {
        const message = JSON.parse(raw)
        if (!['v1-webrtc-offer', 'v1-webrtc-answer', 'v1-webrtc-ice-candidate'].includes(message.is)) return
        const target = peers.get(message.to_id)
        if (!target || target.room !== room || (id !== room.host && message.to_id !== room.host)) return
        send(target.socket, {...message, from_id: id})
      } catch { socket.close(1007, 'Malformed signaling message') }
    })
    socket.on('close', () => {
      peers.delete(id); room.members.delete(id)
      if (id === room.host) {
        rooms.delete(room.id)
        for (const peerId of room.members) peers.get(peerId)?.socket.close(1001, 'Host left')
      }
    })
    socket.on('error', () => {})
  })
  return server
}
