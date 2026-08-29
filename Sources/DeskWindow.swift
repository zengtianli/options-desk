import Foundation

/// 窗口口径的 SSOT。
///
/// 锚日曾经散在 CurveView 里,而风控页用的是服务端默认的全窗口 —— 两页对同一件事
/// 给出不同的答案(回撤 −11.92% vs −9.62%),而且**两个都对**,只是窗口不同。
/// 用户看到的却是「这 app 自己都对不上」。所以锚日只此一处。
enum DeskWindow {
    /// 记分板锚日,与博客 `race_series.py` 的 `RACE_ANCHOR` 同一个日子。
    /// 改它 = 换了一个问题(那边注释写着「写死,禁改」,背后有一次真事故)。
    static let raceAnchor = "2026-07-09"

    /// 拼给服务端的查询串。
    static func startQuery(_ anchored: Bool = true) -> String {
        anchored ? "?start=\(raceAnchor)" : ""
    }
}
