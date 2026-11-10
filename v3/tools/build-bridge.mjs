import {build} from 'esbuild'
import {mkdir, writeFile, readFile, readdir} from 'node:fs/promises'
import path from 'node:path'
await mkdir('build/web', {recursive: true})
await mkdir('.tools', {recursive: true})
await writeFile('node_modules/.gdignore', '')
await writeFile('.tools/.gdignore', '')
const result=await build({entryPoints:['web/bridge.mjs'],bundle:true,format:'iife',target:'es2022',outfile:'build/web/bridge.js',sourcemap:true,minify:true,metafile:true})
const roots=new Set()
for(const input of Object.keys(result.metafile.inputs)){
  if(!input.startsWith('node_modules/')) continue
  let directory=path.dirname(input)
  while(directory!=='.'){
    try {await readFile(path.join(directory,'package.json'));roots.add(directory);break}
    catch {directory=path.dirname(directory)}
  }
}
const notices=[]
for(const file of ['Godot-LICENSE.txt','Godot-COPYRIGHT.txt']) notices.push(`${file}\n${await readFile('third-party/'+file,'utf8')}`)
notices.push(`Barlow Semi Condensed — SIL Open Font License\n${await readFile('assets/fonts/OFL.txt','utf8')}`)
for(const directory of [...roots].sort()){
  const pkg=JSON.parse(await readFile(path.join(directory,'package.json'),'utf8'))
  for(const file of await readdir(directory)){
    if(/^(licen[cs]e|copying|notice)(\.|$)/i.test(file)) notices.push(`${pkg.name} ${pkg.version} — ${file}\n${await readFile(path.join(directory,file),'utf8')}`)
  }
}
await writeFile('build/web/THIRD-PARTY-NOTICES.txt',notices.join('\n\n'+'='.repeat(72)+'\n\n'))
console.log('Bundled browser diagnostics bridge; networking uses Godot WebRTCMultiplayerPeer.')
