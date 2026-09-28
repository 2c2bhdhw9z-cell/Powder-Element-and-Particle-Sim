import CrucibleCore
import SwiftUI

/// The dock for the particle chamber: what your finger does, and what the field is made of.
///
/// Laid out like the powder dock so switching chambers does not move anything under your thumb,
/// but the contents are different in kind. There is nothing to paint with here — a touch applies
/// a force — so the row of things is a row of *tools* rather than of materials.
struct FieldDock: View {
    /// The compact dock stays in the screen layout. The expanded tray is drawn over the world's bottom edge by
    /// ContentView, so it keeps the original appearance without the crash-prone inverted dock alignment guide.
    enum Presentation {
        case dock
        case tray
        /// The list menu: a short list of parts, and one part's controls at a time.
        case menu
    }

    /// Where the choice between the one scrolling tray and the list menu is kept. Shared with ContentView.
    static let listMenuKey = "fieldControlsUseListMenu"

    /// A Field menu used to insert every control into one enormous overlay above the dock. That path still terminated
    /// a real iPhone after lighter animation and lazy layout were tried. The replacement opens this static list first
    /// and constructs exactly one control page only after it is chosen.
    private enum MenuPage: String, CaseIterable {
        case arrangements
        case morph
        case formula
        case layers
        case words
        case creatures
        case worlds
        case bodies
        case touch
        case physics
        case threeD
        case view
        case appearance
        case movie
        case actions

        var title: String {
            switch self {
            case .arrangements: "Arrangements"
            case .morph: "Morph between shapes"
            case .formula: "Shape from a formula"
            case .layers: "Layers"
            case .words: "Words"
            case .creatures: "Creatures"
            case .worlds: "Worlds within worlds"
            case .bodies: "Bodies and population"
            case .touch: "Fingers and loops"
            case .physics: "Physics"
            case .threeD: "3D"
            case .view: "View and camera"
            case .appearance: "Colour and appearance"
            case .movie: "Movie and keepsakes"
            case .actions: "More actions"
            }
        }

        var detail: String {
            switch self {
            case .arrangements: "Ready-made fields and today's shared shape"
            case .morph: "Turn one arrangement into another"
            case .formula: "Make a living shape from equations"
            case .layers: "Separate, hide, lock and colour parts"
            case .words: "Spell with bodies"
            case .creatures: "Build bones, joints and muscles"
            case .worlds: "Look inside a body"
            case .bodies: "Add bodies, set their size and reach"
            case .touch: "More fingers, repeating gestures and show mode"
            case .physics: "Collisions, trails, fluids, forces and wind"
            case .threeD: "Turn the field into a box and look around it"
            case .view: "Detail, tilt, spin and fit"
            case .appearance: "Palettes, shapes, backdrops and glow"
            case .movie: "Camera stops, clips, 3D moments and Live Photos"
            case .actions: "Presets, bridges, wells and Field settings"
            }
        }

        var symbol: String {
            switch self {
            case .arrangements: "square.grid.2x2"
            case .morph: "arrow.triangle.2.circlepath"
            case .formula: "function"
            case .layers: "square.3.layers.3d"
            case .words: "textformat"
            case .creatures: "figure.walk"
            case .worlds: "circle.circle"
            case .bodies: "circle.hexagongrid"
            case .touch: "hand.draw"
            case .physics: "atom"
            case .threeD: "cube"
            case .view: "viewfinder"
            case .appearance: "paintpalette"
            case .movie: "film"
            case .actions: "ellipsis.circle"
            }
        }
    }


    let model: ParticleFieldModel
    @Binding var isOpen: Bool
    @Binding private var batch: Int
    let presentation: Presentation
    let onShowPresets: () -> Void
    let onShowSettings: () -> Void
    /// Today's date in UTC, for the shared daily arrangement.
    let today: String
    /// Pours the whole field into the powder world.
    let onSettleEverything: () -> Void
    /// Shows the powder world in the box, as a slab to turn round.
    let onShowPowderInTheBox: () -> Void

