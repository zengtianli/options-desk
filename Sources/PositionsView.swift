import SwiftUI

// =============================================================================
// 持仓 —— 「六批票据梯子」那一栏。
//
// 两个端点合成一屏:`/api/portfolio`(有什么仓) + `/api/roll-signals`(每条腿该怎么办)。
// 分两页看没意义:看到 710 那批 15 张的时候,你要的正是「它现在 Δ0.62、该 CALENDAR ROLL」。
// 合并的判据是 OCC ticker,不是「symbol+strike 差不多就算」——
// 后者在同一 strike 有多个到期日时会静默配错行。
// =============================================================================

struct PositionsView: View {
    @State private var pf: PortfolioResponse?
    @State private var sigs: RollSignalsResponse?
    @State private var error: DeskError?
    @State private var sigError: DeskError?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if FactsSourceFactory.isSample {
                            Card { Label("样本模式：持仓需要联网", systemImage: "wifi.slash")
                                    .font(.subheadline.weight(.medium)) }
                        } else if loading && pf == nil {
                            ProgressView().padding(.top, 60)
                        } else if let e = error {
                            ErrorCard(error: e)
                        } else if let p = pf {
                            totals(p)
                            if !p.equity_positions.isEmpty { equities(p) }
                            ladder(p)
                            snapshotNote(p)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 32)
                }
            }
            .navigationTitle("持仓")
            .navigationDestination(for: PortfolioResponse.OptionPosition.self) { pos in
                OptionDetail(pos: pos, signal: signal(for: pos))
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: 合并判据

    /// 用 OCC ticker 对齐。持仓侧没有 ticker 字段,所以按 (标的, 到期, C/P, 行权价) 四元组配 ——
    /// 四个都相等才算同一条腿。少一个维度就会把 09-18 的 700 配到 08-28 的 700 上。
    private func signal(for p: PortfolioResponse.OptionPosition) -> RollSignalsResponse.Signal? {
        sigs?.signals.first {
            $0.underlying == p.symbol
            && $0.exp == p.expiration
            && $0.cp.uppercased() == p.rightLabel
            && abs($0.strike - p.strike) < 0.001
        }
    }

    // MARK: 分区

    private func totals(_ p: PortfolioResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                // 口径 2026-08-29 收成单户,「合并总账」从此是句假话。
                // 报合计必标口径 —— 一个户就把它的号印出来,多个户才叫合并。
                Text(p.accounts.count == 1
                     ? "账户 \(p.accounts[0].account)"
                     : "合并总账（\(p.accounts.count) 户）")
                    .font(.subheadline.weight(.semibold))
                bigRow("净值", usd(p.totals.total_value), Palette.ink)
                Divider()
                KV(k: "股票市值", v: usd(p.totals.equity_value), mono: true)
                KV(k: "期权市值", v: usd(p.totals.options_value), mono: true)
                KV(k: "现金", v: usd(p.totals.cash), mono: true,
                   tint: p.totals.cash < 0 ? Palette.loss : nil)
                KV(k: "购买力", v: usd(p.totals.buying_power), mono: true)
                if p.accounts.count > 1 {
                    Divider()
                    ForEach(p.accounts) { a in
                        KV(k: a.account, v: usd(a.total_value), mono: true)
                    }
                }
            }
        }
    }

    private func equities(_ p: PortfolioResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("股票仓（\(p.equity_positions.count)）").font(.subheadline.weight(.semibold))
                ForEach(p.equity_positions) { e in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(e.symbol).font(.headline)
                            Text("×\(qty(e.quantity))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(usd(e.market_value ?? 0)).font(.subheadline.monospacedDigit())
                        }
                        HStack(spacing: 12) {
                            if let a = e.average_buy_price {
                                Text("均价 \(usd2(a))").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let m = e.mark {
                                Text("现价 \(usd2(m))").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let u = e.unrealized, let pct0 = e.unrealizedPct {
                                Text("\(usd(u))（\(pct(pct0))）")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(u >= 0 ? Palette.gain : Palette.loss)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    if e.id != p.equity_positions.last?.id { Divider() }
                }
            }
        }
    }

    /// 期权按到期日分批 —— 「几批票据」这个说法本身就是按到期日数的。
    private func ladder(_ p: PortfolioResponse) -> some View {
        let groups = Dictionary(grouping: p.option_positions, by: \.expiration)
            .sorted { $0.key < $1.key }
        return ForEach(groups, id: \.key) { exp, legs in
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(exp).font(.subheadline.weight(.semibold).monospacedDigit())
                        if let d = daysFromToday(exp) {
                            Text(d >= 0 ? "还有 \(d) 天" : "已过期 \(-d) 天")
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(
                                    (d < 0 ? Palette.alarm : d <= 7 ? Palette.alarm : Palette.ink).opacity(0.12)))
                                .foregroundStyle(d <= 7 ? Palette.alarm : Palette.ink.opacity(0.7))
                        }
                        Spacer()
                        Text("\(legs.count) 腿").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(legs.sorted { $0.strike < $1.strike }) { leg in
                        NavigationLink(value: leg) {
                            LegRow(leg: leg, signal: signal(for: leg))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func snapshotNote(_ p: PortfolioResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("口径").font(.subheadline.weight(.semibold))
                if let n = p.meta.snapshot_note {
                    Text(n).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let a = p.meta.asof { KV(k: "数据时间", v: a, mono: true) }
                if sigError != nil {
                    // 信号取不到不该让持仓整页变成错误 —— 但也不能假装它只是「暂时没有」。
                    KV(k: "滚动信号", v: "取不到：\(sigError!.detail)", tint: Palette.alarm)
                }
            }
        }
    }

    private func bigRow(_ k: String, _ v: String, _ c: Color) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(c)
        }
    }

    private func reload() async {
        guard !FactsSourceFactory.isSample else { loading = false; return }
        loading = true
        async let a = DeskAPI.shared.get("/api/portfolio", as: PortfolioResponse.self)
        async let b = DeskAPI.shared.get("/api/roll-signals", as: RollSignalsResponse.self)
        switch await a {
        case .success(let v): pf = v; error = nil
        case .failure(let e): error = e; pf = nil
        }
        switch await b {
        case .success(let v): sigs = v; sigError = nil
        case .failure(let e): sigError = e; sigs = nil
        }
        loading = false
    }
}

// MARK: - 一条腿

private struct LegRow: View {
    let leg: PortfolioResponse.OptionPosition
    let signal: RollSignalsResponse.Signal?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(leg.isShort ? "卖" : "买")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill((leg.isShort ? Palette.gain : Palette.ink).opacity(0.12)))
                    .foregroundStyle(leg.isShort ? Palette.gain : Palette.ink.opacity(0.8))
                Text("\(leg.symbol) \(leg.rightLabel)\(qty(leg.strike))")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                Text("×\(qty(leg.quantity))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let m = leg.mark {
                    Text(usd2(m)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            if let s = signal {
                HStack(spacing: 6) {
                    Text(s.action)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((s.isUrgent ? Palette.alarm : s.isRoll
                                                    ? Palette.ink : Palette.gain).opacity(0.12)))
                        .foregroundStyle(s.isUrgent ? Palette.alarm : Palette.ink.opacity(0.75))
                    if let d = s.delta {
                        Text(String(format: "Δ%.2f", d)).font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct OptionDetail: View {
    let pos: PortfolioResponse.OptionPosition
    let signal: RollSignalsResponse.Signal?

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(pos.symbol) \(pos.expiration) \(pos.rightLabel)\(qty(pos.strike))")
                                .font(.title3.weight(.bold).monospacedDigit())
                            KV(k: "方向", v: pos.isShort ? "卖出（short）" : "买入（long）")
                            KV(k: "张数", v: qty(pos.quantity), mono: true)
                            if let a = pos.average_price { KV(k: "开仓均价", v: usd2(a), mono: true) }
                            if let m = pos.mark { KV(k: "现价", v: usd2(m), mono: true) }
                            if let n = pos.notionalMark { KV(k: "名义市值", v: usd(n), mono: true) }
                            if let d = daysFromToday(pos.expiration) {
                                KV(k: "到期", v: d >= 0 ? "还有 \(d) 天" : "已过期 \(-d) 天",
                                   tint: d <= 7 ? Palette.alarm : nil)
                            }
                            KV(k: "账户", v: pos.account, mono: true)
                            if pos.quote_missing == true {
                                KV(k: "报价", v: "缺失 —— 上面的现价与市值不可信", tint: Palette.alarm)
                            }
                        }
                    }
                    if let g = greeksCard { g }
                    if let s = signal { signalCard(s) }
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
        }
        .navigationTitle("\(pos.rightLabel)\(qty(pos.strike))")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 希腊字母:**持仓端点里这几个常常是 null**(快照没带),
    /// 有值才画这张卡,没值不画空格子 —— 空格子看着像 0。
    private var greeksCard: AnyView? {
        let g = signal
        let items: [(String, Double?)] = [
            ("Δ delta", pos.delta ?? g?.delta), ("Θ theta", pos.theta ?? g?.theta),
            ("V vega", pos.vega), ("IV", pos.iv ?? g?.iv),
        ]
        let have = items.filter { $0.1 != nil }
        guard !have.isEmpty else { return nil }
        return AnyView(Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("希腊字母").font(.subheadline.weight(.semibold))
                ForEach(have, id: \.0) { name, v in
                    KV(k: name, v: String(format: "%.4f", v!), mono: true)
                }
                if pos.delta == nil && g?.delta != nil {
                    Text("持仓快照没带希腊字母，这里取的是滚动信号端点算的那份。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        })
    }

    private func signalCard(_ s: RollSignalsResponse.Signal) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("建议动作").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(s.action).font(.subheadline.weight(.bold))
                        .foregroundStyle(s.isUrgent ? Palette.alarm : Palette.ink)
                }
                ForEach(Array(s.reasons.enumerated()), id: \.offset) { _, r in
                    Text("· " + r).font(.caption).foregroundStyle(Palette.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                if let u = s.underlying_price { KV(k: "标的现价", v: usd2(u), mono: true) }
                KV(k: "DTE", v: "\(s.dte) 天", mono: true)
                if let tv = s.time_value { KV(k: "时间价值", v: usd2(tv), mono: true) }
                if let h = s.tv_harvested_pct { KV(k: "已收 TV", v: String(format: "%.0f%%", h), mono: true) }
                if let a = s.tv_annual_pct { KV(k: "TV 年化", v: String(format: "%.1f%%", a), mono: true) }
                Text("这是端点算出来的建议，不是下单指令 —— 本 app 只读，不接任何交易通路。")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
    }
}
