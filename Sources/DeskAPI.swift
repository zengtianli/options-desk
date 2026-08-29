import Foundation

// =============================================================================
// 闸内取数的**唯一通路**。
//
// 为什么抽出来:这个 app 有五个页面要取数(盘面/日志/持仓/曲线/风控),而 authgate
// 的「撞闸 → 用钥匙串里的密码换会话 → 重试一次」如果在每个页面各写一份,就是五份
// 会各自漂移的判据。第一次改闸的行为(比如 cookie 名变了)就会有几页悄悄坏掉、
// 另几页还好着 —— 而且坏的那几页表现是「解码失败」,指向完全错误的方向。
//
// 所以:判据只有这一处。页面只说要哪个 path,不碰 cookie、不碰登录、不碰重试。
// =============================================================================

final class DeskAPI: @unchecked Sendable {
    static let shared = DeskAPI(base: FactsSourceFactory.resolvedBase())

    let base: String
    let session: URLSession

    init(base: String) {
        self.base = base
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared          // 域 .tianli.cyou,跨启动保留,也跨子站共用
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: c)
    }

    /// 取一个 URL 的原始字节。撞闸就换一次会话再重试**一次**(只一次:密码错的话
    /// 无限重试等于拿错密码反复撞限流,而界面上什么都看不出来)。
    func fetch(_ url: URL) async -> Result<Data, DeskError> {
        let shown = url.absoluteString
        await Gate.seedFromLaunchArg(session: session)
        do {
            var (data, resp) = try await session.data(from: url)
            if Gate.blocked(resp) {
                guard let pw = Gate.password else {
                    return .failure(.gate(url: shown, reason: "这台设备还没有闸凭证（iOS 钥匙串里没有密码）"))
                }
                do { try await Gate.login(password: pw, session: session) }
                catch {
                    return .failure(.gate(url: shown,
                        reason: (error as? Gate.Failure)?.message ?? "登录失败"))
                }
                (data, resp) = try await session.data(from: url)
                if Gate.blocked(resp) {
                    return .failure(.gate(url: shown, reason: "拿密码换了会话之后仍被拦 —— 密码可能已经改了"))
                }
            }
            guard let http = resp as? HTTPURLResponse else {
                return .failure(.network(url: shown, underlying: "响应不是 HTTP"))
            }
            guard http.statusCode == 200 else {
                return .failure(.http(url: shown, status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "<非文本>"))
            }
            return .success(data)
        } catch {
            return .failure(.network(url: shown, underlying: LiveFactsSource.brief(error)))
        }
    }

    /// 解码。**字段对不上就点名是哪个字段**,不容错、不填默认值 ——
    /// 容错会把「服务端契约漂了」变成「界面上静静显示一个错数」。
    func decode<T: Decodable>(_ data: Data, as type: T.Type, from shown: String) -> Result<T, DeskError> {
        do { return .success(try JSONDecoder().decode(T.self, from: data)) }
        catch let DecodingError.keyNotFound(key, ctx) {
            return .failure(.decoding(url: shown, field: key.stringValue, detail: ctx.debugDescription))
        }
        catch let DecodingError.typeMismatch(_, ctx) {
            return .failure(.decoding(url: shown,
                                      field: ctx.codingPath.map(\.stringValue).joined(separator: "."),
                                      detail: ctx.debugDescription))
        }
        catch let DecodingError.valueNotFound(_, ctx) {
            return .failure(.decoding(url: shown,
                                      field: ctx.codingPath.map(\.stringValue).joined(separator: "."),
                                      detail: "值是 null，但契约要求非空：" + ctx.debugDescription))
        }
        catch { return .failure(.decoding(url: shown, field: "(整个响应体)", detail: "\(error)")) }
    }

    func get<T: Decodable>(_ path: String, as type: T.Type) async -> Result<T, DeskError> {
        guard let url = URL(string: base + path) else {
            return .failure(.notConfigured(baseURL: base))
        }
        switch await fetch(url) {
        case .failure(let e): return .failure(e)
        case .success(let d): return decode(d, as: T.self, from: url.absoluteString)
        }
    }

    /// 博客子站在另一个 host 上（同一个闸、同一个 cookie 域），所以走绝对 URL。
    func get<T: Decodable>(url: URL, as type: T.Type) async -> Result<T, DeskError> {
        switch await fetch(url) {
        case .failure(let e): return .failure(e)
        case .success(let d): return decode(d, as: T.self, from: url.absoluteString)
        }
    }
}
