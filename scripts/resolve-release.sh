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

upstream_tag=$(jq -er 'select(.draft == false) | .tag_name' <<< "$release")
upstream_version=$(version_from_tag "$upstream_tag")
revision=$(gh api "repos/$UPSTREAM_REPOSITORY/commits/$upstream_tag" --jq .sha)
[[ "$revision" =~ ^[0-9a-f]{40}$ ]]

rebuild=${REBUILD:-false}
[[ "$rebuild" == true || "$rebuild" == false ]] || { echo "无效的 rebuild 输入: $rebuild" >&2; exit 1; }
overwrite=${OVERWRITE:-false}
[[ "$overwrite" == true || "$overwrite" == false ]] || { echo "无效的 overwrite 输入: $overwrite" >&2; exit 1; }
release_revision=${RELEASE_REVISION:-}
if [[ -n "$release_revision" ]]; then
  validate_release_revision "$release_revision"
fi

releases=$(gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/releases?per_page=100")
if [[ -z "$release_revision" ]]; then
  release_revision=$(jq -r --arg tag "$upstream_tag" '
    [.[][].tag_name | select(startswith($tag + "-")) | ltrimstr($tag + "-") | select(test("^[1-9][0-9]*$"))]
    | sort_by(length, .) | last // empty
  ' <<< "$releases")
  if [[ -z "$release_revision" ]]; then
    legacy=$(find_release "$upstream_tag" <<< "$releases")
    # Legacy RPM and Arch packages already used package revision 1.
    if [[ $(jq -r '.draft' <<< "$legacy") == false ]]; then
      release_revision=2
    else
      release_revision=1
    fi
  elif [[ "$overwrite" == false ]]; then
    # Keep the existing checksums and packages intact when introducing the second architecture.
    previous=$(find_release "$upstream_tag-$release_revision" <<< "$releases")
    previous_version=$upstream_version-$release_revision
    x64_assets=$({ package_names "$previous_version" x86_64; printf '%s\n' SHA256SUMS; } | jq -Rn '[inputs]')
    arm_packages=$(package_names "$previous_version" aarch64)
    arm_assets=$(jq -Rn '[inputs]' <<< "$arm_packages")
    if [[ $(jq -r '.draft' <<< "$previous") == false \
      && -z $(missing_asset_names "$previous" "$x64_assets") \
      && $(missing_asset_names "$previous" "$arm_assets") == "$arm_packages" ]]; then
      release_revision=$((release_revision + 1))
    fi
  fi
fi
release_tag=$upstream_tag-$release_revision
version=$upstream_version-$release_revision

should_build=true
promote_existing=false
if [[ "$rebuild" == false && "$overwrite" == false ]]; then
  existing=$(find_release "$release_tag" <<< "$releases")
  if [[ $(jq -r '.draft' <<< "$existing") == false ]] && release_has_assets "$existing" "$version"; then
    should_build=false
    if jq -e '.prerelease == true' <<< "$existing" >/dev/null; then
      promote_existing=true
    fi
  fi
fi

{
  printf 'upstream_tag=%s\nrelease_revision=%s\nversion=%s\nrevision=%s\n' "$upstream_tag" "$release_revision" "$version" "$revision"
  printf 'should_build=%s\npromote_existing=%s\n' "$should_build" "$promote_existing"
} >> "$GITHUB_OUTPUT"
printf '上游标签 %s，发布标签 %s，提交 %s，是否构建 %s\n' "$upstream_tag" "$release_tag" "$revision" "$should_build"
