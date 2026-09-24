import Foundation
import Testing

@testable import CrucibleCore

/// Talking to the server.
///
/// Two kinds of test, and the split is the point of the file existing at all.
///
/// **Reading what the server says.** Decoded from the real JSON the routes produce, written out by hand
/// here rather than generated, so that a field renamed at either end fails a test instead of arriving as
/// a silent default. Every one of these is data the app did not produce and cannot trust.
///
/// **Saying what went wrong.** A status code turned into something a person can act on. This is easy to
/// get wrong in the direction that matters most: a request that failed and gets shown as an empty list
/// tells somebody their saved worlds are gone, when in fact nobody managed to ask.
@Suite("Talking to the server")
struct CloudProtocolTests {
    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: What the server says about itself

    @Test("A properly set up server reports nothing to warn about")
    func healthyServer() throws {
        let status = try decode(
            CloudStatus.self,
            from: #"{"api":1,"accounts":true,"storage":"neon","persistent":true}"#
        )
        #expect(status.api == 1)
        #expect(status.accounts)
        #expect(status.persistent)
        #expect(status.isUnderstood)
        #expect(status.warning == nil)
    }

    /// The warning that matters most. A server on the throwaway database hands every request a fresh
    /// empty copy, so a world saved there appears to save and is then simply gone. Discovering that
    /// afterwards is the worst possible way to find out.
    @Test("A server with no permanent storage says so before anything is saved")
    func temporaryStorageWarns() throws {
        let status = try decode(
            CloudStatus.self,
            from: #"{"api":1,"accounts":true,"storage":"pglite","persistent":false}"#
        )
        let warning = try #require(status.warning)
        #expect(warning.contains("disappear"), "the warning should say what will happen: \(warning)")
    }

    @Test("A server with accounts switched off says so rather than offering a button that cannot work")
    func accountsOffWarns() throws {
        let status = try decode(
            CloudStatus.self,
            from: #"{"api":1,"accounts":false,"storage":"neon","persistent":true}"#
        )
        let warning = try #require(status.warning)
        #expect(warning.contains("shared"), "\(warning)")
    }

    /// Both directions, and they need different wording: an app that is behind can be updated, and an app
    /// that is ahead of its server cannot do anything about it.
    @Test("A server of the wrong version is recognised, in both directions")
    func versionMismatch() throws {
        let newer = try decode(
            CloudStatus.self,
            from: #"{"api":2,"accounts":true,"storage":"neon","persistent":true}"#
        )
        #expect(!newer.isUnderstood)
        #expect(try #require(newer.warning).contains("Updating the app"))

        let older = try decode(
            CloudStatus.self,
            from: #"{"api":0,"accounts":true,"storage":"neon","persistent":true}"#
        )
        #expect(!older.isUnderstood)
        #expect(try #require(older.warning).contains("older"))
    }

    // MARK: Saved worlds

    @Test("A list of saves is read, with the server's own field names")
    func saveListDecodes() throws {
        let list = try decode(
            CloudSaveList.self,
            from: """
            {"saves":[
              {"id":"m1-abc","name":"Volcano","mode":"powder","created_at":"2026-09-24T12:00:00.000Z"},
              {"id":"m2-def","name":"Orbits","mode":"particle","created_at":"2026-09-23T09:30:00.000Z"}
            ]}
            """
        )
        #expect(list.saves.count == 2)
        #expect(list.saves[0].name == "Volcano")
        // The column is `created_at`, and reading it as `createdAt` without saying so would leave every
        // date empty with nothing to indicate why.
        #expect(list.saves[0].createdAt == "2026-09-24T12:00:00.000Z")
        #expect(list.saves[0].chamber == .powder)
        #expect(list.saves[1].chamber == .particle)
    }

