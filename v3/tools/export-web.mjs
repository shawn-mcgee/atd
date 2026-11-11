import './build-bridge.mjs'
import {checkProject} from './project.mjs'
checkProject()
import {spawnSync} from 'node:child_process'
import {readFile,writeFile} from 'node:fs/promises'
import path from 'node:path'
const version=(await readFile('.godot-version','utf8')).trim()
const editor=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
for (const args of [['--headless','--path','.', '--editor','--recovery-mode','--import','--quit'],['--headless','--path','.', '--recovery-mode','--export-release','Web','build/web/index.html']]) {
  const result=spawnSync(editor,args,{encoding:'utf8'})
  process.stdout.write(result.stdout || '')
  process.stderr.write(result.stderr || '')
  if (result.status!==0 || /SCRIPT ERROR:|^ERROR:/m.test((result.stdout || '')+(result.stderr || ''))) process.exit(result.status || 1)
}
const entry='build/web/index.html'
let html=await readFile(entry,'utf8')
html=html.replace('</head>','<script src="bridge.js"></script>\n</head>')
await writeFile(entry,html)
await writeFile('build/web/network-test.html','<!doctype html><title>ATD transport test</title><script src="bridge.js"></script>')
console.log('Browser export ready in build/web. Run npm run serve.')
