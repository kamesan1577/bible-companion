import Foundation
import XCTest
@testable import CompanionCore

final class ShareStorageFailureTests: XCTestCase {
    func testActualMissingFileHandleUsesCocoa4() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("missing-" + UUID().uuidString)
        XCTAssertThrowsError(try FileHandle(forReadingFrom: url)) { error in
            XCTAssertTrue(ShareStorageFailure.isMissing(error))
            XCTAssertEqual(ShareStorageFailure(error, stage: .capabilityRead).reason, .missing)
        }
        for code in [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue] {
            XCTAssertTrue(ShareStorageFailure.isMissing(NSError(domain: NSCocoaErrorDomain, code: code)))
        }
        let nested = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 2)])
        XCTAssertTrue(ShareStorageFailure.isMissing(nested))
    }
    func testDirectoryAndCoordinationMissingErrorsAreNotMissingCredentials() {
        let error = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue)
        XCTAssertEqual(ShareStorageFailure(error, stage: .directory).reason, .readFailed)
        XCTAssertEqual(ShareStorageFailure(error, stage: .coordination).reason, .coordinationFailed)
    }
    func testPermissionIsNotProofOfDeviceLock() {
        for error in [NSError(domain: NSPOSIXErrorDomain, code: 1), NSError(domain: NSPOSIXErrorDomain, code: 13), NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadNoPermission.rawValue)] {
            let failure = ShareStorageFailure(error, stage: .capabilityRead)
            XCTAssertEqual(failure.reason, .accessDenied)
            XCTAssertNotEqual(failure.reason, .protectedDataUnavailable)
            XCTAssertFalse(SharePreparationFailure.message(for: failure).contains("ロックを解除して"))
        }
    }
    func testStageAndSafeCodeSurviveWrappingWithoutPrivateErrorContents() {
        let secret = "bcs1_secret /private/path group.personal owner-id"
        let error = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSLocalizedDescriptionKey: secret, NSFilePathErrorKey: secret])
        let failure = ShareStorageFailure(error, stage: .capabilityRead)
        XCTAssertEqual(failure.reason, .readFailed)
        XCTAssertEqual(failure.diagnosticCode, "S/capabilityRead/Cocoa-256")
        XCTAssertEqual(ShareStorageFailure(failure, stage: .operation).diagnosticCode, failure.diagnosticCode)
        let message = SharePreparationFailure.message(for: failure)
        XCTAssertTrue(message.contains(failure.diagnosticCode))
        XCTAssertFalse(message.contains(secret))
        XCTAssertFalse(message.contains("ロックを解除して"))
        let unknown = ShareStorageFailure(NSError(domain: secret, code: 999), stage: .readback, writing: true)
        XCTAssertFalse(unknown.diagnosticCode.contains(secret))
        XCTAssertEqual(unknown.reason, .writeFailed)
    }
    func testFullDiskAndCoordinationHaveDifferentRecovery() {
        XCTAssertEqual(ShareStorageFailure(NSError(domain: NSPOSIXErrorDomain, code: 28), stage: .capabilityWrite, writing: true).reason, .storageFull)
        XCTAssertEqual(ShareStorageFailure(NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError), stage: .coordination).reason, .coordinationFailed)
        XCTAssertFalse(SharePreparationFailure.message(for: ShareAIAccessReadError.corrupted).contains("ロックを解除して"))
    }
}
