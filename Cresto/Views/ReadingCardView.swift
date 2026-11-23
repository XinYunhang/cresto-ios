import SwiftUI
import SwiftData
import UIKit

/// 「待办」页底部的阅读卡片（对照设计图）：
/// · 顶部：阅读 + 默认「近 30 天」；点选格子后右侧实时显示「M月d日 · N分钟 / 无阅读」，再点取消
/// · 30 天热力图：7 列 × 4 满行 + 第 5 行 2 格；5 档（浅灰 + 翠绿四阶）；点格轻震 + 深色描边
/// · 正在读：默认折叠一行（书名缩略 + 箭头），展开只展 1 本：直角封面 + 书名/作者/进度% + 动画进度条
/// · 加载：无缓存时显示等尺寸骨架屏 + 斜向扫光，数据回来平滑过渡；弱网/超时回退本地缓存，不卡 loading
struct ReadingCardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeReadDay.dateKey) private var cachedDays: [WeReadDay]
    @Query private var books: [WeReadBook]

    @State private var phase: Phase = .skeleton
    @State private var selectedKey: String?
    @State private var isBookExpanded = false
    @State private var barValue: Double = 0
    @State private var isRefreshing = false
    /// 节流：10 分钟内不重复同步（切回 Tab 不再触发完整加载）
    @State private var lastRefreshAt: Date?

    @Environment(\.scenePhase) private var scenePhase

    private enum Phase { case skeleton, content }

    private var book: WeReadBook? { books.first }
    private var digest: WeReadDigest { WeReadDigest.build(cached: cachedDays) }

    var body: some View {
        Group {
            switch phase {
            case .skeleton:
                skeletonBody
                    .transition(.opacity)
            case .content:
                contentBody
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 13)
        .animation(.easeInOut(duration: 0.3), value: phase)
        .onAppear {
            if !cachedDays.isEmpty || book != nil { phase = .content }
            Task { await refreshIfStale() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await refreshIfStale() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wereadDataUpdated)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) { phase = .content }
        }
    }

    // MARK: - 内容态

    private var contentBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            heatmap
            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 0.5)
                .padding(.top, 2)
            bookSection
        }
    }

    private var header: some View {
        let trailing = headerTrailing
        return HStack(spacing: 8) {
            Text("阅读")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            Text(trailing.text)
                .font(.system(size: 12, weight: trailing.emphasized ? .medium : .regular))
                .foregroundStyle(trailing.color)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var headerTrailing: (text: String, color: Color, emphasized: Bool) {
        if let key = selectedKey, let day = digest.days.first(where: { $0.id == key }) {
            let label = Self.monthDayLabel(day.date)
            if day.minutes > 0 {
                return ("\(label) · \(day.minutes)分钟", WeReadHeat.green, true)
            }
            return ("\(label) · 无阅读", Theme.textTertiary, false)
        }
        return ("近 30 天", Theme.textTertiary, false)
    }

    private var heatmap: some View {
        // 紧凑化：7 列不变、间距略收、格子由正方形改为扁比例（降低总高度，保持单手点按面积）
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
            ForEach(digest.days) { day in
                heatCell(day)
            }
        }
    }

    private func heatCell(_ day: WeReadDigest.Day) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
            .fill(WeReadHeat.color(level: day.level))
            .aspectRatio(1.22, contentMode: .fit)
            .overlay {
                if selectedKey == day.id {
                    RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                        .strokeBorder(Theme.text, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.2)) {
                    selectedKey = (selectedKey == day.id) ? nil : day.id
                }
            }
            .accessibilityLabel("\(Self.monthDayLabel(day.date))，\(day.minutes > 0 ? "\(day.minutes)分钟" : "无阅读")")
    }

    // MARK: - 正在读

    private var bookSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    isBookExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("正在读")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if !isBookExpanded {
                        Text(book?.title ?? "暂无在读")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isBookExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isBookExpanded {
                if let book {
                    bookDetail(book)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Text("暂无在读数据")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: isBookExpanded) { _, expanded in
            if expanded {
                // 展开时进度条从 0 平滑填充到当前进度
                barValue = 0
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.05)) {
                    barValue = min(1, max(0, book?.progress ?? 0))
                }
            } else {
                barValue = 0
            }
        }
    }

    private func bookDetail(_ book: WeReadBook) -> some View {
        HStack(alignment: .top, spacing: 12) {
            bookCover(book)

            VStack(alignment: .leading, spacing: 7) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(book.author)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(book.progressPercent)%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WeReadHeat.green)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceRaised)
                        Capsule()
                            .fill(WeReadHeat.green)
                            .frame(width: max(0, geo.size.width * barValue))
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 封面：严格 90° 直角（不裁圆角），极细低透明度描边
    private func bookCover(_ book: WeReadBook) -> some View {
        Group {
            if let url = URL(string: book.coverURL), !book.coverURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        coverPlaceholder
                    }
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 64, height: 94)
        .clipped()
        .overlay(Rectangle().strokeBorder(Theme.stroke, lineWidth: 0.5))
    }

    private var coverPlaceholder: some View {
        ZStack {
            Theme.surfaceRaised
            Image(systemName: "book.closed")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - 骨架屏（等尺寸轮廓 + 斜向扫光）

    private var skeletonBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("阅读")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Capsule()
                    .fill(Theme.surfaceRaised)
                    .frame(width: 64, height: 14)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 7) {
                ForEach(0..<30, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppRadius.grid, style: .continuous)
                        .fill(Theme.surfaceRaised)
                        .aspectRatio(1.22, contentMode: .fit)
                }
            }

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 0.5)

            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                .fill(Theme.surfaceRaised)
                .frame(width: 90, height: 16)
        }
        .overlay(ShimmerOverlay())
    }

    // MARK: - 数据

    /// 节流刷新：首次进入、回前台、切回 Tab 时，10 分钟内不重复请求（杜绝每次切页完整加载）
    private func refreshIfStale() async {
        if let last = lastRefreshAt, Date().timeIntervalSince(last) < 600 { return }
        await refresh()
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastRefreshAt = Date()
        defer { isRefreshing = false }
        do {
            let snapshot = try await WeReadService.shared.fetch()
            WeReadStore.apply(snapshot, in: context)
            withAnimation(.easeInOut(duration: 0.3)) { phase = .content }
        } catch {
            // 未配置 / 弱网 / 超时：回退本地缓存；无缓存也退出骨架屏（灰格 + 暂无在读），不卡 loading
            withAnimation(.easeInOut(duration: 0.3)) { phase = .content }
        }
    }

    private static func monthDayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日"
    }
}

// MARK: - 斜向扫光

private struct ShimmerOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var travel: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.55), Color.white.opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.55)
            .rotationEffect(.degrees(18))
            .offset(x: travel * geo.size.width * 1.7)
            .allowsHitTesting(false)
        }
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                travel = 1
            }
        }
    }
}