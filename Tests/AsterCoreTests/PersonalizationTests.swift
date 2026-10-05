import XCTest
@testable import AsterCore

final class PersonalizationTests: XCTestCase {
    func testAccountOverrideAndExplicitlyUnnamedIdentity() {
        XCTAssertEqual(SenderPersonalization.resolve(workspaceName: " Alex Rivera ", accountName: nil), "Alex Rivera")
        XCTAssertEqual(SenderPersonalization.resolve(workspaceName: "Alex Rivera", accountName: "Casey"), "Casey")
        XCTAssertEqual(SenderPersonalization.resolve(workspaceName: "Alex Rivera", accountName: ""), "")
    }
    func testBothWritingPromptsUseExplicitIdentityWithoutInventingRoles() throws {
        let reply = ReplyRequest(intent: "Choose A", senderAddress: "me@example.com", targetMessageID: "m", senderName: "Alex Rivera")
        let formal = FormaliseRequest(selectedText: "Choose A", style: WritingStyle(), senderAddress: "me@example.com", recipientAddress: "professor@example.edu", existingSubject: "", senderName: "Alex Rivera")
        for instructions in [reply.instructions, formal.instructions] {
            XCTAssertTrue(instructions.contains("Alex Rivera"))
            XCTAssertFalse(instructions.contains("Use [Your name] at the end."))
            XCTAssertTrue(instructions.contains("Do not infer their title, role or organization"))
        }
        XCTAssertTrue(ReplyRequest(intent: "Choose A", senderAddress: "me@example.com", targetMessageID: "m").instructions.contains("Never infer it"))
        XCTAssertThrowsError(try ReplyRequest(intent: "Choose A", senderAddress: "me@example.com", targetMessageID: "m", senderName: "Name\nInjected").validate())
        XCTAssertThrowsError(try SenderPersonalization.validate(String(repeating: "x", count: 121)))
        XCTAssertNoThrow(try SenderPersonalization.validate("Çağrı 李"))
    }
    func testKnownNameRepairsSignOffAndCustomSignatureTakesPrecedence() {
        XCTAssertEqual(SenderPersonalization.finish("Hello,\n\nYes.\n\nRegards,\n[Your name]", name: "Alex Rivera", signature: ""), "Hello,\n\nYes.\n\nRegards,\nAlex Rivera")
        XCTAssertEqual(SenderPersonalization.finish("Hello,\n\nYes.", name: "Alex Rivera", signature: ""), "Hello,\n\nYes.\n\nAlex Rivera")
        XCTAssertEqual(SenderPersonalization.finish("Regards,\nAlex Rivera.", name: "Alex Rivera", signature: ""), "Regards,\nAlex Rivera.")
        XCTAssertEqual(SenderPersonalization.finish("Regards,\n[Your name]", name: "Alex Rivera", signature: "Dr. A. Rivera"), "Regards,\nDr. A. Rivera")
        XCTAssertEqual(SenderPersonalization.finish("[Your name]", name: "", signature: ""), "[Your name]")
        var style = WritingStyle(); style.signature = "Dr. A. Rivera"
        XCTAssertTrue(ReplyRequest(intent: "Yes", style: style, senderAddress: "me@example.com", targetMessageID: "m", senderName: "Alex Rivera").instructions.contains("takes precedence"))
    }
    func testOldPoliciesDecodeAndNamesPersistIndependentlyFromStyle() throws {
        let old = try JSONDecoder().decode(AccountPolicy.self, from: Data(#"{"priorityMode":"important","junkMode":"separate","hideJunkFolder":false,"hiddenFolders":[],"prioritySenders":[]}"#.utf8))
        XCTAssertNil(old.senderName)
        var policy = old; policy.senderName = "Casey"
        policy.writingStyle = WritingStyle()
        let copy = try JSONDecoder().decode(AccountPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(copy.senderName, "Casey")
        policy.writingStyle = nil
        XCTAssertEqual(policy.senderName, "Casey")
    }
}
