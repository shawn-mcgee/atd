import {spawnSync} from 'node:child_process'
import {readFileSync} from 'node:fs'
import path from 'node:path'

const version = readFileSync('.godot-version', 'utf8').trim()
const binary = process.env.GODOT_BIN || path.resolve(`.tools/godot/Godot_v${version}-stable_${process.platform === 'win32' ? 'win64_console.exe' : 'linux.x86_64'}`)
const args = process.argv.slice(2)
const result = spawnSync(binary, [...(args.includes('--rendered') ? [] : ['--headless']), '--path', '.', '--quit-after', '180', '--script', 'tools/profile-core.gd', '--', ...args], {encoding: 'utf8', windowsHide: true, timeout: 45000, maxBuffer: 1024 * 1024})
const output = (result.stdout || '') + (result.stderr || '')
process.stdout.write(output)
if (result.error) throw result.error
if (result.status !== 0 || /SCRIPT ERROR:|^ERROR:/m.test(output)) process.exit(result.status || 1)
