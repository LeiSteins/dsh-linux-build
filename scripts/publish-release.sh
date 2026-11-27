#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/release-common.sh"

tag=${RELEASE_TAG:?}
version=$(version_from_tag "$tag")
overwrite=${OVERWRITE:-false}
[[ "$overwrite" == true || "$overwrite" == false ]] || { echo "无效的 overwrite 输入: $overwrite" >&2; exit 1; }
repo=${GITHUB_REPOSITORY:?}
existing=$(find_release "$repo" "$tag")
if [[ "$overwrite" == false && $(jq -r '.draft' <<< "$existing") == false ]] && published_release_has_assets "$existing" "$version"; then
  if jq -e '.prerelease == true' <<< "$existing" >/dev/null; then
    gh release edit "$tag" --repo "$repo" --prerelease=false
    echo "$tag 已转为正式发布。"
  else
    echo "$tag 已正式发布。"
  fi
  exit 0
fi

revision=${GITHUB_SHA:?}
upstream_revision=${UPSTREAM_REVISION:?}
[[ "$upstream_revision" =~ ^[0-9a-f]{40}$ ]]
cd -- "${1:?请输入工作流产物目录}"

mapfile -t packages < <(package_names "$version")
mapfile -t assets < <(asset_names "$version")
for file in "${assets[@]}"; do
  test -s "$file"
done
# Require the checksum file to describe exactly the installers being published.
sha256sum -- "${packages[@]}" | cmp - SHA256SUMS

verify_uploaded_assets() {
  local uploaded=$1 file digest size
  shift
  for file in "$@"; do
    digest=$(sha256sum -- "$file")
    size=$(stat -c %s -- "$file")
    if ! jq -e --arg name "$file" --arg digest "sha256:${digest%% *}" --argjson size "$size" '
      any(.[]; .name == $name and .state == "uploaded" and .size == $size and .digest == $digest)
    ' <<< "$uploaded" >/dev/null; then
      echo "GitHub 资产校验失败: $file" >&2
      return 1
    fi
  done
}

title="DSH Linux $version"
notes=$(cat <<NOTES
上游版本 [\`$tag\`](https://github.com/$UPSTREAM_REPOSITORY/releases/tag/$tag) 的 DSH Linux 社区构建，适用于 x86_64。

- Debian / Ubuntu：下载 \`.deb\`，运行 \`sudo apt install ./文件名.deb\`。
- Fedora：下载 \`.rpm\`，运行 \`sudo dnf install ./文件名.rpm\`。
- Arch Linux：下载 \`.pkg.tar.zst\`，运行 \`sudo pacman -U ./文件名.pkg.tar.zst\`。
- 便携运行：下载 \`.AppImage\`，赋予执行权限后运行。FUSE 不可用时可加 \`--appimage-extract-and-run\`。

安装包未签名，请使用 \`SHA256SUMS\` 验证文件完整性。下载新版本安装包即可手动更新。

[上游源码提交](https://github.com/$UPSTREAM_REPOSITORY/commit/$upstream_revision) · [打包提交](https://github.com/$repo/commit/$revision)
NOTES
)
if [[ -n ${GITHUB_RUN_ID:-} ]]; then
  notes+=" · [构建日志](${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/$GITHUB_RUN_ID)"
fi

expected_assets=$(printf '%s\n' "${assets[@]}" | jq -Rn '[inputs]')
if [[ $(jq -r '.draft' <<< "$existing") == false ]]; then
  if [[ "$overwrite" == true ]]; then
    # Hide the release while replacing large assets so no mix of old and new files is served.
    echo "$tag 已公开，切换为草稿后覆盖全部资产。"
    gh release edit "$tag" --repo "$repo" --draft
    gh release upload "$tag" "${assets[@]}" --repo "$repo" --clobber
    release_id=$(jq -er '.id' <<< "$existing")
  else
    missing=$(missing_asset_names "$existing" "$expected_assets")
    mapfile -t missing_files <<< "$missing"
    uploaded=$(jq -c '.assets' <<< "$existing")
    mapfile -t retained_files < <(jq -r --argjson expected "$expected_assets" '
      .[] | .name as $name | select(.state == "uploaded" and .size > 0 and ($expected | index($name)) != null) | .name
    ' <<< "$uploaded")
    if ! verify_uploaded_assets "$uploaded" "${retained_files[@]}"; then
      echo "已发布的文件与本次构建不同，请使用原构建产物补传，或明确选择 overwrite。" >&2
      exit 1
    fi
    echo "$tag 已公开但缺少资产，尝试补传：${missing_files[*]}"
    gh release upload "$tag" "${missing_files[@]}" --repo "$repo" --clobber
    release_id=$(jq -er '.id' <<< "$existing")
  fi
else
  if [[ "$existing" == '{}' ]]; then
    gh release create "$tag" --repo "$repo" --target "$revision" --draft \
      --title "$title" --notes "$notes"
    # The releases list can briefly omit a draft immediately after creation.
    for delay in 1 2 4 8 16; do
      if existing=$(find_release "$repo" "$tag") && jq -e '.draft == true' <<< "$existing" >/dev/null; then
        break
      fi
      sleep "$delay"
    done
  fi
  if ! release_id=$(jq -er 'select(.draft == true) | .id' <<< "$existing"); then
    echo "无法读取 $tag 的 Release 草稿。重新运行发布作业可继续使用已有构建产物。" >&2
    exit 1
  fi
  gh release upload "$tag" "${assets[@]}" --repo "$repo" --clobber
fi

uploaded=$(gh api "repos/$repo/releases/$release_id/assets?per_page=100")
verify_uploaded_assets "$uploaded" "${assets[@]}"

gh release edit "$tag" --repo "$repo" --target "$revision" --title "$title" \
  --notes "$notes" --prerelease=false --draft=false
