# Anikku Harmony Preview —— 维护手册

> 给未来接手的人（或 AI 助手）看的。读完本文件和 [README](../README.md) 就能独立维护这个项目。
> 姊妹项目 [Xun2202/mihon-harmony](https://github.com/Xun2202/mihon-harmony) 用的是同一套机制，两边的手册互相参考。

## 1. 背景与目标

- 用户在 HarmonyOS NEXT 的卓易通（Android 兼容容器）里用 Anikku 看视频。官方 Anikku Preview（`app.anikku.beta`）在这台机器上
  **任何一集都下载失败**，日志见 README「修了什么」一节：ffmpeg-kit 通过 `saf:` 协议打开刚建好的 `Video.tmp` 时，
  卓易通的 `ExternalStorageProvider` 报 `Missing file`。上游 Aniyomi 在 Motorola 设备上也有同样报告（aniyomiorg/aniyomi#2126），未修。
- 卓易通的文件提供方也不支持 SAF `renameDocument`（mihon-harmony 项目已验证）。
- 用户不希望下载的视频出现在鸿蒙图库里。
- 目标：用一组补丁解决以上问题，流水线自动跟随官方稳定版，用自己的密钥签名发布，应用内更新指向本仓库。

## 2. 现状总览

| 项 | 值 |
| --- | --- |
| 上游 | `komikku-app/anikku`，稳定版 tag `vX.Y.Z`（2026-10-05 时最新 `v0.2.0`，versionCode 8，versionName `0.2.0`） |
| 构建类型 | `preview`（`applicationIdSuffix = ".beta"`，versionNameSuffix `-<提交数>`，Gradle 用 debug 密钥签名） |
| 包名 | `app.anikku.beta`——与官方 Preview 相同，签名不同，首次安装需卸载官方 Preview |
| Release tag | `v<ver>-harmony-preview.<N>` |
| versionCode / versionName | `<官方 versionCode>×100+N` / `<ver>-harmony.<N>` |
| JDK | 17（官方 `build_preview.yml` 写死，仓库无 `.java-version`） |
| 产物 | `Anikku-<tag>-arm64-v8a.apk`、`Anikku-<tag>.apk`（universal） |
| 签名证书 SHA-256 | `cf7a2adca95a7208cada9fba3b95d6aabffc57f2b7d1cc2ac80881af022bd829` |
| 密钥备份 | 私有仓库 `Xun2202/keystores` 的 `anikku-harmony/` 目录（见 §6） |

## 3. 仓库结构

```
patches/
  series                                   套用顺序, 一行一个文件名
  0001-downloads-rename-fallback-...patch  UniFile.renameToOrCopy() + 目录改名/.nomedia
  0002-downloads-mux-video-in-private-cache.patch   核心: ffmpeg 写私有缓存再复制
  0003-updater-use-harmony-fork-releases.patch      更新器指向本仓库
  0004-storage-app-private-location-option.patch    「使用应用私有目录」选项
scripts/prepare-source.sh                  套补丁 + 改版本号 (CI 与本地通用)
.github/workflows/harmony_preview.yml      编译、重签、发布
.github/workflows/check_patches.yml        只验证补丁能否套到最新稳定版 / master
docs/MAINTENANCE.md                        本文件
```

仓库里**没有** Anikku 源码；需要对照源码时在本地 clone 官方仓库。

## 4. 构建流程（`harmony_preview.yml` 做了什么）

1. 解析版本：`upstream_tag` 留空则 `gh api repos/komikku-app/anikku/releases/latest`；拼出 `harmony_version`、`release_tag`。
2. 若同名 Release 已存在且不是 `dry_run`，直接结束（定时任务每天跑，靠这一步幂等）。
3. 校验四个 Secrets 非空。
4. `git clone --branch <tag> --single-branch` 官方源码到 `$RUNNER_TEMP/anikku`（完整历史，`getCommitCount()` 要用）。
5. `scripts/prepare-source.sh`：按 `series` 顺序 `git apply --3way`，每个补丁一个 commit；把 `AppUpdateChecker.kt` 里的
   `Xun2202/anikku-harmony` 换成 `${{ github.repository }}`（fork 本仓库时自动指向 fork）；改写 `versionCode` / `versionName`。
6. JDK 17 + `gradle/actions/setup-gradle`，`./gradlew assemblePreview -Penable-updater --stacktrace`。
   不带 `-Pinclude-telemetry`，所以不需要官方的 `google-services.json` / Firebase；`client_secrets.json`（Google Drive 同步）也不需要。
7. 重签：`base64 -d` 出 jks → `zipalign -p -f 4` → `apksigner sign`（`--ks-pass env:` / `--key-pass env:`）→ `apksigner verify --print-certs`
   打印证书 SHA-256（对照 §2 的值）。只处理 `app-arm64-v8a-preview.apk` 和 `app-universal-preview.apk`。
8. 上传 artifact；生成中文 Release 说明（补丁列表取自每个 patch 的 Subject，附安装/迁移说明和 SHA-256）；
   `gh release create --target $GITHUB_SHA`，**不是 prerelease**（Anikku 更新器会过滤 prerelease）。

约 15–25 分钟（Anikku 比 Mihon 大，带 mpv/ffmpeg 原生库）。

## 5. 补丁维护（最常见的工作）

### 5.1 官方出新版，`check_patches` 或 `harmony_preview` 报补丁套不上

```bash
# 1. 拿官方新版源码
git clone --branch v0.3.0 --single-branch https://github.com/komikku-app/anikku.git /tmp/anikku && cd /tmp/anikku

# 2. 逐个套补丁, 停在失败的那一个
git am --3way /path/to/anikku-harmony/patches/0001-*.patch
git am --3way /path/to/anikku-harmony/patches/0002-*.patch   # 假设这里冲突

# 3. 解决冲突 (编辑带 <<<< 的文件, 保持补丁意图), 然后
git add -A && git am --continue
git am --3way /path/to/anikku-harmony/patches/0003-*.patch
git am --3way /path/to/anikku-harmony/patches/0004-*.patch

# 4. 重新导出整组补丁, 覆盖 patches/ 下的旧文件 (文件名要和 series 一致)
git format-patch -o /tmp/new-patches --no-signature --zero-commit v0.3.0..HEAD
# format-patch 生成的文件名是从 Subject 截断的, 重命名回 series 里的名字, 或者同步更新 series.

# 5. 提交推送到本仓库, check_patches 会自动验证; 然后手动触发 harmony_preview (可先 dry_run)
```

每个补丁的意图写在它的 commit message 里，解决冲突前先读一遍。

- 0001 与 0002 都改 `Downloader.kt`（`downloadEpisode` 收尾、`downloadVideo` / `torrentDownload` / `ffmpegDownload`）。
  上游重构下载器时两者通常要一起重做。重做 0002 时的要点：ffmpeg 输出必须是**普通文件路径**而不是 `toFFmpegString()` 的 SAF 参数；
  复制进 SAF 目录时先写 `<集>.tmp` 再 `renameToOrCopy("<集>.mkv")`，保持上游「`.tmp` 不算完成」的语义（`isDownloadSuccessful` 靠它）。
- 0003 改 `AppUpdateChecker.kt` 和 `GetApplicationRelease.kt`。上游若改成别的更新逻辑，保留三点：仓库是本仓库、
  能解析 `-harmony-preview.N`、不接受非 harmony tag。`ReleaseServiceImpl` 目前不用改（Anikku 已经列 `/releases` 并取第一个非 prerelease）。
- 0004 改 `StorageManager.kt`、`SettingsDataScreen.kt`、`StorageStep.kt` 和 `i18n-ank` 的 base / zh-rCN 字符串。
  字符串 key：`pref_storage_use_app_private`、`pref_storage_use_app_private_summary`（带一个 `%s`）、`pref_storage_use_app_private_active`。

### 5.2 加新补丁

在套完现有补丁的源码树上直接改代码并 commit（message 写清楚为什么），`git format-patch -1 --no-signature --zero-commit` 导出，
放进 `patches/`，追加到 `series` 末尾，更新 README 的补丁表。

### 5.3 验证改动但不发版

Actions → Harmony Preview → Run workflow，勾选 `dry_run`。构建完成后在该次运行的 Artifacts 里下载 APK，
用 `apksigner verify --print-certs` 确认证书 SHA-256 与 §2 一致。重签那一步的日志里也会打印。

### 5.4 正式出新版

Run workflow，`upstream_tag` 填官方 tag（留空取最新稳定版），`patch_number` 从 1 开始；同一官方版本改了补丁要重发就填 2、3……
同名 Release 已存在会直接跳过。

### 5.5 命令行操作（给 AI 助手；token 只放环境变量，不要写进任何文件或 commit）

```bash
export GH_TOKEN='<用户提供的 token>'
gh workflow run harmony_preview.yml --repo Xun2202/anikku-harmony -f upstream_tag=v0.2.0 -f patch_number=1 -f dry_run=true
gh run list --repo Xun2202/anikku-harmony --workflow harmony_preview.yml --limit 3
gh run watch <run_id> --repo Xun2202/anikku-harmony --exit-status
gh run view <run_id> --repo Xun2202/anikku-harmony --log-failed
gh release list --repo Xun2202/anikku-harmony
```

没有 `gh` 时用 REST API：`POST /repos/Xun2202/anikku-harmony/actions/workflows/harmony_preview.yml/dispatches`
（body `{"ref":"main","inputs":{...}}`），`GET /repos/Xun2202/anikku-harmony/actions/runs`。

## 6. 签名密钥

- Secrets：`SIGNING_KEY`（jks 的 Base64）、`KEY_STORE_PASSWORD`、`ALIAS`（`xun2202-anikku-harmony`）、`KEY_PASSWORD`。
  RSA 4096，JKS，store 与 key 密码不同，2026-10-05 生成，有效期到 2056-09-27。
- 签名证书 SHA-256：`cf7a2adca95a7208cada9fba3b95d6aabffc57f2b7d1cc2ac80881af022bd829`。验证产物时对这个值。
- **权威备份**：私有仓库 `Xun2202/keystores` 的 `anikku-harmony/` 目录，含 `signingkey.jks`、`signingkey.jks.b64`
  （即 `SIGNING_KEY` 的值）、`signing.json`（别名、两个密码、证书指纹）和说明 README。GitHub Secrets 只能写不能读；
  任何拿到可读该私有仓库 token 的会话都能用 `scripts/set_secrets.py anikku-harmony` 一键恢复四个 Secrets，用 `scripts/verify.py` 校验钥匙。
- **丢失密钥 = 已安装用户无法覆盖升级**。若真的丢了：重新生成密钥、更新四个 Secrets、提醒用户先在 App 内备份数据再卸载重装。

## 7. 已知问题与排错

| 现象 | 原因 / 处理 |
| --- | --- |
| `prepare-source.sh` 报 `Patch 000X ... does not apply` | 官方新版改动了补丁触及的代码。按 §5.1 rebase |
| 编译报错在 `Downloader.kt` | 补丁 0001 / 0002 的改动点被上游重构，按 §5.1 的要点重做 |
| 编译报错在 `AppUpdateChecker.kt` / `GetApplicationRelease.kt` | 上游改了更新器，重做 0003 |
| 编译报错 `Unresolved reference: pref_storage_use_app_private` | `i18n-ank` 字符串没套上（0004 的 xml hunk 冲突），检查 `i18n-ank/src/commonMain/moko-resources/base/strings.xml` |
| 重签步骤找不到 `app-arm64-v8a-preview.apk` | 上游改了 ABI split 或输出命名，看 `ls -la $apk_dir` 的输出调整文件名 |
| 下载仍然失败，日志里仍有 `Failed to open SAF id` | 说明跑的不是本构建（看 关于 页版本号应含 `harmony`）；或上游新增了别的 SAF 写入点 |
| 下载在「复制」阶段失败（日志 `Failed to create <集>.tmp` 或 `openOutputStream` 异常） | 该设备连普通 SAF 写入都不行；让用户切到「使用应用私有目录」 |
| 鸿蒙图库里能看到视频 | 用户用的是 `Documents/...` 自选目录且系统不认 `.nomedia`；切到「使用应用私有目录」 |
| Release 步骤失败 `refusing to allow a GitHub App to create or update workflow` | 有人把推 tag 的逻辑加回来了。保持 `gh release create --target $GITHUB_SHA`，不要 `git push` tag |
| 定时任务不跑 | 仓库 60 天无提交被 GitHub 暂停，到 Actions 页面手动 Enable |
| App 内检查不到更新 | 确认 Release 不是 draft / prerelease、tag 含 `-harmony-preview.`、资产文件名含 `-arm64-v8a`；App 最多每 2 天自动查一次，可在「关于」页手动检查 |
| 安装提示签名冲突 | 设备上还装着官方 Preview（同包名 `app.anikku.beta`）。先备份，卸载官方，再装 |

## 8. 不要做的事

- 不要把 token、密钥或密码提交进仓库（这是公开仓库）。
- 不要改 Release tag 格式和资产命名规则（更新器依赖）；不要把 Release 标成 prerelease。
- 不要往仓库里放 Anikku 源码快照。
- 不要上传名字里含 `-arm64-v8a` 的非 APK 资产。
- 不要改 `applicationIdSuffix`：改了会和用户已装的版本变成两个 App，SAF 授权也要重做。

## 9. 时间线

- 2026-10-05 根据用户上传的崩溃日志定位根因（ffmpeg-kit SAF open 失败 + renameDocument 不支持），写出补丁 0001–0004，
  建立本仓库和流水线；生成签名密钥并存入 `Xun2202/keystores/anikku-harmony/`，写入四个 Secrets。
