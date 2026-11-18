import AppKit
import AVFoundation
import SwiftUI

/// 仿 macOS 原生音量浮层：右上角的玻璃胶囊，喇叭图标 + 16 段刻度（支持 1/4 段的精细填充）
final class VolumeHUD: ObservableObject {
    static let shared = VolumeHUD()

    @Published var level: Double = 0
    @Published var visible = false

    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?
    static let size = CGSize(width: 306, height: 64)

    private init() {
        let pad: CGFloat = 20   // 留出阴影空间
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.size.width + pad * 2, height: Self.size.height + pad * 2),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: VolumeHUDView().environmentObject(self))
        host.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = host
    }

    /// 主线程调用
    func show(_ v: Double) {
        level = v
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            let vf = screen?.visibleFrame ?? .zero
            // 和系统一样出现在右上角、菜单栏下方
            panel.setFrameOrigin(NSPoint(x: vf.maxX - panel.frame.width + 8, y: vf.maxY - panel.frame.height + 8))
            panel.orderFrontRegardless()
        }
        if !visible { withAnimation(.easeOut(duration: 0.18)) { visible = true } }
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.35)) { self.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.visible == false { self?.panel.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}

private struct VolumeHUDView: View {
    @EnvironmentObject var hud: VolumeHUD
    private static let segments = 16

    private var symbol: String {
        let l = hud.level
        return l <= 0 ? "speaker.slash.fill" : l < 1.0 / 3 ? "speaker.wave.1.fill" : l < 2.0 / 3 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, alignment: .leading)
                .padding(.leading, 20)
            Spacer(minLength: 0)
            bars
                .frame(width: 214, height: 4)
                .padding(.trailing, 30)
        }
        .frame(width: VolumeHUD.size.width, height: VolumeHUD.size.height)
        .modifier(GlassCapsule())
        .environment(\.colorScheme, .dark)
        .opacity(hud.visible ? 1 : 0)
        .scaleEffect(hud.visible ? 1 : 0.94)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bars: some View {
        GeometryReader { g in
            let n = Self.segments
            let gap: CGFloat = 2
            let w = (g.size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            // 和系统一样按 1/4 段取整显示
            let filled = (hud.level * Double(n) * 4).rounded() / 4
            HStack(spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    let f = min(1, max(0, filled - Double(i)))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.22))
                        Capsule().fill(Color.white).frame(width: w * f)
                    }
                    .frame(width: w)
                }
            }
        }
    }
}

/// macOS 26 起用 Liquid Glass，旧系统退回材质
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        }
    }
}

/// 系统的音量反馈音（「调整音量时播放反馈」打开时才响，和系统一致）
enum VolumeFeedback {
    private static let player: AVAudioPlayer? = {
        let url = URL(fileURLWithPath: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff")
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }()

    static var enabled: Bool {
        let g = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (g?["com.apple.sound.beep.feedback"] as? Int ?? 1) != 0
    }

    /// 在音量队列上调用
    static func play() {
        guard let p = player else { return }
        p.currentTime = 0
        p.play()
    }
}
