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
scripts/prepare-source.sh                  套补丁 + 改版本号 (CI 与本地通用)
scripts/write-release-index.sh             把 Releases 接口返回写到 repo 分支 (releases.json / latest.json)
.github/workflows/harmony_preview.yml      编译、重签、发布, 然后写 Release 索引
.github/workflows/release_index.yml        Release 被手动增删改时重写索引 (也可手动触发)
.github/workflows/check_patches.yml        只验证补丁能否套到最新稳定版 / master
docs/MAINTENANCE.md                        本文件
```

仓库里**没有** Anikku 源码；需要对照源码时在本地 clone 官方仓库。

孤儿分支 **`repo`** 只放 `write-release-index.sh` 生成的 `releases.json` / `latest.json` / `README.md`（`GET /repos/<repo>/releases?per_page=30` 的原样返回），
应用内更新器（0014 起）优先从 `https://raw.githubusercontent.com/Xun2202/anikku-harmony/repo/releases.json` 读它，不要手改、不要往里放别的东西。

## 4. 构建流程（`harmony_preview.yml` 做了什么）

1. 解析版本：`upstream_tag` 留空则 `gh api repos/komikku-app/anikku/releases/latest`；拼出 `harmony_version`、`release_tag`。
2. 若同名 Release 已存在且不是 `dry_run`，直接结束（定时任务每天跑，靠这一步幂等）。
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
9. `scripts/write-release-index.sh`：`gh api repos/<repo>/releases?per_page=30` 原样存成 `releases.json`，`jq` 取出最新正式版存成 `latest.json`，
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
| 书架「全景松散网格」每行「自动」时横版封面偏窄、挤；竖版和横版同一行时横版下面一大块空白 | preview.10 及之前：自动列宽沿用 128 dp、`LazyVerticalGrid` 整行按最高格子算。preview.11 起全景模式改瀑布流 `LazyVerticalStaggeredGrid` + 自动列宽 168 dp（补丁 0020）。手动设了每行数量的只有排布变化、宽度不变；浏览页 / 相关作品页的全景网格 preview.12 起由 0021 同样处理 |

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
