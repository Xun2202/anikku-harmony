#!/usr/bin/env bash
# 把 GitHub「列出 Releases」接口的返回原样写进本仓库的 repo 分支 (releases.json, 另附 latest.json 和说明).
# 应用内更新器优先从 raw.githubusercontent.com 读这个文件: 它是普通 CDN, 没有匿名 api.github.com
# 「每个出口 IP 每小时 60 次」的配额 (手机走运营商 NAT / 代理时这 60 次是和别人共用的, 很快被用完,
# App 里表现为「HTTP error 403」); 读不到时 App 再退回 api.github.com.
#
# 调用方: harmony_preview.yml (创建 Release 之后) 和 release_index.yml (Release 被手动增删改时 / 手动触发).
# 用法:   scripts/write-release-index.sh [owner/repo]   (默认 $GITHUB_REPOSITORY)
# 依赖:   gh (用 GH_TOKEN 调接口), jq, git (推送用当前仓库的凭据; Actions 里 actions/checkout 已配好).
set -euo pipefail

repo="${1:-${GITHUB_REPOSITORY:-}}"
[[ -n "$repo" ]] || { echo "Usage: $0 <owner/repo>" >&2; exit 1; }
branch="repo"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
cleanup() {
  cd /
  if [[ -d "$work/wt" ]]; then
    git -C "$repo_root" worktree remove --force "$work/wt" 2>/dev/null || true
  fi
  rm -rf "$work"
  git -C "$repo_root" worktree prune 2>/dev/null || true
}
trap cleanup EXIT

# 和 App 请求的接口一致 (三个 App 都只看最近 30 个 Release), 原样保存, 不裁剪字段.
gh api -H "Accept: application/vnd.github+json" "repos/$repo/releases?per_page=30" > "$work/releases.json"
jq -e 'type == "array"' "$work/releases.json" > /dev/null
# /releases/latest 的等价物: 最新的非 draft、非 prerelease 的 Release; 一个都没有时为 null.
jq '[.[] | select((.draft or .prerelease) | not)] | first' "$work/releases.json" > "$work/latest.json"
latest_tag="$(jq -r '.[0].tag_name // "no releases"' "$work/releases.json")"

cat > "$work/README.md" <<EOF
# repo 分支: Release 索引

由 GitHub Actions 自动生成 (scripts/write-release-index.sh), 不要手改.

- \`releases.json\`: \`GET /repos/$repo/releases?per_page=30\` 的原样返回.
- \`latest.json\`: 其中最新的正式 Release (等价于 \`/releases/latest\`).

应用内更新器优先读 \`https://raw.githubusercontent.com/$repo/$branch/releases.json\`,
读不到再请求 api.github.com (匿名配额每个 IP 每小时 60 次).
EOF

write_once() {
  local wt="$work/wt"
  rm -rf "$wt"
  git -C "$repo_root" worktree prune
  if git -C "$repo_root" fetch --quiet origin "refs/heads/$branch:refs/remotes/origin/$branch" 2>/dev/null; then
    git -C "$repo_root" worktree add --quiet --detach "$wt" "origin/$branch"
  else
    echo "Branch $branch does not exist yet; creating it."
    git -C "$repo_root" worktree add --quiet --detach "$wt"
    git -C "$wt" checkout --quiet --orphan "release-index-$$"
    git -C "$wt" rm -rfq --cached . 2>/dev/null || true
    find "$wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
  fi

  cp "$work/releases.json" "$work/latest.json" "$work/README.md" "$wt/"
  git -C "$wt" add -A
  if git -C "$wt" diff --cached --quiet; then
    echo "Release index already up to date ($latest_tag)."
    return 0
  fi
  git -C "$wt" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "release index: $latest_tag"
  if git -C "$wt" push --quiet origin "HEAD:refs/heads/$branch"; then
    echo "Release index pushed to $branch ($latest_tag)."
    return 0
  fi
  return 1
}

# 两个 workflow 可能同时写 (发版 + 手动改 Release); 被拒绝就重新基于远端再写一次.
for attempt in 1 2 3; do
  if write_once; then
    exit 0
  fi
  echo "Push to $branch rejected (attempt $attempt); retrying on top of the remote branch." >&2
  git -C "$repo_root" worktree remove --force "$work/wt" 2>/dev/null || true
  sleep $((attempt * 5))
done
echo "Could not update the release index on $branch." >&2
exit 1
