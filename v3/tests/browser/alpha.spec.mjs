import {test,expect,chromium} from '@playwright/test'
import browserConfig from '../../playwright.config.mjs'
import {spawn} from 'node:child_process'
import {readFileSync} from 'node:fs'
import path from 'node:path'
const url='http://127.0.0.1:8080/?test=1&coordinator=ws://127.0.0.1:8081'
const diagnostics=page=>page.evaluate(()=>window.ATDNetwork.inspect())
const control=(page,command,value='')=>page.evaluate(([c,v])=>window.ATDNetwork.test(c,v),[command,value])
test('native guest joins a browser host using Godot multiplayer',async({page})=>{
  const errors=await open(page)
  await control(page,'host')
  await expect.poll(async()=> (await diagnostics(page)).invitation).not.toBe('')
  const version=readFileSync('.godot-version','utf8').trim()
  const binary=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
  const invitation=(await diagnostics(page)).invitation
  const child=spawn(binary,['--headless','--path','.', '--script','tests/network_native.gd','--','--coordinator=ws://127.0.0.1:8081',`--join=${invitation}`])
  let output='',exitCode
  child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b)
  child.on('exit',code=>{exitCode=code})
  try {
    await expect.poll(()=>output,{timeout:20000}).toContain('Native guest admitted')
    await expect.poll(async()=> (await diagnostics(page)).peers).toBe(1)
    await control(page,'leave')
    await expect.poll(()=>exitCode,{timeout:20000}).toBe(0)
    expect(output).not.toMatch(/SCRIPT ERROR:|^ERROR:/m)
    expect(errors).toEqual([])
  } finally {if(exitCode===undefined)child.kill()}
})
test('selected workers show cargo and a specific storage blocker',async({page},testInfo)=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(640,400)
  const initial=await diagnostics(page)
  const worker=initial.units.find(u=>u.kind==='engineer')
  const anchor=initial.structures.find(s=>s.kind==='anchor')
  const ore=initial.fields.find(f=>f.kind==='ore')
  await page.mouse.click(...worker.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(worker.id)
  await control(page,'order',JSON.stringify({action:'mine',ids:[worker.id],q:ore.q,r:ore.r}))
  await expect.poll(async()=> (await diagnostics(page)).activity_card.cargo.ore || 0).toBeGreaterThan(0)
  await control(page,'order',JSON.stringify({action:'deposit',ids:[worker.id],target:anchor.id}))
  await expect.poll(async()=> (await diagnostics(page)).activity_card.activities[0].blocker).toBe('storage_full')
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  await page.mouse.move(640,400)
  await page.screenshot({path:testInfo.outputPath('selected-storage-blocker.png')})
  expect((await diagnostics(page)).activity_card.visible).toBe(true)
  expect(errors).toEqual([])
})
test('window fill and edge pan feedback',async({page},testInfo)=>{
  await page.setViewportSize({width:1920,height:900})
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(960,450)
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  await expect.poll(async()=>{const v=(await diagnostics(page)).camera.viewport;return v[0]/v[1]}).toBeCloseTo(1920/900,2)
  for(const [x,y,direction] of [[20,450,[-1,0]],[1900,450,[1,0]],[960,20,[0,-1]],[960,880,[0,1]],[10,10,[-1,-1]],[960,450,[0,0]]]){
    await page.mouse.move(x,y)
    await expect.poll(async()=> (await diagnostics(page)).camera.edge).toEqual(direction)
    if(x===20){
      const before=(await diagnostics(page)).camera.x
      await expect.poll(async()=> (await diagnostics(page)).camera.x).toBeLessThan(before)
      await page.screenshot({path:testInfo.outputPath('edge-arrows.png')})
    }
  }
  await page.setViewportSize({width:900,height:1100})
  await expect.poll(async()=>{const v=(await diagnostics(page)).camera.viewport;return v[0]/v[1]}).toBeCloseTo(900/1100,2)
  expect(errors).toEqual([])
})
test('mission menu deploys every unlocked contract and renders its objectives',async({page},testInfo)=>{
  const errors=await open(page)
  await page.screenshot({path:testInfo.outputPath('mission-menu.png')})
  for(const [id,title] of [['foothold','FIRST FOOTHOLD'],['industry','SUPPLY AND STEEL'],['extraction','THE LAST LIGHT']]){
    const menu=(await diagnostics(page)).mission_menu
    expect(menu.deploy[1]).toBeLessThan(800)
    await page.mouse.click(...menu.choices[id])
    await expect.poll(async()=> (await diagnostics(page)).mission_menu.selected).toBe(id)
    await page.mouse.click(...(await diagnostics(page)).mission_menu.deploy)
    await expect.poll(async()=> (await diagnostics(page)).mission_id).toBe(id)
    await expect.poll(async()=> (await diagnostics(page)).mission).toContain(title)
    await page.keyboard.press('Space')
    await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
    await page.screenshot({path:testInfo.outputPath(`${id}.png`)})
    await control(page,'leave')
    await expect.poll(async()=> (await diagnostics(page)).active).toBe(false)
  }
  expect(errors).toEqual([])
})
async function open(page,target=url){
  // Model separate players' foreground browsers, not two occluded tabs on one PC.
  const cdp=await page.context().newCDPSession(page)
  await cdp.send('Emulation.setFocusEmulationEnabled',{enabled:true})
  const errors=[]
  page.on('pageerror',e=>errors.push(e.message))
  page.on('console',m=>{if(m.type()==='error' && /SCRIPT ERROR|Invalid|Failed to load script/.test(m.text())) errors.push(m.text())})
  await page.goto(target)
  await page.waitForFunction(()=>window.ATDNetwork?.inspect().ready,null,{timeout:60000})
  return errors
}

