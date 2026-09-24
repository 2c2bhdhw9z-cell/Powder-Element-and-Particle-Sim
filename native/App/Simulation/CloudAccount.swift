import AuthenticationServices
import CrucibleCore
import Foundation
import Observation
import UIKit

/// The account, the server's address, and signing in.
///
/// ## Why the address has to be typed in
///
/// The app cannot know where its server is. This project is deployed by whoever deployed it, to whatever
/// address they were given, and nothing compiled into the app can discover that. Baking in a guess would
/// be worse than asking: it would appear to be configured and fail every request.
///
/// So it is asked for, once, and then checked — the interface offers a "check this server" that reports
/// exactly what is right and wrong about it, including the two things nobody would otherwise find out
/// until it was too late: whether accounts work at all, and whether the database is real or the
/// throwaway one that ships with the website. The second is the cruel one. On the throwaway database a
/// saved world appears to save and is simply gone.
///
/// ## Where the token is kept, and why not the keychain
///
/// The conventional answer is the keychain, and it is not the answer here.
///
/// This app ships as an unsigned `.ipa` and is signed on the device by whoever installs it, with no
/// entitlements of its own. Keychain access depends on the entitlements the signing tool happens to
/// inject, and when they do not line up the keychain fails with an error that means nothing to anybody
/// (`-34018`) — so signing in would appear to work and then be forgotten on every launch, on some
/// devices and not others, for reasons nothing in the app could explain.
///
/// A file with complete protection needs no entitlement at all and so cannot fail that way. It is
/// encrypted with the device's passcode and unreadable while the phone is locked, which is the property
/// that actually matters. One code path, and it is the one that was reasoned about.
@MainActor
@Observable
final class CloudAccount {
    /// Where the server is, tidied. Empty when it has not been set.
    private(set) var address: String
    /// What the server says about itself, once asked.
    private(set) var status: CloudStatus?
    /// Which ways of signing in it offers.
    private(set) var providers: [CloudProvider] = []
    /// Whether this device holds a token the server accepted.
    private(set) var isSignedIn = false
    /// Whether a check is under way.
    private(set) var isChecking = false
    /// Whether signing in is under way.
    private(set) var isSigningIn = false
    /// The last thing that went wrong, in words.
    private(set) var problem: String?

    @ObservationIgnored private var token: String?
    @ObservationIgnored private let tokenStore = CloudTokenFile()
    @ObservationIgnored private var signInSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presenter = CloudSignInPresenter()

    /// Where the address is remembered. A preference rather than data, so `UserDefaults` is right.
    private static let addressKey = "cloudServerAddress"

    init() {
        address = UserDefaults.standard.string(forKey: Self.addressKey) ?? ""
        token = tokenStore.read()
    }

    /// A client ready to make requests, or `nil` when there is no server to make them against.
    var client: CloudClient? {
        guard !address.isEmpty, let url = URL(string: address) else { return nil }
        return CloudClient(base: url, token: token)
    }

    /// Whether anything cloud-related can be attempted.
    var hasServer: Bool { client != nil }

    /// The address without its scheme, for putting on one line where the `https://` is just noise.
    var hostText: String {
        if address.hasPrefix("https://") { return String(address.dropFirst("https://".count)) }
        if address.hasPrefix("http://") { return String(address.dropFirst("http://".count)) }
        return address
    }

    /// Whether signing in is possible: a server that is reachable and has accounts switched on.
    var canSignIn: Bool {
        hasServer && (status?.accounts ?? false) && !providers.isEmpty
    }

    // MARK: The server

