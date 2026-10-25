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
  0005-build-flexible-adapter-from-maven-central.patch  临时回迁: FlexibleAdapter 改从 Maven Central 取
  0006-downloads-hide-videos-from-gallery-...patch       视频存成 <集>.mkv.anikku, 鸿蒙图库不收录 + 设置开关/批量改名
  0007-downloads-share-downloads-across-entries-by-url.patch  同一来源内按 url 共用已下载的视频
  0008-updater-in-screen-download-progress-and-install.patch  更新页面留在原地显示进度 + 「安装」按钮 (Mihon 流程)
  0009-downloads-background-keep-alive-silent-audio.patch     后台保活: 静音 AudioTrack + 唤醒锁, 下载服务 mediaPlayback
  0010-downloads-notification-speed-and-progress.patch        下载通知统一为 Animeko 样式: 数量标题 + 速度/进度 + 进度条
  0011-updater-no-background-auto-download-and-apk-cleanup.patch  去掉后台自动下载 (卡住更新页的元凶) + 启动时删已安装的 update.apk
  0012-about-match-mihon-update-ui.patch                        去掉装完后的「已更新至」对话框, 「更新日志」改开 Release 网页 (与 Mihon 一致)
  0013-updater-regular-work-request.patch                       更新下载改普通 WorkManager 任务 (卓易通不派发 expedited 任务) + 更新页看门狗
  0014-updater-release-mirror.patch                             检查更新先读 repo 分支的 releases.json 镜像, 再退回 api.github.com; 修 lastChecked
  0015-library-panorama-grid-fit-wide-covers.patch              书架「全景松散网格」按 3:2 横版排格子 (fitToPanoramaCover = true, 与浏览页一致)
  0016-downloads-finalize-with-fewer-saf-copies-and-error-reasons.patch  下载收尾少抄两遍视频 (直接写最终名 + 标记, 目录用 moveDocument/合并), 队列显示失败原因
  0017-updater-stable-release-notes-while-downloading.patch   更新页 remember { GFMFlavourDescriptor() } (说明文字下载时不再闪烁); ffmpeg 原因去掉 [tcp @ 0x…] 前缀
  0018-downloads-never-skip-silently-reuse-or-replace-leftover-folders.patch  点「下载」不再被静默跳过: 按缓存判断已下载, 残留目录完整则登记/不完整则删, Snackbar 说明原因
  0019-crash-log-filter-harmony-noise-and-keep-app-log.patch  崩溃日志过滤卓易通图形层噪音 + 附应用自己的最近 600 行日志 (HarmonyLogBuffer)
  0020-library-panorama-grid-staggered-and-wider-auto-columns.patch  全景松散网格改瀑布流 (LazyVerticalStaggeredGrid, 横竖混排不留空) + 自动列宽 168 dp + 封面比例缓存
  0021-browse-panorama-grids-staggered-and-wider-auto-columns.patch   浏览页 / 相关作品页的全景网格同 0020 (瀑布流 + 168 dp), 列数偏好用 CountedGridCells 传递
  0022-library-panorama-compact-grid-display-mode.patch           显示模式「全景紧凑网格」(与 Mihon 0015 同源)
  0023-presentation-staggered-fast-scroller-steady-thumb.patch    瀑布流快速滚动条拇指不抽搐 (与 Mihon 0016 估算段逐字相同)
  0024-updater-pick-highest-harmony-version.patch                 getLatest() 按版本号取最大而不是列表第一项 (与 Mihon 0017 同源)
  0025-library-panorama-stable-cell-shapes.patch                   全景格子形状持久化 + 滑动中不改排版 (PanoramaCoverShapes.kt 与 Mihon 0018 逐字节相同)
  0026-presentation-cover-asyncimage-smooth-grids.patch            封面改 AsyncImage，转圈延迟 400 ms；来源角标按 source.id 记住 (Mihon 不适用)
  0027-library-panorama-settle-debounce-browse-prefetch.patch      全景网格连续 300 ms 不滚动才算停下 + 浏览页提前学封面形状 (PanoramaCoverShapes.kt 与 Mihon 0019 逐字节相同)
  0028-presentation-staggered-scroller-stable-thumb.patch           瀑布流快速滚动条拇指不再每行回跳 (StaggeredGridEstimate 段与 Mihon 0020 逐字节相同)
  0029-download-quality-separate-from-playback.patch                设置 → 下载 →「下载画质」与播放分开 (harmony_download_quality, 默认最高可用)
  0030-presentation-panorama-masonry-reading-order.patch            自建全景瀑布流: 阅读顺序容差 + 列数变化当帧重排 (PanoramaMasonry*.kt 与 Mihon 0021 逐字节相同)
  0031-presentation-panorama-auto-columns-span.patch                 全景自动列适合竖封面; 横封面 ≥3 列时跨两列 (与 Mihon 0023 同源)
  0032-presentation-panorama-scroll-anchor-by-key.patch              全景滚动锚点按 key 存, 列表加载完整后再恢复 (书架/浏览/相关作品; 与 Mihon 0024 同源)
  0033-presentation-panorama-layout-epoch.patch                      全景布局世代: 内容不变时跳过逐项计算 (与 Mihon 0025 逐字节相同)
  0034-library-panorama-cover-shapes-versioned.patch                 封面形状表按版本通知, 不再整表订阅 (阈值名 RatioSwitchToPanorama; 与 Mihon 0026 同源)
  0035-presentation-fast-scroller-hold-grab.patch                    滚动条按下即抓, 按住不淡出 (另含剧集网格 IrregularVerticalGridFastScroller; 与 Mihon 0027 同源)
  0036-presentation-panorama-tiered-auto-columns.patch                自动列宽按网格宽分档 Tiered (常量在 PanoramaGrid.kt; 与 Mihon 0028 同源)
  0037-presentation-fast-scroller-snapshotflow.patch                  瀑布流与剧集网格滚动条改为单个 LaunchedEffect + snapshotFlow (与 Mihon 0029 同源)
  0038-presentation-panorama-shaped-columns.patch                    全景自动列 Shaped: 面积大致恒定 (三个共享文件与 Mihon 0030 逐字节相同)
  0039-library-panorama-shape-mode.patch                              形状模式 Tall/Wide/Unknown (PanoramaShapeMode.kt 在 app 层; 阈值名 RatioSwitchToPanorama; 相关作品两套; 与 Mihon 0031 同源)
  0040-presentation-fast-scroller-thumb-hitbox.patch                   滚动条热区收回为绘制宽度 (另含剧集网格 IrregularVerticalGridFastScroller; 与 Mihon 0032 同源)
  0041-presentation-panorama-scroll-trace.patch                      全景滑动诊断: 崩溃日志附最近 400 条轨迹, 不改滚动行为 (PanoramaScrollTrace.kt / PanoramaMasonry.kt 与 Mihon 0033 逐字节相同; 只记全景网格, 剧集网格不记)
  0042-presentation-panorama-exact-scroll-delta.patch               全景滚动没碰到两端时返回精确 delta (PanoramaMasonry.kt 与 Mihon 0034 逐字节相同; 0041 诊断日志保留)
  0043-presentation-fast-scroller-hold-to-grab.patch               滚动条: 按在拇指上立即抓, 拇指旁 20 dp 按住 120 ms 才抓 (四根滚动条; 与 Mihon 0035 同源)
  0044-app-scroll-performance-recorder.patch                        滚动性能记录器 + 「记录」按钮导出脱敏文件 (HarmonyFramePerf.kt 等与 Mihon 0036 逐字节相同)
scripts/prepare-source.sh                  套补丁 + 改版本号 (CI 与本地通用)
scripts/write-release-index.sh             把 Releases 接口返回写到 repo 分支 (releases.json / latest.json)
.github/workflows/harmony_preview.yml      编译、重签、发布, 然后写 Release 索引
.github/workflows/release_index.yml        Release 被手动增删改时重写索引 (也可手动触发)
.github/workflows/check_patches.yml        只验证补丁能否套到最新稳定版 / master
docs/MAINTENANCE.md                        本文件
```

仓库里**没有** Anikku 源码；需要对照源码时在本地 clone 官方仓库。

孤儿分支 **`repo`** 只放 `write-release-index.sh` 生成的 `releases.json` / `latest.json` / `README.md`（`GET /repos/<repo>/releases` 全部分页的条目，按 `created_at` 倒序取前 30 条），
应用内更新器（0014 起）优先从 `https://raw.githubusercontent.com/Xun2202/anikku-harmony/repo/releases.json` 读它，不要手改、不要往里放别的东西。

## 4. 构建流程（`harmony_preview.yml` 做了什么）

1. 解析版本：`upstream_tag` 留空则 `gh api repos/komikku-app/anikku/releases/latest`；拼出 `harmony_version`、`release_tag`。
2. 若同名 Release 已存在且不是 `dry_run`，直接结束（定时任务每天跑，靠这一步幂等）。同一段「Resolve release version」里，非 `dry_run` 且目标 tag 还不存在时，取本仓所有 `vX.Y.Z-harmony-preview.N`，按「上游版本.N」做 `sort -V`，比已发布最高的旧就 `exit 1`，日志「installs would be a downgrade」。已存在的 tag 仍走原来的 skip，每天定时 run 不会因此变红。与 mihon-harmony 同一处（Mihon 提交 `fd1835633`，本仓 `af6652f`）。
3. 校验四个 Secrets 非空。
4. `git clone --branch <tag> --single-branch` 官方源码到 `$RUNNER_TEMP/anikku`（完整历史，`getCommitCount()` 要用）。
5. `scripts/prepare-source.sh`：按 `series` 顺序 `git apply --3way`，每个补丁一个 commit（能 `--reverse` 干净套回去的补丁
   视为上游已合入，自动跳过——回迁类补丁靠这个在新版上自然失效）；把 `AppUpdateChecker.kt` 里的
   `Xun2202/anikku-harmony` 换成 `${{ github.repository }}`（fork 本仓库时自动指向 fork）；改写 `versionCode` / `versionName`。
6. JDK 17 + `gradle/actions/setup-gradle`，`./gradlew assemblePreview -Penable-updater --stacktrace`。
   不带 `-Pinclude-telemetry`，所以不需要官方的 `google-services.json` / Firebase；`client_secrets.json`（Google Drive 同步）也不需要。
7. 重签：`base64 -d` 出 jks → `zipalign -p -f 4` → `apksigner sign`（`--ks-pass env:` / `--key-pass env:`）→ `apksigner verify --print-certs`
   打印证书 SHA-256（对照 §2 的值）。只处理 `app-arm64-v8a-preview.apk` 和 `app-universal-preview.apk`。
8. 上传 artifact；生成中文 Release 说明（补丁列表取自每个 patch 的 Subject，附安装/迁移说明和 SHA-256）；
   `gh release create --target $GITHUB_SHA`，**不是 prerelease**（Anikku 更新器会过滤 prerelease）。
9. `scripts/write-release-index.sh`：`gh api --paginate repos/<repo>/releases` 的条目按 `created_at` 倒序取前 30 条存成 `releases.json`（字段原样；接口顺序不按创建时间），`jq` 取出最新正式版存成 `latest.json`，
   连同说明 `README.md` 提交到孤儿分支 `repo`（已存在则在远端分支之上提交；被并发推送拒绝就重取重写，最多 3 次）。
   `GITHUB_TOKEN` 创建的 Release 不触发 `release` 事件，所以必须在这里写；手动改 Release 时由 `release_index.yml` 兜底。

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
- 0005 只改 `gradle/libs.versions.toml` 一行，是上游 komikku-app/anikku@c44eb6f2d5 的原样回迁：JitPack 对
  `com.github.arkon.FlexibleAdapter:flexible-adapter:c8013533` 的构建状态自 2026-02 起就是 Error，没有 Gradle 缓存的机器
  （比如本仓库第一次跑 CI）会在 `:app:mergePreviewNativeLibs` 报 `Could not find`。官方 CI 没炸只是因为 Actions 里有旧缓存。
  下一个包含 c44eb6f2d5 的官方稳定版（v0.2.0 之后）上它会被 `prepare-source.sh` 自动跳过，届时直接从 `series` 和 `patches/` 删掉即可。
- 0006 改 `Downloader.kt`（`copyIntoDownloadDir` 的最终文件名、常量 `HIDDEN_VIDEO_SUFFIX = ".anikku"`）、`DownloadManager.kt`
  （`buildVideo` 的文件过滤、新增 `applyGalleryVisibilityToDownloads()`）、`DownloadPreferences.kt`（`hideDownloadedVideosFromGallery()`，默认 true）、
  `SettingsDownloadScreen.kt` 和 `i18n-ank` 字符串。重做要点：**只改文件名，不改目录名**——`DownloadCache` 按 `<集>` 目录名判断“已下载”，
  目录名一变缓存就全失效；续传检测 `startsWith("$filename.mkv")` 与 `isDownloadSuccessful`（只排除 `.tmp`）天然兼容后缀，
  上游若改成精确匹配 `.mkv` 要同步放宽。为什么是改扩展名而不是 `.nomedia`：鸿蒙媒体扫描不认 `.nomedia`，只按扩展名归类。
- 0007 改 `episodes.sq`（`getEpisodesByUrls`，`IN :episodeUrls`）、`ChapterRepository(.Impl)`（`getChaptersByUrls`，每 500 个 url 一批）、
  `DownloadPreferences.kt`（`shareDownloadsAcrossEntries()`）、`DownloadManager.kt`（`SharedDownload` / `findSharedDownloads` / `buildVideoOrShared`，
  构造函数新增 `ChapterRepository`、`GetManga` 两个带默认值的注入参数）、`MangaScreenModel.toChapterListItems`（改成 `suspend`，
  两个调用点本来就在协程里）、`EpisodeLoader`（`isDownloadOrShared`、`getHostersOnDownloaded` 改 `suspend`）和 `PlayerViewModel.downloadNextEpisodes`。
  语义：只在**同一来源**内共用，本地源与合并条目不参与；“共用来的”集显示为已下载但文件不归它，删除是空操作。
  上游若把 `Chapter.url` 改名或把 `toChapterListItems` 改成非挂起上下文，这里要跟着改。
- 0008 改 `ui/more/NewUpdateScreen.kt`（改用 `rememberScreenModel`）、新文件 `ui/more/NewUpdateScreenModel.kt`（Voyager `StateScreenModel`，
  订阅 `workManager.getWorkInfosByTagFlow(TAG)`；任务刚入队、还没有进度数据时按「下载中」显示，避免按钮闪回「下载」；
  `onDispose` 时若仍在下载则 `stop`）、`presentation/more/NewUpdateScreen.kt`
  （新增 `stage` / `downloadProgress` 参数，按钮文案随阶段变化，`canAccept`）、`AppUpdateDownloadJob.kt`（`TAG`/`PROGRESS` 公开、
  `updateApk()`、`doWork` 开头先 `setProgress(PROGRESS=0, url)`、下载中 `setProgressAsync`、`Result.success/failure` 带输出数据、
  `interactive` 输入跳过 `startInstalling`）和 `i18n-ank`
  的 `update_downloading_with_progress`。`ComingUpdatesScreen`（KMK 的“即将到来的更新”页）没动，仍是旧流程。
  上游若把更新页改成别的导航框架，照 Mihon 的 `NewUpdateScreenModel` 重做即可。
- 0009 与 mihon-harmony 0005 同源：新文件 `util/system/BackgroundKeepAlive.kt` 无依赖；`DownloadJob.kt` / `LibraryUpdateJob.kt` 在
  `setForegroundSafely()` 之后一行 `acquireForCurrentJob`，`DownloadJob.getForegroundInfo()` 开关开时返回 `FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK`；
  manifest 加 `FOREGROUND_SERVICE_MEDIA_PLAYBACK` 权限、`SystemForegroundService` 类型 `dataSync|mediaPlayback`；`DownloadPreferences.keepAliveInBackground()`
  （默认 true）、`SettingsDownloadScreen` 开关、`i18n-ank` 两条字符串。rebase 时通常只需重新定位插入点。
- 0010 与 mihon-harmony 0006 同源：新文件 `data/download/DownloadSpeedMeter.kt` 与 Mihon 的逐字节相同（改一份要同步另一份）；
  `DownloadNotifier.onProgressChange()` 整段重写（签名多了 `remaining: Int`，`onPaused()` / `onComplete()` 各加一行复位）；
  `Downloader.kt` 四处：`launchDownloaderJob()` 开头的 `DownloadSpeedMeter.reset()` + 1 Hz 定时器、`getOrDownloadVideoFile()` 里
  删掉上游 50 ms 的 `progressJob` 轮询并给首次调用传 `remainingDownloads()`、`ffmpegDownload()` 的 `statCallback` 里按 `s.size`
  增量喂速度、新增 `remainingDownloads()`；`i18n-ank` 两条字符串 + 新建的 `plurals.xml`（base / zh-rCN，该模块此前没有复数资源）。
  上游若改成不经 ffmpeg 的直连下载，速度要改从响应流计数（Mihon 的 `countingInto` 已在同一文件里备好）。
- 0011 改四处：`AppUpdateChecker.checkForUpdate()` 删掉 KMK 的 `autoUpdate` 参数和 `AppUpdateDownloadJob.start(scheduled = true)` 块
  （这是更新页卡在 0% 的根因：定时任务与页面发起的下载共用 unique work name `AppUpdateDownload`，`REPLACE` 还会取消正在进行的下载）；
  `SettingsAdvancedScreen` 删掉「自动更新 App」的 `MultiSelectListPreference`（`AppUpdateJob.setupTask` 仍在 `MainActivity` 用）；
  `AppUpdateDownloadJob`：`TAG_INTERACTIVE` 常量 + `start(interactive = true)` 时 `addTag`、`downloadApk()` 里下载前 `apkFile.delete()`、
  companion 里的 `deleteInstalledApk()`（`getPackageArchiveInfo` 读版本号，≤ 当前或读不出就删）；`NewUpdateScreenModel` 的 pending 判断
  多一个 `TAG_INTERACTIVE in workInfo.tags`；`App.onCreate` 在 WorkManager 初始化后 `scope.launch(Dispatchers.IO) { deleteInstalledApk }`。
  `deleteInstalledApk` 与 mihon-harmony 0007 逐字相同。上游若换掉 `downloadFileWithResume`，删文件那一行可以跟着去掉。
