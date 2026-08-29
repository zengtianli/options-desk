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
