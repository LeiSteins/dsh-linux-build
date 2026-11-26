import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { join } from 'node:path'
import { desktopTargetBuildPaths } from './scripts/desktop-build-paths.mjs'
import { createElectronBuilderConfig } from './scripts/electron-builder-config.mjs'

const config = createElectronBuilderConfig()
const { dsh, electron } = desktopTargetBuildPaths('linux-x64')
const upstreamRoot = fileURLToPath(new URL('../../', import.meta.url))
const productName = process.env.DSH_CLIENT_TITLE
if (!productName) throw new Error('DSH_CLIENT_TITLE is required for Linux packaging')
const executableName = 'dsh-linux'
const maintainer = 'DSH Linux (Community) <noreply@github.com>'
const homepage = 'https://github.com/deepseek-ai/deepseek-harness'
export default {
  ...config,
  electronVersion: readFileSync(join(electron, 'version'), 'utf8').trim(),
  productName,
  executableName,
  artifactName: 'dsh-linux-${version}-${arch}.${ext}',
  extraMetadata: { ...config.extraMetadata, homepage, desktopName: `${executableName}.desktop` },
  linux: { ...config.linux, icon: 'resources/icon-windows.png', maintainer, syncDesktopName: true },
  toolsets: { appimage: '1.0.3' },
  files: config.files.filter(entry => typeof entry === 'string'),
  extraResources: [
    ...config.extraResources,
    { from: join(upstreamRoot, 'LICENSE'), to: 'LICENSE-DSH' },
    { from: join(upstreamRoot, 'THIRD_PARTY_NOTICES.md'), to: 'THIRD_PARTY_NOTICES.md' },
    { from: dsh, to: 'dsh', filter: ['**/*'] },
    { from: join(dsh, 'node_modules'), to: 'dsh/node_modules', filter: ['**/*'] },
  ],
  deb: {
    packageName: executableName,
    depends: [
      'libgtk-3-0t64 | libgtk-3-0', 'libnotify4', 'libnss3', 'libxss1', 'libxtst6',
      'xdg-utils', 'libatspi2.0-0t64 | libatspi2.0-0', 'libuuid1', 'libsecret-1-0',
      'libgbm1', 'libasound2t64 | libasound2', 'libcups2t64 | libcups2',
    ],
  },
  rpm: {
    packageName: executableName,
    depends: [
      'gtk3', 'libnotify', 'nss', 'libXScrnSaver', '(libXtst or libXtst6)',
      'xdg-utils', 'at-spi2-core', '(libuuid or libuuid1)', 'libsecret',
      'libgbm.so.1()(64bit)', 'libasound.so.2()(64bit)', 'libcups.so.2()(64bit)',
    ],
  },
}
