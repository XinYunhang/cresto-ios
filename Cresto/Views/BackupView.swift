import SwiftUI
import SwiftData

/// 备份与回退：每天自动存快照，随时可以回到某个时间点，也能把 JSON 导出去。
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var snapshots: [SnapshotInfo] = []
    @State private var latest: URL?
    @State private var isRestoring = false
    @State private var message: String?
    @State private var confirmRestore: SnapshotInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    actionCard
                    listCard
                    noteCard
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("备份与回退")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.text)
        }
        .presentationBackground(Theme.bg)
        .onAppear(perform: reload)
        .alert(
            "恢复到「\(confirmRestore.map { dateText($0.date) } ?? "")」？",
            isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            )
        ) {
            Button("恢复", role: .destructive) { performRestore() }
            Button("取消", role: .cancel) { confirmRestore = nil }
        } message: {
            Text("当前所有数据会被这份快照完全替换，无法撤销。恢复前建议先手动备份一次。")
        }
    }

    // MARK: 操作

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("现在").cardLabel()
                Spacer()
                if let message {
                    Text(message)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Button {
                createSnapshot()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.aperture").font(.system(size: 13))
                    Text("立即创建快照")
                    Spacer()
                }
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surfaceRaised)
                )
            }
            .buttonStyle(.plain)

            if let latest {
                ShareLink(item: latest) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                        Text("导出备份文件")
                        Spacer()
                        Text(latest.lastPathComponent)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surfaceRaised)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("历史快照").cardLabel()
                Spacer()
                Text("\(snapshots.count) 份")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 8)

            if snapshots.isEmpty {
                Text("还没有快照")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(snapshots) { snapshot in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dateText(snapshot.date))
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Text("\(snapshot.itemCount) 条 · \(sizeText(snapshot.bytes))")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Button("恢复") {
                            confirmRestore = snapshot
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.surfaceRaised))
                    }
                    .padding(.vertical, 9)

                    if snapshot.id != snapshots.last?.id {
                        Rectangle().fill(Theme.stroke).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("规则").cardLabel()
            Text("每天第一次打开 App 自动存一份，最多保留 10 份，超出后删最旧的。\n恢复是整体替换：先解码校验，校验不过不会动现有数据。")
                .font(.system(size: 11.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 动作

    private func reload() {
        snapshots = BackupService.snapshots()
        latest = snapshots.first?.url
    }

    private func createSnapshot() {
        if let url = BackupService.makeSnapshot(in: context) {
            message = "已创建"
            reload()
            latest = url
        } else {
            message = "创建失败"
        }
    }

    private func performRestore() {
        guard let target = confirmRestore else { return }
        confirmRestore = nil
        isRestoring = true
        do {
            try BackupService.restore(from: target.url, in: context)
            message = "已恢复"
        } catch {
            message = "恢复失败"
            AppLog.error("恢复失败：\(error.localizedDescription)")
        }
        isRestoring = false
        reload()
    }

    // MARK: 格式化

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func sizeText(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024
        return kb < 1024 ? String(format: "%.0f KB", kb) : String(format: "%.1f MB", kb / 1024)
    }
}
