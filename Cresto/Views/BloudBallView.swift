import SwiftUI
import UIKit

// MARK: - BLOUD 表情

/// BLOUD 的 7 种经典眼睛几何。
/// 仅由「两只纯白实心几何眼睛」构成：通过形状、旋转角与整体偏离圆心的偏移量，
/// 制造 3D 球面转头错觉（不画嘴巴 / 腮红 / 渐变 / 杂色）。
enum BloudExpression: Int, CaseIterable, Identifiable {
    case idle = 0      // 发呆 / 向左看（默认）
    case calm          // 平静（右上角）
    case focus         // 专注
    case surprise      // 惊讶
    case excited       // 兴奋
    case happy         // 开心
    case laugh         // 大笑 / 调皮

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .idle: return "发呆"
        case .calm: return "平静"
        case .focus: return "专注"
        case .surprise: return "惊讶"
        case .excited: return "兴奋"
        case .happy: return "开心"
        case .laugh: return "大笑"
        }
    }

    /// 眼睛基础尺寸（pt，按 52pt 球体标定）
    var eyeSize: CGSize {
        switch self {
        case .idle: return CGSize(width: 7, height: 3.5)
        case .calm: return CGSize(width: 4, height: 7.5)
        case .focus: return CGSize(width: 4.5, height: 9.5)
        case .surprise: return CGSize(width: 8, height: 8)
        case .excited: return CGSize(width: 6.5, height: 10)
        case .happy: return CGSize(width: 5.5, height: 3.2)
        case .laugh: return CGSize(width: 7, height: 3)
        }
    }

    /// 双眼间距
    var spacing: CGFloat {
        switch self {
        case .idle: return 7
        case .calm: return 6
        case .focus: return 6
        case .surprise: return 8
        case .excited: return 8
        case .happy: return 6
        case .laugh: return 7
        }
    }

    /// 整组眼睛相对球心的偏移（球面转头错觉）
    var groupOffset: CGSize {
        switch self {
        case .idle: return CGSize(width: -8, height: 0)
        case .calm: return CGSize(width: 9, height: -9)
        case .focus: return CGSize(width: 2, height: 0)
        case .surprise: return .zero
        case .excited: return CGSize(width: 3, height: 6)
        case .happy: return CGSize(width: 0, height: -6)
        case .laugh: return CGSize(width: 0, height: -6)
        }
    }

    /// 左眼横向缩放（发呆时左侧微缩模拟球面透视）
    var leftScale: CGFloat {
        self == .idle ? 0.85 : 1
    }

    /// 右眼横向缩放（平静时右上外侧压窄）
    var rightScale: CGFloat {
        self == .calm ? 0.88 : 1
    }

    var leftRotation: Double {
        switch self {
        case .excited: return -6
        case .laugh: return 14
        default: return 0
        }
    }

    var rightRotation: Double {
        switch self {
        case .calm: return 10      // 外上侧顺时针微倾
        case .excited: return 6
        case .laugh: return -14
        default: return 0
        }
    }
}

// MARK: - 纯渲染层（球体 + 眼睛）

/// 哑光深炭黑圆球 + 两只纯白实心几何眼睛。无嘴巴 / 腮红 / 渐变。
struct BloudFaceView: View {
    let expression: BloudExpression
    var eyeBlink: CGFloat = 1
    var gaze: CGSize = .zero
    var size: CGFloat = 52

    var body: some View {
        let s = size / 52
        let perspective = min(0.18, abs(gaze.width) * 0.03)
        let lookingLeft = gaze.width < 0
        let leftWidthScale = expression.leftScale * (lookingLeft ? 1 : 1 - perspective)
        let rightWidthScale = expression.rightScale * (lookingLeft ? 1 - perspective : 1)

        ZStack {
            Circle()
                .fill(Color(hex: 0x18181A))

            HStack(spacing: expression.spacing * s) {
                eye(
                    width: expression.eyeSize.width * leftWidthScale * s,
                    height: expression.eyeSize.height * eyeBlink * s,
                    rotation: expression.leftRotation
                )
                eye(
                    width: expression.eyeSize.width * rightWidthScale * s,
                    height: expression.eyeSize.height * eyeBlink * s,
                    rotation: expression.rightRotation
                )
            }
            .offset(
                x: (expression.groupOffset.width + gaze.width * 0.35) * s,
                y: (expression.groupOffset.height + gaze.height * 0.3) * s
            )
        }
        .frame(width: size, height: size)
    }

