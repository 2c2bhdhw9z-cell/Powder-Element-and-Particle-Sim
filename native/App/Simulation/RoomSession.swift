import CrucibleCore
import Foundation
import MultipeerConnectivity
import Observation
// For the device's own name, which is half of how a peer is identified.
import UIKit

/// Two phones in the same place, sharing one world.
///
/// ## Why this and not what the web version does
///
/// The web version uses WebRTC with a signalling server. That is right for a browser and wrong here:
/// iOS has no WebRTC of its own, so it would mean a third-party framework — and a framework is a dynamic
/// library that needs its own matching provisioning profile every time this app is signed on a device.
/// This app ships unsigned and is signed by whoever installs it. Every embedded framework is another way
/// for that to fail.
///
/// MultipeerConnectivity is already in iOS, needs nothing added, and — the part that matters most —
/// needs **no server at all**. It does precisely what this feature is for.
///
/// Two consequences, stated plainly here because the interface has to state them plainly too:
///
///   - It is phone to phone, over local network or Bluetooth. Two people in different cities cannot use
///     it. Cross-network rooms would need a relay on the server, which is separate work.
///   - A native room and a web room are different rooms and will not see each other. One is
///     MultipeerConnectivity, the other WebRTC; there is no arrangement under which they interoperate.
///
/// ## Where the thinking is
///
/// Almost none of it is here. Who is in charge, when the next world frame may go out, whether an arriving
/// frame is newer than the one on screen, what a typed code means — all of that is in `RoomCoordinator`
/// and `RoomWorld` in the engine, with tests. This file is the part that cannot be tested without two
/// real phones, and it is deliberately as thin as it can be made.

// MARK: - What the transport reports

/// Something that happened on the link.
///
/// Everything in it is a plain value. That is the point: MultipeerConnectivity's own types are not safe
/// to hand between threads, and its callbacks arrive on whichever queue it feels like. Reading what is
/// needed into strings and bytes at the moment of arrival means nothing of Apple's crosses a boundary.
enum RoomTransportEvent: Sendable {
    /// Who is connected now, by identifier.
    case peersChanged([String])
    /// A packet, and who sent it.
    case received([UInt8], from: String)
    /// Something went wrong that somebody should be told about.
    case failed(String)
}

// MARK: - The link

/// Apple's classes, wrapped so that nothing of theirs escapes into the rest of the app.
///
/// Marked as safe to share across threads by hand, and the reason it is true: after `init` every stored
/// property is a constant. Nothing here has mutable state to protect, so the callbacks arriving on
/// MultipeerConnectivity's queues and the calls arriving from the main actor cannot interfere. The one
/// assumption left is that Apple's own objects tolerate being used from more than one queue, which is
/// how every implementation of this framework is written and what its API shape requires.
final class RoomTransport: NSObject, @unchecked Sendable {
    /// Must be fifteen characters or fewer, lower case letters, digits and hyphens. This is thirteen.
    static let serviceType = "crucible-room"
    /// The key the room code travels under, in what a peer advertises.
    private static let codeKey = "rc"

    /// This peer's identifier: unique, stable for the session, and sortable — which is what decides who
    /// hosts, with no negotiation.
    let identifier: String

    private let code: String
    private let peerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private let publish: AsyncStream<RoomTransportEvent>.Continuation

    /// Everything that happens on the link, in the order it happened.
    ///
    /// A stream rather than callbacks straight onto the main actor. Separate hops onto an actor are not
    /// promised to run in the order they were made, and this is a protocol where order matters — a world
    /// frame overtaking the one before it would show the past. A stream keeps them in order.
    ///
    /// Bounded, and drops the oldest when full. Unbounded is the obvious choice and the wrong one: if the
    /// main actor were ever held up, frames would pile up without limit. Sixty-four is far more than a
    /// responsive app ever holds, and if it is somehow exceeded, losing the oldest is exactly right —
    /// stale world frames are worthless by then anyway.
    let events: AsyncStream<RoomTransportEvent>

