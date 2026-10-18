import Foundation

/// Only a fixed stage, reason and allowlisted numeric system code cross into UI.
/// No NSError userInfo, URL, group/account identifier or credential is retained.
public struct ShareStorageFailure: Error, Sendable {
    public enum Stage: String, Sendable {
        case directory, coordination, operation, ownerRead, ownerWrite
        case capabilityRead, capabilityWrite, validation, readback
    }
    public let reason: ShareAIAccessReadError
    public let stage: Stage
    public let systemCode: String?
    public var diagnosticCode: String { "S/" + stage.rawValue + "/" + (systemCode ?? String(describing: reason)) }
    public init(_ error: Error, stage: Stage, writing: Bool = false) {
        if let existing = error as? Self { self = existing; return }
        self.stage = stage
        if let typed = error as? ShareAIAccessReadError { reason = typed; systemCode = nil; return }
        let value = error as NSError
        systemCode = value.domain == NSCocoaErrorDomain ? "Cocoa-\(value.code)" : value.domain == NSPOSIXErrorDomain ? "POSIX-\(value.code)" : nil
        if Self.isMissing(error), stage != .directory, stage != .coordination { reason = .missing }
        else if Self.hasCode(error, cocoa: [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue], posix: [1, 13]) { reason = .accessDenied }
        else if Self.hasCode(error, cocoa: [CocoaError.fileWriteOutOfSpace.rawValue], posix: [28]) { reason = .storageFull }
        else { reason = stage == .coordination ? .coordinationFailed : writing ? .writeFailed : .readFailed }
    }
    public static func reason(for error: Error) -> ShareAIAccessReadError? {
        (error as? Self)?.reason ?? (error as? ShareAIAccessReadError)
    }
    public static func isMissing(_ error: Error) -> Bool {
        hasCode(error, cocoa: [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue], posix: [2])
    }
    private static func hasCode(_ error: Error, cocoa: [Int], posix: [Int], depth: Int = 0) -> Bool {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && cocoa.contains(value.code) { return true }
        if value.domain == NSPOSIXErrorDomain && posix.contains(value.code) { return true }
        guard depth < 3, let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return hasCode(underlying, cocoa: cocoa, posix: posix, depth: depth + 1)
    }
}
