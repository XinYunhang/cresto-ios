import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var tasks: [TaskItem]
    @Query private var courses: [Course]
    @Query private var usages: [DailyUsage]

    @AppStorage("appTheme") private var appTheme = "system"

    @State private var sizeText = "—"
    @State private var isBackupPresented = false

    @State private var apiKeyDraft = ""
    @State private var deepseekStatus: String?
    @State private var isTestingKey = false

    @AppStorage("deepseekPollSeconds") private var deepseekPollSeconds = 300

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    themeCard
                    deepseekCard
                    dataCard
                    backupCard
                    logCard
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
                        .foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.ink)
        }
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $isBackupPresented) {
            BackupView()
        }
        .onAppear {
            AppLog.info("打开设置页")
            sizeText = AppLog.fileSizeText
            if apiKeyDraft.isEmpty {
                apiKeyDraft = KeychainService.load() ?? ""
            }
        }
    }

    // MARK: 主题

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("外观").cardLabel()
            HStack(spacing: 6) {
                themeButton("跟随系统", value: "system")
                themeButton("深色", value: "dark")
                themeButton("浅色", value: "light")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func themeButton(_ title: String, value: String) -> some View {
        let isOn = appTheme == value
        return Button {
            appTheme = value
            AppLog.info("切换主题：\(value)")
        } label: {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(isOn ? Theme.text : Theme.surfaceRaised)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: DeepSeek

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
                Text("每段间隔采样一次余额，差值记进当天消耗")
                    .font(.system(size: 11))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.textTertiary)
            }

            Link(destination: TariffRules.pricingURL) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("官方定价 · 峰谷时段以此为准")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            }

            Text("Key 只存本机钥匙串，不进备份与日志；换机后重填一次。")
                .font(.system(size: 11))
                .lineSpacing(3)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func capsuleButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(filled ? Theme.bg : Theme.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(filled ? Theme.text : Theme.surfaceRaised))
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
                .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                        .fill(isOn ? Theme.text : Theme.surfaceRaised)
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
                // 测试连接也是一次真实采样，差值一并落库
                DeepSeekStore.record(info, in: modelContext)
                deepseekStatus = "✓ 连接正常 · 余额 \(info.currencySymbol)\(info.totalText)"
            } catch {
                deepseekStatus = "✗ \(error.localizedDescription)"
            }
        }
    }

    // MARK: 数据

    private var dataCard: some View {
        VStack(spacing: 0) {
            row("待办", "\(tasks.count) 条")
            divider
            row("课程", "\(courses.count) 门")
            divider
            row("使用记录", "\(usages.count) 天")
        }
        .cardSurface(padding: 0)
    }

    // MARK: 备份

    private var backupCard: some View {
        Button {
            isBackupPresented = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("备份与回退")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.text)
                    Text("每天自动存一份，可随时恢复")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface()
    }

    // MARK: 日志

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("日志").cardLabel()
                Spacer()
                Text(sizeText)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 12)

            Text("记录启动、切页、增删待办、课表导入这些动作，出问题时导出给我看就行。超过 512KB 会自动清空重来。")
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 14)

            ShareLink(item: AppLog.fileURL) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                    Text("导出日志")
                    Spacer()
                    Text("cresto.log")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
            }

            Button {
                AppLog.clear()
                AppLog.info("日志已清空")
                sizeText = AppLog.fileSizeText
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash").font(.system(size: 13))
                    Text("清空日志")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .cardSurface()
    }

    // MARK: 关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("关于").cardLabel()
                Spacer()
                Text(versionText)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("Cresto iOS · 个人自用版本，不对外分发。")
                .font(.system(size: 11.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
    }
}
