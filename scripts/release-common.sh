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

pacman_package_name() {
  printf 'dsh-linux-%s-x86_64.pkg.tar.zst\n' "$1"
}

legacy_package_names() {
  local version=$1
  printf '%s\n' "dsh-linux-$version-amd64.deb" "dsh-linux-$version-x86_64.rpm" "dsh-linux-$version-x86_64.AppImage"
}

package_names() {
  legacy_package_names "$1"
  pacman_package_name "$1"
}

asset_names() {
  package_names "$1"
  printf '%s\n' SHA256SUMS
}

find_release() {
  gh api --paginate --slurp "repos/$1/releases?per_page=100" |
    jq -c --arg tag "$2" '[.[][] | select(.tag_name == $tag)][0] // {}'
}

missing_asset_names() {
  local release=$1 names=$2
  jq -r --argjson assets "$names" '
    .assets as $uploaded |
    $assets[] as $name |
    select(any($uploaded[]; .name == $name and .state == "uploaded" and .size > 0) | not) |
    $name
  ' <<< "$release"
}

release_has_assets() {
  [[ -z $(missing_asset_names "$1" "$2") ]]
}

published_release_has_assets() {
  local release=$1 version=$2 names
  # Releases published before Arch support already have a complete checksum manifest.
  if jq -e --arg pacman "$(pacman_package_name "$version")" 'any(.assets[]?; .name == $pacman)' <<< "$release" >/dev/null; then
    names=$(asset_names "$version" | jq -Rn '[inputs]')
  else
    names=$({ legacy_package_names "$version"; printf '%s\n' SHA256SUMS; } | jq -Rn '[inputs]')
  fi
  release_has_assets "$release" "$names"
}
