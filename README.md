# DSH Linux 社区构建

本项目从 [DeepSeek Harness 上游源码](https://github.com/deepseek-ai/deepseek-harness) 构建 Linux x86_64 桌面安装包，由社区独立维护。安装包自带应用所需的 Node.js、pnpm 和 Python 运行时。桌面应用名为 **Deepseek Harness**，使用上游 Windows 桌面图标。

## 下载与安装

在 [GitHub Releases](https://github.com/LeiSteins/dsh-linux-build/releases) 选择版本，展开 **Assets** 下载对应文件。上游预发布版本会保留 **Pre-release** 标记。应用内版本和安装包文件名沿用上游版本。DEB 和 RPM 的包管理器元数据使用 `~` 表示预发布，例如 `0.2.3~alpha.2`，保证预发布版本排在正式版之前。

| 环境 | 文件 | 安装或运行 |
| --- | --- | --- |
| Debian、Ubuntu | `dsh-linux-<版本>-amd64.deb` | `sudo apt install ./文件名.deb` |
| Fedora | `dsh-linux-<版本>-x86_64.rpm` | `sudo dnf install ./文件名.rpm` |
| 便携运行 | `dsh-linux-<版本>-x86_64.AppImage` | `chmod +x 文件名.AppImage` 后运行 `./文件名.AppImage` |

AppImage 无法使用 FUSE 时，可以运行 `./文件名.AppImage --appimage-extract-and-run`。安装包未签名，下载后可在同一目录运行 `sha256sum -c SHA256SUMS --ignore-missing`，并确认所下载的安装包显示 `OK`。下载新版本即可手动更新。`BUILD-INFO.txt` 记录上游源码提交、打包提交和工作流地址。

## 自动构建与发布

[构建工作流](https://github.com/LeiSteins/dsh-linux-build/actions/workflows/build-linux.yml) 每天北京时间 00:00 检查上游最新的非草稿 Release。对应版本已有三种安装包以及 `SHA256SUMS` 和 `BUILD-INFO.txt` 时，定时任务跳过构建。手动运行可指定 `upstream_tag`，也可以取消 `publish`，只保留 Actions 产物。手动重建同一个已发布的版本会把新文件保留在 Actions，供维护者验证。工作流产物保留 30 天。

构建按上游标签对应的提交检出源码，使用其锁定的 Node.js、pnpm 和依赖。Linux 补丁让桌面 Host 和 CLI 使用应用自带的 Node.js，以避免 Electron 的 Node 模式与 `sharp` 在 Linux 下发生 GLib 冲突。工作流验证打包后的 Host、图片解码、PTY、离线插件安装与 Office 转换，再从同一份桌面构建生成三个格式。发布作业核对 GitHub 收到的文件大小和 SHA-256，校验齐全后公开 Release。

如果新上游版本无法应用补丁，请根据失败日志更新 `patches/linux-x64.patch`，先手动运行一次构建验证，再发布对应版本。裸机 Wayland、中文输入法和账号登录属于发布后的桌面兼容性测试，当前 CI 覆盖运行时和包结构。

## 本地构建

使用 Linux x86_64，安装工作流所列的系统依赖，并按上游 `scripts/primary-runtime/lock.json` 与 `package.json` 选择 Node.js 和 pnpm。构建命令会对干净的临时检出应用补丁。

```sh
tag=dsh-v0.2.3-alpha.2
git clone --depth 1 --branch "$tag" https://github.com/deepseek-ai/deepseek-harness.git upstream
scripts/build-linux.sh upstream "$tag" dist
```

`dist/` 下保留三个安装包、校验文件和构建记录。
