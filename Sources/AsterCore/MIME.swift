import Foundation

public enum AddressParser {
    public static func parse(_ input: String) -> [Address] {
        var parts: [String] = [], current = "", quoted = false, escaped = false, bracket = 0
        for character in input {
            if character == "\\" && !escaped { escaped = true; current.append(character); continue }
            if character == "\"" && !escaped { quoted.toggle() }
            if !quoted && character == "<" { bracket += 1 }; if !quoted && character == ">" { bracket -= 1 }
            if character == "," && !quoted && bracket == 0 { parts.append(current); current = "" } else { current.append(character) }
            escaped = false
        }
        parts.append(current)
        return parts.compactMap { part in
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            if let start = value.lastIndex(of: "<"), let end = value.lastIndex(of: ">"), start < end {
                let email = String(value[value.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
                let name = String(value[..<start]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
                return Address(MIME.decodeHeader(name.isEmpty ? email : name), email)
            }
            return Address(value, value)
        }
    }
}
public enum MIME {
    public static func validAddress(_ address: String) -> Bool {
        guard !address.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "<" || $0 == ">" || $0 == "," }), address.count <= 254 else { return false }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
    private static func safeHeader(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw MailError.message("Email headers cannot contain line breaks.") }; return value
    }
    public static func encode(_ mail: Mail, replyingTo original: Mail? = nil, attachments: [OutgoingAttachment] = []) throws -> Data {
        func recipient(_ address: Address) throws -> String {
            guard validAddress(address.address) else { throw MailError.message("Invalid email address: \(address.address)") }
            _ = try safeHeader(address.name)
            let name = address.name == address.address ? "" : "=?UTF-8?B?" + Data(address.name.utf8).base64EncodedString() + "?= "
            return name + "<\(address.address)>"
        }
        if attachments.reduce(0, { $0 + $1.data.count }) > 20_000_000 { throw MailError.message("Attachments exceed the 20 MB total limit.") }
        let subject = try safeHeader(mail.subject)
        var lines = ["From: \(try recipient(mail.sender))", "To: \(try mail.to.map(recipient).joined(separator: ", "))"]
        if !mail.cc.isEmpty { lines.append("Cc: \(try mail.cc.map(recipient).joined(separator: ", "))") }
        if let bcc = mail.bcc, !bcc.isEmpty { lines.append("Bcc: \(try bcc.map(recipient).joined(separator: ", "))") }
        lines.append("Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=")
        lines += ["MIME-Version: 1.0", "Message-ID: <\(mail.id.hasPrefix("local-") ? String(mail.id.dropFirst(6)) : UUID().uuidString)@aster.local>"]
        if let original, let messageID = original.internetMessageID {
            lines.append("In-Reply-To: \(try safeHeader(messageID))")
            var seen: Set<String> = []
            let references = ((original.references ?? "") + " " + messageID).split(whereSeparator: \.isWhitespace).map(String.init).filter { seen.insert($0).inserted }
            lines.append("References: " + (try references.map(safeHeader)).joined(separator: "\r\n "))
        }
        let content = Data(mail.body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n").utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let contentType = mail.isHTML ? "text/html" : "text/plain"
        if attachments.isEmpty {
            lines += ["Content-Type: \(contentType); charset=UTF-8", "Content-Transfer-Encoding: base64"]
            return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + content + "\r\n").utf8)
        }
        let boundary = "aster-" + UUID().uuidString
        lines.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"")
        var body = "--\(boundary)\r\nContent-Type: \(contentType); charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n\(content)\r\n"
        for file in attachments {
            _ = try safeHeader(file.contentType); _ = try safeHeader(file.id)
            let filename = file.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "attachment"
            body += "--\(boundary)\r\nContent-Type: \(file.contentType)\r\nContent-Disposition: attachment; filename*=UTF-8''\(filename)\r\nContent-ID: <aster-\(file.id)>\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            body += file.data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n"
        }
        body += "--\(boundary)--\r\n"
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n" + body).utf8)
    }
    public static func decodeEntities(_ input: String) -> String {
        input.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
    }
    public static func plainText(_ input: String) -> String {
        decodeEntities(input.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression).replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
    }
    public static func decodeHeader(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "=\\?UTF-8\\?([bBqQ])\\?([^?]*)\\?=", options: .caseInsensitive) else { return value }
        var output = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let range = Range(match.range, in: output), let modeRange = Range(match.range(at: 1), in: value), let encodedRange = Range(match.range(at: 2), in: value) else { continue }
            let encoded = String(value[encodedRange]); let mode = value[modeRange].lowercased()
            let data: Data?
            if mode == "b" { data = Data(base64Encoded: encoded) }
            else {
                var bytes: [UInt8] = []; let source = Array(encoded.replacingOccurrences(of: "_", with: " ").utf8); var i = 0
                while i < source.count { if source[i] == 61, i + 2 < source.count, let byte = UInt8(String(bytes: source[(i+1)...(i+2)], encoding: .utf8) ?? "", radix: 16) { bytes.append(byte); i += 3 } else { bytes.append(source[i]); i += 1 } }; data = Data(bytes)
            }
            if let data, let decoded = String(data: data, encoding: .utf8) { output.replaceSubrange(range, with: decoded) }
        }
        return output
    }
}
