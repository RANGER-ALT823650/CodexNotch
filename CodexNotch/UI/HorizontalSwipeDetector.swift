import AppKit
import SwiftUI

enum HorizontalSwipeDirection: Equatable {
    case left
    case right
}

struct HorizontalSwipeAccumulator {
    let threshold: CGFloat
    private(set) var accumulatedX: CGFloat = 0
    private(set) var hasTriggered = false

    init(threshold: CGFloat = 34) {
        self.threshold = threshold
    }

    mutating func begin() {
        accumulatedX = 0
        hasTriggered = false
    }

    mutating func add(deltaX: CGFloat, deltaY: CGFloat) -> HorizontalSwipeDirection? {
        guard !hasTriggered, abs(deltaX) > abs(deltaY) * 1.15 else { return nil }
        accumulatedX += deltaX
        guard abs(accumulatedX) >= threshold else { return nil }
        hasTriggered = true
        return accumulatedX < 0 ? .left : .right
    }

    mutating func end() {
        accumulatedX = 0
        hasTriggered = false
    }
}

struct HorizontalSwipeDetector: NSViewRepresentable {
    let onSwipe: (HorizontalSwipeDirection) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSwipe = onSwipe
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        var onSwipe: (HorizontalSwipeDirection) -> Void
        private weak var view: NSView?
        private var monitor: Any?
        private var accumulator = HorizontalSwipeAccumulator()
        private var lastUnphasedEventAt = Date.distantPast

        init(onSwipe: @escaping (HorizontalSwipeDirection) -> Void) {
            self.onSwipe = onSwipe
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            guard event.hasPreciseScrollingDeltas,
                  event.momentumPhase.isEmpty,
                  let view,
                  let window = view.window,
                  event.window === window,
                  view.bounds.contains(view.convert(event.locationInWindow, from: nil))
            else { return }

            if event.phase.contains(.began) {
                accumulator.begin()
            } else if event.phase.isEmpty, Date().timeIntervalSince(lastUnphasedEventAt) > 0.25 {
                accumulator.begin()
            }
            lastUnphasedEventAt = Date()

            if let direction = accumulator.add(
                deltaX: event.scrollingDeltaX,
                deltaY: event.scrollingDeltaY
            ) {
                onSwipe(direction)
            }

            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                accumulator.end()
            }
        }
    }
}

