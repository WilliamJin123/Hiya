import Foundation
import Observation

@MainActor
@Observable
final class SessionViewModel {
    enum State: Equatable { case loading, app, auth }
    enum GateDecision: Equatable { case app, auth, createAnonymous }

    private let repo: HiyaRepository
    private(set) var state: State = .loading
    private(set) var account: AuthAccount?
    private(set) var profile: Profile?
    var isWorking = false
    var errorMessage: String?

    private let graduatedKey = "hiya.hasGraduatedToAccount"
    private var hasGraduated: Bool {
        get { UserDefaults.standard.bool(forKey: graduatedKey) }
        set { UserDefaults.standard.set(newValue, forKey: graduatedKey) }
    }

    init(repo: HiyaRepository) { self.repo = repo }

    /// Pure gate decision: a live session → app; otherwise sign-in if this device
    /// has had a real account, else create a fresh anonymous session.
    static func decide(account: AuthAccount?, hasGraduated: Bool) -> GateDecision {
        if account != nil { return .app }
        return hasGraduated ? .auth : .createAnonymous
    }

    func start() async {
        let acct = await repo.currentAccount()
        switch Self.decide(account: acct, hasGraduated: hasGraduated) {
        case .app:
            account = acct
            profile = try? await repo.ensureSignedIn()
            state = .app
        case .auth:
            state = .auth
        case .createAnonymous:
            do {
                profile = try await repo.ensureSignedIn()
                account = await repo.currentAccount()
                state = .app
            } catch {
                errorMessage = error.localizedDescription
                state = .auth
            }
        }
    }

    func claim(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.claimAccount(email: email, password: password, displayName: displayName)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signUp(email: email, password: password, displayName: displayName)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.state = .app
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signIn(email: email, password: password)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.state = .app
        }
    }

    func signOut() async {
        do {
            try await repo.signOut()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        account = nil
        profile = nil
        hasGraduated = true
        state = .auth
    }

    func updateDisplayName(_ name: String) async -> Bool {
        await perform { self.profile = try await self.repo.updateDisplayName(name) }
    }

    @discardableResult
    private func perform(_ action: () async throws -> Void) async -> Bool {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do { try await action(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
}
