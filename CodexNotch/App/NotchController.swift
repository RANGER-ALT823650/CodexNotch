import AppKit
import DynamicNotchKit
import SwiftUI

enum NotchInteractionGeometry {
    static func compactFrame(
        screenFrame: NSRect,
        safeAreaTop: CGFloat,
        menuBarHeight: CGFloat,
        auxiliaryLeft: NSRect?,
        auxiliaryRight: NSRect?,
        sideContentWidth: CGFloat = 160
    ) -> NSRect {
        let notchWidth: CGFloat
        if let auxiliaryLeft,
           let auxiliaryRight,
           auxiliaryLeft.width > 0,
           auxiliaryRight.width > 0
        {
            notchWidth = max(0, auxiliaryRight.minX - auxiliaryLeft.maxX)
        } else {
            notchWidth = 300
        }

        let height = max(safeAreaTop, menuBarHeight) + 4
        let width = notchWidth + sideContentWidth
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}

@MainActor
final class NotchController {
    private let codexStore: UsageStore
    private let antigravityStore: AntigravityUsageStore
    private var outsideLocalMonitor: Any?
    private var outsideGlobalMonitor: Any?
    private var compactLocalMonitor: Any?
    private var compactGlobalMonitor: Any?
    private var isExpanded = false
    private var isCompactVisible = false
    private var observerTimer: Timer?
    private var workspaceNotificationObserver: Any?

    private lazy var notch = DynamicNotch(
        hoverBehavior: .all,
        style: .auto,
        expanded: { [codexStore, antigravityStore] in
            UsageCardView(codexStore: codexStore, antigravityStore: antigravityStore) {
                [weak self] in self?.compact()
            }
        },
        compactLeading: {
            UsageCompactView(
                kind: .primary
            ) { [weak self] in self?.expand() }
        },
        compactTrailing: {
            UsageCompactView(
                kind: .secondary
            ) { [weak self] in self?.expand() }
        }
    )

    init(codexStore: UsageStore, antigravityStore: AntigravityUsageStore) {
        self.codexStore = codexStore
        self.antigravityStore = antigravityStore
        startForegroundObserver()
    }

    func showCompact() {
        isExpanded = false
        isCompactVisible = true
        updateVisibility()
    }

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        isCompactVisible = false
        removeCompactClickMonitors()
        Task {
            await notch.expand(on: targetScreen)
            installOutsideClickMonitors()
        }
    }

    func compact() {
        guard isExpanded else { return }
        isExpanded = false
        isCompactVisible = true
        removeOutsideClickMonitors()
        updateVisibility()
    }

    func stop() {
        isExpanded = false
        removeOutsideClickMonitors()
        removeCompactClickMonitors()
        stopForegroundObserver()
        Task { await notch.hide() }
    }

    func updateVisibility() {
        guard !isExpanded else { return }

        let screen = targetScreen
        let isFullScreen = isFrontmostAppFullScreen(on: screen)
        let isMatchedApp = checkForegroundAppMatches()

        let shouldShow: Bool
        if isFullScreen {
            // In full screen, we ONLY show the notch if the active app is agy or codex, regardless of the setting.
            shouldShow = isMatchedApp
        } else {
            // Not in full screen:
            if AppRuntime.shared.onlyShowOnForeground {
                // Option is ON: show only if the active app matches
                shouldShow = isMatchedApp
            } else {
                // Option is OFF: always show
                shouldShow = true
            }
        }

        if shouldShow {
            Task {
                await notch.compact(on: screen)
                installCompactClickMonitors()
            }
            isCompactVisible = true
        } else {
            if isCompactVisible {
                isCompactVisible = false
                removeCompactClickMonitors()
                Task {
                    await notch.hide()
                }
            }
        }
    }

    private func isFrontmostAppFullScreen(on screen: NSScreen) -> Bool {
        // 1. Accessibility API check (most reliable for native/Electron apps)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
           let appRef = focusedApp as! AXUIElement? {
            var focusedWindow: AnyObject?
            if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
               let windowRef = focusedWindow as! AXUIElement? {
                var isFS: AnyObject?
                if AXUIElementCopyAttributeValue(windowRef, "AXFullScreen" as CFString, &isFS) == .success,
                   let isFSBool = isFS as? Bool {
                    return isFSBool
                }
            }
        }

        // 2. Window list bounds fallback (handles notched screen black bar and standard full screen)
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        if let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            let screenFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            for info in windowListInfo {
                guard let windowOwnerPID = info[kCGWindowOwnerPID as String] as? Int,
                      windowOwnerPID == frontmost.processIdentifier,
                      let windowLayer = info[kCGWindowLayer as String] as? Int,
                      windowLayer == 0,
                      let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                      let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
                else { continue }

                let widthMatches = abs(bounds.width - screenFrame.width) < 10
                let heightMatches = abs(bounds.height - screenFrame.height) < 10 || abs(bounds.height - visibleFrame.height) < 10

                if widthMatches && heightMatches {
                    return true
                }
            }
        }

