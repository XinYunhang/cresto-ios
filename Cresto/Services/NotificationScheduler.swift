import Foundation
import UserNotifications

/// 本地通知。不依赖服务端，关机重启也还在。
enum NotificationScheduler {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 每次保存/勾选都调用：先取消旧的，再按需排新的
    static func sync(_ task: TaskItem) {
        cancel(id: task.id)
        guard !task.isCompleted, let fireDate = task.reminderDate, fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = task.title.isEmpty ? "待办提醒" : task.title
        content.body = body(for: task)
        content.sound = .default
        content.userInfo = ["taskID": task.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier(for: task.id),
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier(for: id)])
    }

    static func syncAll(_ tasks: [TaskItem]) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        tasks.forEach { sync($0) }
    }

    // MARK: 私有

    private static func identifier(for id: UUID) -> String {
        "task-\(id.uuidString)"
    }

    private static func body(for task: TaskItem) -> String {
        if !task.notes.isEmpty { return task.notes }
        if let due = task.dueDate, task.hasTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return "\(formatter.string(from: due)) 到期"
        }
        return "记得处理一下"
    }
}
