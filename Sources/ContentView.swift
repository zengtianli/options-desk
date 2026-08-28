import SwiftUI

/// 首屏。**故意只有这一屏** —— `/appios` 硬约束:登录 + 一个主界面先装进模拟器看过,
/// 才允许写第 3 个界面。导航范式错了是 N 处返工,不是 1 处。
///
/// 放什么是算过的(2026-08-29 重核,见 CLAUDE.md「首屏放什么」):
/// **累计收益 + 对 QQQ 的超额 + 样本天数**,这三个稳、可解释。
/// 年化不在这儿 —— 194% 的点估计带着 ±85pp 的标准误,「194%」和「110%」统计上分不开,
/// 做成大字就是每天剧烈跳动且没有信息量。
struct ContentView: View {
    @State private var facts: DeskFacts?
    @State private var error: DeskError?
    @State private var loading = true

    let source: FactsSource
    /// 注入,便于把「陈旧」那条路径也截图看一眼。
    let now: Date

    init(source: FactsSource = SampleFactsSource(), now: Date = Date()) {
        self.source = source
        self.now = now
    }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if loading {
                        ProgressView().padding(.top, 60)
                    } else if let e = error {
                        ErrorCard(error: e)
                    } else if let f = facts {
                        FreshnessBanner(freshness: .of(f.stalenessDays(now: now)), asof: f.asof)
                        HeroCard(facts: f)
                        ExcessCard(facts: f)
                        FootnoteCard(facts: f)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.light)   // 全局约定:一律亮色
        .task { await reload() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("投资盘面").font(.largeTitle.weight(.bold))
            Spacer()
            Text("只读").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.06)))
        }
        .padding(.top, 8)
    }

    private func reload() async {
        loading = true
        switch await source.load() {
        case .success(let f): facts = f; error = nil
        case .failure(let e): error = e; facts = nil
        }
        loading = false
    }
}

// ── 配色:亮色一档,不跟随系统深色 ────────────────────────────────────────────
enum Palette {
    static let bg     = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let card   = Color.white
    static let gain   = Color(red: 0.06, green: 0.55, blue: 0.38)
    static let loss   = Color(red: 0.78, green: 0.20, blue: 0.18)
    static let alarm  = Color(red: 0.85, green: 0.33, blue: 0.05)
    static let ink    = Color(red: 0.11, green: 0.12, blue: 0.14)
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
    }
}

/// 陈旧提示。前身 cc-options 死于「安静地显示一个旧数字」三个月没人发现,
/// 所以这条在数据新鲜时也**不隐藏**,只是不报警 —— 让人习惯它在哪,坏的那天才会注意到它变色。
private struct FreshnessBanner: View {
    let freshness: Freshness
    let asof: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                // **按市场时区显示,不按手机时区。** asof 是美股收盘时刻,
                // 渲成本机时间会平移一天(08-27 16:00 EDT → 上海 08-28 04:00),
                // 让人以为数据比实际新一天 —— 这个 app 的全部意义就是不让人误判数据新旧。
                Text("数据时间 \(Self.marketTime.string(from: asof))")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundStyle(freshness.isAlarming ? Color.white : Palette.ink.opacity(0.7))
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(freshness.isAlarming ? Palette.alarm : Color.black.opacity(0.05)))
    }

    /// 交易所时区。
    ///
    /// **这是 tz-guard 的真例外,理由:** 这里要显示的不是「本地时间」,而是
    /// **美股收盘时刻**——一个领域常量。NYSE/NASDAQ 收在 America/New_York,
    /// 跟这台 Mac 的系统时区、跟用户人在哪都没关系(这个 app 装在手机上,
    /// 会跟着人飞到任何时区)。走 systime.py 那套「系统时区」在这里反而是错的:
    /// 它会让同一笔收盘数据在不同手机上显示成不同日期。
    /// 带 ET 后缀,让人一眼知道这不是本地时间。
    static let marketTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd HH:mm 'ET'"
        return f
    }()

    private var icon: String {
        switch freshness {
        case .fresh: return "checkmark.seal"
        case .stale: return "exclamationmark.triangle.fill"
        case .dead:  return "xmark.octagon.fill"
        }
    }
    private var title: String {
        switch freshness {
        case .fresh:          return "数据是新的"
        case .stale(let d):   return "数据落后 \(d) 天 —— 同步可能断了"
        case .dead(let d):    return "数据落后 \(d) 天 —— 这条链大概率已经死了"
        }
    }
}

