import SwiftUI

/// 取数 + 三态呈现的公共壳(加载中 / 出错 / 有数)。
///
/// 为什么值得单独一个:四个页面都要写这三态。各写一份的结果是**错误呈现会不一致** ——
/// 有的页面把撞闸显示成「解码失败」,有的干脆转圈到超时。姊妹 app 那条只有一句
/// 「解析失败」的错误条就是这么来的:既不像错误,也指不出方向。
struct Loader<T: Decodable, C: View>: View {
    let path: String
    let content: (T) -> C

    init(_ path: String, @ViewBuilder content: @escaping (T) -> C) {
        self.path = path
        self.content = content
    }

    @State private var value: T?
    @State private var error: DeskError?
    @State private var loading = true

    var body: some View {
        Group {
            if FactsSourceFactory.isSample {
                // 样本档只有首屏有真样本。这里明说,而不是转圈到超时 ——
                // 超时看起来像服务端坏了,会把人引去查一个根本没坏的东西。
                Card {
                    Label("样本模式：本页需要联网", systemImage: "wifi.slash")
                        .font(.subheadline.weight(.medium))
                    Text("去掉 -sample 启动参数即可。首屏有离线样本，其余页面没有 —— 不做假数据。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
            } else if loading && value == nil {
                ProgressView().padding(.top, 60).frame(maxWidth: .infinity)
            } else if let e = error {
                ErrorCard(error: e)
            } else if let v = value {
                content(v)
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard !FactsSourceFactory.isSample else { loading = false; return }
        loading = true
        switch await DeskAPI.shared.get(path, as: T.self) {
        case .success(let v): value = v; error = nil
        case .failure(let e): error = e; value = nil
        }
        loading = false
    }
}

/// 页面标题栏。五个页面共用一条,免得每页各写各的间距。
struct PageHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.largeTitle.weight(.bold))
            if let s = subtitle {
                Text(s).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

/// 一行「键 : 值」。多属性内容一律走这个,不铺 bullet 列表。
struct KV: View {
    let k: String
    let v: String
    var mono = false
    var tint: Color?
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k).font(.caption).foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(v)
                .font(mono ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(tint ?? Palette.ink.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// ── 共用格式化(首屏那几个在 ContentView 里,这里补数量/日期用的) ──────────────
func usd2(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"
    f.maximumFractionDigits = 2; f.minimumFractionDigits = 2
    return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
}
func qty(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
/// 交易所日历上的 `YYYY-MM-DD` → Date。**只此一份** ——
/// 图表的 x 轴必须是真日期(拿字符串当类目轴会把几百个标签糊成一条黑线,实测),
/// 而两个页面各建一个 DateFormatter 就是两处会漂的时区判据。
let exchangeYMD: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "America/New_York")   // 交易日是交易所日历上的日子
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// `YYYY-MM-DD` → 距今天几个自然日(负数=已过)。到期天数用它。
func daysFromToday(_ ymd: String, now: Date = Date()) -> Int? {
    guard let d = exchangeYMD.date(from: ymd) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let a = cal.startOfDay(for: now), b = cal.startOfDay(for: d)
    return cal.dateComponents([.day], from: a, to: b).day
}
