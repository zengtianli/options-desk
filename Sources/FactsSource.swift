import Foundation

protocol FactsSource {
    func load() async -> Result<DeskFacts, DeskError>
}

/// 本地样本源。**数字是真的** —— 2026-08-29 直接抄 `/api/desk-summary` 的实跑响应,
/// 这样第一屏截图里的排版就是上线后真实的量级,不会出现「样本三位数、真数据五位数」那种返工。
///
/// ⚠ 这批数经过两轮订正,别拿旧版对照:
/// ① 归日改按 `session`(快照不是收盘时刻拉的,`asof[:10]` 有 28% 的行归错天);
/// ② 比较窗口两边截齐 —— 服务端曾把 TWR 算到 08-28 而基准只到 08-27,
///    因为 08-28 的 QQQ 收盘价还没结算。两个不同窗口的数并排印成「同窗口」,差 0.66pp。
/// 现值 = 53 个 session / 52 个链接,窗口 2026-06-09~2026-08-27,两条曲线同起同止。
struct SampleFactsSource: FactsSource {
    var asofOverride: Date?

    func load() async -> Result<DeskFacts, DeskError> {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 28; c.hour = 16
        c.timeZone = TimeZone(identifier: "America/New_York")   // 见 ContentView.marketTime 的例外说明
        let asof = asofOverride ?? Calendar(identifier: .gregorian).date(from: c)!
        return .success(DeskFacts(
            asof: asof, nlv: 1_354_906.14,
            twrCumulative: 0.2336_4080, qqqCumulative: 0.0187_6157,
            sampleDays: 53, accounts: ["••••6277", "••••3444"],
            benchmarkLagNote: "最新 1 个 session（2026-08-28）的 QQQ 收盘价尚未结算，已排除出比较窗口",
            flowUnknownDays: 18))
    }
}

/// 线上源:消费 stockoptions 的 `/api/desk-summary`。
///
/// **累计收益是服务端算的,客户端一行公式都不写** —— 客户端自己算就成了第三份 TWR 实现
/// (api.py 的 `_twr_curve` 与 ~/investment 的 `race_series` 已经是两份)。
/// 这里只解码 + 呈现。
struct LiveFactsSource: FactsSource {
    let baseURL: String
    /// **不用 `.shared`** —— 需要一个自己的 cookie jar 装闸的会话 cookie。
    var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared          // 域 .tianli.cyou，跨启动保留
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

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
        let benchmark_lag_note: String?
    }

    func load() async -> Result<DeskFacts, DeskError> {
        guard !baseURL.isEmpty, let url = URL(string: baseURL + "/api/desk-summary") else {
            return .failure(.notConfigured(baseURL: baseURL))
        }
        let shown = url.absoluteString
        // 装机时 `seed-gate.sh` 用 `-gatepw` 喂进来的密码 —— **验过才写钥匙串**。
        // 没喂过就立刻返回，代价为零，所以放在这里而不是 App 启动路径上分叉。
        await Gate.seedFromLaunchArg(session: session)
        do {
            var (data, resp) = try await session.data(from: url)

            // 撞闸：URLSession 会跟着 302 走到登录页，到手是**登录页的 200 HTML**，
            // 状态码分辨不出来 —— 判据是最终 URL 落在 `/_gate/` 下（同 Gate.blocked）。
            // 有密码就换一次会话再重试**一次**；没密码就明说要喂密码，别去查服务端。
            if Gate.blocked(resp) {
                guard let pw = Gate.password else {
                    return .failure(.gate(url: shown,
                        reason: "这台设备还没有闸凭证（iOS 钥匙串里没有密码）"))
                }
                do { try await Gate.login(password: pw, session: session) }
                catch {
                    return .failure(.gate(url: shown,
                        reason: (error as? Gate.Failure)?.message ?? "登录失败"))
                }
                (data, resp) = try await session.data(from: url)
                if Gate.blocked(resp) {
                    return .failure(.gate(url: shown,
                        reason: "拿密码换了会话之后仍被拦 —— 密码可能已经改了"))
                }
            }

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
                benchmarkLagNote: p.benchmark_lag_note,
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

/// 选源。**默认就是线上** —— 2026-08-29 起 `desk.tianli.cyou` 已上线，
/// 装到手机上点开就该看见真数;样本源退回成截图/离线调试用的显式档。
///
///   （默认）        → https://desk.tianli.cyou  ，闸内，凭证走 Gate
///   -apiBase <URL>  → 指别处（本机 uvicorn 调试:`-apiBase http://127.0.0.1:8799`）
///   -sample         → 本地样本，不联网
enum FactsSourceFactory {
    static let productionBase = "https://desk.tianli.cyou"

    static func make(_ args: [String] = ProcessInfo.processInfo.arguments) -> FactsSource {
        if args.contains("-sample") { return SampleFactsSource() }
        if let i = args.firstIndex(of: "-apiBase"), i + 1 < args.count {
            return LiveFactsSource(baseURL: args[i + 1])
        }
        return LiveFactsSource(baseURL: productionBase)
    }
}
