import SwiftUI
import SwiftData

@main
struct CrestoApp: App {
    private let container: ModelContainer

    init() {
        MottoFont.registerIfNeeded()
        container = Persistence.makeContainer()

        SeedData.seedIfNeeded(container.mainContext)
        Persistence.logLaunchDiagnostics(in: container.mainContext)
        BackupService.makeDailySnapshotIfNeeded(in: container.mainContext)
        NotificationScheduler.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
