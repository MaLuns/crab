# 内置应用检测与目录传递

内置应用统一定义在 `Shared/ApplicationCatalog.swift`，包括稳定 ID、显示名、Bundle ID、查找名称和打开方式。操作实例的应用参数通过 `catalogID` 关联该目录，应用信息和打开策略在同一处核对。

## 检测与显示

- 主应用通过 Launch Services 查找应用，并验证 `.app`、可执行文件及特殊适配的身份；用户指定路径优先，指定路径失效时不静默换成另一份应用。
- 操作库保留应用操作，并显示安装与路径可用状态；筛选器可单独查看不可用项。自定义应用路径可通过编辑操作修改。
- 主应用将以操作实例 ID 为键的 `previews` 放入配置广播副本，包含可执行状态及图标预览。Finder 扩展使用该快照过滤不可执行的菜单引用，无需读取应用包。
- `previews` 不写入主应用的持久化配置；扩展缓存保留广播快照。应用可用状态变化不改写操作实例或菜单编排。

## 打开方式

| 类型 | 行为 |
| --- | --- |
| 编辑器 | 使用所选 `.app` 接收所选文件或目录；空选中时接收当前目录 |
| Terminal / iTerm2 | 保留原有窗口、标签页适配；使用所选目录，选中文件时使用其父目录 |
| Ghostty / Hyper | 通过系统打开目录，避免把所选文件当作待执行文件传入终端 |
| Warp | 使用 `warp://action/new_window?path=…`，完整编码目录并交给明确选中的 Warp 应用 |
| Tabby | 直接调用应用包内可执行文件，参数为 `open` 和绝对目录；不拼接 Shell 命令，不依赖用户 PATH 或额外安装的 CLI |

目录型适配沿用原 Terminal 的单目录约定：多选时以第一项的目录为目标。手动添加且 Bundle ID 匹配的应用复用相同适配，未知应用保留系统文档打开方式。成功不增加提示，启动或命令失败沿用错误提示。

上述协议来源：

- [Warp URI Scheme](https://docs.warp.dev/terminal/more-features/uri-scheme)
- [Tabby 命令参数定义](https://github.com/Eugeny/tabby/blob/master/app/lib/cli.ts)、[应用身份](https://github.com/Eugeny/tabby/blob/master/electron-builder.yml)
- [Ghostty 的目录和文件打开处理](https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/App/AppDelegate.swift)
- [Hyper 的 macOS CLI 转发](https://github.com/vercel/hyper/blob/canary/cli/index.ts)、[文件打开事件](https://github.com/vercel/hyper/blob/canary/app/index.ts)

自动化使用临时应用包、独立配置、注入的系统打开入口及真实的测试用命令进程；不能据此认定未安装第三方应用的各个版本均已实际验收。