- 0012 改两处：`MainActivity.onCreate` 删掉 `setComposeContent` 末尾的 KMK 块（`previewLastVersion` 偏好、`showChangelog`、`WhatsNewDialog`），
  `didMigration` 不再需要，`Migrator.awaitAndRelease()` 像 Mihon 一样直接调用；`AboutScreen` 的「更新日志」条目改为 `uriHandler.openUri(RELEASE_URL)`，
  删掉 companion 里的 `getReleaseNotes()`（唯一的两个调用方都没了）。`WhatsNewDialog.kt` / `WhatsNewScreen.kt`、`AppUpdateChecker.getReleaseNotes()`、
  `GetApplicationRelease.awaitReleaseNotes()` 留在树里不删（减少 rebase 冲突面）。上游若把「已更新至」对话框改成别的形式，照 Mihon 的 `MainActivity` 对齐即可。
- 0013 改两处：`AppUpdateDownloadJob.start()` 非 scheduled 分支删掉 `setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)`（与 Mihon 的 `start()` 一致；
  `OutOfQuotaPolicy` import 一并删）；`NewUpdateScreenModel` 加 `downloadRequested` / `workerStarted` / `startTimedOut` 三个标志和 20 秒看门狗：
  打开页面时看到 pending（无 url、未结束、带 `TAG_INTERACTIVE`）但本页没点过「下载」→ `stop()` 并显示 Available；点过「下载」20 秒内 worker 没汇报 url →
  `stop()` 并显示 Failed（按钮「重试」）。上游若改 `start()` 的构造方式，保留「不 expedited」这一点即可。
- 0014 改两处：`ReleaseServiceImpl` 新增 `listReleases(repository)`（镜像 URL `https://raw.githubusercontent.com/$repository/repo/releases.json`，
  `networkService.client.newBuilder()` 三个超时都 10 秒；`CancellationException` 直接抛，其他异常 `logcat(WARN)` 后退回原 API URL），`releaseNotes()` 改调它
  （`with(json)` 外壳去掉，lambda 体整体少缩进 4 格，所以 diff 看着大）；`GetApplicationRelease.await()` 的 `lastChecked.set(now)` 移到 `service.releaseNotes()` 之后、
  `getLatest() ?: return NoNewUpdate` 之前。`latest()` 没有调用方（只有单元测试 `coVerify(exactly = 0)`），保持原样。镜像文件格式必须保持是接口原样返回，
  `GithubRelease` 的字段（`tag_name` / `body` / `html_url` / `assets[].name` / `assets[].browser_download_url` / `prerelease` / `draft`）一个都不能少。
- 0015 只改一处：`LibraryComfortableGrid` 调 `MangaComfortableGridItem` 时加 `fitToPanoramaCover = true`（原来没传，默认 `false`）。
  `BrowseSourceComfortableGrid` 一直是 `true`，所以浏览页的全景网格本来就是横格子；`LibraryCompactGrid` / `LibraryList` 没有全景分支，不用动。
  上游若把参数名改掉或在 `MangaComfortableGridItem` 里统一处理，直接按浏览页的调用方式对齐即可。
- 0016 改五处。`UniFileExtensions.renameToOrCopy(targetName, resolver = null)`：目录回退 = 先 `moveDocument` 每个子项、再 createFile+copy，目标已存在的目录合并、
  同名同大小的子文件跳过，复制后校验 `length()`（只信任正数：有的 provider 要刷新元数据才有大小），删源失败只记日志不回滚（数据已在目标里）。
  `Downloader.copyIntoDownloadDir`：先删同名 `<集>.mkv*`，建空 `<集>.tmp` 标记，直接 `createFile(finalName)` 写入，校验大小，删标记；
  `getOrDownloadVideoFile` 开头若发现 `<集>.tmp` 就连同旁边的 `<集>.mkv*` 一起删（兼容旧版的半成品 `.tmp` 数据文件）。
  `downloadVideo`：缓存文件旁多一个 `.muxed` 标记，复制失败（非取消）时两者都保留，下次直接复制；成功或取消时删除。`retryStorageOperation` 只重试 `IOException`。
  `Download.error` + `fail(message)`（`status` 设回非 ERROR 时自动清空），`DownloadHolder.notifyDownloadedPages` 在 ERROR 时把 `chapterTitle` 改成两行
  （集名 + 「出错：…」，`maxLines = 3`），`DownloadQueueScreenModel.onStatusChange` 的 ERROR 分支补调 `onUpdateDownloadedPages`。`getDuration` 失败返回 null。
  字符串 `harmony_download_unexpected_files` / `harmony_download_error_prefix` / `harmony_download_interrupted`（i18n-ank base + zh-rCN）。
  上游若重写 `Downloader.downloadVideo`，保留「ffmpeg 写私有缓存 → 一次复制到最终名 → 目录改名」这条链和 `.tmp` 标记语义即可。
- 0017 改两处。`NewUpdateScreen`：`MarkdownRender(flavour = remember { GFMFlavourDescriptor() })`——multiplatform-markdown-renderer（0.39.x）的
  `rememberMarkdownState` 把 `flavour` / `parser` 作为 `Input` 的一部分，flavour 实例变了就 `updateInput()` → 状态回到 Loading → 异步重新解析，
  而更新页按钮文字读 `downloadProgress()`，下载期间每个 tick 都重组，于是说明文字闪。Mihon v0.20.4 上游（`NewUpdateScreen.kt`）本来就是 `remember`，
  KMK 的那份漏了；上游若合入同样的 `remember`，脚本会自动跳过。`Downloader` 的 ffmpeg `LogCallback`：`FFMPEG_CONTEXT_PREFIX` 正则去掉
  `[tcp @ 0x…] ` 之类前缀后再进 `recentLogs`，与上一条相同则丢弃。
- 0018 改 `Downloader.kt`（`queueEpisodes()` 返回新增的 `data class QueueResult(queued, alreadyDownloaded, alreadyQueued, sourceUnavailable, fillermarked)`，
  「已下载」改用 `cache.isChapterDownloaded(name, scanlator, anime.ogTitle, anime.source, skipCache = false)`；`downloadEpisode()` 把 `createDirectory(_tmp)` 挪进 `try`，
  之前先调新函数 `reuseOrRemoveExistingEpisode(download, animeDir, episodeDirname)`：`getValidChapterDirNames` 逐个 `animeDir.findFile`，目录里除 `.nomedia` / `*.tmp` 外恰一个文件且 `length() > 0`、
  并且 `_tmp` 里没有视频或有同大小的视频 → `createNoMediaFile` + `cache.addChapter(name, …)` + 删 `_tmp` + 返回 true；否则 `existing.delete()`（删不掉抛 `harmony_download_leftover_delete_failed`）），
  `DownloadManager.downloadChapters()/downloadEpisodes()`（返回 `QueueResult`，`fillermarked = episodes.size - filteredEpisodes.size`），
  `MangaScreenModel.downloadChapters()`（改 `suspend`，MergedSource 分支用私有 `plus` 累加，`result.skipped > 0` 时拼 Snackbar），
  六条字符串 `harmony_download_skipped*` / `harmony_download_leftover_delete_failed`（i18n-ank base + zh-rCN）。`PlayerViewModel` / `LibraryUpdateJob` 等调用方忽略返回值。
  队列里处于 ERROR 状态的剧集记为 `retried`（不计入 `skipped`；点「!」重试走的就是这条路，调用方随后 `startDownloads()`）。
  与 mihon-harmony 0011 + 0013 的差异只在完整性规则（一个视频 vs 页数）和 `fillermarked` 一项。
- 0019 改 `CrashLogUtil.kt`（`Runtime.exec(arrayOf("logcat", "*:E", "-d", "-v", "year", "-v", "zone"))` 读 stdout，`filterNoise()` 按 `HARMONY_NOISE_MARKERS` 六个子串过滤并计数，
  `logcatHeader()` 写「--- Logcat (N 卓易通 graphics-layer lines filtered: …) ---」，末尾追加「--- App log (last N lines …) ---」+ `HarmonyLogBuffer.snapshot()`）、
  新文件 `util/system/HarmonyLogBuffer.kt`（与 mihon-harmony 0012 的同名文件**逐字节相同**，改一处同步另一处）、`App.kt`（`LogcatLogger.loggers += HarmonyLogBuffer`，排在 XLog / Android logger 之后）。
- 0020 改 `LibraryComfortableGrid.kt`（`usePanoramaCover` 为真时走新的 `LazyLibraryStaggeredGrid`，自动列宽 `PanoramaGridMinColumnWidth = 168.dp`，固定列数仍 `Fixed(columns)`；格子内容抽成私有 `LibraryComfortableGridItem`，两种网格共用；`rememberCoverRatio(mangaId, usePanoramaCover)` 从进程级 `ConcurrentHashMap<Long, Float>` 取初值、`snapshotFlow` 写回，全景模式未知封面默认 `9f / 16f`）、`LazyLibraryGrid.kt`（新增 `LazyLibraryStaggeredGrid` + `LazyStaggeredGridScope.globalSearchItem`，span `FullLine`）、`presentation-core` 的 `LazyGrid.kt`（`FastScrollLazyVerticalStaggeredGrid`）与 `VerticalFastScroller.kt`（`VerticalStaggeredGridFastScroller`：lane 数取可见项 `lane` 最大值 + 1，行高 = 可见项平均高度 + `mainAxisItemSpacing`，滚动范围 = ⌈总数 / lane 数⌉ × 行高 + 前后 padding，拖拽时 `scrollToItem(lane 数 × 行号, 行内偏移)`；拇指常量复用文件内的 private 值，所以放在同一个文件里）。上游 `MangaComfortableGridItem` 不动（0015 起已传 `fitToPanoramaCover = true`）。浏览页 / 相关作品页的全景网格由 0021 照搬。
- 0021 把 0020 的 `rememberCoverRatio` / 封面比例缓存从 `LibraryComfortableGrid.kt` 挪到新文件 `library/components/PanoramaGrid.kt`，并在那里加 `CountedGridCells(columnCount)`（实现 `GridCells`，0 时按 `Adaptive(128.dp)`、否则按 `Fixed(n)` 布局，但把列数偏好带出来——上游 `GridCells.Fixed.count` 读不到）、`libraryGridCells(columns)`、`panoramaStaggeredColumns(columnCount)`（0 → `StaggeredGridCells.Adaptive(168.dp)`，否则 `Fixed`）和 `GridCells.panoramaStaggeredColumns()`（非 `CountedGridCells` 时回退到 `LibraryPreferences` 的横/竖屏列数）。`BrowseSourceScreenModel.getColumnsPreference()` / `RelatedMangasScreen` 改为返回 `libraryGridCells(columns)`（紧凑网格也会收到 `CountedGridCells`，布局与原来一致）。`BrowseSourceComfortableGrid.kt` 在 `usePanoramaCover` 为真时走 `FastScrollLazyVerticalStaggeredGrid(columns = columns.panoramaStaggeredColumns())`，分页占位行 `item(span = StaggeredGridItemSpan.FullLine)`，格子传 `coverRatio = rememberCoverRatio(manga.id, usePanoramaCover)`；`RelatedMangasComfortableGrid.kt` 重构成 `addRelatedSections` 由瀑布流 / 普通网格两条路径共用（分区标题整行）。行为差异：浏览页全景模式现在有快速滚动条（非全景的松散网格上游本来没有）；`MangaScreen.kt` 的季度网格 / `MigrateSeasonSelectScreenModel.getColumnsPreference()` 没动（季度网格从不走全景；后者仍返回普通 `GridCells`，靠回退分支拿列数）。此补丁由子代理（grok-4.7-high）按 `/workspace/.cursor/rules/orchestration.mdc` 流程完成，主代理复核 diff 并独立重跑 `:app:compilePreviewKotlin`。
- 0022「全景紧凑网格」：`LibraryDisplayMode.CompactGridPanorama`（序列化 `COMPACT_GRID_PANORAMA`，`values` 变 6 个，`LibraryFlagsTest` 断言同步改），`MangaCompactGridItem` 多 `usePanoramaCover` / `coverRatio`（≤ 0.75 画 3:2，未知封面默认横版），`LibraryCompactGrid` 全景时走 `LazyLibraryStaggeredGrid`（私有 `LibraryCompactGridItem` 合并两条路径的格子画法），`BrowseSourceCompactGrid` / `RelatedMangasCompactGrid` 全景时用瀑布流 + `CountedGridCells`，`BrowseSourceToolbar` / `BrowseSourceSimpleToolbar` / `LibrarySettingsDialog` / `LibraryPager` / `BrowseSourceScreen` / `RelatedMangasScreen` 各多一项。字符串 `action_display_grid_panorama` 放 `i18n-kmk`（与 `action_display_comfortable_grid_panorama` 同处）：base「Panorama compact grid」/ zh-rCN「全景紧凑网格」/ zh-rTW「全景密集格狀」（跟上游 zh-rTW 的「密集格狀」，子代理原写「緊湊格狀」，复核时改）。与 mihon-harmony 0015 同源（Mihon 没有相关作品页和 SimpleToolbar）。
- 0023 只改 `presentation-core/.../VerticalFastScroller.kt` 的 `VerticalStaggeredGridFastScroller`：估算段换成 `StaggeredGridMeasurements` + `rememberStaggeredGridEstimate(state)`（`derivedStateOf`）。要点：① 满行条目按**宽度**识别（比屏上最窄格子宽 1.5 倍以上不计高度）——`LazyStaggeredGridItemInfo` 不暴露 span，子代理最初 `@Suppress("INVISIBLE_REFERENCE")` 强转内部 `LazyStaggeredGridMeasuredItem.span`，复核时改掉；② `offset.y` 相对内容起点（Compose `LazyStaggeredGridMeasure.kt` 里 `beforeContentPadding` 只在 `place()` 时加进 `contentOffset`），`scrollOffset` 不加顶部 padding、只在 `scrollRange` 里算两头——0020 原来的估算加了，静止时拇指不在最顶；③ 一次循环算 `beforeFirst` / `beforeAll`。`private class StaggeredGridEstimate(` 到 `// Harmony <--` 与 mihon-harmony 0016 **逐字相同**（`diff` 校验过），改一处要同步另一处；两边仍只差拇指淡出（Anikku 用 `FadeOutAnimationSpec`）。
- 0024 只改 `GetApplicationRelease.kt`（+ 测试）：`getLatest()` 先按 `(主, 次, 补丁, harmony 号)` 降序排（解析不了的排最后）再取第一项，合并的更新日志跟着这个顺序；`HARMONY_VERSION_REGEX` / `parseHarmonyVersion` / `compareVersions` 从类的私有成员挪到文件级 private，好让扩展函数共用；顺手去掉 0014 留下的双空行（`:domain:spotlessCheck` 原本在这里红）。`GetApplicationReleaseTest` 新增「最新版排在第二个」用例。Mihon 的同一修复在 data 层 `ReleaseServiceImpl.latest()`（0017），因为 Mihon 的频道过滤在那里。
- 0025 与 mihon-harmony 0018 同源，修全景网格滑动时资源块排版抽搐、掉帧，以及滚动条残余抽搐。根因三条：① 格子第一次按默认横版 3:2 排，图片解码完才改 2:3，瀑布流一个格子变高会把该列下面全部推下去，快速滑动时每秒几十张图各触发一次整个瀑布流重测；比例只在进程内，重启重来。② 横/竖切换时 `MangaCover.Panorama(...)` / `MangaCover.Book(...)` 是两个 Compose 调用点，`AsyncImage` 被销毁重建。③ 滚动条残余抽搐是可见格子高度在滑动中变导致估算跳，**0023 的滚动条代码没动**。
  新文件 `app/src/main/java/eu/kanade/presentation/library/components/PanoramaCoverShapes.kt` 与 Mihon 0018 **逐字节相同**（`cmp` 校验过），改一处要同步另一处。`SnapshotStateMap` 存已学到的高/宽，持久化到 `filesDir/harmony_panorama_cover_shapes.txt`（每行 `id ratio`，3 位小数，写临时文件再 rename，2 秒防抖，上限 20000 条丢最旧）。`App.onCreate` 里 `init` 异步加载。书架两种全景模式后台 `prefetch`（未知 id 用 `BitmapFactory` `inJustDecodeBounds` 读封面缓存尺寸，并行 4，不阻塞列表），挂在 `LibraryScreenModel`（Mihon 挂在 `LibraryViewModel`）。`LocalPanoramaGridSettled` 由瀑布流包装层提供 `{ !state.isScrollInProgress }`，`rememberCoverRatio` 只在网格静止时才把新形状写进布局（横竖同侧则立即）。`onCoverLoaded` 改为 `PanoramaCoverShapes.put`。封面单一调用点：`val cover = if (wide) MangaCover.Panorama else MangaCover.Book; cover(...)`。浏览页 `BrowseSource*Grid`、相关作品 `RelatedMangas*Grid`、`GlobalSearchCardRow` 同样注入静止判断，但没有文件预取。不改数据库、不加设置项。
  行为差异（相对 Mihon）：预取挂在 `LibraryScreenModel`；相关作品页和全局搜索横条也注入静止判断。已知局限与 Mihon 相同：从没见过的封面仍会在停下时跳一次；浏览页第一次进全景没有预取。拖滚动条中途改形状、浏览页没有预取，由 0027 补上（见下）。Animeko 不适用。
  **待办（与 0025 无关）**：`:app:spotlessCheck` 对 `DownloadNotifier.kt` / `MangaScreenModel.kt` 有早就存在的 import 顺序告警（`AYMR` 应排在 `AMR` 前，来自更早的 Harmony 补丁）。子代理移植时顺手改过这两处，主代理已撤回。CI 不跑 spotless。下次 rebase 时顺手修。0026 / 0027 / 0028 / 0029 / 0030 / 0031–0037 都没动这两个文件，告警还在。
