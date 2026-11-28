# DSH Linux 社区构建

DeepSeek Harness 的 Linux amd64 和 arm64 桌面安装包，由社区维护。

## 下载与安装

打开发布页，在 **Assets** 中按文件名里的 `amd64` 或 `arm64` 选择安装包。旧版文件里的 `x86_64` 对应 `amd64`，`aarch64` 对应 `arm64`。 [GitHub Releases](https://github.com/LeiSteins/dsh-linux-build/releases)

| 环境 | 文件 | 安装或运行 |
| --- | --- | --- |
| Debian、Ubuntu | `.deb` | `sudo apt install ./文件名.deb` |
| Fedora | `.rpm` | `sudo dnf install ./文件名.rpm` |
| Arch Linux | `.pkg.tar.zst` | `sudo pacman -U ./文件名.pkg.tar.zst` |
| 便携运行 | `.AppImage` | `chmod +x 文件名.AppImage` 后运行 `./文件名.AppImage` |

在应用菜单选择 **检查更新…**，下载新版后按上表安装。从旧命名的安装包迁移时，请直接从发布页下载安装包并重新安装。需要镜像时，退出应用，然后用 `DSH_LINUX_UPDATE_MIRROR=https://gh-proxy.org/ dsh-linux` 启动。便携版将命令中的 `dsh-linux` 换成 AppImage 路径。

## 自行构建

在 Linux amd64 或 arm64 环境准备构建依赖和对应版本的 Node.js、pnpm，然后将下方 `tag` 换成要构建的上游版本标签。脚本按宿主架构原生构建。 [构建环境](.github/workflows/build-linux.yml) · [上游版本](https://github.com/deepseek-ai/deepseek-harness/releases)

```sh
git clone https://github.com/LeiSteins/dsh-linux-build.git
cd dsh-linux-build

tag=dsh-v0.2.3-alpha.2
git clone --depth 1 --branch "$tag" https://github.com/deepseek-ai/deepseek-harness.git upstream
./scripts/build-linux.sh upstream "$tag" dist
```

构建完成后，在 `dist/` 中选择安装包，按上表安装。

## 发布

在 GitHub Actions 手动运行 **Build and publish DSH Linux**。需要指定发布修订号时，填写 `release_revision`。

## 致谢

- [DeepSeek Harness 官网](https://www.deepseek.com/harness/)
- [LinuxDO 社区](https://linux.do/)

## License

本项目采用 [MIT 许可证](LICENSE)。
