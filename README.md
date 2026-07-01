# Codex Notch — MacBook 刘海用量监控工具

<img src="https://img.shields.io/badge/macOS-14%2B-brightgreen" alt="macOS 14+"> <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0">

**Codex Notch** 是一款运行在 MacBook 刘海区域的常驻工具，让你**一眼就能看到** Codex CLI 和 Antigravity 的用量剩余情况，无需打开终端或浏览器。

---

## ✨ 它能做什么？

- **刘海两侧显示用量** — 左侧显示「5 小时」剩余、右侧显示「一周」剩余百分比
- **点击展开卡片** — 点击刘海或两侧用量数字，展开详细用量卡片
- **双指滑动切换** — 在 Codex、Antigravity 和所有智能体 Token 热力图之间切换
- **365 天活动热力图** — 以 GitHub 贡献图的方式展示本机所有支持智能体的 Token 用量
- **颜色提醒** — 绿色充足、橙色警告、红色不足，一目了然
- **自动刷新** — 每 5 分钟自动刷新一次，也可手动刷新
- **菜单栏入口** — 菜单栏中也有小图标，可以展开卡片、刷新、设置开机启动
- **登录时自启** — 设置后每次开机自动运行

## 📸 效果预览

| 紧凑模式（刘海两侧） | 展开卡片（Codex 用量） | Antigravity 用量 |
|---|---|---|
| ![compact-view](docs/screenshots/compact-view.png) | ![card-view](docs/screenshots/card-view.png) | ![antigravity-view](docs/screenshots/antigravity-view.png) |

---

## 🛠️ 如何安装和运行？

### 你需要准备

1. **Mac 电脑**，系统 **macOS 14 (Sonoma)** 或更高版本
2. **Xcode 26** 或更高版本（从 Mac App Store 免费下载）
3. **Codex CLI** — 已安装并用 ChatGPT 账号登录
   - 通常安装在 `/opt/homebrew/bin/codex` 或 `/usr/local/bin/codex`
4. **Antigravity**（可选）— 如果需要查看 Antigravity 用量
   - 安装 Antigravity 应用或 `agy` CLI 并登录
5. **Node.js 20+** — 用于一次性运行 TokenTracker 采集器
6. **XcodeGen**（可选，用于命令行构建）

### 方法一：用 Xcode 直接运行（最简单）

```bash
# 1. 用 XcodeGen 生成 .xcodeproj（如果项目中没有）
xcodegen generate

# 2. 用 Xcode 打开项目
open CodexNotch.xcodeproj

# 3. 在 Xcode 中点击 ▶️ 运行按钮（或按 Cmd+R）
```

### 方法二：命令行构建

```bash
# 构建 Debug 版本
xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch -configuration Debug -destination 'platform=macOS'

# 构建 Release 版本（推荐长期使用）
xcodebuild build -project CodexNotch.xcodeproj -scheme CodexNotch \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData

# 复制到应用程序目录
mkdir -p "$HOME/Applications"
ditto .build/DerivedData/Build/Products/Release/CodexNotch.app "$HOME/Applications/CodexNotch.app"
open "$HOME/Applications/CodexNotch.app"
```

### 长期使用建议

1. 构建 Release 版本后，把 `CodexNotch.app` 复制到 `~/Applications` 或 `/Applications`
2. 从那里启动 App
3. 在菜单栏中开启 **"登录时启动"**，以后开机自动运行

---

## 🎯 如何使用？

启动后，你会看到：

1. **刘海两侧**出现白色小字显示用量（如 `5h 73%` 和 `7d 45%`）
2. **鼠标移入刘海区域**有触觉反馈，**点击刘海或数字**展开详细卡片
3. 在卡片中：
   - 查看 5 小时和一周的详细进度条和重置时间
   - 点击 🔄 按钮手动刷新
   - **双指左右滑动**切换到 Antigravity 用量
   - 继续滑动可查看所有智能体过去 365 天的 Token 热力图
   - 点击卡片外部或 `↑` 按钮收起
4. **菜单栏图标** `⊞` 点击后：
   - 查看用量文字摘要
   - 点击「展开用量卡片」展开卡片
   - 点击「刷新」手动刷新
   - 开关「登录时启动」
   - 开关「仅在 agy/codex 窗口前台时显示」

---

## ⚙️ 技术原理

- **Codex 用量** — 通过本地启动 `codex app-server --stdio` 进程，使用 JSON-RPC 调用 `account/rateLimits/read` 获取
- **Antigravity 用量** — 优先探测已运行的 Antigravity 应用的本地 HTTPS 接口；如果应用未运行，自动启动 `agy` CLI 获取
- **所有智能体 Token** — 调用固定版本的 TokenTracker 执行一次 `sync --auto`，然后原生读取 `~/.tokentracker/tracker/queue.jsonl`
- **内存策略** — 仅在切换到热力图或手动刷新时采集；不启动 TokenTracker Dashboard、菜单栏 App、WKWebView 或常驻服务
- **刘海窗口** — 基于 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) 实现，无刘海屏自动降级为浮动样式
- **自动刷新** — 每 5 分钟轮询一次

---

## 📁 项目结构

```
CodexNotch/
├── App/                    # 应用入口和主逻辑
│   ├── CodexNotchApp.swift # @main 入口，菜单栏
│   ├── AppRuntime.swift    # 全局共享状态
│   └── NotchController.swift # 刘海窗口控制
├── Models/                 # 数据模型
│   ├── UsageSnapshot.swift
│   └── AntigravityUsageSnapshot.swift
├── Services/               # 数据获取服务
│   ├── CodexUsageProviding.swift
│   ├── CodexAppServerUsageProvider.swift
│   ├── AntigravityUsageProviding.swift
│   ├── AntigravityLocalUsageProvider.swift
│   └── AntigravityQuotaParser.swift
├── State/                  # 状态管理（Observable）
│   ├── UsageStore.swift
│   └── AntigravityUsageStore.swift
├── UI/                     # 界面组件
│   ├── UsageCompactView.swift
│   ├── UsageCardView.swift
│   ├── UsageProgressView.swift
│   ├── AntigravityUsageView.swift
│   └── HorizontalSwipeDetector.swift
└── Resources/
    └── Info.plist
```

---

## 🔧 环境变量（可选）

| 变量 | 作用 |
|------|------|
| `CODEX_PATH` | 指定 Codex CLI 可执行文件路径 |
| `ANTIGRAVITY_PATH` | 指定 agy CLI 可执行文件路径 |
| `TOKENTRACKER_PATH` | 指定 TokenTracker CLI；未设置时优先查找已安装命令，再回退到固定版本的 `npx` |

---

## 📄 许可证

本项目包含第三方代码，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — MIT License
- [CodexBar](https://github.com/steipete/CodexBar) — MIT License（参考了 RPC 进程和 JSONL 处理结构）
- [TokenTracker](https://github.com/mm7894215/TokenTracker) — MIT License（仅使用一次性本地采集器，固定为 0.64.2）

---

## 🙋 常见问题

**Q: 外接显示器也能用吗？**  
A: 可以。无刘海屏幕上会使用浮动样式显示；紧凑模式下则由菜单栏入口替代。

**Q: 用量数据安全吗？**  
A: Antigravity 数据只访问本地回环接口（127.0.0.1），不会读取或复制 OAuth 凭据。

**Q: 为什么看不到用量？**  
A: 请确保 Codex CLI 或 Antigravity 已登录并正常运行。
