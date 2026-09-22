import AppKit
import SwiftUI

@MainActor
final class MenuPresentationMonitor: MenuPresentationMonitoring {
    var onChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onChange?(true) }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onChange?(false) }
            },
        ]
    }

    func stop() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
        onChange?(false)
    }
}

@MainActor
final class RemoteFeedbackService: RemoteFeedbackDisplaying {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ edge: RemoteFeedbackEdge) {
        hideTask?.cancel()

        let panel = panel ?? makePanel()
        let screen = screenUnderPointer ?? NSScreen.main
        guard let screen else { return }

        panel.contentView = NSHostingView(rootView: RemoteFeedbackView(edge: edge))
        panel.setFrame(frame(for: edge, on: screen), display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        hideTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled, let self, let panel else { return }

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor in
                    if panel.alphaValue == 0 {
                        panel.orderOut(nil)
                    }
                    self.hideTask = nil
                }
            })
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }

    private var screenUnderPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) }
    }

    private func frame(for edge: RemoteFeedbackEdge, on screen: NSScreen) -> NSRect {
        let width = screen.frame.width * 0.2
        let x = edge == .left ? screen.frame.minX : screen.frame.maxX - width
        return NSRect(x: x, y: screen.frame.minY, width: width, height: screen.frame.height)
    }
}

private struct RemoteFeedbackView: View {
    let edge: RemoteFeedbackEdge

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    colors: edge == .left ? [.black, .black.opacity(0.72), .clear] : [.clear, .black.opacity(0.72), .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .ignoresSafeArea()
    }
}
