// What the server says, and how to ask it things.
//
// ## Why this is in the engine
//
// Nothing here makes a request. There are no sockets, no URLs being opened, no JSON being parsed —
// those need Foundation, which this module deliberately does not have.
//
// What is here is everything that can be got *wrong* without failing: the shape of each reply, the
// paths that identify things, and what a given refusal actually means to somebody looking at the screen.
// Each of those is testable, and each has the same nasty property — a mistake produces a plausible
// wrong answer rather than an error. A path built with an unescaped identifier quietly fetches
// something else. A status code read as "nothing there" rather than "you are signed out" tells somebody
// their saved worlds are gone.
//
// So the app layer is left with the part that genuinely needs Foundation: making the request and turning
// bytes into these types.
//
// ## Everything from the server is untrusted
//
// The same discipline the save format gets. A reply is data this app did not produce, which means it can
// be missing fields, carry values outside any sane range, or be a completely different thing served by
// something that is not this server at all — a captive portal on a café network, most commonly, which
// answers every request with a login page and a 200.

// MARK: - What the server is

/// What the server says about itself.
///
/// Asked before anything else, and the reason it exists is worth stating: without it the app cannot tell
/// a deployment with accounts switched off from one where signing in is broken, and it cannot tell a real
/// database from the throwaway one that ships with the web app. Both matter enormously to somebody about
/// to save a world:
///
/// - with accounts off, a sign-in button is a button that cannot work;
/// - with the throwaway database, a saved world will appear to save and then be gone, because every
///   request gets a fresh empty copy.
///
/// Neither of those is something to discover afterwards.
public struct CloudStatus: Codable, Sendable, Hashable {
    /// The version of the server's API. This app speaks version 1.
    public var api: Int
    /// Whether signing in is possible at all.
    public var accounts: Bool
    /// `"neon"` for a real database, `"pglite"` for the throwaway one.
    public var storage: String
    /// Whether anything saved will still be there later.
    public var persistent: Bool

    public init(api: Int, accounts: Bool, storage: String, persistent: Bool) {
        self.api = api
        self.accounts = accounts
        self.storage = storage
        self.persistent = persistent
    }

    /// The version this app was written against.
    public static let expectedAPI = 1

    /// Whether this app and this server understand each other.
    public var isUnderstood: Bool { api == Self.expectedAPI }

    /// What to warn about, or `nil` when everything is as it should be.
    ///
    /// Written out here rather than in the interface so that it is one decision in one place, and so the
    /// wording can be checked by a test rather than by looking at a screen.
    public var warning: String? {
        if !isUnderstood {
            return api > Self.expectedAPI
                ? "This server is newer than this app. Updating the app should fix it."
                : "This server is older than this app and does not support saving yet."
        }
        if !persistent {
            return "This server has no permanent storage set up, so anything saved here will disappear."
        }
        if !accounts {
            return "This server has accounts switched off, so everything saved here is shared."
        }
        return nil
    }
}

// MARK: - Saved worlds

/// One of somebody's saved worlds, as it appears in a list.
public struct CloudSaveSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// `"powder"` or `"particle"`.
    public var mode: String
    /// When it was kept, as the server wrote it. Left as text on purpose — see ``CloudDate``.
    public var createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, mode
        // The server is a Postgres application and its columns are named this way.
        case createdAt = "created_at"
    }

    public init(id: String, name: String, mode: String, createdAt: String) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
    }

    /// Which chamber this belongs to, or `nil` for a value this build does not recognise.
    public var chamber: CloudChamber? { CloudChamber(rawValue: mode) }
}

/// A saved world, with its contents.
public struct CloudSave: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var mode: String
    public var createdAt: String
    /// The world itself, in the same format a local file uses.
    public var data: String

    private enum CodingKeys: String, CodingKey {
        case id, name, mode, data
        case createdAt = "created_at"
    }

    public init(id: String, name: String, mode: String, createdAt: String, data: String) {
        self.id = id
        self.name = name
        self.mode = mode
        self.createdAt = createdAt
        self.data = data
    }

    public var chamber: CloudChamber? { CloudChamber(rawValue: mode) }
}

