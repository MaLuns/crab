# GitHub Actions 打包与发版

发布入口为 `.github/workflows/release.yml`，本地打包入口为 `Scripts/release.sh`。使用已提交的 Xcode 工程，不需要在 CI 安装 XcodeGen。

## 触发方式

- 推送格式为 `vMAJOR.MINOR.PATCH` 的标签时，构建、检查两个架构的包并生成提交说明；全部成功后才创建 GitHub Release。版本号各段为非负整数，不带多余前导零，例如 `v1.0.0`。不接受预发布后缀。
- `main` 分支中 workflow、发布脚本、`cliff.toml`、`project.yml` 或两端 Info.plist 的变更会触发验证；手动运行 workflow 也仅验证。验证包使用 `v0.0.0`，提交说明生成待发布预览，不创建 Release。
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

发布脚本核对两端版本和 Bundle ID、目标架构、ad-hoc 签名、必要 entitlement，以及 WebP 静态库的单一架构；打包后解压并再次验证完整应用签名。发布 job 等待两个构建和提交说明生成均成功，核对两个 ZIP、各自的 SHA-256 校验文件及非空说明文件后统一上传。

Actions artifacts 用于传递构建包和提交说明，均保留 1 天；正式下载附件保存在 GitHub Release 中。主分支和手动验证产生的临时包及说明不会上传到 Release。

## 提交说明与发布 Action

独立的 Ubuntu `changelog` job 使用 `fetch-depth: 0` 检出完整历史及标签，并调用 [orhun/git-cliff-action v4.9.1](https://github.com/orhun/git-cliff-action/releases/tag/v4.9.1)，固定使用 git-cliff `v2.14.2`。标签发布使用 `--current --use-branch-tags --no-exec`，根据当前标签及其历史中的上一匹配标签生成说明；首次发布从根提交起选取历史，再应用下述筛选。只有符合 `vMAJOR.MINOR.PATCH` 的标签参与发布区间，不符合格式的标签不会截断提交说明。主分支和手动验证使用 `--unreleased --use-branch-tags --no-exec` 生成待发布预览。

`cliff.toml` 同时按提交类型和改动文件范围筛选，不展示所有提交：

- 跳过 `ci:`、`docs:`、`chore:`、`build:`、`test:`、`style:`、`refactor:` 前缀，包含带 scope 的形式；显式带 `!` 的不兼容代码变更保留。
- 文件范围限定为 `Crab/`、`Shared/`、`FinderExtension/` 下的产品源码与资源、`project.yml`、原生归档接口头文件和模块映射，以及 WebP 接口头文件与编解码源码；排除应用内的许可证目录。仅修改 README、Support 专题文档、CI、测试或预览的提交不会进入说明。
- 通过文件范围筛选的 `feat:`、`fix:`、`perf:` 分别归入新增功能、问题修复、性能优化，`revert:` 保留回退记录；未命中类型排除规则的其他提交归入其他变更。没有类型前缀、但触及产品源码或资源的中文及自由格式提交仍保留。

这是提交类型与文件范围筛选，不会分析 Swift 代码是否实际改变功能；类型标记和文件范围决定记录是否保留。说明展示筛选后每条提交的标题及提交链接；有可用且不同的上一版本信息时附上 compare 链接，末尾保留架构选择、安装与签名说明。纯维护版本显示“暂无面向使用者的功能更新”。版本号通过 `GIT_CLIFF_TAG` 明确传入，避免打标签的维护提交被过滤后丢失版本标题。提交范围选择、历史遍历和分类由 git-cliff 处理，没有自写范围、分页或提交解析脚本。

发布 job 使用 [softprops/action-gh-release v3.0.3](https://github.com/softprops/action-gh-release/releases/tag/v3.0.3)。通过 `body_path` 读取生成的说明文件，关闭 GitHub 的 `generate_release_notes`，以免再次生成另一套说明。四个附件使用显式路径，设置 `fail_on_unmatched_files: true`，任一路径无文件即失败。首次创建稳定版时先创建草稿，所有附件上传成功后才公开；上传失败会保留草稿。已公开 Release 的重跑沿用其公开状态，不属于首次创建的草稿发布流程。

两个第三方 Action 均在 workflow 中固定到对应版本的完整 commit SHA。

## 版本与签名

普通本地构建的默认版本仍为 `1.0.0`、构建号 `1`。发布脚本从标签去掉前缀 `v`，通过 `MARKETING_VERSION` 同时传入主应用及 Finder 扩展；构建号优先使用 `RELEASE_BUILD_NUMBER`，其次为 GitHub 的 `GITHUB_RUN_NUMBER`，本地默认 `1`。所有版本写入均由 Xcode 在签名前完成，不修改已签名 bundle。

产物采用无需开发者证书的 ad-hoc 签名，不包含 Developer ID 签名或 Apple 公证。签名检查通过表示包内代码和资源封装一致，不代表已完成真实 Finder 界面验收或首次下载启动验收。

发布 Action 使用工作流自带的 `github.token`，仅发布 job 获得 `contents: write`。无需手工配置个人访问令牌、签名证书或公证凭据。

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
