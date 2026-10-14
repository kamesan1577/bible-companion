import Foundation

public enum PrivateDeletionKind: String, CaseIterable, Sendable {
    case readingData, account
    public var path: String { self == .account ? "/v1/me" : "/v1/me/reading-data" }
    public var confirmation: String { self == .account ? "DELETE_MY_ACCOUNT" : "DELETE_MY_READING_DATA" }
    public var title: String { self == .account ? "アカウントを削除" : "読書データをすべて削除" }
    public var explanation: String {
        self == .account ? "アカウント、パスキー登録、読書履歴、会話、保存した比較を削除し、ログインを失効します。この操作は元に戻せません。" : "読書履歴、会話、質問・回答、保存した比較を削除します。アカウントとパスキー登録は残ります。この操作は元に戻せません。"
    }
}
public struct DeletionResult: Decodable, Sendable {
    public let deleted: Bool
    public let accountRetained: Bool?
    public let sessionRevoked: Bool?
    public let backupErasurePolicy: String
    public func confirms(_ kind: PrivateDeletionKind) -> Bool {
        deleted && (kind == .account ? sessionRevoked == true : accountRetained == true)
    }
}
public struct DeletionIntent: Sendable {
    public let ownerID: String
    public let sessionEpoch: UUID
    public let kind: PrivateDeletionKind
    public init(ownerID: String, sessionEpoch: UUID, kind: PrivateDeletionKind) { self.ownerID = ownerID; self.sessionEpoch = sessionEpoch; self.kind = kind }
    public func permits(ownerID: String?, epoch: UUID, typedConfirmation: String) -> Bool {
        UUID(uuidString: self.ownerID) != nil && self.ownerID == ownerID && self.sessionEpoch == epoch && typedConfirmation == "削除"
    }
    public var body: JSONValue { .object(["confirmation": .string(kind.confirmation)]) }
}
