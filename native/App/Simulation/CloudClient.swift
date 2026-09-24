import CrucibleCore
import Foundation

/// Making the requests.
///
/// Everything about *what* a request is — its path, what comes back, what a refusal means — is in
/// `CloudProtocol.swift` in the engine, where it has tests. This is only the part that needs Foundation:
/// opening a connection and turning bytes into those types.
///
/// ## Every reply is treated as untrusted
///
/// The same discipline the save format gets, and for a better reason than principle. The most common
/// thing at the other end of a request on a phone is not this server: it is a café network's sign-in
/// page, which answers every request with a cheerful 200 and a lump of HTML. That must fail to read
/// rather than be taken for an empty list of saved worlds.
struct CloudClient: Sendable {
    /// Where the server is. Already tidied by ``CloudAddress``.
    let base: URL
    /// The token that stands in for an account, when there is one.
    let token: String?

    /// How long to wait.
    ///
    /// Twenty seconds. Long enough for a slow connection to finish and short enough that somebody is not
    /// left watching a spinner — a request that never returns is worse than one that fails, because a
    /// failure at least says what to do next.
    private static let timeout: TimeInterval = 20

    init(base: URL, token: String?) {
        self.base = base
        self.token = token
    }

    // MARK: Asking

    /// Is this server usable at all?
    func status() async -> Result<CloudStatus, CloudFailure> {
        await get(CloudPath.status, as: CloudStatus.self)
    }

    /// Which ways of signing in this server offers.
    func providers() async -> Result<[CloudProvider], CloudFailure> {
        await get(CloudPath.providers, as: CloudProviderList.self).map(\.providers)
    }

    /// Is the token still good?
    ///
    /// The only way to find out. A token has no expiry the app can read, so the alternative to asking is
    /// discovering it at the moment somebody tries to save something.
    func identity() async -> Result<CloudIdentity, CloudFailure> {
        await get(CloudPath.me, as: CloudIdentity.self)
    }

    // MARK: Saved worlds

    func saves() async -> Result<[CloudSaveSummary], CloudFailure> {
        await get(CloudPath.saves, as: CloudSaveList.self).map(\.saves)
    }

    func save(id: String) async -> Result<CloudSave, CloudFailure> {
        await get(CloudPath.save(id), as: CloudSave.self)
    }

    func createSave(_ request: CloudSaveRequest) async -> Result<CloudCreated, CloudFailure> {
        await send(CloudPath.saves, method: "POST", body: request, as: CloudCreated.self)
    }

    func deleteSave(id: String) async -> Result<Void, CloudFailure> {
        switch await perform(CloudPath.save(id), method: "DELETE", body: nil) {
        case .success: .success(())
        case let .failure(failure): .failure(failure)
        }
    }

    // MARK: The workshop

    func maps(sort: CloudMapSort, tag: String, limit: Int = 60) async
        -> Result<[CloudMapSummary], CloudFailure>
    {
        await get(CloudPath.mapsQuery(sort: sort, tag: tag, limit: limit), as: CloudMapList.self)
            .map(\.maps)
    }

    func publish(_ request: CloudPublishRequest) async -> Result<CloudCreated, CloudFailure> {
        await send(CloudPath.maps, method: "POST", body: request, as: CloudCreated.self)
    }

    /// Adds a like, and gives back the new count.
    func like(id: String) async -> Result<Int, CloudFailure> {
        await postForResult(CloudPath.like(id), as: LikeResult.self).map(\.likes)
    }

    /// Counts a download and fetches the world.
    func download(id: String) async -> Result<CloudMap, CloudFailure> {
        await postForResult(CloudPath.download(id), as: CloudMap.self)
    }

    private struct LikeResult: Decodable {
        var likes: Int
    }

    // MARK: Doing it

    private func get<T: Decodable>(_ path: String, as type: T.Type) async -> Result<T, CloudFailure> {
        decode(await perform(path, method: "GET", body: nil), as: type)
    }

    private func postForResult<T: Decodable>(
        _ path: String,
        as type: T.Type
    ) async -> Result<T, CloudFailure> {
        decode(await perform(path, method: "POST", body: nil), as: type)
    }

    private func send<Body: Encodable, T: Decodable>(
        _ path: String,
        method: String,
        body: Body,
        as type: T.Type
    ) async -> Result<T, CloudFailure> {
        guard let encoded = try? JSONEncoder().encode(body) else {
            // Nothing the server could do about this; it never left. Reported as unreadable rather than
            // as a refusal, so the message does not blame the server for the app's mistake.
            return .failure(.unreadable)
        }
        return decode(await perform(path, method: method, body: encoded), as: type)
    }

    private func decode<T: Decodable>(
        _ result: Result<Data, CloudFailure>,
        as type: T.Type
    ) -> Result<T, CloudFailure> {
        switch result {
        case let .failure(failure):
            return .failure(failure)
        case let .success(data):
            guard let value = try? JSONDecoder().decode(type, from: data) else {
                // The café-network case, among others. Deliberately *not* an empty result.
                return .failure(.unreadable)
            }
            return .success(value)
        }
    }

    private func perform(
        _ path: String,
        method: String,
        body: Data?
    ) async -> Result<Data, CloudFailure> {
        // Relative to the base, which carries no path of its own — `CloudAddress` strips anything after
        // the host precisely so that this cannot end up with a leftover prefix on every request.
        guard let url = URL(string: path, relativeTo: base) else { return .failure(.unreachable) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        // Never served from a cache. These are one person's own rows, and a cached list handed to the
        // next request after signing in as somebody else would be the worst bug available here.
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.unreadable) }
            if let failure = CloudFailure.forStatus(http.statusCode, message: reason(from: data)) {
                return .failure(failure)
            }
            return .success(data)
        } catch {
            // Everything from no signal to a name that will not resolve to a certificate that does not
            // check out. All of it is "could not reach the server", which is both true and the only thing
            // anybody can act on. A request abandoned because the screen was closed also lands here; the
            // interface discards results it no longer wants rather than showing them.
            return .failure(.unreachable)
        }
    }

    /// The server's own words for why it refused, when it gave any.
    private func reason(from data: Data) -> String {
        (try? JSONDecoder().decode(CloudError.self, from: data))?.error ?? ""
    }
}
