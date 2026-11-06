import {createServer} from 'node:http'
import {readFile,stat} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {createWsRelayServer} from '@trystero-p2p/ws-relay/server'

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),process.argv.includes('--site')?'../build/site':'../build/web')
const port=Number(process.env.PORT || 8080)
const types={'.html':'text/html','.js':'text/javascript','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml','.json':'application/json'}
const server=createServer(async(req,res)=>{
  try {
    const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname)
    if(pathname==='/favicon.ico'){res.writeHead(204);res.end();return}
    const target=path.resolve(root,'.'+(pathname==='/'?'/index.html':pathname))
    if (!target.startsWith(root+path.sep) && target!==root) {res.writeHead(403);res.end();return}
    if (!(await stat(target)).isFile()) throw new Error('Not a file')
    res.writeHead(200,{'Content-Type':types[path.extname(target)] || 'application/octet-stream','Cache-Control':'no-store'})
    res.end(await readFile(target))
  } catch {res.writeHead(404);res.end('Not found')}
})
server.listen(port,'127.0.0.1',()=>console.log(`Alpha: http://127.0.0.1:${port} | local Trystero test: ?relay=ws://127.0.0.1:${port+1}`))
createWsRelayServer({port:port+1,host:'127.0.0.1'})
