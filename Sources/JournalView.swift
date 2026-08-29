import SwiftUI

// =============================================================================
// 日志 —— 每日操作记录。
//
// **不另造一份台账**(这个项目的第一条硬约束)。每日复盘已经写在 blog-options 上了,
// 83 篇、一天一篇、series = daily-review。这里读的就是那份,不是第二个输入框。
//
// 一天两本账放在同一页上:
//   ① 你写的复盘正文(blog-options `/api/post/<slug>`,markdown 真渲染)
//   ② 那天的真实成交(quant.db → `/api/orders?date=`)
// 分开看的时候「我以为我做了什么」和「实际成交了什么」永远对不上;
// 摞在一起才看得见差异 —— 这正是这个 app 相对于「打开博客看」多出来的东西。
// =============================================================================

struct JournalView: View {
    var body: some View { JournalList() }
}

private struct JournalList: View {
    @State private var posts: [FeedPost] = []
    @State private var error: DeskError?
    @State private var loading = true
    @State private var query = ""

    private var shown: [FeedPost] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return posts }
        return posts.filter { $0.title.localizedCaseInsensitiveContains(q)
                           || $0.excerpt.localizedCaseInsensitiveContains(q)
                           || $0.date.contains(q) }
    }

    /// 直接打开某一天。**只为调试/截图存在** —— `-openDay 2026-08-28`。
    /// 详情页是这个 app 最主要的新东西(复盘正文 + 当天成交摞在一起),
    /// 而模拟器截图只能截当前屏 —— 没有这个参数,这一页就只能靠「编译过了」来相信它。
    @State private var path: [FeedPost] = []
    private static var openDayArg: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-openDay"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Palette.bg.ignoresSafeArea()
                list
            }
            .navigationTitle("日志")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: FeedPost.self) { JournalDetail(post: $0) }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                if FactsSourceFactory.isSample {
                    Card {
                        Label("样本模式：日志需要联网", systemImage: "wifi.slash")
                            .font(.subheadline.weight(.medium))
                    }
                } else if loading && posts.isEmpty {
                    ProgressView().padding(.top, 60)
                } else if let e = error {
                    ErrorCard(error: e)
                } else {
                    Card {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜标题 / 正文摘要 / 日期", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if !query.isEmpty {
                                Button { query = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        Text("共 \(posts.count) 天\(query.isEmpty ? "" : "，命中 \(shown.count) 天")")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                    ForEach(shown) { p in
                        NavigationLink(value: p) { JournalRow(post: p) }
                            .buttonStyle(.plain)
                    }
                    if shown.isEmpty {
                        Card { Text("没有匹配的日子").font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    private func reload() async {
        guard !FactsSourceFactory.isSample else { loading = false; return }
        loading = true
        let site = Site.options
        switch await DeskAPI.shared.get(url: site.feedURL, as: Feed.self) {
        case .failure(let e): error = e; posts = []
        case .success(let f):
            // 中英同一篇会各出现一次;日志只看中文那条,英文条会把时间线变成两倍长。
            let zh = f.posts.filter { $0.lang == "zh" }
            posts = zh.sorted { $0.date == $1.date ? $0.title < $1.title : $0.date > $1.date }
            error = posts.isEmpty
                ? .empty(url: site.feedURL.absoluteString)   // 空集不报绿
                : nil
            if let day = Self.openDayArg, let hit = posts.first(where: { $0.date == day }) {
                path = [hit]
            }
        }
        loading = false
    }
}

private struct JournalRow: View {
    let post: FeedPost
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(post.date).font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink.opacity(0.55))
                    if post.series == "daily-review" {
                        Text("日复盘").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.gain.opacity(0.12)))
                            .foregroundStyle(Palette.gain)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(post.title).font(.headline).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !post.excerpt.isEmpty {
                    Text(post.excerpt).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - 一天的详情:复盘正文 + 当天真实成交

private struct JournalDetail: View {
    let post: FeedPost

    @State private var markdown: String?
    @State private var orders: OrdersResponse?
    @State private var error: DeskError?
    @State private var ordersError: DeskError?
    @State private var loading = true

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(post.date).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(post.title).font(.title3.weight(.bold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if loading && markdown == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let e = error {
                        ErrorCard(error: e)
                    } else if let md = markdown {
                        Card { MarkdownText(text: md) }     // 真渲染,不露字面 ** 与 |---|
                    }
                    ordersCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(post.date)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// 当天成交。**它和上面的正文是两个独立来源** —— 一个是我写的,一个是券商记的。
    /// 所以这里的错误单独呈现:正文取到了而成交没取到,不该让整页变成一条错误。
    private var ordersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("当天成交", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let o = orders, o.date == post.date {
                        Text(o.count > o.returned ? "\(o.returned)/\(o.count) 笔" : "\(o.count) 笔")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let e = ordersError {
                    Text(e.detail).font(.caption).foregroundStyle(Palette.alarm)
                } else if let o = orders, o.date != post.date {
                    // **服务端没按天过滤**(老版本会静默忽略 date 参数),这时列表里是全库最近若干笔,
                    // 看着完全正常 —— 顶部还会显示「1,796 笔」。宁可不显示,也不显示一份错的当天成交。
                    Label("服务端没有按天过滤（回显 date=\(o.date ?? "nil")），"
                          + "拒绝显示——否则这里会是全库最近若干笔，而不是这一天的。",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Palette.alarm)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let o = orders {
                    if o.orders.isEmpty {
                        // 「那天没交易」和「取不到」必须分得开 —— 后者走上面的错误分支。
                        Text("这一天没有成交记录。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(o.orders) { OrderRow(order: $0) }
                        Divider().padding(.vertical, 2)
                        Text("口径：只含成交与到期交割，**不含**手续费与任何资金流（入金/出金/分红/利息）。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func load() async {
        guard !FactsSourceFactory.isSample else { loading = false; return }
        loading = true
        let url = Site.options.postURL(slug: post.slug, locale: post.lang)
        async let body = DeskAPI.shared.get(url: url, as: PostDetail.self)
        async let ords = DeskAPI.shared.get("/api/orders?limit=200&date=\(post.date)", as: OrdersResponse.self)
        switch await body {
        case .success(let d): markdown = d.markdown; error = nil
        case .failure(let e): error = e; markdown = nil
        }
        switch await ords {
        case .success(let o): orders = o; ordersError = nil
        case .failure(let e): ordersError = e; orders = nil
        }
        loading = false
    }
}

private struct OrderRow: View {
    let order: OrdersResponse.Order
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tag).font(.caption2.weight(.bold))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.14)))
                .foregroundStyle(tint)
                .frame(width: 46)
            Text(order.what).font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let u = order.units { Text("×\(qty(u))").font(.caption2).foregroundStyle(.secondary) }
            if let a = order.amount {
                Text(usd2(a)).font(.caption.monospacedDigit())
                    .foregroundStyle(a >= 0 ? Palette.gain : Palette.loss)
            }
        }
        .padding(.vertical, 2)
    }
    private var tag: String {
        switch order.type {
        case "BUY": return "买入"
        case "SELL": return "卖出"
        case "OPTIONASSIGNMENT": return "交割"
        default: return order.type
        }
    }
    private var tint: Color {
        switch order.type {
        case "BUY": return Palette.loss          // 买入 = 现金流出
        case "SELL": return Palette.gain
        default: return Palette.alarm
        }
    }
}
