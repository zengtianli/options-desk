import Foundation

/// 首屏要显示的一组事实。**刻意不是 API 响应的镜像** —— 中间隔一层,
/// 服务端字段改名不会漫过整个视图层(接口契约还在动:stockoptions API 正在把数据源
/// 从停更的 JSON 换成 quant.db)。解码适配集中在 `FactsSource` 的实现里,只有那一处要改。
struct DeskFacts: Equatable {
    /// 数据本身的时间(不是拉取时间)。陈旧提示全靠它。
    let asof: Date
    /// 净值
    let nlv: Double
    /// 逐日链接 TWR 累计收益
    let twrCumulative: Double
    /// 同窗口 QQQ 买入持有
    let qqqCumulative: Double
    /// 参与链接的交易日数 —— **必须和收益同框显示**:
    /// 49 天的收益率和 3 年的收益率不是同一种东西,只印数字会骗人。
    let sampleDays: Int
    /// 合并进总账的账户
    let accounts: [String]
    /// 基准还没结算、因而被排出比较窗口的尾部 session 说明（没有就是 nil）。
    ///
    /// **不是装饰字段。** 收益率与基准必须是同一个窗口 —— 2026-08-29 独立复核发现
    /// 服务端曾把 TWR 算到最后一天、而基准只算到前一天，两个不同窗口的数并排印成
    /// 「我 vs QQQ 同窗口」，差 0.66pp 且毫无痕迹。现在服务端把两条一起截齐，
    /// 截掉了多少必须说出来，否则用户看到「样本 53 天」而数据到 08-28 会以为是漏了。
    let benchmarkLagNote: String?

    /// 超额的**有界区间** [下界, 上界]，来自 06-18 那笔已定性为「现金流出」但去向未定的钱。
    ///
    /// 为什么值得占一行：开放式的「暂定值」没法决策，区间可以。
    /// 已查实那笔钱确定不是亏掉的（该账户六月 realized 只有 −$2,686），
    /// 只剩「内部划转 vs 外部提现」两种可能，两端都算得出来，真值必落在中间。
    /// 首屏大字取的是**下界**（内部划转口径）—— 保守端。
    let excessRange: ClosedRange<Double>?

    /// 有多少个交易日的资金流(入金/出金)**没有记录**。
    ///
    /// 不是装饰字段。TWR 的分母是「期初市值 + 当日现金流」——
    /// 现金流缺一笔,那天的收益率就是错的,而且**错得毫无痕迹**:
    /// 一笔没记的入金会被当成投资赚来的钱。2026-08-29 实测 50 个交易日里有 17 天缺,
    /// 所以现在这个累计收益只能叫**暂定值**,不能叫结论。
    let flowUnknownDays: Int

    /// 现在的风险:暴露 + 波动。**null = 算不出来,不是「没有风险」** ——
    /// 算不出来的原因在 `riskError` 里,界面要把它印出来而不是让这块消失。
    let risk: DeskRisk?
    /// 风险块算不出来时的原因（服务端 `risk_error` 原文）。
    let riskError: String?

    /// 现金流完整吗。不完整时首屏那个大字必须自带保留。
    var flowComplete: Bool { flowUnknownDays == 0 }

    /// 超额。首屏最重要的那一栏 —— 2026-08-29 回填完 qqq_close 之前它根本算不出来。
    var excess: Double { twrCumulative - qqqCumulative }

    /// 数据落后了几天(自然日)。用注入的 now,避免视图里直接摸系统时钟不好测。
    func stalenessDays(now: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: asof, to: now).day ?? 0)
    }
}

/// 现在的风险 —— 首屏第三块。
///
/// **为什么它该在首屏。** 2026-08-29 用户定了新目标:「更谨慎、精准、对冲，让波动少点」。
/// 累计收益和超额是**结果**,今天做什么都改不了它们;能动手的旋钮只有两个 ——
/// **暴露多大**、**波动多大**。首屏只印结果,等于每天盯着一个自己当下改不了的数。
///
/// 三个比率故意分开,它们回答的不是同一个问题:
///   · `netDeltaRatio`     方向口径 —— 波动按它来(卖 call 覆盖掉的那部分不算暴露)
///   · `equityGrossRatio`  融资口径 —— 券商按它收保证金,和方向无关
///   · `buyingPowerRatio`  余量     —— 它见底才是真的动不了
/// 只报其中一个都会误导:只报融资口径像在说「你满仓杠杆」,只报方向口径像在说「你很轻」。
struct DeskRisk: Equatable {
    let netDeltaRatio: Double?
    let netDeltaNotional: Double?
    let equityGrossRatio: Double?
    let buyingPowerRatio: Double?
    let marginDebt: Double?
    let concentrationSymbol: String?
    let concentrationShare: Double?
    /// 滚动波动的窗口长度(交易日)。文案里要印出来 —— 「波动 13%」不说窗口等于没说。
    let volWindow: Int
    let volCC: Double?
    let volQQQ: Double?
    /// 整整一个窗口之前的同一指标 + 它的日期。**对照点不取前一天** ——
    /// 相邻两天的滚动 σ 差别几乎全是噪声,拿它说「在降」等于看噪声下结论。
    let volCCPrev: Double?
    let volCCPrevDate: String?
    /// 持仓快照的时间。**它和收益那几个数不是同一个时点** —— 收益读逐日序列,
    /// 暴露读覆盖式单快照。同框显示两个时间,免得有人拿上周的持仓解释今天的回撤。
    let exposureAsof: String?
    /// 有没有腿缺 delta / 缺标的现价。不完整时净 delta 是**低估**,必须说。
    let complete: Bool
    let incompleteNote: String?

