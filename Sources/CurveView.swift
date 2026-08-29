import SwiftUI
import Charts

// =============================================================================
// 曲线 —— 记分板:我 vs QQQ,锚日 = 100。
//
// **锚日固定 2026-07-09**,和博客那条记分板折线同一个锚
// (`~/investment/options/robinhood/race_series.py` 的 `RACE_ANCHOR`,那边注释写着
//  「写死,禁改 —— 改起点 = 换了一个问题」,背后有一次真事故)。
// 顺带一个不是巧合的好处:**18 个资金流未记录的交易日全部 ≤ 2026-07-09**,
// 所以从这天起算,TWR 不再是暂定值。
//
// ⚠ **和博客配图会差 0.45 点,这不是 bug,是那边的 bug。** 2026-08-29 拆解(见 CLAUDE.md):
//   race_series 用 `substr(asof,1,10)` 归日,而全库 156 行里 44 行的快照是收盘后
//   甚至次日凌晨拉的 —— 归错天。改用 `session` 归日后领先从 +4.56 → +4.11
//   (同时找回 2 个被记到次日名下的交易日),再把现金流从期末口径换到期初 → +4.23。
//   这里走 +4.23 那一档:**不为了和已发布的图对上而退回一个已证实的错误。**
//
// 画的是 TWR 累计(逐日链接、已剔除资金流),不是账户余额 ——
// 账户余额会因为一笔入金台阶式跳上去,拿它跟 QQQ 比等于把「我存了钱」算成「我赢了」。
//
// ⚠ 口径二:`/api/twr` 的四条序列是**基数 100 的指数**(首值 100.0),不是分数。
//   2026-08-29 实测踩到:按分数处理会画出 "+12336%",而图形形状完全正常 ——
//   只有把末值和 `/api/desk-summary` 的权威值对一下才看得出来。
// =============================================================================

struct CurveView: View {
    @State private var picked: Set<String> = ["cc", "qqq"]
    /// 区间档。**默认落在记分板锚日** —— 换锚 = 换了一个问题
    /// (`race_series.py` 那次事故就是悄悄换了起点,结论从「领先」翻成「落后」),
    /// 所以档位是**显式的五个**,不是一个能悄悄改变结论的下拉框,而且当前档一直显示在标题右边。
    /// 锚日只此一处 —— 见 DeskWindow。这里保留一个同名别名,免得下面几十处都要改。
    static var raceAnchor: String { DeskWindow.raceAnchor }

    @State private var range: Range = {
        // `-range w1|m1|m3|anchor|all` —— 只为截图存在,同 -tab / -openDay。
        // 没有它,这五个档就只能靠「编译过了」来相信。
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-range"), i + 1 < a.count,
              let r = Range(rawValue: a[i + 1]) else { return .anchor }
        return r
    }()

