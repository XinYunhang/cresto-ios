import Foundation

/// 本地个人信息（生日）不打进仓库。
///
/// 生日只用来当运势的种子，但它同时是隐私，公开仓库里不该出现。
/// 所以从 `Resources/profile.plist` 读；没有就用中性默认值。
/// 本地生成：`bash scripts/make_profile.sh 2008-06-17`
enum LocalProfile {
    static var birthday: DateComponents {
        guard let url = Bundle.main.url(forResource: "profile", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let text = dict["birthday"] as? String,
              let date = formatter.date(from: text) else {
            return DateComponents(year: 2000, month: 1, day: 1)
        }
        return Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
