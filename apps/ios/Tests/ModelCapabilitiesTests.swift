import XCTest
@testable import CompanionCore

final class ModelCapabilitiesTests: XCTestCase {
    func model(enabled: Bool = true, maximum: Double = 2048, temperature: Double = 2) -> JSONValue {
        .object(["enabled": .bool(enabled), "settingsSchema": .object([
            "maxOutputTokens": .object(["minimum": .number(64), "maximum": .number(maximum)]),
            "temperature": .object(["minimum": .number(0), "maximum": .number(temperature)]),
            "timeoutMs": .object(["minimum": .number(1000), "maximum": .number(30000)])])])
    }
    func testComparisonUsesCommonCapabilityBounds() throws {
        let bounds = try ModelSettingsBounds(models: [model(), model(maximum: 512, temperature: 1)])
        XCTAssertEqual(bounds.outputTokens, 64...512); XCTAssertEqual(bounds.temperature, 0...1)
        XCTAssertTrue(bounds.accepts(tokens: 512, temperature: 0.2, timeout: 15000))
        XCTAssertFalse(bounds.accepts(tokens: 1024, temperature: 0.2, timeout: 15000))
        XCTAssertFalse(bounds.accepts(tokens: 128, temperature: 2, timeout: 15000))
    }
    func testUnknownDisconnectedAndMalformedFailClosed() {
        XCTAssertThrowsError(try ModelSettingsBounds(models: []))
        XCTAssertThrowsError(try ModelSettingsBounds(models: [.null]))
        XCTAssertThrowsError(try ModelSettingsBounds(models: [model(enabled: false)]))
        XCTAssertThrowsError(try ModelSettingsBounds(models: [model(maximum: 63)]))
        XCTAssertThrowsError(try ModelSettingsBounds(models: [model(maximum: 512.5)]))
    }
}
