<div align="center">
  <img src="Shared/Resources/CrabIcon.png" width="128" alt="Crab 图标" />
  <h1>Crab</h1>
  <p><b>把常用文件操作，放进访达右键菜单</b></p>
  <p>简体中文 · <a href="README_TW.md">繁體中文</a> · <a href="README_EN.md">English</a> · <a href="README_JA.md">日本語</a> · <a href="README_KR.md">한국어</a> · <a href="README_FR.md">Français</a> · <a href="README_ES.md">Español</a> · <a href="README_PT.md">Português</a> · <a href="README_DE.md">Deutsch</a></p>
  <p>macOS 13.0+</p>
</div>

![操作库：搜索、筛选并管理操作](Previews/操作库.png)

<details>
<summary>查看菜单编排</summary>

![菜单编排：管理分组和菜单项](Previews/菜单编排.png)

</details>

## 特点

- **文件工具**：新建文件、拷贝路径、剪切粘贴、文件校验、图片转换，以及 ZIP / 7z 压缩解压。
- **自定义操作**：添加文件模板、传送目录、常用目录、应用、自定义图标和脚本。
- **菜单编排**：分组管理、拖拽排序，独立调整菜单项的名称、图标和显示状态。
- **外观与语言**：彩色或纯色图标，跟随系统、亮色或暗色窗口主题，支持九种界面语言。

## 开始使用

需要 macOS 13 或更新版本，以及完整的 Xcode 工具链。在项目根目录构建并打开：

```sh
bash Scripts/build.sh
open build/Build/Products/Release/Crab.app
```

1. 在“通用设置”的权限区域打开扩展管理，启用 **Crab Finder 菜单**。
2. 在“操作库”使用预置操作，或点击“新增”添加自定义操作。
3. 在“菜单编排”添加操作，调整分组和顺序。新增操作不会自动加入菜单。
4. 保持 Crab 运行，回到访达，在文件、目录或空白位置打开右键菜单。

当前构建使用临时签名（ad-hoc），未经 Apple 公证。

## 使用提示

- 应用入口需要安装对应应用；脚本需要可用的解释器，原文件及执行权限保持不变。
- 解压支持 ZIP / 7z，不支持 RAR 或加密归档；大小等限制见[编解码说明](Support/NativeCodecs.md)。
- “显示隐藏文件 / 不显示隐藏文件”会重启访达。
- iCloud 与 OneDrive 文件夹中的备用菜单需在“通用设置”中启用，并授予辅助功能和访达自动化权限；输入监控按系统提示授权。

## 致谢

- **libwebp**：提供无损 WebP 编码支持。
- **libarchive**：通过 macOS 系统库提供 7z 解码支持。

## 许可

遵循 [Crab Noncommercial Source License 1.0](LICENSE)。个人非商业使用免费；传播须免费公开完整对应源码，修改版沿用本许可；商业用途须事先取得书面授权。
