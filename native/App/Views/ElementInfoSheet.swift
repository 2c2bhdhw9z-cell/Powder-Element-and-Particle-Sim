import CrucibleCore
import SwiftUI

/// An element identifier, made presentable as a sheet.
///
/// SwiftUI's item-based sheet wants something identifiable and an element id is a bare number.
/// Wrapping it keeps the property a plain boolean flag would lose: the card cannot be shown
/// without also saying which material it is describing.
struct ElementInfoTarget: Identifiable {
    let id: ElementID
}

/// What one material is, and what it does to the others.
///
/// Reached by holding down a swatch in the dock. The web version opens the same card from a
/// long-press or from the inspect chip above the canvas.
///
/// The text is not written here — it is generated from the reference implementation and checked
/// against it, so the two say the same thing. See `Encyclopedia.swift`.
struct ElementInfoSheet: View {
    let model: SimulationModel
    let elementID: ElementID

    private var definition: ElementDefinition {
        model.definition(of: elementID)
    }

    private var lore: ElementLore {
        Encyclopedia.lore(for: elementID)
    }

    var body: some View {
        LabSheet(title: definition.name, subtitle: definition.category.rawValue) {
            heading
            description
            facts
            prose
        }
    }

    private var heading: some View {
        HStack(spacing: 12) {
            // The colour taken from the same table the canvas draws from, so a swatch can never
            // disagree with what the material actually looks like.
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(model.color(of: elementID))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .strokeBorder(Palette.border)
                )
            Text(Self.stateName(definition.state))
                .font(.labBody(12))
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var description: some View {
        if !definition.info.isEmpty {
            Text(definition.info)
                .font(.labBody(14))
                .foregroundStyle(Palette.foreground)
        }
    }

    /// The numbers, in a two-column list.
    private var facts: some View {
        VStack(spacing: 0) {
            fact("Heaviness", definition.density.formatted(.number.precision(.fractionLength(0 ... 1))))
            if let melt = lore.melt { fact("Melts", melt) }
            if let boil = lore.boil { fact("Boils", boil) }
            if definition.flammability > 0 {
                fact("Catches fire", "\(definition.flammability.formatted(.number.precision(.fractionLength(0))))/100")
            }
            if definition.isConductor { fact("Carries a spark", "yes") }
            if definition.decayTicks > 0 {
                fact("Lasts", "\(definition.decayTicks) moments")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var prose: some View {
        VStack(alignment: .leading, spacing: 14) {
            paragraph("What it does", lore.eats)
            paragraph("Worth knowing", lore.note)
        }
    }

    private func paragraph(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.labBody(11, .semiBold))
                .foregroundStyle(Palette.subtleForeground)
                .textCase(.uppercase)
            Text(body)
                .font(.labBody(14))
                .foregroundStyle(Palette.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.labBody(13))
                .foregroundStyle(Palette.muted)
            Spacer()
            Text(value)
                .font(.labNumeric(13))
                .foregroundStyle(Palette.foreground)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
                .padding(.horizontal, 14)
        }
    }

    /// The state, in words rather than as the identifier the engine uses.
    private static func stateName(_ state: ElementState) -> String {
        switch state {
        case .solidFixed: "Solid — stays where it is put"
        case .solidMovable: "Powder — falls and piles up"
        case .liquid: "Liquid — flows and finds its level"
        case .gas: "Gas — rises and drifts"
        case .plasma: "Plasma — searingly hot"
        // Not states of matter at all. Sparks and lasers travel rather than sit, and the special
        // ones — portals, cloners, the void — are machinery wearing the shape of a material.
        case .energy: "Energy — travels through things"
        case .special: "Special — behaves by its own rules"
        }
    }
}

/// The periodic drawer: real substances mapped onto what the lab can simulate.
///
/// The premise is stated plainly to the reader rather than hidden, because the mapping is lossy on
/// purpose — seven different metals all become "metal", which is honest rather than pretending to a
/// distinction the physics does not make.
struct PeriodicSheet: View {
    let model: SimulationModel
    let onPick: (ElementID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        LabSheet(
            title: "Periodic",
            subtitle: "Real substances, mapped onto what the lab can simulate"
        ) {
            section("Elements", PeriodicTable.elements)
            section("Compounds", PeriodicTable.compounds)
        }
    }

    private func section(_ title: String, _ entries: [PeriodicEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(entries) { entry in
                    Button {
                        onPick(entry.mapsTo)
                    } label: {
                        cell(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cell(_ entry: PeriodicEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(entry.symbol)
                    // Monospaced, because the compounds' subscript digits sit correctly in it and
                    // the symbols line up down the grid.
                    .font(.labNumeric(17))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 0)
                if !entry.isCompound {
                    Text("\(entry.atomicNumber)")
                        .font(.labNumeric(9))
                        .foregroundStyle(Palette.subtleForeground)
                }
            }
            Text(entry.name)
                .font(.labBody(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            HStack(spacing: 4) {
                Circle()
                    .fill(model.color(of: entry.mapsTo))
                    .frame(width: 7, height: 7)
                Text(model.definition(of: entry.mapsTo).name)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .accessibilityLabel("\(entry.name), becomes \(model.definition(of: entry.mapsTo).name)")
        .accessibilityHint(entry.why)
    }
}
