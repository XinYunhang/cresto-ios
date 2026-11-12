import Foundation

/// 本地个人信息（生日、称呼）不打进仓库。
///
/// 生日用来当运势种子，称呼用在首页问候语——都是隐私，公开仓库里不该出现。
/// 数据从 `Resources/profile.plist` 读；没有就用中性默认值。
/// 本地生成：`bash scripts/make_profile.sh 2008-06-17 秦耀扬`
enum LocalProfile {
    static var birthday: DateComponents {
        guard let text = value(for: "birthday"),
              let date = formatter.date(from: text) else {
            return DateComponents(year: 2000, month: 1, day: 1)
        }
        return Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    }

    static var displayName: String {
        value(for: "name") ?? "你"
    }

    // MARK: 私有

    private static func value(for key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "profile", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = dict[key] as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
