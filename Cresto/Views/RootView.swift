import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appTheme") private var appTheme = "system"

    @State private var tab: AppTab = .overview
    /// iOS 17–25 保活集合
    @State private var mountedTabs: Set<AppTab> = [.overview]
    @State private var isQuickAddPresented = false
    @State private var isSettingsPresented = false
    @State private var showSplash = true
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
        ZStack {
            if #available(iOS 26.0, *) {
                nativeTabView
            } else {
                legacyTabContainer
            }

            if showSplash {
                SplashOverlayView {
                    showSplash = false
                }
                .zIndex(99)
            }
        }
        .onChange(of: tab) { _, newTab in
            mountedTabs.insert(newTab)
        }
        .onChange(of: appTheme) { _, newValue in
            ThemeTransition.apply(newValue, animated: true)
        }
        .onAppear {
            if activeSince == nil { activeSince = Date() }
            ThemeTransition.apply(appTheme, animated: false)
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

    // MARK: iOS 26+ 原生液态玻璃 TabView

    @available(iOS 26.0, *)
    private var nativeTabView: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.overview) {
                tabContent(for: .overview)
                    .background(Theme.bg.ignoresSafeArea())
            } label: {
                tabLabel(.overview)
            }

            Tab(value: AppTab.tasks) {
                tabContent(for: .tasks)
                    .background(Theme.bg.ignoresSafeArea())
            } label: {
                tabLabel(.tasks)
            }

            Tab(value: AppTab.course) {
                tabContent(for: .course)
                    .background(Theme.bg.ignoresSafeArea())
            } label: {
                tabLabel(.course)
            }

            Tab(value: AppTab.ledger) {
                tabContent(for: .ledger)
                    .background(Theme.bg.ignoresSafeArea())
            } label: {
                tabLabel(.ledger)
            }

            if FeatureFlags.enableDeepSeek {
                Tab(value: AppTab.api) {
                    tabContent(for: .api)
                        .background(Theme.bg.ignoresSafeArea())
                } label: {
                    tabLabel(.api)
                }
            }
        }
        .tint(Theme.brand)
    }

    private func tabLabel(_ item: AppTab) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(uiImage: Reicon.tabImage(item.reicon))
        }
    }

    // MARK: iOS 17–25 兜底容器

    private var legacyTabContainer: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            ZStack {
                if isMounted(.overview) {
                    tabContent(for: .overview)
                        .tabPageVisible(tab == .overview)
                }

                if isMounted(.tasks) {
                    tabContent(for: .tasks)
                        .tabPageVisible(tab == .tasks)
                }

                if isMounted(.course) {
                    tabContent(for: .course)
                        .tabPageVisible(tab == .course)
                }

                if isMounted(.ledger) {
                    tabContent(for: .ledger)
                        .tabPageVisible(tab == .ledger)
                }

                if FeatureFlags.enableDeepSeek, isMounted(.api) {
                    tabContent(for: .api)
                        .tabPageVisible(tab == .api)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GlassTabBar(selection: $tab)
        }
    }

    @ViewBuilder
    private func tabContent(for item: AppTab) -> some View {
        switch item {
        case .overview:
            OverviewView(
                onOpenTasks: { tab = .tasks },
                onOpenCourse: { tab = .course },
                onOpenSubscriptions: { tab = .ledger },
                onAddTask: { isQuickAddPresented = true },
                onOpenSettings: { isSettingsPresented = true }
            )
        case .tasks:
            TasksView(onAdd: { isQuickAddPresented = true })
        case .course:
            TimetableView()
        case .ledger:
            SubscriptionMainView()
        case .api:
            DeepSeekMonitorView()
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

    private func pollDeepSeekIfNeeded() {
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

    private func isMounted(_ page: AppTab) -> Bool {
        mountedTabs.contains(page) || tab == page
    }
}

// MARK: - 保活页显隐

private extension View {
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

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: TaskItem.self, Subtask.self, Course.self, CourseSlot.self,
            TimetableSettings.self, DailyUsage.self, DeepSeekDay.self, DeepSeekState.self,
            WeReadDay.self, WeReadBook.self, Subscription.self, CountdownItem.self,
            configurations: config
        )
        SeedData.seedIfNeeded(container.mainContext)
        return container
    }()
}