- 0026 修「Anikku 全景紧凑比 Mihon 卡」（用户：「mihon 的全景紧凑很丝滑，滑块不卡顿，anikku 的还是会卡顿」）。C 层，Komikku 的封面组件，Mihon / Animeko 不适用。`MangaCover` 用 Coil `SubcomposeAsyncImage`：懒加载网格每个格子都再套一层（Coil 文档说它不适合 `LazyList`），每个加载中的格子都有不定型 `CircularProgressIndicator`，每帧都在画。改成同一块着色 `Box` 里的 `AsyncImage`；`onError` 时错误图标画在色块上；`DelayedLoadingIndicator` 等 400 ms（`LoadingIndicatorDelay`）才显示转圈，内存 / 磁盘缓存命中在这之前就成功，不会闪一下。`onCoverLoaded` 仍在 `onSuccess` 里调。`LibraryBadges.kt` 的 `SourceIconBadge`：`Source.icon` 改为 `remember(source.id) { source.icon }`（getter 每次组合都扫已装扩展，还可能把 drawable 重画成新 bitmap）。文件：`app/src/main/java/eu/kanade/presentation/manga/components/MangaCover.kt`、`app/src/main/java/eu/kanade/presentation/library/components/LibraryBadges.kt`。
- 0027 与 mihon-harmony 0019 同源，补 0025 留下的两处（用户接着说 Mihon 也会抖）。① `rememberPanoramaGridSettled { state.isScrollInProgress }`：一旦在滚就立刻不算静止，连续 300 ms 没有滚动才算静止。拖快速滚动条是一串短 `scrollToItem`，两次之间 `isScrollInProgress` 为假，0025 会在拖的过程中把新形状写进布局；两下甩动之间的停顿同样。书架瀑布流、浏览页两种全景网格、`RelatedMangasComfortableGrid` / `RelatedMangasCompactGrid` 都改用它。② 浏览页 `BrowseSourceComfortableGrid` / `BrowseSourceCompactGrid` 加 `PrefetchPanoramaCoverShapes`：对分页已加载、还没上屏的条目按 128 px、`Precision.INEXACT`、内存缓存关掉去要封面，记下高/宽；下载进磁盘缓存，格子后来读同一份；离开网格就取消。相关作品页列表短，只有静止判断，没有这份预取。
  `PanoramaCoverShapes.kt` 与 Mihon 0019 **逐字节相同**（`cmp` 校验过），改一处要同步另一处。不改数据库、不加设置项。已知局限与 Mihon 相同：刚打开的浏览页第一屏在静止时仍可能翻一次；下载失败的封面保持默认横版。额外网络是把已加载未看见的那一页封面提前一点下。Animeko 不适用。
- 0028 与 mihon-harmony 0020 同源，修全景网格往下滑时右侧快速滚动条拇指大约每行回跳一下（用户：「好像还是会抖……大概频率是每一行抽动一下，是不是没找到根因呢？mihon，anikku都是」）。0027 修的是格子形状，不是这段。根因：瀑布流各列格子高度不同；旧估算以「屏幕上编号最小的可见格子」为锚、按行公式推位置，这个格子一移出屏幕就换成下一个，公式对每个格子的偏差不一样（Python 模拟 100 行内 141 次往回跳，中位数 3.2 px，最大 9.3 px）；滚动中总长度的均值也在变。做法与 Mihon 0020 相同，只改 `presentation-core/.../VerticalFastScroller.kt`：位置跨帧累加（可见项中间那个锚的位移），第 0 项可见时用精确值，跳转（拖拇指 / `scrollToItem`）后锚不在了才回退行公式；`isScrollInProgress` 期间冻结总长度，条目数变化时才刷新；停下后 150 ms 平滑（`RANGE_SETTLE_MILLIS = 150`）；到底（`!canScrollForward`）时比例为 1。`private class StaggeredGridEstimate(` 到 `// Harmony <--` 与 Mihon 0020 **逐字节相同**，改一处要同步另一处。开发树 `~/work/anikku-v0.2.0` `dev-0025` 提交 `896faf0`。`:presentation-core:spotlessCheck :app:compilePreviewKotlin` 通过。拇指顺不顺模拟器测不了。Animeko 不适用。0030 起 `StaggeredGridEstimate` 整段删除，滚动条改读真实内容高度，见 0030。
- 0029 只 Anikku 有（用户：「我在哪可以设置缓存的默认清晰度呢？看起来现在下载的像是按我浏览的清晰度设置的」→「要配置下分开的设置，通常希望下载清晰一些」）。C 层。队列里没有指定视频的剧集，下载器走 `HosterLoader.getBestVideo`，和播放一样取扩展标成 preferred 的视频（扩展的 `sortVideos` / 「首选画质」决定），所以下载画质永远等于播放画质。扩展本身分不出播放和下载，只能在 App 里分。此前唯一的办法是作品页长按剧集 →「选择视频画质」逐集选。
  新设置：设置 → 下载 →「下载画质」（在「并发下载」滑块下方），key `harmony_download_quality`，默认 `highest`。选项：最高可用（默认）/ 不超过 2160p / 1440p / 1080p / 720p / 480p / 360p / 与播放相同（插件首选）。字符串在 `i18n-ank` base + zh-rCN。副标题：「下载时未单独选择画质的剧集按此下载；在线播放仍用插件里的首选画质。」
  新文件 `app/src/main/java/eu/kanade/tachiyomi/data/download/DownloadQualitySelector.kt`。加载所有非懒加载的 hoster，按高度排序（来自 `Video.resolution`，或标题里的「1080p」「1920x1080」「4K」）：先取不超上限的最高，再取高于上限的最低，最后是没有高度的（按标签 High > auto > 普通 > Low；上限 ≤ 480p 时 High/Low 反过来）；同高度按码率、再 preferred、再原顺序。按顺序解析，第一个拿到地址的就用。选「与播放相同」或一个都解析不出时回到原来的 `getBestVideo`。长按剧集逐集选的画质仍优先。以 XvXun 为例：HLS 1080p > HLS 720p > HLS 480p > MP4 High > HLS (auto) > MP4 Low。
  已知局限：懒加载的 hoster 不展开（与原逻辑一致）；扩展只给一种画质时没有区别（例如 RouXun 只给一条 HLS）；「HLS (auto)」是主播放列表，实际变体由 ffmpeg 自己挑；回退时会把 hoster 再加载一遍。
  开发树提交 `e4583d6`。`:domain:spotlessCheck :app:compilePreviewKotlin` 通过；`:app:spotlessCheck` 只剩早就存在的 `DownloadNotifier.kt` / `MangaScreenModel.kt` import 顺序告警（待办未变，见上 0025）。新增单元测试 `app/src/test/java/eu/kanade/tachiyomi/data/download/DownloadQualitySelectorTest.kt` 5/5 通过。模拟器（AVD harmony34，TCG，本地 x86_64 preview 包）：设置 → 下载里「下载画质」在并发滑块下方，默认显示「最高可用」，弹窗 8 个选项（模拟器是英文界面）。真实下载未在模拟器上跑。本张是主代理自己写的。Mihon 不适用（漫画，没有视频画质）。Animeko 不适用（v6.2.0 只有一套「资源选择」分辨率偏好 `MediaPreference.fallbackResolutions`，默认 2160P > 1440P > 1080P > 720P 从高到低，播放和缓存共用；手动缓存时用户自己挑资源）。
- 0030 与 mihon-harmony 0021 同源，修两件（用户：「最后一个似乎倾向于高度不是最高的位置开始……左边看起来空出来一块」「折叠到打开时 anikku 从两列变成四列……希望在排布变化的那一刻就优化好」）。B 层，Compose `LazyVerticalStaggeredGrid`，不是卓易通平台限制。0028 修的是滚动条估算，不是分列规则，也不是列数变化。上游若重写全景网格，不要再换回 `LazyVerticalStaggeredGrid`。

  根因两条：① `indexOfMinValue` 零容差，每一项放进底边最短的列，右边只矮一丝也放右边，左边空一块。② lane 数一变 `laneInfo.reset()`，把当前可见项当新网格起点；只有滑动触发的 `misalignedStart` 才从第 0 项重排。停在顶部看不出，要先滚到中部。没有公开 API 能指定进哪一列，目标已可见时 `scrollToItem` 也不会从头重排。

  做法与 Mihon 0021 相同：自建 `LazyLayout`（`presentation-core/.../components/PanoramaMasonry.kt`、`PanoramaMasonryLayout.kt`）。下一项放进底边 ≤ 最短列 + 本项高×0.5 的最左列。`FullLine` 不参与容差。列数 / 宽度变化在同一次测量里重算，用视口顶部项 key 钉住（没有 key 用 index）。列数 0 = `Adaptive(168.dp)`，同宽度下列数和原来一致。

  格子高度不测量：槽宽先减左右各 4dp；高/宽 ≤ 0.75（含未知）宽封面，封面高 = 列内宽 × 2/3，否则 × 3/2；格子高 = 封面高 + 上下各 4dp；松散再加标题 4dp×2 + 2×18sp；垂直间距 4dp；浏览加载行 72dp、相关作品加载行 56dp。上游若改了封面阈值或标题行数，同步 `panoramaCoverCellHeightPx`。

  与 0028 的关系：0028 的 `StaggeredGridEstimate` 是 `LazyVerticalStaggeredGrid` 不给出真实内容高度时的估算。0030 换成自建布局后，快速滚动条读真实内容高度和偏移，估算段删除。

  调用点 7 处：书架、浏览、相关作品各紧凑 / 松散，加上 `LazyLibraryGrid`。Mihon 是 5 处（没有相关作品页，浏览页仍无快速滚动条）。

  共享文件：
  - `PanoramaMasonry.kt`、`PanoramaMasonryLayout.kt`、`presentation-core/src/test/.../PanoramaMasonryLayoutTest.kt` 与 Mihon 0021 **逐字节相同**，改一处要同步另一处。
  - `VerticalFastScroller.kt` 的 `// Harmony -->` 到 `// Harmony <--` 段相同。整文件不同：本仓保留原有不规则滚动条淡出。**行为差异**：Mihon 书架拇指停留从原来的 2 秒变为系统默认约 300 ms；本仓没有改淡出。
  - `app/.../library/components/PanoramaCoverShapes.kt` 此前（0025 / 0027 对 Mihon 0018 / 0019）逐字节相同。0030 起只差阈值常量名：本仓 `RatioSwitchToPanorama` 加一行 import，Mihon `RATIO_SWITCH_TO_PANORAMA`，各 App 原有命名，逻辑相同。重做时不要为了 `cmp` 把常量名改成对方的。
  - `presentation-core/build.gradle.kts` 只加了 JUnit。

  开发树 `~/work/anikku-v0.2.0` `dev-0025` 提交 `a455329`，流水线提交 `a9ecebd`。`:presentation-core:spotlessCheck` 通过、`:presentation-core:testDebugUnitTest` 16/16、`:app:compilePreviewKotlin` 通过。`:app:spotlessCheck` 只剩已知的 `DownloadNotifier.kt` / `MangaScreenModel.kt` import 顺序告警（待办未变，见上 0025）。干净 v0.2.0 树套 30 张成功（versionCode 817），15 个改动文件 `cmp` 一致。

  模拟器（AVD harmony34，TCG，本地 x86_64 preview）：XvXun 最新两列长列表无左侧空洞（短列只凹约 20px 时留左列）；`wm size 2200x2480` 后当帧四列，`wm size reset` 回两列不跳回顶部（左上格可能挪约一行）；快速滚动条拖动正常；书架下拉刷新触发 `LibraryUpdateJob`（manual，SUCCESS）；浏览翻页正常。真折叠屏只用 `wm size` 模拟。

  已知局限：没有 key 的书架过滤结果按 index 钉；标题行高写死 18sp，字体更大时被裁；`scrollToItem(0, 0)` 不计开头 content padding。Animeko 没有这套网格，不适用。

- 0031–0037 与 mihon-harmony 0023–0029 一一对应、同源（用户 2026-10-14 四件，Anikku 同样：返回丢位置、2000 项惯性卡顿、按住滚动条变透明后变成上翻、自动列过宽 / 横封面过小）。根因与 Mihon §5.1 相同，这里只写本仓差异。不是卓易通平台限制。

  做法与 Mihon 相同，补丁号加 8：0031 横封面 ≥3 列跨两列（`PanoramaSpan.TwoLanesWhenRoomy`）；0032 `PanoramaMasonryState.Saver` 按 key 存锚点，列表加载完整后再恢复（书架全景、浏览全景、相关作品全景）；0033 `PanoramaMasonryContentEpoch`，内容不变时跳过逐项计算（基准与 Mihon 同一份：2000 项、120 帧，每帧 0.323 ms → 0.0082 ms，每帧分配 266,776 B → 56 B）；0034 形状表按版本通知，跨 0.75 比例档等所有网格静止 300 ms 后一次提交，写快照放回主线程；0035 `startDragImmediately`，按住期间不淡出、不摘手势，触摸区 32 dp；0036 `PanoramaColumns.Tiered`（< 600 dp 最小 112 dp，≥ 600 dp 用 140 dp；360 / 420 / 459 dp → 3 列，664 / 672 dp → 4 列，800 dp → 5 列，933 / 939 dp → 6 列；比较网格自身宽度）；0037 瀑布流滚动条改为单个 `LaunchedEffect` + `snapshotFlow`。

  **重做要点**（相对 Mihon，rebase 时不要抹平）：
  - `PanoramaMasonry.kt`、`PanoramaMasonryLayout.kt`、`PanoramaMasonryLayoutTest.kt` 与 Mihon 0023–0029 里对应的三份 **逐字节相同**，改一处要同步另一处。
  - 列宽常量在 `PanoramaGrid.kt`（Mihon 在 `LibraryComfortableGrid.kt`）。
  - 形状阈值名是 `RatioSwitchToPanorama`（Mihon `RATIO_SWITCH_TO_PANORAMA`）。0034 改的是通知方式，不要为了 `cmp` 改这个名字。
  - 相关作品全景和书架、浏览一起走这套锚点 / 布局 / 列宽。Mihon 没有相关作品页。
  - 第四个滚动条 `IrregularVerticalGridFastScroller`（番剧详情页的剧集网格）在 0035 / 0037 里一起改了。Mihon 只有列表、网格、瀑布流三根。滚动条 Harmony 段仍用 `// Harmony -->` 包住。
  - 上游列表 / 网格滚动条的 `LaunchedEffect(firstVisibleItemScrollOffset)` **不要**改成 `snapshotFlow`：它们在书架以外，改了会落后一帧。
  - 共享测试不再依赖 `java.awt` / `com.sun.management`（预览用手写 PNG 编码，分配计数用反射），所以 AGP 8 不用改 Gradle 也能编译。

  子代理（grok-4.7-high-fast）实现。主代理复跑 `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 33 通过 / 2 跳过；app 14 个）。`:app:spotlessCheck` 的 `DownloadNotifier.kt` / `MangaScreenModel.kt` import 顺序问题仍是旧待办，本轮没跑这条、也没改那两个文件。干净树 `/tmp/anikku-verify37`（`prepare-source.sh`，v0.2.0，N=18）套用成功，14 个改动文件与开发树 `cmp` 一致。没有真机 / 模拟器手势测试。流水线提交 `610c580`。series 37 张（0001–0037）。

  同病：Mihon 0023–0029 同轮已修。Animeko：滚动条按住不适用（Android 端是不可拖动的 `LazyListVerticalScrollIndicator`）；惯性卡顿 / 自动列宽不适用（没有全景瀑布流，也不学习封面比例）；返回丢位置待确认（另一套导航）。

- 0038–0040 与 mihon-harmony 0030–0032 一一对应、同源（用户 2026-10-14：折叠屏全景紧凑右列空；惯性有时消失，稳定复现是滑到书架最底再往回甩；「我没动滑块」）。根因与 Mihon §5.1 相同，这里只写本仓差异。不是卓易通平台限制。

  做法与 Mihon 相同，补丁号加 8：0038 `PanoramaColumns.Shaped`（`A0 = 23064 dp²`，`refArea = 459 × 552`，`area = A0 × max(1, √(网格面积 / refArea))`，`ideal = clamp(√(area / 高宽比) + 8, 104, 240)`）；0039 形状模式（已知数够了才判定，宽比例 ≥ 0.60 切 Wide、≤ 0.40 才切回 Tall；只在 settle 时采样；`committedShapeVersion` 与条目签名变化时重采样；列数变化不 bump epoch；Tall → `Shaped(1.5)` 且横封面 ≥3 列跨两列，Wide → `Shaped(2/3)` 不跨列，Unknown → 原 `Tiered(112, 140, 600)`；手动固定列数时列数不变，跨列仍按模式）；0040 热区改为 `ThumbThickness + endInset`，按在拇指上仍按下即拖。

  **重做要点**（相对 Mihon，rebase 时不要抹平）：
  - `PanoramaMasonry.kt`、`PanoramaMasonryLayout.kt`、`PanoramaMasonryLayoutTest.kt` 与 Mihon 0030–0032 里对应的三份 **逐字节相同**，改一处要同步另一处。
  - `PanoramaShapeMode.kt` 在 app 层。不要为了 `cmp` 把它挪进上面三个共享文件。
  - `committedShapeVersion` 只在主线程写，measure 不读。
  - 形状阈值名是 `RatioSwitchToPanorama`（Mihon `RATIO_SWITCH_TO_PANORAMA`）。列宽常量在 `PanoramaGrid.kt`（Mihon 在 `LibraryComfortableGrid.kt`）。
  - 相关作品两套全景和书架、浏览一起按自己的条目统计形状。Mihon 没有相关作品页。
  - 第四个滚动条 `IrregularVerticalGridFastScroller`（番剧详情页的剧集网格）在 0040 里一起改了。Mihon 只有列表、网格、瀑布流三根。
  - 测试依赖：Robolectric 4.16.1、Compose ui-test、junit-vintage **6.0.3**（Mihon 是 6.1.3）、`isIncludeAndroidResources`、`debugImplementation(ui-test-manifest)`。UI 测试用 `runComposeUiTest`。发版的 preview 构建对库模块回退到 release 变体，所以不进包。manifest 已核对，无 ui-test 的 ComponentActivity。

  子代理（grok-4.7-high-fast）实现。主代理复跑 `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 51 个用例，0 失败，2 跳过；app 21 个）。干净树 `/tmp/anikku-verify40`（`prepare-source.sh`，v0.2.0，N=19）套用成功，21 个改动文件与开发树 `cmp` 一致。没有真机手势测试。流水线提交 `570066f`。series 40 张（0001–0040）。

  同病：Mihon 0030–0032 同轮已修。Animeko：列数按形状不适用（没有全景瀑布流）；滚动条热区不适用（Android 端是不可拖动的 `LazyListVerticalScrollIndicator`）；惯性不适用，同一原因。

