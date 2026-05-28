import Foundation
import Observation

@MainActor
@Observable
final class SessionViewModel {
    enum State: Equatable { case loading, app, onboarding, auth }
    enum GateDecision: Equatable { case app, auth, createAnonymous }

    private let repo: HiyaRepository
    private let defaults: UserDefaults
    private let cache: SessionCache
    private(set) var state: State = .loading
    private(set) var account: AuthAccount?
    private(set) var profile: Profile?
    var isWorking = false
    var errorMessage: String?

    private let graduatedKey = "hiya.hasGraduatedToAccount"
    private let onboardedKey = "hiya.hasOnboarded"

    private var hasGraduated: Bool {
        get { defaults.bool(forKey: graduatedKey) }
        set { defaults.set(newValue, forKey: graduatedKey) }
    }
    private var hasOnboarded: Bool {
        get { defaults.bool(forKey: onboardedKey) }
        set { defaults.set(newValue, forKey: onboardedKey) }
    }

    init(repo: HiyaRepository, defaults: UserDefaults = .standard) {
        self.repo = repo
        self.defaults = defaults
        self.cache = SessionCache(defaults: defaults)
    }

    /// Pure gate decision: a live session → app; otherwise sign-in if this device
    /// has had a real account, else create a fresh anonymous session.
    static func decide(account: AuthAccount?, hasGraduated: Bool) -> GateDecision {
        if account != nil { return .app }
        return hasGraduated ? .auth : .createAnonymous
    }

    func start() async {
        // Optimistic hydration: render cached profile/account immediately so
        // the gate flips out of `.loading` on the first frame. The network
        // call below runs in the background and overrides this if the cache
        // is stale. Skip the shortcut on .createAnonymous (nothing cached)
        // and on the .auth path (session was deliberately ended).
        let cached = cache.load()
        if let cp = cached.profile, let ca = cached.account, hasOnboarded {
            profile = cp
            account = ca
            state = .app
        }

        let acct = await repo.currentAccount()
        switch Self.decide(account: acct, hasGraduated: hasGraduated) {
        case .app:
            account = acct
            profile = try? await repo.ensureSignedIn()
            state = hasOnboarded ? .app : .onboarding
            cache.save(profile: profile, account: account)
        case .auth:
            cache.clear()
            state = .auth
        case .createAnonymous:
            do {
                profile = try await repo.ensureSignedIn()
                account = await repo.currentAccount()
                state = hasOnboarded ? .app : .onboarding
                cache.save(profile: profile, account: account)
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
            self.cache.save(profile: self.profile, account: self.account)
        }
    }

    func signUp(email: String, password: String, displayName: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signUp(email: email, password: password, displayName: displayName)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.hasOnboarded = true
            self.state = .app
            self.cache.save(profile: self.profile, account: self.account)
        }
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.signIn(email: email, password: password)
            self.account = await self.repo.currentAccount()
            self.hasGraduated = true
            self.hasOnboarded = true
            self.state = .app
            self.cache.save(profile: self.profile, account: self.account)
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
        cache.clear()
        hasGraduated = true
        state = .auth
    }

    func deleteAccount() async {
        do {
            try await repo.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        account = nil
        profile = nil
        cache.clear()
        // A truly fresh device: next launch creates a new anonymous session and
        // re-onboards, rather than offering to sign back into the deleted account.
        hasGraduated = false
        hasOnboarded = false
        state = .auth
    }

    func completeOnboarding() {
        hasOnboarded = true
        state = .app
    }

    func updateDisplayName(_ name: String) async -> Bool {
        await perform {
            self.profile = try await self.repo.updateDisplayName(name)
            self.cache.save(profile: self.profile, account: self.account)
        }
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
