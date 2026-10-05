import XCTest
@testable import AsterCore

final class FormalisationTests: XCTestCase {
    func testSelectionUsesUTF16AndOnlyTheSelectedPassage() throws {
        let text = "Unselected 😀 choose A, replace X with Y. Other notes."
        let range = (text as NSString).range(of: "choose A, replace X with Y.")
        XCTAssertEqual(try SelectedPassage.extract(from: text, range: range), "choose A, replace X with Y.")
        XCTAssertThrowsError(try SelectedPassage.extract(from: text, range: NSRange(location: 0, length: 0)))
        let emoji = (text as NSString).range(of: "😀")
        XCTAssertThrowsError(try SelectedPassage.extract(from: text, range: NSRange(location: emoji.location, length: 1)))
        XCTAssertThrowsError(try SelectedPassage.extract(from: text, range: NSRange(location: NSNotFound, length: 1)))
    }
    func testFormaliseMeansWholeEmailWithFormalToneAndPreservedDecision() throws {
        var style = WritingStyle(); style.tone = .casual; style.language = "Turkish"
        let request = FormaliseRequest(selectedText: "Choose A, replace X with Y", style: style, senderAddress: "me@example.com", recipientAddress: "professor@example.edu", existingSubject: "")
        try request.validate()
        XCTAssertEqual(request.style.tone, .formal)
        XCTAssertTrue(request.instructions.contains("complete formal email"))
        XCTAssertTrue(request.instructions.contains("Choose A, replace X with Y"))
        XCTAssertTrue(request.instructions.contains("Turkish"))
    }
    func testRemoteFormalisationProducesSubjectAndBody() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        defer { StubProtocol.handler = nil }
        StubProtocol.handler = { request in
            let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = object["messages"] as! [[String: String]]
            XCTAssertTrue(messages[0]["content"]!.contains("choose A with Y"))
            return (200, Data(#"{"choices":[{"message":{"content":"{\"subject\":\"Presentation preference\",\"body\":\"Dear Professor,\\n\\nI would prefer option A with Y.\\n\\nBest regards,\\nAlex\"}"}}]}"#.utf8))
        }
        let request = FormaliseRequest(selectedText: "choose A with Y", style: WritingStyle(), senderAddress: "me@example.com", recipientAddress: "professor@example.edu", existingSubject: "")
        let email = try await RemoteIntelligence(endpoint: URL(string: "https://model.example.com/v1")!, model: "test", key: "", session: URLSession(configuration: config)).formalise([], request: request)
        XCTAssertEqual(email.subject, "Presentation preference"); XCTAssertTrue(email.body.contains("Dear Professor"))
    }
}
