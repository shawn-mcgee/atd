// Read-only preflight. Never generate/rewrite UIDs while diagnosing editor exits.
import {existsSync,readFileSync,readdirSync} from 'node:fs'
import path from 'node:path'
import {pathToFileURL} from 'node:url'
export function checkProject(root=process.cwd()) {
  const scripts=[]
  function scan(folder) {
    if(!existsSync(folder) || existsSync(path.join(folder,".gdignore"))) return
    for(const entry of readdirSync(folder,{withFileTypes:true})) {
      const file=path.join(folder,entry.name)
      if(entry.isDirectory()) scan(file)
      else if(entry.isFile() && entry.name.endsWith('.gd')) scripts.push(file)
    }
  }
  for(const folder of ['scripts','tests','tools']) scan(path.join(root,folder))
  const used=new Set(),errors=[]
  for(const file of scripts) {
    if(!existsSync(file+'.uid')) {errors.push('Missing script UID: '+path.relative(root,file)+'.uid');continue}
    const uid=readFileSync(file+'.uid','utf8').trim()
    if(!/^uid:\/\/[a-y0-8]{1,13}$/.test(uid)) errors.push('Malformed script UID: '+file+'.uid')
    if(used.has(uid)) errors.push('Duplicate script UID: '+file+'.uid')
    used.add(uid)
  }
  if(errors.length) throw new Error(errors.join('\n')+'\nEditor import was not started. See docs/editor-troubleshooting.md.')
  return {checked:scripts.length}
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) console.log('Project preflight:',checkProject())
