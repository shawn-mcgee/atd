import {test} from 'node:test'
import assert from 'node:assert/strict'
import {spawn} from 'node:child_process'
import {once} from 'node:events'
import {readFileSync} from 'node:fs'
import path from 'node:path'
import {createCoordinatorServer} from '../tools/coordinator-server.mjs'

test('five native Godot peers use the coordinator, binary transport and terminal host loss', async()=>{
  const server=createCoordinatorServer({port:0})
  await once(server,'listening')
  const version=readFileSync('.godot-version','utf8').trim()
  const binary=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
  const child=spawn(binary,['--headless','--path','.', '--script','tests/network_native.gd','--',`--coordinator=ws://127.0.0.1:${server.address().port}`])
  let output=''
  child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>{output+=b;if(output.includes('SCRIPT ERROR:'))child.kill()})
  const timer=setTimeout(()=>child.kill(),45000)
  try {
    const [code]=await once(child,'exit')
    assert.equal(code,0,output.slice(0,12000))
    assert.doesNotMatch(output,/SCRIPT ERROR:|^ERROR:/m)
    assert.match(output,/failures: 0/)
  } finally {
    clearTimeout(timer)
    for(const socket of server.clients)socket.terminate()
    await new Promise(resolve=>server.close(resolve))
  }
})
