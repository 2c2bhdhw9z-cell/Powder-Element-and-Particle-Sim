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
    /// Opens the card describing one material. Handed in rather than presented here, because the
    /// dock is not a sheet and the card has to sit above everything.
    let onShowInfo: (ElementID) -> Void
    let onShowPeriodic: () -> Void
    let onShowSaves: () -> Void
    let onShowEditor: () -> Void
    /// Changes whenever a material is invented or deleted.
    ///
    /// The palette's own rows come from the registry, which is a class, so SwiftUI has no way to
    /// notice an edit inside it. This is the nudge that makes the list rebuild.
    let paletteVersion: Int

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

    /// The tray's own title row: what is selected, and a chevron.
    ///
    /// One button here, not six. The five ways into other panels used to sit along this row beside
    /// the title, which on a phone is six targets and a label fighting over about three hundred
    /// points — it read as a toolbar rather than as a heading. They have moved inside the tray,
    /// where the reference keeps them and where there is room to label them.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name(of: model.brushElement))
                    .font(.labDisplay(14))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.foreground)
                Text("\(model.activeCells.formatted()) cells")
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

    /// The ways into the other panels, inside the tray where there is room to name them.
    private var destinations: some View {
        LabFlow(spacing: 6) {
            destination("Scenes", "square.grid.2x2", action: onShowScenes)
            destination("Kept", "tray.full", action: onShowSaves)
            destination("Invent", "wand.and.stars", action: onShowEditor)
            destination("Periodic", "atom", action: onShowPeriodic)
            destination("Lab", "slider.horizontal.3", action: onShowSettings)
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

    /// The full set, only while the dock is open.
    private var expanded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                destinations
                // Invented materials first, because someone who has just made one is looking for
                // it, and the fifty built-ins are always in the same place further down.
                if !invented.isEmpty {
                    group("Yours", invented)
                }
                ForEach(Self.groups, id: \.name) { built in
                    group(built.name, built.items)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: 280)
    }

    /// The materials someone invented.
    ///
    /// Read through `paletteVersion` so that inventing or deleting one rebuilds this. The registry is
    /// a class and SwiftUI cannot see an edit inside one.
    private var invented: [(id: ElementID, name: String)] {
        _ = paletteVersion
        return model.customElements
            .sorted { $0.id < $1.id }
            .map { (id: $0.id, name: $0.name) }
    }

    /// One titled block of the palette.
    private func group(_ title: String, _ items: [(id: ElementID, name: String)]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 84), spacing: 6)],
                spacing: 6
            ) {
                ForEach(items, id: \.id) { item in
                    chip(item.id, item.name, wide: true)
                }
            }
        }
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
                    .font(.labBody(15, .semiBold))
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
                    .font(.labBody(12))
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
                    .font(.labBody(12, selected ? .semiBold : .regular))
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
        // Hold a swatch to read what the material is and what it does to the others. A long press
        // rather than a second button, because there are fifty of these and the dock has no room
        // for fifty more.
        .onLongPressGesture(minimumDuration: 0.35) {
            onShowInfo(id)
        }
        .accessibilityHint("Double tap to select. Touch and hold to read about it.")
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

    /// What to call the selected material in the dock's subtitle.
    ///
    /// Asks the registry rather than searching the fixed lists above, so an invented material shows
    /// the name someone gave it instead of "Element 50". The lists are for grouping and ordering;
    /// they are not the source of truth for a name.
    private func name(of id: ElementID) -> String {
        if id == Element.empty { return "Erase" }
        return model.definition(of: id).name
    }
}
