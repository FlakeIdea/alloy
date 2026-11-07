import Foundation

/// Every request Alloy makes goes through this session. It replaces the system's default User-Agent, which names the
/// macOS (Darwin) and CFNetwork versions, and the Accept-Language header, which lists the Mac's languages, so a
/// request says only that it comes from Alloy.
public enum AlloyHTTP {
    public static let headers: [String: String] = ["User-Agent": "Alloy", "Accept-Language": "en"]

    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = headers
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return configuration
    }

    public static let session = URLSession(configuration: configuration())
}
