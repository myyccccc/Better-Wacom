import AppKit
import SwiftUI

/// 屏幕下方短暂显示的浮层（类似系统音量提示），不抢焦点、不挡鼠标
final class HUD: ObservableObject {
    static let shared = HUD()

    @Published var symbol = "dial.medium.fill"
    @Published var title = ""
    @Published var detail: String?
    @Published var level: Double?

    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: HUDView().environmentObject(self))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
    }

    func show(symbol: String, title: String, detail: String? = nil, level: Double? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.level = level

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let vf = screen?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: vf.midX - 130, y: vf.minY + 120))
        if !panel.isVisible || panel.alphaValue < 1 {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self?.panel.animator().alphaValue = 0 },
                                                 completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    // 兼容旧调用
    func show(_ text: String) { show(symbol: "checkmark.circle.fill", title: text) }
}

private struct HUDView: View {
    @EnvironmentObject var hud: HUD

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: hud.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hud.title).font(.system(size: 15, weight: .semibold))
                    if let d = hud.detail {
                        Text(d).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let l = hud.level {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(Color.primary.opacity(0.9))
                            .frame(width: max(6, g.size.width * l))
                            .animation(.easeOut(duration: 0.08), value: l)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .frame(width: 260, height: 120)
    }
}
