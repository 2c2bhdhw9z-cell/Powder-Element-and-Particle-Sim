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

    /// How many bodies a tap of the add button scatters in.
    @State private var batch = 10_000

    /// The eighteen arrangements, as chips rather than only inside a sheet.
    ///
    /// They are the quickest thing in the chamber to want and the reference keeps them here, one tap
    /// away, rather than behind a panel. The sheet stays as well — it has room to explain them.
    private var presetChips: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ARRANGEMENTS")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                Button {
                    model.loadDailyArrangement(day: today)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max")
                            .font(.labBody(11, .medium))
                        Text("Today")
                            .font(.labBody(12, .semiBold))
                    }
                    .foregroundStyle(Palette.primaryForeground)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)

                ForEach(ParticleFieldModel.presets, id: \.id) { preset in
                    Button {
                        model.loadPreset(preset.id)
                    } label: {
                        Text(preset.name)
                            .font(.labBody(12, .medium))
                            .foregroundStyle(Palette.foreground)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
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

            HStack(spacing: 6) {
                Button {
                    model.spawn(batch)
                } label: {
                    Text("Add \(Self.shortCount(batch))")
                        .font(.labBody(12, .semiBold))
                        .foregroundStyle(Palette.primaryForeground)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Capsule().fill(Palette.primary))
                }
                .buttonStyle(.plain)
                .disabled(model.remainingRoom == 0)
                .opacity(model.remainingRoom == 0 ? 0.4 : 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ParticleFieldModel.batchChoices, id: \.self) { choice in
                            countChip(Self.shortCount(choice), selected: batch == choice) {
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
                            model.maxBodies = choice
                        }
                    }
                }
            }
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
            destination("Presets", "square.grid.2x2", action: onShowPresets)
            // Pours the field into the powder world. Worth a named button rather than an icon: it moves
            // everything to the other chamber, which is not a thing to discover by accident.
            destination("Settle into powder", "arrow.down.to.line", action: onSettleEverything)
            destination("Drop a well", "circle.circle", action: { model.dropWell() })
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
        .labScrollEdges(glass)
    }

    private var expandedContents: some View {
        VStack(alignment: .leading, spacing: 14) {
            destinations
            costWarning
            presetChips
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
                value: Binding(get: { model.mouseRadius }, set: { model.mouseRadius = $0 }),
                range: 40 ... 820,
                // At the top of the range the physics treats the reach as unlimited, which is
                // worth saying rather than showing as a number that stops meaning anything.
                display: { model.mouseRadius >= 800 ? "whole field" : "\(Int($0))" }
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

            // Three kinds of physics that change what the field *is* rather than how it looks, which
            // is why they sit apart from the sliders.
            //
            // Two of these showed here for a long time and did nothing at all — the engine saved them,
            // reset them when the field was cleared, and never read either one. They work now, and the
            // labels say what they actually do rather than what they were going to do.
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Fluid — the crowd holds itself apart, and holds a surface", isOn: Binding(
                    get: { model.fluidEnabled },
                    set: { model.fluidEnabled = $0 }
                ))
                Toggle("Flock — bodies steer by their neighbours", isOn: Binding(
                    get: { model.flockEnabled },
                    set: { model.flockEnabled = $0 }
                ))
                Toggle("Gravity between bodies — everything pulls on everything", isOn: Binding(
                    get: { model.nbodyEnabled },
                    set: { model.nbodyEnabled = $0 }
                ))
                Toggle("Wind — eddies and channels filling the field", isOn: Binding(
                    get: { model.flowEnabled },
                    set: { model.flowEnabled = $0 }
                ))
            }
            .font(.labBody(11))
            .foregroundStyle(Palette.muted)
            .tint(Palette.primary)

            colourModes
            colourRamps
            shapeChoices
            backdropChoices
            viewControls
        }
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

            Text("Pinch to zoom, drag with two fingers to move, twist to turn.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)

            LabSlider(
                label: "Tilt",
                value: Binding(get: { model.cameraPitch }, set: { model.cameraPitch = $0 }),
                range: 0 ... ParticleCamera.maximumPitch,
                step: 1
            ) { "\(Int($0.rounded()))°" }

            Toggle(isOn: Binding(
                get: { model.cameraAutoOrbit },
                set: { model.cameraAutoOrbit = $0 }
            )) {
                Text("Turn by itself")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.muted)
            }
            .tint(Palette.primary)

            HStack(spacing: 8) {
                Button {
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
        .labScrollEdges(glass)
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

            // How far a touch reaches — this chamber's equivalent of brush size, and the same control
            // in the same place, which is what this file's opening comment promises and what the
            // colour-mode menu that used to sit here was breaking.
            HStack(spacing: 8) {
                Image(systemName: "circle.dotted")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
                Slider(
                    value: Binding(get: { model.mouseRadius }, set: { model.mouseRadius = $0 }),
                    in: 40 ... 820
                )
                .tint(Palette.primary)
                Text(model.mouseRadius >= 800 ? "all" : "\(Int(model.mouseRadius))")
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 26, alignment: .trailing)
            }
            .accessibilityLabel("How far a touch reaches")

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
