import {test} from 'node:test'
import assert from 'node:assert/strict'
import {PeerHealth} from '../web/peer-health.mjs'

test('silent peers expire once; traffic refreshes their independent deadlines', () => {
  let now = 0
  const lost = []
  const health = new PeerHealth(10000, peer => lost.push(peer), () => now)
  health.observe('host')
  health.observe('guest')
  now = 9000
  health.observe('host')
  now = 10000
  health.check()
  health.check()
  assert.deepEqual(lost, ['guest'])
  now = 19000
  health.check()
  assert.deepEqual(lost, ['guest', 'host'])
})

test('explicit departure and session cleanup remove pending timeouts', () => {
  let now = 0
  const health = new PeerHealth(10000, () => assert.fail('stale timeout'), () => now)
  health.observe('departed')
  health.forget('departed')
  health.observe('previous-session')
  health.clear()
  now = 20000
  health.check()
})
