import SwiftUI

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
//   窗口也统一到记分板锚日(DeskWindow.raceAnchor):锚日之后受影响的链接是 0 个,
//   所以那条「资金流未记录」的警告在这一档下**不再出现** —— 不是藏起来了,
//   是它在这个窗口里不成立。全窗口下照样会出现(17 个链接)。
// =============================================================================

struct RiskView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Loader<HarnessResponse, AnyView>("/api/harness" + DeskWindow.startQuery()) { h in
                            AnyView(VStack(spacing: 14) { verdict(h); detail(h) })
                        }
                        Loader<PerfMetricsResponse, AnyView>("/api/perf-metrics" + DeskWindow.startQuery()) { m in
                            AnyView(metrics(m))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationTitle("风控")
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
                Text("累计与回撤是这段窗口里的**路径事实**，不含年化外推；年化含均值外推，"
                     + "后面的 ± 是一倍标准误。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
