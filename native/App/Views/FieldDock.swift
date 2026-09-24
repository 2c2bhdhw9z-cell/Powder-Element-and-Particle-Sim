import CrucibleCore
import SwiftUI

/// The dock for the particle chamber: what your finger does, and what the field is made of.
///
/// Laid out like the powder dock so switching chambers does not move anything under your thumb,
/// but the contents are different in kind. There is nothing to paint with here — a touch applies
/// a force — so the row of things is a row of *tools* rather than of materials.
struct FieldDock: View {
    let model: ParticleFieldModel
    let glass: GlassLevel
    @Binding var isOpen: Bool
    let onShowPresets: () -> Void
    let onShowSettings: () -> Void

    /// The mouse modes, named for what they do rather than what they are called internally.
    private static let tools: [(mode: ParticleMouseMode, name: String, symbol: String)] = [
        (.attract, "Pull", "arrow.down.right.and.arrow.up.left"),
        (.repel, "Push", "arrow.up.left.and.arrow.down.right"),
        (.vortex, "Swirl", "tornado"),
        (.gravityWell, "Well", "circle.circle"),
        (.freeze, "Freeze", "snowflake"),
        (.emitter, "Emit", "sparkles"),
        (.painter, "Paint", "paintbrush.pointed"),
        (.hawk, "Hawk", "bird"),
        (.hyperDrive, "Hyper", "bolt.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if isOpen { expanded }
            toolStrip
            transport
        }
        .background(alignment: .top) {
            Rectangle().fill(Palette.border).frame(height: 1)
        }
        .glassPanel(glass, in: Rectangle())
        .shadow(color: .black.opacity(0.55), radius: 18, y: -6)
    }

    private var handle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) { isOpen.toggle() }
        } label: {
            Capsule()
                .fill(Color.white.opacity(0.45))
                .frame(width: 48, height: 5)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOpen ? "Close the tray" : "Open the tray")
        .highPriorityGesture(
            DragGesture(minimumDistance: 18).onEnded { value in
                withAnimation(.easeOut(duration: 0.22)) {
                    isOpen = value.translation.height < 0
                }
            }
        )
    }

    /// Same arrangement as the powder tray: what is selected, and a chevron. The ways into other
    /// panels live inside the tray rather than crowding the heading.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.tools.first { $0.mode == model.mouseMode }?.name ?? "Field")
                    .font(.labDisplay(14))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.foreground)
                Text("\(model.bodyCount.formatted()) bodies")
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.easeOut(duration: 0.22)) { isOpen.toggle() }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(Palette.muted)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Close the tray" : "Open the tray")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// The ways into the other panels.
    private var destinations: some View {
        LabFlow(spacing: 6) {
            destination("Presets", "square.grid.2x2", action: onShowPresets)
            destination("Field", "slider.horizontal.3", action: onShowSettings)
        }
    }

    private func destination(
        _ title: String,
        _ symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.labBody(11, .medium))
                Text(title)
                    .font(.labBody(12, .medium))
            }
            .foregroundStyle(Palette.foreground)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 14) {
            destinations
            labelledSlider(
                "Reach",
                value: Binding(get: { model.mouseRadius }, set: { model.mouseRadius = $0 }),
                range: 40 ... 820,
                // At the top of the range the physics treats the reach as unlimited, which is
                // worth saying rather than showing as a number that stops meaning anything.
                display: { model.mouseRadius >= 800 ? "whole field" : "\(Int($0))" }
            )
            labelledSlider(
                "Body size",
                value: Binding(get: { model.particleSize }, set: { model.particleSize = $0 }),
                range: 1 ... 8,
                display: { $0.formatted(.number.precision(.fractionLength(1))) }
            )
            labelledSlider(
                "Gravity",
                value: Binding(get: { model.gravityY }, set: { model.gravityY = $0 }),
                range: -1 ... 1,
                display: { $0.formatted(.number.precision(.fractionLength(2))) }
            )

            HStack(spacing: 18) {
                Toggle("Trails", isOn: Binding(
                    get: { model.showTrails },
                    set: { model.showTrails = $0 }
                ))
                Toggle("Collide", isOn: Binding(
                    get: { model.collisionsEnabled },
                    set: { model.collisionsEnabled = $0 }
                ))
            }
            .font(.labBody(12))
            .foregroundStyle(Palette.foreground)
            .tint(Palette.primary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.tools, id: \.mode) { tool in
                    let selected = model.mouseMode == tool.mode
                    Button {
                        model.mouseMode = tool.mode
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tool.symbol)
                                .font(.labBody(11))
                            Text(tool.name)
                                .font(.labBody(12, selected ? .semiBold : .regular))
                        }
                        .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 38)
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                model.isRunning.toggle()
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.labBody(15, .semiBold))
                    .foregroundStyle(Palette.primaryForeground)
                    .frame(width: 44, height: 36)
                    .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isRunning ? "Pause" : "Play")

            Picker("Colour by", selection: Binding(
                get: { model.colorMode },
                set: { model.colorMode = $0 }
            )) {
                Text("Own").tag(ParticleColorMode.native)
                Text("Speed").tag(ParticleColorMode.velocity)
                Text("Charge").tag(ParticleColorMode.charge)
                Text("Place").tag(ParticleColorMode.rainbow)
                Text("Crowd").tag(ParticleColorMode.density)
                Text("Life").tag(ParticleColorMode.lifespan)
            }
            .pickerStyle(.menu)
            .tint(Palette.muted)
            .font(.labBody(12))

            Spacer(minLength: 0)

            iconButton("trash", "Clear") { model.clear() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func labelledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        display: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.labBody(12))
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text(display(value.wrappedValue))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            Slider(value: value, in: range)
                .tint(Palette.primary)
        }
    }

    private func iconButton(
        _ symbol: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.labBody(14, .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 40, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Picks one of the field presets.
struct FieldPresetPicker: View {
    let glass: GlassLevel
    let onSelect: (String) -> Void

    var body: some View {
        LabSheet(
            title: "Presets",
            subtitle: "Arrangements to start from",
            glass: glass
        ) {
            LabGroup(footnote: "Loading a preset replaces the field. Undo brings it back.") {
                LabFlow(spacing: 6) {
                    ForEach(ParticleFieldModel.presets, id: \.id) { preset in
                        Button { onSelect(preset.id) } label: {
                            Text(preset.name)
                                .font(.labBody(12, .medium))
                                .foregroundStyle(Palette.foreground)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
    }
}