test('wall painting: pointer drag queues affordable blueprints',async({page})=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(640,400); await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  const initial=await diagnostics(page)
  const engineer=initial.units.find(u=>u.kind==='engineer')
  await page.mouse.click(...engineer.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(engineer.id)
  await page.keyboard.press('b'); await page.keyboard.press('w')
  await expect.poll(async()=> (await diagnostics(page)).build_kind).toBe('wall')
  let line
  await expect.poll(async()=>{
    const {build_sites:sites}=await diagnostics(page)
    for(const start of sites){
      const middle=sites.find(s=>s.q===start.q+1 && s.r===start.r)
      const end=sites.find(s=>s.q===start.q+2 && s.r===start.r)
      if(middle && end){line=[start,end];return true}
    }
    return false
  }).toBe(true)
  await page.mouse.move(...line[0].screen); await page.mouse.down()
  await page.mouse.move(...line[1].screen); await page.mouse.up()
  await expect.poll(async()=> (await diagnostics(page)).structures.filter(s=>s.kind==='wall').length).toBe(3)
  const result=await diagnostics(page)
  expect(result.resources.ore).toBe(initial.resources.ore-15)
  expect(result.units.find(u=>u.id===engineer.id).queued).toBe(2)
  expect(result.build_kind).toBe('')
  expect(errors).toEqual([])
})

test('minimap input: drag and queued commands',async({page})=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(640,400)
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  const initial=await diagnostics(page)
  const marine=initial.units.find(u=>u.kind==='marine')
  await page.mouse.click(...marine.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(marine.id)
  await page.keyboard.down('Shift')
  try {await page.mouse.click(180,650,{button:'right'})} finally {await page.keyboard.up('Shift')}
  await expect.poll(async()=> (await diagnostics(page)).units.find(u=>u.id===marine.id).queued).toBe(1)
  await page.mouse.move(118,694); await page.mouse.down()
  await page.mouse.move(158,680,{steps:4}); await page.mouse.up()
  await expect.poll(async()=> Math.abs((await diagnostics(page)).camera.x-initial.camera.x)).toBeGreaterThan(2)
  expect((await diagnostics(page)).selected).toContain(marine.id)
  expect(errors).toEqual([])
})

