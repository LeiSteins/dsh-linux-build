#!/usr/bin/env bash

UPSTREAM_REPOSITORY=deepseek-ai/deepseek-harness

version_from_tag() {
  local tag=$1
  if [[ ! "$tag" =~ ^dsh-v([0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*)?)$ ]]; then
    echo "不支持的上游版本标签: $tag" >&2
    return 1
  fi
  printf '%s\n' "${BASH_REMATCH[1]}"
}

validate_release_revision() {
  if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
    echo "发布修订号须为正整数且不能带前导零: $1" >&2
    return 1
  fi
}

pacman_version() {
  local version=$1 prerelease
  if [[ "$version" == *-* ]]; then
    prerelease=${version#*-}
    # libalpm sorts an attached letter suffix before the unadorned version.
    printf '%spre.%s\n' "${version%%-*}" "${prerelease//-/_}"
  else
    printf '%s\n' "$version"
  fi
}

package_names() {
  local version=$1 arch=$2 extension
  for extension in deb rpm AppImage pkg.tar.zst; do
    printf 'dsh-linux-%s-%s.%s\n' "$version" "$arch" "$extension"
  done
}

release_package_names() {
  package_names "$1" amd64
  package_names "$1" arm64
}

asset_names() {
  release_package_names "$1"
  printf '%s\n' SHA256SUMS
}

find_release() {
  jq -c --arg tag "$1" '[.[][] | select(.tag_name == $tag)][0] // {}'
}

missing_asset_names() {
  local release=$1 names=$2
  jq -r --argjson assets "$names" '
    .assets as $uploaded |
    $assets[] as $name |
    select(any($uploaded[]?; .name == $name and .state == "uploaded" and .size > 0) | not) |
    $name
  ' <<< "$release"
}

release_has_assets() {
  local names missing
  names=$(asset_names "$2" | jq -Rn '[inputs]') || return
  missing=$(missing_asset_names "$1" "$names") || return
  [[ -z "$missing" ]]
}

release_has_legacy_names() {
  jq -e --arg prefix "dsh-linux-$2-" '
    any(.assets[]?.name; startswith($prefix + "x86_64.") or startswith($prefix + "aarch64."))
  ' <<< "$1" >/dev/null
}
