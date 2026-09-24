import CrucibleCore
import SwiftUI
// For the clipboard, so a code can be copied rather than retyped.
import UIKit

/// Sharing a world with somebody in the same room.
///
/// ## What this panel has to be honest about
///
/// More than most. A shared room is the one feature here whose limits are not obvious from using it, and
/// every one of them is the sort of thing that reads as the app being broken:
///
///   - it only works between phones in the same place, so someone trying it with a friend in another
///     city will find nothing and have no idea why;
///   - one phone runs the world and the others watch, so a follower's own controls do very little;
///   - and it will not connect to the web version, which looks identical and is not.
///
/// So the panel says all three, in the room rather than buried in help, and shows plainly which device
/// is running things.
struct RoomSheet: View {
    let bridge: RoomBridge
    let glass: GlassLevel

    @State private var typedCode = ""
    @FocusState private var codeFieldFocused: Bool

    private var room: RoomSession { bridge.session }

    var body: some View {
        LabSheet(title: "Shared room", subtitle: subtitle, glass: glass) {
            if let problem = room.problem {
                notice(problem)
            }

            switch room.status {
            case .closed:
                closedControls
            case .open, .connected:
                openControls
            }

            explanation
        }
    }

    /// The three limits, said out loud.
    ///
    /// Here rather than in the help screen on purpose. Every one of them reads as the app being broken if
    /// you meet it without having been told, and the moment somebody is most likely to meet them is while
    /// this panel is open and nothing is happening.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works".uppercased())
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            note("A room is between phones in the same place, over wifi or Bluetooth. There is no server and nothing goes over the internet — so somebody in another town cannot join.")
            note("One phone runs the world and the others are shown it, many times a second. Everyone can paint, and every mark goes to whichever phone is running things. If that phone leaves, another takes over on its own.")
            note("Crucible in a browser has its own rooms, built a different way. The two cannot see each other.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.labBody(11))
            .foregroundStyle(Palette.subtleForeground)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String? {
        switch room.status {
        case .closed: "Paint in the same world as somebody next to you"
        case .open: "Waiting for somebody to join"
        case .connected: room.isHost ? "You are running the world" : "Watching another phone's world"
        }
    }

    // MARK: Not in a room

    private var closedControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabGroup("Start a room", footnote: "You will get a code to read out to the other person.") {
                LabAction(label: "Open a room", symbol: "person.2.badge.plus") {
                    room.open()
                }
            }

            LabGroup("Join a room", footnote: "Four characters. Case does not matter.") {
                HStack(spacing: 10) {
                    TextField("Code", text: $typedCode)
                        // Monospaced and wide-spaced, because this is a string of characters being
                        // copied one at a time from somebody else's screen rather than a word.
                        .font(.labNumeric(20))
                        .tracking(4)
                        .foregroundStyle(Palette.foreground)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .focused($codeFieldFocused)
                        .onSubmit(join)
                    Spacer(minLength: 0)
                    Button(action: join) {
                        Text("Join")
                            .font(.labBody(12, .semiBold))
                            .foregroundStyle(
                                canJoin ? Palette.primaryForeground : Palette.subtleForeground
                            )
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(canJoin ? Palette.primary : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canJoin)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
            }
        }
    }

    /// Whether what has been typed could be a code.
    ///
    /// Checked with the engine's own reader rather than by counting characters, so the button agrees
    /// exactly with what joining will accept. Two different ideas of "valid" is how a button that is
    /// clearly enabled comes to do nothing when pressed.
    private var canJoin: Bool { RoomCode.normalise(typedCode) != nil }

    private func join() {
        guard canJoin else { return }
        codeFieldFocused = false
        room.join(code: typedCode)
    }

    // MARK: In a room

    private var openControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabGroup("Room code", footnote: "Read this out to whoever is joining.") {
                HStack {
                    Text(room.code)
                        .font(.labNumeric(30))
                        .tracking(8)
                        .foregroundStyle(Palette.foreground)
                    Spacer(minLength: 12)
                    Button {
                        UIPasteboard.general.string = room.code
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.labBody(14, .medium))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy the room code")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 60)
            }

            LabGroup("This phone") {
                LabRow(
                    label: "Role",
                    value: room.isHost ? "Running the world" : "Watching",
                    tint: room.isHost ? Palette.ok : Palette.foreground
                )
                LabDivider()
                LabRow(label: "Status", value: statusText, tint: statusTint)
                if room.status == .connected {
                    LabDivider()
                    LabRow(label: "Worlds a second", value: "\(room.framesPerSecond)")
                }
                if room.unreadableFrames > 0 {
                    LabDivider()
                    LabRow(
                        label: "Unreadable",
                        value: "\(room.unreadableFrames)",
                        tint: Palette.danger
                    )
                }
            }

            LabGroup(
                room.peers.isEmpty ? "Nobody else yet" : "Also here",
                footnote: room.peers.isEmpty
                    ? "Keep this open. The other phone needs to be nearby, with Crucible open and the same code typed in."
                    : nil
            ) {
                if room.peers.isEmpty {
                    LabRow(label: "Looking nearby", value: "…", tint: Palette.muted)
                } else {
                    // Keyed by position rather than by name. The names are unique by construction, but a
                    // list that crashes if that ever stops being true is not worth the tidier code.
                    ForEach(Array(room.peers.enumerated()), id: \.offset) { index, peer in
                        if index > 0 { LabDivider() }
                        LabRow(label: peer, value: "")
                    }
                }
            }

            if room.unreadableFrames > 0 {
                note("""
                Some worlds arrived that this phone could not read. That almost always means the two \
                phones are running different versions of Crucible — updating both to the same one \
                should fix it.
                """)
            }

            LabGroup {
                LabAction(label: "Leave the room", symbol: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                    bridge.leave()
                    typedCode = ""
                }
            }
        }
    }

    private var statusText: String {
        switch room.status {
        case .closed: "Not in a room"
        case .open: "Waiting"
        case .connected: room.isCurrent ? "In step" : "Nothing arriving"
        }
    }

    private var statusTint: Color {
        switch room.status {
        case .closed: Palette.muted
        case .open: Palette.warn
        case .connected: room.isCurrent ? Palette.ok : Palette.danger
        }
    }

    // MARK: Something went wrong

    private func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.labBody(13, .medium))
                .foregroundStyle(Palette.warn)
            Text(message)
                .font(.labBody(12))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                room.dismissProblem()
            } label: {
                Image(systemName: "xmark")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.subtleForeground)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.warn.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(Palette.warn.opacity(0.3), lineWidth: 1)
        )
    }
}
