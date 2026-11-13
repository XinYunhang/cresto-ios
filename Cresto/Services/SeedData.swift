import Foundation
import SwiftData

/// 第一次启动塞一点样例，免得打开是一片空白。
/// 真用起来之后在设置里加一个「清空示例数据」就行。
enum SeedData {
    static func seedIfNeeded(_ context: ModelContext) {
        let taskCount = (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? 0
        let settingsCount = (try? context.fetchCount(FetchDescriptor<TimetableSettings>())) ?? 0

        if settingsCount == 0 {
            context.insert(TimetableSettings())
        }

        if taskCount == 0 {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            let morning = TaskItem(
                title: "晨间复盘 15 分钟",
                dueDate: calendar.date(byAdding: .hour, value: 9, to: today),
                hasTime: true,
                priority: .low,
                reminder: .min5,
                repeatKind: .daily,
                tags: ["习惯"]
            )
            morning.isCompleted = true
            morning.completedAt = Date()

            let main = TaskItem(
                title: "给 Cresto 写 iOS 首页",
                dueDate: today,
                hasTime: false,
                priority: .high,
                reminder: .none,
                tags: ["开发"]
            )
            let sub1 = Subtask(title: "确认底栏交互", order: 0)
            let sub2 = Subtask(title: "接 SwiftData", order: 1)
            sub2.isDone = true
            main.subtasks = [sub1, sub2]

            let night = TaskItem(
                title: "整理 dsh-go 的远程协议笔记",
                dueDate: calendar.date(byAdding: .hour, value: 21, to: today),
                hasTime: true,
                reminder: .min15,
                tags: ["研究"]
            )

            let tomorrow = TaskItem(
                title: "塔罗牌阵：三张牌",
                dueDate: calendar.date(byAdding: .day, value: 1, to: today),
                hasTime: true
            )

            [morning, main, night, tomorrow].forEach { context.insert($0) }
        }

        CourseImporter.importIfNeeded(into: context)

        try? context.save()
    }
}
