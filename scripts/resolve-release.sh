#!/usr/bin/env bash
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/release-common.sh"

requested_tag=${REQUESTED_TAG:-}
if [[ -n "$requested_tag" ]]; then
  version_from_tag "$requested_tag" >/dev/null
  release=$(gh api "repos/$UPSTREAM_REPOSITORY/releases/tags/$requested_tag")
else
  release=$(gh api --paginate --slurp "repos/$UPSTREAM_REPOSITORY/releases?per_page=100" |
    jq -c '[.[][] | select(.draft == false)][0] // {}')
fi

tag=$(jq -er 'select(.draft == false) | .tag_name' <<< "$release")
version=$(version_from_tag "$tag")
prerelease=$(jq -r '.prerelease' <<< "$release")
revision=$(gh api "repos/$UPSTREAM_REPOSITORY/commits/$tag" --jq .sha)
[[ "$revision" =~ ^[0-9a-f]{40}$ ]]

rebuild=${REBUILD:-false}
[[ "$rebuild" == true || "$rebuild" == false ]] || { echo "无效的 rebuild 输入: $rebuild" >&2; exit 1; }
overwrite=${OVERWRITE:-false}
[[ "$overwrite" == true || "$overwrite" == false ]] || { echo "无效的 overwrite 输入: $overwrite" >&2; exit 1; }
should_build=true
if [[ "$rebuild" == false && "$overwrite" == false ]]; then
  existing=$(find_release "$GITHUB_REPOSITORY" "$tag")
  if [[ $(jq -r '.draft' <<< "$existing") == false ]] && published_release_has_assets "$existing" "$version"; then
    should_build=false
  fi
fi

{
  printf 'tag=%s\nversion=%s\nrevision=%s\n' "$tag" "$version" "$revision"
  printf 'prerelease=%s\nshould_build=%s\n' "$prerelease" "$should_build"
} >> "$GITHUB_OUTPUT"
printf '上游版本 %s，提交 %s，是否构建 %s\n' "$tag" "$revision" "$should_build"
