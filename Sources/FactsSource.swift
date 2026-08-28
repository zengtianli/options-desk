import Foundation

protocol FactsSource {
    func load() async -> Result<DeskFacts, DeskError>
}

/// 本地样本源。**数字是真的**(2026-08-29 用回填完 qqq_close 之后的 quant.db 实算,
/// 口径:两账户合并总账 · 逐日链接 TWR · 当日现金流计入期初基数),
/// 这样第一屏截图里看到的排版就是上线后真实的量级,不会出现「样本里三位数、真数据五位数」那种返工。
///
/// 它存在的理由是 `/appios` 那条硬约束:登录 + 一个主界面**先装进模拟器看过**,
/// 才允许写第 3 个界面。此刻 stockoptions API 还在换数据源,不该为了看一眼排版就干等。
struct SampleFactsSource: FactsSource {
    /// 让调用方能把「陈旧」这条路径也截图看一眼 —— 它是本 app 最重要的防死机制,
    /// 不能只在真的坏掉那天才第一次见到它长什么样。
    var asofOverride: Date?

    func load() async -> Result<DeskFacts, DeskError> {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 27; c.hour = 16; c.timeZone = TimeZone(identifier: "America/New_York")
        let asof = asofOverride ?? Calendar(identifier: .gregorian).date(from: c)!
        return .success(DeskFacts(
            asof: asof,
            nlv: 1_365_065.86,
            twrCumulative: 0.2335,
            qqqCumulative: 0.0188,
            sampleDays: 49,
            accounts: ["5UK56277", "700013444"]
        ))
    }
}

/// 线上源。**故意还没实装** —— stockoptions 的 API 正在把数据源从 2026-06 就停更的
/// JSON/CSV 换成活的 quant.db(见 handoffs/data-truth-fix.md)。契约定死之前写解码
/// 等于按「我以为它这么实现」写一遍,那是最隐蔽的一种假验证。
///
/// 契约落定后,要改的**只有这一个文件**:DeskFacts 是 app 自己的模型,视图层不动。
struct LiveFactsSource: FactsSource {
    let baseURL: String

    func load() async -> Result<DeskFacts, DeskError> {
        .failure(.notConfigured(baseURL: baseURL.isEmpty ? "(未设置)" : baseURL))
    }
}
