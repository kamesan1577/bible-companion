import Foundation

/// The server catalog is authoritative. Unknown/missing schemas never enable a
/// parameter or provider, and comparing models uses their common valid range.
public struct ModelSettingsBounds: Sendable, Equatable {
    public let outputTokens: ClosedRange<Int>
    public let temperature: ClosedRange<Double>
    public let timeoutMilliseconds: ClosedRange<Int>
    public init(models: [JSONValue]) throws {
        guard !models.isEmpty else { throw NetworkFailure.invalidResponse }
        var tokenMin = 0, tokenMax = 1_000_000, timeoutMin = 0, timeoutMax = 60_000
        var temperatureMin = 0.0, temperatureMax = 100.0
        for model in models {
            guard model["enabled"].bool == true else { throw NetworkFailure.invalidResponse }
            let schema = model["settingsSchema"]
            func range(_ field: String) throws -> ClosedRange<Double> {
                guard case .number(let lower) = schema[field]["minimum"], case .number(let upper) = schema[field]["maximum"], lower.isFinite, upper.isFinite, lower <= upper else { throw NetworkFailure.invalidResponse }
                return lower...upper
            }
            let tokens = try range("maxOutputTokens"), temp = try range("temperature"), timeout = try range("timeoutMs")
            guard tokens.lowerBound >= 1, tokens.upperBound <= 1_000_000, tokens.lowerBound.rounded() == tokens.lowerBound, tokens.upperBound.rounded() == tokens.upperBound,
                  timeout.lowerBound >= 1, timeout.upperBound <= 60_000, timeout.lowerBound.rounded() == timeout.lowerBound, timeout.upperBound.rounded() == timeout.upperBound,
                  temp.lowerBound >= 0, temp.upperBound <= 100 else { throw NetworkFailure.invalidResponse }
            tokenMin = max(tokenMin, Int(tokens.lowerBound)); tokenMax = min(tokenMax, Int(tokens.upperBound))
            timeoutMin = max(timeoutMin, Int(timeout.lowerBound)); timeoutMax = min(timeoutMax, Int(timeout.upperBound))
            temperatureMin = max(temperatureMin, temp.lowerBound); temperatureMax = min(temperatureMax, temp.upperBound)
        }
        guard tokenMin <= tokenMax, timeoutMin <= timeoutMax, temperatureMin <= temperatureMax else { throw NetworkFailure.invalidResponse }
        outputTokens = tokenMin...tokenMax; temperature = temperatureMin...temperatureMax; timeoutMilliseconds = timeoutMin...timeoutMax
    }
    public func accepts(tokens: Int, temperature: Double, timeout: Int) -> Bool {
        outputTokens.contains(tokens) && self.temperature.contains(temperature) && timeoutMilliseconds.contains(timeout)
    }
}
