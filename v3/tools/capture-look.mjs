import {chromium} from '@playwright/test'
import {mkdir} from 'node:fs/promises'
import config from '../playwright.config.mjs'

// Capture actual exported gameplay, including its normal lighting and shaders.
await mkdir('build/visual-review',{recursive:true})
const browser=await chromium.launch({...config.use.launchOptions,headless:true})
try {
  const page=await browser.newPage({viewport:{width:1280,height:800}})
  const cdp=await page.context().newCDPSession(page)
  await cdp.send('Emulation.setFocusEmulationEnabled',{enabled:true})
  const errors=[]
  page.on('console',m=>{if(m.type()==='error' && /SCRIPT ERROR|Shader|Invalid|Failed to load script/.test(m.text())) errors.push(m.text())})
  page.on('pageerror',e=>errors.push(e.message))
  page.setDefaultTimeout(90000)
  await page.goto('http://127.0.0.1:8080/?test=1&relay=ws://127.0.0.1:8081')
  await page.waitForFunction(()=>ATDNetwork.inspect().ready)
  await page.screenshot({path:'build/visual-review/title.png'})
  await page.evaluate(()=>ATDNetwork.test('solo'))
  await page.waitForFunction(()=>ATDNetwork.inspect().active && ATDNetwork.inspect().tick>15)
  const engineer=(await page.evaluate(()=>ATDNetwork.inspect())).units.find(u=>u.kind==='engineer')
  await page.mouse.click(...engineer.screen)
  await page.waitForFunction(id=>ATDNetwork.inspect().selected.includes(id),engineer.id)
  await page.screenshot({path:'build/visual-review/expedition.png'})
  for(let i=0;i<4;i++) await page.mouse.wheel(0,-100)
  await page.waitForFunction(()=>ATDNetwork.inspect().camera.distance<17)
  await page.screenshot({path:'build/visual-review/close.png'})
  if(errors.length) throw new Error(errors.join('\n'))
  console.log('Rendered title, gameplay and close-up captures in build/visual-review.')
} finally {await browser.close()}
