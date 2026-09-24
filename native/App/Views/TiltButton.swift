import SwiftUI

/// The tilt control, in both chambers' docks.
///
/// One button with three states, matching the web version: tapping cycles off → following →
/// locked → off. "Locked" holds gravity wherever the phone was pointing, which is what lets
/// someone tip a world right over and then bring the phone back level to look at it without
/// everything sliding back.
///
/// A phone that cannot do this, or a person who has refused motion access, gets a button that
/// says so and does nothing, rather than one that looks live and silently fails.
struct TiltButton: View {
    let tilt: TiltSensor
    let glass: GlassLevel

    var body: some View {
        Button {
            tilt.advance()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.labBody(12, .medium))
                Text(label)
                    .font(.labBody(11, .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .glassPanel(glass, in: Capsule())
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(hint)
    }

    private var isAvailable: Bool {
        tilt.status != .denied && tilt.status != .unavailable
    }

    private var symbol: String {
        switch tilt.status {
        case .off: "iphone.gen3"
        case .on: "iphone.gen3.radiowaves.left.and.right"
        case .locked: "lock.iphone"
        // A slash through it, because the reason it does nothing is that it cannot.
        case .denied, .unavailable: "iphone.gen3.slash"
        }
    }

    private var label: String {
        switch tilt.status {
        case .off: "Tilt"
        case .on: "Tilt"
        case .locked: "Locked"
        case .denied, .unavailable: "No tilt"
        }
    }

    /// Green only while it is actually following the phone. Locked is deliberately not green:
    /// it *is* on, but it is no longer responding to being tilted, and that difference is the
    /// whole reason the state exists.
    private var tint: Color {
        switch tilt.status {
        case .on: Palette.ok
        case .locked: Palette.foreground
        case .off: Palette.muted
        case .denied, .unavailable: Palette.subtleForeground
        }
    }

    private var accessibilityLabel: String {
        switch tilt.status {
        case .off: "Tilt gravity, off"
        case .on: "Tilt gravity, following the phone"
        case .locked: "Tilt gravity, locked"
        case .denied: "Tilt gravity unavailable, motion access refused"
        case .unavailable: "Tilt gravity unavailable on this device"
        }
    }

    private var hint: String {
        switch tilt.status {
        case .off: "Tip the phone to change which way things fall"
        case .on: "Tap to hold gravity where it is"
        case .locked: "Tap to switch tilt off"
        case .denied: "Allow motion access in Settings to use this"
        case .unavailable: ""
        }
    }
}