    @Test("An empty list is read as empty rather than as a failure")
    func emptyListDecodes() throws {
        let list = try decode(CloudSaveList.self, from: #"{"saves":[]}"#)
        #expect(list.saves.isEmpty)
    }

    @Test("A saved world carries its contents")
    func saveDecodes() throws {
        let save = try decode(
            CloudSave.self,
            from: """
            {"id":"m1-abc","name":"Volcano","mode":"powder",
             "created_at":"2026-09-24T12:00:00.000Z","data":"{\\"width\\":10}"}
            """
        )
        #expect(save.id == "m1-abc")
        #expect(save.data == #"{"width":10}"#)
    }

    /// A mode this build does not know must not become a guess. Treating an unknown chamber as powder
    /// would open a field of orbiting bodies as a grid of sand.
    @Test("A world of an unknown kind is reported as unknown rather than guessed at")
    func unknownChamberIsNil() throws {
        let save = try decode(
            CloudSaveSummary.self,
            from: #"{"id":"x","name":"Thing","mode":"sculpture","created_at":"now"}"#
        )
        #expect(save.chamber == nil)
        // And the rest of it still reads, so a list containing one is not lost entirely.
        #expect(save.name == "Thing")
    }

    @Test("A reply missing a field it needs is refused, not filled in")
    func missingFieldRefused() {
        #expect(throws: (any Error).self) {
            _ = try decode(CloudSaveSummary.self, from: #"{"id":"x","mode":"powder"}"#)
        }
        #expect(throws: (any Error).self) {
            _ = try decode(CloudSaveList.self, from: #"{"wrong":[]}"#)
        }
    }

    /// The café-network case: something that is not the server answers every request with a page and a
    /// 200. It must fail to read rather than be taken for an empty list.
    @Test("A reply that is not from this server at all is refused")
    func foreignReplyRefused() {
        #expect(throws: (any Error).self) {
            _ = try decode(CloudSaveList.self, from: "<html><body>Sign in to WiFi</body></html>")
        }
        #expect(throws: (any Error).self) {
            _ = try decode(CloudStatus.self, from: "")
        }
    }

    // MARK: The workshop

    @Test("A published world is read, tags and all")
    func mapListDecodes() throws {
        let list = try decode(
            CloudMapList.self,
            from: """
            {"maps":[{
              "id":"w1","title":"Acid Rain","author":"Someone","description":"It rains acid.",
              "tags":"acid, weather ,, chaos","thumbnail":"","likes":12,"downloads":40,
              "created_at":"2026-09-20T00:00:00.000Z"
            }]}
            """
        )
        let map = try #require(list.maps.first)
        #expect(map.title == "Acid Rain")
        #expect(map.likes == 12)
        #expect(map.downloads == 40)
        // Tidied: the empty one between the commas would otherwise be an invisible chip in the interface
        // that nothing could explain.
        #expect(map.tagList == ["acid", "weather", "chaos"])
    }

    @Test("A world with no tags has no tags, rather than one empty one")
    func emptyTagsGiveNothing() throws {
        let map = CloudMapSummary(
            id: "w", title: "T", author: "A", description: "", tags: "",
            thumbnail: "", likes: 0, downloads: 0, createdAt: "now"
        )
        #expect(map.tagList.isEmpty)

        var spaces = map
        spaces.tags = " , ,  "
        #expect(spaces.tagList.isEmpty)
    }

    @Test("A published world's contents are read from the server's column name")
    func mapDecodes() throws {
        let map = try decode(
            CloudMap.self,
            from: #"{"id":"w1","title":"Acid Rain","grid_data":"{\"width\":4}"}"#
        )
        #expect(map.gridData == #"{"width":4}"#)
    }

    // MARK: Paths

    @Test("The paths are the ones the server answers on")
    func pathsAreRight() {
        #expect(CloudPath.status == "/api/v1/status")
        #expect(CloudPath.saves == "/api/v1/saves")
        #expect(CloudPath.save("m1-abc") == "/api/v1/saves/m1-abc")
        #expect(CloudPath.maps == "/api/v1/maps")
        #expect(CloudPath.map("w1") == "/api/v1/maps/w1")
        #expect(CloudPath.like("w1") == "/api/v1/maps/w1/like")
        #expect(CloudPath.download("w1") == "/api/v1/maps/w1/download")
    }

    /// The reason every identifier is escaped. One containing a slash would address a different endpoint
    /// entirely — and the shape of that mistake is a `like` quietly becoming something else.
    @Test("An identifier cannot escape its own path segment")
    func identifiersCannotEscape() {
        #expect(CloudPath.save("../maps") == "/api/v1/saves/..%2Fmaps")
        #expect(CloudPath.like("w1/../../saves/other") == "/api/v1/maps/w1%2F..%2F..%2Fsaves%2Fother/like")
        // A `?` would otherwise turn the rest of the path into a query string.
        #expect(CloudPath.save("a?b=c") == "/api/v1/saves/a%3Fb%3Dc")
        // And a `#` would make the server see nothing after it at all.
        #expect(CloudPath.save("a#b") == "/api/v1/saves/a%23b")
    }

    @Test("Ordinary identifiers are left alone")
    func ordinaryIdentifiersUnchanged() {
        // The server's own format: base-36 time, a hyphen, base-36 randomness. Nothing to escape, and it
        // should not be mangled into something unrecognisable.
        for id in ["m1abc-9xz2qp", "abc", "A-Z_0.9~"] {
            #expect(CloudPath.escape(pathSegment: id) == id, "\(id) was altered")
        }
    }

    @Test("Spaces and accents survive being escaped and are still one segment")
    func unicodeEscapes() {
        #expect(CloudPath.escape(pathSegment: "a b") == "a%20b")
        // Two bytes in UTF-8, so two escapes.
        #expect(CloudPath.escape(pathSegment: "é") == "%C3%A9")
        // Four bytes.
        #expect(CloudPath.escape(pathSegment: "🙂") == "%F0%9F%99%82")
    }

    @Test("The workshop query carries the sort, the tag and a sane limit")
    func mapsQuery() {
        #expect(CloudPath.mapsQuery(sort: .recent, tag: "", limit: 60) == "/api/v1/maps?sort=recent&limit=60")
        #expect(
            CloudPath.mapsQuery(sort: .popular, tag: "acid rain", limit: 20)
                == "/api/v1/maps?sort=popular&tag=acid%20rain&limit=20"
        )
        // A tag of nothing but spaces is no tag at all, rather than a filter matching nothing.
        #expect(CloudPath.mapsQuery(sort: .recent, tag: "   ", limit: 10) == "/api/v1/maps?sort=recent&limit=10")
    }

    /// Clamped here rather than sent and refused. Being turned down for a number the app chose itself is
    /// a failure nobody looking at the screen can do anything about.
    @Test("An impossible limit is brought into range rather than being refused by the server")
    func limitIsClamped() {
        #expect(CloudPath.mapsQuery(sort: .recent, tag: "", limit: 0).hasSuffix("limit=1"))
        #expect(CloudPath.mapsQuery(sort: .recent, tag: "", limit: -5).hasSuffix("limit=1"))
        #expect(CloudPath.mapsQuery(sort: .recent, tag: "", limit: 9999).hasSuffix("limit=60"))
    }

    // MARK: What went wrong

    @Test("Success is not a failure")
    func successIsNotFailure() {
        for status in [200, 201, 204, 299] {
            #expect(CloudFailure.forStatus(status) == nil, "\(status) was treated as a failure")
        }
    }

    @Test("Each refusal becomes something a person can act on")
    func statusesMapToActions() {
        #expect(CloudFailure.forStatus(401) == .signedOut)
        #expect(CloudFailure.forStatus(403) == .signedOut)
        #expect(CloudFailure.forStatus(404) == .missing)
        #expect(CloudFailure.forStatus(503) == .notConfigured)
        #expect(CloudFailure.forStatus(400, message: "Name too long") == .refused("Name too long"))
        // And the server's fragment is framed rather than shown bare, so it does not read as the app
        // accusing somebody of something with no indication of what refused it.
        #expect(
            CloudFailure.refused("Name too long").explanation
                == "The server would not accept that. Name too long."
        )
        #expect(
            CloudFailure.refused("Name too long.").explanation
                == "The server would not accept that. Name too long.",
            "a reason that already ended in a full stop should not get a second one"
        )
        #expect(CloudFailure.forStatus(405) == .refused(""))
        #expect(CloudFailure.forStatus(500) == .serverFault)
        #expect(CloudFailure.forStatus(502) == .serverFault)
    }

    /// A redirect reaching this point means something is answering that is not the server. A captive
    /// portal on a café network is the usual culprit, and it must not be read as anything else.
    @Test("A reply from something that is not the server is a server fault, not a refusal")
    func strangeStatusesAreFaults() {
        for status in [100, 301, 302, 0, -1, 999] {
            #expect(CloudFailure.forStatus(status) == .serverFault, "\(status)")
        }
    }

    /// Every message has to say what to do as well as what happened, or somebody is left staring at it.
    @Test("Every failure explains itself in terms somebody can act on")
    func everyFailureExplainsItself() {
        let failures: [CloudFailure] = [
            .unreachable, .signedOut, .notConfigured, .missing,
            .refused("Name too long"), .refused(""), .serverFault, .unreadable,
        ]
        for failure in failures {
            let text = failure.explanation
            #expect(!text.isEmpty, "\(failure) says nothing")
            #expect(text.count > 20, "\(failure) says too little: \(text)")
            #expect(text.hasSuffix(".") || text.hasSuffix("!"), "\(failure) is not a sentence: \(text)")
        }
    }

    /// The most important message in the app. When the server cannot be reached, the tempting thing is to
    /// show an empty list — and an empty list tells somebody their saved worlds are gone when in fact
    /// nobody managed to ask.
    @Test("Being unable to reach the server says nothing has been lost")
    func unreachableReassures() {
        let text = CloudFailure.unreachable.explanation
        #expect(text.contains("nothing has been lost"), "\(text)")
        #expect(CloudFailure.unreachable.isWorthRetrying)
    }

    /// Offering a retry for something that will be refused identically forever is worse than offering
    /// none: it turns one failure into somebody pressing a button over and over.
    @Test("Only the failures that could go differently offer to try again")
    func retryIsOfferedOnlyWhereItCouldHelp() {
        #expect(CloudFailure.unreachable.isWorthRetrying)
        #expect(CloudFailure.serverFault.isWorthRetrying)
        #expect(!CloudFailure.signedOut.isWorthRetrying)
        #expect(!CloudFailure.notConfigured.isWorthRetrying)
        #expect(!CloudFailure.missing.isWorthRetrying)
        #expect(!CloudFailure.refused("no").isWorthRetrying)
        #expect(!CloudFailure.unreadable.isWorthRetrying)
    }

    // MARK: Refusing before asking

    @Test("The limits match the server's, so the app can be polite about them")
    func limitsAgreeWithServer() {
        #expect(CloudLimits.nameLength == 80)
        #expect(CloudLimits.descriptionLength == 400)
        #expect(CloudLimits.tagsLength == 120)
        #expect(CloudLimits.thumbnailLength == 400_000)
        #expect(CloudLimits.dataLength == 8_000_000)
    }

    @Test("A save is checked before it is sent")
    func saveLimitsChecked() {
        #expect(CloudLimits.acceptsSave(name: "Volcano", data: "{}"))
        // A name of nothing but spaces is no name.
        #expect(!CloudLimits.acceptsSave(name: "   ", data: "{}"))
        #expect(!CloudLimits.acceptsSave(name: "", data: "{}"))
        #expect(!CloudLimits.acceptsSave(name: "Volcano", data: ""))
        #expect(!CloudLimits.acceptsSave(name: String(repeating: "x", count: 81), data: "{}"))
        // Exactly at the limit is fine; the server's check is inclusive too.
        #expect(CloudLimits.acceptsSave(name: String(repeating: "x", count: 80), data: "{}"))
        // Surrounding spaces do not count against the length.
        #expect(CloudLimits.acceptsSave(name: "  " + String(repeating: "x", count: 80) + "  ", data: "{}"))
    }

    @Test("A publication is checked before it is sent")
    func publicationLimitsChecked() {
        #expect(
            CloudLimits.acceptsPublication(
                title: "Acid Rain", description: "It rains acid.", tags: "acid",
                thumbnail: "", gridData: "{}"
            )
        )
        #expect(
            !CloudLimits.acceptsPublication(
                title: "", description: "", tags: "", thumbnail: "", gridData: "{}"
            ),
            "a world with no title was accepted"
        )
        #expect(
            !CloudLimits.acceptsPublication(
                title: "T", description: String(repeating: "d", count: 401),
                tags: "", thumbnail: "", gridData: "{}"
            )
        )
        #expect(
            !CloudLimits.acceptsPublication(
                title: "T", description: "", tags: String(repeating: "t", count: 121),
                thumbnail: "", gridData: "{}"
            )
        )
        #expect(
            !CloudLimits.acceptsPublication(
                title: "T", description: "", tags: "", thumbnail: "", gridData: ""
            ),
            "an empty world was accepted"
        )
    }

    // MARK: Where the server is

    /// Everything somebody might realistically paste. The app cannot discover its own server's address,
    /// so all of this has to work.
    @Test("An address is tidied into something requests can be made against")
    func addressesAreTidied() {
        let expected = "https://crucible.vercel.app"
        for typed in [
            "crucible.vercel.app",
            "https://crucible.vercel.app",
            "https://crucible.vercel.app/",
            "https://crucible.vercel.app///",
            "  https://crucible.vercel.app  ",
            "HTTPS://Crucible.Vercel.App",
            // A path, a query and a fragment all left on the end by a copy from the address bar.
            "https://crucible.vercel.app/login",
            "https://crucible.vercel.app/some/page?a=1",
            "https://crucible.vercel.app/#top",
            "crucible.vercel.app/login",
        ] {
            #expect(CloudAddress.normalise(typed) == expected, "\"\(typed)\"")
        }
    }

    /// A leftover path is the one that would be silently broken: every request the app makes would be
    /// prefixed with it, so all of them would 404 while the address looked perfectly correct.
    @Test("Nothing after the host survives, because it would be prefixed to every request")
    func pathsAreDropped() {
        let address = try? #require(CloudAddress.normalise("https://host.example.com/dashboard/x"))
        #expect(address == "https://host.example.com")
    }

    @Test("A local server may be insecure; anything else may not")
    func insecureOnlyLocally() {
        // On this desk, where there is no network to listen on.
        #expect(CloudAddress.normalise("http://localhost:8080") == "http://localhost:8080")
        #expect(CloudAddress.normalise("http://127.0.0.1:8080") == "http://127.0.0.1:8080")
        // Anywhere else, plain http would send the token that stands in for somebody's whole account
        // across a network in the clear.
        #expect(CloudAddress.normalise("http://crucible.vercel.app") == nil)
        #expect(CloudAddress.normalise("http://example.com") == nil)
    }

    @Test("Things that are not addresses are refused rather than half-accepted")
    func nonAddressesRefused() {
        for typed in [
            "",
            "   ",
            "localhost is where it runs",
            "ftp://example.com",
            "ssh://example.com",
            // A bare word is a machine on a local network, not a server on the internet.
            "mymachine",
            "myserver",
            ".example.com",
            "example.com.",
            "exam..ple.com",
            "https://",
            "https://exa mple.com",
            "https://exam<ple>.com",
        ] {
            #expect(CloudAddress.normalise(typed) == nil, "\"\(typed)\" was accepted")
        }
    }

    /// An address carrying credentials would send them with every single request, to a server that never
    /// asked for them.
    @Test("Credentials in an address are dropped")
    func credentialsDropped() {
        #expect(CloudAddress.normalise("https://someone:secret@example.com") == "https://example.com")
    }

    /// The substring search the address tidying depends on, written by hand rather than borrowed.
    ///
    /// The standard library's version requires macOS 13, which the rest of the engine does not, and Linux
    /// applies no such gate — so the convenient one compiled perfectly here and failed the macOS build.
    /// These are the cases an off-by-one in a hand-written search gets wrong.
    @Test("Finding one run of characters inside another")
    func substringSearch() {
        #expect("https://example.com".containsRun("://"))
        #expect("a..b".containsRun(".."))
        #expect(!"a.b".containsRun(".."))
        // At the very start and the very end, which is where an off-by-one shows.
        #expect("://x".containsRun("://"))
        #expect("x://".containsRun("://"))
        #expect("..".containsRun(".."))
        // A needle longer than the haystack, and both empty.
        #expect(!"a".containsRun("abc"))
        #expect(!"".containsRun("a"))
        #expect("abc".containsRun(""))
        // A near miss that shares a prefix, which a search that fails to back up would accept.
        #expect(!"a:/b".containsRun("://"))
        #expect("a:/:/ /://".containsRun("://"))
        // Multi-byte characters, since this works in bytes.
        #expect("héllo".containsRun("éll"))
        #expect(!"hello".containsRun("é"))
    }

    // MARK: Signing in

    @Test("The list of ways to sign in is read")
    func providersDecode() throws {
        let list = try decode(
            CloudProviderList.self,
            from: #"{"providers":[{"id":"google","label":"Google"},{"id":"x","label":"X"}]}"#
        )
        #expect(list.providers.map(\.id) == ["google", "x"])
        #expect(list.providers.map(\.label) == ["Google", "X"])
    }

    @Test("The sign-in paths are the ones the server answers on")
    func signInPaths() {
        #expect(CloudPath.providers == "/api/v1/auth/providers")
        #expect(CloudPath.me == "/api/v1/me")
        #expect(CloudPath.signIn(provider: "google") == "/api/v1/auth/start/google")
        // A provider name is a string from the server, so it is escaped like any other.
        #expect(CloudPath.signIn(provider: "a/b") == "/api/v1/auth/start/a%2Fb")
    }

    @Test("A successful sign-in hands over its token")
    func callbackCarriesToken() {
        #expect(CloudCallback.outcome(query: "token=abc123") == .token("abc123"))
    }

    /// The case that would be silently broken. A session token is two base64 parts joined by a dot, and
    /// base64 contains `+`, `/` and `=`. Every one of them arrives percent-encoded, and a decoder that
    /// mishandled any would produce a token that looks perfectly reasonable and is refused by every
    /// request from then on — which reads as "signing in does not work" with nothing to point at.
    @Test("A token containing base64 punctuation survives intact")
    func tokenPunctuationSurvives() {
        let token = "AbC+dEf/gH=.iJk+LmN/oP=="
        // As the server writes it into the callback address.
        let escaped = "AbC%2BdEf%2FgH%3D.iJk%2BLmN%2FoP%3D%3D"
        #expect(CloudCallback.outcome(query: "token=\(escaped)") == .token(token))
    }

    /// `+` in a query means a space. That is exactly why the server escapes a base64 `+` as `%2B` — and
    /// why this must keep treating a bare `+` as a space rather than "helpfully" leaving it alone.
    @Test("A bare plus is a space, which is why a real plus arrives escaped")
    func barePlusIsSpace() {
        #expect(CloudCallback.decode("a+b") == "a b")
        #expect(CloudCallback.decode("a%2Bb") == "a+b")
    }

    @Test("A failed sign-in carries its reason")
    func callbackCarriesReason() {
        #expect(CloudCallback.outcome(query: "error=sign_in_declined") == .failed("sign_in_declined"))
    }

    /// A callback with nothing useful in it must still finish. Ignoring it leaves the interface waiting
    /// forever on something that has already happened.
    @Test("A callback that says nothing is treated as a failure, not ignored")
    func emptyCallbackIsFailure() {
        #expect(CloudCallback.outcome(query: "") == .failed("no_session"))
        #expect(CloudCallback.outcome(query: "token=") == .failed("no_session"))
        #expect(CloudCallback.outcome(query: "error=") == .failed("no_session"))
        #expect(CloudCallback.outcome(query: "unrelated=1") == .failed("no_session"))
    }

    @Test("A malformed callback does not crash or silently drop characters")
    func malformedCallbackSurvives() {
        // A stray percent with nothing usable after it is kept as written, so the result is visibly wrong
        // rather than quietly plausible.
        #expect(CloudCallback.decode("100%") == "100%")
        #expect(CloudCallback.decode("%ZZ") == "%ZZ")
        #expect(CloudCallback.decode("%2") == "%2")
        #expect(CloudCallback.decode("") == "")
        // A field with no value, and repeated separators.
        #expect(CloudCallback.parse(query: "a&&b=1&=2")["b"] == "1")
        #expect(CloudCallback.parse(query: "a") == ["a": ""])
    }

    @Test("Every sign-in failure explains itself in plain words")
    func signInFailuresExplained() {
        let reasons = [
            "unknown_provider", "sign_in_declined", "no_session",
            "sign_in_no_destination", "sign_in_unavailable_500", "something_new",
        ]
        for reason in reasons {
            let text = CloudSignInOutcome.failed(reason).explanation
            #expect(!text.isEmpty, "\(reason)")
            // No identifier should ever reach the screen.
            #expect(!text.contains("_"), "\(reason) leaked its identifier: \(text)")
            #expect(text.hasSuffix("."), "\(reason) is not a sentence: \(text)")
        }
    }

    @Test("Being signed in is read from the server rather than assumed")
    func identityDecodes() throws {
        let identity = try decode(CloudIdentity.self, from: #"{"signedIn":true,"id":"user-1"}"#)
        #expect(identity.signedIn)
        #expect(identity.id == "user-1")
    }

    // MARK: Asking for things

    @Test("A request to keep a world says which chamber it came from")
    func saveRequestEncodes() throws {
        let request = CloudSaveRequest(name: "Volcano", mode: .powder, data: "{}")
        let json = try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"mode\":\"powder\""), "\(json)")
        #expect(json.contains("\"name\":\"Volcano\""), "\(json)")
    }

    /// The server's validator expects `gridData`, not `grid_data`. Sending the wrong one is refused as a
    /// missing field, which reads as a mysterious rejection of a perfectly good world.
    @Test("A publication uses the field names the server validates")
    func publishRequestEncodes() throws {
        let request = CloudPublishRequest(
            title: "Acid Rain", description: "d", tags: "acid", thumbnail: "t", gridData: "{}"
        )
        let json = try String(decoding: JSONEncoder().encode(request), as: UTF8.self)
        #expect(json.contains("\"gridData\":"), "\(json)")
        #expect(!json.contains("grid_data"), "\(json)")
    }
}
