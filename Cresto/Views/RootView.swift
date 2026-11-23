import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appTheme") private var appTheme = "system"

    @State private var tab: AppTab = .overview
    @State private var isQuickAddPresented = false
    @State private var isSettingsPresented = false
    @State private var activeSince: Date?
    @State private var lastDeepSeekPoll: Date?

    @AppStorage("deepseekPollSeconds") private var deepseekPollSeconds = 300

    @State private var ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            if activeSince == nil { activeSince = Date() }
            AppLog.info("App 启动 · 主题 \(appTheme)")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activeSince = Date()
            } else {
                pauseUsage()
            }
        }
        .onReceive(ticker) { _ in
            guard scenePhase == .active else { return }
            accrueUsage()
            pollDeepSeekIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dataRestored)) { _ in
            // 恢复后旧的提醒都失效了，按新数据重排一遍
            let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
            NotificationScheduler.syncAll(tasks)
            AppLog.info("数据已恢复：重排 \(tasks.count) 条提醒")
        }
        .sheet(isPresented: $isQuickAddPresented) {
            QuickAddSheet()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    // MARK: 使用时长

    private func accrueUsage() {
        guard let start = activeSince else {
            activeSince = Date()
            return
        }
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds > 0 {
            UsageStore.add(seconds: seconds, in: context)
        }
        activeSince = Date()
    }

    private func pauseUsage() {
        guard let start = activeSince else { return }
        let seconds = Int(Date().timeIntervalSince(start))
        if seconds > 0 {
            UsageStore.add(seconds: seconds, in: context)
        }
        activeSince = nil
    }

    // MARK: DeepSeek 轮询

    /// 前台按设置项间隔采样余额（60–300s，默认 5 分钟），差值落库（笔记 07 §3）。
    /// 借用 60s 心跳做节流，间隔改了立即生效，不用重建 Timer。
    private func pollDeepSeekIfNeeded() {
        // 开关关闭时停止自动轮询（服务与数据完整保留，切回 true 即恢复）
        guard FeatureFlags.enableDeepSeek else { return }
        guard KeychainService.load()?.isEmpty == false else { return }
        let interval = TimeInterval(max(60, min(300, deepseekPollSeconds)))
        if let last = lastDeepSeekPoll, Date().timeIntervalSince(last) < interval { return }
        lastDeepSeekPoll = Date()
        Task {
            do {
                let info = try await DeepSeekService.shared.fetchBalance()
                DeepSeekStore.record(info, in: context)
                AppLog.info("DeepSeek 轮询采样成功")
            } catch {
                AppLog.info("DeepSeek 轮询失败：\(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            OverviewView(
                onOpenTasks: { tab = .tasks },
                onAddTask: { isQuickAddPresented = true },
                onOpenSettings: { isSettingsPresented = true }
            )
        case .tasks:
            TasksView(onAdd: { isQuickAddPresented = true })
        case .course:
            TimetableView()
        case .ledger:
            LedgerView()
        case .api:
            // DeepSeek 页仅在 FeatureFlags.enableDeepSeek = true 时出现在底栏；保留视图以便无损恢复
            DeepSeekMonitorView()
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container)
}

/// SwiftUI 预览用的内存容器
@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: TaskItem.self, Subtask.self, Course.self, CourseSlot.self,
            TimetableSettings.self, DailyUsage.self, DeepSeekDay.self, DeepSeekState.self,
            WeReadDay.self, WeReadBook.self,
            configurations: config
        )
        SeedData.seedIfNeeded(container.mainContext)
        return container
    }()
}
