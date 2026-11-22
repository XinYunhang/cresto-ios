import Foundation

/// DeepSeek 官方余额接口。官方只有余额、没有用量历史；
/// 「轮询 + 余额差值累计消耗」按笔记 07 的规划放到下一轮接热力图时再做。
actor DeepSeekService {
    static let shared = DeepSeekService()

    private let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    // MARK: 错误

    enum DeepSeekError: LocalizedError {
        case keyMissing
        case unauthorized    // 401：Key 失效
        case rateLimited     // 429：限流
        case server          // 5xx 及其他非 200
        case network(String) // 断网 / 超时
        case malformed       // 返回结构对不上

        var errorDescription: String? {
            switch self {
            case .keyMissing: return "还没配置 API Key，去设置页填一个"
            case .unauthorized: return "API Key 失效了，去设置页重新填"
            case .rateLimited: return "被限流了，稍后再试"
            case .server: return "DeepSeek 服务端暂时有问题，稍后再试"
            case .network(let detail): return "网络不通：\(detail)"
            case .malformed: return "返回结构对不上，余额先显示「—」"
            }
        }
    }

    // MARK: 数据

    struct BalanceInfo {
        let currency: String
        let total: Double?
        let granted: Double?
        let toppedUp: Double?
    }

    // MARK: 查询

    func fetchBalance() async throws -> BalanceInfo {
        guard let key = KeychainService.load(), !key.isEmpty else {
            throw DeepSeekError.keyMissing
        }

        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw DeepSeekError.network(error.localizedDescription)
        }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            break
        case 401:
            throw DeepSeekError.unauthorized
        case 429:
            throw DeepSeekError.rateLimited
        default:
            throw DeepSeekError.server
        }

        // total_balance 等数值是字符串 "5.10"，不是数字——必须 Double(str) 再算；
        // 转换失败一律当「无数据」渲染「—」，严禁强解
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let first = payload.balanceInfos.first else {
            // 返回结构与预期不符时把开头一段写进日志，方便定位（响应体不含 Key，无泄露）
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<非文本响应>"
            AppLog.info("DeepSeek 余额返回结构异常：\(snippet)")
            throw DeepSeekError.malformed
        }

        return BalanceInfo(
            currency: first.currency,
            total: Double(first.totalBalance),
            granted: Double(first.grantedBalance),
            toppedUp: Double(first.toppedUpBalance)
        )
    }
}

// MARK: - 请求结构

private extension DeepSeekService {
    struct Payload: Decodable {
        let balanceInfos: [Info]

        // JSONDecoder 默认策略不做 snake_case 转换，顶层键必须显式映射
        enum CodingKeys: String, CodingKey {
            case balanceInfos = "balance_infos"
        }

        struct Info: Decodable {
            let currency: String
            let totalBalance: String
            let grantedBalance: String
            let toppedUpBalance: String

            enum CodingKeys: String, CodingKey {
                case currency
                case totalBalance = "total_balance"
                case grantedBalance = "granted_balance"
                case toppedUpBalance = "topped_up_balance"
            }
        }
    }
}

// MARK: - 展示辅助

extension DeepSeekService.BalanceInfo {
    var currencySymbol: String {
        switch currency.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        default: return currency
        }
    }

    /// 解析失败的数值一律显示「—」
    func text(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value)
    }

    var totalText: String { text(total) }
    var grantedText: String { text(granted) }
    var toppedUpText: String { text(toppedUp) }
}
