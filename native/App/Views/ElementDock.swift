import CrucibleCore
import SwiftUI

/// The dock along the bottom: what you are painting with, how big, and what to do next.
///
/// Laid out like the web version — a drag handle, a title line that doubles as the open and
/// close control, and a body that slides up. Collapsed it shows only what you need while
/// drawing; opened it shows the full element set and the world's settings.
struct ElementDock: View {
    let model: SimulationModel
    let glass: GlassLevel
    @Binding var isOpen: Bool
    let onShowScenes: () -> Void
    let onShowSettings: () -> Void

    /// Elements grouped the way someone reaching for one would look for them, rather than by
    /// internal identifier.
    private static let groups: [(name: String, items: [(id: ElementID, name: String)])] = [
        ("Powders", [
            (Element.sand, "Sand"), (Element.dirt, "Dirt"), (Element.salt, "Salt"),
            (Element.snow, "Snow"), (Element.coal, "Coal"), (Element.gunpowder, "Gunpowder"),
            (Element.thermite, "Thermite"), (Element.seed, "Seed"),
        ]),
        ("Liquids", [
            (Element.water, "Water"), (Element.oil, "Oil"), (Element.acid, "Acid"),
            (Element.lava, "Lava"), (Element.honey, "Honey"), (Element.mercury, "Mercury"),
            (Element.mud, "Mud"), (Element.nitro, "Nitro"), (Element.wetMix, "Wet mix"),
        ]),
        ("Solids", [
            (Element.stone, "Stone"), (Element.wood, "Wood"), (Element.metal, "Metal"),
            (Element.copper, "Copper"), (Element.glass, "Glass"), (Element.ice, "Ice"),
            (Element.rubber, "Rubber"), (Element.wax, "Wax"), (Element.concrete, "Concrete"),
            (Element.obsidian, "Obsidian"), (Element.bedrock, "Bedrock"),
        ]),
        ("Energy", [
            (Element.fire, "Fire"), (Element.spark, "Spark"), (Element.plasma, "Plasma"),
            (Element.laser, "Laser"), (Element.fuseWire, "Fuse"), (Element.c4, "C4"),
        ]),
        ("Gases", [
            (Element.smoke, "Smoke"), (Element.steam, "Steam"), (Element.oxygen, "Oxygen"),
            (Element.hydrogen, "Hydrogen"), (Element.helium, "Helium"),
        ]),
        ("Life & odd", [
            (Element.plant, "Plant"), (Element.ant, "Ant"), (Element.virus, "Virus"),
            (Element.clone, "Clone"), (Element.void, "Void"), (Element.fan, "Fan"),
            (Element.portalA, "Portal A"), (Element.portalB, "Portal B"),
            (Element.antiGravityPowder, "Anti-gravity"),
        ]),
    ]

    /// The handful most reached for, shown while the dock is closed.
    private static let favourites: [(id: ElementID, name: String)] = [
        (Element.sand, "Sand"), (Element.water, "Water"), (Element.lava, "Lava"),
        (Element.fire, "Fire"), (Element.stone, "Stone"), (Element.wood, "Wood"),
        (Element.oil, "Oil"), (Element.acid, "Acid"), (Element.ice, "Ice"),
        (Element.plant, "Plant"), (Element.c4, "C4"), (Element.spark, "Spark"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            if isOpen { expanded }
            collapsedStrip
            transport
        }
        .background(alignment: .top) {
            // A hairline along the top edge and a shadow beneath it, so the dock reads as
            // sitting in front of the simulation rather than printed on it.
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
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
        // A downward drag closes it and an upward drag opens it, which is what the handle
        // looks like it should do.
        .highPriorityGesture(
            DragGesture(minimumDistance: 18).onEnded { value in
                withAnimation(.easeOut(duration: 0.22)) {
                    isOpen = value.translation.height < 0
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.name(of: model.brushElement))
                    .font(.labDisplay(15))
                    .foregroundStyle(Palette.foreground)
                Text("\(model.ticksPerSecond) fps · \(model.activeCells.formatted()) cells")
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            iconButton("square.grid.2x2", "Scenes", action: onShowScenes)
            iconButton("slider.horizontal.3", "Settings", action: onShowSettings)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// The full set, only while the dock is open.
    private var expanded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Palette.subtleForeground)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 84), spacing: 6)],
                            spacing: 6
                        ) {
                            ForEach(group.items, id: \.id) { item in
                                chip(item.id, item.name, wide: true)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 280)
    }

    /// The favourites row, always visible.
    private var collapsedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.favourites, id: \.id) { item in
                    chip(item.id, item.name, wide: false)
                }
                chip(Element.empty, "Erase", wide: false)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.primaryForeground)
                    .frame(width: 44, height: 36)
                    .background(Palette.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isRunning ? "Pause" : "Play")

            // Brush size. A slider rather than stepped buttons: it is the control reached for
            // most often while drawing, and the size wants to be felt rather than counted.
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.subtleForeground)
                Slider(
                    value: Binding(
                        get: { Double(model.brushRadius) },
                        set: { model.brushRadius = Int($0.rounded()) }
                    ),
                    in: 1 ... 28
                )
                .tint(Palette.primary)
                Text("\(model.brushRadius)")
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 20, alignment: .trailing)
            }
            .accessibilityLabel("Brush size")

            iconButton("trash", "Clear") { model.clear() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func chip(_ id: ElementID, _ name: String, wide: Bool) -> some View {
        let selected = model.brushElement == id
        return Button {
            model.brushElement = id
        } label: {
            HStack(spacing: 6) {
                // The element's own colour, so the row can be read by eye before the labels
                // are read at all.
                Circle()
                    .fill(model.color(of: id))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                Text(name)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: wide ? .infinity : nil, alignment: .leading)
            .background(
                Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        _ symbol: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 40, height: 36)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private static func name(of id: ElementID) -> String {
        if id == Element.empty { return "Erase" }
        for group in groups {
            if let match = group.items.first(where: { $0.id == id }) { return match.name }
        }
        return "Element \(id)"
    }
}
