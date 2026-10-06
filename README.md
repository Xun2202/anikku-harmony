> [!IMPORTANT]
> ## Anikku Harmony Preview（非官方 HarmonyOS / 卓易通 兼容构建）
>
> 本仓库**不是** [Anikku](https://github.com/komikku-app/anikku) 的源码 fork，而是一组补丁加一条自动发布流水线：
> 每天检查 Anikku 官方最新稳定版，拉取官方源码、套用 [`patches/`](./patches) 下的补丁、编译 **preview** 构建类型的 APK，
> 用本仓库自己的密钥签名后发布到本仓库的 [Releases](../../releases)。tag 形如 `v0.2.0-harmony-preview.1`。
>
> 目标：让 Anikku 在 HarmonyOS 卓易通（Android 兼容容器）里**能正常下载视频**，下载的视频**不被鸿蒙图库收录**，
> 并顺手修掉几个在鸿蒙上更明显的使用痛点（比如同一个视频在多个收藏夹里的下载状态不互通）。
> 本项目不隶属于、也不受 Anikku / Aniyomi 官方支持；与本构建相关的问题请提到本仓库，不要向上游反馈。
> 本构建沿用上游的 [Apache-2.0](https://github.com/komikku-app/anikku/blob/master/LICENSE) 许可，原始项目与绝大部分代码归功于 [Anikku 及其贡献者](https://github.com/komikku-app/anikku/graphs/contributors)。
> 本仓库不提供、不托管任何视频或内容源。

## 修了什么

官方 Anikku Preview 在卓易通里下载任何一集都会反复失败并提示 `Error in ffmpeg!`。日志里的根因是：

```
E ffmpeg-kit: Failed to open SAF id: 8 ... IllegalArgumentException: Failed to determine if
  primary:Documents/Anikku/downloads/<源>/<标题>/Video_tmp/Video.tmp is child of primary:Documents/Anikku:
  java.io.FileNotFoundException: Missing file for ... Video.tmp
```

Anikku 先在用户选择的 SAF 目录里创建 `Video.tmp`，再把这个 `content://` URI 交给 ffmpeg-kit 的 `saf:` 协议去打开；
卓易通的文件提供方在打开时找不到刚建好的文档，ffmpeg 直接失败。上游 Aniyomi 也有同样的报告（[aniyomiorg/aniyomi#2126](https://github.com/aniyomiorg/aniyomi/issues/2126)，Motorola 设备），至今未修。
此外卓易通不支持 SAF `renameDocument`，就算下载成功，`<集>_tmp` 目录也改不了名。

本构建的做法：ffmpeg 改写到 App 私有缓存里的普通文件，写完后再复制进下载目录；目录/文件改名失败时自动改为「复制后删除」。
另外提供「使用应用私有目录」一键选项，完全绕开 SAF。

**鸿蒙图库会收录下载的视频。** 卓易通把应用选的 SAF 文件夹映射到鸿蒙文件管理的「我的手机 → 兼容应用数据 → …」下，
鸿蒙的媒体扫描会把整棵树扫一遍，并且**不认 `.nomedia`**（华为官方文档也只说图库按文件类型收录）。它判断“是不是视频”只看扩展名，
所以本构建从 preview.2 起把下载完成的视频存成 `<集>.mkv.anikku`：对系统来说是“未知类型文件”，图库不收；Anikku 自己是通过文件描述符交给 mpv 播放的，
不看扩展名，播放完全不受影响。想在别的播放器里打开，把末尾的 `.anikku` 去掉即可。

## 下载与安装

- 到 [Releases](../../releases) 下载最新的 `Anikku-<tag>-arm64-v8a.apk`（华为设备均为 arm64）。
- 包名为 `app.anikku.beta`，与官方 Anikku Preview **相同但签名不同**：第一次安装前必须先卸载官方 Preview。
  卸载前先在 设置 → 数据与存储 → **创建备份** 导出备份文件，装好本构建后再 **恢复备份**；已下载的视频留在原来的文件夹里不会丢，重新选择同一个存储位置就会被重新识别。
- harmony-preview 版本之间可直接覆盖安装；应用内「检查更新」已改为检查本仓库的 Release，不会再提示安装官方 APK。
  preview.3 起点「下载」后页面会留在原地显示进度，下载完按钮变成「安装」，点它交给系统安装器（和 Mihon 一样）；
  之前那种点完就退回、只靠通知栏和静默安装的流程在卓易通里什么都看不到。
- 后台下载：卓易通会在 App 切到后台几秒后冻结进程，下载队列和番剧库更新都会停住。preview.3 起默认开启 设置 → 下载 →「**后台保持运行（鸿蒙）**」：
  下载 / 更新期间播放一段静音音轨并持有唤醒锁，卓易通就不会冻结进程；不影响其他 App 的声音，不需要时可关闭。
  关闭后回到官方行为，另受 Android 15 的限制：数据同步类前台服务后台累计 6 小时会被系统强制停止（表现为闪退），隔几小时切回前台可重置额度。
- **存储位置**：继续用 `Documents/Anikku` 这类自选文件夹即可（和 Mihon 一样，换机、重装都方便）。
  设置 → 下载 → 「**下载的视频对系统图库隐藏**」默认开启，新下载会存成 `<集>.mkv.anikku`，鸿蒙图库不再收录。
  升级前已经下载的 `.mkv` 还是旧名字，点一下同一页的「**按上述设置重命名已下载的视频**」统一补上后缀（下载进行中时不能点，先暂停）。
- 不想在文件管理里看到任何下载内容的话，也可以选 设置 → 数据与存储 → 「使用应用私有目录（鸿蒙推荐）」：下载保存到 `Android/data/app.anikku.beta/files/Anikku/`，
  不经过 SAF；代价是卸载应用时会一并删除，自动备份也在里面，卸载前记得导出。
- **同一视频收藏进多个文件夹**（XvXun 这类把收藏夹当“剧集”的源）：设置 → 下载 → 「**不同条目间共用已下载的视频**」默认开启，
  一个视频只要在同一来源的任一条目下载过，其他条目里也显示为已下载并直接播放那份文件；「下载未看/下载后 N 集」也会跳过它们。
  删除时请到真正下载它的那个条目里删——在别的条目里点删除不会有效果（文件不属于它）。
- APK 被交给「出境易」而提示「暂不支持安装该应用」时，把 APK 复制到本机存储后用系统「文件管理」打开即可由卓易通安装（详细步骤见 [animeko-harmony 的说明](https://github.com/Xun2202/animeko-harmony#安装步骤鸿蒙-next--6--7)，两者相同）。

## 包含的补丁

| 补丁 | 作用 |
| --- | --- |
| [`0001-downloads-rename-fallback-for-saf-without-renamedocument.patch`](./patches/0001-downloads-rename-fallback-for-saf-without-renamedocument.patch) | 新增 `UniFile.renameToOrCopy()`：改名失败时回退为「复制到目标后删除源」；每集下载完成后把 `<集>_tmp` 目录改名为正式目录时使用它，并把 `.nomedia` 建在改名后的目录里。移植自 [mihon-harmony](https://github.com/Xun2202/mihon-harmony) 补丁 0001。 |
| [`0002-downloads-mux-video-in-private-cache.patch`](./patches/0002-downloads-mux-video-in-private-cache.patch) | **核心修复。** ffmpeg 不再通过 ffmpeg-kit 的 `saf:` 协议写 SAF 文档，而是写到 `cacheDir/harmony_download_tmp/<animeId>/<集>.mkv`；完成后复制进下载目录的 `<集>.tmp`，再 `renameToOrCopy` 成 `<集>.mkv`。复制失败重试时不重新下载；缓存文件无论成功失败都会删除；外部下载器（1DM/ADM）流程不变。 |
| [`0003-updater-use-harmony-fork-releases.patch`](./patches/0003-updater-use-harmony-fork-releases.patch) | 应用内更新改查本仓库的 GitHub Releases，版本按 `(x, y, z, N)` 四元组比较；harmony 构建不会接受非 harmony 的 tag。否则官方逻辑会因解析不了 `0.2.0-harmony.1` 而抛 `NumberFormatException`，或推送签名不同、装不上的官方 APK。 |
| [`0004-storage-app-private-location-option.patch`](./patches/0004-storage-app-private-location-option.patch) | 设置页与新手引导增加「使用应用私有目录」。复用上游给 Fire TV 准备的回退逻辑（`Android/data/<包名>/files/<应用名>`），是普通文件路径，`UniFile` 直接走 `java.io.File`，ffmpeg 与改名都不再碰 SAF。字符串加在 `i18n-ank`（英文 + 简体中文）。 |

| [`0005-build-flexible-adapter-from-maven-central.patch`](./patches/0005-build-flexible-adapter-from-maven-central.patch) | **临时回迁**，不改功能。v0.2.0 仍从 JitPack 取 `com.github.arkon.FlexibleAdapter:flexible-adapter:c8013533`，而 JitPack 已不再提供该产物，冷缓存编译必失败；上游 master 已改为 Maven Central 的 `eu.davidea:flexible-adapter:5.1.0`（[c44eb6f](https://github.com/komikku-app/anikku/commit/c44eb6f2d5)），这里原样回迁。下个官方稳定版包含该提交后脚本会自动跳过它。 |
| [`0006-downloads-hide-videos-from-gallery-with-unknown-extension.patch`](./patches/0006-downloads-hide-videos-from-gallery-with-unknown-extension.patch) | 下载完成的视频存成 `<集>.mkv.anikku`（MIME 变成 `application/octet-stream`），让只看扩展名、不认 `.nomedia` 的鸿蒙媒体扫描不再把它当视频。`DownloadManager.buildVideo` 同时接受带后缀和不带后缀的文件；下载缓存按目录名索引，不受影响。设置 → 下载 新增开关「下载的视频对系统图库隐藏」（默认开）和动作「按上述设置重命名已下载的视频」（给存量文件加/去后缀，不能改名的存储自动走复制）。 |
| [`0007-downloads-share-downloads-across-entries-by-url.patch`](./patches/0007-downloads-share-downloads-across-entries-by-url.patch) | 同一来源里按剧集 `url` 共用下载：`episodes.sq` 新增 `getEpisodesByUrls`（每 500 条一批，避开 SQLite 变量上限），`DownloadManager.findSharedDownloads()` 为未下载的集找出其他条目下已下载的同 url 文件，条目页把它们显示为已下载，播放器与「自动下载后几集」用同一份判断直接播放那份文件。设置 → 下载 新增开关「不同条目间共用已下载的视频」（默认开）。本地源与合并条目不参与。 |
| [`0008-updater-in-screen-download-progress-and-install.patch`](./patches/0008-updater-in-screen-download-progress-and-install.patch) | 应用内更新改成 Mihon 的流程：新版本页面不再点「下载」就退出，而是用 Voyager `StateScreenModel` 订阅 `AppUpdateDownloadJob` 的 WorkInfo，按钮依次显示「下载」→「正在下载… (xx%)」→「安装」（`ACTION_VIEW` 交给系统安装器，卓易通里可用）→ 失败时「重试」；下载中退出页面会取消下载。`AppUpdateDownloadJob` 通过 `setProgress` / 输出数据上报进度和 URL，新增 `interactive` 输入：从页面发起的下载跳过 API 31 的静默 `PackageInstaller` 会话和「点击安装」通知（卓易通都不显示）；通知栏 / 定时自动更新发起的下载保持原行为。 |
| [`0009-downloads-background-keep-alive-silent-audio.patch`](./patches/0009-downloads-background-keep-alive-silent-audio.patch) | 与 mihon-harmony 补丁 0005 相同。卓易通在 App 退到后台几秒后冻结进程，dataSync 前台服务、唤醒锁、电池优化白名单都拦不住，只有音频输出能让容器继续跑（Animeko 上验证）。新增 `BackgroundKeepAlive`：下载队列 / 番剧库更新运行期间循环播放静音 PCM（`AudioTrack` MODE_STATIC，不占 CPU、不抢音频焦点）并持有部分唤醒锁；下载服务改为声明 `mediaPlayback` 类型（无 Android 15 的 6 小时限制）。设置 → 下载 →「后台保持运行（鸿蒙）」可关闭。 |

补丁按 [`patches/series`](./patches/series) 的顺序套用；已被官方合入的补丁会被 `prepare-source.sh` 自动跳过。

## 版本号规则

- `versionName` = `<官方版本>-harmony.<N>`，例如 `0.2.0-harmony.1`；preview 构建类型会再自动追加 `-<上游提交数>` 后缀，这是 Anikku 自己的行为。
- `versionCode` = `<官方 versionCode> × 100 + N`（如 `8 × 100 + 1 = 801`），保证新官方版本的任意 harmony 构建都高于旧版本的，覆盖安装不会被拒。
- Release tag = `<官方 tag>-harmony-preview.<N>`。`N` 是同一官方版本的第几次打包，改了补丁需要重发时递增。**不要改这个格式**，更新器靠它识别版本。
- Release 必须是正式 Release（非 prerelease）：Anikku 的更新器会过滤掉 prerelease。

## 构建机制

流水线定义在 [`.github/workflows/harmony_preview.yml`](./.github/workflows/harmony_preview.yml)，每天 UTC 04:23（北京 12:23）定时运行，也可以在 Actions 里手动触发并指定 `upstream_tag` / `patch_number`，或勾选 `dry_run` 只编译不发布：

1. 取官方最新稳定版 tag（或手动指定），若对应 Release 已存在则直接结束。
2. `git clone --branch <tag> --single-branch` 官方源码（保留完整历史，preview 构建用提交数做版本后缀）。
3. [`scripts/prepare-source.sh`](./scripts/prepare-source.sh)：按 `series` 顺序 `git apply --3way` 补丁、改写 `versionCode` / `versionName`，每一步各提交一次。
4. JDK 17（与官方 `build_preview.yml` 一致），`./gradlew assemblePreview -Penable-updater`（不带 `-Pinclude-telemetry`，因此不需要官方的 `google-services.json`）。preview 构建类型用 debug 密钥出包。
5. 用 `zipalign` + `apksigner` 以仓库 Secrets 里的密钥重签 `arm64-v8a` 与 `universal` 两个 APK，命名为 `Anikku-<tag>-arm64-v8a.apk` / `Anikku-<tag>.apk`，上传为 Actions artifact 并 `gh release create`，Release 说明里附 SHA-256。

[`.github/workflows/check_patches.yml`](./.github/workflows/check_patches.yml) 在补丁改动时和每周一，把补丁分别试套到官方最新稳定版和 `master`，上游一变就能提前知道要 rebase。

## Secrets

| 名称 | 内容 |
| --- | --- |
| `SIGNING_KEY` | 签名密钥库（`.jks`）的 Base64 |
| `KEY_STORE_PASSWORD` | 密钥库密码 |
| `ALIAS` | 密钥别名（`xun2202-anikku-harmony`） |
| `KEY_PASSWORD` | 密钥密码 |

签名证书 SHA-256：`cf7a2adca95a7208cada9fba3b95d6aabffc57f2b7d1cc2ac80881af022bd829`（可用 `apksigner verify --print-certs` 核对）。

**丢失密钥 = 已安装用户无法覆盖升级**，只能卸载重装。密钥备份位置与维护流程见 [`docs/MAINTENANCE.md`](./docs/MAINTENANCE.md)。