/// Which half of the lab a saved world belongs to.
public enum CloudChamber: String, Codable, Sendable, CaseIterable {
    case powder
    case particle
}

/// A list of saves, as the server wraps it.
public struct CloudSaveList: Codable, Sendable {
    public var saves: [CloudSaveSummary]

    public init(saves: [CloudSaveSummary]) {
        self.saves = saves
    }
}

// MARK: - The workshop

/// A published world, as it appears in the workshop.
public struct CloudMapSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var author: String
    public var description: String
    /// Comma-separated, as the server stores them.
    public var tags: String
    /// A small picture, as a data URL. May be empty.
    public var thumbnail: String
    public var likes: Int
    public var downloads: Int
    public var createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, author, description, tags, thumbnail, likes, downloads
        case createdAt = "created_at"
    }

    public init(
        id: String,
        title: String,
        author: String,
        description: String,
        tags: String,
        thumbnail: String,
        likes: Int,
        downloads: Int,
        createdAt: String
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.description = description
        self.tags = tags
        self.thumbnail = thumbnail
        self.likes = likes
        self.downloads = downloads
        self.createdAt = createdAt
    }

    /// The tags, separated and tidied.
    ///
    /// Empty ones dropped, so `"sand,,water, "` gives two rather than four — one of which would be an
    /// invisible chip in the interface that nothing could explain.
    public var tagList: [String] {
        tags.split(separator: ",")
            .map { String($0).trimmingSpaces() }
            .filter { !$0.isEmpty }
    }
}

/// A published world, with its contents.
public struct CloudMap: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// The world itself.
    public var gridData: String

    private enum CodingKeys: String, CodingKey {
        case id, title
        case gridData = "grid_data"
    }

    public init(id: String, title: String, gridData: String) {
        self.id = id
        self.title = title
        self.gridData = gridData
    }
}

public struct CloudMapList: Codable, Sendable {
    public var maps: [CloudMapSummary]

    public init(maps: [CloudMapSummary]) {
        self.maps = maps
    }
}

/// How the workshop may be ordered. Matches the server's own list exactly.
public enum CloudMapSort: String, Codable, Sendable, CaseIterable, Identifiable {
    case recent
    case popular
    case downloaded

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recent: "Newest"
        case .popular: "Most liked"
        case .downloaded: "Most opened"
        }
    }
}

// MARK: - Asking for things

/// What to send when keeping a world.
public struct CloudSaveRequest: Codable, Sendable {
    public var name: String
    public var mode: String
    public var data: String

    public init(name: String, mode: CloudChamber, data: String) {
        self.name = name
        self.mode = mode.rawValue
        self.data = data
    }
}

/// What to send when publishing a world.
public struct CloudPublishRequest: Codable, Sendable {
    public var title: String
    public var description: String
    public var tags: String
    public var thumbnail: String
    public var gridData: String

    public init(title: String, description: String, tags: String, thumbnail: String, gridData: String) {
        self.title = title
        self.description = description
        self.tags = tags
        self.thumbnail = thumbnail
        self.gridData = gridData
    }
}

/// The limits the server enforces, stated here so the app can refuse before asking.
///
/// Duplicated from the server on purpose, and it is a duplication worth having: without it the only way
/// to discover that a title is one character too long is to send eight megabytes and be refused. The
/// server remains the authority — nothing here is trusted by it — but the app can be polite about it.
public enum CloudLimits {
    public static let nameLength = 80
    public static let descriptionLength = 400
    public static let tagsLength = 120
    public static let thumbnailLength = 400_000
    public static let dataLength = 8_000_000