    /// Records an address somebody typed.
    ///
    /// - Returns: whether it was one. Refused rather than corrected: an address that is nearly right,
    ///   quietly adjusted into something else, fails every request while looking perfectly correct.
    @discardableResult
    func setAddress(_ typed: String) -> Bool {
        guard let tidied = CloudAddress.normalise(typed) else {
            problem = "That does not look like a web address. It should be something like "
                + "crucible.vercel.app."
            return false
        }
        guard tidied != address else { return true }

        address = tidied
        UserDefaults.standard.set(tidied, forKey: Self.addressKey)
        // A token belongs to one server. Carrying it to another would send somebody's session to a
        // machine that has no business with it.
        forgetToken()
        status = nil
        providers = []
        problem = nil
        return true
    }

    /// Forgets the server entirely.
    func clearAddress() {
        address = ""
        UserDefaults.standard.removeObject(forKey: Self.addressKey)
        forgetToken()
        status = nil
        providers = []
        problem = nil
    }

    /// Asks the server what it is, and whether the stored token still works.
    ///
    /// Everything the interface needs before showing anything, in one round. Done in this order on
    /// purpose: there is no point asking who somebody is on a server that does not answer.
    func check() async {
        guard let client else {
            problem = "No server has been set yet."
            return
        }
        isChecking = true
        defer { isChecking = false }
        problem = nil

        switch await client.status() {
        case let .failure(failure):
            status = nil
            providers = []
            isSignedIn = false
            problem = failure.explanation
            return
        case let .success(reported):
            status = reported
            // Stated here rather than left for a sheet to notice, because somebody about to save a world
            // on a throwaway database needs to know before they do it, not after.
            problem = reported.warning
            guard reported.isUnderstood else {
                providers = []
                isSignedIn = false
                return
            }
        }

        if case let .success(list) = await client.providers() {
            providers = list
        } else {
            providers = []
        }

        await refreshIdentity()
    }

    /// Checks whether the token this device holds is still accepted.
    func refreshIdentity() async {
        guard let client else { return }
        guard token != nil else {
            isSignedIn = false
            return
        }
        switch await client.identity() {
        case .success:
            isSignedIn = true
        case let .failure(failure):
            if failure == .signedOut {
                // Expired or revoked. Dropped rather than kept, so every later request fails for a
                // reason somebody can act on instead of silently being refused.
                forgetToken()
            }
            isSignedIn = false
        }
    }

    // MARK: Signing in

    /// Signs in through the system's own sign-in sheet.
    ///
    /// `ASWebAuthenticationSession` rather than a web view of the app's own. It is the only arrangement
    /// both Apple and an identity provider accept, it shows the real address bar so somebody can see
    /// whose page they are typing a password into, and the app never gets to see the password at all.
    func signIn(provider: CloudProvider) async {
        guard hasServer, let base = URL(string: address) else { return }
        guard let start = URL(string: CloudPath.signIn(provider: provider.id), relativeTo: base) else {
            return
        }

        isSigningIn = true
        problem = nil

        let outcome: CloudSignInOutcome = await withCheckedContinuation { continuation in
            // Resuming a continuation twice is not an error to be handled, it is a crash. The two paths
            // below — the sheet finishing, and the sheet refusing to start — should be mutually
            // exclusive, and a latch is cheaper than depending on that.
            let once = CloudOnce()
            let session = ASWebAuthenticationSession(
                url: start,
                // The scheme the server's last redirect uses. The sheet matches it, stops, and hands the
                // address back — it never fetches it, which is why the token can travel in it.
                callbackURLScheme: CloudSignIn.scheme
            ) { callback, error in
                guard once.claim() else { return }
                if let callback {
                    continuation.resume(returning: CloudCallback.outcome(query: callback.query ?? ""))
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(returning: .failed("sign_in_declined"))
                } else {
                    continuation.resume(returning: .failed("sign_in_failed"))
                }
            }
            session.presentationContextProvider = presenter
            // Deliberately *not* ephemeral. Reusing the browser's existing session is what makes signing
            // in one tap when somebody is already signed in to Google on this phone, which is most of the
            // point of using the system sheet at all.
            session.prefersEphemeralWebBrowserSession = false
            signInSession = session
            if !session.start(), once.claim() {
                continuation.resume(returning: .failed("sign_in_failed"))
            }
        }

        signInSession = nil
        isSigningIn = false

        switch outcome {
        case let .token(value):
            keepToken(value)
            // Checked rather than assumed. A token that arrives and is not accepted would otherwise leave
            // the app claiming to be signed in while every request was refused.
            await refreshIdentity()
            if !isSignedIn {
                problem = "Signing in seemed to work, but the server did not accept it."
            }
        case .failed:
            isSignedIn = false
            problem = outcome.explanation
        }
    }

