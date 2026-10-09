import Foundation

/// 本体アプリを開く URL(ウィジェット・コントロールセンター・Live Activity から使う)
public enum DeepLink {
    public static let scheme = "goukakulock"

    public enum Route: String, Sendable {
        case home, checkin, emergency, timer
    }

    public static func url(_ route: Route) -> URL {
        URL(string: "\(scheme)://\(route.rawValue)")!
    }

    public static var checkIn: URL { url(.checkin) }
    public static var emergency: URL { url(.emergency) }
    public static var home: URL { url(.home) }
    public static var timer: URL { url(.timer) }

    public static func route(of url: URL) -> Route? {
        guard url.scheme == scheme else { return nil }
        return Route(rawValue: url.host ?? "")
    }
}

/// ウィジェットの種類(本体から再読み込みを頼むときに使う)
public enum WidgetKinds {
    public static let status = "GoukakuStatusWidget"
    public static let checkInControl = "com.aokijp.goukakulock.control.checkin"
}
