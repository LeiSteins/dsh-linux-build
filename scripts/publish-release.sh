#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/release-common.sh"

tag=${RELEASE_TAG:?}
version=$(version_from_tag "$tag")
prerelease=${RELEASE_PRERELEASE:?}
[[ "$prerelease" == true || "$prerelease" == false ]]
repo=${GITHUB_REPOSITORY:?}
revision=${GITHUB_SHA:?}
cd -- "${1:?请输入工作流产物目录}"

mapfile -t packages < <(package_names "$version")
mapfile -t assets < <(asset_names "$version")
for file in "${assets[@]}"; do
  test -s "$file"
done
# Require the checksum file to describe exactly the three installers being published.
sha256sum -- "${packages[@]}" | cmp - SHA256SUMS

title="DSH Linux $version"
notes=$(cat <<NOTES
上游版本 [\`$tag\`](https://github.com/$UPSTREAM_REPOSITORY/releases/tag/$tag) 的 DSH Linux 社区构建，适用于 x86_64。

- Debian / Ubuntu：下载 \`.deb\`，运行 \`sudo apt install ./文件名.deb\`。
- Fedora：下载 \`.rpm\`，运行 \`sudo dnf install ./文件名.rpm\`。
- 便携运行：下载 \`.AppImage\`，赋予执行权限后运行。FUSE 不可用时可加 \`--appimage-extract-and-run\`。

安装包未签名，请使用 \`SHA256SUMS\` 验证文件完整性。\`BUILD-INFO.txt\` 记录上游源码和构建提交。下载新版本安装包即可手动更新。
NOTES
)

existing=$(find_release "$repo" "$tag")
if [[ $(jq -r '.draft' <<< "$existing") == false ]]; then
  expected_assets=$(printf '%s\n' "${assets[@]}" | jq -Rn '[inputs]')
  if release_has_assets "$existing" "$expected_assets"; then
    echo "$tag 已发布。新构建保留在 Actions Artifacts。"
    exit 0
  fi
  echo "$tag 已公开，但产物不完整。请检查 Release 后再处理。" >&2
  exit 1
fi

if [[ "$existing" == '{}' ]]; then
  gh release create "$tag" --repo "$repo" --target "$revision" --draft \
    --prerelease="$prerelease" --title "$title" --notes "$notes"
  existing=$(find_release "$repo" "$tag")
fi
release_id=$(jq -er 'select(.draft == true) | .id' <<< "$existing")
gh release upload "$tag" "${assets[@]}" --repo "$repo" --clobber

uploaded=$(gh api "repos/$repo/releases/$release_id/assets?per_page=100")
for file in "${assets[@]}"; do
  digest=$(sha256sum -- "$file")
  size=$(stat -c %s -- "$file")
  if ! jq -e --arg name "$file" --arg digest "sha256:${digest%% *}" --argjson size "$size" '
    any(.[]; .name == $name and .state == "uploaded" and .size == $size and .digest == $digest)
  ' <<< "$uploaded" >/dev/null; then
    echo "GitHub 资产校验失败: $file" >&2
    exit 1
  fi
done

gh release edit "$tag" --repo "$repo" --target "$revision" --title "$title" \
  --notes "$notes" --prerelease="$prerelease" --draft=false
