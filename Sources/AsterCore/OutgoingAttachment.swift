import Foundation

public struct OutgoingAttachment: Sendable {
    public let id: String
    public let name: String
    public let contentType: String
    public let data: Data
    public init(id: String, name: String, contentType: String, data: Data) { self.id = id; self.name = name; self.contentType = contentType; self.data = data }
}
