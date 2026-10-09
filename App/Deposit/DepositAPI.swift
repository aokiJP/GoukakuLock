import Foundation
import GoukakuCore

/// 預け金のサーバーの設定(GET /v1/config)
struct DepositConfig: Codable, Equatable {
    var ready: Bool
    var publishableKey: String
    var testMode: Bool
    var currency: String
    var minDaily: Int
    var maxDaily: Int
    var days: Int
    var graceDays: Int
    var merchantName: String
    var requiresCode: Bool
}

/// サーバーから届く、1週分の預け金
struct DepositWeek: Codable, Equatable, Identifiable {
    struct Day: Codable, Equatable {
        var key: String
        var startsAt: Date
        var endsAt: Date
        var refunded: Bool
        var refundedAmount: Int
        var outcome: String?
        var refundStatus: String?

        var cycle: CycleID? { CycleID(key) }
    }

    enum Status: String, Codable {
        case pending, upcoming, active, ended, closed
    }

    var id: String
    var status: Status
    var daily: Int
    var total: Int
    var currency: String
    var days: [Day]
    var refunded: Int
    var forfeited: Int?
    var startsAt: Date
    var endsAt: Date
    var closesAt: Date
    var renew: Bool
    var next: String?
    var prev: String?
    var renewError: String?
    var livemode: Bool

    /// 返金の知らせをまだ受け付けているか
    var acceptsReports: Bool { status == .active || status == .ended }
}

struct DepositState: Codable {
    var deposits: [DepositWeek]
    var config: DepositConfig
}

struct DepositRegistration: Codable {
    var token: String
    var customerId: String
}

/// 支払いの用意(Stripe の画面に渡す)
struct DepositCheckout: Codable {
    var depositId: String
    var clientSecret: String
    var amount: Int
    var publishableKey: String
    var merchantName: String
}

/// サーバーからのエラー({"error":{"code","message"}})
struct DepositServerError: LocalizedError, Equatable {
    var status: Int
    var code: String
    var message: String

    var errorDescription: String? { message }
}

/// サーバーのエラーの形({"error":{"code","message"}})
private struct DepositErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var code: String
        var message: String
    }
    var error: Detail
}

/// 預け金のサーバーと話す(カード番号は扱わない。支払いは Stripe の画面が Stripe と直接やりとりする)
struct DepositAPI {
    var baseURL: URL
    var token: String?
    var session: URLSession = .shared

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    /// 入力された URL を整える(末尾の / を落とす・https を足す)。使えなければ nil
    static func normalize(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let url = URL(string: t), let scheme = url.scheme, ["https", "http"].contains(scheme), url.host != nil else {
            return nil
        }
        return url
    }

    func config() async throws -> DepositConfig {
        try await send("GET", "/v1/config", authorized: false)
    }

    func register(code: String?) async throws -> DepositRegistration {
        var body: [String: String] = [:]
        if let code, !code.isEmpty { body["code"] = code }
        return try await send("POST", "/v1/register", body: body, authorized: false)
    }

    func state() async throws -> DepositState {
        try await send("GET", "/v1/state")
    }

    func createDeposit(daily: Int, days: [DepositDay], renew: Bool) async throws -> DepositCheckout {
        struct Body: Encodable {
            struct Day: Encodable { var key: String; var startsAt: Int }
            var daily: Int
            var days: [Day]
            var endsAt: Int
            var renew: Bool
        }
        let body = Body(daily: daily,
                        days: days.map { .init(key: $0.key, startsAt: Int($0.startsAt.timeIntervalSince1970)) },
                        endsAt: Int((days.last?.endsAt ?? Date()).timeIntervalSince1970),
                        renew: renew)
        return try await send("POST", "/v1/deposits", body: body)
    }

    func report(depositID: String, day: String, outcome: CycleOutcome) async throws -> DepositWeek {
        try await send("POST", "/v1/deposits/\(escape(depositID))/days/\(escape(day))", body: ["outcome": outcome.rawValue])
    }

    func setRenew(depositID: String, on: Bool) async throws -> DepositWeek {
        try await send("POST", "/v1/deposits/\(escape(depositID))/renew", body: ["on": on])
    }

    /// やめる(まだ始まっていない日の分を返してもらい、自動で続けるのも止める)
    func cancel(depositID: String) async throws -> DepositWeek {
        try await send("POST", "/v1/deposits/\(escape(depositID))/cancel", body: [String: String]())
    }

    // MARK: 中身

    private func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? text
    }

    private func send<T: Decodable>(_ method: String, _ path: String, authorized: Bool = true) async throws -> T {
        try await send(method, path, body: Optional<[String: String]>.none, authorized: authorized)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?,
                                                  authorized: Bool = true) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString + path) else {
            throw DepositServerError(status: 0, code: "bad_url", message: "サーバーの URL がまちがっています")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            guard let token else { throw DepositServerError(status: 401, code: "unauthorized", message: "サーバーにつないでください") }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let envelope = try? Self.decoder.decode(DepositErrorEnvelope.self, from: data) {
                throw DepositServerError(status: status, code: envelope.error.code, message: envelope.error.message)
            }
            throw DepositServerError(status: status, code: "http_\(status)", message: "サーバーにつながりませんでした(\(status))")
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
