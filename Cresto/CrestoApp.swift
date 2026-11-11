import SwiftUI
import SwiftData

@main
struct CrestoApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: TaskItem.self,
                Subtask.self,
                Course.self,
                CourseSlot.self,
                TimetableSettings.self,
                DailyTarot.self,
                DailyUsage.self
            )
        } catch {
            fatalError("SwiftData 容器创建失败：\(error)")
        }

        SeedData.seedIfNeeded(container.mainContext)
        NotificationScheduler.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
