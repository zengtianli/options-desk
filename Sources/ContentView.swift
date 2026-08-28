import SwiftUI

/// 骨架屏。**故意只有一屏** —— `/appios` 硬约束：登录 + 一个主界面先装进模拟器看过，
/// 才允许写第 3 个界面。导航范式错了是 N 处返工，不是 1 处
/// （2026-08-27 fitcoach-ios 实证：14 个界面全写完才第一次编译）。
///
/// 内容留空是**对齐过的顺序**（2026-08-28 用户拍板「先修口径再建 app」）：
/// 现在建界面，「对 QQQ 的超额」那一栏根本算不出来 —— `qqq_close` 53 天里只有 36 天有值。
/// 首屏最重要的那个数是空的，等于先做一个注定要返工的版本。
struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.98).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.10, green: 0.62, blue: 0.45))
                Text("投资盘面").font(.title2.weight(.bold))
                Text("脚手架已就位，界面等数据口径修完再建。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("待办与判据见 CLAUDE.md")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .preferredColorScheme(.light)      // 全局约定：一律亮色，不自作主张上深色
    }
}
