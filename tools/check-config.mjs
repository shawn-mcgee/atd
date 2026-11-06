import {spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
import path from 'node:path'
import {checkProject} from './project.mjs'
checkProject()
const version=readFileSync('.godot-version','utf8').trim()
const binary=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
const p=spawnSync(binary,['--headless','--path','.', '--script','tests/simulation.gd','--','--config-only'],{encoding:'utf8',windowsHide:true,timeout:30000})
process.stdout.write(p.stdout || '');process.stderr.write(p.stderr || '')
if(p.error) throw p.error
if(p.status!==0 || /SCRIPT ERROR:|^ERROR:/m.test((p.stdout || '')+(p.stderr || ''))) process.exit(p.status || 1)