test('versioned browser scene: select, mine, pause and navigate',async({page})=>{
  const errors=await open(page,url.replace('8080/','8080/v3/'))
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(640,400)
  const initial=await diagnostics(page)
  const engineer=initial.units.find(u=>u.kind==='engineer')
  expect(engineer.screen[0]).toBeGreaterThan(0)
  expect(engineer.screen[0]).toBeLessThan(1280)
  await page.mouse.click(...engineer.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(engineer.id)
  const ore=(await diagnostics(page)).fields.find(f=>f.kind==='ore')
  await page.keyboard.press('m')
  await page.mouse.click(...ore.screen)
  await expect.poll(async()=> (await diagnostics(page)).units.find(u=>u.id===engineer.id).cargo.ore || 0).toBeGreaterThan(0)
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  expect((await diagnostics(page)).mission).toContain('FIND AND DESTROY')
  await page.keyboard.press('x')
  await expect.poll(async()=> (await diagnostics(page)).units.find(u=>u.id===engineer.id).job).toBe('idle')
  expect((await diagnostics(page)).units.find(u=>u.id===engineer.id).cargo.ore).toBeGreaterThan(0)
  await page.keyboard.press('b')
  await expect.poll(async()=> (await diagnostics(page)).build_buttons.depot[0]).toBeGreaterThan(950)
  await page.mouse.click(...(await diagnostics(page)).build_buttons.depot)
  await expect.poll(async()=> (await diagnostics(page)).build_kind).toBe('depot')
  await expect.poll(async()=> (await diagnostics(page)).build_sites.length).toBeGreaterThan(0)
  const site=(await diagnostics(page)).build_sites[0]
  await page.mouse.move(...site.screen)
  await page.screenshot({path:'test-results/construction-preview.png'})
  await page.mouse.click(...site.screen)
  await expect.poll(async()=> (await diagnostics(page)).structures.filter(s=>s.kind==='depot').length).toBe(1)
  expect((await diagnostics(page)).resources.ore).toBe(80)
  const before=await diagnostics(page)
  await page.keyboard.down('ArrowRight')
  await page.waitForTimeout(350)
  await page.keyboard.up('ArrowRight')
  await expect.poll(async()=> (await diagnostics(page)).camera.x).toBeGreaterThan(before.camera.x)
  const after=await diagnostics(page)
  expect(after.tick).toBe(before.tick)
  await page.mouse.wheel(0,-100)
  await expect.poll(async()=> (await diagnostics(page)).camera.distance).toBeLessThan(before.camera.distance-1)
  await page.keyboard.down('Insert')
  await expect.poll(async()=> (await diagnostics(page)).camera.yaw).toBeGreaterThan(1)
  await page.keyboard.up('Insert')
  await expect.poll(async()=>Math.abs((await diagnostics(page)).camera.yaw)).toBeLessThan(.05)
  await page.keyboard.press('Home')
  await expect.poll(async()=>Math.abs((await diagnostics(page)).camera.x-initial.camera.x)).toBeLessThan(.1)
  await page.mouse.click(118,694)
  await expect.poll(async()=>Math.abs((await diagnostics(page)).camera.x)).toBeLessThan(1)
  expect(errors).toEqual([])
})

test('production interface: inspect queues and cancel an unstarted order',async({page})=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  const anchor=(await diagnostics(page)).structures.find(s=>s.kind==='anchor')
  await page.mouse.click(...anchor.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(anchor.id)
  await expect.poll(async()=> (await diagnostics(page)).inspection).toContain('GRID')
  const requestOperator=async()=>{
    const card=(await diagnostics(page)).commands.find(c=>c.text.startsWith('Operator'))
    expect(card.disabled).toBe(false)
    await page.mouse.click(...card.screen)
  }
  await requestOperator()
  await expect.poll(async()=> (await diagnostics(page)).queue_cards.length).toBe(1)
  await requestOperator()
  await expect.poll(async()=> (await diagnostics(page)).queue_cards.length).toBe(2)
  await page.screenshot({path:'test-results/production-interface.png'})
  await page.mouse.click(...(await diagnostics(page)).queue_cards[0].screen)
  await expect.poll(async()=> (await diagnostics(page)).queue_cards.length).toBe(1)
  expect((await diagnostics(page)).resources.ore).toBe(90)
  expect(errors).toEqual([])
})

test('combat feedback: legal friendly fire reaches the browser renderer',async({page})=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  const initial=await diagnostics(page)
  const marine=initial.units.find(u=>u.kind==='marine')
  const anchor=initial.structures.find(s=>s.kind==='anchor')
  await page.mouse.click(...marine.screen)
  await control(page,'order',JSON.stringify({action:'attack',ids:[marine.id],target:anchor.id}))
  await expect.poll(async()=> (await diagnostics(page)).feedback.events.includes('fire')).toBe(true)
  await expect.poll(async()=> (await diagnostics(page)).feedback.events.includes('hit')).toBe(true)
  await expect.poll(async()=> (await diagnostics(page)).feedback.cursor).toBeGreaterThan(0)
  await control(page,'order',JSON.stringify({action:'stop',ids:[marine.id]}))
  await expect.poll(async()=> (await diagnostics(page)).units.find(u=>u.id===marine.id).job).toBe('idle')
  expect(errors).toEqual([])
})

