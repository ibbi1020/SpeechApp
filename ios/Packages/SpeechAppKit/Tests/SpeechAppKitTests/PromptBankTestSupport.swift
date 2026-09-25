import Testing

func expectNoBannedThemes(_ prompts: [String], _ banned: [String]) {
    for prompt in prompts {
        let lower = prompt.lowercased()
        for term in banned {
            #expect(!lower.contains(term), "banned theme \(term) in: \(prompt)")
        }
    }
}
