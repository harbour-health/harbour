struct SpacingFixture {
    func double(_ value: Int?) -> Int {
        let text = """
        guard return
        let untouched = "return"
        """

        guard let value else {
            return 0
        }

        let doubled = value * 2

        return doubled
    }
}
