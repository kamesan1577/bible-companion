import Foundation

/// Only a successful response for the latest explicit plan can be confirmed.
public struct ComparisonPlanDraft: Sendable {
    public private(set) var generation = UUID()
    public private(set) var plan: JSONValue?
    public private(set) var estimate: JSONValue?
    public init() {}
    @discardableResult public mutating func begin() -> UUID {
        generation = UUID(); plan = nil; estimate = nil
        return generation
    }
    public mutating func invalidate() { begin() }
    @discardableResult public mutating func accept(plan: JSONValue, estimate: JSONValue, generation: UUID) -> Bool {
        guard self.generation == generation else { return false }
        self.plan = plan; self.estimate = estimate
        return true
    }
}