    /// 波动在降还是在升。差额小于 1 个百分点当持平 —— 滚动 σ 本身的噪声就有这个量级。
    var volTrend: (arrow: String, text: String)? {
        guard let now = volCC, let prev = volCCPrev, let d = volCCPrevDate else { return nil }
        let delta = now - prev
        if abs(delta) < 0.01 {
            return ("arrow.right", String(format: "与一个窗口前持平（%@ %.1f%%）", d, prev * 100))
        }
        return (delta < 0 ? "arrow.down.right" : "arrow.up.right",
                String(format: "%@：一个窗口前是 %.1f%%（%@）",
                       delta < 0 ? "在降" : "在升", prev * 100, d))
    }
}

/// 陈旧程度分档。前身 cc-options 的死法是**安静地显示一个旧数字**三个月没人发现,
/// 所以这里没有「安静」这一档:超过阈值就必须在界面上刺眼。
enum Freshness {
    case fresh          // 当日/隔日
    case stale(Int)     // 落后了,但还能看
    case dead(Int)      // 链子大概率断了

    static func of(_ days: Int) -> Freshness {
        switch days {
        case ...2:  return .fresh
        case 3...7: return .stale(days)
        default:    return .dead(days)
        }
    }

    var isAlarming: Bool { if case .fresh = self { return false } else { return true } }
}

/// 取数失败。**每个 case 都要能指出下一步动作** ——
/// options-desk 的 CLAUDE.md 点名批评过姊妹 app 那条「解析失败」:
/// 既不像错误,也指不出方向。所以这里强制带上 `whatToDo`。
enum DeskError: Error, Equatable {
    case notConfigured(baseURL: String)
    case network(url: String, underlying: String)
    case http(url: String, status: Int, body: String)
    case decoding(url: String, field: String, detail: String)
    case empty(url: String)
    /// 被访问闸拦下。**必须单独一档** —— 它长得像成功（302 之后是登录页的 200 HTML），
    /// 混进 `.decoding` 就会显示成「服务返回的数据对不上契约」，把人引向服务端去查。
    case gate(url: String, reason: String)

    var headline: String {
        switch self {
        case .notConfigured:      return "还没接上数据源"
        case .network:            return "连不上盘面服务"
        case .http(_, let s, _):  return "服务返回 HTTP \(s)"
        case .decoding:           return "服务返回的数据对不上契约"
        case .empty:              return "服务返回了空序列"
        case .gate:               return "被访问闸拦住了"
        }
    }

    /// 出了什么事 —— 具体到 URL / 状态码 / 哪个字段,不给「失败了」这种废话。
    var detail: String {
        switch self {
        case .notConfigured(let base):
            return "base URL = \(base)"
        case .network(let url, let e):
            return "\(url)\n\(e)"
        case .http(let url, let s, let body):
            return "\(url)\n状态 \(s)\n\(body.prefix(300))"
        case .decoding(let url, let field, let detail):
            return "\(url)\n字段 `\(field)`\n\(detail)"
        case .empty(let url):
            return "\(url)\n返回 0 行 —— 空集不当成 0 收益显示"
        case .gate(let url, let reason):
            return "\(url)\n\(reason)"
        }
    }

    /// 下一步做什么。没有这一条的错误提示等于没提示。
    var whatToDo: String {
        switch self {
        case .notConfigured:
            return "装机时用 -gatepw 喂一次密码,或检查 API base URL 是否指向已上线的子域。"
        case .network:
            return "先确认手机联网;再确认 stockoptions 服务在 VPS 上是活的(它前身死过一次)。"
        case .http(_, let s, _):
            return s == 401 || s == 403
                ? "多半是 authgate 拦了 —— 凭证过期或没通过闸,重新走一次登录。"
                : "服务端错误,看 VPS 上该 service 的日志。"
        case .decoding(_, let field, _):
            return "服务端契约变了。对齐 `\(field)` 这个字段,别在客户端猜着容错。"
        case .empty:
            return "查 quant.db 的 rh_history 是不是空了 —— 空集报绿就是前身那种静默死法。"
        case .gate:
            return "把闸密码喂一次：Mac 上连着手机跑 `bash seed-gate.sh`（密码取自 macOS 钥匙串 tlz-gate，不进环境变量）。"
        }
    }
}
