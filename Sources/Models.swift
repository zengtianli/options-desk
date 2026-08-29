import Foundation

// =============================================================================
// 服务端契约的消费端。**字段名照抄 JSON（snake_case）** —— 不做花式改名,
// 因为改名层本身就是一处会漂的判据:服务端加字段是向后兼容的,而一个手写的
// CodingKeys 表漏一行不会报错,只会让那个字段永远是 nil。
//
// 可能为 null 的一律 optional。**但该必需的绝不给默认值** —— 给了默认值,
// 「服务端没算出来」就会在界面上显示成「值是 0」,这个 app 反复栽的就是这种。
// =============================================================================

// MARK: - /api/portfolio

struct PortfolioResponse: Decodable {
    let totals: Totals
    let accounts: [AccountRow]
    let equity_positions: [EquityPosition]
    let option_positions: [OptionPosition]
    let meta: Meta

    struct Meta: Decodable {
        let asof: String?
        let asof_date: String?
        let staleness_days: Int?
        let is_stale: Bool?
        /// 覆盖式单快照 —— 只反映最近一次同步,不是历史序列。这句得原样印出来。
        let snapshot_note: String?
    }
    struct Totals: Decodable {
        let total_value: Double
        let equity_value: Double
        let options_value: Double
        let cash: Double
        let buying_power: Double
    }
    struct AccountRow: Decodable, Identifiable {
        let account: String
        let total_value: Double
        let equity_value: Double
        let options_value: Double
        let cash: Double
        let buying_power: Double
        var id: String { account }
    }
    struct EquityPosition: Decodable, Identifiable {
        let account: String
        let symbol: String
        let quantity: Double
        let average_buy_price: Double?
        let side: String?
        let mark: Double?
        let market_value: Double?
        var id: String { account + "/" + symbol }

        /// 浮盈浮亏。均价或现价缺一个就返回 nil —— 不拿 0 顶替。
        var unrealized: Double? {
            guard let a = average_buy_price, let m = mark else { return nil }
            return (m - a) * quantity
        }
        var unrealizedPct: Double? {
            guard let a = average_buy_price, a != 0, let m = mark else { return nil }
            return m / a - 1
        }
    }
    /// Hashable 是 navigationDestination(for:) 要的 —— 少了它点开详情页那行编译不过。
    struct OptionPosition: Decodable, Identifiable, Hashable {
        let account: String
        let option_id: String
        let symbol: String
        let side: String          // long / short
        let right: String         // call / put
        let strike: Double
        let expiration: String    // YYYY-MM-DD
        let quantity: Double
        let average_price: Double?
        let mark: Double?
        let iv: Double?
        let delta: Double?
        let theta: Double?
        let vega: Double?
        let open_interest: Double?
        let volume: Double?
        let quote_missing: Bool?
        var id: String { option_id }

        var isShort: Bool { side.lowercased() == "short" }
        /// 一张合约 100 股。名义市值 = mark × 100 × 张数。
        var notionalMark: Double? { mark.map { $0 * 100 * quantity } }
        var rightLabel: String { right.lowercased() == "call" ? "C" : "P" }
    }
}

// MARK: - /api/twr

struct TwrResponse: Decodable {
    let dates: [String]
    let cc: [Double?]
    let spy: [Double?]
    let qqq: [Double?]
    let tqqq: [Double?]
    let sessions: Int
    let sessions_awaiting_benchmark: Int?
    let flow_unknown_days: Int?
    /// **真正会污染收益率的是「链接」不是「天」** —— 窗口第一天的资金流只当分母基点,
    /// 不进任何一个链接。锚日 2026-07-09 恰好是那种情况:报「1 天未知」会让人以为
    /// 曲线不可信,而受影响的链接是 0 个。
    let flow_unknown_links: Int?
    let provisional: Bool?
    let asof: String?
}

// MARK: - /api/roll-signals

struct RollSignalsResponse: Decodable {
    let count: Int
    let signals: [Signal]
    let portfolio_asof: String?
    let credit_coverage: CreditCoverage?

