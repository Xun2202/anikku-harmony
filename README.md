> [!IMPORTANT]
> ## Anikku Harmony Preview（非官方 HarmonyOS / 卓易通 兼容构建）
>
> 本仓库**不是** [Anikku](https://github.com/komikku-app/anikku) 的源码 fork，而是一组补丁加一条自动发布流水线：
> 每天检查 Anikku 官方最新稳定版，拉取官方源码、套用 [`patches/`](./patches) 下的补丁、编译 **preview** 构建类型的 APK，
> 用本仓库自己的密钥签名后发布到本仓库的 [Releases](../../releases)。tag 形如 `v0.2.0-harmony-preview.1`。
>
> 目标只有一个：让 Anikku 在 HarmonyOS 卓易通（Android 兼容容器）里**能正常下载视频**。
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
另外提供「使用应用私有目录」一键选项，完全绕开 SAF，鸿蒙图库也看不到下载的视频。

## 下载与安装

- 到 [Releases](../../releases) 下载最新的 `Anikku-<tag>-arm64-v8a.apk`（华为设备均为 arm64）。
- 包名为 `app.anikku.beta`，与官方 Anikku Preview **相同但签名不同**：第一次安装前必须先卸载官方 Preview。
  卸载前先在 设置 → 数据与存储 → **创建备份** 导出备份文件，装好本构建后再 **恢复备份**；已下载的视频留在原来的文件夹里不会丢，重新选择同一个存储位置就会被重新识别。
- harmony-preview 版本之间可直接覆盖安装；应用内「检查更新」已改为检查本仓库的 Release，不会再提示安装官方 APK。
- **鸿蒙建议**：设置 → 数据与存储 → 「**使用应用私有目录（鸿蒙推荐）**」（新手引导的存储页也有同样的按钮）。
  下载会保存到 `Android/data/app.anikku.beta/files/Anikku/`：不经过 SAF、鸿蒙图库不会索引；代价是卸载应用时会一并删除，自动备份也在里面，卸载前记得导出。
- 继续用 `Documents/Anikku` 这类自选文件夹也可以，下载同样能成功；但鸿蒙图库是否会把其中的 `.mkv` 当作视频收录，取决于系统是否尊重 `.nomedia`，不保证。
- APK 被交给「出境易」而提示「暂不支持安装该应用」时，把 APK 复制到本机存储后用系统「文件管理」打开即可由卓易通安装（详细步骤见 [animeko-harmony 的说明](https://github.com/Xun2202/animeko-harmony#安装步骤鸿蒙-next--6--7)，两者相同）。

## 包含的补丁

| 补丁 | 作用 |
| --- | --- |
| [`0001-downloads-rename-fallback-for-saf-without-renamedocument.patch`](./patches/0001-downloads-rename-fallback-for-saf-without-renamedocument.patch) | 新增 `UniFile.renameToOrCopy()`：改名失败时回退为「复制到目标后删除源」；每集下载完成后把 `<集>_tmp` 目录改名为正式目录时使用它，并把 `.nomedia` 建在改名后的目录里。移植自 [mihon-harmony](https://github.com/Xun2202/mihon-harmony) 补丁 0001。 |
| [`0002-downloads-mux-video-in-private-cache.patch`](./patches/0002-downloads-mux-video-in-private-cache.patch) | **核心修复。** ffmpeg 不再通过 ffmpeg-kit 的 `saf:` 协议写 SAF 文档，而是写到 `cacheDir/harmony_download_tmp/<animeId>/<集>.mkv`；完成后复制进下载目录的 `<集>.tmp`，再 `renameToOrCopy` 成 `<集>.mkv`。复制失败重试时不重新下载；缓存文件无论成功失败都会删除；外部下载器（1DM/ADM）流程不变。 |
| [`0003-updater-use-harmony-fork-releases.patch`](./patches/0003-updater-use-harmony-fork-releases.patch) | 应用内更新改查本仓库的 GitHub Releases，版本按 `(x, y, z, N)` 四元组比较；harmony 构建不会接受非 harmony 的 tag。否则官方逻辑会因解析不了 `0.2.0-harmony.1` 而抛 `NumberFormatException`，或推送签名不同、装不上的官方 APK。 |
| [`0004-storage-app-private-location-option.patch`](./patches/0004-storage-app-private-location-option.patch) | 设置页与新手引导增加「使用应用私有目录」。复用上游给 Fire TV 准备的回退逻辑（`Android/data/<包名>/files/<应用名>`），是普通文件路径，`UniFile` 直接走 `java.io.File`，ffmpeg 与改名都不再碰 SAF。字符串加在 `i18n-ank`（英文 + 简体中文）。 |

| [`0005-build-flexible-adapter-from-maven-central.patch`](./patches/0005-build-flexible-adapter-from-maven-central.patch) | **临时回迁**，不改功能。v0.2.0 仍从 JitPack 取 `com.github.arkon.FlexibleAdapter:flexible-adapter:c8013533`，而 JitPack 已不再提供该产物，冷缓存编译必失败；上游 master 已改为 Maven Central 的 `eu.davidea:flexible-adapter:5.1.0`（[c44eb6f](https://github.com/komikku-app/anikku/commit/c44eb6f2d5)），这里原样回迁。下个官方稳定版包含该提交后脚本会自动跳过它。 |

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