    /// Whether a save would be accepted.
    public static func acceptsSave(name: String, data: String) -> Bool {
        let trimmed = name.trimmingSpaces()
        return !trimmed.isEmpty
            && trimmed.count <= nameLength
            && !data.isEmpty
            && data.count <= dataLength
    }

    /// Whether a publication would be accepted.
    public static func acceptsPublication(
        title: String,
        description: String,
        tags: String,
        thumbnail: String,
        gridData: String
    ) -> Bool {
        let trimmed = title.trimmingSpaces()
        return !trimmed.isEmpty
            && trimmed.count <= nameLength
            && description.count <= descriptionLength
            && tags.count <= tagsLength
            && thumbnail.count <= thumbnailLength
            && !gridData.isEmpty
            && gridData.count <= dataLength
    }
}

// MARK: - Accounts

/// One way of signing in.
public struct CloudProvider: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct CloudProviderList: Codable, Sendable {
    public var providers: [CloudProvider]

    public init(providers: [CloudProvider]) {
        self.providers = providers
    }
}

/// Who the server thinks this is.
public struct CloudIdentity: Codable, Sendable, Hashable {
    public var signedIn: Bool
    public var id: String

    public init(signedIn: Bool, id: String) {
        self.signedIn = signedIn
        self.id = id
    }
}

/// How signing in ended.
public enum CloudSignInOutcome: Sendable, Hashable {
    /// It worked, and this is the token to keep.
    case token(String)
    /// It did not, and this is why, in the server's words.
    case failed(String)

    /// What to put on screen for a failure.
    ///
    /// The server's reasons are short identifiers, not sentences — they travel in a URL, so they have to
    /// be. Turning them into something readable is this app's job, and doing it here means the wording
    /// can be tested rather than checked by signing in and looking.
    public var explanation: String {
        switch self {
        case .token:
            "Signed in."
        case let .failed(reason):
            switch reason {
            case "unknown_provider":
                "That way of signing in is not available on this server."
            case "sign_in_declined":
                "Signing in was cancelled."
            case "no_session":
                "Signing in did not complete. Please try again."
            case "sign_in_no_destination":
                "This server's sign-in is not set up properly."
            default:
                reason.hasPrefix("sign_in_unavailable")
                    ? "This server's sign-in is not working at the moment."
                    : "Signing in did not work. Please try again."
            }
        }
    }
}

/// Reading the address the sign-in sheet hands back.
///
/// The sheet does not fetch this address — it matches the app's scheme, stops, and passes it over. So
/// this is the one moment where a token crosses from the server into the app, and everything about it is
/// worth being careful with.
public enum CloudCallback {
    /// Works out what happened from the query part of the callback address.
    ///
    /// - Parameter query: everything after the `?`, without it.
    ///
    /// A callback with neither a token nor a reason is treated as a failure rather than ignored. Ignoring
    /// it leaves the interface waiting forever on something that has already finished.
    public static func outcome(query: String) -> CloudSignInOutcome {
        let fields = parse(query: query)
        if let token = fields["token"], !token.isEmpty {
            return .token(token)
        }
        if let error = fields["error"], !error.isEmpty {
            return .failed(error)
        }
        return .failed("no_session")
    }