    init(identifier: String, code: String) {
        self.identifier = identifier
        self.code = code
        let id = MCPeerID(displayName: identifier)
        peerID = id
        // Encryption required rather than optional. It costs a little setup time on a link that is
        // already the slow part, and it means a world in progress is not readable by anything else on
        // the café wifi.
        session = MCSession(peer: id, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(
            peer: id,
            discoveryInfo: [Self.codeKey: code],
            serviceType: Self.serviceType
        )
        browser = MCNearbyServiceBrowser(peer: id, serviceType: Self.serviceType)
        let made = AsyncStream<RoomTransportEvent>.makeStream(
            of: RoomTransportEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        events = made.stream
        publish = made.continuation
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    /// Starts telling others this room exists, and starts looking for them.
    ///
    /// Both at once, every peer. There is no host to be chosen by who started first — that is settled
    /// afterwards, from the identifiers, by arithmetic every peer does for itself.
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        publish.finish()
    }

    /// Sends to everyone connected.
    ///
    /// - Parameter reliable: `true` for anything that would be missed. Everything this app sends is
    ///   reliable: strokes because a lost one is a mark that never appeared, and world frames because the
    ///   pacing already prevents a backlog — there is never more than one outstanding, so reliability
    ///   costs nothing and unreliable delivery would let frames arrive out of order for no gain.
    func send(_ bytes: [UInt8], reliable: Bool = true) {
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }
        do {
            try session.send(Data(bytes), toPeers: peers, with: reliable ? .reliable : .unreliable)
        } catch {
            publish.yield(.failed("Could not send to the room: \(error.localizedDescription)"))
        }
    }
}

// MARK: - MCSessionDelegate

extension RoomTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer _: MCPeerID, didChange _: MCSessionState) {
        // Read as identifiers here and now, so no peer object leaves this queue.
        publish.yield(.peersChanged(session.connectedPeers.map(\.displayName)))
    }

    func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        publish.yield(.received([UInt8](data), from: peerID.displayName))
    }

    // Streams and file transfers are not used. Required by the protocol, so they are here and empty
    // rather than being left to a default that does not exist.
    func session(_: MCSession, didReceive _: InputStream, withName _: String, fromPeer _: MCPeerID) {}

    func session(
        _: MCSession,
        didStartReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        with _: Progress
    ) {}

    func session(
        _: MCSession,
        didFinishReceivingResourceWithName _: String,
        fromPeer _: MCPeerID,
        at _: URL?,
        withError _: (any Error)?
    ) {}
}

// MARK: - Advertising

extension RoomTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        // Nearly always the missing local network permission, and the failure is otherwise silent.
        publish.yield(.failed("Could not open the room. \(error.localizedDescription)"))
    }

    func advertiser(
        _: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let theirCode = context.flatMap { String(data: $0, encoding: .utf8) }
        // The code is checked on both sides. The browser already filters on what was advertised; this
        // catches an invitation that did not come from a browser doing that.
        guard theirCode == code else {
            invitationHandler(false, nil)
            return
        }
        // Lower invites higher, so exactly one of any two peers invites the other. Without a rule like
        // this, both peers browse, both invite, and the pair can end up with two half-built connections
        // where neither side agrees which one is real.
        guard peerID.displayName < identifier else {
            invitationHandler(false, nil)
            return
        }
        invitationHandler(true, session)
    }
}

// MARK: - Browsing

extension RoomTransport: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        // A different code is a different room. This is the whole mechanism by which two groups of people
        // in one place do not end up painting in each other's worlds.
        guard info?[Self.codeKey] == code else { return }
        // The other half of "lower invites higher".
        guard identifier < peerID.displayName else { return }
        browser.invitePeer(peerID, to: session, withContext: Data(code.utf8), timeout: 20)
    }

    func browser(_: MCNearbyServiceBrowser, lostPeer _: MCPeerID) {
        // Nothing to do. Losing sight of a peer that is not connected is not an event; the session
        // reports the ones that matter.
    }

    func browser(_: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        publish.yield(.failed("Could not look for anyone nearby. \(error.localizedDescription)"))
    }
}