- 0041 与 mihon-harmony 0033 同源（用户 2026-10-14 10:53 UTC：「我感觉不是加宽的原因，mihon书架有时候不在底部的时候还是会滑动完没有惯性，之前应该没有的，要有办法定位吗？」）。preview.19 收回热区（0040），只解释「到底往回滑」那一下。书架中间偶发的问题另有原因。没有真机数据，不能定论，因此先发诊断版，不改滑动行为。根因与 Mihon §5.1 相同，这里只写本仓差异。

  做法与 Mihon 相同：新文件 `presentation-core/.../PanoramaScrollTrace.kt`，并改 `PanoramaMasonry.kt`。这两个文件与 Mihon **逐字节相同**。`CrashLogUtil.kt`：「转储崩溃日志」末尾附「--- Panorama scroll trace (last N events) ---」，最多 400 条，与 `HarmonyLogBuffer`（0019）分开存。每次触摸记 `down` / `up`（`up` 带 `moves`、`dy`、`gapLastMove`、`trackerV`、`recentV`、`consumed`）；每次惯性记 `fling start v= offset= max=`，结束为 `fling done|stopped|cancelled left= dist= frames= ms= maxGap=`，吃不满的帧记 `short frame asked= got=`；`scrollToItem` / `requestScrollToItem` / `scrollToOffset` 各写一行；offset 被改时记 `measure reason=request|restore|anchor|clamp`，epoch 变化、滚动中 max 变化也记；网格 `enter` / `leave`，以及 `userScrollEnabled=false`。只覆盖全景（瀑布流）网格，普通紧凑 / 舒适网格不记录。第四根 `IrregularVerticalGridFastScroller`（番剧详情页剧集网格）**不**在这条轨迹里。

  不改滚动行为：惯性包装逐帧原样转发；触摸只在 Initial 阶段旁听、不消费；测量里读 `isScrollInProgress` 用 `Snapshot.withoutReadObservation`，不额外触发重测。

  **重做要点**（相对 Mihon，rebase 时不要抹平）：
  - `PanoramaScrollTrace.kt`、`PanoramaMasonry.kt` 与 Mihon 0033 **逐字节相同**，改一处要同步另一处。`PanoramaMasonryLayout.kt` / `PanoramaMasonryLayoutTest.kt` 本张没动。
  - 轨迹不要塞进 `HarmonyLogBuffer` 的 600 行应用日志，分开存。本仓缓冲是 0019，不是 Mihon 的 0012。
  - 每个滚动入口自己写标签。正式版混淆后没有调用栈。
  - 判读与 Mihon 0033 相同：`trackerV=0` 而 `recentV` 很大、`gapLastMove≥40ms` → 触摸投递卡顿；`fling cancelled` 前一行是 `scrollTo…` / `down` / `leave` → 被它打断；`short frame` 或 `fling stopped` → 滚动范围问题；`up` 的 `trackerV` 很大但 `fling start v` 小 → 外层吃了速度。
  - 新测试 3 个与 Mihon 同一份：`the scroll trace records the release and how the fling ended`（顺序 up → fling start → fling done，dist 4462、frames 132）；`the scroll trace names a jump that cancels the fling`（`scrollToOffset 1000` 之后紧跟 `fling cancelled`）；`a pause before lifting reads as zero release velocity`（4 次 move 后停 60 ms 再松手：`gapLastMove=60ms trackerV=0 recentV=-2215`，`fling start v=0`，惯性 0）。这说明「停顿后速度归零」的假设在机制上成立。

  `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 54 个用例，0 失败，2 跳过；app 21 个）。本轮没有 `:app:spotlessCheck`。干净树 `/tmp/anikku-verify41`（`prepare-source.sh`，v0.2.0，N=20）套用成功，23 个改动文件与开发树 `cmp` 一致。开发树 `dev-0031` 提交 `b831ddf`。流水线提交 `101835a`。series 41 张（0001–0041）。

  同病：Mihon 0033 同轮已加诊断。Animeko 没有全景瀑布流，这条日志不适用；若「停顿 >40 ms 速度归零」是卓易通触摸投递问题，属于平台层，Animeko 的 LazyColumn 也可能受影响，等这份诊断日志定性后再看。日志已于 0042 定性，见下。

- 0042 与 mihon-harmony 0034 同源。用户日志见 Mihon §5.1 补丁 0034（11:37 UTC `mihon_crash_logs_318b.txt`、11:39 UTC `mihon_crash_logs_ab65.txt`）。preview.20 的日志否定了「触摸送慢了、速度被算成 0」。根因与 Mihon 相同，这里只写本仓差异。

  做法与 Mihon 相同：没碰到两端时返回精确的 delta，碰到两端才返回 `next - current`。`PanoramaMasonry.kt` 与 Mihon **逐字节相同**。0041 的诊断日志保留。只有全景网格是自写的 ScrollableState。第四根 `IrregularVerticalGridFastScroller` 不在 0041 的轨迹里，这张也不改它。

  **重做要点**（相对 Mihon，rebase 时不要抹平）：
  - `PanoramaMasonry.kt` 与 Mihon 0034 **逐字节相同**，改一处要同步另一处。`PanoramaScrollTrace.kt` 仍与 0041 / 0033 那一份逐字节相同，诊断日志不要删。
  - 没被两端截断时必须返回这一帧传入的 delta。只有碰到两端才返回 `next - current`。
  - 回归测试要包一层 `pullToRefresh`，offset 设到远超过 65536。本仓旧代码上同一条测试同样失败。
  - `HarmonyLogBuffer` 是 0019，不是 Mihon 的 0012。轨迹仍与它分开存。
  - 编的是 Preview。

  新测试 `return flicks under pull to refresh keep their velocity far down the list` 与 Mihon 同一份：网格包在 `pullToRefresh` 里，offset 70000，先往下翻 3 次再往回甩 4 次。修前起速 `[5120, 5120, 5120, 0, 0, 0, 0]`，修后往回甩为 -5120。

  `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 55 个用例，0 失败，2 跳过；app 21 个）。干净树 `/tmp/anikku-verify42`（`prepare-source.sh`，v0.2.0，N=21）套用成功，23 个改动文件与开发树 `cmp` 一致。开发树 `dev-0031` 提交 `334702d`。流水线提交 `535be14`。series 42 张（0001–0042）。

  同病：Mihon 0034 同轮已修。Animeko 不适用：没有自写的 ScrollableState，列表用 Compose 的 Lazy 系列，会精确返回 delta。根因不是平台触摸投递。

补丁 0043 与 mihon-harmony 0035 同源。用户 2026-10-14：「好像mihon的惯性消失问题解决了，但是为啥滑动块又很难按到了」。0040 把热区收回到画出来的拇指（12 dp + 边距），误抓往回甩的问题没了，但很难按中。

做法：热区恢复 32 dp + 边距，分两段。
- 画出来的拇指（加边距）：按下即抓，和以前一样，内容收不到这个指针。
- 朝内容一侧的另外 20 dp：`HoldToGrabNode`（`PointerInputModifierNode`，`sharePointerInputWithSiblings() = true`），与内容共享触摸、不消费。手指按住且不超过 touch slop 达 120 ms（`HoldToGrabMillis = 120L`），且内容不在滚动（`contentScrolling` lambda）时才抓。抓住后在 Initial 阶段消费所有变化，y 方向拖拇指，`tryEmit` `DragInteraction` start / stop。
- 快甩先越过 slop，照常滚内容并带惯性；惯性中按下只停住内容，不算抓。
- 重叠的兄弟节点，命中测试到第一个被命中的就停，除非它共享指针输入；所以旁边那段必须 `sharePointerInputWithSiblings() = true`，否则内容收不到事件。原 KDoc 写反了，已更正。
- 列表、网格、瀑布流和番剧详情页剧集网格的 `IrregularVerticalGridFastScroller` 四根都用同一个 `HarmonyScrollerThumb`；第四根是本仓独有，rebase 时不要漏。

**重做要点**：
- 两段热区不要合并回一个按下即抓的 32 dp（那就是 0027 / 0035 时代误抓往回甩的原因），也不要只留 12 dp（0040 时代很难按）。
- 120 ms 远小于 500 ms 长按超时。抓住后一移动就取消条目长按；一动不动按满 500 ms 仍会弹长按菜单，这是已知副作用。
- `VerticalFastScroller.kt` 的 Harmony 段与 Mihon 0035 保持一致。

新测试 3 个：`a press and hold beside the thumb grabs it`、`a hold beside the thumb during a coast does not grab it`、`a tap beside the thumb does not move the list`。0040 的 `a downward flick beside the bottom thumb still coasts` 照常通过。

同病：Mihon 0035 同轮已修。Animeko 不适用：Android 上的 `LazyListVerticalScrollbar` / `ScrollStateVerticalScrollbar` 只是 `…ScrollIndicator` 指示器，不能拖。

补丁 0044 与 mihon-harmony 0036 同源。用户 2026-10-14 想记录书架上下滑和惯性时的帧率 / 耗时（「有时候又很丝滑」），要一个临时调试按钮导出脱敏日志，不依赖 IP 或 token。

做法：设置 → 高级 →「滚动性能记录（调试）」，pref `harmony_scroll_perf_recorder`（本仓是函数 `scrollPerfRecorder()`，Mihon 是属性），默认关。`MainActivity` 里 `HarmonyFramePerf.bind(this, pref.changes())`。打开且 Activity 在前台时，往首次 attach 时分配、关掉就释放的原始类型环形缓冲里写（约 1 MB）：
- FrameMetrics 每帧各阶段，在独立 HandlerThread 上回调；GPU 和 DEADLINE 只在 API 31+ 有，否则写 -1。6000 帧。
- 主线程 Choreographer 帧间隔 6000 个，FrameMetrics 不工作时也有。每个间隔带全景滚动阶段（idle / drag / fling，`PanoramaScrollTrace` 里的 volatile，在 down / up / fling start / fling end 设置），以及 `PanoramaFrameCounters` 的测量次数、测量总耗时和新组合格子数。热路径只有一对 `nanoTime` 和加法，不分配。
- 每 500 ms：GC 次数增量、进程 CPU 增量、刷新率与模式、温控（API 29+）、省电模式。
- attach 后 3 秒没有帧回调（会 invalidate decor 逼一帧）时，导出写「FrameMetrics 未提供」，摘要只用 Choreographer 间隔。

记录时左下角（safeDrawing 内、底栏之上）有 40 dp 半透明「记录」按钮，别处的触摸穿透。点按会在滑动轨迹写 `mark user`，在后台线程生成缓存目录下的 `<app>_scroll_perf_<yyyyMMdd-HHmmss>.txt`，和「转储崩溃日志」一样打开分享面板。

导出由纯函数 `PerfReport` 只用数字生成，末行 `privacy: no titles, urls, extension list or logcat text`。不含 logcat 原文、标题、URL、扩展列表、文件路径、账号和 `HarmonyLogBuffer`。卓易通图形层噪音只按 `HARMONY_NOISE_MARKERS`（`CrashLogUtil` 的 companion 改为 `internal` 以共用）每秒计数。卡顿判据：已知 DEADLINE 时 TOTAL > DEADLINE，否则 > 1.5 个 vsync。

开着时的开销：每帧一次后台 FrameMetrics 回调、每个 vsync 一次 Choreographer 回调（主线程按刷新率唤醒），以及 500 ms 采样。关着时什么都不跑。

**重做要点**：
- `HarmonyFramePerf.kt`、`HarmonyFramePerfTest.kt`、`PanoramaFrameCounters.kt`、`PanoramaScrollTrace.kt`、`PanoramaMasonry.kt` 与 Mihon 0036 **逐字节相同**，改一处要同步另一处。
- 字符串在 `i18n-ank` base + zh-rCN 的 Harmony 段。
- 导出内容只能是数字和固定标签。往里加字段前先想清楚会不会带出书名 / 网址。
- 分析脚本在归档仓 `tools/scroll-perf-analyze/analyze.py`，导出格式变了要一起改。

开发树 HEAD 复跑 `:presentation-core:testDebugUnitTest :app:testDebugUnitTest` 通过（presentation-core 59 个用例，0 失败，2 跳过；app 27 个）；发版前另跑了 spotless 和 `:app:compilePreviewKotlin`。

同病：Mihon 0036 同轮已加。Animeko 不适用：用户没报 Animeko 卡顿，它也没有全景网格；需要时可移植 `HarmonyFramePerf`，去掉全景计数器即可。


### 0045：全景浏览分页快照刷新

用户在 `v0.2.0-harmony-preview.23` 报告插件浏览页开全景后只显示部分内容，继续下滑无新条目，其他模式正常。`PanoramaMasonryState.intervalsFor` 按 content lambda 身份缓存间隔；原来在 DSL 内读取 `mangaList.itemCount` / `loadState`，新页抵达时 lambda 可被 Compose 复用，布局仍保留旧数量与 footer。

两种 `BrowseSource*Grid` 的全景分支改为在组合阶段捕获 `itemSnapshotList` 和 `loadState`，DSL 使用该快照的 size / key / 封面 id。页数增长、同数量刷新和加载状态变化都会更新内容捕获；格子内保留 `mangaList[index]` 访问提示，不改插件的 PagingSource。此项与 Mihon 0044 的快照捕获同源；Mihon preview.12 已包含，Animeko 没有这套自定义全景布局、不适用。其余性能优化与末端可见项提示未随本修复扩大移植。

目标 `v0.2.0-harmony-preview.24`。验证以改动文件的 Spotless 检查、目标稳定版补丁套用和一次正式签名构建为准；本轮没有 Android 真机 / 模拟器复现，连续分页及搜索 / 筛选切换由用户安装后反馈。

### 0046–0047：通用自动列数与统一全景入口

用户在 Pura X Max 展开模式下希望横屏保持三列、竖屏减为两列，并报告作品详情的相关推荐出现三列中横封面跨两列、右侧空白。旧 Shaped 用网格面积与最大 240dp 理想列宽选最近列，展开竖屏仍挤入三列；Unknown 回退书形 Tiered 列，横封面却跨两列，且推荐页没有浏览页的形状预读。已知形状需半个列表才可确定，也会在分页增多或缩略图失败时长时间停留 Unknown。

0046 按可用宽度、密度和封面高宽比，选择满足可读封面尺寸的最少列数：目标封面高 234dp，列宽范围 104–324dp，横封面能容纳两列时至少两列。高度不参与选列，避免键盘 / 搜索栏改变列数；无机型、屏幕比例或方向判断，手动 Fixed 列数不改。测试样本 459 / 664 / 939dp 的横封面为 2 / 2 / 3；窄屏、大屏和密度边界见新增 PanoramaAutoColumnsTest。

0047 将书架、浏览、相关推荐的舒适 / 紧凑两套入口接到 HarmonyPanoramaGrid（季迁移页复用浏览入口）。Unknown 用与宽封面一致的 Shaped 列且每项一列；已知 Tall 的混排仍保留横封面跨列。格子和布局共享每个网格的占位比例；已缓存形状在首次组合即采样，短列表半数或最多八个已知封面即可决定方向。相关推荐和浏览均只预读可见附近最多 64 个条目、最多四个请求并行，数据更换 / 滚动 / 离开会取消旧预读；图片失败保留占位。首次形状测量也等滚动结束后批量应用。各网格统一四边 8dp 内容留白，滚动条按原 scaffold 内边距计算。preview.24 的分页 snapshot / loadState 捕获继续保留。

已做改动文件 Spotless Apply / Check，真实生产数学与纯策略 JVM 测试 8 项通过；正式构建在 assemblePreview 前跑相关 core 布局、app 形状 / 占位测试。真实折叠窗口、推荐页加载体验与滚动手感由用户安装后反馈。Mihon 共享旧列数数学有同类适用性，待它的维护任务同步；其浏览占位 / 预读已有后续实现，不盲拷 Anikku 分组推荐代码。Animeko 没有此自定义全景组件。历史 / 更新页的单项封面不属于多列网格，未强行改成网格。

### 5.2 加新补丁

在套完现有补丁的源码树上直接改代码并 commit（message 写清楚为什么），`git format-patch -1 --no-signature --zero-commit` 导出，
放进 `patches/`，追加到 `series` 末尾，更新 README 的补丁表。

### 5.3 验证改动但不发版

Actions → Harmony Preview → Run workflow，勾选 `dry_run`。构建完成后在该次运行的 Artifacts 里下载 APK，
用 `apksigner verify --print-certs` 确认证书 SHA-256 与 §2 一致。重签那一步的日志里也会打印。

### 5.4 正式出新版

