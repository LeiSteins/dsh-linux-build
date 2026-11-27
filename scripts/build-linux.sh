#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/release-common.sh"

if [[ $# != 3 ]]; then
  echo '用法: scripts/build-linux.sh <上游源码目录> <上游发布标签> <产物目录>' >&2
  exit 2
fi

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
upstream=$(realpath -- "$1")
tag=$2
version=$(version_from_tag "$tag")
output=$(realpath -m -- "$3")
if [[ "$output/" == "$upstream/"* ]]; then
  echo '产物目录需要位于上游检出目录之外。' >&2
  exit 1
fi
cd -- "$upstream"

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo '构建需要 Linux x86_64。' >&2
  exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
  echo '请使用干净的上游检出目录。构建会在该目录应用 Linux 补丁。' >&2
  exit 1
fi
if [[ $(jq -r .version package.json) != "$version" || $(jq -r .version apps/desktop/package.json) != "$version" ]]; then
  echo "上游 package.json 的版本须与 $tag 一致。" >&2
  exit 1
fi

revision=$(git rev-parse HEAD)
if [[ -n ${UPSTREAM_REVISION:-} && "$revision" != "$UPSTREAM_REVISION" ]]; then
  echo "上游检出提交与工作流选择的提交不同: $revision" >&2
  exit 1
fi

export DSH_DESKTOP_LINUX_CLIENT_TITLE='Deepseek Harness'
export DSH_DESKTOP_BUILD_VERSION="$version"
export DSH_DESKTOP_PACMAN_VERSION="$(pacman_version "$version")"
export DSH_DESKTOP_APP_ID=io.github.leisteins.dshlinux
export DSH_DESKTOP_TARGET_PLATFORM=linux DSH_DESKTOP_TARGET_ARCH=x64 DSH_DESKTOP_UNSIGNED=1
export DSH_DESKTOP_BUILD_COMMIT="$revision" DSH_DESKTOP_BUILD_DIRTY=1 DSH_TELEMETRY_DISABLED=1

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT

# Validate each patch against the preceding result without modifying the checkout.
patch_index="$stage/patch-index"
GIT_INDEX_FILE="$patch_index" git read-tree "$revision"
patches=(
  0001-linux-build-runtime.patch
  0002-linux-tray.patch
  0003-linux-caption.patch
  0004-linux-branding.patch
  0005-linux-release-update.patch
  0006-linux-welcome-window.patch
  0007-linux-host-environment.patch
)
for patch in "${patches[@]}"; do
  if ! GIT_INDEX_FILE="$patch_index" git apply --cached "$repo/patches/$patch"; then
    echo "Linux 补丁 $patch 需要同步至 $tag。" >&2
    exit 1
  fi
done
if ! GIT_INDEX_FILE="$patch_index" git diff --cached --binary --no-ext-diff --no-textconv --no-color \
  --src-prefix=a/ --dst-prefix=b/ "$revision" | git apply; then
  echo "无法将 Linux 补丁写入 $tag 的检出目录。" >&2
  exit 1
fi
install -m 644 "$repo/packaging/electron-builder-linux.config.mjs" apps/desktop/electron-builder-linux.config.mjs
install -m 644 "$repo/packaging/smoke-linux.mts" apps/desktop/scripts/smoke-linux.mts

pnpm install --frozen-lockfile
pnpm exec vitest run \
  scripts/client-build-environment.client.spec.ts \
  apps/desktop/tests/desktop-build-paths.spec.ts \
  apps/desktop/tests/runtime-preparation.spec.ts \
  apps/desktop/tests/prepare-package-set.spec.ts \
  apps/desktop/tests/retain-desktop-ci.spec.ts \
  apps/desktop/tests/main-startup.spec.ts \
  apps/desktop/tests/host-process.spec.ts \
  apps/desktop/tests/node-environment.spec.ts \
  apps/desktop/tests/prepared-runtime-smoke.spec.ts \
  apps/desktop/tests/smoke-runtime.spec.ts \
  apps/desktop/tests/tray.spec.ts \
  apps/desktop/tests/caption-controls.client.spec.ts \
  apps/desktop/tests/preload-menu.client.spec.ts \
  apps/desktop/tests/preload-app.spec.ts \
  apps/desktop/tests/preload-platform.client.spec.ts \
  apps/desktop/tests/preload-windows.client.spec.ts \
  apps/desktop/tests/update-dialog.spec.ts \
  apps/desktop/tests/linux-release-update.spec.ts \
  apps/desktop/tests/update-overlay.spec.ts \
  apps/desktop/tests/welcome-window.spec.ts \
  apps/desktop/tests/pack-local-packages.spec.ts \
  packages/client/ui-brand-official/tests/browser-plugin.client.spec.tsx
pnpm run build:artifacts --profile local
if ! jq -e --arg title "$DSH_DESKTOP_LINUX_CLIENT_TITLE" \
  '.environment.DSH_CLIENT_TITLE == $title' .dsh-build/client-build-environment.json >/dev/null; then
  echo '构建记录缺少社区 Linux 客户端标题。' >&2
  exit 1
fi

# Follow upstream package-target.ts to prepare the local package closure and embedded runtimes.
target_build="$upstream/apps/desktop/.desktop-build/targets/linux-x64"
packed="$target_build/packed"
mkdir -p "$packed/dsh" "$packed/vendor" "$packed/landlock"
pnpm exec tsx apps/desktop/scripts/pack-local-packages.ts --out "$packed/dsh" --concurrency 4
pnpm --dir apps/desktop-host pack --pack-destination "$packed/dsh"
pnpm run release:pack --family vendor --out "$packed/vendor" --concurrency 4
pnpm --dir native/system run build:ts
pnpm --dir native/system/packages/entry pack --pack-destination "$packed/landlock"
pnpm --dir apps/desktop run prepare:runtime
pnpm --dir apps/desktop run prepare:packages
pnpm --dir apps/desktop run prepare:dsh 2>&1 | sed -uE 's/([?&]token=)[^[:space:]&]+/\1[redacted]/g'

# hicolor indexes standard sizes through 512 px. The upstream icon is 1024 px.
pnpm --dir apps/desktop exec node --input-type=module - "$target_build/linux-icons" <<'JS'
import { mkdir } from 'node:fs/promises'
import { join } from 'node:path'
import sharp from 'sharp'

const directory = process.argv[2]
await mkdir(directory, { recursive: true })
for (const size of [16, 32, 48, 64, 128, 256, 512]) {
  await sharp('resources/icon-windows.png').resize(size, size).toFile(join(directory, `${size}x${size}.png`))
}
JS

builder=(pnpm --dir apps/desktop exec electron-builder --config electron-builder-linux.config.mjs --x64 --publish never "--config.directories.output=$stage")
"${builder[@]}" --linux --dir
cmp apps/desktop/resources/icon-windows.png "$stage/linux-unpacked/resources/icon.png"
ELECTRON_RUN_AS_NODE=1 "$stage/linux-unpacked/dsh-linux" -e '
  const [archive, version] = process.argv.slice(1);
  const { version: packagedVersion } = JSON.parse(require("node:fs").readFileSync(archive + "/package.json", "utf8"));
  require("node:assert/strict").equal(packagedVersion, version);
' "$stage/linux-unpacked/resources/app.asar" "$version"
pnpm --dir apps/desktop exec node --input-type=module - "$stage/linux-unpacked/resources/app-update.yml" <<'JS'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { load } from 'js-yaml'

const update = load(readFileSync(process.argv[2], 'utf8'))
assert.equal(update.provider, 'github')
assert.equal(`${update.owner}/${update.repo}`, process.env.GITHUB_REPOSITORY ?? 'LeiSteins/dsh-linux-build')
assert.equal(update.publishAutoUpdate, false)
assert.ok(update.updaterCacheDirName)
JS
pnpm exec tsx apps/desktop/scripts/smoke-linux.mts "$stage/linux-unpacked/resources" 2>&1 |
  sed -uE 's/([?&]token=)[^[:space:]&]+/\1[redacted]/g'
package_type="$stage/linux-unpacked/resources/package-type"
for target in deb rpm AppImage pacman; do
  # The native targets write this file into the shared Electron tree.
  if [[ -e "$package_type" ]]; then unlink "$package_type"; fi
  printf '%s\n' "${target,,}" > "$stage/linux-unpacked/resources/dsh-linux-package-type"
  "${builder[@]}" --linux "$target" --prepackaged "$stage/linux-unpacked"
done

mapfile -t packages < <(package_names "$version")
for file in "${packages[@]}"; do
  test -s "$stage/$file"
done
native_version=${version//-/\~}
[[ $(dpkg-deb -f "$stage/${packages[0]}" Architecture) == amd64 ]]
[[ $(dpkg-deb -f "$stage/${packages[0]}" Version) == "$native_version" ]]
mkdir "$stage/rpmdb"
[[ $(rpm --dbpath "$stage/rpmdb" -qp --queryformat '%{ARCH} %{VERSION}' "$stage/${packages[1]}") == "x86_64 $native_version" ]]
launcher_icon=/usr/share/icons/hicolor/256x256/apps/dsh-linux.png
dpkg-deb --fsys-tarfile "$stage/${packages[0]}" | tar -t | grep -Fx ".$launcher_icon"
rpm --dbpath "$stage/rpmdb" -qpl "$stage/${packages[1]}" | grep -Fx "$launcher_icon"
pacman_package="$stage/$(pacman_package_name "$version")"
pkginfo=$(bsdtar -xOf "$pacman_package" .PKGINFO)
grep -Fx 'pkgname = dsh-linux' <<< "$pkginfo"
grep -Fx "pkgver = $DSH_DESKTOP_PACMAN_VERSION-1" <<< "$pkginfo"
grep -Fx 'arch = x86_64' <<< "$pkginfo"
bsdtar -tf "$pacman_package" | grep -Fx "${launcher_icon#/}"
bsdtar -xOf "$pacman_package" "opt/$DSH_DESKTOP_LINUX_CLIENT_TITLE/resources/dsh-linux-package-type" | grep -Fx pacman
mkdir "$stage/appimage-test"
(
  cd "$stage/appimage-test"
  "$stage/${packages[2]}" --appimage-extract dsh-linux.desktop >/dev/null
  grep -Fx "Name=$DSH_DESKTOP_LINUX_CLIENT_TITLE" squashfs-root/dsh-linux.desktop
  grep -Fx 'Icon=dsh-linux' squashfs-root/dsh-linux.desktop
  "$stage/${packages[2]}" --appimage-extract resources/dsh-linux-package-type >/dev/null
  grep -Fx appimage squashfs-root/resources/dsh-linux-package-type
  "$stage/${packages[2]}" --appimage-extract resources/app-update.yml >/dev/null
  cmp "$stage/linux-unpacked/resources/app-update.yml" squashfs-root/resources/app-update.yml
  "$stage/${packages[2]}" --appimage-extract "${launcher_icon#/}" >/dev/null
  test -s "squashfs-root$launcher_icon"
)

mkdir -p -- "$output"
for file in "${packages[@]}"; do
  cp -p -- "$stage/$file" "$output/$file"
done
cd -- "$output"
sha256sum -- "${packages[@]}" > SHA256SUMS
