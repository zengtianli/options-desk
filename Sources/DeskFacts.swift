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

    /// 超额。首屏最重要的那一栏 —— 2026-08-29 回填完 qqq_close 之前它根本算不出来。
    var excess: Double { twrCumulative - qqqCumulative }

    /// 数据落后了几天(自然日)。用注入的 now,避免视图里直接摸系统时钟不好测。
    func stalenessDays(now: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: asof, to: now).day ?? 0)
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

    var headline: String {
        switch self {
        case .notConfigured:      return "还没接上数据源"
        case .network:            return "连不上盘面服务"
        case .http(_, let s, _):  return "服务返回 HTTP \(s)"
        case .decoding:           return "服务返回的数据对不上契约"
        case .empty:              return "服务返回了空序列"
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
        }
    }
}
