import { join, resolve } from 'node:path'
import { readDesktopRuntime, verifyDesktopRuntime } from '../src/runtime-tree.ts'
import { smokePreparedRuntime } from './smoke-prepared-runtime.ts'

const resources = resolve(process.argv[2])
const dsh = join(resources, 'dsh')
const runtime = join(resources, 'runtime')
const description = await verifyDesktopRuntime(dsh, readDesktopRuntime(dsh).release.version, { platform: 'linux', arch: 'x64' })
await smokePreparedRuntime(dsh, join(runtime, 'primary-runtime/dependencies/node/bin/node'), runtime, description, resources)