Run workflow，`upstream_tag` 填官方 tag（留空取最新稳定版），`patch_number` 从 1 开始；同一官方版本改了补丁要重发就填 2、3……
同名 Release 已存在会直接跳过。发版前确认最新上游 tag（定时 run 会自动跟进新上游）。目标 tag 还不存在、且按「上游版本.N」比已发布最高的旧时，workflow 会 `exit 1`（「installs would be a downgrade」），不会发出降级包。

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
| Gradle 报 `Could not find com.github.xxx:yyy`（搜索位置里有 `jitpack.io`） | JitPack 对该版本的构建已失效，本地 `curl https://jitpack.io/api/builds/<group>/<artifact>` 可确认。先查上游 master 是否已换坐标（0005 就是这么来的），有就回迁；没有就自己 fork 该库到 JitPack 能构建的分支 |
| 重签步骤找不到 `app-arm64-v8a-preview.apk` | 上游改了 ABI split 或输出命名，看 `ls -la $apk_dir` 的输出调整文件名 |
| 下载仍然失败，日志里仍有 `Failed to open SAF id` | 说明跑的不是本构建（看 关于 页版本号应含 `harmony`）；或上游新增了别的 SAF 写入点 |
| 下载在「复制」阶段失败（日志 `Failed to create <集>.tmp` 或 `openOutputStream` 异常） | 该设备连普通 SAF 写入都不行；让用户切到「使用应用私有目录」 |
| 鸿蒙图库里能看到视频 | 鸿蒙不认 `.nomedia`，只按扩展名归类。确认 设置 → 下载 → 「下载的视频对系统图库隐藏」开着（preview.2 起默认开），并对升级前的存量文件点一次「按上述设置重命名已下载的视频」；图库可能还缓存着旧索引，重启或等它重扫。仍不行再切「使用应用私有目录」 |
| 下载的视频名字以 `.anikku` 结尾、别的播放器打不开 | 预期行为（见 0006）。去掉后缀即可；或关掉上面的开关并点「按上述设置重命名已下载的视频」把后缀全部去掉 |
| 同一视频在另一个收藏夹里不显示已下载 | 确认 设置 → 下载 → 「不同条目间共用已下载的视频」开着；两条记录的 `url` 必须完全相同（同一来源）；条目页要重新进一次才会重算 |
| Release 步骤失败 `refusing to allow a GitHub App to create or update workflow` | 有人把推 tag 的逻辑加回来了。保持 `gh release create --target $GITHUB_SHA`，不要 `git push` tag |
| 定时任务不跑 | 仓库 60 天无提交被 GitHub 暂停，到 Actions 页面手动 Enable |
| App 内检查不到更新 | 确认 Release 不是 draft / prerelease、tag 含 `-harmony-preview.`、资产文件名含 `-arm64-v8a`，且 `repo` 分支的 `releases.json` 里已有它（0014 起 App 先读镜像）；App 最多每 2 天自动查一次（0014 起已是最新时也会记录检查时间），可在「关于」页手动检查 |
| 安装提示签名冲突 | 设备上还装着官方 Preview（同包名 `app.anikku.beta`）。先备份，卸载官方，再装 |
| 点「检查更新」→「下载」后页面直接退回、之后没任何反应 | preview.2 及之前的旧流程（通知 + 静默安装会话，卓易通都不显示）。升级到 preview.3 起的版本 |
| 更新页一进来（还没点下载）就停在「正在下载… (0%)」，一直不动 | preview.3 / preview.4：「检查更新」排了一个 10 分钟后才跑的后台自动下载，页面把它当成自己的下载（见 0011）。升级到 preview.5；preview.5 之后若再出现，看 `adb shell dumpsys jobscheduler` 里 `AppUpdateDownload` 任务是不是别处排进来的（通知栏「下载」动作、`ComingUpdatesScreen`） |
| 刚装完新版就弹「已更新至 v…」对话框，「更新日志」页面写着「最新: v…-preview.N – 当前: …-harmony.N」，像在推送同一个版本 | preview.5 及之前的 KMK 行为（Mihon 没有这个对话框）。0012 起对话框去掉，「更新日志」直接开当前版本的 Release 网页。「检查更新」在已是最新时一直都是 toast「没有新版本」，若真的弹出更新页，先对比 `GetApplicationRelease.HARMONY_VERSION_REGEX` 与 `BuildConfig.VERSION_NAME` / tag 的格式 |
| 点「下载」后停在「正在下载… (0%)」、按钮灰掉，一直不动（preview.5 / preview.6 也会） | 更新下载是 WorkManager expedited 任务，卓易通从不派发，worker 没跑过（见 0013；这才是 0011 之后还卡住的原因）。升级到 preview.7 起的版本。升级后若 20 秒变「重试」，说明普通任务也没被派发：设置 → 高级 → 转储崩溃日志，看 logcat 里有没有 `WM-WorkerWrapper` 启动 `AppUpdateDownloadJob` 的记录 |
| 「检查更新」toast「HTTP error 403」 | 匿名 `api.github.com` 的配额（每个出口 IP 每小时 60 次）被用完，NAT / 代理后面所有人共用；仓库本身公开可访问。等一小时或换网络；preview.7 起先读 `repo` 分支的镜像（`raw.githubusercontent.com`），一般不会再撞上。仍 403 说明镜像也读不到（被墙 / 超时 10 秒），看 logcat 里的 `Release mirror unavailable` |
| 下载进度到 100% 后变成「!」，重试还是一样；日志里成对出现 `DocumentsContractApi21: Failed to renameTo …/<集>_tmp/<集>.mkv.anikku` 与 `…/<集>` | preview.7 及之前：卓易通 SAF 不支持 `renameDocument`，0001 的回退把整段视频在 SAF 里再复制两遍，失败又没有提示（见 0016）。升级到 preview.8 起的版本；之后再出错，下载队列的那一行会直接写出原因（「出错：…」），把这句话连同崩溃日志一起发来。残留的 `<集>_tmp` 目录不用手动删，重新下载会合并 / 覆盖 |
| 点「下载」按钮没反应、队列为空也没提示 | preview.9 及之前：磁盘上已有同名剧集目录（收尾被打断的残留）但下载缓存不知道，`queueEpisodes` 静默丢弃（见 0018）。preview.10 起会弹「未加入下载队列：…」，残留目录完整则直接登记为已下载，不完整则删掉重下；「不要下载标记剧集」排除的也会说明。若仍无提示，看 crash log 末尾「App log」小节有没有 `Removing incomplete leftover` / `already on disk` |
| 导出的崩溃日志几乎全是 `BLASTBufferQueue` / `SurfaceDelegator` | 卓易通图形层噪音。preview.10 起会被过滤并在「--- Logcat (N … filtered) ---」里计数；应用自己的日志看末尾「App log」小节。出现新的刷屏 tag 就往 `CrashLogUtil.HARMONY_NOISE_MARKERS` 加子串（与 Mihon 同步） |
| 更新页点「下载」后，上面的版本说明文字随进度一直闪烁 / 短暂变空 | preview.8 及之前：每个进度 tick 都新建 `GFMFlavourDescriptor()`，Markdown 渲染库当成内容变了重新解析（见 0017）。升级到 preview.9 起的版本；按钮上的百分比照常跳动即可，说明文字不应再变 |
| 刚发版几分钟内「检查更新」说「没有新版本」 | `raw.githubusercontent.com` 对 `releases.json` 有最多约 5 分钟缓存，加上 OkHttp 本地缓存；等几分钟再点。确认 `repo` 分支的 `releases.json` 已包含新 tag（发版 workflow 最后一步「Update the release index」） |
| `repo` 分支的 `releases.json` 没更新 / 不存在 | 发版 workflow 的最后一步失败，或 Release 是手动改的而 `release_index.yml` 没跑。到 Actions 手动运行「Release index」；本地也可 `GH_TOKEN=... scripts/write-release-index.sh Xun2202/anikku-harmony` |
| 「安装」后系统提示「解析软件包时出现问题」 | 旧版本的 `update.apk` 没删干净，`downloadFileWithResume` 把新包接在了后面（0011 起每次下载前先删）。清除 Anikku 缓存后重试 |
| 后台下载停住 / 切回 App 才继续 | 卓易通冻结后台进程。确认 设置 → 下载 →「后台保持运行（鸿蒙）」开着（preview.3 起默认开）；logcat 里应有 `Background keep-alive started`。若鸿蒙后续版本连静音音频也拦，只能等上游 / 系统变化 |
| 闪退 `ForegroundServiceDidNotStopInTimeException ... type dataSync` | Android 15 对 dataSync 前台服务的 6 小时限制，通常是后台被冻结、服务空转耗光额度。开着「后台保持运行（鸿蒙）」时下载服务是 `mediaPlayback` 类型不受限；关着就隔几小时切回前台重置额度 |
| 下载时其他 App 的音乐被暂停 / 变小声 | 不应发生：keep-alive 不请求音频焦点。若出现，检查 `BackgroundKeepAlive.kt` 是否被改成了 `requestAudioFocus` |
| 下载通知一直只有速度、没有百分比 / 进度条在滚动 | ffmpeg 的 `StatisticsCallback` 还没报出时间，或 `getDuration()` 拿不到时长（部分 HLS 源），这是预期显示；速度一直 0 B/s 则看 ffmpeg 是否真的在写文件（`s.size` 不增长） |
| 「检查更新」拿到的不是最新 tag | 0024 之前 `getLatest()` 取列表第一项。0024 起按版本四元组取最大；若再现，`curl` 镜像 `releases.json` 看 tag 是否符合 `v<x>.<y>.<z>-harmony(-preview).<n>` |
| 全景网格上下滑动时右侧快速滚动条抽搐 | 0020–0022 用屏上平均高度估算。0023 起按索引记高度；若再现，看 `VerticalFastScroller.kt` 的估算段是否还与 Mihon 0016 一致。格子高度在滑动中变化造成的残余抽搐由 0025 消除（滚动条代码没动） |
| 全景网格滑动时各个资源块排版抽搐、感觉掉帧 | preview.13 及之前：比例只在进程内，格子先按 3:2 排、解码完改 2:3，瀑布流整列重测；横竖切换还重建 `AsyncImage`。0025（preview.14）起形状写在 `filesDir/harmony_panorama_cover_shapes.txt`，滑动中不把新形状写进布局。从没见过的封面仍会在停下时跳一次。拖滚动条的间隙和浏览页未上屏封面由 0027 补（下两行里的第二行）。掉帧要真机确认。若只有 Anikku 卡、Mihon 丝滑，先看再下一行（0026 的转圈） |
| 全景紧凑网格比 Mihon 卡、每个封面都在转圈 | preview.14 及之前：`MangaCover` 用 `SubcomposeAsyncImage`，懒加载网格每个格子再套一层，加载中的不定型转圈每帧都画；`SourceIconBadge` 每次组合读 `Source.icon`。0026（preview.15）起改 `AsyncImage` + 色块，转圈延迟 400 ms，角标 `remember(source.id)`。Mihon 没有这层 |
| 全景网格拖右侧滚动条、或连续甩两下时格子还会跳；浏览页新滑出来的格子第一次形状不对 | preview.14（0025）把「停下」定义成 `isScrollInProgress` 为假。0027（preview.15）起连续 300 ms 不滚动才算停下；浏览页对已加载未上屏封面按 128 px 提前学形状（`PanoramaCoverShapes.kt` 与 Mihon 0019 逐字节相同）。相关作品页只有防抖、没有预取。刚打开的第一屏在静止时仍可能翻一次；下载失败保持默认横版。往下滑时拇指大约每行回跳由 0028 补（下一行） |
| 全景网格往下滑时右侧滑动块大约每一行往回抽一下，再移回来 | preview.15（0027）修的是格子形状，滚动条估算没动。0028（preview.16）与 Mihon 0020 同源：位置跨帧累加，滚动中冻结总长度，停下 150 ms 平滑，到底比例为 1。`StaggeredGridEstimate` 段逐字节相同。0030 起这套估算已删除，滚动条改用真实内容高度（下一行） |
| 全景网格末尾左边空一块；折叠屏展开后最后几项和前面空一格，滑一下才重排 | preview.16 及之前用 Compose `LazyVerticalStaggeredGrid`：零容差放进最短列；列数一变把可见项当新起点。0030（preview.17）与 Mihon 0021 同源：自建 `PanoramaMasonryLayout`，放进底边 ≤ 最短列 + 本项高×0.5 的最左列；列数 / 宽度变化同一次测量里重算并用视口顶部项 key 钉住。模拟器（AVD harmony34）：短列只凹约 20px 时留左列；`wm size 2200x2480` 当帧四列，`wm size reset` 不跳回顶部。真折叠屏只用 `wm size` 模拟。验收要先滚到中部再改宽度 |
| 全景网格格子里的标题被裁掉 | 松散模式标题行高按 2×18sp 写死，另加上下各 4dp。系统字体调大时格子仍按这个高度排，多出来的字被裁。改行高就改 `panoramaCoverCellHeightPx` 里的 18sp，与 Mihon 一起改 |
| 上游改了封面横竖阈值或标题行数，全景格子高矮不对 | 高度不测量、按公式算（`panoramaCoverCellHeightPx`）：槽宽先减左右各 4dp；宽封面 3/2、高封面 2/3；格子高 = 封面高 + 上下各 4dp；松散再加标题 4dp×2 + 2×18sp；浏览加载行 72dp、相关作品加载行 56dp。阈值常量名本仓是 `RatioSwitchToPanorama`，Mihon 是 `RATIO_SWITCH_TO_PANORAMA`，逻辑相同，不要改成对方的名字 |
| 下载画质一直等于播放画质，找不到单独的设置 | preview.15 及之前：没指定视频的剧集走 `getBestVideo`，取扩展标成 preferred 的视频，和播放相同。只能作品页长按剧集「选择视频画质」逐集选。0029（preview.16）起 设置 → 下载 →「下载画质」（`harmony_download_quality`，默认最高可用，在「并发下载」滑块下方）。选项共 8 个。长按逐集选的仍优先。扩展只给一种画质时没有区别（RouXun 一条 HLS）。真实下载未在模拟器上跑 |
| 手机提示版本过老 / 降级不给装 | 更新器按版本号取最大。官方出了更高的上游之后，定时 run 会自动发新底座的 preview.1；若再在更旧的上游上发一版，versionCode 更小，手机拒装。2026-10-13 Mihon 先撞上（`v0.21.1-harmony-preview.5` 低于已装的 `v0.21.2-harmony-preview.1`）。本仓同一段「Resolve release version」（提交 `af6652f`，与 mihon-harmony `fd1835633` 同源）：非 dry_run 且目标 tag 还不存在时，按「上游版本.N」`sort -V`，比已发布最高的旧就 `exit 1` 报「installs would be a downgrade」。已存在的 tag 仍 skip，定时 run 不会因此变红。发版前先看 Releases 上最新的上游底座。本地用真实 tag 列表测过：0.2.0 的 preview.15 拒绝，preview.17 放行。CI 上没实际触发过拒绝路径 |
| `:app:spotlessCheck` 报 `DownloadNotifier.kt` / `MangaScreenModel.kt` 的 import 顺序（`AYMR` 应在 `AMR` 前） | 更早 Harmony 补丁带进来的，与 0025 无关。CI 不跑 spotless。**待办：下次 rebase 顺手修**（见 §5.1 0025） |
| 书架「全景松散网格」每行「自动」时横版封面偏窄、挤；竖版和横版同一行时横版下面一大块空白 | preview.10 及之前：自动列宽沿用 128 dp、`LazyVerticalGrid` 整行按最高格子算。preview.11 起全景模式改瀑布流 `LazyVerticalStaggeredGrid` + 自动列宽 168 dp（补丁 0020）。手动设了每行数量的只有排布变化、宽度不变；浏览页 / 相关作品页的全景网格 preview.12 起由 0021 同样处理。168 dp 在 360 dp 宽上只有 2 列，由 0036 分档取代（下一行） |
| 全景点进条目再返回，回到最顶 | preview.17 及之前：`rememberPanoramaMasonryState` 用父组合 `SideEffect` 把锚点拷进 `rememberSaveable`，滑动不重组父组合，存下的永远是 0。0032（`v0.2.0-harmony-preview.18`）起按 key 存，列表加载完整后再恢复。书架、浏览、相关作品全景都改了。没有真机手势测试 |
| 2000 项书架高速松开后惯性滑动一卡一卡 | 与 Mihon 0025 / 0026 / 0029 同一处。0033 加 `PanoramaMasonryContentEpoch`（2000 项、120 帧：每帧 0.323 ms → 0.0082 ms，分配 266,776 B → 56 B）。0034 形状表按版本通知，阈值名仍是 `RatioSwitchToPanorama`。0037 瀑布流滚动条改为单个 `LaunchedEffect` + `snapshotFlow`；剧集网格滚动条同样改了。可装的是 preview.18。上游列表 / 网格的 `LaunchedEffect(firstVisibleItemScrollOffset)` 故意没改 |
| 按住滚动条快速下翻时拇指变透明，松手方向变成上翻 | 0035（preview.18）与 Mihon 0027 同源：`startDragImmediately`，按住期间不淡出、不摘手势，触摸区 32 dp。本仓多一根番剧详情页剧集网格的 `IrregularVerticalGridFastScroller`，一起修了 |
| 全景「自动」在折叠屏只有两列，竖封面过大、横封面过小 | preview.17 及之前自动最小列宽 168 dp。0031 起横封面在 ≥3 列时跨两列。0036 起 `PanoramaColumns.Tiered`，常量在 `PanoramaGrid.kt`：网格宽 < 600 dp 最小 112 dp，≥ 600 dp 用 140 dp。360 / 420 / 459 dp → 3 列，939 dp → 6 列。比较的是网格自身宽度。横封面多时右列空、以及按主导形状定列，见下两行 |
| 横封面多时右列空 | 折叠 459 dp 按 `Tiered` 分 3 列，横封面 `TwoLanesWhenRoomy` 跨两列，等高时取最左，横封面占多数时第 3 列永远空。折叠竖全景紧凑看起来只有一列、右边空着。0038 / 0039（`v0.2.0-harmony-preview.19`）改为 `Shaped` + 形状模式：折叠竖 + 横书架为 2 列宽封面。相关作品两套也按自己的条目统计。形状未学够时先按 Tiered，判定后最多跳一次。40–60% 横的混合书架仍按 Tall（跨列），偶尔会有空位。阈值名 `RatioSwitchToPanorama`，常量在 `PanoramaGrid.kt` |
| 到底往回滑没惯性 | 0035 的热区 32 dp，比画出的拇指（12 dp）向内容侧多约 20 dp 透明区，且按下即抓。到底时拇指停在右下角，往回滑被当成拖滚动条，松手没有惯性。用户说没动滑块，碰到的是透明的那一截。0040 起热区改为 `ThumbThickness + endInset`。第四根 `IrregularVerticalGridFastScroller`（番剧详情页剧集网格）一起改了。测试与 Mihon 0032 同一份数字：修前距右缘 20 dp 起滑 0 px，修后 4462 px / 134 帧；滚到底再向下甩，修前 0 px，修后 247.72 px（中央基线的 100%）。UI 测试用 `runComposeUiTest`。热区变窄后能否稳稳按住拖，要真机确认。preview.19 对应的「到底往回滑没惯性」可能也有下一行的浮点剩余（热区确实也会抓），把握不足。若收回热区之后、不在底部时仍没惯性，见下两行 |
| 书架中间滑完没有惯性 | preview.20 的日志否定了「触摸送慢了、速度被算成 0」，结论与 Mihon 0033 / 0034 相同：往下翻正常，一次往回甩之后连续 5 次 `fling start v=0`，`trackerV` 仍有几千，`gapLastMove` 只有几毫秒。0041 的轨迹还在，只记全景网格。根因与修法见下一行。0042（`v0.2.0-harmony-preview.21`）起没碰到两端时返回精确 delta，与 Mihon 0034 同源。若仍复现，立刻转储，最近 400 条会覆盖 |
| 自写 ScrollableState 必须精确返回 delta，否则 pullToRefresh 会吃回甩速度 | 与 Mihon 0034 同一条。`PanoramaMasonry.kt` 两边逐字节相同。旧代码上同一条测试同样失败：offset 70000、包在 `pullToRefresh` 里，先往下翻 3 次再往回甩 4 次，起速 `[5120, 5120, 5120, 0, 0, 0, 0]`；0042 之后往回甩为 -5120。只有全景网格是自写的 ScrollableState。以后新写的滚动容器同样要遵守 |
| 发版等待脚本把一次 API 报错当成 dry_run 已完成 | preview.20 的正式 run 38553915121 在 dry_run 38553804454 结束前就触发了。正式 run 在同一并发组里排队，等 dry_run 成功后才执行，结果无影响。等待循环要把取不到 `conclusion` 当作「未完成」。preview.21 的正式 run 38559880393 是在 dry_run 38558928679 成功之后才触发的，等待脚本已修好 |
| 滚动条又很难按到（preview.21 及之前） | 0040 把热区收回为画出来的拇指宽（12 dp + 边距），不再误抓往回甩，但手指很难按中。0043（`preview.22`）起热区恢复 32 dp + 边距，分两段：按在画出来的拇指上立即抓；拇指旁边那 20 dp 与内容共享触摸（`sharePointerInputWithSiblings() = true`，否则重叠的兄弟节点命中测试到第一个就停，内容收不到事件），只有手指按住、不超过 touch slop 达 120 ms，且内容没在滚动时才抓。快甩会更早越过 slop，照常滚内容带惯性；惯性中按下只是停住内容，不会抓。已知副作用：在拇指旁边一动不动按 500 ms 仍可能触发条目长按菜单。与 Mihon 0035 同源 |
| 觉得上下滑 / 惯性时卡，有时又很顺 | 0044（`preview.23`）起：设置 → 高级 →「滚动性能记录（调试）」，默认关。打开后左下角出现半透明「记录」按钮，感觉卡的时候立刻点，分享出来的 `<app>_scroll_perf_<时间>.txt` 发来。文件只有数字：FrameMetrics 各阶段耗时、Choreographer 帧间隔、每帧全景测量次数 / 耗时 / 新组合格子数、每 500 ms 的 GC / CPU / 刷新率 / 温控 / 省电、每秒卓易通图形层噪音行数（只计数）和全景滑动轨迹；不含标题、URL、扩展列表、logcat 原文。分析：归档仓 `tools/scroll-perf-analyze/analyze.py <文件>`。卡顿判据：有 DEADLINE 时 TOTAL > DEADLINE，否则 > 1.5 个 vsync。FrameMetrics 3 秒内没有回调时文件里写「FrameMetrics 未提供」，只看 Choreographer 间隔。开着时每帧一次回调、每个 vsync 唤醒主线程，用完关掉。与 Mihon 0036 同源 |
| `repo` 分支 `releases.json` 第一条不是最新版 | GitHub「列出 Releases」接口不按创建时间排序（2026-10-14 mihon-harmony 的 preview.10 排在 preview.9 等 6 个旧版之后）。三个 App 的更新器都按版本号取最大，不受影响；但只取第一页 30 条时，新版可能被挤出去。`write-release-index.sh` 起翻完所有页、按 `created_at` 倒序取 30 条（三个流水线同一改动）。raw CDN 约 5 分钟缓存，要看即时内容用 `gh api "repos/<repo>/contents/releases.json?ref=repo"` |

