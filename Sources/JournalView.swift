import SwiftUI

// =============================================================================
// 日志 —— 每日操作记录。
//
// **不另造一份台账**(这个项目的第一条硬约束)。每日复盘已经写在 blog-options 上了,
// 83 篇、一天一篇、series = daily-review。这里读的就是那份,不是第二个输入框。
//
// 一天三本账放在同一页上:
//   ① 你写的复盘正文(blog-options `/api/post/<slug>`,markdown 真渲染)
//   ② **那天的市场读**(quant.db → `/api/market-read?date=`)—— 大盘为什么这么走、
//      我的几只票逐只对新闻、对我意味着什么。这是这个 app 里「新闻」那一半
//      (用户 2026-08-30:「收盘后的 30 分钟 更新数据 新闻之类的」),
//      同样**不另造采集**:它是复盘八件套里被 missing_for 硬性要求的一件,天天在产。
//   ③ 那天的真实成交(quant.db → `/api/orders?date=`)
// 分开看的时候「市场发生了什么」「我以为我做了什么」「实际成交了什么」永远对不上;
// 摞在一起才看得见差异 —— 这正是这个 app 相对于「打开博客看」多出来的东西。
//
// ⚠ 列表是 feed ∪ 市场读日期,不是单读 feed。理由见 FeedPost.init(marketReadOnly:)。
// =============================================================================

struct JournalView: View {
    var body: some View { JournalList() }
}

