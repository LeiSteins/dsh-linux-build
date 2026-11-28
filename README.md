# DSH Linux 社区构建

DeepSeek Harness 的 Linux amd64 和 arm64 桌面安装包，由社区维护。

## 下载与安装

打开发布页，在 **Assets** 中按文件名里的 `amd64` 或 `arm64` 选择安装包。旧版文件里的 `x86_64` 对应 `amd64`，`aarch64` 对应 `arm64`。本项目统一发布正式 Release，版本号里的 `alpha`、`beta`、`rc` 仍表示上游的预发布阶段。 [GitHub Releases](https://github.com/LeiSteins/dsh-linux-build/releases)

Release 标签和安装包文件名在完整上游版本号后加 `-n`。例如，上游 `dsh-v0.2.3-alpha.2` 的第 2 次 Linux 发布使用标签 `dsh-v0.2.3-alpha.2-2`。同一上游版本的 Linux 更新递增 `n`，Arch 包的 `pkgrel` 也使用这个修订号。

| 环境 | 文件 | 安装或运行 |
| --- | --- | --- |
| Debian、Ubuntu | `.deb` | `sudo apt install ./文件名.deb` |
| Fedora | `.rpm` | `sudo dnf install ./文件名.rpm` |
| Arch Linux | `.pkg.tar.zst` | `sudo pacman -U ./文件名.pkg.tar.zst` |
| 便携运行 | `.AppImage` | `chmod +x 文件名.AppImage` 后运行 `./文件名.AppImage` |

在应用菜单选择 **检查更新…**，下载新版后按上表安装。从旧命名的安装包迁移时，请直接在发布页下载，版本号相同也需重新安装。需要镜像时，退出应用，然后用 `DSH_LINUX_UPDATE_MIRROR=https://gh-proxy.org/ dsh-linux` 启动。便携版将命令中的 `dsh-linux` 换成 AppImage 路径。

## 自行构建

在 Linux amd64 或 arm64 环境准备构建依赖和对应版本的 Node.js、pnpm，然后将下方 `tag` 换成要构建的上游版本标签。脚本按宿主架构原生构建。 [构建环境](.github/workflows/build-linux.yml) · [上游版本](https://github.com/deepseek-ai/deepseek-harness/releases)

```sh
git clone https://github.com/LeiSteins/dsh-linux-build.git
cd dsh-linux-build

tag=dsh-v0.2.3-alpha.2
git clone --depth 1 --branch "$tag" https://github.com/deepseek-ai/deepseek-harness.git upstream
./scripts/build-linux.sh upstream "$tag" dist 2
```

构建完成后，在 `dist/` 中选择安装包，按上表安装。省略最后一个参数时，修订号默认为 `1`。

## 发布

在 GitHub Actions 手动运行 **Build and publish DSH Linux** 时，通过 `release_revision` 指定同一上游版本的下一修订号。留空时，工作流沿用最高修订号。如果该修订含有旧命名的安装包，工作流会为新命名递增修订号。首次发布从 `1` 开始，已有无后缀 Release 的版本从 `2` 开始，因为旧 RPM 和 Arch 包已使用修订号 `1`。