    private func eye(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: max(1.5, width), height: max(1.2, height))
            .rotationEffect(.degrees(rotation))
    }
}

// MARK: - 交互相

/// 首页右下角 BLOUD 小黑球（52pt，与课表/待办 FAB 同锚点）。
/// 轻点：轻震 + 果冻压感 + 下一个表情；长按：表情面板（持久化）；
/// 拖动：球体弹性轻移（≤ ±10pt），眼睛实时朝拖拽方向偏移并带球面透视压窄。
struct BloudBallView: View {
    @AppStorage("bloudExpression") private var faceRaw = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var blinkScale: CGFloat = 1
    @State private var gaze: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var squash = false
    @State private var isPanelPresented = false

    private var expression: BloudExpression {
        BloudExpression(rawValue: faceRaw) ?? .idle
    }

    var body: some View {
        BloudFaceView(expression: expression, eyeBlink: blinkScale, gaze: gaze)
            .scaleEffect(x: squash ? 1.08 : 1, y: squash ? 0.92 : 1)
            .offset(dragOffset)
            .shadow(color: Color.black.opacity(0.14), radius: 8, y: 4)
            .contentShape(Circle())
            .onTapGesture { cycle() }
            .onLongPressGesture(minimumDuration: 0.45) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isPanelPresented = true
            }
            .gesture(dragGesture)
            .task { await blinkLoop() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { blinkScale = 1 }
            }
            .sheet(isPresented: $isPanelPresented) {
                BloudExpressionPanel(selection: $faceRaw)
            }
    }

    // MARK: 轻点切表情 + 果冻

    private func cycle() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        jellySquash()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
            faceRaw = (faceRaw + 1) % BloudExpression.allCases.count
        }
    }

    private func jellySquash() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) {
            squash = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 110_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                squash = false
            }
        }
    }

    // MARK: 拖拽追随

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                dragOffset = CGSize(
                    width: clamp(value.translation.width * 0.35, limit: 10),
                    height: clamp(value.translation.height * 0.35, limit: 10)
                )
                gaze = CGSize(
                    width: clamp(value.translation.width * 0.6, limit: 7),
                    height: clamp(value.translation.height * 0.5, limit: 6)
                )
            }
            .onEnded { _ in
                isDragging = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
                    dragOffset = .zero
                    gaze = .zero
                }
            }
    }

    private func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        min(limit, max(-limit, value))
    }

    // MARK: 随机眨眼（2.8 ~ 5.5s）

    private func blinkLoop() async {
        guard !reduceMotion else { return }
        let intervals: [Double] = [3.1, 4.6, 2.9, 5.2, 3.7, 4.1, 5.4, 2.8]
        var step = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(intervals[step % intervals.count] * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.07)) { blinkScale = 0.12 }
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) { blinkScale = 1 }
            step += 1
        }
    }
}

// MARK: - 表情面板（长按唤起，3 列网格）

struct BloudExpressionPanel: View {
    @Binding var selection: Int
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("角色与表情")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Theme.surfaceRaised))
                }
                .buttonStyle(.plain)
            }

            Text("BLOUD")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(BloudExpression.allCases) { item in
                    let isSelected = selection == item.rawValue
                    VStack(spacing: 8) {
                        ZStack {
                            BloudFaceView(expression: item, size: 54)
                                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                            if isSelected {
                                Circle()
                                    .strokeBorder(Theme.text, lineWidth: 1.5)
                                    .frame(width: 62, height: 62)
                            }
                        }
                        .frame(width: 64, height: 64)

                        Text(item.title)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Theme.text : Theme.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) {
                            selection = item.rawValue
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }
}