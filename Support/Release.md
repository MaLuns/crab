# GitHub Actions 打包与发版

发布入口为 `.github/workflows/release.yml`，本地打包入口为 `Scripts/release.sh`。使用已提交的 Xcode 工程，不需要在 CI 安装 XcodeGen。

## 触发方式

- 推送格式为 `vMAJOR.MINOR.PATCH` 的标签时，构建、检查两个架构的包；两者均成功后才创建 GitHub Release。版本号各段为非负整数，不带多余前导零，例如 `v1.0.0`。不接受预发布后缀。
- `main` 分支中 workflow、发布脚本、`project.yml` 或两端 Info.plist 的变更会触发验证；手动运行 workflow 也仅验证。验证包使用 `v0.0.0`，不创建 Release。
- 标签触发器匹配 `v*`，具体格式由发布脚本检查；不符合上述格式的标签会失败，不会发布。

准备发布时，先确保发布代码已推送，并选择尚未发布的版本号。在项目根目录执行，例如：

```sh
git tag v1.0.0
git push main v1.0.0
```

此处 `main` 是本仓库当前远程名称；只推送该标签即可触发发版，不需要手动创建 GitHub Release。

## 两种独立架构的产物

两个 macOS job 分别构建 `arm64` 和 `x86_64`，不合并为通用二进制。以 `v1.0.0` 为例，Release 附件为：

```text
Crab-v1.0.0-macOS-arm64.zip
Crab-v1.0.0-macOS-arm64.zip.sha256
Crab-v1.0.0-macOS-x86_64.zip
Crab-v1.0.0-macOS-x86_64.zip.sha256
```

Apple Silicon Mac 使用 `arm64` 包，Intel Mac 使用 `x86_64` 包。ZIP 中包含完整的 `Crab.app` 及其 Finder 扩展。

发布脚本核对两端版本和 Bundle ID、目标架构、ad-hoc 签名、必要 entitlement，以及 WebP 静态库的单一架构；打包后解压并再次验证完整应用签名。发布 job 等待两个构建成功，核对两个 ZIP 及其 SHA-256 校验文件后统一上传，避免只发布一个架构。

Actions artifacts 只用于传递构建结果，保留 1 天；正式下载附件保存在 GitHub Release 中。主分支和手动验证产生的临时包不会上传到 Release。

## 版本与签名

普通本地构建的默认版本仍为 `1.0.0`、构建号 `1`。发布脚本从标签去掉前缀 `v`，通过 `MARKETING_VERSION` 同时传入主应用及 Finder 扩展；构建号优先使用 `RELEASE_BUILD_NUMBER`，其次为 GitHub 的 `GITHUB_RUN_NUMBER`，本地默认 `1`。所有版本写入均由 Xcode 在签名前完成，不修改已签名 bundle。

产物采用无需开发者证书的 ad-hoc 签名，不包含 Developer ID 签名或 Apple 公证。签名检查通过表示包内代码和资源封装一致，不代表已完成真实 Finder 界面验收或首次下载启动验收。

发布 job 将工作流自带的 `github.token` 传为 `GH_TOKEN`，并仅在该 job 授予 `contents: write`。无需额外配置个人访问令牌、签名证书或公证凭据。

## 本地打包

需要完整 Xcode 工具链。在项目根目录按顺序执行：

```sh
bash Scripts/release.sh v1.0.0 arm64
bash Scripts/release.sh v1.0.0 x86_64
```

默认分别输出到 `build/release-arm64/release/` 和 `build/release-x86_64/release/`。可覆盖 DerivedData 目录和构建号，例如：

```sh
BUILD_DIR="$PWD/build/local-arm64" RELEASE_BUILD_NUMBER=2 bash Scripts/release.sh v1.0.0 arm64
```

`BUILD_DIR` 只隔离 Xcode 输出；WebP 预构建仍共享仓库内的 `build/vendor-webp/` 和 `Support/WebP/lib/libwebp.a`。同一个本地检出中应串行打包两个架构，不要同时启动两个打包进程。CI 的两个 job 使用独立检出，不共享这些输出。
