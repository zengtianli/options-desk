import SwiftUI
import Charts

// =============================================================================
// 曲线 —— 我 vs 三条基准,同一个窗口。
//
// 画的是 **TWR 累计**(逐日链接、已剔除资金流),不是账户余额曲线。
// 这两条长得很像但意思完全不同:账户余额会因为一笔入金直接台阶式跳上去,
// 拿它跟 QQQ 比等于把「我往里存了钱」算成「我跑赢了」。
//
// ⚠ **口径**:`/api/twr` 的四条序列是**基数 100 的指数**(首值 100.0),不是分数。
//   2026-08-29 实测踩到:按分数处理会画出 "+12336%" 这种数,而且图形形状完全正常 ——
//   只有把末值和 `/api/desk-summary` 的权威值(+23.36% / +1.88%)对一下才看得出来。
//   所以下面 `ret()` 是唯一的换算处,并且**首值不是 100 就当场报错**,不静默画。
// =============================================================================

struct CurveView: View {
    @State private var picked: Set<String> = ["cc", "qqq"]

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

    private static let series: [(key: String, label: String, color: Color)] = [
        ("cc",   "我",   Palette.gain),
        ("qqq",  "QQQ",  Color(red: 0.16, green: 0.42, blue: 0.90)),
        ("spy",  "SPY",  Color(red: 0.72, green: 0.53, blue: 0.10)),
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

    /// 契约自检:四条序列首值都该是 100。不是就说出来,不猜、不静默换算。
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

    /// 交易所日历上的日子 → Date。图的 x 轴必须是真日期,
    /// 拿字符串当类目轴会把 53 个标签糊成一条黑线(实测)。
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func points(_ t: TwrResponse, _ key: String) -> [(Date, Double)] {
        let vs = values(t, key)
        return t.dates.enumerated().compactMap { i, d in
            guard i < vs.count, let v = vs[i], let day = Self.ymd.date(from: d) else { return nil }
            return (day, ret(v) * 100)
        }
    }

    private func chartCard(_ t: TwrResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("累计收益（TWR）").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(t.dates.first ?? "") ~ \(t.dates.last ?? "")")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                // 点一下开关一条线。四条全开时 TQQQ 的量级会把另外三条压平,
                // 所以默认只开「我」和 QQQ。
                HStack(spacing: 6) {
                    ForEach(Self.series, id: \.key) { s in
                        Button {
                            if picked.contains(s.key) { picked.remove(s.key) } else { picked.insert(s.key) }
                        } label: {
                            Text(s.label)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(picked.contains(s.key)
                                                           ? s.color.opacity(0.16) : Color.black.opacity(0.05)))
                                .foregroundStyle(picked.contains(s.key) ? s.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                Chart {
                    ForEach(Self.series.filter { picked.contains($0.key) }, id: \.key) { s in
                        // `series:` 不能省 —— 少了它 Charts 把四条并成一条,
                        // 全部按最后一次 foregroundStyle 上色(实测四条全变绿)。
                        ForEach(points(t, s.key), id: \.0) { day, v in
                            LineMark(x: .value("日期", day), y: .value("累计", v),
                                     series: .value("系列", s.label))
                                .foregroundStyle(s.color)
                                .interpolationMethod(.monotone)
                        }
                    }
                    RuleMark(y: .value("零", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Double.self) { Text(String(format: "%+.0f%%", d)).font(.caption2) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { v in
                        AxisGridLine()
                        AxisValueLabel {
                            if let d = v.as(Date.self) {
                                Text(d.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
    }

    private func legendCard(_ t: TwrResponse) -> some View {
        let last: (String) -> Double? = { key in
            values(t, key).compactMap { $0 }.last.map { ret($0) }
        }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("区间末值").font(.subheadline.weight(.semibold))
                ForEach(Self.series, id: \.key) { s in
                    let v = last(s.key)
                    HStack {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.label).font(.caption)
                        Spacer()
                        Text(v.map { pct($0) } ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle((v ?? 0) >= 0 ? Palette.gain : Palette.loss)
                    }
                }
                Divider()
                if let cc = last("cc"), let q = last("qqq") {
                    HStack {
                        Text("对 QQQ 超额").font(.caption.weight(.semibold))
                        Spacer()
                        Text(pp(cc - q)).font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(cc - q >= 0 ? Palette.gain : Palette.loss)
                    }
                }
            }
        }
    }

    private func noteCard(_ t: TwrResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("口径").font(.subheadline.weight(.semibold))
                KV(k: "画的是", v: "逐日链接 TWR 累计（已剔除资金流），不是账户余额")
                KV(k: "样本", v: "\(t.sessions) 个 session")
                if let n = t.sessions_awaiting_benchmark, n > 0 {
                    KV(k: "窗口", v: "末尾 \(n) 个 session 的基准收盘价尚未结算，已截齐排除")
                }
                if t.provisional == true, let f = t.flow_unknown_days, f > 0 {
                    KV(k: "暂定", v: "\(f) 个交易日的资金流无记录，曲线在那几天是暂定值",
                       tint: Palette.alarm)
                }
            }
        }
    }
}