    /// Splits a query string into its fields.
    ///
    /// Written out rather than borrowed, so the engine keeps its independence — and because a session
    /// token contains characters that *must* survive: it is two base64 parts joined by a dot, and base64
    /// contains `+`, `/` and `=`. A decoder that mishandled any of those would produce a token that looks
    /// perfectly reasonable and is rejected by every request from then on.
    public static func parse(query: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = parts.first, !name.isEmpty else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            fields[decode(String(name))] = decode(value)
        }
        return fields
    }

    /// Reverses percent-encoding.
    ///
    /// `+` becomes a space, as it does in a query string — which is exactly why a base64 `+` arrives
    /// percent-encoded as `%2B` and must not be touched here.
    public static func decode(_ text: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        var iterator = Array(text.utf8)
        var index = 0
        while index < iterator.count {
            let byte = iterator[index]
            if byte == UInt8(ascii: "+") {
                bytes.append(UInt8(ascii: " "))
                index += 1
            } else if byte == UInt8(ascii: "%"), index + 2 < iterator.count,
                      let high = hexValue(iterator[index + 1]),
                      let low = hexValue(iterator[index + 2]) {
                bytes.append(high << 4 | low)
                index += 3
            } else {
                // A stray `%` that is not a valid escape is kept as written rather than dropped. The
                // result will not be a usable token, and it is better for that to be visible than for the
                // character to disappear and leave something plausible.
                bytes.append(byte)
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}

/// What the server answers when something has been created.
public struct CloudCreated: Codable, Sendable, Hashable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

/// What the server answers when something went wrong.
public struct CloudError: Codable, Sendable {
    public var error: String

    public init(error: String) {
        self.error = error
    }
}

// MARK: - Where the server is

/// Tidying up an address somebody typed.
///
/// The app cannot know where its server is. This project is deployed by whoever deployed it, to whatever
/// address they were given, and nothing in the app can discover that — so it has to be told, which means
/// accepting whatever somebody pastes in.
///
/// What they paste is rarely a clean base address. It is `myapp.vercel.app`, or the whole thing with a
/// path still on the end, or with a space where the copy picked one up. All of those should work; a few
/// things should not, and being refused clearly beats appearing to work and then failing every request.
public enum CloudAddress {
    /// Turns typed text into an address to make requests against.
    ///
    /// - Returns: `https://host`, with nothing after the host, or `nil` if it is not an address.
    public static func normalise(_ text: String) -> String? {
        var working = text.trimmingSpaces()
        guard !working.isEmpty else { return nil }

        // A scheme if there is one; otherwise assume the secure one. Assuming is right here — nobody
        // pastes a scheme when copying a domain from a browser's address bar, and refusing them for it
        // would be pedantry.
        var isSecure = true
        let lowered = working.lowercased()
        if lowered.hasPrefix("https://") {
            working = String(working.dropFirst("https://".count))
        } else if lowered.hasPrefix("http://") {
            isSecure = false
            working = String(working.dropFirst("http://".count))
        } else if lowered.contains("://") {
            // Some other scheme — `ftp://`, `ssh://` — or a stray `://` in the middle of nonsense.
            // Neither is an address this app can make requests against.
            return nil
        }

        // Everything after the host is dropped: a path, a query, a fragment. The app builds its own paths
        // and a leftover `/dashboard` on the end would be prefixed to every one of them.
        for separator in ["/", "?", "#"] {
            if let index = working.firstIndex(of: Character(separator)) {
                working = String(working[working.startIndex ..< index])
            }
        }
        // Credentials in an address are not something to carry into every request.
        if let at = working.lastIndex(of: "@") {
            working = String(working[working.index(after: at)...])
        }

        let host = working.lowercased()
        guard !host.isEmpty else { return nil }
        // No spaces, and nothing that is plainly not a host.
        guard !host.contains(" "), !host.contains("\t") else { return nil }

        let isLocal = host == "localhost"
            || host.hasPrefix("localhost:")
            || host.hasPrefix("127.0.0.1")
            || host.hasPrefix("[::1]")

        // A host with no dot in it is a machine name on a local network, not a server on the internet.
        // Allowed only for the local addresses above, where it is the normal case.
        guard isLocal || host.contains(".") else { return nil }
        // And every character has to be one a host can contain.
        guard host.allSatisfy(isHostCharacter) else { return nil }
        // A dot at either end, or two together, is a typo rather than a host.
        guard !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return nil }

        // Insecure only for a machine on this desk. Anywhere else it would send the token that stands in
        // for somebody's account across a network in the clear.
        guard isSecure || isLocal else { return nil }
        return "\(isSecure ? "https" : "http")://\(host)"
    }

    private static func isHostCharacter(_ character: Character) -> Bool {
        character.isLetter && character.isASCII
            || character.isNumber && character.isASCII
            || character == "." || character == "-" || character == ":"
            || character == "[" || character == "]"
    }
}

// MARK: - Paths

/// Building the paths the server answers on.
///
/// Every identifier goes through ``escape(pathSegment:)``. That is not caution for its own sake: an
/// identifier comes back from the server and goes out again in the next request, and one containing a
/// slash — through a change at the other end, or somebody's deliberate attempt — would silently address
/// a different endpoint entirely. A `like` that became a `delete` is the shape of that mistake.
public enum CloudPath {
    /// The prefix every path sits under.
    public static let prefix = "/api/v1"

    public static let status = "\(prefix)/status"
    public static let saves = "\(prefix)/saves"
    public static let maps = "\(prefix)/maps"
    public static let me = "\(prefix)/me"
    public static let providers = "\(prefix)/auth/providers"

    /// Where to send the sign-in sheet.
    public static func signIn(provider: String) -> String {
        "\(prefix)/auth/start/\(escape(pathSegment: provider))"
    }

    public static func save(_ id: String) -> String {
        "\(saves)/\(escape(pathSegment: id))"
    }

    public static func map(_ id: String) -> String {
        "\(maps)/\(escape(pathSegment: id))"
    }

    public static func like(_ id: String) -> String {
        "\(map(id))/like"
    }

    public static func download(_ id: String) -> String {
        "\(map(id))/download"
    }

    /// The query for listing the workshop.
    public static func mapsQuery(sort: CloudMapSort, tag: String, limit: Int) -> String {
        var query = "sort=\(sort.rawValue)"
        let trimmedTag = tag.trimmingSpaces()
        if !trimmedTag.isEmpty {
            query += "&tag=\(escape(queryValue: trimmedTag))"
        }
        // Clamped rather than passed on. The server would refuse an absurd number, and being refused for
        // something the app chose itself is a failure with nothing anyone can do about it.
        query += "&limit=\(max(1, min(60, limit)))"
        return "\(maps)?\(query)"
    }

    /// Percent-encodes one path segment.
    ///
    /// Written out here rather than borrowed, because the engine has no Foundation — and because
    /// Foundation's own version works from a set of *allowed* characters, which is easy to get subtly
    /// wrong in the permissive direction. This works the other way round: unreserved characters pass and
    /// absolutely everything else is encoded.
    public static func escape(pathSegment segment: String) -> String {
        var out = ""
        out.reserveCapacity(segment.utf8.count)
        for byte in segment.utf8 {
            if isUnreserved(byte) {
                out.append(Character(UnicodeScalar(byte)))
            } else {
                out.append("%")
                out.append(hexDigit(byte >> 4))
                out.append(hexDigit(byte & 0x0F))
            }
        }
        return out
    }

    /// Percent-encodes one query value. The same rules; named separately so call sites read correctly.
    public static func escape(queryValue value: String) -> String {
        escape(pathSegment: value)
    }

    /// The characters RFC 3986 says never need encoding: letters, digits, and `-._~`.
    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) // A-Z
            || (byte >= 0x61 && byte <= 0x7A) // a-z
            || (byte >= 0x30 && byte <= 0x39) // 0-9
            || byte == 0x2D // -
            || byte == 0x2E // .
            || byte == 0x5F // _
            || byte == 0x7E // ~
    }

    private static func hexDigit(_ value: UInt8) -> Character {
        let digits = Array("0123456789ABCDEF")
        return digits[Int(value & 0x0F)]
    }
}

