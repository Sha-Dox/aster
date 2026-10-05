import Foundation

/// Credentialed API requests never follow redirects. Only idempotent reads are automatically retried.
public final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct HTTPTransport: Sendable {
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 40
        return URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }()
    public static func execute(_ request: URLRequest, session: URLSession = Self.session) async throws -> (Data, HTTPURLResponse) {
        let mayRetry = request.httpMethod == "GET" || request.httpMethod == "HEAD"
        for attempt in 0...3 {
            try Task.checkCancellation()
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw MailError.message("The mail service returned an invalid response.") }
                if mayRetry && [429, 500, 502, 503, 504].contains(http.statusCode) && attempt < 3 {
                    let delay = retryDelay(header: http.value(forHTTPHeaderField: "Retry-After"), attempt: attempt)
                    try await Task.sleep(for: .seconds(delay)); continue
                }
                return (data, http)
            } catch let error as URLError where mayRetry && attempt < 3 && [.timedOut, .networkConnectionLost].contains(error.code) {
                try await Task.sleep(for: .seconds(Double(1 << attempt)))
            }
        }
        throw MailError.message("Request retries exhausted.")
    }
    public static func retryDelay(header: String?, attempt: Int, now: Date = Date()) -> Double {
        if let header, let seconds = Double(header) { return min(max(seconds, 0), 30) }
        if let header {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = formatter.date(from: header) { return min(max(date.timeIntervalSince(now), 0), 30) }
        }
        return min(Double(1 << min(attempt, 5)) + Double.random(in: 0...0.3), 30)
    }
}
