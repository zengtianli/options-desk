import SwiftUI

/// 首屏。(`/appios` 那条「先跑一屏再铺开」是**门槛不是终点**,五页已于 2026-08-29 铺开。)
///
/// 放什么是算过的(见 CLAUDE.md「首屏放什么」):**累计收益 + 对 QQQ 的超额 + 现在的风险**。
/// 年化不在这儿 —— 点估计带着一倍标准误就有 ±21pp,做成大字每天剧烈跳动且没有信息量;
/// 它在风控页,旁边印着标准误。
///
/// 第三块是 2026-08-29 加的。前两块都是**结果**,今天做什么都改不了它们;
/// 能动手的旋钮只有暴露和波动这两个。首屏只印结果 = 每天盯着一个自己当下改不了的数。
struct ContentView: View {
    @State private var facts: DeskFacts?
    @State private var error: DeskError?
    @State private var loading = true

    let source: FactsSource
    /// 注入,便于把「陈旧」那条路径也截图看一眼。
    let now: Date

    init(source: FactsSource = FactsSourceFactory.make(), now: Date = Date()) {
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
                        FreshnessBanner(freshness: f.freshness(now: now), asof: f.asof)
                        HeroCard(facts: f)
                        ExcessCard(facts: f)
                        RiskCard(risk: f.risk, error: f.riskError)
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

struct Card<Content: View>: View {
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
struct FreshnessBanner: View {
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
        case .fresh:
            return "数据是新的"
        case .stale(let n, let u):
            // 「下一步做什么」得写在提示里 —— 只说「旧了」的提示等于没提示。
            return "数据落后 \(n) \(u.label) —— 日常链可能断了（本机 launchd + VPS 定时器）"
        case .dead(let n, let u):
            return "数据落后 \(n) \(u.label) —— 这条链大概率已经死了，去看 ~/Library/Logs/tlz-optionsdesk-daily.log"
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
                Text("逐日链接 TWR · \(facts.sampleDays) 个交易日（\(max(0, facts.sampleDays - 1)) 个链接）")
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
                // 区间比「暂定值」有用:开放式的不确定没法决策,区间可以。
                // 大字取下界(保守端),这里说清另一端在哪、以及区间从哪来。
                if let r = facts.excessRange {
                    Label("区间 \(pp(r.lowerBound)) ~ \(pp(r.upperBound))　"
                          + "（2026-06-18 一笔 $35,939 已确认是现金流出，去向未定；大字取保守端）",
                          systemImage: "arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(Palette.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
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

/// 现在的风险。**这一块回答「我现在扛着多少」,不回答「我赚了多少」。**
///
/// 为什么和收益分开印:收益读的是逐日序列(rh_history,400 个 session),
/// 暴露读的是覆盖式单快照(rh_*_positions,只有「现在」)。两个时点不同 ——
/// 所以这张卡自带自己的时间戳,免得有人拿上周的持仓解释今天的回撤。
private struct RiskCard: View {
    let risk: DeskRisk?
    let error: String?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("现在的风险").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let a = risk?.exposureAsof, let d = Self.parse(a) {
                        Text("持仓 " + FreshnessBanner.marketTime.string(from: d))
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let r = risk {
                    body(r)
                } else {
                    // **算不出来 ≠ 没有风险。** 这一块消失掉才是最坏的显示方式:
                    // 界面看起来干干净净,而实际是暴露没人算。
                    Label("暴露/波动这次没算出来", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.alarm)
                    Text(error ?? "服务端没给 risk 块，也没给原因 —— 这两种情况都要查服务端。")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func body(_ r: DeskRisk) -> some View {
        HStack(spacing: 0) {
            ratio("净暴露", r.netDeltaRatio, suffix: "×", hint: "方向")
            Divider().frame(height: 38)
            ratio("融资杠杆", r.equityGrossRatio, suffix: "×", hint: "保证金")
            Divider().frame(height: 38)
            ratio("余量", r.buyingPowerRatio, suffix: "%", scale: 100,
                  hint: "购买力/NLV", warnBelow: 0.05)
        }
        Divider()
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(r.volWindow) 日波动").font(.caption).foregroundStyle(.secondary)
            Spacer()
            volLeg("我", r.volCC, tint: tint(mine: r.volCC, bench: r.volQQQ))
            volLeg("QQQ", r.volQQQ, tint: Palette.ink.opacity(0.7))
        }
        if let t = r.volTrend {
            Label(t.text, systemImage: t.arrow)
                .font(.caption)
                .foregroundStyle(t.arrow == "arrow.down.right" ? Palette.gain
                                 : (t.arrow == "arrow.up.right" ? Palette.alarm : .secondary))
        }
        if let sym = r.concentrationSymbol, let share = r.concentrationShare {
            Text(String(format: "集中度：%@ 占净暴露 %.0f%%", sym, share * 100))
                .font(.caption).foregroundStyle(Palette.ink.opacity(0.75))
        }
        // 缺 delta 的腿被排除在净 delta 之外 —— 那让暴露看起来**更小**,
        // 也就是错在最舒服的那一侧。所以这条必须刺眼。
        if !r.complete, let note = r.incompleteNote {
            Label(note, systemImage: "questionmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(Palette.alarm)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 我的波动低于基准染绿、高于染橙。**这不是「好/坏」的判断** ——
    /// 是「离目标近了还是远了」,而目标是用户自己定的:波动少点。
    private func tint(mine: Double?, bench: Double?) -> Color {
        guard let m = mine, let b = bench else { return Palette.ink.opacity(0.8) }
        return m <= b ? Palette.gain : Palette.alarm
    }

    private func ratio(_ label: String, _ v: Double?, suffix: String,
                       scale: Double = 1, hint: String, warnBelow: Double? = nil) -> some View {
        let warn = (warnBelow != nil && v != nil && v! < warnBelow!)
        return VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v.map { String(format: suffix == "%" ? "%.1f%%" : "%.2f×", $0 * scale) } ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(warn ? Palette.alarm : Palette.ink)
            Text(hint).font(.caption2).foregroundStyle(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    private func volLeg(_ label: String, _ v: Double?, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v.map { String(format: "%.1f%%", $0 * 100) } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }

    private static func parse(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso) ?? {
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: iso)
        }()
    }
}

/// 口径脚注。报任何合计都要标口径 —— 数的是什么、不含什么。
private struct FootnoteCard: View {
    let facts: DeskFacts
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("口径").font(.subheadline.weight(.semibold))
                // 2026-08-29：口径从「两户合并」收成单户 —— 700013444 已按用户钦定移出。
                // 那个户 06-09 开、06-22 归零，整段生命都落在数据最脏的窗口里。
                row("账户", facts.accounts.joined(separator: " + ")
                          + (facts.accounts.count > 1 ? "（合并总账）" : "（单账户）"))
                row("收益", "逐日链接 TWR，当日现金流计入期初基数")
                row("基准", "QQQ 买入持有，同一窗口")
                // 这一行以前写「样本只有 N 天，所以不放年化」。序列补到 400 天之后
                // 那个理由不成立了 —— 现在不放首屏是因为**首屏只放三个数**，
                // 不是因为算不出来。算得出来，在风控页，带标准误。
                row("不含", "年化 / Sharpe / 回撤 —— 都在「风控」页，那里同时印标准误和样本长度")
                if !facts.flowComplete {
                    row("存疑", "\(facts.flowUnknownDays) 天 net_deposit 缺记录 —— "
                             + "一笔没记的入金会被算成投资赚来的钱，且错得毫无痕迹")
                } else {
                    // 2026-08-29 起这条是绿的。值得占一行 —— 它是这个数能不能当结论的前提，
                    // 而且它曾经**不成立**（六月的到期指派没进库，18 天的资金流因此算不出来）。
                    row("资金流", "全窗口逐日已知（现金恒等式反算 + 对账守卫判红 0 组）")
                }
                // 收益率与基准必须同窗口。截掉了尾巴就得说出来，否则「样本 53 天」
                // 配上「数据时间 08-28」看着像漏了一天。
                if let note = facts.benchmarkLagNote {
                    row("窗口", note)
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
struct ErrorCard: View {
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
func pct(_ v: Double) -> String { String(format: "%+.2f%%", v * 100) }
func pp(_ v: Double)  -> String { String(format: "%+.2fpp", v * 100) }
func usd(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}
