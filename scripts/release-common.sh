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

package_names() {
  local version=$1
  printf '%s\n' "dsh-linux-$version-amd64.deb" "dsh-linux-$version-x86_64.rpm" "dsh-linux-$version-x86_64.AppImage"
}

asset_names() {
  package_names "$1"
  printf '%s\n' SHA256SUMS BUILD-INFO.txt
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