// MARK: - When it does not work

/// Why a request did not succeed.
///
/// The cases are separated by what somebody can *do* about them, which is the only distinction that
/// matters to an interface. Being told "error 401" helps nobody; being told to sign in does.
/// (`Error` is in the standard library, not Foundation, so conforming to it costs the engine none of its
/// independence — and it is what lets every call site be a `Result`.)
public enum CloudFailure: Error, Sendable, Hashable {
    /// The phone could not reach the server at all.
    case unreachable
    /// Signed out, or the token has expired.
    case signedOut
    /// The server has no account support configured.
    case notConfigured
    /// Whatever was asked for is not there.
    case missing
    /// The request was refused as invalid, with the server's reason.
    case refused(String)
    /// The server broke.
    case serverFault
    /// A reply arrived that could not be understood.
    case unreadable

    /// What to put on screen.
    ///
    /// Every one of these says what happened *and* what to do, because a message that says only what
    /// happened leaves somebody staring at it. The one that matters most is ``unreachable``: the
    /// tempting alternative is to show an empty list, and an empty list tells somebody their saved
    /// worlds are gone when in fact nobody managed to ask.
    public var explanation: String {
        switch self {
        case .unreachable:
            "Could not reach the server. Check your connection and try again — nothing has been lost."
        case .signedOut:
            "You have been signed out. Sign in again to see your worlds."
        case .notConfigured:
            "This server does not have accounts set up, so there is nothing to sign in to."
        case .missing:
            "That is not there any more. Somebody may have removed it."
        case let .refused(reason):
            // Framed rather than shown bare. What arrives is the server's wording, which is a fragment
            // like "Name too long" — on its own that reads as though the app is accusing you of
            // something, with no indication of what refused it or why.
            Self.frame(reason)
        case .serverFault:
            "Something went wrong at the server's end. Trying again in a moment usually works."
        case .unreadable:
            "The server replied with something this app could not read. It may be a newer version."
        }
    }