// MARK: - The room

/// A shared room, as the rest of the app sees it.
@MainActor
@Observable
final class RoomSession {
    enum Status: Equatable {
        /// Not in a room.
        case closed
        /// In a room, waiting for somebody else.
        case open
        /// Sharing a world with at least one other person.
        case connected
    }

    private(set) var status: Status = .closed
    /// The code to read out to somebody.
    private(set) var code = ""
    /// Who else is here, by identifier.
    private(set) var peers: [String] = []
    /// Whether this device is the one simulating.
    ///
    /// Alone in a room, yes — which is what makes a room work before anyone arrives.
    private(set) var isHost = true
    /// The last thing that went wrong, for saying so rather than failing silently.
    private(set) var problem: String?
    /// World frames exchanged in the last second, sampled rather than counted live.
    private(set) var framesPerSecond = 0
    /// Whether a frame has been exchanged recently. What "in sync" in the interface means.
    private(set) var isCurrent = false
    /// How many frames arrived that this build could not read.
    ///
    /// Worth showing. It should be nought, and anything else means the two phones are running builds
    /// that disagree about the format — which is a thing somebody can act on, unlike a world that simply
    /// looks stuck.
    private(set) var unreadableFrames = 0

    /// A stroke arrived from somebody else. Only the host is given these.
    var onRemoteStroke: (@MainActor (RoomStroke) -> Void)?
    /// A world arrived. Returns whether it could be used.
    var onRemoteWorld: (@MainActor (RoomWorld) -> Bool)?
    /// The host's settings arrived.
    var onRemoteSettings: (@MainActor (RoomSettings) -> Void)?

    @ObservationIgnored private var transport: RoomTransport?
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var pacer = RoomPacer()
    @ObservationIgnored private var lastAppliedSequence: UInt32 = 0
    /// Which peer sent the last world frame, so a change of host can be noticed.
    @ObservationIgnored private var lastWorldFrom: String?
    @ObservationIgnored private var lastSentSettings: RoomSettings?
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var lastCountedAt = CFAbsoluteTimeGetCurrent()
    @ObservationIgnored private var lastFrameAt: CFAbsoluteTime = 0
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    /// How long without a frame before the interface stops claiming to be up to date.
    private static let staleAfter: CFAbsoluteTime = 1.5

    // MARK: Opening and closing

    /// Opens a new room and returns its code.
    @discardableResult
    func open() -> String {
        var generator = Mulberry32(seed: UInt32.random(in: UInt32.min ... UInt32.max))
        let newCode = RoomCode.generate(using: &generator)
        join(code: newCode)
        return newCode
    }

    /// Joins the room with a given code.
    ///
    /// - Returns: whether the code was one. A code that is nearly right is refused rather than corrected,
    ///   because correcting it into a *different* valid code means joining a stranger's room.
    @discardableResult
    func join(code typed: String) -> Bool {
        guard let wanted = RoomCode.normalise(typed) else {
            problem = "That is not a room code. They are four characters long."
            return false
        }
        leave()

        let link = RoomTransport(identifier: Self.makeIdentifier(), code: wanted)
        transport = link
        code = wanted
        problem = nil
        status = .open
        peers = []
        isHost = true
        pacer = RoomPacer()
        lastAppliedSequence = 0
        lastWorldFrom = nil
        lastSentSettings = nil
        unreadableFrames = 0

        // Started before the link, so nothing that happens on connection can be missed.
        pump = Task { [weak self] in
            for await event in link.events {
                guard let self else { return }
                handle(event)
            }
        }
        link.start()
        return true
    }

    func leave() {
        pump?.cancel()
        pump = nil
        transport?.stop()
        transport = nil
        status = .closed
        peers = []
        code = ""
        isHost = true
        isCurrent = false
        framesPerSecond = 0
    }

