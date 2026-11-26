import SwiftUI

/// 冷启动自适应开屏遮罩：
/// · 深色模式匹配暗夜星尘底图（SplashDark），浅色模式匹配通透蔚蓝光斑（SplashLight）
/// · 居中极简白色 RayLamb 字标聚焦显现后，整体高斯模糊放大消散进入主页
struct SplashOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinish: () -> Void

    @State private var textOpacity: Double = 0
    @State private var textBlur: CGFloat = 8
    @State private var textScale: CGFloat = 0.96
    @State private var bgScale: CGFloat = 1.05
    @State private var exitBlur: CGFloat = 0
    @State private var exitScale: CGFloat = 1.0
    @State private var exitOpacity: Double = 1
    @State private var isDismissing = false

    private var imageName: String {
        colorScheme == .dark ? "SplashDark" : "SplashLight"
    }

    private var fallbackColor: Color {
        colorScheme == .dark ? Color(hex: 0x050914) : Color(hex: 0x1D7AF2)
    }

    var body: some View {
        ZStack {
            fallbackColor
                .ignoresSafeArea()

            GeometryReader { geo in
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(bgScale)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            Text("RayLamb")
                .font(.system(size: 32, weight: .light))
                .tracking(6)
                .foregroundStyle(Color.white)
                .shadow(
                    color: Color(hex: 0x061A48).opacity(colorScheme == .dark ? 0.55 : 0.30),
                    radius: 14,
                    y: 2
                )
                .scaleEffect(textScale)
                .blur(radius: textBlur)
                .opacity(textOpacity)
        }
        .scaleEffect(exitScale)
        .blur(radius: exitBlur)
        .opacity(exitOpacity)
        .ignoresSafeArea()
        .allowsHitTesting(!isDismissing)
        .accessibilityHidden(true)
        .task {
            await playSequence()
        }
    }

    private func playSequence() async {
        if reduceMotion {
            textOpacity = 1
            textBlur = 0
            textScale = 1
            bgScale = 1
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            isDismissing = true
            withAnimation(.easeOut(duration: 0.25)) {
                exitOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            onFinish()
            return
        }

        try? await Task.sleep(nanoseconds: 40_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.42)) {
            textOpacity = 1
            textBlur = 0
            textScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.72)) {
            bgScale = 1.0
        }

        try? await Task.sleep(nanoseconds: 640_000_000)
        guard !Task.isCancelled else { return }
        isDismissing = true
        withAnimation(.easeInOut(duration: 0.50)) {
            exitBlur = 28
            exitScale = 1.08
            exitOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 520_000_000)
        guard !Task.isCancelled else { return }
        onFinish()
    }
}
