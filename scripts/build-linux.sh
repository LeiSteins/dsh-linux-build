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

export DSH_CLIENT_TITLE='Deepseek Harness'
export DSH_DESKTOP_BUILD_VERSION="$version"
export DSH_DESKTOP_APP_ID=io.github.leisteins.dshlinux
export DSH_DESKTOP_TARGET_PLATFORM=linux DSH_DESKTOP_TARGET_ARCH=x64 DSH_DESKTOP_UNSIGNED=1
export DSH_DESKTOP_BUILD_COMMIT="$revision" DSH_DESKTOP_BUILD_DIRTY=1 DSH_TELEMETRY_DISABLED=1

if ! git apply --check "$repo/patches/linux-x64.patch"; then
  echo "Linux 补丁需要同步至 $tag。" >&2
  exit 1
fi
git apply "$repo/patches/linux-x64.patch"
install -m 644 "$repo/packaging/electron-builder-linux.config.mjs" apps/desktop/electron-builder-linux.config.mjs
install -m 644 "$repo/packaging/smoke-linux.mts" apps/desktop/scripts/smoke-linux.mts

stage=$(mktemp -d)
trap 'rm -rf -- "$stage"' EXIT

pnpm install --frozen-lockfile
pnpm run build:artifacts --profile local

# Follow upstream package-target.ts to prepare the local package closure and embedded runtimes.
packed="$upstream/apps/desktop/.desktop-build/targets/linux-x64/packed"
mkdir -p "$packed/dsh" "$packed/vendor" "$packed/landlock"
pnpm exec tsx apps/desktop/scripts/pack-local-packages.ts --out "$packed/dsh" --concurrency 4
pnpm --dir apps/desktop-host pack --pack-destination "$packed/dsh"
pnpm run release:pack --family vendor --out "$packed/vendor" --concurrency 4
pnpm --dir native/system run build:ts
pnpm --dir native/system/packages/entry pack --pack-destination "$packed/landlock"
pnpm --dir apps/desktop run prepare:runtime
pnpm --dir apps/desktop run prepare:packages
pnpm --dir apps/desktop run prepare:dsh 2>&1 | sed -uE 's/([?&]token=)[^[:space:]&]+/\1[redacted]/g'

builder=(pnpm --dir apps/desktop exec electron-builder --config electron-builder-linux.config.mjs --x64 --publish never "--config.directories.output=$stage")
"${builder[@]}" --linux --dir
cmp apps/desktop/resources/icon-windows.png "$stage/linux-unpacked/resources/icon.png"
ELECTRON_RUN_AS_NODE=1 "$stage/linux-unpacked/dsh-linux" -e '
  const [archive, version] = process.argv.slice(1);
  const { version: packagedVersion } = JSON.parse(require("node:fs").readFileSync(archive + "/package.json", "utf8"));
  require("node:assert/strict").equal(packagedVersion, version);
' "$stage/linux-unpacked/resources/app.asar" "$version"
pnpm exec tsx apps/desktop/scripts/smoke-linux.mts "$stage/linux-unpacked/resources" 2>&1 |
  sed -uE 's/([?&]token=)[^[:space:]&]+/\1[redacted]/g'
"${builder[@]}" --linux deb rpm AppImage --prepackaged "$stage/linux-unpacked"

mapfile -t packages < <(package_names "$version")
for file in "${packages[@]}"; do
  test -s "$stage/$file"
done
native_version=${version//-/\~}
[[ $(dpkg-deb -f "$stage/${packages[0]}" Architecture) == amd64 ]]
[[ $(dpkg-deb -f "$stage/${packages[0]}" Version) == "$native_version" ]]
mkdir "$stage/rpmdb"
[[ $(rpm --dbpath "$stage/rpmdb" -qp --queryformat '%{ARCH} %{VERSION}' "$stage/${packages[1]}") == "x86_64 $native_version" ]]
mkdir "$stage/appimage-test"
(
  cd "$stage/appimage-test"
  "$stage/${packages[2]}" --appimage-extract dsh-linux.desktop >/dev/null
  grep -Fx "Name=$DSH_CLIENT_TITLE" squashfs-root/dsh-linux.desktop
  grep -Fx 'Icon=dsh-linux' squashfs-root/dsh-linux.desktop
)

mkdir -p -- "$output"
for file in "${packages[@]}"; do
  cp -p -- "$stage/$file" "$output/$file"
done
cd -- "$output"
sha256sum -- "${packages[@]}" > SHA256SUMS
{
  printf 'Upstream repository: https://github.com/%s\n' "$UPSTREAM_REPOSITORY"
  printf 'Application: %s\nVersion: %s\n' "$DSH_CLIENT_TITLE" "$version"
  printf 'Upstream tag: %s\nUpstream commit: %s\n' "$tag" "$revision"
  printf 'Packaging commit: %s\n' "$(git -C "$repo" rev-parse HEAD)"
  if [[ -n ${GITHUB_RUN_ID:-} ]]; then
    printf 'Workflow run: %s/%s/actions/runs/%s\n' "$GITHUB_SERVER_URL" "$GITHUB_REPOSITORY" "$GITHUB_RUN_ID"
  fi
  printf 'Architecture: x86_64\nBuild: unsigned community packages\n'
} > BUILD-INFO.txt
