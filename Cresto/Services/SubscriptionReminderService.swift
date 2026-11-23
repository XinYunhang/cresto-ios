import Foundation
import SwiftData
import UserNotifications

/// 订阅续费提醒：进入提醒窗口时自动写入 #订阅 待办 + 注册本地通知。
/// 幂等设计：`lastRemindedCycleKey` 记录已提醒的扣费周期日期，
/// 且额外按「标题 + 扣费日」查重，同一周期不会生成多条。
enum SubscriptionReminderService {
    /// App 启动 / 回前台 / 保存订阅后调用
    static func sync(_ subscriptions: [Subscription], in context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var changed = false

        for sub in subscriptions {
            guard !sub.isPaused else { continue }

            // 1) 把已经过去的扣费日按锚定日顺延到未来
            var advanced = false
            var guardCount = 0
            while calendar.startOfDay(for: sub.nextChargeDate) < today, guardCount < 400 {
                sub.nextChargeDate = SubscriptionMath.advance(
                    sub.nextChargeDate,
                    cycle: sub.cycle,
                    anchorDay: sub.anchorDay,
                    by: 1
                )
                advanced = true
                guardCount += 1
            }
            if advanced { changed = true }

            guard sub.remindEnabled else { continue }
            guard let days = calendar.dateComponents(
                [.day],
                from: today,
                to: calendar.startOfDay(for: sub.nextChargeDate)
            ).day, days >= 0, days <= sub.remindDaysBefore else { continue }

            let cycleKey = UsageStore.key(for: sub.nextChargeDate)
            if sub.lastRemindedCycleKey == cycleKey { continue }

            let title = "确认续费：\(sub.name) (\(sub.displayPrice))"
            if !hasExistingTask(title: title, due: sub.nextChargeDate, in: context) {
                let task = TaskItem(
                    title: title,
                    dueDate: calendar.startOfDay(for: sub.nextChargeDate),
                    hasTime: false,
                    tags: ["订阅"]
                )
                context.insert(task)
                NotificationScheduler.sync(task)
            }

            scheduleNotification(for: sub, cycleKey: cycleKey)
            sub.lastRemindedCycleKey = cycleKey
            changed = true
        }

        if changed { try? context.save() }
    }

    /// 暂停 / 删除订阅时取消已排的本地通知
    static func cancelPendingNotifications(for sub: Subscription) {
        let prefix = "subscription-\(sub.id.uuidString)-"
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: 私有

    private static func hasExistingTask(title: String, due: Date, in context: ModelContext) -> Bool {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let calendar = Calendar.current
        return tasks.contains { task in
            guard task.title == title, !task.isCompleted, task.deletedAt == nil,
                  let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: due)
        }
    }

    /// 通知时间：扣费日前 remindDaysBefore 天的 09:00；若已过（例如刚进入窗口）则 5 秒后补发一次
    private static func scheduleNotification(for sub: Subscription, cycleKey: String) {
        let calendar = Calendar.current
        guard let remindDay = calendar.date(
            byAdding: .day,
            value: -sub.remindDaysBefore,
            to: calendar.startOfDay(for: sub.nextChargeDate)
        ) else { return }

        var components = calendar.dateComponents([.year, .month, .day], from: remindDay)
        components.hour = 9
        var fireDate = calendar.date(from: components) ?? remindDay
        if fireDate <= Date() {
            fireDate = Date().addingTimeInterval(5)
        }

        let content = UNMutableNotificationContent()
        content.title = "订阅续费提醒"
        content.body = "\(sub.name) 将于 \(monthDayText(sub.nextChargeDate)) 扣费 \(sub.displayPrice)，记得确认"
        content.sound = .default
        content.userInfo = ["subscriptionID": sub.id.uuidString, "cycleKey": cycleKey]

        let triggerComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "subscription-\(sub.id.uuidString)-\(cycleKey)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func monthDayText(_ date: Date) -> String {
        let calendar = Calendar.current
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }
}