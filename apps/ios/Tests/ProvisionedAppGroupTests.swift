import XCTest
@testable import CompanionCore

final class ProvisionedAppGroupTests: XCTestCase {
    private let base = "group.org.kamesan1577.BibleCompanion"
    func testExactAndSimulatorGroups() {
        XCTAssertEqual(ProvisionedAppGroup.resolve(configured: base, groups: nil), base)
        XCTAssertEqual(ProvisionedAppGroup.resolve(configured: base, groups: [base]), base)
        XCTAssertNil(ProvisionedAppGroup.resolve(configured: base, groups: []))
    }
    func testSideStoreSuffixAndAmbiguity() {
        XCTAssertEqual(ProvisionedAppGroup.resolve(configured: base, groups: [base + ".C5KX9LRQRY"]), base + ".C5KX9LRQRY")
        XCTAssertNil(ProvisionedAppGroup.resolve(configured: base, groups: [base + ".C5KX9LRQRY", base + ".ABCDE12345"]))
        XCTAssertNil(ProvisionedAppGroup.resolve(configured: base, groups: [base + ".other", "group.unrelated.C5KX9LRQRY"]))
    }
    func testProfilePayloadAndMalformedInput() throws {
        let plist: [String: Any] = ["Entitlements": ["com.apple.security.application-groups": [base + ".C5KX9LRQRY"]]]
        let payload = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        var envelope = Data([0x30, 0x82]); envelope.append(payload); envelope.append(0)
        XCTAssertEqual(ProvisionedAppGroup.groups(inProfile: envelope), [base + ".C5KX9LRQRY"])
        XCTAssertEqual(ProvisionedAppGroup.groups(inProfile: Data("invalid".utf8)), [])
    }
}
