import Foundation

/// 微信读书同步服务。
///
/// ⚠️ 接口契约状态（2026-11-24，如实标注）：本轮任务提供了 Key，但**未附带接口文档/地址**，
/// 公网检索也未找到 `wrk-` 前缀的已知服务。当前实现按「最小通用约定」：
///   GET {endpoint}
///   Authorization: Bearer {key}
///   期望 JSON：
///   {
///     "days": [{"date": "2026-11-23", "minutes": 48}, ...],
///     "current_book": {"title": "惊悚乐园", "author": "三天两觉",
///                      "cover": "https://...", "progress": 0.7}
///   }
/// decode 层做了容错（days/date/dateKey/day、minutes/duration/readTime、
/// currentBook/current_book/book、progress 0-1 或 0-100）。
/// 拿到正式接口文档后，**只需改本文件的请求头与 decode**，UI / 缓存 / 备份不动。
///
/// 凭证：Key 存钥匙串（com.xinyunhang.cresto.weread），或回退 profile.plist 本地默认（不进仓库）；
/// 接口地址存 UserDefaults（设置页可改），或回退 profile.plist 本地默认。
actor WeReadService {
    static let shared = WeReadService()

    struct Config {
        let endpoint: URL
        let key: String
    }

    enum WeReadError: LocalizedError {
        case notConfigured
        case unauthorized
        case network(String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "还没配置微信读书接口地址或 Key，去设置页填一下"
            case .unauthorized: return "Key 无效或已失效，去设置页检查"
            case .network(let detail): return "网络不通：\(detail)"
            case .malformed: return "返回结构对不上（接口契约待文档校准）"
            }
        }
    }

    /// 端点优先级：设置页保存的 UserDefaults → profile.plist 本地默认；Key：钥匙串 → profile.plist 本地默认
    static func resolvedConfig() -> Config? {
        let savedEndpoint = UserDefaults.standard.string(forKey: "wereadEndpoint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointText = (savedEndpoint?.isEmpty == false ? savedEndpoint : nil) ?? LocalProfile.wereadEndpoint
        let key = KeychainService.load(service: KeychainService.wereadService, account: KeychainService.wereadAccount)
            ?? LocalProfile.wereadAPIKey

        guard let endpointText, !endpointText.isEmpty,
              let endpoint = URL(string: endpointText),
              let key, !key.isEmpty else {
            return nil
        }
        return Config(endpoint: endpoint, key: key)
    }

    /// 拉取近 30 天阅读记录与当前在读（超时 2s：弱网自动回退本地缓存）
    func fetch() async throws -> WeReadSnapshot {
        guard let config = Self.resolvedConfig() else { throw WeReadError.notConfigured }

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 2.0

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WeReadError.network(error.localizedDescription)
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            break
        case 401, 403:
            throw WeReadError.unauthorized
        default:
            throw WeReadError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        return try Self.decode(data)
    }

    // MARK: - 解码（唯一需要按接口文档校准的位置）

    static func decode(_ data: Data) throws -> WeReadSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeReadError.malformed
        }
        let container = (root["data"] as? [String: Any]) ?? root

        let rawDays = (container["days"] as? [[String: Any]])
            ?? (container["read_days"] as? [[String: Any]])
            ?? (container["stats"] as? [[String: Any]])
            ?? []

        var days: [WeReadSnapshot.Day] = []
        for item in rawDays {
            let dateText = (item["date"] as? String)
                ?? (item["dateKey"] as? String)
                ?? (item["day"] as? String)
                ?? ""
            let minutes = intValue(item["minutes"])
                ?? intValue(item["duration"])
                ?? intValue(item["readTime"])
                ?? intValue(item["read_minutes"])
                ?? 0
            let key = normalizeDateKey(dateText)
            guard !key.isEmpty else { continue }
            days.append(.init(dateKey: key, minutes: max(0, minutes)))
        }

        let rawBook = (container["current_book"] as? [String: Any])
            ?? (container["currentBook"] as? [String: Any])
            ?? (container["book"] as? [String: Any])
        var book: WeReadSnapshot.Book?
        if let rawBook {
            let title = (rawBook["title"] as? String) ?? ""
            if !title.isEmpty {
                let author = (rawBook["author"] as? String)
                    ?? (rawBook["authorName"] as? String)
                    ?? ""
                let cover = (rawBook["cover"] as? String)
                    ?? (rawBook["coverURL"] as? String)
                    ?? (rawBook["coverUrl"] as? String)
                    ?? ""
                var progress = doubleValue(rawBook["progress"]) ?? 0
                if progress > 1 { progress /= 100 }
                book = .init(title: title, author: author, coverURL: cover, progress: min(1, max(0, progress)))
            }
        }

        guard !days.isEmpty || book != nil else { throw WeReadError.malformed }
        return WeReadSnapshot(days: days, book: book)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return Int(double.rounded())
        case let number as NSNumber: return number.intValue
        case let text as String:
            if let int = Int(text) { return int }
            return Double(text).map { Int($0.rounded()) }
        default: return nil
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    /// 归一化 dateKey：接受 "2026-11-23" / "2026/11/23" / ISO8601 前缀
    private static func normalizeDateKey(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return "" }
        let normalized = trimmed.replacingOccurrences(of: "/", with: "-")
        return String(normalized.prefix(10))
    }
}