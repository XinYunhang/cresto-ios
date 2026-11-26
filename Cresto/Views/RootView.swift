import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appTheme") private var appTheme = "system"

    @State private var tab: AppTab = .overview
    /// 已挂载过的页面（保活：切 Tab 只切换显隐与命中，不销毁重建）
    @State private var mountedTabs: Set<AppTab> = [.overview]
    @State private var isQuickAddPresented = false
    @State private var isSettingsPresented = false
    @State private var activeSince: Date?
    @State private var lastDeepSeekPoll: Date?

    @AppStorage("deepseekPollSeconds") private var deepseekPollSeconds = 300

    @State private var ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// 订阅续费提醒扫描（启动 / 回前台；保存订阅后由编辑页自行触发）
    private func syncSubscriptions() {
        let subs = (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
        SubscriptionReminderService.sync(subs, in: context)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            // 保活容器：页面首次访问时懒加载，之后只切换显隐/命中（避免切 Tab 销毁重建复杂列表与网格）
            ZStack {
                if isMounted(.overview) {
                    OverviewView(
                        onOpenTasks: { tab = .tasks },
                        onOpenCourse: { tab = .course },
                        onOpenSubscriptions: { tab = .ledger },
                        onAddTask: { isQuickAddPresented = true },
                        onOpenSettings: { isSettingsPresented = true }
                    )
                    .tabPageVisible(tab == .overview)
                }

                if isMounted(.tasks) {
                    TasksView(onAdd: { isQuickAddPresented = true })
                        .tabPageVisible(tab == .tasks)
                }

                if isMounted(.course) {
                    TimetableView()
                        .tabPageVisible(tab == .course)
                }

                if isMounted(.ledger) {
                    SubscriptionMainView()
                        .tabPageVisible(tab == .ledger)
                }

                if FeatureFlags.enableDeepSeek, isMounted(.api) {
                    DeepSeekMonitorView()
                        .tabPageVisible(tab == .api)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底边渐隐：内容与悬浮底栏之间 40pt 柔和过渡（非交互，深浅主题自适应）
            VStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    colors: [Theme.bg.opacity(0), Theme.bg],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            GlassTabBar(selection: $tab)
        }
        .preferredColorScheme(colorScheme)
        .onChange(of: tab) { _, newTab in
            mountedTabs.insert(newTab)
        }
        .onAppear {
            if activeSince == nil { activeSince = Date() }
            AppLog.info("App 启动 · 主题 \(appTheme)")
            syncSubscriptions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                activeSince = Date()
                syncSubscriptions()
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

    /// 首次访问的 Tab 当帧即可渲染（`tab == page` 兜底），onChange 再纳入保活集合
    private func isMounted(_ page: AppTab) -> Bool {
        mountedTabs.contains(page) || tab == page
    }
}

// MARK: - 保活页显隐

private extension View {
    /// 保活页的显隐切换：只影响透明度与命中，不参与布局重建
    func tabPageVisible(_ isVisible: Bool) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
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
            WeReadDay.self, WeReadBook.self, Subscription.self,
            configurations: config
        )
        SeedData.seedIfNeeded(container.mainContext)
        return container
    }()
}
