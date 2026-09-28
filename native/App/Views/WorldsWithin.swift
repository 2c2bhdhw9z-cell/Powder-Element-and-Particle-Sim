import CrucibleCore
import SwiftUI

/// Worlds within worlds, in the field's tray: the switch that makes the next tap on a body go inside it.
struct FieldWithinControls: View {
    let model: ParticleFieldModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WORLDS WITHIN")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            if model.depthEnabled {
                Text("Bodies can be gone into in a flat field. Switch 3D off to look inside one.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    Haptics.selection()
                    model.isLookingInside.toggle()
                } label: {
                    Label(
                        model.isLookingInside ? "Now tap a body on the world" : "Look inside a body",
                        systemImage: "plus.magnifyingglass"
                    )
                    .font(.labBody(12, .semiBold))
                    .foregroundStyle(model.isLookingInside ? Palette.primaryForeground : Palette.foreground)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(model.isLookingInside ? Palette.primary : Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("within.look")
                Text("Every body has a whole world inside it — a galaxy, a flock, a jellyfish — and every body in that "
                    + "world has another. The same body always holds the same world, so it can be found again.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem = model.insideProblem {
                    Text(problem)
                        .font(.labBody(10))
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Where you are, while inside a body, and the way back out.
struct WorldWithinBanner: View {
    let model: ParticleFieldModel

    var body: some View {
        if let place = model.whereInside {
            HStack(spacing: 8) {
                Image(systemName: "circle.circle")
                    .font(.labBody(12, .medium))
                    .foregroundStyle(Palette.muted)
                VStack(alignment: .leading, spacing: 0) {
                    Text(place)
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(2)
                        .accessibilityIdentifier("within.where")
                    Text("\(model.worldsOutside.count) \(model.worldsOutside.count == 1 ? "world" : "worlds") down")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                }
                Spacer(minLength: 6)
                if model.worldsOutside.count > 1 {
                    Button("All the way out") { withAnimation(.easeOut(duration: 0.2)) { model.backOutAll() } }
                        .font(.labBody(11, .medium))
                        .foregroundStyle(Palette.muted)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("within.backAll")
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { model.backOut() }
                } label: {
                    Text("Back out")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("within.back")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 460)
            .solidPanel(in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .padding(.horizontal, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// A body opening up as the world inside it arrives: a disc of its colour swelling from where it was touched to cover
/// the screen, and fading to show the world within.
struct DiveFlash: View {
    let model: ParticleFieldModel
    @State private var grown = false

    var body: some View {
        GeometryReader { space in
            if let flash = model.diveFlash {
                let colour = Color(hue: flash.hue / 360, saturation: 0.6, brightness: 0.8)
                Circle()
                    .fill(colour)
                    .frame(width: 24, height: 24)
                    .scaleEffect(grown ? max(space.size.width, space.size.height) / 8 : 1)
                    .opacity(grown ? 0 : 0.9)
                    .position(x: flash.x * space.size.width, y: flash.y * space.size.height)
                    .task(id: flash.id) {
                        // Small again first, then a frame later swelling, so a second dive starts from the finger
                        // rather than already grown.
                        grown = false
                        // Held still for somebody who has asked for less motion: the world simply changes.
                        guard !LabMotion.isReduced else {
                            grown = true
                            return
                        }
                        try? await Task.sleep(for: .milliseconds(16))
                        withAnimation(.easeIn(duration: 0.45)) { grown = true }
                    }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
