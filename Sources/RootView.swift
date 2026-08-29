import SwiftUI

/// 五个页面。
///
/// 顺序是按「多久看一次」排的,不是按重要性:
/// 盘面(每天开一眼) → 日志(每天写完看一眼) → 持仓(要动手时) → 曲线(每周) → 风控(出事时)。
/// 把风控放第一个会让它天天在眼前晃,晃到出事那天也没人看。
struct RootView: View {
    /// 起始页。**只为调试/截图存在** —— `-tab 0..4`，默认 0（盘面）。
    /// 为什么需要它:模拟器截图只能截当前那一屏,没有这个参数就没法把五页各验一遍,
    /// 而「编译过了」和「这页渲染对不对」是两件事。
    @State private var tab: Int = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-tab"), i + 1 < a.count, let n = Int(a[i + 1]) else { return 0 }
        return max(0, min(4, n))
    }()

    var body: some View {
        TabView(selection: $tab) {
            ContentView()
                .tabItem { Label("盘面", systemImage: "gauge.with.dots.needle.50percent") }
                .tag(0)
            JournalView()
                .tabItem { Label("日志", systemImage: "calendar.day.timeline.left") }
                .tag(1)
            PositionsView()
                .tabItem { Label("持仓", systemImage: "square.stack.3d.up") }
                .tag(2)
            CurveView()
                .tabItem { Label("曲线", systemImage: "chart.xyaxis.line") }
                .tag(3)
            RiskView()
                .tabItem { Label("风控", systemImage: "shield.lefthalf.filled") }
                .tag(4)
        }
        .tint(Palette.gain)
        .preferredColorScheme(.light)   // 全局约定:一律亮色
    }
}
