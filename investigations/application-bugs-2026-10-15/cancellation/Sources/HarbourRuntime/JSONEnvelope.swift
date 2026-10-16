import Foundation

public enum JSONEnvelope {
    /// Find the completed outer object, without treating nested objects or string braces as its end.
    public static func completePrefix(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0, quoted = false, escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else {
                if character == "\"" { quoted = true }
                else if character == "{" { depth += 1 }
                else if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
        }
        return nil
    }
}
