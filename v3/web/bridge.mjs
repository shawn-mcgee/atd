// Browser diagnostics/input only. Godot owns signaling, WebRTC and packets.
const parameters = new URLSearchParams(location.search)
let events = []
window.ATDNetwork = {
  diagnosticsEnabled: parameters.has('test') || parameters.has('diagnostics'),
  diagnostics: {},
  options() { return JSON.stringify({coordinator: parameters.get('coordinator') || parameters.get('relay') || '', relayOnly: parameters.get('relayOnly') === '1'}) },
  poll() { const batch = events; events = []; return JSON.stringify(batch) },
  updateDiagnostics(value) { this.diagnostics = JSON.parse(value) },
  inspect() { return this.diagnostics },
  test(command, value = '') {
    if (!parameters.has('test')) throw new Error('Test controls are disabled')
    events.push({type: 'test', command, value})
  }
}
