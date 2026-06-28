import AppKit
import Observation
import ServiceManagement

enum UsageProvider: String, CaseIterable, Identifiable, Sendable {
    case codex = "Codex"
    case antigravity = "Antigravity"

    var id: Self { self }
}

@MainActor
@Observable
final class AppRuntime {
    static let shared = AppRuntime()

    let usageStore: UsageStore
    let antigravityStore: AntigravityUsageStore
    var activeProvider: UsageProvider = .codex
    private var notchController: NotchController?
    private(set) var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    var onlyShowOnForeground: Bool = UserDefaults.standard.bool(forKey: "onlyShowOnForeground") {
        didSet {
            UserDefaults.standard.set(onlyShowOnForeground, forKey: "onlyShowOnForeground")
            notchController?.updateVisibility()
        }
    }

    private init() {
        usageStore = UsageStore(provider: CodexAppServerUsageProvider())
        antigravityStore = AntigravityUsageStore(provider: AntigravityLocalUsageProvider())
    }

    func start() {
        guard notchController == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        let controller = NotchController(codexStore: usageStore, antigravityStore: antigravityStore)
        notchController = controller
        controller.showCompact()
        usageStore.startAutomaticRefresh()
        antigravityStore.startAutomaticRefresh()
    }

    func stop() {
        ManagedCLIProcessRegistry.shared.terminate()
        usageStore.stopAutomaticRefresh()
        antigravityStore.stop()
        notchController?.stop()
        notchController = nil
    }

    func showCard() {
        notchController?.expand()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }
}
