import SwiftUI
import SwiftData
import UIKit

/// 第 4 Tab：DeepSeek 峰谷状态 + API 余额 + 消耗热力。
///
/// 卡片 1「峰谷时段」：官方定价规则纯本地时钟判定（`TariffClock`），
/// TimelineView 每秒刷新倒计时与 24 小时进度条，零 API 调用。
/// 卡片 2「API 余额」：官方 user/balance 接口，Key 在设置页配置（Keychain），
/// 进入页面自动查询，右上角手动刷新带加载态与轻震动；每次成功采样即差值落库。
/// 卡片 3「消耗」：余额差值累计 + Canvas 热力图（笔记 07 §6 公式）。
struct DeepSeekMonitorView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \DeepSeekDay.dateKey, order: .reverse) private var deepseekDays: [DeepSeekDay]
    @Query private var deepseekStates: [DeepSeekState]

    @State private var balance: DeepSeekService.BalanceInfo?
    @State private var balanceError: DeepSeekService.DeepSeekError?
    @State private var isLoading = false
    @State private var lastCheck: Date?
    @State private var isSettingsPresented = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                tariffCard
                balanceCard
                costCard
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
        }
        .background(Theme.bg)
        .task {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepseekDataUpdated)) { _ in
            // 后台轮询记到消耗了，余额展示跟上（记录无消耗时不广播，不会循环）
            Task { await refresh() }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .onChange(of: isSettingsPresented) { _, presented in
            // 设置页存完 Key 回来立即生效
            if !presented {
                Task { await refresh() }
            }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Text("DeepSeek")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 0)
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("设置")
        }
        .padding(.top, 2)
    }

    // MARK: 卡片 1 · 峰谷时段

    private var tariffCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("峰谷时段").cardLabel()
                Spacer()
                Link(destination: TariffRules.pricingURL) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .accessibilityLabel("官方定价页")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let moment = TariffClock.moment(now: context.date)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TariffBadge(period: moment.period)
                        if moment.isWeekend {
                            chip("周末全谷")
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(countdownText(moment))
                            .font(.system(size: 26, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("后切换至\(moment.nextPeriod.label)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    TariffDayBar(isWeekend: moment.isWeekend, nowFraction: TariffClock.dayFraction(now: context.date))

                    Text("北京时间 \(TariffClock.clockText(now: context.date)) · 峰价 = 谷价 × 2")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private struct TariffBadge: View {
        let period: TariffPeriod

        var body: some View {
            Text(period.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(period.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(period.bg))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.surfaceRaised))
    }

    /// 24 小时进度条：谷价打底，峰顶段染琥珀色，圆点标记当前时刻
    private struct TariffDayBar: View {
        let isWeekend: Bool
        let nowFraction: Double

        var body: some View {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.text.opacity(0.08))
                    if !isWeekend {
                        peakSpan(9, 12, width: width)
                        peakSpan(14, 18, width: width)
                    }
                    Circle()
                        .fill(Theme.text)
                        .frame(width: 5, height: 5)
                        .offset(x: width * nowFraction - 2.5)
                }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
        }

        private func peakSpan(_ start: Double, _ end: Double, width: CGFloat) -> some View {
            Capsule()
                .fill(TariffPeriod.peak.fg.opacity(0.45))
                .frame(width: width * (end - start) / 24)
                .offset(x: width * start / 24)
        }
    }

    private func countdownText(_ moment: TariffMoment) -> String {
        let seconds = max(0, Int(moment.secondsUntilSwitch.rounded()))
        let days = seconds / 86400
        let hours = seconds % 86400 / 3600
        let minutes = seconds % 3600 / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分"
    }

    // MARK: 卡片 2 · API 余额

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API 余额").cardLabel()
                Spacer()
                refreshButton
            }

            if let balance {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(balance.currencySymbol)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Text(balance.totalText)
                            .font(.system(size: 44, weight: .light))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
                    Text("充值 \(balance.currencySymbol)\(balance.toppedUpText) · 赠送 \(balance.currencySymbol)\(balance.grantedText)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if balanceError == nil && !isLoading {
                Text("—")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let balanceError {
                errorBody(balanceError)
            } else if !isLoading && balance == nil {
                Text("还没查到余额")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let lastCheck {
                Text("上次刷新 " + timeText(lastCheck))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var refreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await refresh() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(Theme.text)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Theme.surfaceRaised))
        }
        .buttonStyle(PressableStyle())
        .disabled(isLoading)
        .accessibilityLabel("刷新余额")
    }

    /// 温和错误态：不闪退、不红屏，Key 问题引导去设置页
    @ViewBuilder
    private func errorBody(_ error: DeepSeekService.DeepSeekError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(error.localizedDescription)
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .foregroundStyle(Theme.textSecondary)

            if error.needsKeyFix {
                Button {
                    isSettingsPresented = true
                } label: {
                    Text("去设置页配置")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.text))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: 卡片 3 · 消耗热力

    private var costCard: some View {
        let digest = DeepSeekDigest.build(days: deepseekDays, lastCheck: deepseekStates.first?.lastCheck)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("消耗").cardLabel()
                Spacer()
                Text("记录 \(deepseekDays.count) 天")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("今日")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                Text("¥\(costText(digest.todayCost))")
                    .font(.system(size: 26, weight: .light))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("累计 ¥\(costText(digest.totalCost))")
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }

            CostHeatmapView(costs: digest.costs, thresholds: digest.thresholds, anchor: digest.anchor)
                .frame(height: 110)

            legend
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// 图例「少 ■■■■■ 多」，复用热力图同一组透明度（笔记 07 §6-3）
    private var legend: some View {
        HStack(spacing: 4) {
            Text("少")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 9, height: 9)
            ForEach(1..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                    .fill(Theme.costHeat.opacity(CostHeatmapView.alphas[level]))
                    .frame(width: 9, height: 9)
            }
            Text("多")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
            Text("阈值按近 210 天 p40/p75/p99")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func costText(_ cost: Double) -> String {
        String(format: "%.2f", cost)
    }

    /// 消耗热力图：桌面组件原版几何公式移植（笔记 07 §6）。
    /// 列优先 7 行 × N 列，最近一天固定右下角并描边；accent × 五档透明度，空格 secondary@0.35。
    private struct CostHeatmapView: View {
        let costs: [String: Double]
        let thresholds: [Double]
        let anchor: Date

        static let alphas: [CGFloat] = [0.35, 0.55, 0.75, 0.90, 1.0]

        var body: some View {
            Canvas { ctx, size in
                let pad = min(size.width, size.height) * 0.05
                let gap = pad * 0.5
                let inner = size.width - pad * 2
                let gridH = size.height - pad * 2
                guard gridH > 0, inner > 0 else { return }
                let cell = (gridH - 6 * gap) / 7
                guard cell > 0 else { return }
                var cols = Int((inner + gap) / (cell + gap))
                cols = min(max(cols, 1), 30)
                let step = cell + gap
                let x0 = pad + (inner - CGFloat(cols) * step + gap) / 2
                let accent = Theme.costHeat
                let ghost = Color.secondary.opacity(0.35)
                let formatter = DateFormatter() // 循环外建一次
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                let calendar = Calendar.current

                for c in 0..<cols {
                    for r in 0..<7 {
                        let back = (cols - 1 - c) * 7 + (6 - r)
                        guard let date = calendar.date(byAdding: .day, value: -back, to: anchor) else { continue }
                        let key = formatter.string(from: date)
                        let cost = costs[key] ?? 0
                        let level = Self.level(cost, thresholds)
                        let rect = CGRect(
                            x: x0 + CGFloat(c) * step,
                            y: CGFloat(r) * step,
                            width: cell,
                            height: cell
                        )
                        let path = Path(roundedRect: rect, cornerRadius: cell * 0.28)
                        if level == 0 {
                            ctx.fill(path, with: .color(ghost))
                        } else {
                            ctx.fill(path, with: .color(accent.opacity(Self.alphas[level])))
                        }
                        if back == 0 {
                            ctx.stroke(path, with: .color(Theme.text), lineWidth: max(1, cell * 0.07))
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }

        static func level(_ cost: Double, _ thresholds: [Double]) -> Int {
            if cost <= 0 { return 0 }
            if cost <= thresholds[0] { return 1 }
            if cost <= thresholds[1] { return 2 }
            if cost <= thresholds[2] { return 3 }
            return 4
        }
    }

    // MARK: 数据

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await DeepSeekService.shared.fetchBalance()
            balance = info
            balanceError = nil
            lastCheck = Date()
            // 每次成功采样都落库：差值累计今天消耗（余额没降时只更新锚点）
            DeepSeekStore.record(info, in: context)
        } catch let error as DeepSeekService.DeepSeekError {
            balanceError = error
        } catch {
            balanceError = .network(error.localizedDescription)
        }
        if let balanceError {
            AppLog.info("DeepSeek 余额刷新失败：\(balanceError.localizedDescription)")
        } else {
            AppLog.info("DeepSeek 余额刷新成功")
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension DeepSeekService.DeepSeekError {
    /// Key 缺失 / 失效时引导去设置页
    var needsKeyFix: Bool {
        if case .keyMissing = self { return true }
        if case .unauthorized = self { return true }
        return false
    }
}
