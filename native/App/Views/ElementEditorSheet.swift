import CrucibleCore
import SwiftUI

/// Inventing a material.
///
/// Fifty slots exist for these, numbered 50 to 99, and the engine has always supported them — it
/// registers them, simulates them, saves them and loads them. There was simply no way to make one.
///
/// ## What is deliberately not offered
///
/// The engine understands far more about a material than this asks for: viscosity, burn rate, acid
/// resistance, heat conductivity, self-ignition temperature, what it decays into. Exposing all of it
/// would make this a form of twenty fields, and the web version chose six for a reason — those six
/// are the ones whose effect you can see immediately. The rest keep sensible defaults, and the
/// starting points below are there for anyone who wants something more interesting than a coloured
/// powder.
struct ElementEditorSheet: View {
    let model: SimulationModel
    /// Called after the set of materials changes, so the palette redraws.
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colour = Color(red: 0.78, green: 0.8, blue: 0.83)
    @State private var state: ElementState = .solidMovable
    @State private var density = 15.0
    @State private var flammability = 0.0
    @State private var gravity = 1.0

    /// The optional "when this touches that" rule.
    @State private var reactsWith: ElementID = Element.water
    @State private var reactionChance = 0.0
    @State private var becomes: ElementID = Element.empty

    @State private var problem: String?

    /// The materials someone can react against: the built-ins, which are the ones everyone has.
    private var builtIns: [ElementDefinition] {
        model.builtInElements.filter { $0.id != Element.empty }
    }

