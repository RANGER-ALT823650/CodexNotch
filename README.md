# Codex Notch

Codex Notch 是一个 macOS 14+ 常驻工具，把 Codex 的 5 小时和每周剩余用量显示在 MacBook 刘海两侧。光标进入刘海区域产生触觉反馈后，点击刘海或两侧用量即可展开卡片；在卡片内用触控板双指左右滑动可切换 Codex 与 Antigravity，点击卡片外收起。

## 实现

- 通过本机 `codex app-server --stdio` 的 `account/rateLimits/read` JSON-RPC 获取用量。
- Antigravity 优先探测已运行应用的本地配额接口；应用未运行时，用伪终端保持 `agy` CLI 存活并读取其 localhost HTTPS 接口。
- Antigravity 数据层只访问回环接口，不读取或复制本机 OAuth 凭据。
- 直接依赖 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 提供刘海窗口、动画和无刘海退化逻辑。
- Codex RPC 进程和 JSONL 处理结构参考了 [CodexBar](https://github.com/steipete/CodexBar)。
- 每 5 分钟自动刷新，也可从卡片或菜单栏手动刷新。

## 构建

需要 Xcode 26、XcodeGen 和已登录的 Codex CLI。

```bash
xcodegen generate
xcodebuild -project CodexNotch.xcodeproj -scheme CodexNotch -resolvePackageDependencies
xcodebuild test -project CodexNotch.xcodeproj -scheme CodexNotch -destination 'platform=macOS'
xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch -configuration Debug -destination 'platform=macOS'
```

也可直接用 Xcode 打开 `CodexNotch.xcodeproj` 运行。
本仓库验证后的本地构建位于 `.build/DerivedData/Build/Products/Debug/CodexNotch.app`。

## 长期运行

这是独立的 macOS App。Xcode 只负责编译和启动；App 启动后，即使关闭 Xcode，已经运行的进程也会继续工作。

不要把长期使用的副本留在 DerivedData 中，因为清理构建缓存会删除它。建议构建 Release 版本后复制到 `~/Applications` 或 `/Applications`，从固定位置启动，然后在菜单栏中开启“登录时启动”：

```bash
xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData

mkdir -p "$HOME/Applications"
ditto .build/DerivedData/Build/Products/Release/CodexNotch.app \
  "$HOME/Applications/CodexNotch.app"
open "$HOME/Applications/CodexNotch.app"
```

“登录时启动”由 macOS `SMAppService` 管理，适合日常常驻和重启后自动启动。若还要求进程崩溃后自动拉起，需要另外配置带 `KeepAlive` 的 LaunchAgent；这比普通菜单栏 App 更强，但发布版应配合正式签名和独立 helper 使用。

## 运行条件

- macOS 14 或更高版本。
- `codex` 位于 `/opt/homebrew/bin/codex`、`/usr/local/bin/codex`、`~/.local/bin/codex` 之一，或通过 `CODEX_PATH` 指定。
- Codex CLI 已用 ChatGPT 账号登录。
- Antigravity 配额需要已登录的 Antigravity 应用，或位于常用安装路径且已登录的 `agy`。也可用 `ANTIGRAVITY_PATH` 指定 CLI。
- 外接无刘海屏幕上 DynamicNotchKit 会使用 floating 样式；紧凑模式则由菜单栏入口替代。

## 归属

第三方代码及许可证见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