test('RTS controls: WASD, same-type selection, groups, build keys and Q',async({page})=>{
  const errors=await open(page)
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  await page.mouse.move(640,400)
  let d=await diagnostics(page)
  const marine=d.units.find(u=>u.kind==='marine')
  await page.mouse.dblclick(...marine.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(marine.id)
  await page.keyboard.press('Shift+1')
  await expect.poll(async()=> (await diagnostics(page)).controls.groups['1']).toContain(marine.id)
  let engineer=(await diagnostics(page)).units.find(u=>u.kind==='engineer')
  await page.mouse.click(...engineer.screen)
  await page.keyboard.press('1')
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(marine.id)
  await page.keyboard.press('q')
  await expect.poll(async()=> (await diagnostics(page)).controls.attack).toBe(true)
  await page.keyboard.press('Escape')
  const camera=(await diagnostics(page)).camera
  await page.keyboard.down('d')
  try {await expect.poll(async()=> (await diagnostics(page)).camera.x).toBeGreaterThan(camera.x+.2)} finally {await page.keyboard.up('d')}
  await page.keyboard.down('s')
  try {await expect.poll(async()=> (await diagnostics(page)).camera.z).toBeGreaterThan(camera.z+.2)} finally {await page.keyboard.up('s')}
  await page.keyboard.press('Home')
  await expect.poll(async()=>Math.abs((await diagnostics(page)).camera.x-d.camera.x)).toBeLessThan(.1)
  engineer=(await diagnostics(page)).units.find(u=>u.kind==='engineer')
  await page.mouse.click(...engineer.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(engineer.id)
  await page.keyboard.press('b')
  await expect.poll(async()=> (await diagnostics(page)).controls.buildMenu).toBe(true)
  const before=(await diagnostics(page)).camera.x
  await page.keyboard.down('d')
  try {
    await expect.poll(async()=> (await diagnostics(page)).build_kind).toBe('depot')
    await expect.poll(async()=> (await diagnostics(page)).controls.ghost).toBe(true)
    expect((await diagnostics(page)).camera.x).toBeCloseTo(before,1)
  } finally {await page.keyboard.up('d')}
  expect((await diagnostics(page)).controls.buildMenu).toBe(false)
  await page.keyboard.press('Escape')
  await expect.poll(async()=> (await diagnostics(page)).build_kind).toBe('')
  expect(errors).toEqual([])
})

test('custom coordinator room: cross-origin clients, host orders and host loss',async()=>{
  // Separate browser processes model separate players and isolate software-GPU
  // and window lifetimes when the host closes. Incognito contexts share both.
  const [hostBrowser,guestBrowser]=await Promise.all([
    chromium.launch({...browserConfig.use.launchOptions,headless:true}),
    chromium.launch({...browserConfig.use.launchOptions,headless:true})
  ])
  try {
  const hostContext=await hostBrowser.newContext({viewport:{width:1280,height:800}})
  const guestContext=await guestBrowser.newContext({viewport:{width:1280,height:800}})
  const host=await hostContext.newPage(),guest=await guestContext.newPage()
  const hostErrors=await open(host)
  const guestErrors=await open(guest,url.replace('127.0.0.1:8080','localhost:8080'))
  await control(host,'host')
  await expect.poll(async()=> (await diagnostics(host)).invitation).not.toBe('')
  const invitation=(await diagnostics(host)).invitation
  await control(guest,'join',invitation)
  await expect.poll(async()=> (await diagnostics(host)).peers,{timeout:45000}).toBe(1)
  await control(host,'launch')
  // Two cold WebGL scenes share the software GPU on CI; allow shader warm-up.
  await expect.poll(async()=> (await diagnostics(guest)).active,{timeout:60000}).toBe(true)
  try {
    await expect.poll(async()=> (await diagnostics(guest)).tick).toBeGreaterThan(2)
  } catch(error) {
    for (const [name,page] of [['host',host],['guest',guest]]) {
      const d=await diagnostics(page)
      console.error(name,JSON.stringify({tick:d.tick,active:d.active,ended:d.ended,status:d.status,result:d.result,paused:d.paused}))
    }
    console.error('Game errors',hostErrors,guestErrors)
    throw error
  }
  expect((await diagnostics(host)).controls.timeControls).toEqual([false,false])
  expect((await diagnostics(guest)).controls.timeControls).toEqual([false,false])
  const g=await diagnostics(guest)
  expect(g.owner).toBe(1)
  const unit=g.units.find(u=>u.kind==='engineer')
  await control(guest,'order',JSON.stringify({action:'move',ids:[unit.id],x:unit.x+1,z:unit.z}))
  await expect.poll(async()=> (await diagnostics(guest)).units.find(u=>u.id===unit.id).x).toBeGreaterThan(unit.x+.4)
  await hostContext.close()
  // Closing a window can occlude the survivor in headless Linux. Model the
  // remaining player's foreground game, including Godot's animation frames.
  await guest.bringToFront()
  try {
    await expect.poll(async()=> (await diagnostics(guest)).ended,{timeout:30000}).toBe(true)
  } catch (error) {
    console.error('Guest after host closure', JSON.stringify(await guest.evaluate(() => ({
      game: window.ATDNetwork.inspect(), visibility: document.visibilityState, focused: document.hasFocus()
    }))))
    console.error('Game errors', hostErrors, guestErrors)
    throw error
  }
  expect((await diagnostics(guest)).result).toContain('Host disconnected')
  expect([...hostErrors,...guestErrors]).toEqual([])
  await guestContext.close()
  } finally {await Promise.allSettled([hostBrowser.close(),guestBrowser.close()])}
})
