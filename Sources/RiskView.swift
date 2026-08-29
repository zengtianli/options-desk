import SwiftUI
import Charts

// =============================================================================
// 风控 —— 回撤硬约束 + 绩效指标。
//
// 这一页存在的理由:2026-08-29 把 `/api/harness` 接到真数据上之后,**硬约束是破的**。
// 在此之前这个端点连着停更的 JSON、返回一堆 0 并且 HTTP 200 ——
// 这条破裂**在三个月里一直存在、一直没人看见**。绿着的时候也照样显示:
// 只在出事时才出现的东西,出事那天没人认得它。
//
// ⚠ **2026-08-29 重做呈现。** 原来这页是四段一模一样的「拒绝给出点估计」,
//   用户原话「就我不想看到这些了」「要做就做真实的」。他是对的,而且问题在服务端:
//   `_curve_metrics` 样本 <119 时把六个指标**全部**抹成 None —— 连累计收益和最大回撤
//   这种**不含任何年化外推的路径统计量**也一起抹了。现在服务端全都算,
//   年化/Sharpe 带 ± 一起给。**一个带误差带的数能拿来决策,一句「拒绝给出点估计」不能。**
//
// ⚠ **2026-08-29 二次订正:窗口从锚日改回全窗口**(DeskWindow.riskQuery)。
//   当天早些时候统一到锚日是对的 —— 那时全窗口只有 53 个 session 且有 18 天资金流未记录。
//   **这两条前提当天就没了**:序列补到 400 个 session、资金流全窗口逐日已知。
//   再拿 35 个链接算年化和 Sharpe 就是白扔九成样本(Sharpe 标准误 ±0.80 → ±0.08)。
//   换窗口**不是**为了让结论变好看:回撤硬约束在两个窗口下都是破的
//   (全窗口 −32.11% vs 基准 −21.72%;锚日 −9.62% vs −7.17%),没有能挑的绿窗口。
//   记分板(曲线页)仍然锚在 2026-07-09 —— 那是**系列属性**,要和已发布的图可比。
//
// ⚠ **2026-08-29 再加两块:当前暴露 + 波动趋势。** 用户定了新目标
//   (「更谨慎、精准、对冲,让波动少点」),而在此之前这一页只有**已经发生的统计**。
//   回撤和 Sharpe 是记分,暴露和波动才是今天能拧的旋钮 —— 所以它们排在最前面。
// =============================================================================

struct RiskView: View {
    /// `-riskOnly exposure|vol|harness|perf` —— **只为截图存在**，同 `-tab` / `-range`。
    /// 这一页有四张卡、比一屏长得多，后两张在模拟器上根本截不到。没有这个开关，
    /// 「下面那两张渲染对不对」就只能靠「编译过了」来相信 —— 而这个 app 栽过的坑
    /// (指数当分数、date 参数被静默忽略、样条画出不存在的起伏) 全都编译得过。
    private static let only: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-riskOnly"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    private static func show(_ key: String) -> Bool { only == nil || only == key }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        // 顺序 = 「今天能动手的」在前,「已经发生的统计」在后。
                        // 暴露和波动是旋钮,回撤和 Sharpe 是记分 —— 把记分放前面
                        // 会让这页读起来像成绩单,而它该是仪表盘。
                        if Self.show("exposure") {
                            Loader<ExposureResponse, AnyView>("/api/exposure") { e in
                                AnyView(VStack(spacing: 14) { exposure(e); ladder(e) })
                            }
                        }
                        if Self.show("vol") {
                            Loader<VolTrendResponse, AnyView>("/api/vol-trend?window=20") { v in
                                AnyView(volCard(v))
                            }
                        }
                        if Self.show("harness") {
                            Loader<HarnessResponse, AnyView>("/api/harness" + DeskWindow.riskQuery) { h in
                                AnyView(VStack(spacing: 14) { verdict(h); detail(h) })
                            }
                        }
                        if Self.show("perf") {
                            Loader<PerfMetricsResponse, AnyView>("/api/perf-metrics" + DeskWindow.riskQuery) { m in
                                AnyView(metrics(m))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationTitle("风控")
        }
    }

