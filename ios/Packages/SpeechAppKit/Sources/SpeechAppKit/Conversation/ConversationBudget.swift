import Foundation

public struct ConversationBudgetSnapshot: Equatable, Sendable {
    public var limit: Int
    public var used: Int
    public var month: String
    public var startEnabled: Bool { used < limit }
    public var label: String { "\(used) of \(limit)" }
    public init(limit: Int, used: Int, month: String) {
        self.limit = limit
        self.used = used
        self.month = month
    }
}
