import Foundation

/// Sender identity is explicit user input, never guessed from addresses or incoming mail.
public enum SenderPersonalization {
    public static func resolve(workspaceName: String, accountName: String?) -> String {
        (accountName ?? workspaceName).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func validate(_ name: String) throws {
        guard name.count <= 120, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw MailError.message("Use a name of up to 120 characters on one line.")
        }
    }
    public static func instructions(name: String?, signature: String) -> String {
        let known = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = known.isEmpty ? "Sender name is not provided. Never infer it from an address or incoming email." : "The sender's explicitly saved name is \(String(reflecting: known)). This is the user writing the email, not the recipient. Use it as their identity; do not replace it with a name from the conversation. Do not infer their title, role or organization."
        if !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return identity + "\nInclude the user's custom signature verbatim at the end; it takes precedence over a default name-only signature:\n" + signature }
        return identity + (known.isEmpty ? "\nUse [Your name] at the end." : "\nSign the email with this exact name after a suitable closing: " + known)
    }
    /// A model occasionally leaves a name placeholder or omits the requested signature.
    /// A supplied custom signature takes precedence over the default name.
    public static func finish(_ body: String, name: String?, signature: String) -> String {
        var result = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = !signature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let signOff = custom ? signature : known
        guard !result.isEmpty, !signOff.isEmpty else { return result }
        for placeholder in ["[Your name]", "[Your full name]", "[Sender name]"] {
            result = result.replacingOccurrences(of: placeholder, with: signOff, options: .caseInsensitive)
        }
        if custom {
            if !result.hasSuffix(signature) { result += "\n\n" + signature }
            return result
        }
        let lastLine = result.split(separator: "\n").last.map(String.init) ?? ""
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        if lastLine.trimmingCharacters(in: trim).caseInsensitiveCompare(known.trimmingCharacters(in: trim)) != .orderedSame { result += "\n\n" + known }
        return result
    }
}
