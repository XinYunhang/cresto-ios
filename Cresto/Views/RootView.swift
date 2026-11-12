import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("appTheme") private var appTheme = "system"

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

            GlassTabBar(selection: $tab)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
        }
        .preferredColorScheme(colorScheme)
        .onAppear {
            if activeSince == nil { activeSince = Date() }
            AppLog.info("App 启动 · 主题 \(appTheme)")
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

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            OverviewView(
                draw: todayDraw,
                onOpenTarot: { tab = .tarot },
                onOpenTasks: { tab = .tasks },
                onAddTask: { isQuickAddPresented = true },
                onOpenSettings: { isSettingsPresented = true }
            )
        case .tasks:
            TasksView(onAdd: { isQuickAddPresented = true })
        case .course:
            TimetableView()
        case .tarot:
            TarotView(draw: todayDraw)
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
