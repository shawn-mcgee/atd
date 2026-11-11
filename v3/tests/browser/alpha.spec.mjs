import {test,expect} from '@playwright/test'
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
  await page.mouse.click(...(await diagnostics(page)).mission_menu.nav)
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

test('versioned browser export starts and selects a worker',async({page})=>{
  const errors=await open(page,url.replace('8080/','8080/v3/'))
  await control(page,'solo')
  await expect.poll(async()=> (await diagnostics(page)).active).toBe(true)
  const engineer=(await diagnostics(page)).units.find(u=>u.kind==='engineer')
  await page.mouse.click(...engineer.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(engineer.id)
  expect(errors).toEqual([])
})

test('Lightless controls: launch, change stance, spawn and cancel',async({page})=>{
  const errors=await open(page)
  await control(page,'lightless')
  await expect.poll(async()=> (await diagnostics(page)).owner).toBe(-1)
  const initialScavengers=(await diagnostics(page)).units.filter(u=>u.kind==='scavenger')
  await expect.poll(async()=> (await diagnostics(page)).units.some(u=>u.kind==='scavenger' && initialScavengers.some(start=>start.id===u.id && Math.hypot(u.x-start.x,u.z-start.z)>.7))).toBe(true)
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).paused).toBe(true)
  const clickCommand=async(prefix)=>{
    const button=(await diagnostics(page)).commands.find(c=>c.text.startsWith(prefix))
    expect(button).toBeTruthy()
    expect(button.disabled).toBe(false)
    await page.mouse.click(...button.screen)
  }
  await clickCommand('Defend')
  await expect.poll(async()=> (await diagnostics(page)).status).toContain('stance changed')
  await clickCommand('Mother')
  await page.screenshot({path:'test-results/lightless-controls.png'})
  await expect.poll(async()=> (await diagnostics(page)).queue_cards.length).toBe(1)
  await page.mouse.click(...(await diagnostics(page)).queue_cards[0].screen)
  await expect.poll(async()=> (await diagnostics(page)).queue_cards.length).toBe(0)
  expect((await diagnostics(page)).mission).toContain('LIGHTLESS')
  await clickCommand('Attack')
  const beforeAttack=await diagnostics(page)
  const medusaHealth=beforeAttack.inspection.match(/^HEALTH (\d+)/)[1]
  await page.keyboard.press('Space')
  await expect.poll(async()=> (await diagnostics(page)).tick).toBeGreaterThan(beforeAttack.tick+20)
  await page.keyboard.press('Space')
  expect((await diagnostics(page)).inspection).toMatch(new RegExp(`^HEALTH ${medusaHealth} /`))
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

test('native host assigns a Lightless guest and confirms movement and host loss',async({page})=>{
  const version=readFileSync('.godot-version','utf8').trim()
  const binary=process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform==='win32'?'win64_console.exe':'linux.x86_64'}`)
  const child=spawn(binary,['--headless','--path','.', '--script','tests/network_native.gd','--','--coordinator=ws://127.0.0.1:8081','--main-host-lightless'])
  let output='',exitCode
  child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>output+=b)
  child.on('exit',code=>{exitCode=code})
  try {
    await expect.poll(()=>output,{timeout:20000}).toContain('Lightless host ready:')
    const invitation=output.match(/Lightless host ready: (\S+)/)[1]
    const errors=await open(page)
    await control(page,'join',invitation)
    await expect.poll(async()=> (await diagnostics(page)).active,{timeout:60000}).toBe(true)
    const g=await diagnostics(page)
    expect(g.owner).toBe(-1)
    expect(g.controls.timeControls).toEqual([false,false])
    const unit=g.units.find(u=>u.kind==='father')
    const medusa=g.structures.find(s=>s.kind==='medusa')
    const dx=unit.x-medusa.x,dz=unit.z-medusa.z,length=Math.hypot(dx,dz)
    await control(page,'order',JSON.stringify({action:'move',ids:[unit.id],x:unit.x+dx/length,z:unit.z+dz/length}))
    await expect.poll(()=>output).toContain('Native Lightless move accepted')
    await expect.poll(async()=> {const u=(await diagnostics(page)).units.find(u=>u.id===unit.id);return Math.hypot(u.x-unit.x,u.z-unit.z)}).toBeGreaterThan(.4)
    child.kill()
    await expect.poll(async()=> (await diagnostics(page)).ended).toBe(true)
    expect((await diagnostics(page)).result).toContain('Host disconnected')
    expect(output).not.toMatch(/SCRIPT ERROR:|^ERROR:/m)
    expect(errors).toEqual([])
  } finally {if(exitCode===undefined)child.kill()}
})

test('complex mining keeps guards with workers and exposes expedition status',async({page},testInfo)=>{
  const errors=await open(page)
  await page.mouse.click(...(await diagnostics(page)).mission_menu.nav)
  await page.mouse.click(...(await diagnostics(page)).mission_menu.choices.foothold)
  await page.mouse.click(...(await diagnostics(page)).mission_menu.deploy)
  await expect.poll(async()=> (await diagnostics(page)).mission_id).toBe('foothold')
  const initial=await diagnostics(page)
  const worker=initial.units.find(u=>u.kind==='engineer')
  const guard=initial.units.find(u=>u.kind==='marine')
  const ore=initial.fields.find(f=>f.kind==='ore')
  await page.mouse.click(...guard.screen)
  await expect.poll(async()=> (await diagnostics(page)).selected).toContain(guard.id)
  await control(page,'order',JSON.stringify({action:'mine',ids:[worker.id,guard.id],q:ore.q,r:ore.r}))
  await page.mouse.move(640,400)
  await expect.poll(async()=> (await diagnostics(page)).activity_card.activities[0]?.role).toBe('escort')
  await expect.poll(async()=> (await diagnostics(page)).activity_card.activities[0]?.group_phase).toBe('gather')
  const state=await diagnostics(page)
  const current=state.units.find(u=>u.id===guard.id)
  const source=state.activity_card.activities[0].source
  expect(Math.hypot(current.x-source[0],current.z-source[1])).toBeLessThan(7)
  expect(state.activity_card.activities[0].members).toBe(2)
  await page.screenshot({path:testInfo.outputPath('complex-mining-escort.png')})
  await control(page,'order',JSON.stringify({action:'stop',ids:[worker.id]}))
  await expect.poll(async()=> (await diagnostics(page)).activity_card.activities[0]?.blocker).toBe('no_workers')
  expect(errors).toEqual([])
})
