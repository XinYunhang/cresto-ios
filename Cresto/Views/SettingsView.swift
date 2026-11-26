import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query private var courses: [Course]
    @Query private var usages: [DailyUsage]
    @Query private var subscriptions: [Subscription]
    @Query private var countdowns: [CountdownItem]

    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("jpyToCny") private var jpyToCny = 0.048

    @State private var sizeText = "—"
    @State private var isBackupPresented = false

    @State private var apiKeyDraft = ""
    @State private var deepseekStatus: String?
    @State private var isTestingKey = false
    @AppStorage("deepseekPollSeconds") private var deepseekPollSeconds = 300

    // 微信读书同步
    @AppStorage("wereadEndpoint") private var wereadEndpoint = ""
    @State private var wereadKeyDraft = ""
    @State private var wereadStatus: String?
    @State private var isTestingWeread = false

    // 参考汇率编辑
    @State private var editingRate: RateKind?
    @State private var rateDraft = ""

    // 个性化 / 票根预留提示
    @State private var reservedFeatureTitle: String?

    private enum RateKind {
        case usd, jpy
    }

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Theme.cardGap) {
                    themeCard
                    personalizationReservedCard
                    dataGridCard
                    exchangeRateCard
                    if FeatureFlags.enableDeepSeek {
                        deepseekCard
                    }
                    wereadCard
                    backupAndLogCard
                    aboutCard
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.brand)
                        .fontWeight(.medium)
                }
            }
            .tint(Theme.brand)
        }
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $isBackupPresented) {
            BackupView()
        }
        .alert(editingRate == .jpy ? "100 JPY → CNY 参考汇率" : "1 USD → CNY 参考汇率", isPresented: Binding(
            get: { editingRate != nil },
            set: { if !$0 { editingRate = nil } }
        )) {
            TextField(editingRate == .jpy ? "4.80" : "7.25", text: $rateDraft)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let value = Double(rateDraft.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    if editingRate == .usd {
                        usdToCny = value
                    } else if editingRate == .jpy {
                        jpyToCny = value / 100.0
                    }
                }
                editingRate = nil
            }
            Button("取消", role: .cancel) { editingRate = nil }
        } message: {
            Text(editingRate == .jpy
                 ? "当前 100 JPY = \(String(format: "%.2f", jpyToCny * 100)) CNY"
                 : "当前 1 USD = \(String(format: "%.2f", usdToCny)) CNY")
        }
        .alert(reservedFeatureTitle ?? "", isPresented: Binding(
            get: { reservedFeatureTitle != nil },
            set: { if !$0 { reservedFeatureTitle = nil } }
        )) {
            Button("知道了", role: .cancel) { reservedFeatureTitle = nil }
        } message: {
            Text("入口已预留，将在后续个性化更新中开放节日主题与旅行票根式纪念馆。")
        }
        .onAppear {
            AppLog.info("打开设置页")
            sizeText = AppLog.fileSizeText
            if apiKeyDraft.isEmpty {
                apiKeyDraft = KeychainService.load() ?? ""
            }
            if wereadKeyDraft.isEmpty {
                wereadKeyDraft = KeychainService.load(
                    service: KeychainService.wereadService,
                    account: KeychainService.wereadAccount
                ) ?? LocalProfile.wereadAPIKey ?? ""
            }
        }
    }

    // MARK: 外观（可视化三缩略卡片 + 丝滑窗口溶解）

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("外观").cardLabel()
                Spacer()
                Text("丝滑切换")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(spacing: 10) {
                themePreviewTile("跟随系统", value: "system", style: .auto)
                themePreviewTile("浅色", value: "light", style: .light)
                themePreviewTile("深色", value: "dark", style: .dark)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private enum PreviewStyle { case auto, light, dark }

    private func themePreviewTile(_ title: String, value: String, style: PreviewStyle) -> some View {
        let isOn = appTheme == value
        return Button {
            guard appTheme != value else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            appTheme = value
            ThemeTransition.apply(value, animated: true)
            AppLog.info("切换主题：\(value)")
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    switch style {
                    case .light:
                        miniPhoneMockup(bg: Color(hex: 0xF2F3F7), card: Color.white, accent: Color(hex: 0x3B5BDB))
                    case .dark:
                        miniPhoneMockup(bg: Color(hex: 0x0E1015), card: Color(hex: 0x171A22), accent: Color(hex: 0x6B8AFF))
                    case .auto:
                        HStack(spacing: 0) {
                            miniPhoneMockup(bg: Color(hex: 0xF2F3F7), card: Color.white, accent: Color(hex: 0x3B5BDB))
                                .frame(maxWidth: .infinity)
                                .clipped()
                            miniPhoneMockup(bg: Color(hex: 0x0E1015), card: Color(hex: 0x171A22), accent: Color(hex: 0x6B8AFF))
                                .frame(maxWidth: .infinity)
                                .clipped()
                        }
                    }
                }
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .strokeBorder(isOn ? Theme.brand : Theme.stroke, lineWidth: isOn ? 2 : 0.6)
                )

                Text(title)
                    .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Theme.brand : Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func miniPhoneMockup(bg: Color, card: Color, accent: Color) -> some View {
        ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(accent)
                    .frame(width: 18, height: 4)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(card)
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(card)
                    .frame(height: 12)
            }
            .padding(7)
        }
    }

    // MARK: 个性化与纪念（预留节日主题 / 纪念票根收藏）

    private var personalizationReservedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("个性化与纪念").cardLabel()
                .padding(.bottom, 8)

            Button {
                reservedFeatureTitle = "节日主题"
            } label: {
                reservedRow(icon: .star, title: "节日主题", subtitle: "随节日与纪念日切换氛围视觉")
            }
            .buttonStyle(.plain)

            Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.leading, 43)

            Button {
                reservedFeatureTitle = "纪念票根"
            } label: {
                reservedRow(icon: .card, title: "纪念票根收藏", subtitle: "将节日与纪念物保存为旅行票根卡片")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func reservedRow(icon: Reicon, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            iconBadge(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("预留")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.surfaceRaised))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: 数据概览（2×2 紧凑格 + 圆体数字）

    private var dataGridCard: some View {
        let activeTasks = tasks.filter { $0.deletedAt == nil }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("数据概览").cardLabel()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                statTile("待办", value: "\(activeTasks)", unit: "条", icon: .checkCircle)
                statTile("课程", value: "\(courses.count)", unit: "门", icon: .calendarDays)
                statTile("订阅", value: "\(subscriptions.count)", unit: "项", icon: .card)
                statTile("倒数 / 使用", value: "\(countdowns.count)/\(usages.count)", unit: "项·天", icon: .clock)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func statTile(_ title: String, value: String, unit: String, icon: Reicon) -> some View {
        HStack(spacing: 10) {
            ReiconIcon(icon: icon, size: 15)
                .foregroundStyle(Theme.brand)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.brandSoft))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                .fill(Theme.surfaceRaised)
        )
    }

    // MARK: 参考汇率（订阅详情折算用）

    private var exchangeRateCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("参考汇率").cardLabel()
                .padding(.bottom, 10)

            Button {
                rateDraft = String(format: "%.2f", usdToCny)
                editingRate = .usd
            } label: {
                rateRow(label: "美元 (USD)", detail: "1 USD = \(String(format: "%.2f", usdToCny)) CNY")
            }
            .buttonStyle(.plain)

            Rectangle().fill(Theme.stroke).frame(height: 0.5)

            Button {
                rateDraft = String(format: "%.2f", jpyToCny * 100)
                editingRate = .jpy
            } label: {
                rateRow(label: "日元 (JPY)", detail: "100 JPY = \(String(format: "%.2f", jpyToCny * 100)) CNY")
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func rateRow(label: String, detail: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
            Spacer()
            Text(detail)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.brand)
            ReiconIcon(icon: .chevronRight, size: 12)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: 微信读书同步

    private var wereadCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("微信读书同步").cardLabel()

            TextField("https://i.weread.qq.com/api/agent/gateway", text: $wereadEndpoint)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )

            SecureField("wrk-...", text: $wereadKeyDraft)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )

            HStack(spacing: 8) {
                capsuleButton("保存", filled: true, action: saveWeread)
                capsuleButton(isTestingWeread ? "测试中…" : "测试连接", filled: false, action: testWeread)
            }

            if let wereadStatus {
                Text(wereadStatus)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Key 仅存本机钥匙串，不进仓库与日志；弱网自动回退本地缓存。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 备份与日志（合并紧凑卡片）

    private var backupAndLogCard: some View {
        VStack(spacing: 0) {
            Button {
                isBackupPresented = true
            } label: {
                HStack(spacing: 11) {
                    iconBadge(.refresh)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("备份与回退")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("每日自动快照，支持整体恢复")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    ReiconIcon(icon: .chevronRight, size: 13)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.leading, 43)

            ShareLink(item: AppLog.fileURL) {
                HStack(spacing: 11) {
                    iconBadge(.share)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("导出运行日志")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(Theme.text)
                        Text("cresto.log · \(sizeText)")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    ReiconIcon(icon: .chevronRight, size: 13)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }

            Rectangle().fill(Theme.stroke).frame(height: 0.5).padding(.leading, 43)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                AppLog.clear()
                AppLog.info("日志已清空")
                sizeText = AppLog.fileSizeText
            } label: {
                HStack(spacing: 11) {
                    iconBadge(.trash, tint: Theme.textTertiary, bg: Theme.surfaceRaised)
                    Text("清空日志")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cardSurface(padding: 15)
    }

    private func iconBadge(_ icon: Reicon, tint: Color = Theme.brand, bg: Color = Theme.brandSoft) -> some View {
        ReiconIcon(icon: icon, size: 15)
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bg))
    }

    // MARK: DeepSeek（仅 Flag 开启时展示）

    private var deepseekCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DeepSeek").cardLabel()

            SecureField("sk-...", text: $apiKeyDraft)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )

            HStack(spacing: 8) {
                capsuleButton("保存", filled: true, action: saveKey)
                capsuleButton("删除", filled: false, action: deleteKey)
                capsuleButton(isTestingKey ? "测试中…" : "测试连接", filled: false, action: testKey)
            }

            if let deepseekStatus {
                Text(deepseekStatus)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("前台轮询间隔")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    intervalButton("1 分", seconds: 60)
                    intervalButton("2 分", seconds: 120)
                    intervalButton("3 分", seconds: 180)
                    intervalButton("5 分", seconds: 300)
                }
            }

            Link(destination: TariffRules.pricingURL) {
                HStack(spacing: 6) {
                    ReiconIcon(icon: .arrowUpRight, size: 12)
                    Text("官方定价 · 峰谷时段以此为准")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 关于

    private var aboutCard: some View {
        HStack {
            Text("Cresto iOS · 个人自用版本")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(versionText)
                .font(.system(size: 11.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .cardSurface(padding: 14)
    }

    // MARK: 辅助控件与动作

    private func capsuleButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(filled ? Color.white : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(filled ? Theme.brand : Theme.surfaceRaised))
        }
        .buttonStyle(PressableStyle())
    }

    private func intervalButton(_ title: String, seconds: Int) -> some View {
        let isOn = deepseekPollSeconds == seconds
        return Button {
            deepseekPollSeconds = seconds
            AppLog.info("DeepSeek 轮询间隔：\(seconds)s")
        } label: {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(isOn ? Theme.brand : Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            deepseekStatus = "Key 不能为空"
            return
        }
        do {
            try KeychainService.save(trimmed)
            deepseekStatus = "已保存到钥匙串（仅本设备）"
            AppLog.info("DeepSeek Key 已保存")
        } catch {
            deepseekStatus = error.localizedDescription
        }
    }

    private func deleteKey() {
        KeychainService.delete()
        apiKeyDraft = ""
        deepseekStatus = "已删除"
        AppLog.info("DeepSeek Key 已删除")
    }

    private func testKey() {
        guard !isTestingKey else { return }
        isTestingKey = true
        deepseekStatus = nil
        Task {
            defer { isTestingKey = false }
            do {
                let info = try await DeepSeekService.shared.fetchBalance()
                DeepSeekStore.record(info, in: modelContext)
                deepseekStatus = "✓ 连接正常 · 余额 \(info.currencySymbol)\(info.totalText)"
            } catch {
                deepseekStatus = "✗ \(error.localizedDescription)"
            }
        }
    }

    private func saveWeread() {
        let endpoint = wereadEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = wereadKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        wereadEndpoint = endpoint
        if key.isEmpty {
            wereadStatus = "Key 不能为空（可先填 Key 再保存）"
            return
        }
        do {
            try KeychainService.save(
                key,
                service: KeychainService.wereadService,
                account: KeychainService.wereadAccount
            )
            wereadStatus = "已保存（接口地址 + 钥匙串 Key）"
            AppLog.info("微信读书同步配置已保存")
        } catch {
            wereadStatus = error.localizedDescription
        }
    }

    private func testWeread() {
        guard !isTestingWeread else { return }
        saveWeread()
        isTestingWeread = true
        wereadStatus = "正在同步…"
        Task {
            defer { isTestingWeread = false }
            do {
                let snapshot = try await WeReadService.shared.fetch()
                WeReadStore.apply(snapshot, in: modelContext)
                let bookText = snapshot.book.map { "在读《\($0.title)》" } ?? "无在读"
                wereadStatus = "✓ 同步成功 · \(snapshot.days.count) 天记录 · \(bookText)"
            } catch {
                wereadStatus = "✗ \(error.localizedDescription)"
            }
        }
    }
}
