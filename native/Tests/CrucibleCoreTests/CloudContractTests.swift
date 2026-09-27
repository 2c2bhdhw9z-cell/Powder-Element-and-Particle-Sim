import Foundation
import Testing

@testable import CrucibleCore

/// The phone's half of the agreement with the server: what it asks for, and whether it can read what comes back.
///
/// ## How the two halves meet
///
/// Two files in `Fixtures/`, each written by one side and checked by the other:
///
/// - `phone-requests.json` is every request the phone's cloud client makes — the method, the exact path its own path
///   builder produces, and the exact body its encoder writes. This test builds them afresh and fails if they no
///   longer match the file.
/// - `server-replies.json` is what the server answered when every one of those requests was replayed against it, with
///   a real database built from its real migrations (`web/src/lib/api/__tests__/phone-contract.test.ts`, run by the
///   Server check). This test decodes every answer with the phone's own types.
///
/// So a server that renames a field fails its own check (its answers no longer match the file), and once the file is
/// brought up to date, fails this one (the phone cannot read it). A phone that changes a path or a body fails here
/// until the file is updated, and then the server's check replays the new request.
///
/// To bring the phone's file up to date after a deliberate change:
///
///     CRUCIBLE_WRITE_CONTRACT=1 swift test --filter CloudContractTests
///
/// and then run the server's check the same way (see that file) so its answers are recorded for the new requests.
@Suite("What the phone asks the server, and what it can read back")
struct CloudContractTests {
    /// One request, as the phone makes it.
    struct PhoneRequest: Codable, Equatable {
        /// What it is called here and in the server's recording of its answer.
        var name: String
        var method: String
        /// Exactly what the phone's path builder produces. `SAVE-ID` and `MAP-ID` stand for whatever ids the server
        /// hands back for the save and the map made earlier in the list; the server's check puts those in.
        var path: String
        /// Which of the server's operations this must reach.
        var operation: String
        /// For an operation about one thing, the id the server must see once the path's escaping is undone.
        var id: String?
        /// Whether the phone sends its sign-in with it.
        var signedIn: Bool
        /// The body, exactly as the phone's encoder writes it but with its keys in order, so the file does not change
        /// from one run to the next.
        var body: String?
        /// Whether the server's answer is recorded. Starting a sign-in hands over to a web page rather than
        /// answering, so only where it leads is checked.
        var replay: Bool

        init(
            _ name: String,
            _ method: String,
            _ path: String,
            reaches operation: String,
            id: String? = nil,
            signedIn: Bool = false,
            body: String? = nil,
            replay: Bool = true
        ) {
            self.name = name
            self.method = method
            self.path = path
            self.operation = operation
            self.id = id
            self.signedIn = signedIn
            self.body = body
            self.replay = replay
        }
    }

    struct RequestFile: Codable, Equatable {
        var requests: [PhoneRequest]
    }