    /// Clears a reported problem, once somebody has read it.
    func dismissProblem() {
        problem = nil
    }

    // MARK: Sending

    /// Offers the world to the room, once per frame.
    ///
    /// - Parameter capture: called **only** when a frame is actually going out. Packing a world is a full
    ///   pass over the grid and then compressing it, which is far too much to do every frame and throw
    ///   away — so the decision comes first and the work second.
    func offerWorld(_ capture: @MainActor (UInt32) -> RoomWorld) {
        guard let transport, isHost, !peers.isEmpty else { return }
        guard let sequence = pacer.nextFrame(now: CFAbsoluteTimeGetCurrent(), peers: peers) else { return }
        guard let frame = capture(sequence).encoded() else { return }
        transport.send(RoomPacket.wrap(.world, frame))
        noteFrame()
    }

    /// Passes the world's settings on, if they have changed since last time.
    ///
    /// Called every frame and almost always does nothing. Comparing four numbers is cheaper than keeping
    /// track of which of them somebody might have touched.
    func offerSettings(_ settings: RoomSettings) {
        guard let transport, isHost, !peers.isEmpty else { return }
        guard settings != lastSentSettings else { return }
        lastSentSettings = settings
        send(.settings(settings), over: transport)
    }

    /// Sends a stroke this device just painted.
    ///
    /// Only a follower needs to. The host's world is the truth and its next frame carries the stroke
    /// already, so sending it as well would be the same information twice.
    func send(stroke: RoomStroke) {
        guard let transport, !isHost, !peers.isEmpty else { return }
        send(.stroke(stroke), over: transport)
    }

    private func send(_ message: RoomMessage, over transport: RoomTransport) {
        guard let data = try? encoder.encode(message) else { return }
        transport.send(RoomPacket.wrap(.control, [UInt8](data)))
    }

    // MARK: Receiving

    private func handle(_ event: RoomTransportEvent) {
        switch event {
        case let .peersChanged(identifiers):
            peersChanged(to: identifiers)
        case let .received(bytes, from):
            received(bytes, from: from)
        case let .failed(message):
            problem = message
        }
    }

    private func peersChanged(to identifiers: [String]) {
        guard let transport else { return }
        peers = identifiers.sorted()
        pacer.retain(peers: peers)
        status = peers.isEmpty ? .open : .connected

        isHost = RoomHost.isHost(me: transport.identifier, peers: peers)

        if isHost {
            // Whatever was sent before is no longer known to be what anyone has.
            //
            // Nothing is announced when this device takes over from a host that has left. The world
            // simply starts moving again, which says it more plainly than any banner would, and the panel
            // states the role outright.
            lastSentSettings = nil
        } else if !peers.isEmpty {
            // A follower with nothing to show. Ask at once rather than waiting out the host's rhythm.
            send(.needWorld, over: transport)
        }
    }

    private func received(_ bytes: [UInt8], from peer: String) {
        guard let packet = RoomPacket.unwrap(bytes) else { return }
        switch packet.channel {
        case .world:
            receivedWorld(packet.payload, from: peer)
        case .control:
            guard let message = try? decoder.decode(RoomMessage.self, from: Data(packet.payload)) else {
                return
            }
            received(message, from: peer)
        }
    }

