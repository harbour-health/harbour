public enum VisitSummaryOutputGrammar {
    public static let maximumItemsPerCategory = 12
    public static let maximumQuoteCharacters = 600
    public static let maximumNameCharacters = 100
    public static let maximumInstructionCharacters = 180

    public static func make() -> String {
        #"""
        root ::= ws "{" ws "\"highlights\"" ws ":" ws quotes ws "," ws "\"medicines\"" ws ":" ws medicines ws "," ws "\"followUps\"" ws ":" ws quotes ws "," ws "\"appointments\"" ws ":" ws quotes ws "}" ws
        quotes ::= "[" ws (quote (ws "," ws quote){0,\#(maximumItemsPerCategory - 1)})? ws "]"
        quote ::= "{" ws "\"quote\"" ws ":" ws quote-string ws "}"
        medicines ::= "[" ws (medicine (ws "," ws medicine){0,\#(maximumItemsPerCategory - 1)})? ws "]"
        medicine ::= active-medicine | stop-medicine
        active-medicine ::= "{" ws "\"action\"" ws ":" ws active-action ws "," ws "\"name\"" ws ":" ws name-string ws "," ws "\"instructions\"" ws ":" ws instruction-string ws "," ws "\"quote\"" ws ":" ws quote-string ws "}"
        stop-medicine ::= "{" ws "\"action\"" ws ":" ws "\"stop\"" ws "," ws "\"name\"" ws ":" ws name-string ws "," ws "\"instructions\"" ws ":" ws "\"\"" ws "," ws "\"quote\"" ws ":" ws quote-string ws "}"
        active-action ::= "\"start\"" | "\"update\""
        quote-string ::= "\"" character{4,\#(maximumQuoteCharacters)} "\""
        name-string ::= "\"" character{1,\#(maximumNameCharacters)} "\""
        instruction-string ::= "\"" character{1,\#(maximumInstructionCharacters)} "\""
        character ::= [^"\\\x00-\x1F] | "\\" (["\\/bfnrt] | "u" [0-9a-fA-F]{4})
        ws ::= [ \t\n\r]{0,4}
        """#
    }
}
