import Foundation

public protocol MonologuePromptStore: AnyObject, Sendable {
    var lastPrompt: String? { get set }
}

public final class InMemoryMonologuePromptStore: MonologuePromptStore, @unchecked Sendable {
    public var lastPrompt: String?
    public init(lastPrompt: String? = nil) {
        self.lastPrompt = lastPrompt
    }
}

public final class UserDefaultsMonologuePromptStore: MonologuePromptStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "monologue.lastPrompt"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var lastPrompt: String? {
        get { defaults.string(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
