import Foundation

public enum ToolOutputGrammarError: LocalizedError, Equatable {
    case emptyTools, invalidToolName
    public var errorDescription: String? {
        switch self {
        case .emptyTools: "No tools are available for this request."
        case .invalidToolName: "The available tool names could not be prepared."
        }
    }
}

public enum ToolOutputGrammar {
    public static func make(allowedTools: [String]) throws -> String {
        guard !allowedTools.isEmpty else { throw ToolOutputGrammarError.emptyTools }
        var seen = Set<String>(), names: [String] = []
        for name in allowedTools {
            let bytes = Array(name.utf8)
            guard let first = bytes.first, (97...122).contains(first),
                  bytes.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else {
                throw ToolOutputGrammarError.invalidToolName
            }
            if seen.insert(name).inserted { names.append("\"\(name)\"") }
        }
        return #"""
        root ::= "{\"tool\":\"" tool "\",\"arg\":\"\"}"
        tool ::= \#(names.joined(separator: " | "))
        """#
    }
}