    init(
        model: ParticleFieldModel,
        isOpen: Binding<Bool>,
        batch: Binding<Int>,
        presentation: Presentation = .dock,
        onShowPresets: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        today: String,
        onSettleEverything: @escaping () -> Void,
        onShowPowderInTheBox: @escaping () -> Void
    ) {
        self.model = model
        _isOpen = isOpen
        _batch = batch
        self.presentation = presentation
        self.onShowPresets = onShowPresets
        self.onShowSettings = onShowSettings
        self.today = today
        self.onSettleEverything = onSettleEverything
        self.onShowPowderInTheBox = onShowPowderInTheBox
    }

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
        // The two that change the world rather than pushing the bodies. Last, because they are a different
        // kind of thing and grouping them apart is the only hint the strip can give about that.
        (.current, "Wind", "wind"),
        (.wall, "Wall", "line.diagonal"),
        // Draws a ribbon that stays. With the other two that change the world rather than pushing the bodies.
        (.light, "Light", "scribble"),
        (.source, "Source", "drop.circle"),
        // Two that make something: a body thrown, and a jelly drawn. Flat things, so not offered in 3D.
        (.slingshot, "Throw", "scope"),
        (.jelly, "Jelly", "circle.hexagongrid"),
    ]

    /// The tools that only make sense on a flat field.
    private static let flatOnly: Set<ParticleMouseMode> = [.slingshot, .jelly]

    /// The top-to-bottom order of the original single scrolling tray. Supplying these through a `ForEach` gives the
    /// lazy stack real rows to request as they approach the screen, instead of one giant result-builder expression.
    private enum ExpandedSection: CaseIterable, Hashable {
        case style
        case destinations
        case cost
        case depth
        case fingers
        case loops
        case arrangements
        case morph
        case formula
        case layers
        case arrangementDetails
        case word
        case creatures
        case worldsWithin
        case bodyControls
        case physics
        case colourModes
        case colourRamps
        case shapes
        case backdrop
        case view
        case movie
    }

    /// Opens the unusually large Field tray without animating its insertion. On real phones, animating the
    /// complete control tree can briefly require enough layout and accessibility work to terminate the app.
    /// Closing is cheap because the tree has already been laid out, so it can keep the familiar movement.
    /// The one control page the list menu has built, or nil for its list of parts.
    @State private var selectedPage: MenuPage? = nil

    /// Whether the Field's controls open as the list menu (true) or as the one scrolling tray (false).
    @AppStorage(FieldDock.listMenuKey) private var usesListMenu = true

    private func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        if open {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { isOpen = true }
        } else {
            withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
        }
    }

    private func toggleOpen() {
        setOpen(!isOpen)
    }

    @ViewBuilder
    var body: some View {
        switch presentation {
        case .dock:
            compactDock
        case .tray:
            expanded
                .solidPanel(in: Rectangle())
        case .menu:
            menu
        }
    }

    private var compactDock: some View {
        VStack(spacing: 0) {
            handle
            header
            toolStrip
            transport
        }
        .background(alignment: .top) {
            Rectangle().fill(Palette.border).frame(height: 1)
        }
        // No soft shadow under it any more. A shadow of that size is a blur pass of its own — the
        // compositor filtering a band of the screen every frame — and the hairline above already says the
        // dock is in front of the world rather than printed on it.
        .solidPanel(in: Rectangle())
    }

    private var handle: some View {
        Button {
            Haptics.selection()
            toggleOpen()
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
        .accessibilityIdentifier("fieldTray.handle")
        .highPriorityGesture(
            DragGesture(minimumDistance: 18).onEnded { value in
                setOpen(value.translation.height < 0)
            }
        )
    }

    /// Whether one finger is turning the view round the box rather than working the field.
    private var isTurning: Bool {
        model.depthEnabled && model.turnsView
    }

    /// Whether the lens has the finger.
    private var isLooking: Bool { model.usesLens }

    /// What a finger does now, in a word.
    private var toolName: String {
        if isLooking { return "Look" }
        if isTurning { return "Turn" }
        return Self.tools.first(where: { $0.mode == model.mouseMode })?.name ?? "Field"
    }

    /// Same arrangement as the powder tray: what is selected, and a chevron. The ways into other
    /// panels live inside the tray rather than crowding the heading.
    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(toolName)
                    .font(.labDisplay(14))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.foreground)
                // What the field is showing, as well as how many bodies, so the arrangement that is lit in the
                // tray is also named where it can be seen with the tray shut.
                Text(
                    model.arrangementDetails.map { "\($0.name) · \(model.bodyCount.formatted()) bodies" }
                        ?? "\(model.bodyCount.formatted()) bodies"
                )
                .font(.labNumeric(11))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 3D on and off, where it can be reached with the tray shut. Everything about how the box is looked
            // at is in the tray, under the same switch.
            Button {
                Haptics.firm()
                model.depthEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                        .font(.labBody(11, .medium))
                    Text("3D")
                        .font(.labBody(12, .semiBold))
                }
                .foregroundStyle(model.depthEnabled ? Palette.primaryForeground : Palette.foreground)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule().fill(model.depthEnabled ? Palette.primary : Color.white.opacity(0.10))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("3D")
            .accessibilityValue(model.depthEnabled ? "On" : "Off")
            .accessibilityAddTraits(model.depthEnabled ? [.isSelected] : [])

            Button {
                toggleOpen()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(Palette.muted)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Close the tray" : "Open the tray")
            .accessibilityIdentifier("fieldTray.arrow")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// Which addition chip is lit for a moment, having just been pressed.
    @State private var flashing: String?
    /// Only the first small group is even offered to SwiftUI when the tray opens. More rows are appended as the
    /// bottom approaches, preserving one continuous list without one opening tap constructing the whole laboratory.
    @State private var expandedSectionLimit = 5

    /// Lights a chip briefly, for a button that adds something rather than choosing it.
    ///
    /// A scene stays lit for as long as it is what the field is showing. An addition — a burst, a well —
    /// is not a thing the field *becomes*, so it cannot stay lit, but a press that shows nothing at all is
    /// indistinguishable from a press that did nothing. So it lights up and fades.
    private func flash(_ id: String) {
        withAnimation(.easeOut(duration: 0.08)) { flashing = id }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard flashing == id else { return }
            withAnimation(.easeOut(duration: 0.35)) { flashing = nil }
        }
    }

    /// One chip, lit when it is chosen.
    private func chip(
        _ title: String,
        symbol: String? = nil,
        lit: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.labBody(11, .medium))
                }
                Text(title)
                    .font(.labBody(12, lit ? .semiBold : .medium))
            }
            .foregroundStyle(lit ? Palette.primaryForeground : Palette.foreground)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Capsule().fill(lit ? Palette.primary : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(lit ? [.isSelected] : [])
    }

    /// Every arrangement, as chips rather than only inside a sheet.
    ///
    /// They are the quickest thing in the chamber to want and the reference keeps them here, one tap
    /// away, rather than behind a panel. The sheet stays as well — it has room to explain them.
    ///
    /// The one showing is lit, and stays lit until something else is chosen or the field is cleared. They
    /// used to look identical whether chosen or not, so there was no way to tell what the field was meant
    /// to be doing — which matters more now that adding bodies can join it.
    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ARRANGEMENTS")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                chip("Today", symbol: "sun.max", lit: model.isShowingToday) {
                    Haptics.firm()
                    model.loadDailyArrangement(day: today)
                }

                ForEach(ParticleFieldModel.presets, id: \.id) { preset in
                    let isAddition = preset.kind == .addition
                    // The ones that only exist in 3D carry a cube, since choosing one on a flat field turns 3D on.
                    chip(
                        preset.name,
                        symbol: isAddition ? "plus" : (preset.depth == .only ? "cube" : nil),
                        lit: isAddition ? flashing == preset.id : model.arrangement == preset.id
                    ) {
                        if isAddition {
                            Haptics.tap()
                            flash(preset.id)
                        } else {
                            Haptics.firm()
                        }
                        model.loadPreset(preset.id)
                    }
                    .accessibilityIdentifier("arrangement.\(preset.id)")
                }
            }
            // Only for the one scene it belongs to, so it is not a button that does nothing almost all the time.
            if model.isParticleLife {
                HStack(spacing: 8) {
                    Button {
                        Haptics.firm()
                        model.shuffleParticleLife()
                    } label: {
                        Label("Shuffle their feelings", systemImage: "shuffle")
                            .font(.labBody(12, .semiBold))
                            .foregroundStyle(Palette.primaryForeground)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(Palette.primary))
                    }
                    .buttonStyle(.plain)
                    Text("A new table of likes and dislikes — the same bodies become a different creature.")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.isDrum {
                HStack(spacing: 8) {
                    Button {
                        Haptics.firm()
                        model.nextDrumNote()
                    } label: {
                        Label("Next note", systemImage: "music.note")
                            .font(.labBody(12, .semiBold))
                            .foregroundStyle(Palette.primaryForeground)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Capsule().fill(Palette.primary))
                    }
                    .buttonStyle(.plain)
                    Text("Ringing in \(model.drumNoteName). With Listen on, the music picks the note and loudness "
                        + "is how hard the plate rings.")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var arrangementDescription: some View {
        if let details = model.arrangementDetails {
            Text(details.about(inDepth: model.depthEnabled))
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Recording a finger movement to play back for ever.
    private var loopControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOOPS")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                chip(
                    model.isRecordingLoop ? "Recording — lift to keep" : "Record a loop",
                    symbol: model.isRecordingLoop ? "record.circle.fill" : "record.circle",
                    lit: model.isRecordingLoop
                ) {
                    Haptics.firm()
                    model.toggleLoopRecording()
                }
                .disabled(!model.toolCanLoop && !model.isRecordingLoop)
                .opacity(model.toolCanLoop || model.isRecordingLoop ? 1 : 0.4)
                if model.loopCount > 0 {
                    chip("Take back the last", symbol: "arrow.uturn.backward", lit: false) {
                        Haptics.tap()
                        model.removeLastLoop()
                    }
                    chip("Stop all \(model.loopCount)", symbol: "stop.circle", lit: false) {
                        Haptics.tap()
                        model.clearLoops()
                    }
                }
            }
            Text(model.toolCanLoop || model.isRecordingLoop
                ? "Press record, then make the movement once. It repeats by itself with the tool it was made "
                    + "with — a stirrer, a heartbeat, a wave machine — until stopped. Up to six at once."
                : "Loops are made of a tool that pushes, turns, holds or paints. Choose one of those to record.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Turning one arrangement into another with a slider.
    private var morphControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Morph")
                    .font(.labBody(11, .semiBold))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 8)
                Button {
                    Haptics.firm()
                    model.startMorph()
                } label: {
                    Text(model.isMorphing ? "Again" : "Start")
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
            }
            Text("Pick two and slide between them. Everything stays touchable on the way: push the halfway shape "
                + "about and it finds its way back to wherever the slider is.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                morphPicker("From", selection: Binding(get: { model.morphFrom }, set: { model.morphFrom = $0 }))
                morphPicker("To", selection: Binding(get: { model.morphTo }, set: { model.morphTo = $0 }))
            }

            if model.isMorphing {
                inlineSlider(
                    "How far across",
                    \.morphAt,
                    0 ... 1,
                    step: 0.01,
                    format: { $0 < 0.01 ? "the first" : ($0 > 0.99 ? "the second" : "\(Int(($0 * 100).rounded()))%") }
                )
            }
        }
    }

    /// A shape described by a formula, with the knobs the shape itself asks for.
    ///
    /// The sliders are built from what the recipe declares rather than written out here, which is the whole point of
    /// the feature: a rose's petal count and a knot's number of turns are not one slider with two labels. A fixed set
    /// of sliders could not be right for both, so the recipe says what it wants and this draws it.
    private var recipeControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Shape from a formula")
                    .font(.labBody(11, .semiBold))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 8)
                Button {
                    Haptics.firm()
                    model.makeRecipe()
                } label: {
                    Text("Make")
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recipe.make")
            }

            Menu {
                ForEach(ParticleRecipe.built, id: \.title) { recipe in
                    Button(recipe.title) { model.chooseRecipe(recipe.title) }
                        .accessibilityIdentifier("recipe.choice.\(recipe.title)")
                }
            } label: {
                Text(model.recipeDraft.title)
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
            .accessibilityIdentifier("recipe.pick")

            if !model.recipeDraft.about.isEmpty {
                Text(model.recipeDraft.about)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The recipe's own knobs. A counting knob's slider clicks whole numbers; a smooth one does not.
            ForEach(model.recipeDraft.knobs, id: \.symbol) { knob in
                inlineSlider(
                    knob.name,
                    Binding(
                        get: { model.recipeKnobValue(knob.symbol) },
                        set: { model.turnRecipeKnob(knob.symbol, to: $0) }
                    ),
                    knob.low ... knob.high,
                    step: knob.step > 0 ? knob.step : (knob.high - knob.low) / 100,
                    format: {
                        knob.step >= 1
                            ? "\(Int($0.rounded()))"
                            : $0.formatted(.number.precision(.fractionLength(2)))
                    }
                )
            }

            if let problem = model.recipeProblem {
                Text(problem)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(model.recipe == nil
                    ? "A shape written down rather than drawn. Press Make and the bodies go and be it."
                    : "Shove it about and it pulls itself back together. Move a slider and it becomes a "
                        + "different shape, still shovable the whole way.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Several worlds in one world: named groups with their own colour and rules.
    private var layerControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Layers")
                    .font(.labBody(11, .semiBold))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 8)
                Button {
                    Haptics.firm()
                    model.addLayer()
                } label: {
                    Text("Add")
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layer.add")
            }

            ForEach(Array(model.layers.enumerated()), id: \.offset) { pair in
                layerRow(pair.offset, pair.element)
            }

            Text(model.hasLayers
                ? "New things go on the layer with the dot beside it. Hidden layers keep running; locked ones "
                    + "keep running too, they just cannot be pushed."
                : "Keep parts of a world apart: a still globe on one layer, a storm on another. Each gets its "
                    + "own colour, its own weight and its own air.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One layer: which one is current, its name and count, and what can be done to it.
    @ViewBuilder
    private func layerRow(_ index: Int, _ layer: ParticleLayer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Choosing the layer is the whole row's tap, so the small controls beside it are the only things that
                // do anything else.
                Button {
                    Haptics.tap()
                    model.currentLayer = index
                } label: {
                    HStack(spacing: 6) {
                        // Built from the three channels rather than from the packed number: the engine packs red in
                        // the lowest byte, so handing the packed value over as a hex colour would show every layer's
                        // red and blue the wrong way round.
                        Circle()
                            .fill(layer.tint.map {
                                Color(
                                    red: Double($0.r) / 255,
                                    green: Double($0.g) / 255,
                                    blue: Double($0.b) / 255
                                )
                            } ?? Palette.muted)
                            .frame(width: 9, height: 9)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        model.currentLayer == index ? Palette.foreground : .clear, lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            }
                        Text(layer.name)
                            .font(.labBody(11, model.currentLayer == index ? .semiBold : .regular))
                            .foregroundStyle(layer.shown ? Palette.foreground : Palette.subtleForeground)
                            .lineLimit(1)
                        Text("\(model.bodiesInLayer(index))")
                            .font(.labNumeric(10))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layer.choose.\(index)")

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    model.showLayer(index, !layer.shown)
                } label: {
                    Image(systemName: layer.shown ? "eye" : "eye.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(layer.shown ? Palette.foreground : Palette.subtleForeground)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layer.show.\(index)")

                Button {
                    Haptics.tap()
                    model.lockLayer(index, !layer.locked)
                } label: {
                    Image(systemName: layer.locked ? "lock" : "lock.open")
                        .font(.system(size: 12))
                        .foregroundStyle(layer.locked ? Palette.warn : Palette.subtleForeground)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("layer.lock.\(index)")

                Menu {
                    Button("Copy it") { model.duplicateLayer(index) }
                        .accessibilityIdentifier("layer.copy.\(index)")
                    Button("Empty it") { model.emptyLayer(index) }
                        .accessibilityIdentifier("layer.empty.\(index)")
                    if index > 0 {
                        Button("Pour into the one above") { model.mergeLayerDown(index) }
                            .accessibilityIdentifier("layer.merge.\(index)")
                        Button("Delete it", role: .destructive) { model.deleteLayer(index) }
                            .accessibilityIdentifier("layer.delete.\(index)")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.subtleForeground)
                        .frame(width: 26, height: 24)
                }
                .accessibilityIdentifier("layer.more.\(index)")
            }

            // Its two rules, only for the layer being worked on, so eight layers do not become sixteen sliders.
            if model.currentLayer == index, model.hasLayers {
                inlineSlider(
                    "Weight",
                    Binding(
                        get: { model.layers.indices.contains(index) ? model.layers[index].weight : 1 },
                        set: { model.setLayerWeight(index, $0) }
                    ),
                    -2 ... 2,
                    step: 0.05,
                    format: {
                        $0 == 0 ? "weightless" : ($0 < 0 ? "up, ×\(abs($0).formatted(.number.precision(.fractionLength(2))))" : "×\($0.formatted(.number.precision(.fractionLength(2))))")
                    }
                )
                inlineSlider(
                    "Air",
                    Binding(
                        get: { model.layers.indices.contains(index) ? model.layers[index].thinness : 1 },
                        set: { model.setLayerThinness(index, $0) }
                    ),
                    0.5 ... 1.5,
                    step: 0.01,
                    format: { $0 < 0.99 ? "thicker" : ($0 > 1.01 ? "thinner" : "the world's") }
                )
            }
        }
    }

    /// One of the two arrangement choosers for the morph.
    private func morphPicker(_ title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
            Menu {
                ForEach(ParticleFieldModel.morphableScenes, id: \.id) { scene in
                    Button(scene.name) { selection.wrappedValue = scene.id }
                }
            } label: {
                Text(ParticleArrangement.named(selection.wrappedValue)?.name ?? selection.wrappedValue)
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.foreground)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }
        }
    }

    /// The field in 3D, and everything about how the box is looked at.
    ///
    /// One switch, with the rest folded in under it while it is on: one-tap views, which way round the box the
    /// view is and how high above it, how deep the box is, how strong the perspective and the fog are, whether
    /// the box is drawn, whether bodies glow, and looking round by moving the phone.
    private var depthControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("3D")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            switchAndNumbers(
                "3D — the bodies move in a box you can look round",
                isOn: Binding(get: { model.depthEnabled }, set: { model.depthEnabled = $0 })
            ) {
                Text("Pick Turn in the tools below and drag to go round the box. Every tool reaches right through "
                    + "it, from the front to the back.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 3)

                LabFlow(spacing: 6) {
                    ForEach(ParticleFieldModel.Viewpoint.allCases) { point in
                        let here = abs(model.orbitYaw - point.angles.yaw) < 0.5
                            && abs(model.orbitPitch - point.angles.pitch) < 0.5
                        chip(point.name, lit: here) {
                            Haptics.selection()
                            model.look(from: point)
                        }
                    }
                }
                .padding(.bottom, 3)

                inlineSlider("Turn round", \.orbitYaw, -180 ... 180, step: 1, format: { Self.degrees($0) })
                inlineSlider(
                    "Look from above",
                    \.orbitPitch,
                    -ParticleCamera.maximumOrbitPitch ... ParticleCamera.maximumOrbitPitch,
                    step: 1,
                    format: { Self.degrees($0) }
                )
                inlineSlider(
                    "Box depth",
                    \.depthRatio,
                    ParticleEngine.depthRatioRange,
                    step: 0.05,
                    format: { "\(Int(($0 * 100).rounded()))% of the width" }
                )
                inlineSlider("Perspective", \.perspective, 0 ... 1, step: 0.05, format: { Self.share($0) })
                inlineSlider("Fog on the far side", \.fog, 0 ... 1, step: 0.05, format: { Self.share($0) })
                // Into the middle of the box, where turning the view becomes looking round from inside it.
                inlineSlider(
                    "Fly in",
                    \.flyIn,
                    0 ... 1,
                    step: 0.02,
                    format: { $0 < 0.01 ? "outside" : ($0 > 0.99 ? "the middle" : Self.share($0)) }
                )
                if model.flyIn > 0.01 {
                    Text("From inside, turning the view with Turn is looking round. Every tool still reaches what "
                        + "is under your finger.")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Somewhere other than the middle: touch it with Look, then fly there.
                HStack(spacing: 6) {
                    chip("Fly to what Look touched", symbol: "location.fill", lit: false) {
                        Haptics.firm()
                        model.flyToLookedAt()
                    }
                    .disabled(!model.canFlyToLookedAt)
                    .opacity(model.canFlyToLookedAt ? 1 : 0.4)
                    if model.isOffCentre {
                        chip("Back to the middle", symbol: "scope", lit: false) {
                            Haptics.tap()
                            model.flyBackToTheMiddle()
                        }
                    }
                }

                // Near and far go soft, as in a photograph.
                switchAndNumbers(
                    "Camera focus — near and far go soft",
                    isOn: Binding(get: { model.focusBlur > 0.001 }, set: { model.focusBlur = $0 ? 0.5 : 0 })
                ) {
                    Text("Pick Look in the tools and touch something to bring it into focus.")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                    inlineSlider("How soft", \.focusBlur, 0.05 ... 1, step: 0.05, format: { Self.share($0) })
                    inlineSlider(
                        "In focus",
                        \.focusAt,
                        0 ... 1,
                        step: 0.01,
                        format: { $0 < 0.4 ? "near" : ($0 > 0.6 ? "far" : "middle") }
                    )
                }

                // A thin slab instead of the whole box, for seeing inside a crowd.
                switchAndNumbers(
                    "Show a slice only",
                    isOn: Binding(
                        get: { model.sliceDepth < 0.999 },
                        set: { model.sliceDepth = $0 ? 0.18 : 1 }
                    )
                ) {
                    inlineSlider("How thick", \.sliceDepth, 0.02 ... 0.6, step: 0.02, format: { Self.share($0) })
                    inlineSlider(
                        "Front to back",
                        \.sliceAt,
                        -1 ... 1,
                        step: 0.02,
                        format: { $0 < -0.05 ? "near" : ($0 > 0.05 ? "far" : "middle") }
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    if model.hasLabels {
                        smallToggle(
                            "Show the names",
                            isOn: Binding(get: { model.showsLabels }, set: { model.showsLabels = $0 })
                        )
                    }
                    smallToggle(
                        "Colour by how far away things are",
                        isOn: Binding(get: { model.colorsByDistance }, set: { model.colorsByDistance = $0 })
                    )
                    smallToggle(
                        "Red-and-blue glasses",
                        isOn: Binding(
                            get: { model.glassesTurn > 0.01 },
                            set: { model.glassesTurn = $0 ? 2.4 : 0 }
                        )
                    )
                    if model.glassesTurn > 0.01 {
                        inlineSlider(
                            "How far apart your eyes are",
                            \.glassesTurn,
                            0.4 ... 8,
                            step: 0.2,
                            format: { Self.degrees($0) }
                        )
                    }
                    smallToggle(
                        "Shadows on the floor",
                        isOn: Binding(get: { model.showsShadows }, set: { model.showsShadows = $0 })
                    )
                    smallToggle(
                        "Show the box",
                        isOn: Binding(get: { model.showsBox }, set: { model.showsBox = $0 })
                    )
                    smallToggle(
                        "Glow — overlapping bodies add up into light",
                        isOn: Binding(get: { model.glows }, set: { model.glows = $0 })
                    )
                    smallToggle(
                        "Look round by moving the phone",
                        isOn: Binding(get: { model.looksAround }, set: { model.looksAround = $0 })
                    )
                    if model.looksAround {
                        // Whatever way the phone is held when this is pressed becomes looking straight at the view.
                        Button {
                            Haptics.tap()
                            model.recentreLookingAround()
                        } label: {
                            Label("Hold it like this", systemImage: "scope")
                                .font(.labBody(11, .semiBold))
                                .foregroundStyle(Palette.foreground)
                                .padding(.horizontal, 11)
                                .frame(height: 28)
                                .background(Capsule().fill(Color.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 3)
            }
        }
    }

    /// Using more than one finger at once, and copying a stroke round the middle.
    private var fingerControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("FINGERS AND SHOWING OFF")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            switchAndNumbers(
                "Every finger is its own tool",
                isOn: Binding(get: { model.manyFingers }, set: { model.manyFingers = $0 })
            ) {
                Text("Ten fingers, ten whirlpools. While this is on there is no spare finger for the view, so "
                    + "pinching and twisting stand down — zoom and turn from the View section instead.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switchAndNumbers(
                "Be a clock",
                isOn: Binding(get: { model.isAClock }, set: { model.isAClock = $0 })
            ) {
                Text("The field spells out the time and tumbles into the next minute as it turns. Push the digits "
                    + "about and they will be back, differently, within the minute.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                smallToggle(
                    "Twenty-four hour face",
                    isOn: Binding(get: { model.clockUses24Hour }, set: { model.clockUses24Hour = $0 })
                )
            }

            switchAndNumbers(
                "Show me — drift between scenes by itself",
                isOn: Binding(get: { model.relaxes }, set: { model.relaxes = $0 })
            ) {
                Text("For leaving on a table. It picks a new arrangement at random every so often and turns "
                    + "slowly. Touch anything and you are simply working on whatever is showing.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                inlineSlider(
                    "Each one lasts",
                    \.relaxDwell,
                    10 ... 240,
                    step: 5,
                    format: { "\(Int($0.rounded()))s" }
                )
            }

            switchAndNumbers(
                "Kaleidoscope",
                isOn: Binding(
                    get: { model.kaleidoscopeFolds > 1 },
                    set: { model.kaleidoscopeFolds = $0 ? 6 : 1 }
                )
            ) {
                Text("Every stroke is copied evenly round the middle, so one line comes out as a snowflake. "
                    + "Each copy is a real push, so it works with any tool.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                inlineSlider(
                    "Folds",
                    \.kaleidoscopeFolds,
                    2 ... 12,
                    step: 1,
                    format: { "\(Int($0.rounded()))" }
                )
                smallToggle(
                    "Mirror every other one",
                    isOn: Binding(get: { model.kaleidoscopeMirrors }, set: { model.kaleidoscopeMirrors = $0 })
                )
            }
        }
    }

    /// An angle, in whole degrees.
    private static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    /// A share from nought to one, as a percentage, or "None" at nought.
    private static func share(_ value: Double) -> String {
        value < 0.005 ? "None" : "\(Int((value * 100).rounded()))%"
    }

    /// A switch in one of the folded-in sets.
    private func smallToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(.labBody(11))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tint(Palette.primary)
    }

    /// The word the field spells out, and how it is made.
    ///
    /// Directly under the arrangements, because the "Word" chip among them does nothing sensible until
    /// there is a word to draw — a chip that needs typing first and gives you nowhere to type is a dead end.
    private var wordControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WORD")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: Binding(get: { model.wordText }, set: { model.wordText = $0 }),
                    prompt: Text("a word to spell").foregroundStyle(Palette.subtleForeground)
                )
                .font(.labBody(12))
                .foregroundStyle(Palette.foreground)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    Haptics.firm()
                    model.spawnWord()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )

                Button {
                    Haptics.firm()
                    model.spawnWord()
                } label: {
                    Text("Spell it")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                inlineSlider(
                    "How many bodies",
                    Binding(get: { model.wordCount }, set: { model.wordCount = $0 }),
                    500 ... 40_000,
                    step: 500
                ) { "\(Int($0).formatted(.number.grouping(.automatic)))" }
                inlineSlider(
                    "How big",
                    Binding(get: { model.wordFill }, set: { model.wordFill = $0 }),
                    0.2 ... 1,
                    step: 0.02
                ) { "\(Int($0 * 100))% of the field" }

                Button {
                    Haptics.tap()
                    flash("another-word")
                    model.spawnWord(replacingField: false)
                } label: {
                    Text("Add another without clearing")
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(flashing == "another-word" ? Palette.primaryForeground : Palette.muted)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(
                            Capsule().fill(flashing == "another-word" ? Palette.primary : Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.primary.opacity(0.35))
                    .frame(width: 1.5)
            }

            if let problem = model.wordProblem {
                Text(problem)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Adding bodies, and the ceiling on how many there can be.
    private var population: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("POPULATION")
                    .font(.labBody(10, .semiBold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.subtleForeground)
                Spacer(minLength: 8)
                Text("\(model.remainingRoom.formatted()) more will fit")
                    .font(.labNumeric(10))
                    .foregroundStyle(Palette.subtleForeground)
            }

            joinControl

            HStack(spacing: 6) {
                Button {
                    if model.remainingRoom == 0 {
                        Haptics.refused()
                        return
                    }
                    Haptics.tap()
                    flash("add")
                    model.spawn(batch)
                } label: {
                    Text(model.addButtonTitle(for: batch, short: Self.shortCount(batch)))
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(
                            Capsule().fill(flashing == "add" ? Palette.primary.opacity(0.6) : Palette.primary)
                        )
                        .scaleEffect(flashing == "add" ? 0.94 : 1)
                }
                .buttonStyle(.plain)
                .opacity(model.remainingRoom == 0 ? 0.4 : 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ParticleFieldModel.batchChoices, id: \.self) { choice in
                            countChip(Self.shortCount(choice), selected: batch == choice) {
                                Haptics.selection()
                                batch = choice
                            }
                        }
                    }
                }
            }

            HStack {
                Text("Most it will hold")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Text(Self.shortCount(model.maxBodies))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.foreground)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ParticleFieldModel.bodyCapChoices, id: \.self) { choice in
                        countChip(Self.shortCount(choice), selected: model.maxBodies == choice) {
                            Haptics.selection()
                            model.maxBodies = choice
                        }
                    }
                }
            }
        }
    }

    /// Whether bodies added now join the arrangement, and what that means for this one.
    ///
    /// Shown only while there is an arrangement that can be joined, because a switch that does nothing on an
    /// empty field is a puzzle.
    @ViewBuilder
    private var joinControl: some View {
        if let details = model.arrangementDetails, model.canJoinArrangement {
            VStack(alignment: .leading, spacing: 3) {
                Toggle(isOn: Binding(
                    get: { model.joinsArrangement },
                    // No buzz of its own: a switch already gives one.
                    set: { model.joinsArrangement = $0 }
                )) {
                    Text("Join the \(details.name.lowercased())")
                        .font(.labBody(12))
                        .foregroundStyle(Palette.foreground)
                }
                .tint(Palette.primary)
                Text(
                    model.joinsArrangement
                        ? details.joinDescription
                        : "New bodies are scattered in on their own, and the \(details.name.lowercased()) acts on "
                            + "them as it would on anything."
                )
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
            }
            // Only where it would make a difference: an arrangement whose bodies have a size of their own. A
            // sunflower's seeds are all the slider's size, so matching them changes nothing.
            if model.arrangementHasOwnSize {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle(isOn: Binding(
                        get: { model.matchesArrangementSize },
                        set: { model.matchesArrangementSize = $0 }
                    )) {
                        Text("Match the size of what's there")
                            .font(.labBody(12))
                            .foregroundStyle(Palette.foreground)
                    }
                    .tint(Palette.primary)
                    Text(
                        model.matchesArrangementSize
                            ? "New bodies are made the same size as the ones already in the "
                                + "\(details.name.lowercased())."
                            : "New bodies are the size the Particle size slider sets."
                    )
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if let note = model.additionNote {
            Text(note)
                .font(.labBody(10))
                .foregroundStyle(Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func countChip(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.labNumeric(11))
                .foregroundStyle(selected ? Palette.primaryForeground : Palette.muted)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    /// Large counts as people say them: fifty thousand is "50k", a million is "1M".
    ///
    /// Not the system's abbreviation, which would give "50K" and "1.0M" — and which changes with the
    /// phone's language, so a row of chips would change width unpredictably.
    private static func shortCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return millions == millions.rounded()
                ? "\(Int(millions))M"
                : "\(millions.formatted(.number.precision(.fractionLength(1))))M"
        }
        if value >= 1_000 { return "\(value / 1_000)k" }
        return "\(value)"
    }

    /// The ways into the other panels.
    private var destinations: some View {
        LabFlow(spacing: 6) {
            destination("Presets", "square.grid.2x2", id: "presets") {
                Haptics.tap()
                onShowPresets()
            }
            // Pours the field into the powder world. Worth a named button rather than an icon: it moves
            // everything to the other chamber, which is not a thing to discover by accident.
            destination("Settle into powder", "arrow.down.to.line", id: "settle") {
                Haptics.firm()
                flash("settle")
                onSettleEverything()
            }
            // The other direction: the powder world shown in the box, as a slab to turn round. A view of that world
            // rather than a copy of it — nothing can be built from this side, and the powder world is untouched.
            destination("Show the powder world", "cube.transparent", id: "slab") {
                Haptics.firm()
                flash("slab")
                onShowPowderInTheBox()
            }
            if model.hasRibbons {
                destination("Rub out the light", "eraser", id: "ribbons") {
                    Haptics.firm()
                    flash("ribbons")
                    model.clearRibbons()
                }
            }
            destination("Drop a well", "circle.circle", id: "well") {
                Haptics.tap()
                flash("well")
                model.dropWell()
            }
            destination("Field", "slider.horizontal.3", id: "field") {
                Haptics.tap()
                onShowSettings()
            }
        }
    }

    private func destination(
        _ title: String,
        _ symbol: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        let lit = flashing == id
        return Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.labBody(11, .medium))
                Text(title)
                    .font(.labBody(12, .medium))
            }
            .foregroundStyle(lit ? Palette.primaryForeground : Palette.foreground)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(Capsule().fill(lit ? Palette.primary : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    /// Scrolling, with a floor under it, for the reason written out on the powder tray's equivalent: a
    /// tray taller than the screen has to give somewhere, and without a minimum height the thing that
    /// gives is whatever has no height of its own — silently, and all the way to nothing.
    private var expanded: some View {
        ScrollView {
            expandedContents
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(minHeight: 220, maxHeight: 380)
        .scrollBounceBehavior(.basedOnSize)
        .labScrollEdges()
        .accessibilityIdentifier("fieldTray.expanded")
    }

    private var expandedContents: some View {
        // The original one-piece scrolling tray, built a few parts at a time rather than all at once when it opens.
        //
        // A plain stack, not a lazy one. In the lazy one the parts' heights were only guesses until they were drawn, and
        // on a narrow phone scrolling far down it kept re-measuring and never settled: the walkthrough saw the app stop
        // answering for minutes near the movie and formula parts, which on a real phone is the system closing the app.
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(ExpandedSection.allCases.prefix(expandedSectionLimit)), id: \.self) { section in
                expandedSection(section)
                    .id(section)
            }
            if expandedSectionLimit < ExpandedSection.allCases.count {
                Color.clear
                    .frame(height: 1)
                    .id(expandedSectionLimit)
                    .accessibilityHidden(true)
                    .onAppear {
                        // Move this work out of the layout pass that noticed the end of the current chunk.
                        Task { @MainActor in
                            // A breath between parts, so opening never does all the work in one go.
                            try? await Task.sleep(for: .milliseconds(40))
                            expandedSectionLimit = min(
                                ExpandedSection.allCases.count,
                                expandedSectionLimit + 4
                            )
                        }
                    }
            }
        }
    }

    /// Each section is wrapped on its own so SwiftUI never has to hold every section's type as one giant nested view.
    private func expandedSection(_ section: ExpandedSection) -> AnyView {
        switch section {
        case .style:
            AnyView(styleSwitchRow(toListMenu: true))
        case .destinations:
            AnyView(destinations)
        case .cost:
            AnyView(costWarning)
        case .depth:
            AnyView(depthControls)
        case .fingers:
            AnyView(fingerControls)
        case .loops:
            AnyView(loopControls)
        case .arrangements:
            AnyView(presetChips)
        case .morph:
            AnyView(morphControls)
        case .formula:
            AnyView(recipeControls)
        case .layers:
            AnyView(layerControls)
        case .arrangementDetails:
            AnyView(arrangementDescription)
        case .word:
            AnyView(wordControls)
        case .creatures:
            AnyView(FieldCreatureControls(model: model))
        case .worldsWithin:
            AnyView(FieldWithinControls(model: model))
        case .bodyControls:
            AnyView(primaryBodyControls)
        case .physics:
            AnyView(physics)
        case .colourModes:
            AnyView(colourModes)
        case .colourRamps:
            AnyView(colourRamps)
        case .shapes:
            AnyView(shapeChoices)
        case .backdrop:
            AnyView(backdropChoices)
        case .view:
            AnyView(viewControls)
        case .movie:
            AnyView(FieldMovieControls(model: model))
        }
    }

    /// A separate modal rather than another child of the dock. Its first screen is deliberately static: tapping the
    /// arrow constructs no sliders, dynamic ranges, custom layouts or simulation-dependent labels.
    private var menu: some View {
        GeometryReader { screen in
            let safeHorizontal = screen.safeAreaInsets.leading + screen.safeAreaInsets.trailing
            let safeVertical = screen.safeAreaInsets.top + screen.safeAreaInsets.bottom
            let width = min(680, max(1, screen.size.width - safeHorizontal - 20))
            let height = min(760, max(1, screen.size.height - safeVertical - 20))

            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { setOpen(false) }
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    menuHeader
                    Rectangle().fill(Palette.border).frame(height: 1)
                    ScrollView {
                        Group {
                            if let selectedPage {
                                menuPage(selectedPage)
                                    .accessibilityIdentifier("fieldTray.section.\(selectedPage.rawValue)")
                            } else {
                                menuChooser
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(selectedPage?.rawValue ?? "root")
                    .labScrollEdges()
                }
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Palette.elevated)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Palette.borderStrong, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .accessibilityAddTraits(.isModal)
            }
            .frame(width: screen.size.width, height: screen.size.height)
        }
        .accessibilityIdentifier("fieldTray.modal")
        .accessibilityAction(.escape) { setOpen(false) }
    }

    private var menuHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            if selectedPage != nil {
                Button {
                    selectedPage = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.labBody(14, .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Field controls")
                .accessibilityIdentifier("fieldTray.categories")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedPage?.title ?? "Particle field")
                    .font(.labDisplay(16))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.foreground)
                    .accessibilityIdentifier("sheet.title")
                Text(selectedPage?.detail ?? "Choose one part to change")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                setOpen(false)
            } label: {
                Image(systemName: "xmark")
                    .font(.labBody(14, .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("sheet.close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var menuChooser: some View {
        LazyVStack(spacing: 8) {
            styleSwitchRow(toListMenu: false)
            ForEach(MenuPage.allCases, id: \.self) { page in
                Button {
                    selectedPage = page
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.symbol)
                            .font(.labBody(15, .medium))
                            .foregroundStyle(Palette.primary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title)
                                .font(.labBody(13, .semiBold))
                                .foregroundStyle(Palette.foreground)
                            Text(page.detail)
                                .font(.labBody(10))
                                .foregroundStyle(Palette.subtleForeground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.labBody(11, .medium))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fieldTray.category.\(page.rawValue)")
            }
        }
        .accessibilityIdentifier("fieldTray.root")
    }

    /// This switch is the construction boundary the old LazyVStack was not. SwiftUI evaluates only the selected
    /// branch, so no page can make the first arrow tap instantiate the other fourteen pages.
    private func menuPage(_ page: MenuPage) -> AnyView {
        switch page {
        case .arrangements:
            AnyView(presetChips)
        case .morph:
            AnyView(morphControls)
        case .formula:
            AnyView(recipeControls)
        case .layers:
            AnyView(layerControls)
        case .words:
            AnyView(wordControls)
        case .creatures:
            AnyView(FieldCreatureControls(model: model))
        case .worlds:
            AnyView(FieldWithinControls(model: model))
        case .bodies:
            AnyView(primaryBodyControls)
        case .touch:
            AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    fingerControls
                    loopControls
                }
            )
        case .physics:
            AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    costWarning
                    physics
                }
            )
        case .threeD:
            AnyView(depthControls)
        case .view:
            AnyView(viewControls)
        case .appearance:
            AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    colourModes
                    colourRamps
                    shapeChoices
                    backdropChoices
                }
            )
        case .movie:
            AnyView(FieldMovieControls(model: model))
        case .actions:
            AnyView(destinations)
        }
    }

    /// The way to swap between the list menu and the one scrolling tray. Shown at the top of both, so whichever one
    /// is open, the other is one tap away. The choice is remembered.
    private func styleSwitchRow(toListMenu: Bool) -> some View {
        Button {
            Haptics.selection()
            selectedPage = nil
            usesListMenu = toListMenu
        } label: {
            HStack(spacing: 10) {
                Image(systemName: toListMenu ? "list.bullet" : "rectangle.bottomthird.inset.filled")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(Palette.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(toListMenu ? "Show as a list menu" : "Show as one scrolling tray")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.foreground)
                    Text(toListMenu ? "One part at a time" : "Everything in one tray, like before")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.labBody(11, .medium))
                    .foregroundStyle(Palette.subtleForeground)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(toListMenu ? "fieldTray.useListMenu" : "fieldTray.useTray")
    }

    /// Population and the few always-visible body controls, kept together exactly as they were in the old tray.
    private var primaryBodyControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            population
            labelledSlider(
                "Particle size",
                value: Binding(get: { model.particleSize }, set: { model.particleSize = $0 }),
                range: 1 ... 8,
                display: { $0.formatted(.number.precision(.fractionLength(1))) }
            )
            labelledSlider(
                "Reach",
                value: Binding(get: { model.reachShare }, set: { model.reachShare = $0 }),
                range: ParticleFieldModel.reachShareRange,
                display: { Self.reachLabel($0, long: true) }
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

            Text("Collide is what costs: about a millisecond for every thousand bodies. Everything else "
                + "here is nearly free.")
                .font(.labBody(11))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The kinds of physics. Built as many small separate views in `FieldPhysicsControls.swift`, because as one
    /// giant view here it closed the app on a real iPhone as soon as it was shown.
    private var physics: some View {
        FieldPhysicsControls(model: model)
    }

    /// A switch, with its own numbers folded in underneath it while it is on.
    @ViewBuilder
    private func switchAndNumbers(
        _ label: String,
        isOn: Binding<Bool>,
        @ViewBuilder numbers: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: isOn) {
                Text(label)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Palette.primary)

            if isOn.wrappedValue {
                VStack(alignment: .leading, spacing: 2) {
                    numbers()
                }
                .padding(.leading, 10)
                .padding(.top, 2)
                .overlay(alignment: .leading) {
                    // A hairline down the left, so a set of numbers plainly belongs to the switch above it
                    // rather than floating between two of them.
                    Rectangle()
                        .fill(Palette.primary.opacity(0.35))
                        .frame(width: 1.5)
                }
            }
        }
    }

    /// A compact slider for the folded-in sets, which have no room for the full-width kind.
    private func inlineSlider(
        _ label: String,
        _ path: ReferenceWritableKeyPath<ParticleFieldModel, Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) }
    ) -> some View {
        inlineSlider(
            label,
            Binding(get: { model[keyPath: path] }, set: { model[keyPath: path] = $0 }),
            range,
            step: step,
            format: format
        )
    }

    private func inlineSlider(
        _ label: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String = { $0.formatted(.number.precision(.fractionLength(2))) }
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Text(format(value.wrappedValue))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            Slider(value: value, in: range, step: step) { Text(label) }
                .tint(Palette.primary)
                // Named the same way the panel's sliders are, so the walk-through can find any of these too. Without
                // it every slider in this tray was invisible to the walk, and a tray that crashes when a slider moves
                // is exactly the kind of fault the walk exists to catch.
                .accessibilityIdentifier("slider.\(label)")
        }
        .padding(.vertical, 1)
    }

    /// What the field sits on, and how brightly it glows.
    ///
    /// Together these change the character of the chamber more than any physics setting does. The field
    /// has always been a scatter of points on flat near-black; stars behind it and a glow around it make
    /// the same arrangement read as a photograph of something rather than as a chart.
    private var backdropChoices: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BEHIND")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                ForEach(ParticleBackdrop.allCases, id: \.self) { choice in
                    let selected = model.backdrop == choice
                    Button {
                        Haptics.selection()
                        model.backdrop = choice
                    } label: {
                        Text(choice.displayName)
                            .font(.labBody(12, selected ? .semiBold : .regular))
                            .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if model.backdrop != .none {
                LabSlider(
                    label: "How strong",
                    value: Binding(
                        get: { model.backdropStrength },
                        set: { model.backdropStrength = $0 }
                    ),
                    range: 0 ... 2,
                    step: 0.05
                ) { "\($0.formatted(.number.precision(.fractionLength(2))))×" }
            }

            LabSlider(
                label: "Glow",
                value: Binding(get: { model.glowStrength }, set: { model.glowStrength = $0 }),
                range: 0 ... 3,
                step: 0.05
            ) { $0 == 0 ? "off" : "\($0.formatted(.number.precision(.fractionLength(2))))×" }

            if model.glowStrength > 0 {
                LabSlider(
                    label: "Glow spread",
                    value: Binding(get: { model.glowSpread }, set: { model.glowSpread = $0 }),
                    range: 0.4 ... 8,
                    step: 0.1
                ) { $0.formatted(.number.precision(.fractionLength(1))) }
                LabSlider(
                    label: "Glow threshold",
                    value: Binding(get: { model.glowThreshold }, set: { model.glowThreshold = $0 }),
                    range: 0 ... 1,
                    step: 0.02
                ) { $0.formatted(.number.precision(.fractionLength(2))) }
            }
        }
    }

    /// What silhouette bodies are drawn as.
    ///
    /// Shown as the shapes themselves rather than as a list of words. "Spark, Plus, Diamond" tells
    /// nobody what they are choosing between; these are pictures, and the point of them is how they
    /// look.
    ///
    /// The swatches are drawn by SwiftUI rather than sampled from the shader, which is the one place in
    /// this file where two drawings of the same thing exist. That is a real risk — it is exactly how the
    /// reference implementation ended up with hearts the right way up on one path and upside down on
    /// the other — so the swatches are kept deliberately plain, and the engine's own tests are what
    /// establish which way round a shape belongs.
    private var shapeChoices: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SHAPE")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                ForEach(ParticleShape.allCases, id: \.self) { shape in
                    let selected = model.particleShape == shape
                    Button {
                        Haptics.selection()
                        model.particleShape = shape
                    } label: {
                        ShapeSwatch(shape: shape)
                            .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
                            .frame(width: 26, height: 26)
                            .padding(5)
                            .background(
                                Circle().fill(selected ? Palette.primary : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shape.displayName)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }

    /// What the fingers do to the view, for the kind of field it is.
    private var viewHint: String {
        guard model.depthEnabled else {
            return "Pinch to zoom, drag with two fingers to move, twist to turn."
        }
        return "Pinch to zoom, drag with two fingers to move, twist to turn the box round. "
            + "The Turn tool goes round it with one finger."
    }

    /// Where the field is being looked at from.
    ///
    /// Only the two things a gesture cannot say are given controls. Zoom is a pinch, shifting is a
    /// two-finger drag and turning is a twist, so those need nothing here — but tipping the plane has
    /// no natural two-finger motion left, and "put it back" and "fit it on screen" are buttons by
    /// nature.
    ///
    /// The plane genuinely tips rather than the picture being squashed: the near half of the field is
    /// drawn larger than the far half, so a ring of bodies becomes a proper ellipse and a galaxy
    /// reads as a disc seen at an angle instead of as a circle that has been sat on.
    private var viewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VIEW")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            Text(viewHint)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)

            // How finely it is drawn. The powder half has had this since it was built; the field never did,
            // and it is the half that can be made to fill eight million pixels a frame with a glow over them.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Detail")
                        .font(.labBody(11))
                        .foregroundStyle(Palette.muted)
                    Spacer(minLength: 8)
                    ForEach(ParticleFieldModel.detailChoices, id: \.id) { choice in
                        Button {
                            Haptics.selection()
                        model.detail = choice.id
                        } label: {
                            Text(choice.name)
                                .font(.labBody(11, .semiBold))
                                .foregroundStyle(
                                    model.detail == choice.id
                                        ? Palette.primaryForeground
                                        : Palette.foreground
                                )
                                .padding(.horizontal, 9)
                                .frame(height: 26)
                                .background(
                                    Capsule().fill(
                                        model.detail == choice.id
                                            ? Palette.primary
                                            : Color.white.opacity(0.10)
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(model.detailDescription)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The difference between a zoom that is worth having and one that is not.
            Toggle(isOn: Binding(get: { model.zoomAddsSpace }, set: { model.zoomAddsSpace = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Zooming out adds room")
                        .font(.labBody(11))
                        .foregroundStyle(Palette.muted)
                    Text(
                        model.worldScale > 1.01
                            ? "The world is \(model.worldScale.formatted(.number.precision(.fractionLength(1))))× the screen."
                            : "Pulling back makes the world bigger instead of the picture smaller."
                    )
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.primary)

            // Tipping the flat sheet. In 3D the box is looked at from above with the slider in the 3D section, and
            // this one would only lean a sheet that is not being drawn.
            if !model.depthEnabled {
                LabSlider(
                    label: "Tilt",
                    value: Binding(get: { model.cameraPitch }, set: { model.cameraPitch = $0 }),
                    range: 0 ... ParticleCamera.maximumPitch,
                    step: 1
                ) { "\(Int($0.rounded()))°" }
            }

            switchAndNumbers(
                model.depthEnabled ? "Turn round the box by itself" : "Turn by itself",
                isOn: Binding(get: { model.cameraAutoOrbit }, set: { model.cameraAutoOrbit = $0 })
            ) {
                if LabMotion.isReduced {
                    Text("Held still, because your phone is set to reduce motion. Turn that off in the phone's "
                        + "Accessibility settings to let it spin.")
                        .font(.labBody(10))
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
                inlineSlider(
                    "Speed",
                    \.spinRate,
                    0.1 ... 5,
                    step: 0.1,
                    format: { "\($0.formatted(.number.precision(.fractionLength(1))))×" }
                )
            }

            // One slow turn, recorded, for showing somebody what you made.
            if model.depthEnabled {
                Button {
                    Haptics.firm()
                    if model.turntableRunning { model.stopTurntable() } else { model.startTurntable() }
                } label: {
                    Label(
                        model.turntableRunning
                            ? "Turning… \(Int((model.turntableProgress * 100).rounded()))%"
                            : "Record one slow turn",
                        systemImage: model.turntableRunning ? "stop.circle" : "video.badge.plus"
                    )
                    .font(.labBody(12, .semiBold))
                    .foregroundStyle(model.turntableRunning ? Palette.primaryForeground : Palette.foreground)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(
                        Capsule().fill(model.turntableRunning ? Palette.primary : Color.white.opacity(0.10))
                    )
                }
                .buttonStyle(.plain)
                Text("Records the whole screen and stops itself after one full circle. Close the tray first.")
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    model.fitCameraToContent()
                } label: {
                    Label("Fit to the field", systemImage: "viewfinder")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.foreground)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)

                if model.cameraIsMoved {
                    Button {
                        Haptics.tap()
                        model.resetCamera()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.labBody(12, .semiBold))
                            .foregroundStyle(Palette.foreground)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Says so when the crowd and the collisions together cannot work, and offers the one tap that fixes
    /// it.
    ///
    /// ## Why this is here rather than the field simply being faster
    ///
    /// Because it cannot be. Pushing bodies apart costs about a millisecond per thousand of them:
    /// measured, two hundred thousand comes to two hundred milliseconds a moment, which is five frames a
    /// second, while the same crowd with Collide off costs under one millisecond. A factor of two hundred
    /// and fifty.
    ///
    /// The pass is not badly written — it is a uniform grid with a hard cap on how many neighbours any
    /// cell examines, and it runs at about the speed the memory can feed it. Two hundred thousand bodies
    /// each overlapping dozens of others, resolved twice a frame, is simply not a smooth workload in any
    /// implementation. See `SwarmCost` for the figures.
    ///
    /// So the field still offers the crowd, and now tells the truth about what it costs instead of
    /// quietly grinding to five frames a second and leaving somebody to conclude the app is broken.
    @ViewBuilder
    private var costWarning: some View {
        if let warning = SwarmCost.warning(
            bodies: model.bodyCount,
            collisions: model.collisionsEnabled,
            inDepth: model.depthEnabled
        )
            ?? model.forceWarning
            ?? SwarmCost.repaintWarning(
                bodies: model.bodyCount,
                ramp: model.paletteEnabled,
                rampMoves: model.paletteRampMoves
            )
        {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.labBody(12, .medium))
                        .foregroundStyle(Palette.warn)
                    Text(warning)
                        .font(.labBody(11))
                        .foregroundStyle(Palette.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Haptics.tap()
                    model.collisionsEnabled = false
                } label: {
                    Text("Switch Collide off")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
            }
            .padding(11)
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

    /// How the bodies are coloured.
    ///
    /// Chips rather than a menu. This was a `Picker` in the bottom row, which drew the system's own
    /// pop-up menu button — grey text and a pair of tiny chevrons, sitting between the play button and
    /// the clear button looking like a piece of a different application had been left in by mistake.
    /// Nothing else in Crucible looks like that, and it was also the widest thing in that row, which is
    /// what pushed the buttons either side of it into the corners.
    private var colourModes: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("COLOUR BY")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                ForEach(Self.colourChoices, id: \.mode) { choice in
                    let selected = model.colorMode == choice.mode
                    Button {
                        Haptics.selection()
                        model.colorMode = choice.mode
                    } label: {
                        Text(choice.name)
                            .font(.labBody(12, selected ? .semiBold : .regular))
                            .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(
                                Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let colourChoices: [(mode: ParticleColorMode, name: String)] = [
        (.native, "Own"),
        (.velocity, "Speed"),
        (.charge, "Charge"),
        (.rainbow, "Place"),
        (.density, "Crowd"),
        (.lifespan, "Life"),
        // The one the web engine had and this field could not, until the crowd carried weights.
        (.mass, "Weight"),
    ]

    /// Which colours the row above is drawn in.
    ///
    /// Two rows rather than one long list of combinations, because they answer different questions.
    /// The row above says what the colour *means* — speed, place, age. This row says which colours
    /// say it. Six meanings and seven ramps as one list would be forty-two chips.
    ///
    /// Each ramp is shown as the ramp itself. A row of words reading "Ember, Ice, Aurora" tells
    /// nobody what they are choosing between, and these are pictures, not settings.
    private var colourRamps: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(
                get: { model.paletteEnabled },
                set: { model.paletteEnabled = $0 }
            )) {
                Text("Use a colour ramp")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
            }
            .tint(Palette.primary)

            if model.paletteEnabled {
                LabFlow(spacing: 6) {
                    ForEach(ParticlePalette.allCases, id: \.self) { ramp in
                        let selected = model.palette == ramp
                        Button {
                            Haptics.selection()
                        model.palette = ramp
                        } label: {
                            VStack(spacing: 4) {
                                Capsule()
                                    .fill(Self.rampGradient(ramp))
                                    .frame(width: 58, height: 12)
                                Text(ramp.displayName)
                                    .font(.labBody(10, selected ? .semiBold : .regular))
                                    .foregroundStyle(
                                        selected ? Palette.foreground : Palette.subtleForeground
                                    )
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .fill(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                                    .stroke(
                                        selected ? Palette.primary : Color.clear,
                                        lineWidth: 1.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ramp.displayName) colour ramp")
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    /// A ramp drawn as a gradient, sampled from the same colours the field will use.
    ///
    /// Sampled rather than handed the stop list directly, so the swatch goes through exactly the
    /// arithmetic the particles do. A swatch that flatters a ramp the field then draws differently
    /// is worse than no swatch.
    private static func rampGradient(_ ramp: ParticlePalette) -> LinearGradient {
        let steps = 12
        let colors = (0 ..< steps).map { step -> Color in
            let sampled = ramp.sample(Double(step) / Double(steps - 1))
            return Color(
                red: Double(sampled.r) / 255,
                green: Double(sampled.g) / 255,
                blue: Double(sampled.b) / 255
            )
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // In 3D, first: one finger goes round the box instead of working the field. Picking any other tool
                // puts it down again.
                if model.depthEnabled {
                    toolButton("Turn", symbol: "rotate.3d", selected: model.turnsView && !model.usesLens) {
                        model.usesLens = false
                        model.turnsView = true
                    }
                }
                // Reads what is under your finger rather than pushing it. First with Turn, because both are
                // about looking rather than doing.
                toolButton("Look", symbol: "magnifyingglass", selected: model.usesLens) {
                    model.usesLens = true
                }
                ForEach(Self.tools.filter { !model.depthEnabled || !Self.flatOnly.contains($0.mode) }, id: \.mode) { tool in
                    toolButton(
                        tool.name,
                        symbol: tool.symbol,
                        selected: !isTurning && !model.usesLens && model.mouseMode == tool.mode
                    ) {
                        model.usesLens = false
                        model.mouseMode = tool.mode
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 38)
        .labScrollEdges()
    }

    /// One tool in the strip, lit while it is what a finger does.
    private func toolButton(
        _ name: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.labBody(11))
                Text(name)
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
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var transport: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
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

            // How far a touch reaches — this chamber's equivalent of brush size, and the same control
            // in the same place, which is what this file's opening comment promises and what the
            // colour-mode menu that used to sit here was breaking.
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
                Slider(
                    value: Binding(get: { model.reachShare }, set: { model.reachShare = $0 }),
                    in: ParticleFieldModel.reachShareRange
                )
                .tint(Palette.primary)
                Text(Self.reachLabel(model.reachShare, long: false))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 30, alignment: .trailing)
            }
            .accessibilityLabel("How far a touch reaches")
            .accessibilityValue(Self.reachLabel(model.reachShare, long: true))

            iconButton("trash", "Clear") {
                Haptics.firm()
                model.clear()
            }
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

    /// The reach in words: how much of the screen's height the circle is, or that it reaches everything.
    static func reachLabel(_ share: Double, long: Bool) -> String {
        if share >= ParticleFieldModel.wholeFieldReachShare { return long ? "whole field" : "all" }
        let percent = "\(Int((share * 100).rounded()))%"
        return long ? "\(percent) of the screen" : percent
    }
}

/// Picks one of the field presets.
///
/// Each with a line saying what it is, since this is the one place with room to say so, and the one showing
/// is marked — as it is in the tray.
struct FieldPresetPicker: View {
    /// Which arrangement is showing, to mark it.
    let current: String?
    /// Whether the field is in 3D, so each is described the way it will be built.
    var inDepth: Bool = false
    let onSelect: (String) -> Void

    /// What a preset is called in the list: marked when it adds rather than replaces, and when it only exists
    /// in 3D.
    private func title(of preset: ParticleArrangement) -> String {
        if preset.kind == .addition { return "\(preset.name) (adds)" }
        if preset.depth == .only { return "\(preset.name) (3D)" }
        return preset.name
    }

    var body: some View {
        LabSheet(
            title: "Presets",
            subtitle: "Arrangements to start from"
        ) {
            LabGroup(footnote: "A scene replaces the field and stays chosen until you pick another or clear. "
                + "Burst adds to whatever is there. The ones marked 3D only exist in 3D, and choosing one turns "
                + "3D on. Undo brings back what was there before.")
            {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ParticleFieldModel.presets, id: \.id) { preset in
                        let chosen = preset.kind == .scene && preset.id == current
                        Button {
                            if preset.kind == .addition { Haptics.tap() } else { Haptics.firm() }
                            onSelect(preset.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(of: preset))
                                        .font(.labBody(13, chosen ? .semiBold : .medium))
                                        .foregroundStyle(chosen ? Palette.primary : Palette.foreground)
                                    Text(preset.about(inDepth: inDepth))
                                        .font(.labBody(11))
                                        .foregroundStyle(Palette.subtleForeground)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                if chosen {
                                    Image(systemName: "checkmark")
                                        .font(.labBody(12, .semiBold))
                                        .foregroundStyle(Palette.primary)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(chosen ? Palette.primary.opacity(0.12) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}
