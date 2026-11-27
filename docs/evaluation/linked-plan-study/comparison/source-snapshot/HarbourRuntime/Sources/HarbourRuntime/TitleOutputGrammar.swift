public enum TitleOutputGrammar {
    public static let maximumCharacters = 60

    public static func make() -> String {
        #"""
        root ::= ws "{" ws "\"title\"" ws ":" ws string ws "}" ws
        string ::= "\"" character{1,\#(maximumCharacters)} "\""
        character ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
        ws ::= [ \t\n\r]{0,4}
        """#
    }
}
