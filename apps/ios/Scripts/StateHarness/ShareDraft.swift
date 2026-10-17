import Foundation
import CompanionCore

/// Compile with the exact SharedPreviewModel declaration (before its View), DEBUG,
/// and Boundaries.swift. No network, Apple storage, or simulator is used here.
@main enum ShareDraftChecks {
    @MainActor static func main() async throws {
        let alice = "11111111-1111-4111-8111-111111111111", bob = "22222222-2222-4222-8222-222222222222"
        let client = try APIClient(baseURL: URL(string:"https://example.test")!)
        ShareInbox.owner = alice; ShareInbox.capability = nil
        let model = SharedPreviewModel(); model.configureQA(client:client); model.draft = "Alice private draft"
        let initialOwner = try model.chatGPTHandoffOwner(); precondition(model.canSend && initialOwner == alice)
        ShareInbox.owner = bob; model.startQuestion()
        precondition(model.draft.isEmpty && model.queued.isEmpty && !model.canSend && model.aiRequests == 0)
        do { _ = try model.chatGPTHandoffOwner(); preconditionFailure("Old owner's draft could leave for ChatGPT") } catch {}
        ShareInbox.owner = nil
        let signedOut = SharedPreviewModel(); signedOut.configureQA(client:client); signedOut.draft = "Unbound draft"
        ShareInbox.owner = alice; signedOut.revalidateAccess()
        precondition(signedOut.draft.isEmpty && !signedOut.canSend && signedOut.aiRequests == 0)
        let noAI = SharedPreviewModel(); noAI.configureQA(client:client); noAI.draft = "External question"
        let externalOwner = try noAI.chatGPTHandoffOwner(); precondition(externalOwner == alice)
        ShareInbox.unavailable = true
        noAI.revalidateAccess(); precondition(noAI.draft.isEmpty && !noAI.canSend)
        ShareInbox.unavailable = false
        print("PASS draft-only account changes block AI submission and ChatGPT handoff, including sign-in from signed-out scope and unreadable identity; same-owner external handoff needs no AI capability")
    }
}
