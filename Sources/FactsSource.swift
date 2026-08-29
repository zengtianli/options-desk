import Foundation

protocol FactsSource {
    func load() async -> Result<DeskFacts, DeskError>
}

/// 本地样本源。**数字是真的** —— 2026-08-29 直接抄 `/api/desk-summary` 的实跑响应,
/// 这样第一屏截图里的排版就是上线后真实的量级,不会出现「样本三位数、真数据五位数」那种返工。
///
/// ⚠ 这批数经过**四轮**订正,别拿旧版对照:
/// ① 归日改按 `session`(快照不是收盘时刻拉的,`asof[:10]` 有 28% 的行归错天);
/// ② 比较窗口两边截齐(服务端曾把 TWR 算到 08-28 而基准只到 08-27,差 0.66pp);
/// ③ 序列从 54 天补到 **400 天**(2025-01-02 起,legacy daily_nlv.csv + 整年订单流);
/// ④ **2026-08-29 最要紧的一轮**:六月的到期指派补进库之后,原先当成「资金流未记录」
///    的 18 天算出来了 —— 那 18 天里有 **+$13.4 万的净入金**被当成了投资赚来的钱。
///    修正前 +46.48%、修正后 **+30.69%**,而 QQQ 同窗 +41.33% ——
///    **方向都变了:不是跑赢 5 个点,是落后 10.6 个点。**
///    口径同时收成单账户(700013444 按用户钦定移出)。
struct SampleFactsSource: FactsSource {
    var asofOverride: Date?

    func load() async -> Result<DeskFacts, DeskError> {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 28; c.hour = 16
        c.timeZone = TimeZone(identifier: "America/New_York")   // 见 ContentView.marketTime 的例外说明
        let asof = asofOverride ?? Calendar(identifier: .gregorian).date(from: c)!
        return .success(DeskFacts(
            asof: asof, nlv: 1_354_906.08,
            twrCumulative: 0.3068_5695, qqqCumulative: 0.4133_0380,
            sampleDays: 400, accounts: ["••••6277"],
            benchmarkLagNote: "最新 1 个 session（2026-08-28）的 QQQ 收盘价尚未结算，已排除出比较窗口",
            // 区间机制留着（服务端一旦又出现定性不明的资金流会重新给值），
            // 但现在全窗口资金流逐日已知，所以是 nil —— 不是把不确定藏了，是它不成立了。
            excessRange: nil,
            flowUnknownDays: 0,
            // 同样是**实跑抄下来的真数**（/api/desk-summary 的 risk 块，2026-08-29）。
            // 编一组好看的会让截图上的排版和上线后对不上 —— 这个 app 反复栽的就是那个。
            risk: DeskRisk(netDeltaRatio: 0.7697, netDeltaNotional: 1_042_902.08,
                           equityGrossRatio: 2.4984, buyingPowerRatio: 0.01704,
                           marginDebt: 2_042_256.73,
                           concentrationSymbol: "QQQ", concentrationShare: 0.9339,
                           volWindow: 20, volCC: 0.1349, volQQQ: 0.1768,
                           volCCPrev: 0.3310, volCCPrevDate: "2026-07-30",
                           exposureAsof: "2026-08-28T16:00:00-04:00",
                           complete: true, incompleteNote: nil),
            riskError: nil))
    }
}

/// 线上源:消费 stockoptions 的 `/api/desk-summary`。
///
/// **累计收益是服务端算的,客户端一行公式都不写** —— 客户端自己算就成了第三份 TWR 实现
/// (api.py 的 `_twr_curve` 与 ~/investment 的 `race_series` 已经是两份)。
/// 这里只解码 + 呈现。
struct LiveFactsSource: FactsSource {
    let baseURL: String
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
        let excess_range: [Double]?
        /// 整块可能是 null（持仓快照坏了 / 样本不够算滚动波动）。
        /// 那时 `risk_error` 有原文 —— **两个都不给默认值**，界面照原文印。
        let risk: Risk?
        let risk_error: String?

        struct Risk: Decodable {
            let net_delta_ratio: Double?
            let net_delta_notional: Double?
            let equity_gross_ratio: Double?
            let buying_power_ratio: Double?
            let margin_debt: Double?
            let concentration_symbol: String?
            let concentration_share: Double?
            let vol_window: Int
            let vol_cc: Double?
            let vol_qqq: Double?
            let vol_cc_prev: Double?
            let vol_cc_prev_date: String?
            let exposure_asof: String?
            let complete: Bool
            let incomplete_note: String?
        }
    }

    func load() async -> Result<DeskFacts, DeskError> {
        guard !baseURL.isEmpty else { return .failure(.notConfigured(baseURL: baseURL)) }
        let shown = baseURL + "/api/desk-summary"
        // 取数与闸(撞闸 → 换会话 → 重试一次)全在 DeskAPI 里 —— 五个页面共用同一份判据。
        switch await DeskAPI(base: baseURL).get("/api/desk-summary", as: Payload.self) {
        case .failure(let e): return .failure(e)
        case .success(let p):
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
                // 服务端给的是 [下界, 上界]；两端相等或缺失就不显示区间。
                excessRange: {
                    guard let r = p.excess_range, r.count == 2, r[0] < r[1] else { return nil }
                    return r[0]...r[1]
                }(),
                flowUnknownDays: p.flow_unknown_days,
                risk: p.risk.map {
                    DeskRisk(netDeltaRatio: $0.net_delta_ratio,
                             netDeltaNotional: $0.net_delta_notional,
                             equityGrossRatio: $0.equity_gross_ratio,
                             buyingPowerRatio: $0.buying_power_ratio,
                             marginDebt: $0.margin_debt,
                             concentrationSymbol: $0.concentration_symbol,
                             concentrationShare: $0.concentration_share,
                             volWindow: $0.vol_window,
                             volCC: $0.vol_cc, volQQQ: $0.vol_qqq,
                             volCCPrev: $0.vol_cc_prev, volCCPrevDate: $0.vol_cc_prev_date,
                             exposureAsof: $0.exposure_asof,
                             complete: $0.complete, incompleteNote: $0.incomplete_note)
                },
                riskError: p.risk_error))
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
        return LiveFactsSource(baseURL: resolvedBase(args))
    }

    /// 别的页面(日志/持仓/曲线/风控)也要知道指向哪 —— 解析只此一处,
    /// 免得出现「首屏指线上、别的页指默认」这种一半一半的错。
    static func resolvedBase(_ args: [String] = ProcessInfo.processInfo.arguments) -> String {
        if let i = args.firstIndex(of: "-apiBase"), i + 1 < args.count { return args[i + 1] }
        return productionBase
    }

    /// 样本档只有首屏有真样本;别的页面据此明说「本页要联网」,
    /// 而不是转圈到超时(那看起来像服务端坏了)。
    static var isSample: Bool { ProcessInfo.processInfo.arguments.contains("-sample") }
}
