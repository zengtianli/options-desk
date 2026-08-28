import Foundation

protocol FactsSource {
    func load() async -> Result<DeskFacts, DeskError>
}

/// 本地样本源。**数字是真的**(2026-08-29 用回填完 qqq_close 之后的 quant.db 实算,
/// 且与服务端 /api/desk-summary 独立实现的结果逐位一致),
/// 这样第一屏截图里的排版就是上线后真实的量级,不会出现「样本三位数、真数据五位数」那种返工。
struct SampleFactsSource: FactsSource {
    var asofOverride: Date?

    func load() async -> Result<DeskFacts, DeskError> {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 27; c.hour = 16
        c.timeZone = TimeZone(identifier: "America/New_York")   // 见 ContentView.marketTime 的例外说明
        let asof = asofOverride ?? Calendar(identifier: .gregorian).date(from: c)!
        return .success(DeskFacts(
            asof: asof, nlv: 1_365_065.92,
            twrCumulative: 0.2335, qqqCumulative: 0.0188,
            sampleDays: 50, accounts: ["••••6277", "••••3444"], flowUnknownDays: 17))
    }
}

/// 线上源:消费 stockoptions 的 `/api/desk-summary`。
///
/// **累计收益是服务端算的,客户端一行公式都不写** —— 客户端自己算就成了第三份 TWR 实现
/// (api.py 的 `_twr_curve` 与 ~/investment 的 `race_series` 已经是两份)。
/// 这里只解码 + 呈现。
struct LiveFactsSource: FactsSource {
    let baseURL: String
    var session: URLSession = .shared

    /// 服务端契约。字段名对不上就报 `.decoding` 并**点名是哪个字段**,不容错、不填默认值 ——
    /// 容错会让契约漂移变成一个静默显示错数的 app。
    private struct Payload: Decodable {
        let asof: String?
        let nlv: Double
        let twr_cumulative: Double
        let qqq_cumulative: Double?
        let sessions: Int
        let flow_unknown_days: Int
        let accounts_merged: [String]?
        let is_stale: Bool?
    }

    func load() async -> Result<DeskFacts, DeskError> {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + "/api/desk-summary") else {
            return .failure(.notConfigured(baseURL: baseURL))
        }
        let shown = url.absoluteString
        do {
            let (data, resp) = try await session.data(from: url)
            guard let http = resp as? HTTPURLResponse else {
                return .failure(.network(url: shown, underlying: "响应不是 HTTP"))
            }
            guard http.statusCode == 200 else {
                return .failure(.http(url: shown, status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "<非文本>"))
            }
            let p: Payload
            do { p = try JSONDecoder().decode(Payload.self, from: data) }
            catch let DecodingError.keyNotFound(key, ctx) {
                return .failure(.decoding(url: shown, field: key.stringValue, detail: ctx.debugDescription))
            }
            catch let DecodingError.typeMismatch(_, ctx) {
                return .failure(.decoding(url: shown,
                                          field: ctx.codingPath.map(\.stringValue).joined(separator: "."),
                                          detail: ctx.debugDescription))
            }
            catch { return .failure(.decoding(url: shown, field: "(整个响应体)", detail: "\(error)")) }

            guard p.sessions > 0 else { return .failure(.empty(url: shown)) }
            guard let q = p.qqq_cumulative else {
                // 超额是首屏最重要那栏。基准算不出来就说清楚,别显示一个没有基准的孤零零收益率。
                return .failure(.decoding(url: shown, field: "qqq_cumulative",
                                          detail: "服务端返回 null —— 基准序列缺失，超额无法计算"))
            }
            guard let iso = p.asof, let asof = Self.iso.date(from: iso) ?? Self.isoNoFrac.date(from: iso) else {
                return .failure(.decoding(url: shown, field: "asof",
                                          detail: "缺失或不是 ISO8601：\(p.asof ?? "nil")"))
            }
            return .success(DeskFacts(
                asof: asof, nlv: p.nlv,
                twrCumulative: p.twr_cumulative, qqqCumulative: q,
                sampleDays: p.sessions,
                accounts: p.accounts_merged ?? [],
                flowUnknownDays: p.flow_unknown_days))
        } catch {
            return .failure(.network(url: shown, underlying: Self.brief(error)))
        }
    }

    /// URLError 的 `\(error)` 是一整坨 NSError dump(实测占满一屏,有用的只有第一行)。
    /// 错误条要能一眼看懂,所以只留「码 + 人话」;需要细节时 URL 已经单列在上面了。
    static func brief(_ error: Error) -> String {
        if let u = error as? URLError {
            return "URLError \(u.errorCode)：\(u.localizedDescription)"
        }
        return (error as NSError).localizedDescription
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}

/// 启动参数选源:`-apiBase http://127.0.0.1:8621` 指线上源,不给就用样本源。
/// 这样「接上真 API 跑一遍」不需要改代码重编,也不用把 base URL 写死进包里。
enum FactsSourceFactory {
    static func make(_ args: [String] = ProcessInfo.processInfo.arguments) -> FactsSource {
        if let i = args.firstIndex(of: "-apiBase"), i + 1 < args.count {
            return LiveFactsSource(baseURL: args[i + 1])
        }
        return SampleFactsSource()
    }
}