private struct HeroCard: View {
    let facts: DeskFacts
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("累计收益").font(.subheadline).foregroundStyle(.secondary)
                Text(pct(facts.twrCumulative))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(facts.twrCumulative >= 0 ? Palette.gain : Palette.loss)
                // 样本天数**必须和收益同框** —— 49 天的 23% 和 3 年的 23% 不是一回事。
                Text("逐日链接 TWR · \(facts.sampleDays) 个交易日")
                    .font(.caption).foregroundStyle(.secondary)
                // 现金流不全 → 这个数是暂定值,必须当场说,不能等人去翻脚注。
                // 一笔没记的入金会被算成投资赚来的钱,而且错得毫无痕迹。
                if !facts.flowComplete {
                    Label("暂定值：\(facts.flowUnknownDays) 个交易日的资金流未记录",
                          systemImage: "questionmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.alarm)
                        .padding(.top, 2)
                }
                Divider().padding(.vertical, 4)
                HStack {
                    Text("净值").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(usd(facts.nlv)).font(.title3.weight(.semibold).monospacedDigit())
                }
            }
        }
    }
}

/// 首屏最重要的一栏。回填 qqq_close 之前它是空的 —— 那正是「先修口径再建界面」的理由。
private struct ExcessCard: View {
    let facts: DeskFacts
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("对 QQQ 的超额").font(.subheadline).foregroundStyle(.secondary)
                Text(pp(facts.excess))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(facts.excess >= 0 ? Palette.gain : Palette.loss)
                HStack(spacing: 0) {
                    leg("我", facts.twrCumulative)
                    Divider().frame(height: 32)
                    leg("QQQ 同窗口", facts.qqqCumulative)
                }
            }
        }
    }
    private func leg(_ label: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(pct(v)).font(.headline.monospacedDigit())
                .foregroundStyle(v >= 0 ? Palette.gain : Palette.loss)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 口径脚注。报任何合计都要标口径 —— 数的是什么、不含什么。
private struct FootnoteCard: View {
    let facts: DeskFacts
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("口径").font(.subheadline.weight(.semibold))
                row("账户", facts.accounts.joined(separator: " + ") + "（合并总账）")
                row("收益", "逐日链接 TWR，当日现金流计入期初基数")
                row("基准", "QQQ 买入持有，同一窗口")
                row("不含", "年化 / Sharpe —— 样本只有 \(facts.sampleDays) 天，误差带比数本身还宽")
                if !facts.flowComplete {
                    row("存疑", "\(facts.flowUnknownDays) 天 net_deposit 缺记录；已知悬案 2026-06-18 一笔 $35,939，"
                             + "内部划转还是提现未定 —— 定性为提现则累计收益更高，不更低")
                }
            }
        }
    }
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Text(v).font(.caption).foregroundStyle(Palette.ink.opacity(0.8))
        }
    }
}

/// 错误呈现。**三段式:出了什么事 / 具体是什么 / 下一步做什么。**
/// 姊妹 app 那条只有一句「解析失败」的错误条是反面教材:既不像错误,也指不出方向。
private struct ErrorCard: View {
    let error: DeskError
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(error.headline, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline).foregroundStyle(Palette.alarm)
                Text(error.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)      // 能复制出来才查得下去
                Divider()
                Label(error.whatToDo, systemImage: "arrow.turn.down.right")
                    .font(.footnote).foregroundStyle(Palette.ink)
            }
        }
    }
}

// ── 格式化 ────────────────────────────────────────────────────────────────
private func pct(_ v: Double) -> String { String(format: "%+.2f%%", v * 100) }
private func pp(_ v: Double)  -> String { String(format: "%+.2fpp", v * 100) }
private func usd(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}