    struct CreditCoverage: Decodable {
        let source: String?
        let count: Int?
        let first: String?
        let last: String?
        let missing_event_types: [String]?
        let fees_unavailable: Bool?
        let coverage_note: String?
    }
    struct Signal: Decodable, Identifiable {
        let action: String
        let reasons: [String]
        let ticker: String
        let underlying: String
        let underlying_price: Double?
        let strike: Double
        let exp: String
        let dte: Int
        let cp: String
        let qty: Double
        let price: Double?
        let delta: Double?
        let theta: Double?
        let iv: Double?
        let time_value: Double?
        let tv_annual_pct: Double?
        let tv_harvested_pct: Double?
        var id: String { ticker }

        /// 动作里带的 emoji 前缀是服务端给的强调,拿来判轻重比解析中文稳。
        var isUrgent: Bool { action.contains("⚠️") || action.contains("🚨") }
        var isRoll: Bool { action.contains("ROLL") }
    }
}

// MARK: - /api/harness

struct HarnessResponse: Decodable {
    let ok: Bool
    let severity: String?
    let message: String?
    let cc_dd_pct: Double?
    let qqq_dd_pct: Double?
    let spy_dd_pct: Double?
    let benchmark_dd_pct: Double?
    let benchmark_weights: [String: Double]?
    let headroom_pct: Double?
    let cc_peak: String?
    let cc_trough: String?
    let benchmark_peak: String?
    let benchmark_trough: String?
    let window: [String]?
    let sessions: Int?
    let cc_curve: String?
    let provisional: Bool?
    let provisional_reason: String?
    let flow_unknown_days: Int?
    let flow_unknown_links: Int?
    let as_of: String?
}

// MARK: - /api/perf-metrics

struct PerfMetricsResponse: Decodable {
    let start: String?
    let strategies: [Strategy]

    struct Strategy: Decodable, Identifiable {
        let label: String
        let annual_return: Double?
        let annual_vol: Double?
        let sharpe: Double?
        let sortino: Double?
        let max_drawdown: Double?
        let total_return: Double?
        let n: Int?
        let se_annual: Double?
        let se_sharpe: Double?
        /// σ 里含跨空洞的链接时，这两个字段把它的成分摊开。
        /// **`annual_vol` 本身不变** —— 剔掉接缝会让波动看起来更小，
        /// 那个方向的口径改动得由看的人自己决定，不由 app 替他做。
        let seam_variance_share: Double?
        let annual_vol_ex_seam: Double?
        let insufficient_sample: Bool?
        /// 样本不够时服务端**拒绝给点估计**,并把理由写在这里。这句必须原样显示 ——
        /// 只显示一个空白格会让人以为是 app 没解析出来。
        let sample_note: String?
        var id: String { label }
    }
}

// MARK: - /api/orders

struct OrdersResponse: Decodable {
    let count: Int
    let returned: Int
    let date: String?
    let orders: [Order]
    let coverage: Coverage?

    struct Coverage: Decodable {
        let missing_event_types: [String]?
        let fees_unavailable: Bool?
        let coverage_note: String?
    }
    struct Order: Decodable, Identifiable {
        let type: String              // BUY / SELL / OPTIONASSIGNMENT
        let trade_date: String
        let settlement_date: String?
        let price: Double?
        let units: Double?
        let amount: Double?
        let fee: Double?
        let option_symbol: OptionSymbol?
        let symbol: EquitySymbol?

        struct OptionSymbol: Decodable {
            let ticker: String?
            let strike_price: Double?
            let underlying_symbol: Underlying?
            struct Underlying: Decodable { let symbol: String? }
        }
        struct EquitySymbol: Decodable { let symbol: String? }

        /// 列表要稳定的 id。同一天同一腿可能有多笔成交,所以把价和量也拌进去。
        var id: String {
            [type, trade_date, option_symbol?.ticker ?? symbol?.symbol ?? "-",
             String(price ?? 0), String(units ?? 0), String(amount ?? 0)].joined(separator: "|")
        }
        var what: String {
            if let t = option_symbol?.ticker { return OrdersResponse.prettyOCC(t) }
            if let s = symbol?.symbol { return s }
            return "—"
        }
        var isAssignment: Bool { type == "OPTIONASSIGNMENT" }
    }

