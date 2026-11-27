# DSH Linux 社区构建

本项目从 [DeepSeek Harness 上游源码](https://github.com/deepseek-ai/deepseek-harness) 构建 Linux x86_64 桌面安装包，由社区独立维护。安装包自带应用所需的 Node.js、pnpm 和 Python 运行时。桌面应用名为 **Deepseek Harness**，使用上游 Windows 桌面图标。

## 下载与安装

在 [GitHub Releases](https://github.com/LeiSteins/dsh-linux-build/releases) 选择版本，展开 **Assets** 下载对应文件。上游预发布版本会保留 **Pre-release** 标记。应用内版本和安装包文件名沿用上游版本。DEB 和 RPM 的包管理器元数据使用 `~` 表示预发布，例如 `0.2.3~alpha.2`，保证预发布版本排在正式版之前。

| 环境 | 文件 | 安装或运行 |
| --- | --- | --- |
| Debian、Ubuntu | `dsh-linux-<版本>-amd64.deb` | `sudo apt install ./文件名.deb` |
| Fedora | `dsh-linux-<版本>-x86_64.rpm` | `sudo dnf install ./文件名.rpm` |
| Arch Linux | `dsh-linux-<版本>-x86_64.pkg.tar.zst` | `sudo pacman -U ./文件名.pkg.tar.zst` |
| 便携运行 | `dsh-linux-<版本>-x86_64.AppImage` | `chmod +x 文件名.AppImage` 后运行 `./文件名.AppImage` |

Arch 包的 pacman 版本把预发布标记写成 `0.2.3pre.alpha.2-1`，使同系列正式版排在预发布版之后。

AppImage 无法使用 FUSE 时，可以运行 `./文件名.AppImage --appimage-extract-and-run`。安装包未签名，下载后可在同一目录运行 `sha256sum -c SHA256SUMS --ignore-missing`，并确认所下载的安装包显示 `OK`。发布说明链接到上游源码提交、打包提交和构建日志。

在应用菜单选择 **检查更新…**，可查看社区已发布的更高版本，包括 alpha 和 RC。安装包沿用桌面端的 `resources/app-update.yml`，更新源指向发布该安装包的 GitHub 仓库。发现新版时，应用会显示与当前安装格式匹配的文件名。点击 **下载更新** 后，浏览器直接打开安装包链接。下载后按上表手动升级。同版本重打包可从发布页手动下载。

默认直连 GitHub。国内网络可以退出应用后，用 `DSH_LINUX_UPDATE_MIRROR` 指定自选的 HTTPS 镜像前缀，再启动应用。例如，已安装的 DEB、RPM 或 Arch 包可运行以下命令。

```sh
DSH_LINUX_UPDATE_MIRROR=https://gh-proxy.org/ dsh-linux
```

便携版可用相同的环境变量启动 AppImage。镜像需要支持代理 GitHub Release API 和单个附件的下载链接。检查请求失败或镜像附件不可用时，应用会回退到 GitHub。若浏览器中的镜像下载中断，可在更新提示中选择 **GitHub**。用镜像下载时，建议从 GitHub 发布页独立取得 `SHA256SUMS` 后再校验安装包。

## 自动构建与发布

[构建工作流](https://github.com/LeiSteins/dsh-linux-build/actions/workflows/build-linux.yml) 每天北京时间 00:00 检查上游最新的非草稿 Release。对应版本安装包和 `SHA256SUMS` 齐全时，定时任务跳过构建。新增 Arch 支持前已发布的完整版本也会跳过。手动运行可指定 `upstream_tag`，也可以取消 `publish`，只保留 Actions 产物。勾选 `rebuild` 可强制重新构建，已发布版本的新文件保留在 Actions 供维护者验证。勾选 `overwrite` 会重新构建并替换该版本的安装包和校验文件，同时触发发布。补传缺失文件前，发布作业会核对已有文件与本次构建是否一致。工作流产物保留 30 天。

构建按上游标签对应的提交检出源码，使用其锁定的 Node.js、pnpm 和依赖。Linux 安装包至少使用 Electron 45.5.0，让支持传递激活令牌的 Wayland 托盘可以恢复最小化的窗口。Linux 补丁让桌面 Host 和 CLI 使用应用自带的 Node.js，以避免 Electron 的 Node 模式与 `sharp` 在 Linux 下发生 GLib 冲突。工作流先执行构建配置、运行时准备、标题栏和托盘等定向测试，再验证打包后的 Host、图片解码、PTY、离线插件安装与 Office 转换，最后从同一份桌面构建生成四种格式。发布作业核对 GitHub 收到的文件大小和 SHA-256，校验齐全后公开 Release。

构建按编号应用 [运行时、托盘、标题栏、品牌、更新检查和欢迎窗口补丁](patches/)。整个补丁序列通过检查后才写入上游检出目录。如果新上游版本出现冲突，请根据日志中的补丁文件名更新相应改动，手动构建验证后再发布。裸机 Wayland、中文输入法和账号登录需要桌面环境实测。

## 本地构建

使用 Linux x86_64，安装工作流所列的系统依赖，并按上游 `scripts/primary-runtime/lock.json` 与 `package.json` 选择 Node.js 和 pnpm。构建命令会对干净的临时检出应用补丁。

```sh
tag=dsh-v0.2.3-alpha.2
git clone --depth 1 --branch "$tag" https://github.com/deepseek-ai/deepseek-harness.git upstream
scripts/build-linux.sh upstream "$tag" dist
```

`dist/` 下保留四个安装包和 `SHA256SUMS`。