## 8. 不要做的事

- 不要把 token、密钥或密码提交进仓库（这是公开仓库）。
- 不要改 Release tag 格式和资产命名规则（更新器依赖）；不要把 Release 标成 prerelease。
- 不要往仓库里放 Anikku 源码快照。
- 不要上传名字里含 `-arm64-v8a` 的非 APK 资产。
- 不要改 `applicationIdSuffix`：改了会和用户已装的版本变成两个 App，SAF 授权也要重做。

## 9. 时间线

- 2026-10-05 根据用户上传的崩溃日志定位根因（ffmpeg-kit SAF open 失败 + renameDocument 不支持），写出补丁 0001–0004，
  建立本仓库和流水线；生成签名密钥并存入 `Xun2202/keystores/anikku-harmony/`，写入四个 Secrets。
  首次 dry_run 在依赖解析阶段失败（JitPack 不再提供 FlexibleAdapter c8013533），加入回迁补丁 0005，并让 `prepare-source.sh`
  自动跳过上游已合入的补丁。发布 `v0.2.0-harmony-preview.1`（versionCode 801），用户确认下载可用。
- 2026-10-05 用户反馈鸿蒙图库仍收录下载的 `.mkv`（`.nomedia` 无效），以及 XvXun 多个收藏夹里同一视频下载状态不互通。
  加入补丁 0006（`<集>.mkv.anikku` + 设置开关 + 存量改名）和 0007（同一来源按 url 共用下载），发布 `v0.2.0-harmony-preview.2`（versionCode 802）。
- 2026-10-06 用户反馈应用内更新点「下载」后页面直接退回、没法安装，以及（与 Mihon 相同的）切后台下载停住。加入补丁 0008
  （更新页面留在原地：进度 + 「安装」按钮，跳过卓易通不支持的静默安装会话）和 0009（后台保活：静音 `AudioTrack` + 唤醒锁，
  下载服务改 `mediaPlayback`，设置开关），发布 `v0.2.0-harmony-preview.3`（versionCode 803）。
- 同日 用户要求三个鸿蒙版应用的下载通知统一成 Animeko 的样式（速度 + 进度）。加入补丁 0010（与 mihon-harmony 0006 同源的
  `DownloadSpeedMeter`、通知重写、1 Hz 刷新替代 50 ms 轮询），`dry_run` 验证后发布 `v0.2.0-harmony-preview.4`（versionCode 804）。
- 2026-10-06（晚） 用户反馈 preview.4 应用内更新「一直卡在正在下载，进度不动」。根因是 KMK 的定时后台自动下载与更新页下载同名（见 0011）；
  顺带回答「更新完的 APK 会不会一直占空间」：此前不会删，0011 起启动时自动删。加入补丁 0011，`dry_run` 验证后发布 `v0.2.0-harmony-preview.5`（versionCode 805）。
- 同日（夜） 用户装上 preview.5 后反馈「点检查更新也弹出来个 5，Mihon 会显示没有新版本」。版本比较本身正确（dex 里确认），用户看到的是 KMK 装完新版后的
  「已更新至 vX」对话框和「更新日志」页面的「最新 / 当前」标题。加入补丁 0012 与 Mihon 对齐，`dry_run` 验证后发布 `v0.2.0-harmony-preview.6`（versionCode 806）。
- 同日（深夜） 用户反馈「检查更新」报「HTTP error 403」（匿名 GitHub 接口配额，三个 App 同病），随后又反馈 preview.5 点「下载」仍停在「正在下载 0%」、按钮灰掉。
  后者的真正原因是 KMK 把更新下载排成 expedited WorkManager 任务、卓易通不派发（0011 去掉的后台自动下载是同时存在的另一个阻塞点，但不是全部）。
  加入补丁 0013（普通任务 + 更新页看门狗）和 0014（先读 `repo` 分支的 Release 索引镜像 + 修 `lastChecked`），流水线新增 `write-release-index.sh` / `release_index.yml`，
  三个鸿蒙版仓库同步建立 `repo` 分支。`dry_run` 验证后发布 `v0.2.0-harmony-preview.7`（versionCode 807）。
- 2026-10-11 用户反馈 XvXun 这类 16:9 封面在书架里都是竖版显示，切到「全景松散网格」后封面反而更小、上下有两条看不见的空边。
  根因是 `LibraryComfortableGrid` 没传 `fitToPanoramaCover`，格子仍按 2:3 竖版算高度。加入补丁 0015（与浏览页对齐），`dry_run`（run 38118421200，versionCode 815）
  编译通过；在 Android 14 x86_64 模拟器（TCG，无 KVM）里装本地构建 + XvXun 两个条目，普通网格 vs 全景松散网格对比截图确认格子变成 3:2 横版、无空边。
- 同日 用户反馈下载「进度满了变成惊叹号」并提供日志：`DocumentsContractApi21: Failed to renameTo …/Video_tmp/Video.mkv.anikku` 和两秒后的
  `…/Varesa/Video`，说明 0001 的改名回退在收尾处连续触发（卓易通 SAF 不支持 `renameDocument`），每次都是整段视频再复制一遍，之后的失败没有任何可见原因
  （出错路径之一不通知不记日志，ffmpeg 失败只有 "Error in ffmpeg!"）。加入补丁 0016（直接写最终名 + 标记、目录 `moveDocument`/合并、收尾重试、缓存保留、
  队列显示原因）。这一张没有单独跑 `dry_run`：本地 `./gradlew :app:assemblePreview -Penable-updater` 编译同一棵树（与 `prepare-source.sh` 干净套用后的
  `Downloader.kt` / `UniFileExtensions.kt` `cmp` 一致），装进模拟器用 SAF 文件夹验证：新流程产物正确（`Video_tmp/Video.tmp` 标记 → `Video/Video.mkv.anikku` +
  `.nomedia`，`_tmp` 目录消失）；iptables 只封 CDN 一个 IP 时首次 ffmpeg I/O error、2 秒后重试换到另一 IP 成功；封整个 CDN 网段时 4 次尝试全失败，
  队列行显示「Error: ffmpeg: [tcp @ …] Connection to tcp://hls-cdn77… failed: Network is unreachable」，解除封锁后点「继续」重试成功。
  正式发版 run 38128844399 → `v0.2.0-harmony-preview.8`（versionCode 808，versionName `0.2.0-harmony.8-8907`，签名 `cf7a2adc…d829`，
  `repo` 分支 `8b43542` 已含 preview.8）。卓易通特有的「`renameDocument` 不支持 → `moveDocument` / 复制合并」分支模拟器复现不了，等用户真机。
- 同日 用户装上 preview.8 后反馈：更新页点「下载」时，新版本的说明文字一直闪烁。读 multiplatform-markdown-renderer 0.39.2 源码确认
  `rememberMarkdownState` 以 flavour 为输入键，而 KMK 的 `NewUpdateScreen` 每次重组都新建 `GFMFlavourDescriptor()`（Mihon 上游是 `remember`）。
  加入补丁 0017（`remember` + ffmpeg 原因去 `[tcp @ 0x…]` 前缀）；本地 `assemblePreview -Penable-updater` 编译通过，干净 v0.2.0 上 `prepare-source.sh … 9`
  套用 17 张补丁后与本地树 `cmp` 一致。同时把 Mihon 的同病（矩阵 #25）移植为 mihon-harmony 0010 并发布 `v0.20.4-harmony-preview.9`。
  正式发版 → `v0.2.0-harmony-preview.9`（versionCode 809）。闪烁本身在无 GPU 的 TCG 模拟器上截不到稳定画面，按代码分析 + 与 Mihon 相同写法确认。
- 2026-10-12 Mihon 用户上报「点了下载按钮卡一下但没开始」+ crash log 全是卓易通图形层噪音。根因在 Tachiyomi 共享的 `queueChapters/queueEpisodes` 静默过滤（B 层），
  Anikku 同病：移植为 0018 / 0019（Mihon 为 0011 / 0012），本地 `:app:compilePreviewKotlin` 通过，干净 v0.2.0 上 19 张补丁套用后与开发树一致，`check_patches` run 38206407935 绿。
  `dry_run` run 38206483876 绿后发起的第一次正式发版 run 38207083959 在发现「点『!』重试会被算成已在队列中」后主动取消（未产生 Release），
  把 `retried` 的拆分并进 0018 重新导出 → `dry_run` run 38207400700 绿 → 正式 run 38208443188 → `v0.2.0-harmony-preview.10`（05:39 UTC，versionCode 810，
  versionName `0.2.0-harmony.10-8910`，签名 `cf7a2adc…d829`，arm64 90,132,597 B，SHA-256 `f5b76768…58ca`，DEX 含 `HarmonyLogBuffer` / `already on disk as`，
  `resources.arsc` 含 `harmony_download_skipped*`，`repo` 分支 `8abd41a`）。Mihon 同轮为 preview.10（0011 / 0012）+ preview.11（0013）。
- 2026-10-12（下午） 用户：「全景松散网格每行自动时横着的封面默认宽度有点窄…像之前竖屏的宽度，很拥挤，但也别太宽；竖屏和横屏一排会把横屏下面挤出空隙，能不能排布下」。
  根因两条：自动列宽是书形网格的 `GridCells.Adaptive(128.dp)`（3:2 格子只有 2:3 格子那么宽、三分之二高）；`LazyVerticalGrid` 每行按最高格子算高度，2:3 和 3:2 混排时横版下面空出约 0.8 个格宽。
  补丁 0020：全景模式改 `LazyVerticalStaggeredGrid`（每列各自往下排，不留空），自动列宽 168 dp（手机两列，≈530 dp 起三列；固定列数不变），`presentation-core` 新增 `VerticalStaggeredGridFastScroller` / `FastScrollLazyVerticalStaggeredGrid`，
  封面横竖比按作品缓存到进程生命周期（滚回视野不再先书形再跳横版，全景模式未知封面默认 16:9）。本机 `:app:compilePreviewKotlin` + `:presentation-core:spotlessCheck` 通过（`:app:spotlessCheck` 报的两处 import 顺序是 0010 / 0018 带进来的旧问题，CI 不跑 spotless，留待下次动那两张时顺手修）；
  20 张补丁在干净 v0.2.0 上套用后与开发树只差版本号行。推 `main` `9cfb9c8` → `check_patches` run 38259301396 绿 → `dry_run` run 38259313780 绿（DEX 含 `VerticalStaggeredGridFastScroller` / `LazyLibraryStaggeredGrid` / `rememberCoverRatio`）→
  正式 run 38261157970 → `v0.2.0-harmony-preview.11`（14:18 UTC，target `9cfb9c8`，versionCode 811，versionName `0.2.0-harmony.11-8911`，签名 `cf7a2adc…d829`，arm64 90,148,981 B，SHA-256 `283c05e4…c4d8`，universal 282,149,687 B，`repo` 分支 `2944494`）。
  没有模拟器截图（用户 10-11 起要求真机验证排版）；待用户看：自动列数下横版封面是否两列、横竖混排是否不留空、拖快速滚动条是否大致准确。
- 2026-10-12（晚） 用户：「插件浏览里面的全景好像还没同步一样的效果，能不能也加上，其他你也检查下」+ 要求改用「主代理解析意图、Grok 子代理执行、主代理复核」的流程（见 `/workspace/.cursor/rules/orchestration.mdc`）。
  浏览页 / 相关作品页由子代理（grok-4.7-high）改为补丁 0021（瀑布流 + 168 dp，`CountedGridCells` 传列数）；主代理复核作者 / diff / 独立重跑 `:app:compilePreviewKotlin`。子代理顺带排查未改的网格：作品详情页季度网格从不走全景；`MigrateSeasonSelectScreenModel.getColumnsPreference()` 仍返回普通 `GridCells`（靠回退分支拿列数）；
  `GlobalSearchCardRow` / `HistoryItem` / `UpdatesUiItem` / `MangaInfoHeader` / `DuplicateMangaDialog` / `EditMangaDialog` 不是网格，不动。21 张补丁在干净 v0.2.0 上套用后与开发树只差版本号行。
  推 `main` `fcea12f` → `check_patches` run 38269247489 绿 → `dry_run` run 38269257912 绿 → 正式 run 38270583982 → `v0.2.0-harmony-preview.12`（15:37 UTC，target `fcea12f`，versionCode 812，versionName `0.2.0-harmony.12-8912`，签名 `cf7a2adc…d829`，
  arm64 90,165,365 B，SHA-256 `e745c353…cdb9`，universal 282,166,071 B，DEX 含 `CountedGridCells` / `panoramaStaggeredColumns` / `VerticalStaggeredGridFastScroller` / `rememberCoverRatio`，`repo` 分支 `7a69d99`，`releases.json` 第一项即 preview.12，共 12 条）。
  同轮 Mihon 新增显示模式「全景松散网格」（mihon-harmony 0014，`v0.21.0-harmony-preview.2`）。
- 2026-10-12（深夜） 用户：「能不能加个全景紧凑网络」「上下滑动全景网格的时候右侧竖列进度条好像会抽搐」；另 Mihon 用户侧「没正常拉到更新」查出更新器取列表第一项的 B 层同病。
  0022 / 0023 由子代理（grok-4.7-high-fast）在 `~/work/anikku-v0.2.0` `dev-0015` 写成（`3588902` / `add2616`）；主代理复核：0023 的满行判断从 `@Suppress("INVISIBLE_REFERENCE")` 强转内部 `LazyStaggeredGridMeasuredItem.span` 改为宽度启发式，估算段整段与 Mihon 0016 对齐（`diff` 为空）；0022 的 zh-rTW「全景緊湊格狀」改「全景密集格狀」；0024 主代理自己写（+ 单元测试，顺手修 0014 留下的 `:domain:spotlessCheck` 双空行）。`flock /tmp/gradle.lock ./gradlew :app:compilePreviewKotlin :domain:test :presentation-core:spotlessCheck :domain:spotlessCheck` 通过。
  24 张补丁在干净 v0.2.0 上套用后与开发树只差版本号行。推 `main` `7d01298` → `dry_run` run 38283740364 绿 → 正式 run 38285378680 → **`v0.2.0-harmony-preview.13`**（17:43 UTC，target `7d01298`，非 draft / prerelease；
  `app.anikku.beta`，versionCode 813，versionName `0.2.0-harmony.13-8915`，签名 `cf7a2adc…d829`，arm64 90,165,365 B，SHA-256 `47287904…`，universal 282,166,071 B；DEX 含 `CompactGridPanorama` / `COMPACT_GRID_PANORAMA` / `StaggeredGridMeasurements`，`resources.arsc` 含「Panorama compact grid」「全景紧凑网格」「全景密集格狀」；`repo` 分支 `85b5103`，`releases.json` 第一项即 preview.13，共 13 条）。同轮 Mihon 0015 / 0016 / 0017 → `v0.21.1-harmony-preview.2`。
- 2026-10-13 用户：「滚动条还是会有些抽搐，我有时候也发现上下滑动的时候，各个资源块的排版也会出现轻微抽搐」「全景下，滑动时也有比较明显的掉帧的感觉」。根因与 Mihon 0018 相同（见该仓 MAINTENANCE §5.1）：格子先按默认横版排、解码完改竖版，瀑布流整列重测；横竖两个 Compose 调用点；滚动条残余抽搐是同一件事，0023 没动。
  子代理按 Mihon diff 移植到 `~/work/anikku-v0.2.0` `dev-0025`，提交 `e422fe3`；主代理去掉它顺手改的两处无关 import 顺序（`DownloadNotifier.kt` / `MangaScreenModel.kt`）。`:app:compilePreviewKotlin` 通过。`:app:spotlessCheck` 对这两个文件仍有早就存在的 import 顺序告警（`AYMR` 应排在 `AMR` 前），与 0025 无关，下次 rebase 顺手修（§5.1 待办）。导出 `patches/0025-library-panorama-stable-cell-shapes.patch`。干净 v0.2.0 树 `/tmp/anikku-verify25` 套 25 张成功（versionCode 814），关键文件 `cmp` 一致（`PanoramaCoverShapes.kt` 与 Mihon 逐字节相同）。
  推 `main` `56248d2` → `dry_run` run 38369352313 绿 → 正式 run 38370950359 → **`v0.2.0-harmony-preview.14`**（08:50 UTC，target `56248d2`，非 draft / prerelease；
  `app.anikku.beta`，versionCode 814，versionName `0.2.0-harmony.14-8916`，签名 `cf7a2adc…d829`（与 preview.13 相同），arm64 90,165,365 B，SHA-256 `f4a32d6e…`，universal 282,166,071 B。**体积与 preview.12 / 13 逐字节相同**：APK 有对齐填充，连续几版大小都一样，分辨版本看 SHA-256 / versionCode，不看体积。DEX 含 `PanoramaCoverShapes`（25 处）；`repo` 分支 `releases.json` 第一项即 preview.14，共 14 条）。同轮 Mihon 0018 → `v0.21.1-harmony-preview.3`。Animeko 不适用。掉帧要用户真机确认。
