import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Query private var tasks: [TaskItem]
    @Query private var courses: [Course]
    @Query private var usages: [DailyUsage]

    @State private var sizeText = "—"

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    dataCard
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
        .onAppear {
            AppLog.info("打开设置页")
            sizeText = AppLog.fileSizeText
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

            Text("记录启动、切页、增删待办、抽牌、课表导入这些动作，出问题时导出给我看就行。超过 512KB 会自动清空重来。")
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
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            Text("Cresto iOS · 个人自用版本。塔罗卡面来自非商业授权素材，仅供自己安装使用，不对外分发。")
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
