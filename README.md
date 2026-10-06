# repo 分支: Release 索引

由 GitHub Actions 自动生成 (scripts/write-release-index.sh), 不要手改.

- `releases.json`: `GET /repos/Xun2202/anikku-harmony/releases?per_page=30` 的原样返回.
- `latest.json`: 其中最新的正式 Release (等价于 `/releases/latest`).

应用内更新器优先读 `https://raw.githubusercontent.com/Xun2202/anikku-harmony/repo/releases.json`,
读不到再请求 api.github.com (匿名配额每个 IP 每小时 60 次).