- 2026-10-13 用户：「mihon 的全景紧凑很丝滑，滑块不卡顿，anikku 的还是会卡顿」，接着「现在看 mihon 也会抖，是不是无解了？」。两张补丁：0026 是 Anikku 独有的封面组件（`SubcomposeAsyncImage` + 每帧转圈；`Source.icon` 每次组合都读），0027 与 Mihon 0019 同源（300 ms 才算停下 + 浏览页提前学形状）。根因见 §5.1。
  开发树 `~/work/anikku-v0.2.0` `dev-0025`：0026 提交 `532288b`，0027 提交 `8a889b7`。`:app:compilePreviewKotlin` 通过。`:app:spotlessCheck` 仍只有早就存在的两处 import 顺序告警（`DownloadNotifier.kt` / `MangaScreenModel.kt`），与这两张无关，待办未动（§5.1）。导出 `patches/0026-presentation-cover-asyncimage-smooth-grids.patch`、`patches/0027-library-panorama-settle-debounce-browse-prefetch.patch`（`PanoramaCoverShapes.kt` 与 Mihon 0019 逐字节相同）。干净 v0.2.0 树 `/tmp/anikku-verify27` 套 27 张成功（versionCode 815），关键文件 `cmp` 与开发树一致。
  模拟器（AVD harmony34，TCG 软件加速，本地 x86_64 preview 包，含 0026 + 0027）：书架全景紧凑封面和角标能画出来；本地源 100 条（每 3 条 1 个竖封面），不滑动时 `files/harmony_panorama_cover_shapes.txt` 长到 102 行（浏览 100 + 书架 2；34 条竖约 `1.50`，68 条横约 `0.56`），预取生效；向下甩之后新出现的格子第一次就是对的形状；作品页封面能显示，按封面取的主题色仍套上（`onCoverLoaded` 还在）。帧率测不了，要用户真机确认。
  推 `main` `26c4881` → `check_patches` run 38381660084 绿 → `dry_run` run 38381670886。计划发 **`v0.2.0-harmony-preview.15`**（versionCode 815）。已发布并核对：正式 run 38382880512（10:31 UTC，target `26c4881`），`app.anikku.beta` versionCode 815、versionName `0.2.0-harmony.15-8918`，签名 `cf7a2adc…d829` 不变，arm64 90,165,365 B（体积又与上一版相同，是对齐填充）、SHA-256 `69960800…`，DEX 含 `PrefetchPanoramaCoverShapes` / `rememberPanoramaGridSettled` / `DelayedLoadingIndicator`；`repo` 分支 `releases.json` 第一项即 preview.15（共 15 条）。同轮 Mihon 0019 → `v0.21.1-harmony-preview.4`。Animeko 不适用。
- 2026-10-13（再稍后）用户两件：①「好像还是会抖……大概频率是每一行抽动一下，是不是没找到根因呢？mihon，anikku都是」；②「我在哪可以设置缓存的默认清晰度呢？看起来现在下载的像是按我浏览的清晰度设置的」→「要配置下分开的设置，通常希望下载清晰一些」。两张补丁：0028 与 Mihon 0020 同源（滚动条拇指跨帧累加），0029 是 Anikku 独有的「下载画质」（`harmony_download_quality`，默认最高可用）。根因见 §5.1。
  开发树 `~/work/anikku-v0.2.0` `dev-0025`：0028 提交 `896faf0`，0029 提交 `e4583d6`（0029 是主代理自己写的）。0028：`:presentation-core:spotlessCheck :app:compilePreviewKotlin` 通过。0029：`:domain:spotlessCheck :app:compilePreviewKotlin` 通过；`:app:spotlessCheck` 仍只有早就存在的两处 import 顺序告警（`DownloadNotifier.kt` / `MangaScreenModel.kt`），待办未动（§5.1）。`DownloadQualitySelectorTest` 5/5 通过。导出 `patches/0028-presentation-staggered-scroller-stable-thumb.patch`（`StaggeredGridEstimate` 段与 Mihon 0020 逐字节相同）、`patches/0029-download-quality-separate-from-playback.patch`。干净 v0.2.0 树 `/tmp/anikku-verify29` 套 29 张（`… v0.2.0 16`）成功，关键文件 `cmp` 与开发树一致。
  模拟器（AVD harmony34，TCG 软件加速，本地 x86_64 preview 包）：设置 → 下载里「下载画质」在并发滑块下方，默认显示「最高可用」，弹窗 8 个选项（英文界面）。真实下载未跑。拇指顺不顺测不了，要用户真机确认。
  推 `main` `c49843c` → `check_patches` run 38421742706 绿 → `dry_run` run 38421965352 绿 → 正式 run 38424095190 → **`v0.2.0-harmony-preview.16`**（15:48 UTC，target `c49843c`），`app.anikku.beta` versionCode 816、versionName `0.2.0-harmony.16-8920`，签名 `cf7a2adc…d829` 不变，arm64 90,169,461 B、SHA-256 `f8f32e98…`，DEX 含 `DownloadQualitySelector` / `harmony_download_quality` / 新滚动条字段；`repo` 分支 `releases.json` 第一项即 preview.16（共 16 条）。同轮 Mihon 0020 先发了 `v0.21.1-harmony-preview.5`，同日被 `v0.21.2-harmony-preview.2` 取代（preview.5 不要装，见 mihon-harmony）。下载画质：Mihon 不适用（漫画），Animeko 不适用（播放和缓存共用一套分辨率偏好）。滚动条：Animeko 不适用。
- 2026-10-13（16:09 UTC 前后）与 mihon-harmony 同一处防降级检查。用户在 Mihon 上装了定时任务跟上的 `v0.21.2-harmony-preview.1` 之后，0.21.1 的 preview.5 被手机当成降级拒装。`harmony_preview.yml`「Resolve release version」：非 dry_run 且目标 tag 还不存在时，取本仓所有 `vX.Y.Z-harmony-preview.N`，按「上游版本.N」`sort -V`，比已发布最高的旧就 `exit 1`（「installs would be a downgrade」）。已存在的 tag 仍 skip，定时 run 不会因此变红。本地用真实 tag 列表测过：本仓 0.2.0 preview.15 拒绝、preview.17 放行（Mihon 侧 0.21.1 preview.6 拒绝，0.21.2 preview.3 / 0.21.3 preview.1 / 0.21.10 preview.1 放行）。CI 上没实际触发过拒绝路径。提交 `af6652f`（已推 main；Mihon 同源 `fd1835633`）。发版前要先确认最新上游 tag。本仓没有因此重发 App。
- 2026-10-13（发版）用户两件：① 全景网格末尾一项总进最短列，右边只短一丝也放右边，左边空一块；② 折叠屏展开从两列变四列，最后几项和前面空一格，滑一下才重排。根因见 §5.1 补丁 0030，与 mihon-harmony 0021 同源：Compose `LazyVerticalStaggeredGrid` 零容差最短列 + 列数变化把可见项当新起点。自建 LazyLayout，放进底边 ≤ 最短列 + 本项高×0.5 的最左列；列数 / 宽度变化同一次测量里重算并用视口顶部项 key 钉住；快速滚动条用真实内容高度，0028 的 `StaggeredGridEstimate` 删除。
  开发树 `~/work/anikku-v0.2.0` `dev-0025` 提交 `a455329`。`:presentation-core:spotlessCheck` 通过、`:presentation-core:testDebugUnitTest` 16/16、`:app:compilePreviewKotlin` 通过。`:app:spotlessCheck` 只剩已知的 `DownloadNotifier.kt` / `MangaScreenModel.kt` import 顺序告警，待办未动（§5.1）。导出 `patches/0030-presentation-panorama-masonry-reading-order.patch`（`PanoramaMasonry.kt` / `PanoramaMasonryLayout.kt` / `PanoramaMasonryLayoutTest.kt` 与 Mihon 0021 逐字节相同；`PanoramaCoverShapes.kt` 起只差阈值常量名 `RatioSwitchToPanorama` / `RATIO_SWITCH_TO_PANORAMA`）。干净 v0.2.0 树套 30 张成功（versionCode 817），15 个改动文件 `cmp` 一致。
  模拟器（AVD harmony34，TCG，本地 x86_64 preview）：XvXun 最新两列长列表无左侧空洞（短列只凹约 20px 时留左列）；`wm size 2200x2480` 后当帧四列，`wm size reset` 回两列不跳回顶部（左上格可能挪约一行）；快速滚动条拖动正常；书架下拉刷新触发 `LibraryUpdateJob`（manual，SUCCESS）；浏览翻页正常。真折叠屏只用 `wm size` 模拟。
  推 `main` `a9ecebd` → `check_patches` run 38453486938 绿 → `dry_run` run 38453489044 绿 → 正式 run 38454544696 → **`v0.2.0-harmony-preview.17`**（target `a9ecebd`），`app.anikku.beta` versionCode 817、versionName `0.2.0-harmony.17-8921`，签名 `cf7a2adc…d829` 不变，arm64 90,169,461 B（SHA-256 前缀 `e87c66110faf`；体积与 preview.16 相同，是对齐填充，分辨看 SHA-256 / versionCode），universal 282,166,071 B，DEX 含 `PanoramaMasonryLayout`；`repo` 分支 `releases.json` 第一条即此版（共 17 条）。同轮 Mihon 0021 → `v0.21.2-harmony-preview.3`。Animeko 没有这套网格，不适用。行为差异：本仓保留不规则滚动条淡出；Mihon 书架拇指停留改为约 300 ms，浏览页仍无快速滚动条。
- 2026-10-14（07:42 UTC）与 mihon-harmony 0023–0029 同一轮四件事：返回丢位置、2000 项惯性卡顿、按住滚动条变透明后上翻、自动列过宽 / 横封面过小。根因见 §5.1 补丁 0031–0037。本仓差异：列宽常量在 `PanoramaGrid.kt`，形状阈值名 `RatioSwitchToPanorama`，相关作品全景一并改，第四个滚动条 `IrregularVerticalGridFastScroller`（番剧详情页剧集网格）在 0035 / 0037 里一起修。三个共享文件与 Mihon 逐字节相同。共享测试不再依赖 `java.awt` / `com.sun.management`，AGP 8 不用改 Gradle。`:app:spotlessCheck` 的 import 顺序告警仍是旧待办。
  子代理（grok-4.7-high-fast）实现。主代理复跑 `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 33 通过 / 2 跳过；app 14 个）。干净树 `/tmp/anikku-verify37`（v0.2.0，N=18）套用成功，14 个改动文件与开发树 `cmp` 一致。没有真机 / 模拟器手势测试。
  推 `main` `610c580` → `check_patches` run 38527764370 绿 → `dry_run` run 38527790664 绿 → 正式 run 38529023403 → **`v0.2.0-harmony-preview.18`**（07:42 UTC），`app.anikku.beta` versionCode 818、versionName `0.2.0-harmony.18-8928`，签名 `cf7a2adc…d829` 不变，arm64 90,185,845 B（SHA-256 前缀 `8a97b8189469`），universal 282,182,455 B，DEX 含 `PanoramaColumns$Tiered`、`holdOpaqueWhileThumbGrabbed`、`PanoramaMasonryContentEpoch`，另含 `harmonyThumbTouch`；`repo` 分支 `releases.json` 18 条，第一条即此版。series 37 张（0001–0037）。同轮 Mihon 0023–0029 → `v0.21.2-harmony-preview.5`。Animeko：滚动条按住、惯性卡顿、自动列宽不适用；返回丢位置待确认。
- 2026-10-14（10:34 UTC）与 mihon-harmony 0030–0032 同一轮两件事：横封面多时全景右列空，滑到底再往回甩惯性消失。根因见 §5.1 补丁 0038–0040。本仓差异：阈值名 `RatioSwitchToPanorama`，列宽常量在 `PanoramaGrid.kt`，相关作品两套一并按自己的条目统计，第四个滚动条 `IrregularVerticalGridFastScroller` 在 0040 里一起修，junit-vintage 6.0.3，UI 测试用 `runComposeUiTest`。`PanoramaShapeMode.kt` 在 app 层。`committedShapeVersion` 只在主线程写，measure 不读。三个共享文件与 Mihon 逐字节相同。测试依赖不进包（preview 对库模块回退 release 变体）。
  子代理（grok-4.7-high-fast）实现。主代理复跑 `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 51 个用例，0 失败，2 跳过；app 21 个）。干净树 `/tmp/anikku-verify40`（v0.2.0，N=19）套用成功，21 个改动文件与开发树 `cmp` 一致。没有真机手势测试。
  推 `main` `570066f` → `check_patches` run 38548386536 绿 → `dry_run` run 38548398379 绿 → 正式 run 38549488071 → **`v0.2.0-harmony-preview.19`**（10:34 UTC），`app.anikku.beta` versionCode 819、versionName `0.2.0-harmony.19-8931`，签名 `cf7a2adc…d829` 不变，arm64 90,185,845 B（SHA-256 前缀 `772e6e5232a9`；体积与 preview.18 相同，是对齐填充，分辨看 SHA-256 / versionCode），universal 282,182,455 B，DEX 含 `PanoramaColumns$Shaped`、`PanoramaShapeMode`、`committedShapeVersion`；manifest 无 ui-test 的 ComponentActivity；DEX 里 `robolectric` 字符串 3 处，与上一版相同。`repo` 分支 `releases.json` 19 条，第一条即此版。series 40 张（0001–0040）。同轮 Mihon 0030–0032 → `v0.21.2-harmony-preview.6`。Animeko：列数按形状、滚动条热区、惯性都不适用。
