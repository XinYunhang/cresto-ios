import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .overview
    @State private var isQuickAddPresented = false
    @State private var isCourseEditorPresented = false
    @State private var isSettingsPresented = false
    @State private var todayDraw: DailyTarot?
    @State private var activeSince: Date?

    @State private var ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.bg.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底栏下方不垫不透明渐隐：让卡片的边角从玻璃底下滚过去，玻璃才有折射
            LinearGradient(
                stops: [
                    .init(color: Theme.bg.opacity(0), location: 0),
                    .init(color: Theme.bg.opacity(0.55), location: 0.6),
                    .init(color: Theme.bg.opacity(0.9), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .allowsHitTesting(false)

            GlassTabBar(selection: $tab, onAdd: handleAdd)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if activeSince == nil { activeSince = Date() }
            AppLog.info("App 启动")
        }
        .onChange(of: tab) { _, newValue in
            AppLog.info("切换到 \(newValue.title)")
        }
        .task {
            if todayDraw == nil {
                todayDraw = TarotService.ensureToday(in: context)
            }
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
        }
        .sheet(isPresented: $isQuickAddPresented) {
            QuickAddSheet()
        }
        .sheet(isPresented: $isCourseEditorPresented) {
            CourseEditor(course: nil, slot: nil)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    // MARK: 使用时长

    /// 把从上次记录到现在的前台时间累加进今天
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

    /// FAB 是上下文相关的：课表页加课程，其他页加速记
    private func handleAdd() {
        if tab == .course {
            isCourseEditorPresented = true
        } else {
            isQuickAddPresented = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            OverviewView(
                draw: todayDraw,
                onOpenTarot: { tab = .tarot },
                onOpenTime: { tab = .time },
                onOpenTasks: { tab = .tasks },
                onOpenSettings: { isSettingsPresented = true }
            )
        case .tasks:
            TasksView()
        case .course:
            TimetableView()
        case .tarot:
            TarotView(draw: todayDraw)
        case .time:
            TimeView()
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
            TimetableSettings.self, DailyTarot.self, DailyUsage.self,
            configurations: config
        )
        SeedData.seedIfNeeded(container.mainContext)
        return container
    }()
}