    // MARK: 当前暴露（今天就能动手的那两个旋钮之一）

    /// **三个比率并排,因为它们回答的不是同一个问题。**
    /// 只报融资杠杆像在说「你满仓」,只报净 delta 像在说「你很轻」——
    /// 一个卖 call 覆盖住的仓,融资口径 2.5× 而方向口径可能只有 0.77×,两个都对。
    private func exposure(_ e: ExposureResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("当前暴露").font(.subheadline.weight(.semibold))
                    Spacer()
                    // 这一块和下面几块**不是同一个时点**:暴露是覆盖式单快照,
                    // 回撤/绩效是 400 个 session 的序列。不写出来会有人拿它们互相解释。
                    Text(e.asof.flatMap { String($0.prefix(10)) } ?? "—")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    stat("净暴露", e.net_delta_ratio.map { String(format: "%.2f×", $0) },
                         sub: usd(e.net_delta_notional))
                    Divider().frame(height: 40)
                    stat("融资杠杆", e.equity_gross_ratio.map { String(format: "%.2f×", $0) },
                         sub: usd(e.equity_gross_notional))
                    Divider().frame(height: 40)
                    stat("余量", e.buying_power_ratio.map { String(format: "%.1f%%", $0 * 100) },
                         sub: usd(e.buying_power),
                         warn: (e.buying_power_ratio ?? 1) < 0.05)
                }
                Divider()
                KV(k: "融资负债", v: usd(e.margin_debt), mono: true)
                if let sym = e.concentration_symbol, let sh = e.concentration_share {
                    KV(k: "集中度", v: String(format: "%@ 占净暴露 %.0f%%", sym, sh * 100), mono: true)
                }
                if let c = e.convention {
                    Text(c).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 缺 delta 的腿被排除在外 —— 那让暴露看起来**更小**,错在最舒服的一侧。
                if !e.complete, let note = e.incomplete_note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let n = e.settled_note {
                    // 静默丢弃已结算的腿和「漏算了几条腿」长得一模一样,所以说出来。
                    Text(n).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ label: String, _ v: String?, sub: String, warn: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v ?? "—").font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(warn ? Palette.alarm : Palette.ink)
            Text(sub).font(.caption2.monospacedDigit()).foregroundStyle(.secondary.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    /// 逐标的拆开。合计能说「我扛着 0.77 倍」,拆开才能说「其中 93% 是同一个标的」。
    private func ladder(_ e: ExposureResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("按标的").font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text("").frame(width: 46, alignment: .leading)
                    Text("净Δ股数").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("名义").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("占NLV").frame(maxWidth: .infinity, alignment: .trailing)
                    Text("覆盖").frame(width: 46, alignment: .trailing)
                }
                .font(.caption2).foregroundStyle(.secondary)
                ForEach(e.underlyings) { u in
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(u.symbol).font(.caption.weight(.semibold))
                                .frame(width: 46, alignment: .leading)
                            Text(String(format: "%+.0f", u.net_delta_shares))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(u.net_delta_shares >= 0 ? Palette.gain : Palette.loss)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(u.net_delta_notional.map { usd($0) } ?? "—")
                                .font(.caption.monospacedDigit())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(u.ratio_of_nlv.map { String(format: "%.2f×", $0) } ?? "—")
                                .font(.caption.monospacedDigit())
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            // 覆盖率 >1 = 卖超了,裸的那部分是真敞口 —— 染色。
                            Text(u.short_call_coverage.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle((u.short_call_coverage ?? 0) > 1.0 ? Palette.alarm : .secondary)
                                .frame(width: 46, alignment: .trailing)
                        }
                        Text(String(format: "股票 %+.0f 股 · 期权Δ %+.0f 股 · 空头 %.0f 张 / 多头 %.0f 张",
                                    u.equity_shares, u.option_delta_shares,
                                    u.short_contracts, u.long_contracts))
                            .font(.caption2).foregroundStyle(.secondary.opacity(0.85))
                        if !u.delta_missing_legs.isEmpty {
                            Text("缺 delta：" + u.delta_missing_legs.joined(separator: "、"))
                                .font(.caption2).foregroundStyle(Palette.alarm)
                        }
                    }
                    .padding(.vertical, 1)
                }
                Divider()
                Text("覆盖 = 空头 call 股数 ÷ 多头等价股数（股票 + 多头 call 的 Δ 股）。"
                     + "100% 刚好覆盖；超过 100% 的那部分是裸的。没有空头 call 时不显示。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 波动趋势（另一个旋钮）

    /// **「波动少点」这个目标得能被看见才算数。** 只印一个当前值回答不了「在降还是在升」,
    /// 所以这里是序列。前 20 个点没有值是窗口没填满,不是缺数据。
    private func volCard(_ v: VolTrendResponse) -> some View {
        // **按空洞切成段。** compactMap 掉 nil 再一条线连起来,Charts 会在洞的两端
        // 拉一条笔直的斜线 —— 那条线上每一个像素都是数据里没有的东西,而它看起来
        // 和真数据一模一样(2026-08-29 实测:挡掉 75% 假尖峰之后,洞被一条直线补上了,
        // 图看着更「干净」了)。所以断的地方必须真断:每一段自己一个 series。
        let seg: (_ xs: [Double?]) -> [[(Date, Double)]] = { xs in
            var out: [[(Date, Double)]] = []
            var cur: [(Date, Double)] = []
            for (i, d) in v.dates.enumerated() {
                guard i < xs.count, let y = xs[i], let day = exchangeYMD.date(from: d) else {
                    if !cur.isEmpty { out.append(cur); cur = [] }
                    continue
                }
                cur.append((day, y * 100))
            }
            if !cur.isEmpty { out.append(cur) }
            return out
        }
        let mine = seg(v.cc), bench = seg(v.qqq)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(v.window) 日滚动波动").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(v.dates.first ?? "") ~ \(v.dates.last ?? "")")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    stat("我", v.cc_latest.map { String(format: "%.1f%%", $0 * 100) },
                         sub: trendSub(v),
                         warn: (v.cc_latest ?? 0) > (v.qqq_latest ?? .infinity))
                    Divider().frame(height: 40)
                    stat("QQQ", v.qqq_latest.map { String(format: "%.1f%%", $0 * 100) }, sub: "同窗口")
                }
                Chart {
                    // `series:` 每段一个不同的值 —— 少了它 Charts 把几段并成一条,
                    // 洞就又被直线补上了(这正是这一版要修的那个东西)。
                    ForEach(Array(bench.enumerated()), id: \.offset) { k, run in
                        ForEach(run, id: \.0) { d, y in
                            LineMark(x: .value("日期", d), y: .value("波动", y),
                                     series: .value("系列", "QQQ-\(k)"))
                                .foregroundStyle(.gray)
                                .lineStyle(StrokeStyle(lineWidth: 1.6))
                                .interpolationMethod(.linear)
                        }
                    }
                    ForEach(Array(mine.enumerated()), id: \.offset) { k, run in
                        ForEach(run, id: \.0) { d, y in
                            LineMark(x: .value("日期", d), y: .value("波动", y),
                                     series: .value("系列", "我-\(k)"))
                                .foregroundStyle(Palette.gain)
                                .lineStyle(StrokeStyle(lineWidth: 2.4))
                                .interpolationMethod(.linear)
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { m in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = m.as(Double.self) {
                                Text(String(format: "%.0f%%", d)).font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { m in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = m.as(Date.self) {
                                Text(d.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 170)
                HStack(spacing: 12) {
                    legendDot(Palette.gain, "我（TWR，已剔资金流）")
                    legendDot(.gray, "QQQ")
                }
                // 断开的线必须自带解释。**一个看得见的洞会让人去问为什么,
                // 一个假尖峰不会** —— 挡掉之前这里是个 75% 的尖峰,有形状、有平台,
                // 看起来完全像真的。
                if let n = v.seam_note {
                    Label(n, systemImage: "scissors")
                        .font(.caption).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let c = v.convention {
                    Text(c).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 对照点是**整整一个窗口之前**的那个值,不是昨天 ——
    /// 相邻两天的滚动 σ 差别几乎全是噪声,拿它说趋势等于看噪声下结论。
    private func trendSub(_ v: VolTrendResponse) -> String {
        guard let now = v.cc_latest, let prev = v.cc_prev, let d = v.cc_prev_date else {
            return "无对照点"
        }
        if abs(now - prev) < 0.01 { return String(format: "持平（%@ %.1f%%）", d, prev * 100) }
        return String(format: "%@ %@ 的 %.1f%%", now < prev ? "↓ 自" : "↑ 自", d, prev * 100)
    }

    private func legendDot(_ c: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 硬约束

    private func verdict(_ h: HarnessResponse) -> some View {
        let bad = !h.ok
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: bad ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                        .foregroundStyle(bad ? Palette.alarm : Palette.gain)
                    Text(bad ? "回撤硬约束：破裂" : "回撤硬约束：满足")
                        .font(.headline).foregroundStyle(bad ? Palette.alarm : Palette.gain)
                    Spacer()
                    if let w = h.window, w.count == 2 {
                        // 回撤是路径统计量,换窗口就换了答案 —— 窗口必须和结论同框,
                        // 否则「破没破」会脱离它成立的那段时间。
                        Text("\(w[0]) ~ \(w[1])")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 0) {
                    leg("我", h.cc_dd_pct)
                    Divider().frame(height: 34)
                    leg("加权基准", h.benchmark_dd_pct)
                    Divider().frame(height: 34)
                    leg("余量", h.headroom_pct)
                }
                if let m = h.message {
                    Text(m).font(.caption).foregroundStyle(Palette.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func leg(_ label: String, _ v: Double?) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v.map { pct($0) } ?? "—")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle((v ?? 0) < 0 ? Palette.loss : Palette.gain)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ h: HarnessResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("怎么算的").font(.subheadline.weight(.semibold))
                if let w = h.benchmark_weights {
                    let s = w.sorted { $0.key < $1.key }
                        .map { "\($0.key.uppercased()) \(Int($0.value * 100))%" }.joined(separator: " + ")
                    KV(k: "基准", v: s)
                }
                if let c = h.cc_curve { KV(k: "我这条", v: c) }
                if let p = h.cc_peak, let t = h.cc_trough { KV(k: "我的峰谷", v: "\(p) → \(t)", mono: true) }
                if let p = h.benchmark_peak, let t = h.benchmark_trough {
                    KV(k: "基准峰谷", v: "\(p) → \(t)", mono: true)
                }
                KV(k: "QQQ 回撤", v: h.qqq_dd_pct.map { pct($0) } ?? "—", mono: true)
                KV(k: "SPY 回撤", v: h.spy_dd_pct.map { pct($0) } ?? "—", mono: true)
                if let n = h.sessions { KV(k: "样本", v: "\(n) 个 session", mono: true) }
                // **只在真的成立时才出现。** 判据是受影响的链接数,不是「有几天没记录」——
                // 窗口首日的资金流只当分母基点,不进任何链接。
                if h.provisional == true, let r = h.provisional_reason {
                    Divider()
                    Label(r, systemImage: "questionmark.circle.fill")
                        .font(.caption).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 绩效指标（表，不是四段解释）

    private func metrics(_ m: PerfMetricsResponse) -> some View {
        let n = m.strategies.first?.n
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("绩效指标").font(.subheadline.weight(.semibold))
                    Spacer()
                    if let n { Text("n=\(n)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                }
                header
                ForEach(m.strategies) { s in
                    Divider()
                    row(s)
                }
                Divider()
                // 一句,不是每条策略各来一段。
                // ⚠ **别用 `+` 拼这一句。** `Text("a" + "b")` 的实参类型是 String,
                // 走的是 `Text(_: StringProtocol)` 那个重载 —— **不渲染 markdown**,
                // 于是 `**路径事实**` 会带着四个星号原样印在屏幕上(2026-08-29 截图实见)。
                // 只有**单个字面量**才会走 `Text(_: LocalizedStringKey)`。
                Text("累计与回撤是这段窗口里的**路径事实**，不含年化外推；年化含均值外推，后面的 ± 是一倍标准误。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 四行的 ± 几乎一样,看着像 bug,其实不是 —— 值得写一句,
                // 否则下次看到的人会去查一个没坏的东西。
                // 四行的 ± 几乎一样,看着像 bug,其实不是 —— 值得写一句,
                // 否则下次看到的人会去查一个没坏的东西。数是**算出来的**,不写死:
                // 写死的 "n=399" 明天就过期,而它过期时看不出来。
                if let n, n > 0 {
                    Text(String(format: "四行的 Sharpe ± 几乎相同不是 bug：样本一样长时它主要由 n 决定"
                                + "（≈√(252/n)），与 Sharpe 本身几乎无关 —— n=%d 时约 ±%.2f。"
                                + "换句话说这段样本还分不开这几条谁的风险调整后收益更高。",
                                n, (252.0 / Double(n)).squareRoot()))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 接缝披露:**不改上面那个 σ**,只把它的成分摊开。
                // 剔掉接缝会让波动看起来更小 —— 那是「让数字变好看」的方向,
                // 该由看的人自己决定要不要那么读,不由 app 替他决定。
                if let s = m.strategies.first,
                   let share = s.seam_variance_share, share >= 0.05,
                   let ex = s.annual_vol_ex_seam, let vol = s.annual_vol {
                    Text(String(format: "⚠︎ 我这条的波动里有 %.0f%% 的方差来自一条跨空洞的链接"
                                + "（2026-05-22~06-08 无快照，多日涨跌被压成「一天」）："
                                + "%.1f%% 是含它的，剔掉它是 %.1f%%。",
                                share * 100, vol * 100, ex * 100))
                        .font(.caption2).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("").frame(width: 58, alignment: .leading)
            cell("累计"); cell("回撤"); cell("波动"); cell("年化")
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func cell(_ s: String) -> some View {
        Text(s).frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func row(_ s: PerfMetricsResponse.Strategy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(s.label).font(.caption.weight(.medium))
                    .frame(width: 58, alignment: .leading)
                num(s.total_return); num(s.max_drawdown); num(s.annual_vol, signed: false)
                num(s.annual_return)
            }
            if let se = s.se_annual, let sh = s.sharpe {
                HStack(spacing: 6) {
                    Text("").frame(width: 58)
                    Text("Sharpe \(fmt2(sh))\(s.se_sharpe.map { " ±\(fmt2($0))" } ?? "")")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("年化 ±" + String(format: "%.2f%%", se * 100))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.caption2).foregroundStyle(.secondary.opacity(0.9))
            }
        }
        .padding(.vertical, 1)
    }

    private func num(_ v: Double?, signed: Bool = true) -> some View {
        Text(v.map { signed ? pct($0) : String(format: "%.1f%%", $0 * 100) } ?? "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(v == nil ? .secondary
                             : (!signed ? Palette.ink.opacity(0.8)
                                : ((v ?? 0) >= 0 ? Palette.gain : Palette.loss)))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func fmt2(_ v: Double) -> String { String(format: "%.2f", v) }
}
