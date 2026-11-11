import {test} from 'node:test'
import assert from 'node:assert/strict'
import {spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
import path from 'node:path'
import {checkProject} from '../tools/project.mjs'

test('Godot simulation invariants, progression and serialization',()=>{
  const version=readFileSync('.godot-version','utf8').trim()
  const binary=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
  checkProject()
  for (const args of [['--headless','--path','.', '--editor','--recovery-mode','--import','--quit'],['--headless','--path','.', '--script','tests/simulation.gd'],['--headless','--path','.', '--script','tests/interface.gd']]) {
    const result=spawnSync(binary,args,{encoding:'utf8',timeout:90000})
    const output=result.stdout+result.stderr
    assert.equal(result.status,0,output)
    assert.doesNotMatch(output,/SCRIPT ERROR:|^ERROR:/m,output)
    if(args.includes('--script')) assert.match(output,/failures: 0/)
  }
})

test('browser alpha settings preserve confirmed constraints',()=>{
  const c=JSON.parse(readFileSync('config/prototype.json','utf8'))
  const n=JSON.parse(readFileSync('config/networking.json','utf8'))
  assert.equal(c.features.nativeDesktopExports,false)
  assert.equal(c.features.extractionBoss,false)
  assert.equal(c.match.anchorLimitPerPlayer,1)
  assert.equal(c.match.maxCommonwealthPlayers,5)
  assert.equal(n.hostLossPolicy,'end_match')
  assert.equal(n.hostRecoveryEnabled,false)
  assert.equal(n.clientDisconnectPolicy,'eliminate_keep_assets_and_orders')
  for (const name of ['operator','engineer','marine','flamer','lancer']) {
    assert.equal(c.units[name].illuminationRangeTiles,0)
    assert.equal(c.units[name].visionRangeTiles,2)
  }
})
