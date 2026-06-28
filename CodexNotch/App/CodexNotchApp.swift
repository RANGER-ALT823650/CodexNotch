import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRuntime.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.shared.stop()
    }
}

@main
struct CodexNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra("Codex Notch", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContent(runtime: runtime)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    let runtime: AppRuntime

    var body: some View {
        if let snapshot = runtime.usageStore.snapshot {
            Text("5 小时剩余 \(Int(snapshot.primary.remainingPercent.rounded()))%")
            Text("一周剩余 \(Int(snapshot.secondary.remainingPercent.rounded()))%")
            Divider()
        }

        if let snapshot = runtime.antigravityStore.snapshot {
            Text("Antigravity（\(snapshot.source.rawValue)）")
            ForEach(snapshot.buckets) { bucket in
                if let remaining = bucket.remainingPercent, bucket.usageKnown {
                    Text("\(bucket.groupTitle) \(bucket.title) 剩余 \(Int(remaining.rounded()))%")
                }
            }
            Divider()
        }

        Button("展开用量卡片") {
            runtime.showCard()
        }

        Button(runtime.usageStore.isRefreshing ? "正在刷新…" : "刷新") {
            Task {
                async let codex: Void = runtime.usageStore.refresh()
                async let antigravity: Void = runtime.antigravityStore.refresh()
                _ = await (codex, antigravity)
            }
        }
        .disabled(runtime.usageStore.isRefreshing || runtime.antigravityStore.isRefreshing)

        Toggle("登录时启动", isOn: Binding(
            get: { runtime.launchAtLoginEnabled },
            set: { enabled in runtime.setLaunchAtLogin(enabled) }
        ))

        Toggle("仅在 agy/codex 窗口前台时显示", isOn: Binding(
            get: { runtime.onlyShowOnForeground },
            set: { runtime.onlyShowOnForeground = $0 }
        ))

        if let error = runtime.usageStore.errorMessage
            ?? runtime.antigravityStore.errorMessage
            ?? runtime.launchAtLoginError
        {
            Text(error)
        }

        Divider()
        Button("退出 Codex Notch") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