    /// Wraps the server's reason in a sentence of this app's own.
    ///
    /// Punctuation added where the server left it off, because these two strings are written by different
    /// people in different places and neither can assume the other's habits.
    private static func frame(_ reason: String) -> String {
        let tidied = reason.trimmingSpaces()
        guard !tidied.isEmpty else { return "The server would not accept that." }
        let needsStop = !(tidied.hasSuffix(".") || tidied.hasSuffix("!") || tidied.hasSuffix("?"))
        return "The server would not accept that. \(tidied)\(needsStop ? "." : "")"
    }

    /// Whether trying the same thing again could plausibly work.
    ///
    /// Used to decide whether to offer a retry. Offering one for a request that will be refused
    /// identically forever is worse than not offering one.
    public var isWorthRetrying: Bool {
        switch self {
        case .unreachable, .serverFault: true
        case .signedOut, .notConfigured, .missing, .refused, .unreadable: false
        }
    }

    /// What a given HTTP status means.
    ///
    /// - Returns: the failure, or `nil` for a status that means it worked.
    public static func forStatus(_ status: Int, message: String = "") -> CloudFailure? {
        switch status {
        case 200 ..< 300:
            return nil
        case 401, 403:
            return .signedOut
        case 404:
            return .missing
        case 503:
            return .notConfigured
        case 400 ..< 500:
            return .refused(message)
        default:
            // Anything else, including the 1xx and 3xx nobody should be seeing here — a redirect that
            // reached this point means something is answering that is not the server, and a captive
            // portal on a café network is the usual culprit.
            return .serverFault
        }
    }
}

// MARK: - Small string help

extension String {
    /// Trims spaces, tabs and newlines from both ends.
    ///
    /// Foundation's `trimmingCharacters(in: .whitespacesAndNewlines)` by hand, because the engine has no
    /// Foundation. Only the characters a phone keyboard actually produces are covered, which is all that
    /// is wanted — a name is being tidied, not normalised.
    func trimmingSpaces() -> String {
        var characters = Array(self)
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        while let first = characters.first, isSpace(first) { characters.removeFirst() }
        while let last = characters.last, isSpace(last) { characters.removeLast() }
        return String(characters)
    }
}