    private var mine: [ElementDefinition] {
        model.customElements.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                starters
                basics
                behaviour
                reaction
                save
                existing
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Invent a material")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.background)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    /// Three worked examples, carried over from the web version.
    ///
    /// Not templates so much as an answer to "what can these actually do" — each one uses the
    /// reaction rule, which is the part nobody would think to try from an empty form.
    private var starters: some View {
        Section {
            HStack(spacing: 8) {
                starter("Goo", .init(red: 0.525, green: 0.937, blue: 0.675)) {
                    name = "Goo"
                    colour = Color(red: 0.525, green: 0.937, blue: 0.675)
                    state = .liquid
                    density = 9
                    flammability = 0
                    gravity = 1
                    reactsWith = Element.water
                    reactionChance = 0.2
                    becomes = Element.plant
                }
                starter("Foam", .init(red: 0.906, green: 0.898, blue: 0.894)) {
                    name = "Foam"
                    colour = Color(red: 0.906, green: 0.898, blue: 0.894)
                    state = .gas
                    density = 2
                    flammability = 10
                    gravity = -0.2
                    reactsWith = Element.fire
                    reactionChance = 0.5
                    becomes = Element.smoke
                }
                starter("Slag", .init(red: 0.471, green: 0.443, blue: 0.424)) {
                    name = "Slag"
                    colour = Color(red: 0.471, green: 0.443, blue: 0.424)
                    state = .solidMovable
                    density = 22
                    flammability = 0
                    gravity = 1
                    reactsWith = Element.lava
                    reactionChance = 0.35
                    becomes = Element.stone
                }
            }
        } header: {
            Text("Start from")
        } footer: {
            Text("Each of these fills the form in. Change anything you like before keeping it.")
                .font(.labBody(11))
        }
    }

    private var basics: some View {
        Section {
            TextField("Name", text: $name)
                .font(.labBody(14))
            ColorPicker("Colour", selection: $colour, supportsOpacity: false)
            Picker("Behaves like", selection: $state) {
                Text("Powder").tag(ElementState.solidMovable)
                Text("Solid").tag(ElementState.solidFixed)
                Text("Liquid").tag(ElementState.liquid)
                Text("Gas").tag(ElementState.gas)
                Text("Plasma").tag(ElementState.plasma)
            }
        } header: {
            Text("What it is")
        }
    }

    private var behaviour: some View {
        Section {
            labelledSlider("Heaviness", value: $density, range: 0 ... 60, step: 1) {
                $0.formatted(.number.precision(.fractionLength(0)))
            }
            labelledSlider("Catches fire", value: $flammability, range: 0 ... 100, step: 1) {
                $0 == 0 ? "never" : "\($0.formatted(.number.precision(.fractionLength(0))))/100"
            }
            labelledSlider("Falls", value: $gravity, range: -1 ... 2, step: 0.1) {
                if $0 == 0 { return "floats in place" }
                return $0 < 0 ? "upward" : "\($0.formatted(.number.precision(.fractionLength(1))))×"
            }
        } header: {
            Text("How it behaves")
        } footer: {
            Text("Heaviness decides what sinks through what. Water is 10, stone is 40.")
                .font(.labBody(11))
        }
    }

    private var reaction: some View {
        Section {
            Picker("When it touches", selection: $reactsWith) {
                ForEach(builtIns, id: \.id) { element in
                    Text(element.name).tag(element.id)
                }
            }
            labelledSlider("How often", value: $reactionChance, range: 0 ... 1, step: 0.05) {
                $0 == 0 ? "never" : "\(($0 * 100).formatted(.number.precision(.fractionLength(0))))%"
            }
            Picker("It becomes", selection: $becomes) {
                Text("nothing").tag(Element.empty)
                ForEach(builtIns, id: \.id) { element in
                    Text(element.name).tag(element.id)
                }
            }
            .disabled(reactionChance == 0)
        } header: {
            Text("A reaction, if you want one")
        } footer: {
            Text(
                reactionChance == 0
                    ? "Leave this at never and the material simply sits there being itself."
                    : "Each moment they are touching, there is a chance your material turns into "
                        + "the thing below."
            )
            .font(.labBody(11))
        }
    }

    private var save: some View {
        Section {
            Button {
                keep()
            } label: {
                Label("Keep this material", systemImage: "plus.circle")
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        } footer: {
            if let problem {
                Text(problem)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.danger)
            } else {
                Text("\(model.freeCustomSlots) of 50 slots left.")
                    .font(.labBody(11))
            }
        }
    }

    @ViewBuilder
    private var existing: some View {
        Section {
            if mine.isEmpty {
                Text("You have not invented anything yet.")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
            } else {
                ForEach(mine, id: \.id) { element in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(model.color(of: element.id))
                            .frame(width: 12, height: 12)
                        Text(element.name)
                            .foregroundStyle(Palette.foreground)
                        Spacer()
                        Text("slot \(element.id)")
                            .font(.labNumeric(10))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.deleteCustomElement(element.id)
                            onChange()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Yours")
        } footer: {
            Text(
                "Deleting one does not remove it from a world already holding it — those cells stay "
                    + "put and behave as air until something moves them."
            )
            .font(.labBody(11))
        }
    }

    // MARK: Doing it

    private func keep() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var rules: [InteractionRule] = []
        if reactionChance > 0 {
            rules.append(
                InteractionRule(
                    targetElementID: reactsWith,
                    chance: reactionChance,
                    // What *this* material becomes. Nothing happens to the other one, which is what
                    // the web version's editor offers and is the easier idea to hold.
                    resultSelfID: becomes
                )
            )
        }

        let created = model.createCustomElement(
            name: trimmed,
            color: Self.packed(colour),
            state: state,
            density: density,
            flammability: flammability,
            gravityFactor: gravity,
            interactions: rules
        )

        guard let created else {
            problem = "All fifty slots are full. Delete one below to make room."
            return
        }

        problem = nil
        onChange()
        // Selected straight away, so keeping a material and then painting with it is one gesture
        // rather than a hunt through the palette for the thing you just made.
        model.brushElement = created
        dismiss()
    }

    /// Turns a picked colour into the engine's packed form.
    ///
    /// Through the platform's own conversion rather than by reading the `Color` directly, because a
    /// `Color` can come from any colour space and the engine's is plain 8-bit sRGB.
    private static func packed(_ colour: Color) -> PackedColor {
        let resolved = UIColor(colour)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func byte(_ value: CGFloat) -> UInt8 {
            UInt8(max(0, min(255, (value * 255).rounded())))
        }
        return PackedColor(r: byte(red), g: byte(green), b: byte(blue))
    }

    // MARK: Pieces

    private func starter(_ title: String, _ swatch: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(swatch)
                    .frame(height: 22)
                Text(title)
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.foreground)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func labelledSlider(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.labNumeric(12))
                    .foregroundStyle(Palette.muted)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
        }
    }
}
