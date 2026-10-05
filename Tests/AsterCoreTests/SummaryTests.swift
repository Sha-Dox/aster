import XCTest
@testable import AsterCore

final class SummaryTests: XCTestCase {
    func testRemoteSummaryAllowsNoDetailsAndPreservesConcreteRequest() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        defer { StubProtocol.handler = nil }
        StubProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = payload["messages"] as! [[String: String]]
            XCTAssertTrue(messages[0]["content"]!.contains("complete, useful sentences"))
            return (200, Data(#"{"choices":[{"message":{"content":"{\"summary\":\"Casey wants a rough annual production range to plan tooling.\",\"action\":\"Send the range and explain any uncertainty.\",\"details\":[]}"}}]}"#.utf8))
        }
        let notes = try await RemoteIntelligence(endpoint: URL(string: "https://model.example.com/v1")!, model: "fixture", key: "", session: URLSession(configuration: config)).summarize([DemoMail.messages()[0]])
        XCTAssertTrue(notes.summary.contains("annual")); XCTAssertTrue(notes.action.contains("uncertainty")); XCTAssertTrue(notes.details.isEmpty)
    }
}