- 2026-10-14（11:19 UTC）与 mihon-harmony 0033 同一轮：书架中间偶发滑完没有惯性。preview.19 收回热区只解释「到底往回滑」。没有真机数据，先发诊断版，不改滑动行为。根因见 §5.1 补丁 0041。本仓差异：`HarmonyLogBuffer` 是 0019；只记全景网格，第四根 `IrregularVerticalGridFastScroller` 不在轨迹里；编的是 Preview，没有 `:app:spotlessCheck`。`PanoramaScrollTrace.kt` / `PanoramaMasonry.kt` 与 Mihon 逐字节相同。
  `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 54 个用例，0 失败，2 跳过；app 21 个）。干净树 `/tmp/anikku-verify41`（v0.2.0，N=20）套用成功，23 个改动文件与开发树 `cmp` 一致。开发树 `dev-0031` 提交 `b831ddf`。新测试 3 个与 Mihon 同一份（dist 4462、frames 132；`scrollToOffset 1000` 之后 `fling cancelled`；停 60 ms 得 `gapLastMove=60ms trackerV=0 recentV=-2215`，`fling start v=0`，惯性 0）。
  推 `main` `101835a` → `check_patches` run 38553793027 绿 → `dry_run` run 38553804454 绿 → 正式 run 38553915121 → **`v0.2.0-harmony-preview.20`**（11:19 UTC），`app.anikku.beta` versionCode 820、versionName `0.2.0-harmony.20-8932`，签名 `cf7a2adc…d829` 不变，arm64 90,185,845 B（SHA-256 前缀 `402f5ec45a18`；体积与 preview.19 相同，是对齐填充，分辨看 SHA-256 / versionCode），universal 282,182,455 B，DEX 含 `Panorama scroll trace`、`gapLastMove=`、`fling start v=`；manifest 无 ui-test。`repo` 分支 `releases.json` 20 条，第一条即此版。series 41 张（0001–0041）。正式 run 在 dry_run 结束前就触发了（等待脚本把一次 API 报错当成完成）；同一并发组里排队，等 dry_run 成功后才执行，结果无影响。同轮 Mihon 0033 → `v0.21.2-harmony-preview.7`。Animeko 没有全景瀑布流，这条日志不适用；若是触摸投递卡顿，LazyColumn 也可能受影响，等日志定性后再看。
- 2026-10-14（12:03 UTC）与 mihon-harmony 0034 同一轮：深处往回甩惯性为 0。日志否定了触摸投递猜测。根因见 §5.1 补丁 0042。本仓差异：`PanoramaMasonry.kt` 与 Mihon 逐字节相同；0041 诊断日志保留；`HarmonyLogBuffer` 是 0019；编的是 Preview；旧代码上同一条测试同样失败。
  `:presentation-core:spotlessCheck :presentation-core:testDebugUnitTest :app:testDebugUnitTest :app:compilePreviewKotlin` 通过（presentation-core 55 个用例，0 失败，2 跳过；app 21 个）。干净树 `/tmp/anikku-verify42`（v0.2.0，N=21）套用成功，23 个改动文件与开发树 `cmp` 一致。开发树 `dev-0031` 提交 `334702d`。新测试与 Mihon 同一份：offset 70000，修前起速 `[5120, 5120, 5120, 0, 0, 0, 0]`，修后往回甩 -5120。
  推 `main` `535be14` → `check_patches` run 38558903734 绿 → `dry_run` run 38558928679 绿 → 正式 run 38559880393 → **`v0.2.0-harmony-preview.21`**（12:03 UTC），`app.anikku.beta` versionCode 821、versionName `0.2.0-harmony.21-8933`，签名 `cf7a2adc…d829` 不变，arm64 90,185,845 B（SHA-256 前缀 `b9643f2890ba`；体积与 preview.20 相同，是对齐填充，分辨看 SHA-256 / versionCode），universal 282,182,455 B；manifest 无 ui-test。`repo` 分支 `releases.json` 21 条，第一条即此版。series 42 张（0001–0042）。这次 dry_run 成功后才触发正式 run，等待脚本已修好。同轮 Mihon 0034 → `v0.21.2-harmony-preview.8`。Animeko 不适用（没有自写的 ScrollableState）。
- 2026-10-14（12:53 UTC）用户：「好像mihon的惯性消失问题解决了，但是为啥滑动块又很难按到了」。精确 delta 已确认修好惯性；收回热区后只剩画出来的 12 dp 拇指可按。补丁 0043（与 mihon-harmony 0035 同源）：热区恢复 32 dp + 边距，拇指本体按下即抓，旁边 20 dp 按住 120 ms 不动才抓，快甩照常滚内容。推 `main` `a7767e4ee` → `check_patches` run 38564908070 绿 → `dry_run` run 38564987874 绿 → 正式 run 38566080812 → **`v0.2.0-harmony-preview.22`**（12:53 UTC），`app.anikku.beta` versionCode 822、versionName `0.2.0-harmony.22-8934`，签名 `cf7a2adc…d829` 不变，arm64 90,185,845 B（SHA-256 前缀 `67aabb3d2aa9`）。dry_run 成功后才触发正式 run。
- 2026-10-14 用户：解锁后第一下滑不动，随后说「要不不加这个解锁后第一下不动了，好像又没有问题了」，诊断提交已撤掉，没有发版。
- 2026-10-14（13:37 UTC）用户：想记录上下滑 / 惯性时的帧率或耗时，「有时候又很丝滑」，要一个调试按钮导出脱敏日志，不依赖 IP 或 token。补丁 0044（与 mihon-harmony 0036 同源）：设置 → 高级 →「滚动性能记录（调试）」，左下角「记录」按钮经分享面板导出只含数字的文件；归档仓新增 `tools/scroll-perf-analyze/analyze.py`。推 `main` `4137fa1b9` → `check_patches` run 38570497489 绿 → `dry_run` run 38570550124 绿 → 正式 run 38572074220 → **`v0.2.0-harmony-preview.23`**（13:37 UTC），`app.anikku.beta` versionCode 823、versionName `0.2.0-harmony.23-8935`，签名 `cf7a2adc…d829` 不变，arm64 90,202,229 B（SHA-256 前缀 `5d2ea23ce55a`），DEX 含 `harmony_scroll_perf_recorder`、`privacy: no titles`。开发树 HEAD 复跑 `:presentation-core:testDebugUnitTest :app:testDebugUnitTest` 通过（presentation-core 59 个用例，0 失败，2 跳过；app 27 个）。
- 2026-10-14（13:43 UTC）`repo` 分支索引按 `created_at` 倒序（`7170c6e`，`release_index` run 38574203527）：GitHub 列表接口把 mihon-harmony preview.10 排在 6 个旧版之后，App 按版本号取最大所以不受影响，但只取第一页时新版可能被挤出。三个流水线同一改动。同时更正补丁 0043 正文里的同源编号（原写成 mihon-harmony 0036），只改提交信息，代码不变。

## 2026-10-25：紧凑导航与浏览时收起

- 顶栏普通字号采用 56dp，大字号保留 64dp；底部改用官方 64dp 最小高度的短导航组件，文字需要时可增长，保留系统安全区与至少 48dp 触控尺寸。
- 书架、更新、历史、来源/扩展页和源内容列表的标题用 Material3 `enterAlwaysScrollBehavior`，分类/筛选行仍可操作；搜索、多选、屏幕朗读时不自动收起标题。
- 底栏复用既有显示动画，只观察真实用户纵向滚动：向后累计 24dp 收起，反向 8dp 显示；横向切页、惯性与无法滚动的空/短列表不会触发隐藏，不消费位移或惯性。切换标签、选择模式复位，更多页和侧边导航保持可用。
- Mihon 0046 复用 Anikku 0046 的宽度分列算法，避免收起导航改变视口高度时换列；保留 Mihon 的 minLane 限制、局部重排与缓存。Mihon 0047 / Anikku 0048 的 `NavigationChrome.kt`、`NavigationChromeScrollTracker.kt` 及对应测试逐字节相同。
- 组件差异：Mihon 保留 NavigationSuiteScaffold，手机改用 ShortNavigationBarCompact；Anikku 用 ShortNavigationBar/ShortNavigationBarItem，隐藏未选中标签的旧偏好仍保留，投屏连接期间底栏不自动收起；Anikku 相关推荐页也接入标题收起。
- 机器检查覆盖方向阈值、边界/短列表、复位、不吞滚动/惯性以及列数不随高度变化。双应用签名构建与更新索引见归档仓现状；实际手感、字体与系统安全区由用户安装反馈。Animeko 使用独立 AniTopAppBar/多平台导航，不直接移植本次 Tachiyomi 组件。
- 依据：[华为 Pura X Max 官方比例](https://consumer.huawei.com/cn/phones/pura-x-max/specs/)、[Material3 顶栏行为](https://developer.android.com/reference/kotlin/androidx/compose/material3/TopAppBarDefaults)。不根据手机型号或物理像素写死 dp。

## 2026-10-25：整块导航收起、透明系统区域与快速恢复

- Mihon 0048 / Anikku 0049 跟进用户对 preview.13 / preview.26 的反馈：标题、分类、底栏统一使用 surface，标题滚动后也不变色；移除 MainActivity 手工底部遮罩，Android 10+ 关闭系统导航栏对比遮罩。保留时钟、状态图标和系统手势条。
- 浏览 Scaffold 用共同高度与折叠比例收起标题、顶部系统 inset、分类及源筛选行；完全收起后正文可画到透明状态栏下。底部安全 inset 仍作为列表末项滚动空间，避免最后一项被手势条遮住。普通详情/设置页不启用整块收起；搜索、多选和触摸探索仍复位并禁用自动隐藏。
- 底栏在 onPreScroll 首次反向用户拖动就恢复，不再等顶栏消费后的 8dp；仍不消费滚动或惯性。Mihon 用官方 NavigationSuiteScaffoldState.snapTo(Visible)，Anikku 显示 120ms / 隐藏 180ms，保留投屏和标签偏好。
- NavigationChrome.kt 及新增回滑/布局回归在两仓同源；布局测试只按 Compose 版本选择旧包或 v2 包的 runComposeUiTest，断言相同；布局回归检查完整收起无顶部空条以及展开恢复。版本、构建和真机状态以档案仓现状为准。
- 一手依据：[Android edge-to-edge](https://developer.android.com/develop/ui/views/layout/edge-to-edge)、[Compose Insets](https://developer.android.com/develop/ui/compose/system/insets-ui)、[Material3 顶栏滚动](https://developer.android.com/develop/ui/compose/components/app-bars)。

## 2026-10-25：同步悬浮导航与阔屏紧凑尺寸

- Mihon 0049 / Anikku 0050 跟进 preview.14 / preview.27 真机反馈：标题和分类不再各自压缩，二者在同一 topBar 容器整体平移；上下导航共用显隐状态和 140ms 动画。
- 首个真实用户向上滚动即收起，首个反向拖动即恢复；去掉隐藏24dp等待，监听不消费滚动/惯性，横向切页、惯性和短列表未消费的拖动不触发隐藏。搜索、多选、触摸探索、更多页及 Anikku 投屏的保护仍保留。
- 导航是悬浮层：Home 手机正文不再因底栏加减 padding，顶部整体平移保持测量高度；书架/分页顶部余量放进列表 contentPadding，可随正常滚动离开。收放动画不改视口或列表 padding，不替用户拖动漫画；末项保留实际导航/投屏和系统区域的滚动余量。
- 通用紧凑规则：字号比例≤1.3，窗口宽高比≥0.65或高度≤480dp时，标题48dp、底部48dp触控行；普通窗口保持56/64dp，大字号顶栏64dp并用官方底栏。分类保持48dp触控，不按设备型号写死。Mihon tablet NavigationSuite rail 保留，Anikku 投屏/标签/徽标保留。
- NavigationChrome.kt、NavigationChromeScrollTracker.kt、CompactNavigationBar.kt 及纯逻辑测试两仓一致；布局回归仅按 Compose 版本选择旧包或 v2 runComposeUiTest，按0/0.5/1确定进度验证正文边界/封面坐标不变、标题与分类距离不变、上下移动进度一致，并独立验证真实动画完成隐藏与恢复；不依赖固定80ms取样。版本和构建结果以归档现状为准。

## 2026-10-25：手势内锁定导航、滑块避让与统一留白

- Mihon 0050 / Anikku 0051 跟进 preview.15 / preview.28：轻微来回拖动不再反复收放。父 Scaffold 在 Initial 阶段只观察触摸，不消费事件；一次按住最多改变一次显隐，所有手指松开或取消后允许下一次手势切换；6dp同向位移确认意图，惯性和横向手势不触发。
- 恢复共用225ms缓出动画；隐藏随触摸速度从175ms缩至100ms，上下仍共用同一进度。保留系统动画缩放、无障碍/搜索/选择保护，正文视口和滚动padding不随动画变。
- List/Grid/Masonry快速滑块轨道与宿主内容padding取最大值，避开固定展开头部/底部安全区，去掉底部重复预留。轨道在导航收放时保持不变，短窗口不足放滑块时隐藏；Anikku独有不规则网格同步处理。
- 新的共享 browsingContentVerticalPadding 沿用窗口/字号规则：紧凑4dp、其他8dp，统一书架、浏览、Anikku相关推荐。48dp标题/分类触控与系统安全区保持；未发现重复顶部inset。Mihon相关推荐宿主不同，保留原有结构。
- 参考：Android [每次手势生命周期](https://developer.android.com/develop/ui/compose/touch-input/pointer-input/understand-gestures)、Material [175/225ms隐藏/恢复](https://github.com/material-components/material-components-android/blob/master/lib/java/com/google/android/material/behavior/HideViewOnScrollBehavior.java)、[Headroom方向容差](https://github.com/WickyNilliams/headroom.js/blob/master/src/Headroom.js)。一次手势锁定是依据用户小红书实测反馈设计，没有声称取得小红书源码。
- 共享NavigationChrome与tracker/spacing两仓一致；回归覆盖同手势反向锁定、松手后再切换、小幅容差、真实触摸事件和正文坐标稳定。版本、构建、产物和真机状态见归档现状。

## 2026-10-26：紧凑单行导航、磨砂背景与滑块联动

- Mihon 0051 / Anikku 0052 跟进 preview.16/29：阔/矮窗口把书架分类或浏览分页放进标题行下拉选择，保留左右Pager和搜索/多选入口；普通窗口保持两行。标题触控48dp，底栏在48dp行上方增加16dp徽标空间。
- 首屏顶部留白未滑走时，导航收起进度受实际第0项位移约束，不先飞走露空条；List/Grid使用含padding区域的第0项offset，避免矮行提前失去首项。中部仍悬浮，不改正文视口/滚动padding；保留一次触摸一次显隐与225ms恢复/速度感知收起。
- 快速滑块随可见导航调整轨道，系统区/FAB额外间距分开保留；按下/拖动冻结直到松手。视觉16dp、直接命中28dp，额外侧区仍短按住抓取，不扩大整条边缘热区。首末钉0/1并实际到达；修规则网格过期范围缓存及Anikku不规则网格先返回导致高度无法初始化。
- 两款列表导航复用Haze 1.7.2（Anikku原已使用）：18dp背景模糊、深浅色半透明tint和轻噪点，正文作为source，图标文字保持清晰。非硬件加速/API<31自动用可读半透明底色；磨砂观感和性能待真机。详情MangaToolbar显式Color.Transparent，不加入磨砂、不随滚动或选择状态变色。
- NavigationChrome/BrowsingGlass/BrowsingScrollInsets/BrowsingScrollGeometry/BrowsingTabSelector/CompactNavigationBar两仓同源。回归覆盖首屏短行对齐、正文不被推拉、气泡原始坐标、分类菜单可达及系统/FAB轨道边界。Anikku独有IrregularGrid与源码Scaffold保留差异。版本/构建/签名/索引以归档现状为准。

## 2026-10-26：标题内横滑分类、底栏与刷新层级

- Mihon 0052 / Anikku 0053 跟进preview.17/30真机反馈：用户认可导航动画；阔屏保留书架/浏览标题，中间恢复14sp横滑分类与2dp选中条。分类视口独立裁剪，两端10dp渐隐，标题和右侧按钮不随分类移动；Pager、计数、搜索/选择及普通窗口两行布局保留。
- 紧凑浏览标题行48→40dp，系统WindowInsets保留，详情顶栏尺寸与始终透明规则不改；大字号沿用宽松高度。
- 底栏总内容高度64→56dp：8dp徽标余量+48dp视觉行均可点击；选中背景覆盖图标和文字，左右各4dp。徽标独立布局，10sp/12sp行高、最大99+，完整数量仍用于无障碍，五项窄窗口与1.3字号检查原始四边坐标及图标/标签居中。
- 书架/扩展/Feed默认刷新指示器原来从y=0绘制，被顶栏盖住。共享Scaffold提供窗口坐标下的可见顶栏下缘，PullRefresh据自身位置避让，并裁剪入场动画；保留更大显式padding，详情/更新等调用一起覆盖。首次测量前不画，防止首帧闪到顶栏后；不抬高整个列表或改变正文padding。
- 用户追加滑块消失太快：统一列表/网格/全景/Anikku不规则网格的停留为2.5秒，随后沿用系统淡出时长；按住保持及再次滚动重置计时不变。FastScrollerVisibility.kt两仓逐字节相同。
- 用户继续追加贴边与窄缝：屏幕左右仅1dp，网格实际封面横纵间距从约12dp收至3dp，列表上下各1.5dp；移除格内重复padding并同步全景高度合同，保留系统横向安全区、标题padding/行高与选中描边。书架/浏览/相关推荐及横向搜索封面行保持一致。
- 滑块使用独立列表兄弟节点作为Haze背景，12dp模糊/浅色高光/细轮廓；避免从包含滑块自身的祖先source采样，老系统或软件绘制回退半透明底。
- 共享组件两仓同源；Anikku自定义Scaffold/侧栏/consumed insets、独有徽标偏好/投屏和其他导航样式保留。回归覆盖横滑选择不移标题按钮、五项气泡边界、内移容器刷新避让与详情显式inset，复用原导航手势/正文稳定测试。Animeko为独立AniTopAppBar，不直接移植；版本与签名证据见归档现状。

## 2026-10-26：阅读提示、首次横屏窗口与列表末尾导航

- Mihon 0053：原“单页式”等模式提示在阅读器入场前通过系统Toast独立窗口显示；用户报告进入章节与旋转时全屏闪烁。本版改为现有Compose阅读器窗口内限宽280dp/限高96dp提示，2秒消失，暂停/销毁清除，保留模式提示偏好与手动切换提示，不拦截触摸。代码已避开系统提示窗口，平台闪屏未真机复现；Anikku无此ReaderActivity。
- 两仓0054：用户明确黑边发生在书架/浏览，路径为杀后台→外屏竖屏启动→首次横屏。主窗口在内容挂载前应用edge-to-edge/cutout策略，实际窗口bounds变化后合并请求新Insets，onResume协调、onDestroy移除监听；不再只依赖主题/状态条改变时的一次Compose effect，不移除必要的内容安全区。共享HarmonyWindowInsets.kt字节一致，真机仍需按原路径验证。Anikku旧Compose测试API使用legacy入口，修正候选40220389336编译测试时发现的v2入口不兼容；生产Kotlin当轮已编译。
- 两仓0055：当前活动List/Grid/Masonry绑定末尾真实剩余滚动距离，最后一段bottom spacer把上下悬浮导航共同带回。触底时将背后动画落定为可见并锁定该手势；即使到端点再开新手势继续推、同指回拉也不藏。短列表/未知布局/离屏Pager/reverseLayout分别处理，正文视口和padding不随动画改变。
- 本地13项方向/几何测试通过；UI回归进一步检查真实列表到底与离开、上下对齐及正文不动。完整构建和真机结果以归档现状为准；已有动画获用户认可，未修改中部正常收放时序。

- 0056修正初始化reset与首次布局注册的竞争：reset不再清空活动列表绑定，由observer离屏/销毁负责释放；布局结束同步尾端状态，直接拖滑块跳底也能联显。Mihon40222400100暴露该路径，Anikku同源预防。气泡边界回归保留四边/居中检查，允许在图标上半角正常重叠，替换无设计依据的固定6dp字体估值。
- 后续运行诊断确认计数Text可能换行成高气泡：0056把Home计数限制单行、不换行；回归使用同样的99+单行文字，保留不遮图标中心断言。
- 补充更正：LEGACY软件测试中徽标坐标位于图标右侧，两者X区间不相交，原先仅比较Y误判遮挡；现改为二维相交合同（横向相交才约束不能越过图标中心），四边/居中/高度检查保留。单行计数策略保留。

## 2026-10-26：历史瀑布卡片与更多页固定磨砂

- 0057：用户要求先发布preview.18/31，再改此批。历史用单个FastScrollPanoramaMasonry承载按时间排序的数据，日期FullLine、卡片SingleLane/Measure；正文/封面点详情，继续阅读或播放独立按钮，保留时间、章集、收藏、删除。外边1dp、行列3dp，至少160dp卡宽；Anikku全景复用Tiered规则：网格宽≥600dp时最小卡宽240dp，否则160dp，保留长按多选、筛选、进度、未读点和灰显。
- Anikku按进入页面时的id形状快照排版，优先既有形状缓存，启用全景的未知封面用宽占位；后续加载只学习比例，下次进入采用，避免逐图重排已有卡片。数据层、日期生成和继续下章逻辑保留。
- 两仓共享PinnedBrowsingGlass：更多页内容作为独立Haze source，给Home底栏提供背景，系统状态栏单独磨砂层；导航由页面生命周期pin为可见，离开释放。仅更多页应用，不改变详情顶栏透明规则；保留API/软件半透明回退。
- 验证使用必要格式检查、补丁完整tree复现与现有正式构建/回归；卡片视觉、触控与磨砂帧率由用户安装反馈。Animeko结构独立且用户指定两款，不直接移植。

## 2026-10-26：手动检查更新强制刷新

- 用户明确Mihon手动检查仍找不到新版，当前r8227(0b7915655)经旧APK确认是preview.18，而服务端已发布preview.19（r8228/ef65a8f3c）。版本元组比较正常；定位到forceCheck虽到达domain，ReleaseServiceImpl却未向HTTP传递，仍用默认max-age=10min和磁盘缓存。真实手机缓存响应不可见，不能把症状归因当作真机复现。
- 0058新增两仓字节一致ReleaseCheckRequest：自动检查原GET不变；手动请求FORCE_NETWORK/no-cache，并追加_harmony_check时间戳改变缓存key，保留已有查询参数。mirror、API回退及Anikku单条latest入口均传forceCheck；保持原超时/取消/失败提示，不通过清除全应用缓存来解决。
- 真实OkHttp磁盘缓存回归：fresh旧响应下自动命中缓存，手动走网络获得新JSON；验证请求no-cache/时间戳及per_page保留。用真实helper加最小GET适配在临时JVM工程跑2项通过（20秒），正式CI再编译。旧已安装包仍可能需等旧缓存过期或覆盖升级一次；安装本修复后才改变后续手动检查。
- Animeko使用独立Ktor HarmonyForkUpdates，也读取raw镜像，但无该forceCheck丢失路径；其CDN/客户端时效需单独证据后适配，本轮不直接移植。版本/签名/更新索引以归档现状为准。
