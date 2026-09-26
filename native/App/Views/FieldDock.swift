import CrucibleCore
import SwiftUI

/// The dock for the particle chamber: what your finger does, and what the field is made of.
///
/// Laid out like the powder dock so switching chambers does not move anything under your thumb,
/// but the contents are different in kind. There is nothing to paint with here — a touch applies
/// a force — so the row of things is a row of *tools* rather than of materials.
struct FieldDock: View {
    let model: ParticleFieldModel
    @Binding var isOpen: Bool
    let onShowPresets: () -> Void
    let onShowSettings: () -> Void
    /// Today's date in UTC, for the shared daily arrangement.
    let today: String
    /// Pours the whole field into the powder world.
    let onSettleEverything: () -> Void

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
        (.source, "Source", "drop.circle"),
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
        // No soft shadow under it any more. A shadow of that size is a blur pass of its own — the
        // compositor filtering a band of the screen every frame — and the hairline above already says the
        // dock is in front of the world rather than printed on it.
        .solidPanel(in: Rectangle())
    }

    private var handle: some View {
        Button {
            Haptics.selection()
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

    /// Whether one finger is turning the view round the box rather than working the field.
    private var isTurning: Bool {
        model.depthEnabled && model.turnsView
    }

    /// What a finger does now, in a word.
    private var toolName: String {
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

    /// How many bodies a tap of the add button scatters in.
    @State private var batch = 10_000

    /// Which addition chip is lit for a moment, having just been pressed.
    @State private var flashing: String?

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
                }
            }
            if let details = model.arrangementDetails {
                Text(details.about(inDepth: model.depthEnabled))
                    .font(.labBody(10))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
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

                VStack(alignment: .leading, spacing: 4) {
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
    }

    private var expandedContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            destinations
            costWarning
            // Before the arrangements, because it changes what every one of them is.
            depthControls
            presetChips
            wordControls
            population
            // Directly under how many there are, because it is the other half of the same question and
            // because this is where somebody looks for it. It used to sit between Reach and Gravity,
            // among the forces, called "Body size" — in a chamber named the Particle field, which is a
            // good way to make a control that exists impossible to find.
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
                // How much of the screen's height the circle is, which stays true however far the view is
                // zoomed. At the top of the range the finger reaches everything, which is worth saying rather
                // than showing as a number that stops meaning anything.
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

            // Said once, plainly, next to the switch it is about. This is by a very wide margin the most
            // expensive thing in the chamber, and nothing used to indicate that — so a crowd that would
            // have run at a thousand frames a second ran at five, and the only visible explanation was
            // that the app could not cope.
            Text("Collide is what costs: about a millisecond for every thousand bodies. Everything else "
                + "here is nearly free.")
                .font(.labBody(11))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)

            physics
            colourModes
            colourRamps
            shapeChoices
            backdropChoices
            viewControls
        }
    }

    /// The kinds of physics, each with its own numbers directly underneath it.
    ///
    /// Underneath, and not in a separate panel. Every one of these used to be a bare switch with everything
    /// about how it behaved written into the code as a constant — and when the numbers did arrive they
    /// arrived somewhere else, which is the same fault wearing a different hat. A switch you can turn on and
    /// then not adjust is somebody else's decision presented as a choice.
    ///
    /// Each set of numbers appears only when its switch is on, because five sliders that do nothing are
    /// worse than no sliders.
    private var physics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PHYSICS")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            switchAndNumbers(
                "Collide — bodies push each other apart",
                isOn: Binding(get: { model.collisionsEnabled }, set: { model.collisionsEnabled = $0 })
            ) {
                inlineSlider("How wide they count as", \.contactSize, 0 ... 24, step: 0.5) {
                    $0 <= 0 ? "automatic" : "\($0.formatted(.number.precision(.fractionLength(1)))) px"
                }
                inlineSlider("Bounciness", \.contactBounciness, 0 ... 1, step: 0.02)
                inlineSlider("Friction", \.contactFriction, 0 ... 1, step: 0.02)
                inlineSlider("Firmness", \.contactPasses, 1 ... 6, step: 1) {
                    "\(Int($0)) pass\(Int($0) == 1 ? "" : "es")"
                }
            }

            switchAndNumbers(
                "Trails — bodies leave a fading streak",
                isOn: Binding(get: { model.showTrails }, set: { model.showTrails = $0 })
            ) {
                // The length control, phrased as length rather than as the fade it actually is — a slider
                // that gets shorter as you drag it right is a puzzle, not a control.
                inlineSlider("How long they last", \.trailFade, 0.01 ... 1, step: 0.01) {
                    "\(Int((1 / max(0.01, $0)).rounded())) frames"
                }
                inlineSlider("How solid", \.trailOpacity, 0.02 ... 1, step: 0.02)
                inlineSlider("How thick", \.trailWidth, 0.1 ... 3, step: 0.1)
                // A different thing from the trail behind a body: a trail says where it has been, a streak
                // says how fast it is going now. A field of fast bodies drawn as dots reads as a static
                // scatter however quickly it is moving, because a dot has no direction.
                inlineSlider("Stretch with speed", \.streakLength, 0 ... 16, step: 0.5) {
                    $0 == 0 ? "round dots" : "\($0.formatted(.number.precision(.fractionLength(1)))) moments"
                }
            }

            switchAndNumbers(
                "Fluid — the crowd holds itself apart, and holds a surface",
                isOn: Binding(get: { model.fluidEnabled }, set: { model.fluidEnabled = $0 })
            ) {
                // Spacing rather than the crowding figure it is stored as. Crowding is bodies per square
                // pixel, which is a real quantity and a useless thing to drag.
                inlineSlider(
                    "Spacing",
                    Binding(
                        get: { (1 / max(1e-6, model.fluidRestDensity)).squareRoot() },
                        set: { model.fluidRestDensity = 1 / max(1e-6, $0 * $0) }
                    ),
                    2 ... 20,
                    step: 0.5
                ) { "\($0.formatted(.number.precision(.fractionLength(1)))) px" }
                inlineSlider("Reach", \.fluidSmoothing, 4 ... 48, step: 1) {
                    "\(Int($0)) px"
                }
                inlineSlider("Springiness", \.fluidStiffness, 0 ... 8, step: 0.1)
                inlineSlider("Thickness", \.fluidViscosity, 0 ... 0.6, step: 0.01)
                inlineSlider("Beading", \.fluidCohesion, 0 ... 1.2, step: 0.05)
            }

            switchAndNumbers(
                "Flock — bodies steer by their neighbours",
                isOn: Binding(get: { model.flockEnabled }, set: { model.flockEnabled = $0 })
            ) {
                inlineSlider("Keep apart", \.flockSeparation, 0 ... 1, step: 0.01)
                inlineSlider("Match direction", \.flockAlignment, 0 ... 0.3, step: 0.005)
                inlineSlider("Stay together", \.flockCohesion, 0 ... 0.02, step: 0.0005) {
                    $0.formatted(.number.precision(.fractionLength(4)))
                }
                inlineSlider("How far they see", \.flockVision, 10 ... 300, step: 5) {
                    "\(Int($0)) px"
                }
                inlineSlider("Personal space", \.flockPersonalSpace, 2 ... 200, step: 2) {
                    "\(Int($0)) px"
                }
                inlineSlider("How many take part", \.flockLimit, 20 ... 1200, step: 20) {
                    Int($0).formattedWithSeparators
                }
            }

            switchAndNumbers(
                "Gravity between bodies — everything pulls on everything",
                isOn: Binding(get: { model.nbodyEnabled }, set: { model.nbodyEnabled = $0 })
            ) {
                inlineSlider("Strength", \.bodyGravityStrength, 0 ... 12, step: 0.1)
                inlineSlider("Closest approach", \.bodyGravitySoftening, 1 ... 60, step: 1) {
                    "\(Int($0)) px"
                }
            }

            // The two drawn things. Shown whenever there is something drawn, or the tool is in hand —
            // otherwise the numbers for a wall would be hidden precisely when somebody was drawing one.
            if model.mouseMode == .current || model.hasPaintedCurrent {
                drawnSection(
                    "Painted wind",
                    detail: model.hasPaintedCurrent
                        ? "Drag across the field to paint which way the crowd should go."
                        : "Drag across the field to paint. Nothing is painted yet.",
                    clearTitle: "Wipe the wind",
                    canClear: model.hasPaintedCurrent,
                    clear: { model.clearCurrent() }
                ) {
                    inlineSlider("How hard it pushes", \.currentStrength, 0 ... 6, step: 0.05)
                    inlineSlider("Brush width", \.currentBrushRadius, 0.02 ... 0.6, step: 0.01)
                    inlineSlider("Brush strength", \.currentBrushStrength, 0.02 ... 1, step: 0.02)
                    inlineSlider("How finely", \.currentResolution, 4 ... 64, step: 4) {
                        "\(Int($0)) across"
                    }
                }
            }

            if model.mouseMode == .source || model.emitterCount > 0 {
                drawnSection(
                    "Sources",
                    detail: model.emitterCount > 0
                        ? "\(model.emitterCount) pouring. Drag on the field to place another, aimed the way "
                            + "you drag."
                        : "Drag on the field to place one, aimed the way you drag. It keeps pouring after you "
                            + "let go.",
                    clearTitle: "Remove them all",
                    canClear: model.emitterCount > 0,
                    clear: { model.clearEmitters() }
                ) {
                    inlineSlider("How fast it pours", \.sourceRate, 0 ... 1_200, step: 10) {
                        "\(Int($0))/s"
                    }
                    inlineSlider("How wide a fan", \.sourceSpread, 0 ... 3.14, step: 0.02) {
                        "\(Int($0 * 57.2958))°"
                    }
                    inlineSlider("How fast they leave", \.sourceSpeed, 0 ... 30, step: 0.5)
                    inlineSlider("Speed varies by", \.sourceSpeedVariation, 0 ... 1, step: 0.02)
                    inlineSlider("How long they last", \.sourceLifespan, 0 ... 600, step: 10) {
                        $0 <= 0 ? "forever" : "\(Int($0)) moments"
                    }
                    inlineSlider("How heavy", \.sourceWeight, 0.05 ... 12, step: 0.05)
                    inlineSlider("Colour", \.sourceHue, -1 ... 359, step: 1) {
                        $0 < 0 ? "a mixture" : "\(Int($0))°"
                    }

                    // One row per source, so a stray one can be stopped or removed without clearing them all.
                    if model.emitterCount > 0 {
                        ForEach(Array(model.emitterSummaries.enumerated()), id: \.offset) { entry in
                            HStack(spacing: 8) {
                                Text(entry.element)
                                    .font(.labBody(10))
                                    .foregroundStyle(Palette.subtleForeground)
                                Spacer(minLength: 8)
                                Button {
                                    model.setEmitterRunning(
                                        entry.element.hasSuffix("stopped"),
                                        at: entry.offset
                                    )
                                } label: {
                                    Image(
                                        systemName: entry.element.hasSuffix("stopped")
                                            ? "play.fill"
                                            : "pause.fill"
                                    )
                                    .font(.labBody(10, .semiBold))
                                    .foregroundStyle(Palette.muted)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    model.removeEmitter(at: entry.offset)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.labBody(10, .semiBold))
                                        .foregroundStyle(Palette.muted)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
            }

            if model.mouseMode == .wall || model.wallCount > 0 {
                drawnSection(
                    "Walls",
                    detail: model.wallCount > 0
                        ? "\(model.wallCount) drawn. Drag across the field to add another."
                        : "Drag across the field to draw one.",
                    clearTitle: "Remove them all",
                    canClear: model.wallCount > 0,
                    clear: { model.clearWalls() }
                ) {
                    inlineSlider("Bounciness", \.wallBounciness, 0 ... 1, step: 0.02)
                    inlineSlider("Friction", \.wallFriction, 0 ... 1, step: 0.02)
                    inlineSlider("Thickness", \.wallThickness, 1 ... 20, step: 0.5) {
                        "\($0.formatted(.number.precision(.fractionLength(1)))) px"
                    }
                }
            }

            switchAndNumbers(
                "Wind — eddies and channels filling the field",
                isOn: Binding(get: { model.flowEnabled }, set: { model.flowEnabled = $0 })
            ) {
                inlineSlider("Strength", \.flowStrength, 0 ... 3, step: 0.05)
                inlineSlider("Eddy size", \.flowScale, 20 ... 600, step: 10) { "\(Int($0)) px" }
                inlineSlider("How fast it changes", \.flowDrift, 0 ... 1, step: 0.02) {
                    $0 == 0 ? "still" : $0.formatted(.number.precision(.fractionLength(2)))
                }
            }
        }
    }

    /// A drawn thing: what it is, how much of it there is, its numbers, and a way to remove it.
    ///
    /// No switch, because these are not switched on — they exist because somebody drew them, and the only
    /// two questions are how they behave and how to get rid of them.
    @ViewBuilder
    private func drawnSection(
        _ title: String,
        detail: String,
        clearTitle: String,
        canClear: Bool,
        clear: @escaping () -> Void,
        @ViewBuilder numbers: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.labBody(11, .semiBold))
                        .foregroundStyle(Palette.foreground)
                    Text(detail)
                        .font(.labBody(10))
                        .foregroundStyle(Palette.subtleForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if canClear {
                    Button(action: clear) {
                        Text(clearTitle)
                            .font(.labBody(10, .semiBold))
                            .foregroundStyle(Palette.warn)
                            .padding(.horizontal, 9)
                            .frame(height: 26)
                            .background(Capsule().fill(Palette.warn.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                numbers()
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.primary.opacity(0.35))
                    .frame(width: 1.5)
            }
        }
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
                inlineSlider(
                    "Speed",
                    \.spinRate,
                    0.1 ... 5,
                    step: 0.1,
                    format: { "\($0.formatted(.number.precision(.fractionLength(1))))×" }
                )
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
        if let warning = SwarmCost.warning(bodies: model.bodyCount, collisions: model.collisionsEnabled)
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
                    toolButton("Turn", symbol: "rotate.3d", selected: model.turnsView) {
                        model.turnsView = true
                    }
                }
                ForEach(Self.tools, id: \.mode) { tool in
                    toolButton(tool.name, symbol: tool.symbol, selected: !isTurning && model.mouseMode == tool.mode) {
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
