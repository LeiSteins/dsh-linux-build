# DSH Linux 社区构建

DeepSeek Harness 的 Linux x86_64 桌面安装包，由社区维护。

## 下载与安装

打开发布页，选择所需版本，在 **Assets** 中下载对应的安装包。测试版标有 **Pre-release**。 [GitHub Releases](https://github.com/LeiSteins/dsh-linux-build/releases)

| 环境 | 文件 | 安装或运行 |
| --- | --- | --- |
| Debian、Ubuntu | `.deb` | `sudo apt install ./文件名.deb` |
| Fedora | `.rpm` | `sudo dnf install ./文件名.rpm` |
| Arch Linux | `.pkg.tar.zst` | `sudo pacman -U ./文件名.pkg.tar.zst` |
| 便携运行 | `.AppImage` | `chmod +x 文件名.AppImage` 后运行 `./文件名.AppImage` |

在应用菜单选择 **检查更新…**，下载新版后按上表安装。需要镜像时，退出应用，然后用 `DSH_LINUX_UPDATE_MIRROR=https://gh-proxy.org/ dsh-linux` 启动。便携版将命令中的 `dsh-linux` 换成 AppImage 路径。

## 自行构建

在 Linux x86_64 环境准备构建依赖和对应版本的 Node.js、pnpm，然后将下方 `tag` 换成要构建的上游版本标签。 [构建环境](.github/workflows/build-linux.yml) · [上游版本](https://github.com/deepseek-ai/deepseek-harness/releases)

```sh
git clone https://github.com/LeiSteins/dsh-linux-build.git
cd dsh-linux-build

tag=dsh-v0.2.3-alpha.2
git clone --depth 1 --branch "$tag" https://github.com/deepseek-ai/deepseek-harness.git upstream
./scripts/build-linux.sh upstream "$tag" dist
```

构建完成后，在 `dist/` 中选择安装包，按上表安装。