    private func receivedWorld(_ payload: [UInt8], from peer: String) {
        // The host's own world is the truth. A frame arriving here means two peers each believe they are
        // hosting, which the identifier rule makes impossible — but if it ever happened, adopting the
        // other one's world would have the two overwriting each other forever.
        guard !isHost, let transport else { return }

        guard let world = RoomWorld.decode(payload) else {
            unreadableFrames += 1
            send(.needWorld, over: transport)
            return
        }

        // A different phone is sending the world now: the host left and somebody else took over. Its
        // numbering starts again from one, and one measured against the old host's five hundredth frame
        // looks like something from the distant past.
        //
        // Without this, every frame from the new host would be rejected as stale and the follower would
        // sit staring at a frozen world for good, with the link working perfectly and nothing to
        // indicate why. Found by reading rather than by running, which is the only way it could have
        // been found — it needs three phones and one of them to leave.
        if peer != lastWorldFrom {
            lastWorldFrom = peer
            lastAppliedSequence = 0
        }

        // A frame that arrived after a newer one would show the past.
        guard RoomSequence.isNewer(world.sequence, than: lastAppliedSequence) else { return }
        guard onRemoteWorld?(world) == true else {
            unreadableFrames += 1
            send(.needWorld, over: transport)
            return
        }

        lastAppliedSequence = world.sequence
        noteFrame()
        // Only now, having actually drawn it. Acknowledging on arrival would let the host run ahead of
        // what is on screen, which is the backlog the pacing exists to prevent.
        send(.worldAck(sequence: world.sequence), over: transport)
    }

    private func received(_ message: RoomMessage, from peer: String) {
        switch message {
        case let .worldAck(sequence):
            guard isHost else { return }
            pacer.acknowledge(peer: peer, sequence: sequence)
        case let .stroke(stroke):
            // Only the host applies somebody else's stroke. A follower's world is replaced by the next
            // frame regardless, and applying it here as well would briefly show a mark the host may have
            // refused — a material this build has and that one does not, say.
            guard isHost else { return }
            onRemoteStroke?(stroke)
        case let .settings(settings):
            guard !isHost else { return }
            onRemoteSettings?(settings)
        case .needWorld:
            guard isHost else { return }
            pacer.requestFrame()
        }
    }

    // MARK: Counting

    /// Records a frame, and samples the rate about once a second.
    ///
    /// Counted privately and published rarely on purpose. These change dozens of times a second, and an
    /// observed property that changes that often has the interface rebuilding itself against the very
    /// frame budget the simulation needs.
    private func noteFrame() {
        frameCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        lastFrameAt = now
        let elapsed = now - lastCountedAt
        guard elapsed >= 1 else {
            if !isCurrent { isCurrent = true }
            return
        }
        framesPerSecond = Int((Double(frameCount) / elapsed).rounded())
        frameCount = 0
        lastCountedAt = now
        isCurrent = true
    }

    /// Notices when frames have stopped arriving. Called about once a second from the app's own clock,
    /// because nothing else will happen to notice — a link that has gone quiet produces no events at all.
    func checkForSilence() {
        guard status == .connected else { return }
        let quietFor = CFAbsoluteTimeGetCurrent() - lastFrameAt
        // Only a follower can be left behind. A host with nobody answering is reported by the peer list.
        if !isHost, quietFor > Self.staleAfter {
            if isCurrent { isCurrent = false }
            if framesPerSecond != 0 { framesPerSecond = 0 }
            if let transport { send(.needWorld, over: transport) }
        }
    }

    // MARK: Identity

    /// This device's identifier within a room.
    ///
    /// Two jobs, and they pull in different directions. It is shown to people, so it should read as a
    /// device; and it decides who hosts by sorting, so it must be unique. Hence a name and four random
    /// characters — from iOS 16 onwards `UIDevice.name` gives the model rather than the name somebody
    /// chose, so without the suffix two iPhones would be called the same thing and sorting them would be
    /// a coin toss that each phone could flip differently.
    private static func makeIdentifier() -> String {
        var generator = Mulberry32(seed: .random(in: .min ... .max))
        let suffix = RoomCode.generate(using: &generator)
        let name = UIDevice.current.name
        // MCPeerID is capped at sixty-three bytes and a long device name is easily that. Trimmed by
        // characters rather than bytes, well inside the limit, so no multi-byte character is ever cut in
        // half.
        let trimmed = name.count > 24 ? String(name.prefix(24)) : name
        let base = trimmed.isEmpty ? "iPhone" : trimmed
        return "\(base) \(suffix)"
    }
}
