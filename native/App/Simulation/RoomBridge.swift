import CrucibleCore
import Foundation
import Observation

/// Connects the powder chamber to a shared room.
///
/// ## Why this is its own object
///
/// The same reason `ChamberBridge` is. The model must not know what MultipeerConnectivity is, and the
/// room must not know what a `PowderEngine` is — so the wiring between them belongs to neither and lives
/// here. It is also the only place that holds both, which makes it the only place that can close a
/// reference cycle, so it is the only place that has to be careful about it.
///
/// ## What actually crosses
///
/// Four things, and it is worth being able to see all four at once:
///
///   - **Every tick**, the host offers its world to the room. The room decides whether a frame is due;
///     if it is not, nothing is packed and nothing is sent.
///   - **Every tick**, the host offers its settings. Almost always they have not changed and nothing
///     happens.
///   - **Every local stroke** goes to the room, which sends it on only if this device is a follower — the
///     host's next world frame carries its own strokes already.
///   - **Everything arriving** is handed to the model: a world to display, a stroke to apply, settings to
///     adopt.
///
/// And one piece of state rather than an event: whether the model should be simulating at all. A follower
/// must not, so the room's idea of who hosts is pushed onto the model whenever it changes.
@MainActor
@Observable
final class RoomBridge {
    /// The room itself. Everything about its state is read from here.
    let session: RoomSession
    private let powder: SimulationModel

    /// How often a quiet link is checked for having gone silent, in ticks.
    ///
    /// About once a second at sixty frames, twice at a hundred and twenty. It does not need to be precise
    /// — it exists so that a follower whose host has stopped sending eventually asks again instead of
    /// staring at a still picture forever.
    private static let silenceCheckInterval = 60

    private var sinceSilenceCheck = 0

    init(powder: SimulationModel) {
        self.powder = powder
        session = RoomSession()
        connect()
    }

    private func connect() {
        // Every closure captures weakly. The model holds two of these, the room holds three, and this
        // object holds both — so capturing strongly would close a cycle through every one of them and
        // keep the lot alive for as long as the app runs.
        powder.onTicked = { [weak self] in
            self?.tick()
        }

        powder.onLocalStroke = { [weak self] stroke in
            self?.session.send(stroke: stroke)
        }

        session.onRemoteWorld = { [weak self] world in
            guard let self else { return false }
            return powder.applyRemote(world: world)
        }

        session.onRemoteStroke = { [weak self] stroke in
            self?.powder.applyRemote(stroke: stroke)
        }

        session.onRemoteSettings = { [weak self] settings in
            self?.powder.applyRemote(settings: settings)
        }
    }

    /// Called at the end of every tick of the powder chamber.
    private func tick() {
        // Pushed rather than read, so the model never has to know a room exists. A follower stops
        // simulating from the next tick onwards.
        let shouldFollow = session.status == .connected && !session.isHost
        if powder.isFollowingRoom != shouldFollow {
            powder.isFollowingRoom = shouldFollow
        }

        // The closure is the point: the room calls it only when a frame is genuinely due, so packing a
        // world — a full pass over the grid and then compressing it — happens at the rate the link can
        // carry rather than once per frame and mostly thrown away.
        session.offerWorld { [powder] sequence in
            powder.roomWorld(sequence: sequence)
        }
        session.offerSettings(powder.roomSettings())

        sinceSilenceCheck += 1
        if sinceSilenceCheck >= Self.silenceCheckInterval {
            sinceSilenceCheck = 0
            session.checkForSilence()
        }
    }

    /// Stops sharing, and gives the chamber back to whoever is holding the phone.
    func leave() {
        session.leave()
        // Put back at once rather than on the next tick. Leaving a room should hand control back
        // immediately, and a paused world would otherwise stay frozen with no obvious reason why.
        powder.isFollowingRoom = false
        // The host's world may have been a different shape; it is redrawn to fit this screen rather than
        // left stretched onto it.
        powder.refitToScreen()
    }
}
