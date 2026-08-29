import SwiftUI

// =============================================================================
// 风控 —— 回撤硬约束 + 绩效指标。
//
// 这一页存在的理由:2026-08-29 把 `/api/harness` 接到真数据上之后，**硬约束是破的** ——
// CC 最大回撤 −11.9%，加权基准（0.7 QQQ + 0.3 SPY）−8.8%，headroom −3.1%。
// 在此之前这个端点连着停更的 JSON、返回一堆 0 并且 HTTP 200，
// 也就是说这条破裂**在三个月里一直存在、一直没人看见**。
//
// 所以它必须有一屏，而且破裂时必须刺眼。绿着的时候也照样显示 ——
// 只在出事时才出现的东西，出事那天没人认得它。
// =============================================================================

struct RiskView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Loader<HarnessResponse, AnyView>("/api/harness") { h in
                            AnyView(VStack(spacing: 14) { verdict(h); detail(h) })
                        }
                        Loader<PerfMetricsResponse, AnyView>("/api/perf-metrics") { m in
                            AnyView(metrics(m))
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationTitle("风控")
        }
    }

    private func verdict(_ h: HarnessResponse) -> some View {
        let bad = !h.ok
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: bad ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                        .foregroundStyle(bad ? Palette.alarm : Palette.gain)
                    Text(bad ? "回撤硬约束：破裂" : "回撤硬约束：满足")
                        .font(.headline)
                        .foregroundStyle(bad ? Palette.alarm : Palette.gain)
                    Spacer()
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
                if let w = h.window, w.count == 2 { KV(k: "窗口", v: "\(w[0]) ~ \(w[1])", mono: true) }
                if let n = h.sessions { KV(k: "样本", v: "\(n) 个 session", mono: true) }
                if h.provisional == true, let r = h.provisional_reason {
                    Divider()
                    Label(r, systemImage: "questionmark.circle.fill")
                        .font(.caption).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 绩效指标。**服务端在样本不够时拒绝给点估计** —— 这里就照实显示那句拒绝，
    /// 不自己编一个数,也不留空白格(空白格看着像 app 没解析出来)。
    private func metrics(_ m: PerfMetricsResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("绩效指标").font(.subheadline.weight(.semibold))
                ForEach(m.strategies) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.label).font(.subheadline.weight(.medium))
                            Spacer()
                            if let n = s.n {
                                Text("n=\(n)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        if s.insufficient_sample == true {
                            Text(s.sample_note ?? "样本不足，服务端拒绝给点估计。")
                                .font(.caption2).foregroundStyle(Palette.alarm)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            HStack(spacing: 14) {
                                metric("年化", s.annual_return.map { pct($0) })
                                metric("波动", s.annual_vol.map { pct($0) })
                                metric("Sharpe", s.sharpe.map { String(format: "%.2f", $0) })
                                metric("最大回撤", s.max_drawdown.map { pct($0) })
                            }
                            if let se = s.se_annual {
                                Text("年化标准误 ±\(pp(se))　—— 点估计别单看")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    if s.id != m.strategies.last?.id { Divider() }
                }
            }
        }
    }

    private func metric(_ k: String, _ v: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v ?? "—").font(.caption.monospacedDigit())
        }
    }
}