private struct JournalList: View {
    @State private var posts: [FeedPost] = []
    @State private var error: DeskError?
    @State private var loading = true
    @State private var query = ""
    /// 市场读那条取失败时的原话。**不吞掉** —— 「新闻这一半坏了」必须看得见。
    @State private var marketReadNote: String?
    /// 有市场读但复盘还没发布的天数。它不是错误,是常态(自动链不发布),所以只做说明不报警。
    @State private var marketReadOnlyDays = 0
    /// 博客 feed 取不到时的原话。**降级不静默** —— 页面还能用,但少了哪一半必须说出来。
    @State private var feedNote: String?

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
                        Text("共 \(posts.count) 天\(query.isEmpty ? "" : "，命中 \(shown.count) 天")"
                             + (marketReadOnlyDays > 0 ? "，其中 \(marketReadOnlyDays) 天只有市场读（复盘未发布）" : ""))
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                        if let n = feedNote {
                            Label(n, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(Palette.alarm)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        }
                        if let n = marketReadNote {
                            Label(n, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(Palette.alarm)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        }
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
        // 两个来源并行取。市场读那条**允许失败** —— 它挂了不该让整个日志页变成一条错误,
        // 但也不能静默:失败时下面会记进 marketReadNote,列表顶上说出来。
        async let feedResult = DeskAPI.shared.get(url: site.feedURL, as: Feed.self)
        async let mrResult = DeskAPI.shared.get("/api/market-read", as: MarketReadResponse.self)

        var mrDates: [String] = []
        switch await mrResult {
        case .success(let m): mrDates = m.available; marketReadNote = nil
        case .failure(let e): marketReadNote = "市场读取不到：\(e.detail)"
        }

        switch await feedResult {
        case .failure(let e):
            // 博客站挂了 ≠ 这一页没东西可看。市场读住在**另一个服务**(desk API)上，
            // 当天成交也是。所以退化成「只有市场读」的列表，把 feed 的错当成一条说明印在顶上。
            // 之前这里一律 posts = []，于是博客一超时整页就空 —— 而那时候盘面服务好好的。
            // (模拟器 2026-08-30 实测正是这个形状：feed -1001 超时，market-read 200。)
            if mrDates.isEmpty {
                error = e; posts = []
            } else {
                error = nil
                feedNote = "复盘正文取不到（\(e.detail)）—— 下面是市场读与当天成交。"
                posts = mrDates.map(FeedPost.init(marketReadOnly:))
                    .sorted { $0.date > $1.date }
                marketReadOnlyDays = posts.count
                if let day = Self.openDayArg, let hit = posts.first(where: { $0.date == day }) {
                    path = [hit]
                }
            }
        case .success(let f):
            // 中英同一篇会各出现一次;日志只看中文那条,英文条会把时间线变成两倍长。
            let zh = f.posts.filter { $0.lang == "zh" }
            // **并集**:市场读有、feed 没有的日子补一条合成行。少了这一步,
            // 「今天的市场读已经进库、博文还没发」的那天在 app 里够不着 ——
            // 而自动链每天产出的正是这种天。
            let feedDates = Set(zh.map(\.date))
            let extra = mrDates.filter { !feedDates.contains($0) }.map(FeedPost.init(marketReadOnly:))
            marketReadOnlyDays = extra.count
            posts = (zh + extra).sorted { $0.date == $1.date ? $0.title < $1.title : $0.date > $1.date }
            feedNote = nil
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
                    } else if post.slug.isEmpty {
                        // 合成行:市场读有、博文还没发。用中性色,这是常态不是故障。
                        Text("市场读").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.ink.opacity(0.08)))
                            .foregroundStyle(Palette.ink.opacity(0.7))
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
    @State private var marketRead: MarketReadResponse?
    @State private var error: DeskError?
    @State private var ordersError: DeskError?
    @State private var marketReadError: DeskError?
    @State private var loading = true

    /// 详情页只渲某一张卡。**只为截图存在** —— `-dayOnly market|orders|post`。
    ///
    /// 和风控页的 `-riskOnly` 同一个理由:这一页有三张卡、比一屏长得多,市场读那张在博文
    /// 正文下面,模拟器上根本截不到。没有它,「下面那张对不对」就只能靠「编译过了」来相信,
    /// 而这个 app 栽过的坑(样条曲线、指数当分数、Text 拼接不渲染 markdown)全都编译得过。
    private static var onlyArg: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-dayOnly"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

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
                    if Self.onlyArg == nil, post.slug.isEmpty {
                        // 合成行:这一天只有市场读。**说清楚为什么没有复盘正文** ——
                        // 空着或者报一条「取不到」都会让人以为链子坏了,而这是设计中的常态。
                        Card {
                            Label("这一天的复盘还没发布（自动链只写不发，审完自己点）。下面是市场读与当天成交。",
                                  systemImage: "doc.badge.clock")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if Self.onlyArg != nil && Self.onlyArg != "post" {
                        EmptyView()
                    } else if loading && markdown == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let e = error {
                        ErrorCard(error: e)
                    } else if let md = markdown {
                        Card { MarkdownText(text: md) }     // 真渲染,不露字面 ** 与 |---|
                    }
                    if Self.onlyArg == nil || Self.onlyArg == "market" { marketReadCard }
                    if Self.onlyArg == nil || Self.onlyArg == "orders" { ordersCard }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(post.date)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// 当天的市场读 —— 「新闻」那一半。
    ///
    /// 和正文、成交一样是**独立来源**,所以错误也独立呈现:市场读没取到不该让复盘正文
    /// 跟着消失。同时**不静默** —— 取不到就把服务端原话印出来。
    /// (同源教训:blog-reader 那次撞闸静默贡献 0 篇,错误条上只有一句「解析失败」,
    ///  既不像错误也指不出方向。)
    private var marketReadCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("市场读", systemImage: "newspaper")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if let m = marketRead, m.date == post.date {
                        Text("\(m.chars) 字").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if let e = marketReadError {
                    if e.detail.contains("没有市场读") {
                        // 「这天没写」和「链子坏了」是两件事,服务端已经用 404 分开了,
                        // 这里也得分开显示 —— 否则每个周末都像出故障。
                        Text("这一天没有市场读。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label(e.detail, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.alarm)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let m = marketRead {
                    if m.date != post.date {
                        // 契约守卫,和成交那条同款:服务端没按天回显就拒绝显示。
                        // 老版本静默忽略 date 参数的坑在这个项目里已经踩过一次。
                        Label("服务端回显的日期是 \(m.date)，不是 \(post.date) —— 拒绝显示，"
                              + "否则这里会是另一天的市场读。",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(Palette.alarm)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        MarkdownText(text: m.body)          // 真渲染,不露字面 **
                    }
                } else {
                    ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
        async let ords = DeskAPI.shared.get("/api/orders?limit=200&date=\(post.date)", as: OrdersResponse.self)
        async let mr = DeskAPI.shared.get("/api/market-read?date=\(post.date)", as: MarketReadResponse.self)

        // 合成行没有 slug,**不发那个请求** —— 拿空 slug 去拼 URL 会得到一条
        // 必然失败的请求,然后在页面上显示成一条看着像故障的错误。
        if !post.slug.isEmpty {
            let url = Site.options.postURL(slug: post.slug, locale: post.lang)
            switch await DeskAPI.shared.get(url: url, as: PostDetail.self) {
            case .success(let d): markdown = d.markdown; error = nil
            case .failure(let e): error = e; markdown = nil
            }
        }
        switch await ords {
        case .success(let o): orders = o; ordersError = nil
        case .failure(let e): ordersError = e; orders = nil
        }
        switch await mr {
        case .success(let m): marketRead = m; marketReadError = nil
        case .failure(let e): marketReadError = e; marketRead = nil
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