    /// What the phone sends as a body: its request types through a plain encoder, as `CloudClient` does.
    static func encode<Body: Encodable>(_ body: Body) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(body), as: UTF8.self)
    }

    /// The name of the world kept in the list below, and what is in it, so what comes back can be checked against them.
    static let saveName = "Sandcastle at high tide"
    static let saveData = #"{"powder":{"height":4,"width":4},"version":2}"#
    static let mapTitle = "Lava lamp, done in powder"
    static let mapGrid = #"{"height":4,"width":4}"#
    /// Deliberately full of things a path has to escape: a space, a slash and a question mark.
    static let awkwardID = "a b/c?d"

    /// Every request the phone's cloud client makes, in an order that leaves something to find for the ones that look
    /// things up. One line per method on `CloudClient`, plus sign-in from `CloudAccount`; a new method there needs a
    /// line here, or the server is never asked whether it understands it.
    static func phoneRequests() throws -> [PhoneRequest] {
        let save = CloudSaveRequest(name: saveName, mode: .powder, data: saveData)
        let publish = CloudPublishRequest(
            title: mapTitle,
            description: "Warm wax rises, cools at the top and sinks again.",
            tags: "lava, sand art & water",
            thumbnail: "",
            gridData: mapGrid
        )
        return [
            PhoneRequest("status", "GET", CloudPath.status, reaches: "status"),
            PhoneRequest("providers", "GET", CloudPath.providers, reaches: "providers"),
            PhoneRequest(
                "signInStart", "GET", CloudPath.signIn(provider: "google"), reaches: "signInStart", replay: false
            ),
            // With no sign-in: how the phone finds out a kept sign-in has run out.
            PhoneRequest("meSignedOut", "GET", CloudPath.me, reaches: "me"),
            PhoneRequest("me", "GET", CloudPath.me, reaches: "me", signedIn: true),
            PhoneRequest("createSave", "POST", CloudPath.saves, reaches: "createSave", signedIn: true, body: try encode(save)),
            PhoneRequest("listSaves", "GET", CloudPath.saves, reaches: "listSaves", signedIn: true),
            PhoneRequest("loadSave", "GET", CloudPath.save("SAVE-ID"), reaches: "loadSave", id: "SAVE-ID", signedIn: true),
            PhoneRequest(
                "loadAwkwardSave", "GET", CloudPath.save(awkwardID), reaches: "loadSave", id: awkwardID, signedIn: true
            ),
            PhoneRequest("publishMap", "POST", CloudPath.maps, reaches: "publishMap", signedIn: true, body: try encode(publish)),
            PhoneRequest("listMapsRecent", "GET", CloudPath.mapsQuery(sort: .recent, tag: "", limit: 60), reaches: "listMaps"),
            PhoneRequest(
                "listMapsTagged", "GET", CloudPath.mapsQuery(sort: .popular, tag: "sand art & water", limit: 60),
                reaches: "listMaps"
            ),
            PhoneRequest("likeMap", "POST", CloudPath.like("MAP-ID"), reaches: "likeMap", id: "MAP-ID"),
            PhoneRequest("downloadMap", "POST", CloudPath.download("MAP-ID"), reaches: "downloadMap", id: "MAP-ID"),
            PhoneRequest("likeMissingMap", "POST", CloudPath.like("nothing-here"), reaches: "likeMap", id: "nothing-here"),
            PhoneRequest("deleteSave", "DELETE", CloudPath.save("SAVE-ID"), reaches: "deleteSave", id: "SAVE-ID", signedIn: true),
        ]
    }

    /// Where the fixtures are in the source, for writing them. Reading goes through the test bundle, like every other
    /// fixture here.
    private static var sourceFixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private static func fixture(_ name: String) -> Data? {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    @Test("The requests the phone makes are the ones recorded for the server to answer")
    func requestsAreRecorded() throws {
        let current = RequestFile(requests: try Self.phoneRequests())
        if ProcessInfo.processInfo.environment["CRUCIBLE_WRITE_CONTRACT"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var text = try encoder.encode(current)
            text.append(0x0A)
            try text.write(to: Self.sourceFixtures.appendingPathComponent("phone-requests.json"))
            return
        }
        let data = try #require(Self.fixture("phone-requests"), "phone-requests.json is missing from Fixtures")
        let recorded = try JSONDecoder().decode(RequestFile.self, from: data)
        #expect(
            recorded == current,
            "The phone now asks the server something different. If that is meant, write the file again (see the note at the top), then record the server's answers."
        )
        #expect(Set(current.requests.map(\.name)).count == current.requests.count, "two requests share a name")
    }

    /// The server's recorded answers, by the name of the request that got them.
    private static func replies() throws -> [String: (status: Int, body: Data)] {
        let data = try #require(fixture("server-replies"), "server-replies.json is missing from Fixtures")
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = try #require(root["replies"] as? [[String: Any]])
        var found: [String: (status: Int, body: Data)] = [:]
        for reply in list {
            let name = try #require(reply["name"] as? String)
            let status = try #require(reply["status"] as? Int)
            let body = try #require(reply["body"])
            found[name] = (status, try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed]))
        }
        return found
    }

    private struct Likes: Decodable {
        var likes: Int
    }

    private struct Done: Decodable {
        var ok: Bool
    }

    @Test("Every answer the server gave is one the phone can read, and says what it should")
    func repliesAreReadable() throws {
        let replies = try Self.replies()
        let decoder = JSONDecoder()
        func reply<T: Decodable>(_ name: String, _ type: T.Type, status: Int = 200) throws -> T {
            let found = try #require(replies[name], "the server has no recorded answer to \(name)")
            #expect(found.status == status, "\(name) was answered with \(found.status), not \(status)")
            do {
                return try decoder.decode(type, from: found.body)
            } catch {
                Issue.record("the phone cannot read the server's answer to \(name): \(String(describing: error))")
                throw error
            }
        }

        // Every request that is replayed has an answer.
        for request in try Self.phoneRequests() where request.replay {
            #expect(replies[request.name] != nil, "the server's answer to \(request.name) was never recorded")
        }

        let status = try reply("status", CloudStatus.self)
        #expect(status.api == 1)
        let providers = try reply("providers", CloudProviderList.self)
        #expect(!providers.providers.isEmpty, "no ways to sign in were offered")

        let refused = try reply("meSignedOut", CloudError.self, status: 401)
        #expect(!refused.error.isEmpty)
        let me = try reply("me", CloudIdentity.self)
        #expect(me.signedIn)

        _ = try reply("createSave", CloudCreated.self, status: 201)
        let saves = try reply("listSaves", CloudSaveList.self)
        #expect(saves.saves.map(\.name) == [Self.saveName])
        #expect(saves.saves.first?.mode == CloudChamber.powder.rawValue)
        #expect(!(saves.saves.first?.createdAt.isEmpty ?? true), "a save came back with no date")
        let loaded = try reply("loadSave", CloudSave.self)
        #expect(loaded.data == Self.saveData, "the world came back different from how it was sent")
        _ = try reply("loadAwkwardSave", CloudError.self, status: 404)

        _ = try reply("publishMap", CloudCreated.self, status: 201)
        for listing in ["listMapsRecent", "listMapsTagged"] {
            let maps = try reply(listing, CloudMapList.self)
            #expect(maps.maps.map(\.title) == [Self.mapTitle], "\(listing) did not find the world just published")
            #expect(maps.maps.first?.author == "Test Physicist", "the published world was not credited to its author")
        }
        #expect(try reply("likeMap", Likes.self).likes == 1)
        let downloaded = try reply("downloadMap", CloudMap.self)
        #expect(downloaded.gridData == Self.mapGrid)
        _ = try reply("likeMissingMap", CloudError.self, status: 404)
        #expect(try reply("deleteSave", Done.self).ok)
    }
}