    /// Signs out on this device.
    ///
    /// Local only, and worth saying so in the interface: the session on the server is left alone. Ending
    /// it properly would need another request, and one that fails would leave somebody apparently still
    /// signed in on a phone they have just handed to somebody else. Dropping the token always works.
    func signOut() {
        forgetToken()
        isSignedIn = false
        problem = nil
    }

    func dismissProblem() {
        problem = nil
    }

    /// Reports something that went wrong, from wherever it happened.
    ///
    /// Held here rather than in each panel because there is one account and one server, and two panels
    /// each with their own idea of what is currently wrong would contradict each other.
    func reportProblem(_ message: String) {
        problem = message
    }

    // MARK: The token

    private func keepToken(_ value: String) {
        token = value
        tokenStore.write(value)
    }

    private func forgetToken() {
        token = nil
        tokenStore.clear()
    }
}

/// Facts about the sign-in callback that both the app and its `Info.plist` have to agree on.
enum CloudSignIn {
    /// Must match `CFBundleURLSchemes` in `Info.plist` and `nativeCallbackScheme` on the server.
    ///
    /// All three are the same word in three places, which is not ideal and is unavoidable: one is a
    /// property list, one is a TypeScript constant on another machine, and this is the only one a Swift
    /// compiler can see. Getting it wrong shows up as a sign-in sheet that opens, completes, and then
    /// sits there — so it is worth checking all three when that happens.
    static let scheme = "crucible"
}

/// A one-shot latch.
///
/// Small enough to feel unnecessary and worth having: resuming a continuation twice is not an error that
/// can be caught, it stops the app. This makes "only the first one counts" a fact rather than something
/// the two call sites have to keep true between them.
private final class CloudOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Tells the system which window to put the sign-in sheet over.
///
/// Its own small object because this is an old-style delegate protocol. Marked as safe to share by hand,
/// which it is: it holds nothing at all.
private final class CloudSignInPresenter: NSObject, ASWebAuthenticationPresentationContextProviding,
    @unchecked Sendable
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // The system always calls this on the main thread, which is where the windows are. Stated rather
        // than assumed, and written so it compiles whether or not the SDK has got round to annotating
        // this protocol.
        MainActor.assumeIsolated {
            // Only windows that are actually on screen. A hidden one is a perfectly valid answer that
            // shows the sheet nowhere.
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                if let key = windowScene.windows.first(where: \.isKeyWindow) { return key }
                if let first = windowScene.windows.first { return first }
            }
            return ASPresentationAnchor()
        }
    }
}

/// The token, in a file only this device can read.
///
/// See the note on ``CloudAccount`` for why this is not the keychain. In short: the keychain needs
/// entitlements this app cannot rely on having after being re-signed on a phone, and when they are wrong
/// it fails in a way that looks like the app forgetting you at random.
private struct CloudTokenFile {
    private let url: URL?

    init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("cloud-token", isDirectory: false)
        } else {
            url = nil
        }
    }

    func read() -> String? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func write(_ value: String) {
        guard let url else { return }
        // Complete protection: encrypted with the device's passcode and unreadable while the phone is
        // locked. Atomic, so an interrupted write cannot leave half a token behind — half a token is
        // indistinguishable from an expired one and would send somebody round the sign-in loop with no
        // explanation.
        try? Data(value.utf8).write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