        // 3. Basic fallback
        return screen.frame.maxY == screen.visibleFrame.maxY
    }

    private func checkForegroundAppMatches() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        let appName = frontmost.localizedName ?? ""
        let bundleID = frontmost.bundleIdentifier ?? ""

        let lowerAppName = appName.lowercased()
        let lowerBundleID = bundleID.lowercased()

        if lowerAppName.contains("codex") || lowerBundleID.contains("codex") {
            return true
        }

        let isTerminalOrIDE = lowerAppName.contains("terminal") ||
                              lowerAppName.contains("iterm") ||
                              lowerAppName.contains("cursor") ||
                              lowerAppName.contains("code") ||
                              lowerAppName.contains("zed") ||
                              lowerBundleID.contains("terminal") ||
                              lowerBundleID.contains("iterm") ||
                              lowerBundleID.contains("cursor") ||
                              lowerBundleID.contains("vscode") ||
                              lowerBundleID.contains("zed")

        if isTerminalOrIDE {
            let systemWide = AXUIElementCreateSystemWide()
            var focusedApp: AnyObject?
            let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
            if result == .success, let appRef = focusedApp as! AXUIElement? {
                var focusedWindow: AnyObject?
                if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success,
                   let windowRef = focusedWindow as! AXUIElement? {
                    var title: AnyObject?
                    if AXUIElementCopyAttributeValue(windowRef, kAXTitleAttribute as CFString, &title) == .success,
                       let titleString = title as? String {
                        let lowerTitle = titleString.lowercased()
                        if lowerTitle.contains("agy") || lowerTitle.contains("codex") {
                            return true
                        }
                    }
                }
            }

            let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
            if let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for info in windowListInfo {
                    guard let windowOwnerPID = info[kCGWindowOwnerPID as String] as? Int,
                          windowOwnerPID == frontmost.processIdentifier,
                          let windowName = info[kCGWindowName as String] as? String else { continue }
                    let lowerTitle = windowName.lowercased()
                    if lowerTitle.contains("agy") || lowerTitle.contains("codex") {
                        return true
                    }
                }
            }

            return true
        }

        return false
    }

    private func startForegroundObserver() {
        guard workspaceNotificationObserver == nil else { return }

        workspaceNotificationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibility()
            }
        }

        observerTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateVisibility()
            }
        }
    }

    private func stopForegroundObserver() {
        observerTimer?.invalidate()
        observerTimer = nil
        if let observer = workspaceNotificationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceNotificationObserver = nil
        }
    }

    private var targetScreen: NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func installOutsideClickMonitors() {
        guard outsideLocalMonitor == nil, outsideGlobalMonitor == nil else { return }

        outsideLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            let location = Self.screenLocation(for: event)
            Task { @MainActor [weak self] in self?.collapseIfOutside(location) }
            return event
        }

        outsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.collapseIfOutside(location) }
        }
    }

    private func collapseIfOutside(_ point: NSPoint) {
        guard isExpanded, !expandedInteractionFrame.contains(point) else { return }
        compact()
    }

    private func installCompactClickMonitors() {
        guard compactLocalMonitor == nil, compactGlobalMonitor == nil else { return }

        compactLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            let location = Self.screenLocation(for: event)
            Task { @MainActor [weak self] in self?.expandIfInsideCompactNotch(location) }
            return event
        }

        compactGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.expandIfInsideCompactNotch(location) }
        }
    }

    private func expandIfInsideCompactNotch(_ point: NSPoint) {
        guard !isExpanded,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              compactInteractionFrame(on: screen).contains(point)
        else { return }
        expand()
    }

    private func compactInteractionFrame(on screen: NSScreen) -> NSRect {
        NotchInteractionGeometry.compactFrame(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            auxiliaryLeft: screen.auxiliaryTopLeftArea,
            auxiliaryRight: screen.auxiliaryTopRightArea
        )
    }

    private static func screenLocation(for event: NSEvent) -> NSPoint {
        event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    private var expandedInteractionFrame: NSRect {
        let screen = notch.windowController?.window?.screen ?? targetScreen
        let width = UsageCardView.contentSize.width + 50
        let height = UsageCardView.contentSize.height + screen.safeAreaInsets.top + 45
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func removeOutsideClickMonitors() {
        if let outsideLocalMonitor {
            NSEvent.removeMonitor(outsideLocalMonitor)
            self.outsideLocalMonitor = nil
        }
        if let outsideGlobalMonitor {
            NSEvent.removeMonitor(outsideGlobalMonitor)
            self.outsideGlobalMonitor = nil
        }
    }

    private func removeCompactClickMonitors() {
        if let compactLocalMonitor {
            NSEvent.removeMonitor(compactLocalMonitor)
            self.compactLocalMonitor = nil
        }
        if let compactGlobalMonitor {
            NSEvent.removeMonitor(compactGlobalMonitor)
            self.compactGlobalMonitor = nil
        }
    }
}