    enum Range: String, CaseIterable, Identifiable {
        case w1, m1, m3, anchor, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .w1: return "1周"
            case .m1: return "1月"
            case .m3: return "3月"
            case .anchor: return "锚日"
            case .all: return "全部"
            }
        }
        /// 自然日回看窗口。nil = 不按天数算(锚日 / 全部)。
        var lookbackDays: Int? {
            switch self {
            case .w1: return 7
            case .m1: return 30
            case .m3: return 90
            default: return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Loader<TwrResponse, AnyView>("/api/twr") { t in
                            AnyView(VStack(spacing: 14) {
                                if let bad = contractViolation(t) {
                                    Card {
                                        Label("曲线口径对不上", systemImage: "exclamationmark.triangle.fill")
                                            .font(.headline).foregroundStyle(Palette.alarm)
                                        Text(bad).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                                    }
                                } else {
                                    chartCard(t)
                                    legendCard(t)
                                }
                                noteCard(t)
                            })
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationTitle("曲线")
        }
    }

    /// 配色对齐博客那张记分板图:我=砖红,QQQ=灰。两个 app 之间的视觉一致性
    /// 比「好看」重要 —— 同一条线在两处不同颜色,读者会以为是两条不同的线。
    private static let series: [(key: String, label: String, color: Color)] = [
        ("cc",   "我",   Color(red: 0.69, green: 0.26, blue: 0.12)),
        ("qqq",  "QQQ",  Color(red: 0.52, green: 0.52, blue: 0.50)),
        ("spy",  "SPY",  Color(red: 0.16, green: 0.42, blue: 0.90)),
        ("tqqq", "TQQQ", Color(red: 0.72, green: 0.24, blue: 0.62)),
    ]

    private func values(_ t: TwrResponse, _ key: String) -> [Double?] {
        switch key {
        case "cc": return t.cc
        case "qqq": return t.qqq
        case "spy": return t.spy
        default: return t.tqqq
        }
    }

    /// 指数 → 累计收益率。**换算只此一处。**
    private func ret(_ indexValue: Double) -> Double { indexValue / 100 - 1 }

    /// 当前档的起点在序列里的位置。
    ///
    /// 找不到精确那天就取**其后第一个**有数的日子(锚日/起始日不一定是交易日),
    /// 并把实际用的那天显示在标题右边 —— 不静默换一个起点。
    private func anchorIndex(_ t: TwrResponse) -> Int? {
        switch range {
        case .all: return 0
        case .anchor: return t.dates.firstIndex { $0 >= Self.raceAnchor }
        case .w1, .m1, .m3:
            guard let days = range.lookbackDays,
                  let lastStr = t.dates.last, let last = Self.ymd.date(from: lastStr),
                  let from = Calendar(identifier: .gregorian)
                      .date(byAdding: .day, value: -days, to: last) else { return 0 }
            let fromStr = Self.iso(from)
            return t.dates.firstIndex { $0 >= fromStr } ?? 0
        }
    }

    /// 这一档要的区间比数据还长吗。是的话得说出来 ——
    /// 显示「3月」而实际只有 2.6 个月的数,是那种没人会发现的小谎。
    private func rangeTruncated(_ t: TwrResponse) -> Bool {
        range.lookbackDays != nil && anchorIndex(t) == 0 && !t.dates.isEmpty
    }

    private static func iso(_ d: Date) -> String { ymd.string(from: d) }

    /// 重定基到锚日 = 100。TWR 指数是逐日 (1+r) 的连乘,所以「除以锚日那天的值」
    /// 恰好就是「从锚日起算的 TWR」—— 这一步是恒等变换,不是近似。
    private func rebased(_ t: TwrResponse, _ key: String) -> [Double?] {
        let v = values(t, key)
        guard let i = anchorIndex(t), i < v.count, let base = v[i], base != 0 else { return v }
        return v.enumerated().map { j, x in
            guard j >= i, let x else { return nil }
            return x / base * 100
        }
    }

    /// 契约自检:四条序列首值都该是 100(服务端口径)。不是就说出来,不猜、不静默换算。
    private func contractViolation(_ t: TwrResponse) -> String? {
        for s in Self.series {
            guard let first = values(t, s.key).compactMap({ $0 }).first else { continue }
            if abs(first - 100) > 0.01 {
                return "\(s.label) 序列首值是 \(String(format: "%.4f", first))，不是约定的基数 100。"
                     + "服务端 /api/twr 的口径可能变了 —— 在确认之前拒绝画图，"
                     + "免得画出一条形状正常但数值错 100 倍的线。"
            }
        }
        return nil
    }

    /// 交易所日历上的日子 → Date。**共享那一份**(Loader.swift 的 `exchangeYMD`),
    /// 风控页的波动趋势图也用它 —— 各建一个就是两处会漂的时区判据。
    private static var ymd: DateFormatter { exchangeYMD }

    /// 画的是**指数值**(锚日=100),跟博客那张图一样 —— 这样「领先 N 点」就是两条线的垂直距离,
    /// 不用读者自己去做减法。
    private func points(_ t: TwrResponse, _ key: String) -> [(Date, Double)] {
        let vs = rebased(t, key)
        return t.dates.enumerated().compactMap { i, d in
            guard i < vs.count, let v = vs[i], let day = Self.ymd.date(from: d) else { return nil }
            return (day, v)
        }
    }

    /// 本档实际用的起点(可能不是请求的那天 —— 那天不是交易日/早于数据起点)。
    private func shownStart(_ t: TwrResponse) -> String? {
        anchorIndex(t).flatMap { $0 < t.dates.count ? t.dates[$0] : nil } ?? t.dates.first
    }

    private func lastIndexValue(_ t: TwrResponse, _ key: String) -> Double? {
        rebased(t, key).compactMap { $0 }.last
    }

    private func chartCard(_ t: TwrResponse) -> some View {
        let start = shownStart(t)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("记分板").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(start ?? "") ~ \(t.dates.last ?? "")")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                // 锚日是**系列属性**,不是每次自选的参数。所以这里是两个明确的档,
                // 不是一个能悄悄改变结论的下拉框。
                Picker("", selection: $range) {
                    ForEach(Range.allCases) { r in Text(r.label).tag(r) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 6) {
                    ForEach(Self.series, id: \.key) { s in
                        Button {
                            if picked.contains(s.key) { picked.remove(s.key) } else { picked.insert(s.key) }
                        } label: {
                            // 选中态**不能只靠颜色深浅** —— QQQ 那条线本身就是灰的,
                            // 「选中的灰」和「未选中的灰」看起来一模一样(实测截图分不出来)。
                            // 所以选中另加一圈描边 + 一个实心色点。
                            HStack(spacing: 4) {
                                if picked.contains(s.key) {
                                    Circle().fill(s.color).frame(width: 6, height: 6)
                                }
                                Text(s.label).font(.caption2.weight(.semibold))
                            }
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(picked.contains(s.key)
                                                           ? s.color.opacity(0.14) : Color.black.opacity(0.05)))
                                .overlay(Capsule().stroke(picked.contains(s.key)
                                                          ? s.color.opacity(0.65) : .clear, lineWidth: 1.2))
                                .foregroundStyle(picked.contains(s.key) ? s.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                Chart {
                    // 锚日那条基准线。博客那张图上是虚线 100,「领先几点」就是两条线到它的距离差。
                    RuleMark(y: .value("锚日", 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.gray.opacity(0.6))
                    ForEach(Self.series.filter { picked.contains($0.key) }, id: \.key) { s in
                        // `series:` 不能省 —— 少了它 Charts 把几条并成一条,
                        // 全部按最后一次 foregroundStyle 上色(实测四条全变绿)。
                        ForEach(points(t, s.key), id: \.0) { day, v in
                            LineMark(x: .value("日期", day), y: .value("指数", v),
                                     series: .value("系列", s.label))
                                .foregroundStyle(s.color)
                                .lineStyle(StrokeStyle(lineWidth: s.key == "cc" ? 2.4 : 1.6))
                                // **直线不是样条。** 样条会在两个真实收盘点之间画出数据里
                                // 根本没有的起伏 —— 1 周档只有 6 个点时尤其明显。
                                // 博客那张记分板图也是直线段 + 圆点,两边一致。
                                .interpolationMethod(.linear)
                            if points(t, s.key).count <= 45 {
                                PointMark(x: .value("日期", day), y: .value("指数", v))
                                    .foregroundStyle(s.color)
                                    .symbolSize(s.key == "cc" ? 26 : 16)
                            }
                        }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(String(format: "%.0f", d)).font(.caption2) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Date.self) {
                                Text(d.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 250)
            }
        }
    }

    private func legendCard(_ t: TwrResponse) -> some View {
        let mine = lastIndexValue(t, "cc")
        let bench = lastIndexValue(t, "qqq")
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                if let m = mine, let q = bench {
                    HStack {
                        Text("领先").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(String(format: "%+.2f 点", m - q))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(m - q >= 0 ? Self.series[0].color : Palette.loss)
                    }
                    Text("＝两条线在起点 100 之上的距离差（本档起点 \(shownStart(t) ?? "—")）。"
                         + "点数就是百分点，因为两条线同日同起点。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Divider()
                }
                ForEach(Self.series, id: \.key) { s in
                    let v = lastIndexValue(t, s.key)
                    HStack {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.label).font(.caption)
                        Spacer()
                        Text(v.map { String(format: "%.2f", $0) } ?? "—")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(v.map { pct(ret($0)) } ?? "—")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .frame(width: 74, alignment: .trailing)
                            .foregroundStyle((v ?? 100) >= 100 ? Palette.gain : Palette.loss)
                    }
                }
            }
        }
    }

    private func noteCard(_ t: TwrResponse) -> some View {
        let links = points(t, "cc").count
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("口径").font(.subheadline.weight(.semibold))
                KV(k: "画的是", v: "逐日链接 TWR 指数，锚日 = 100（已剔除资金流，不是账户余额）")
                KV(k: "样本", v: "本档 \(max(0, links - 1)) 个链接（全库 \(t.sessions) 个 session）")
                if let n = t.sessions_awaiting_benchmark, n > 0 {
                    KV(k: "窗口", v: "末尾 \(n) 个 session 的基准收盘价尚未结算，已截齐排除")
                }
                if rangeTruncated(t) {
                    KV(k: "注意", v: "「\(range.label)」比现有数据还长，实际画的是全部 \(t.sessions) 个 session",
                       tint: Palette.alarm)
                }
                if range == .anchor {
                    // 锚日之后资金流是全的 —— 这不是巧合,18 个未记录的日子全在 07-09 及以前。
                    KV(k: "资金流", v: "锚日之后每天都有记录 —— 这一段不是暂定值", tint: Palette.gain)
                    Divider()
                    Text("和博客那张记分板图会差约 0.45 点：那边用 substr(asof) 归日，"
                         + "而 156 行里有 44 行是收盘后甚至次日凌晨拉的快照，归错了天。"
                         + "改按 session 归日后领先 +4.56 → +4.11（同时找回 2 个交易日），"
                         + "再把现金流从期末口径换到期初 → +4.23。这里走后者。")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if t.provisional == true, let f = t.flow_unknown_links, f > 0 {
                    // 判据是**受影响的链接数**,不是「有几天没记录」——
                    // 窗口首日的流只当分母基点,不进任何链接。
                    KV(k: "暂定", v: "\(f) 个链接日的资金流无记录，曲线在那几段是暂定值",
                       tint: Palette.alarm)
                }
            }
        }
    }
}
