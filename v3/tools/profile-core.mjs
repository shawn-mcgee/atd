import {spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
import path from 'node:path'

const version = readFileSync('.godot-version', 'utf8').trim()
const binary = process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform === 'win32' ? 'win64_console.exe' : 'linux.x86_64'}`)
const args = process.argv.slice(2)
const timelineBudgetMs = Number(args.find(arg => arg.startsWith('--timeline-budget-ms='))?.split('=')[1] ?? 35000)
const timeout = args.includes('--match-timeline') && Number.isFinite(timelineBudgetMs) ? Math.max(45000, Math.min(timelineBudgetMs, 300000) + 10000) : 45000
const result = spawnSync(binary, [...(args.includes('--rendered') ? [] : ['--headless']), '--path', '.', '--quit-after', '180', '--script', 'tools/profile-core.gd', '--', ...args], {encoding: 'utf8', windowsHide: true, timeout, maxBuffer: 1024 * 1024})
const output = (result.stdout || '') + (result.stderr || '')
process.stdout.write(output)
if (result.error) throw result.error
if (result.status !== 0 || /SCRIPT ERROR:|^ERROR:/m.test(output)) process.exit(result.status || 1)
