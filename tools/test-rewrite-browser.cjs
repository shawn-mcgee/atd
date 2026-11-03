/* Browser/core parity, local view and two real WebRTC peers. No repository npm install. */
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { spawn } = require('node:child_process');
const args = process.argv.slice(2);
const option = name => { const index = args.indexOf(name); return index < 0 ? null : args[index + 1]; };
const modulePath = option('--playwright');
const { chromium } = modulePath ? require(path.resolve(modulePath)) : require('playwright');
const root = path.resolve(__dirname, '../build/rewrite-web');
const results = path.resolve(__dirname, '../v2/test-results');
const types = { '.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.png': 'image/png' };
const server = http.createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  const target = path.resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {
    response.writeHead(404).end(); return;
  }
  response.writeHead(200, { 'Content-Type': types[path.extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
  fs.createReadStream(target).pipe(response);
});
let browser;
let nativePeer;
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function state(page, action = 'status', value = '') {
  return page.evaluate(([action, value]) => { window.atdTestAction(action, value); return window.atdLiveState; }, [action, value]);
}
async function until(callback, timeout = 45000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = await callback();
    if (result) return result;
    await delay(100);
  }
  throw new Error('Timed out waiting for browser/session state');
}
async function main() {
  fs.mkdirSync(results, { recursive: true });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  browser = await chromium.launch({ headless: true, executablePath: option('--chromium') || undefined,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--autoplay-policy=no-user-gesture-required'] });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const errors = [];
  async function open() {
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(String(error)));
    page.on('console', message => { if (/SCRIPT ERROR:|^ERROR:/.test(message.text())) errors.push(message.text()); });
    await page.goto(origin + '/?selftest=1');
    await page.waitForFunction(() => window.atdTestResult && window.atdTestAction, null, { timeout: 60000 });
    return page;
  }
  const host = await open();
  const foundation = await host.evaluate(() => window.atdTestResult);
  if (!foundation.ok) throw new Error(JSON.stringify(foundation));
  const nativeLog = path.join(results, 'foundation.log');
  if (!fs.existsSync(nativeLog)) throw new Error('Run test-rewrite.py first to provide a native parity result');
  const native = JSON.parse(fs.readFileSync(nativeLog, 'utf8').split('\n').find(line => line.startsWith('ATD_RESULT ')).slice(11));
  if (foundation.checks !== native.checks) throw new Error('Native/browser test counts differ; rebuild the Web export');
  if (foundation.deterministic_hash !== native.deterministic_hash) throw new Error('Native/browser deterministic hashes differ');
  const benchmarkOptions = ['--codecs', '--packed-checkpoints', '--dictionary-checkpoints'].filter(flag => args.includes(flag)).join(' ');
  const benchmark = args.includes('--benchmark') || args.includes('--benchmark-only') || args.includes('--compare-checkpoints')
    ? (await state(host, 'benchmark', '--opposing --large --verify ' + benchmarkOptions)).benchmark : null;
  if (benchmark && !benchmark.ok) throw new Error('Browser movement collision/replay verification failed');
  if (benchmark) fs.writeFileSync(path.join(results, 'movement-browser.json'), JSON.stringify(benchmark, null, 2));
  const checkpointComparison = [];
  if (args.includes('--compare-checkpoints')) {
    for (const format of ['--packed-checkpoints', '--dictionary-checkpoints', '--dictionary-checkpoints', '--packed-checkpoints']) {
      const result = (await state(host, 'benchmark', '--opposing --large --verify ' + format)).benchmark;
      if (!result.ok) throw new Error('Checkpoint comparison collision/replay verification failed');
      if (benchmark && result.reports[0].final_hash !== benchmark.reports[0].final_hash) throw new Error('Checkpoint formats changed the stress state');
      checkpointComparison.push({ option: format, ...result.reports[0] });
    }
    fs.writeFileSync(path.join(results, 'checkpoint-comparison-browser.json'), JSON.stringify(checkpointComparison, null, 2));
  }
  if (args.includes('--benchmark-only')) {
    if (errors.length) throw new Error(errors.join('\n'));
    console.log(JSON.stringify({ok: true, native_browser_hash: foundation.deterministic_hash, foundation_checks: foundation.checks, benchmark, checkpoint_comparison: checkpointComparison}));
    return;
  }
  await host.screenshot({ path: path.join(results, 'configurator.png') });
  // Exercise actual browser downloads/upload, preserving editable project files.
  const projectDownload = host.waitForEvent('download');
  await state(host, 'config_export_project');
  const projectPath = path.join(results, 'config-project.json');
  await (await projectDownload).saveAs(projectPath);
  const project = JSON.parse(fs.readFileSync(projectPath, 'utf8'));
  if (project.format !== 'atd-config-project' || Object.keys(project.files).length < 3) throw new Error('Project export lost source files');
  const engineerPath = 'human/units/engineer.json';
  const engineer = JSON.parse(project.files[engineerPath]);
  engineer.units.engineer.hp = 26;
  project.files[engineerPath] = JSON.stringify(engineer);
  const chooser = host.waitForEvent('filechooser');
  await state(host, 'config_load');
  await (await chooser).setFiles({ name: 'test-project.json', mimeType: 'application/json', buffer: Buffer.from(JSON.stringify(project)) });
  await until(async () => (await state(host, 'config_status')).engineer_hp === 26);
  const mergedDownload = host.waitForEvent('download');
  await state(host, 'config_export_merged');
  const mergedPath = path.join(results, 'config-merged.json');
  await (await mergedDownload).saveAs(mergedPath);
  const merged = JSON.parse(fs.readFileSync(mergedPath, 'utf8'));
  if (merged.imports || merged.units.engineer.hp !== 26) throw new Error('Merged export did not retain edited imported unit');
  await state(host, 'config_defaults');
  await state(host, 'local');
  await until(async () => (await state(host)).tick > 10);
  await state(host, 'move');
  await until(async () => (await state(host)).tick > 30);
  await host.screenshot({ path: path.join(results, 'arena.png') });
  await state(host, 'reset');
  await state(host, 'lightless');
  await until(async () => (await state(host)).tick > 50);
  await state(host, 'defensive');
  await until(async () => (await state(host)).tick > 60);
  await host.screenshot({ path: path.join(results, 'veil.png') });
  await state(host, 'reset');
  // Bound test matches so a faster renderer cannot trim the slower peer's comparison checkpoint.
  await state(host, 'limit', '100');
  await state(host, 'host');
  const room = (await until(async () => { const info = await state(host); return info.room && info; })).room;
  const client = await open();
  await state(client, 'limit', '100');
  await state(client, 'join', room);
  await until(async () => (await state(host)).players === 2);
  await state(host, 'start');
  await until(async () => (await state(host)).running && (await state(client)).running);
  await state(client, 'move');
  const comparison = await until(async () => {
    const a = await state(host), b = await state(client);
    if (a.error || b.error) throw new Error(a.error || b.error);
    const tick = Math.floor((Math.min(a.confirmed, b.confirmed) + 1) / 20) * 20;
    if (tick < 80) return false;
    if (!a.hashes[tick] || a.hashes[tick] !== b.hashes[tick]) {
      const snapshots = { tick, a, b, host: await state(host, 'checkpoint', String(tick)), client: await state(client, 'checkpoint', String(tick)) };
      fs.writeFileSync(path.join(results, 'browser-desync.json'), JSON.stringify(snapshots, null, 2));
      throw new Error(`Browser peers differ at ${tick}; see browser-desync.json`);
    }
    return { tick, hash: a.hashes[tick] };
  });
  let nativeBrowserMatch = null;
  if (option('--godot')) {
    await host.close();
    await client.close();
    // Load/run the browser foundation suite before starting the native peer's
    // bounded live-match clock. Startup work is not part of that match deadline.
    const cross = await open();
    // The native companion hosts Humans; this peer must supply Lightless.
    await state(cross, 'lightless');
    await state(cross, 'reset');
    const hashes = [];
    let nativeRoom = '', nativeOutput = '', nativeExit = null;
    nativePeer = spawn(option('--godot'), ['--headless', '--path', path.resolve(__dirname, '../v2'), '--script', 'res://tests/browser_host.gd']);
    nativePeer.on('exit', code => { nativeExit = code; });
    nativePeer.on('error', error => { nativeOutput += String(error); nativeExit = -1; });
    nativePeer.stdout.on('data', chunk => {
      nativeOutput += chunk.toString();
      const lines = nativeOutput.split('\n');
      lines.pop(); // Keep a partially received final line for the next chunk.
      const roomLine = lines.find(line => line.startsWith('ATD_ROOM '));
      if (roomLine) nativeRoom = roomLine.slice(9).trim();
      for (const line of lines.filter(line => line.startsWith('ATD_CROSS_HASH '))) {
        const value = JSON.parse(line.slice(15));
        if (!hashes.some(item => item.tick === value.tick)) hashes.push(value);
      }
    });
    nativePeer.stderr.on('data', chunk => { nativeOutput += chunk.toString(); });
    await until(async () => { if (nativeExit !== null) throw new Error(nativeOutput); return nativeRoom; });
    await state(cross, 'limit', '100');
    await state(cross, 'join', nativeRoom);
    await until(async () => {
      const info = await state(cross);
      if (info.error || nativeExit !== null) throw new Error(info.error || nativeOutput);
      return info.running;
    });
    await state(cross, 'move');
    nativeBrowserMatch = await until(async () => {
      const info = await state(cross);
      if (info.error || nativeExit !== null) throw new Error(info.error || nativeOutput);
      const common = hashes.find(item => item.tick >= 60 && item.tick <= info.confirmed + 1 && info.hashes[item.tick]);
      if (!common) return false;
      if (info.hashes[common.tick] !== common.hash) throw new Error('Native/browser live match desync');
      return common;
    });
    await state(cross, 'finish_test');
    await until(async () => nativeExit !== null, 5000);
    if (nativeExit !== 0 || /SCRIPT ERROR:|^ERROR:/m.test(nativeOutput)) throw new Error(nativeOutput);
  }
  if (errors.length) throw new Error(errors.join('\n'));
  const result = { ok: true, native_browser_hash: foundation.deterministic_hash, foundation_checks: foundation.checks,
    browser_match: comparison, native_browser_match: nativeBrowserMatch, benchmark, checkpoint_comparison: checkpointComparison, screenshots: ['configurator.png', 'arena.png', 'veil.png'] };
  fs.writeFileSync(path.join(results, 'browser.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  if (browser) await browser.close();
  if (nativePeer && nativePeer.exitCode === null) nativePeer.kill();
  server.close();
});