    /// OCC 代号 `QQQ   260828C00713000` → `QQQ 08-28 C713`。
    /// 原样印是给机器看的,一屏放不下也读不出来。
    static func prettyOCC(_ t: String) -> String {
        let s = t.replacingOccurrences(of: " ", with: "")
        // 尾部固定 15 位:YYMMDD(6) + C/P(1) + strike×1000 补零(8)
        guard s.count > 15 else { return t }
        let tail = String(s.suffix(15))
        let root = String(s.dropLast(15))
        let mm = tail.dropFirst(2).prefix(2), dd = tail.dropFirst(4).prefix(2)
        let cp = tail.dropFirst(6).prefix(1)
        let strikeRaw = Double(tail.suffix(8)) ?? 0
        let strike = strikeRaw / 1000
        let k = strike == strike.rounded() ? String(Int(strike)) : String(format: "%.1f", strike)
        return "\(root) \(mm)-\(dd) \(cp)\(k)"
    }
}

// MARK: - /api/exposure

/// 当前暴露。**数据源是覆盖式单快照**（rh_*_positions，distinct asof 恒为 1）——
/// 只回答「现在」，库里没有暴露的历史轨迹。所以这个响应不带序列，也别指望它带。
struct ExposureResponse: Decodable {
    let asof: String?
    let nlv: Double
    let cash: Double
    let margin_debt: Double
    let buying_power: Double
    let buying_power_ratio: Double?
    let equity_gross_notional: Double
    let equity_gross_ratio: Double?
    let net_delta_notional: Double
    let net_delta_ratio: Double?
    let concentration_symbol: String?
    let concentration_share: Double?
    let complete: Bool
    let incomplete_note: String?
    let underlyings: [Underlying]
    let settled_legs: [SettledLeg]
    let settled_note: String?
    let convention: String?

    struct Underlying: Decodable, Identifiable {
        let symbol: String
        let spot: Double?
        let equity_shares: Double
        let option_delta_shares: Double
        let net_delta_shares: Double
        let net_delta_notional: Double?
        let ratio_of_nlv: Double?
        let long_contracts: Double
        let short_contracts: Double
        let short_call_contracts: Double
        /// 空头 call 张数×100 ÷ 多头等价股数。1.0 = 刚好覆盖；>1 = 卖超了。
        /// **没有空头 call 时是 nil 而不是 0** —— 0% 会被读成「一张都没覆盖」。
        let short_call_coverage: Double?
        let delta_missing_legs: [String]
        let complete: Bool
        var id: String { symbol }
    }
    struct SettledLeg: Decodable, Identifiable {
        let symbol: String
        let right: String
        let strike: Double
        let expiration: String
        let side: String
        let quantity: Double
        var id: String { "\(symbol)\(expiration)\(right)\(strike)\(side)" }
    }
}

// MARK: - /api/vol-trend

/// 滚动年化波动率序列。**「波动少点」这个目标得能被看见才算数** ——
/// 只印一个当前值没法回答「在降还是在升」，所以这里是序列，不是一个数。
struct VolTrendResponse: Decodable {
    let window: Int
    let start: String
    let sessions: Int
    let dates: [String]
    /// 前 `window` 个点必然是 null（窗口还没填满）。**不是缺数据**，别当错误显示。
    let cc: [Double?]
    let qqq: [Double?]
    let cc_latest: Double?
    let qqq_latest: Double?
    let cc_prev: Double?
    let cc_prev_date: String?
    /// **线上那几个洞是这里造成的。** 跨越数据空洞的链接把多日涨跌压成「一天」，
    /// 含它的窗口一律不出值 —— 断开的线要能指出原因，否则只会被读成「数据缺了」。
    let seam_links: [SeamLink]
    let seam_note: String?
    let convention: String?
    let asof: String?

    struct SeamLink: Decodable, Identifiable {
        let from: String
        let to: String
        let biz_days: Int
        var id: String { from + "→" + to }
    }
}
