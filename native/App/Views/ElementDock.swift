import CrucibleCore
import PhotosUI
import SwiftUI

/// The dock along the bottom: what you are painting with, how big, and what to do next.
///
/// Laid out like the web version — a drag handle, a title line that doubles as the open and
/// close control, and a body that slides up. Collapsed it shows only what you need while
/// drawing; opened it shows the full element set and the world's settings.
struct ElementDock: View {
    let model: SimulationModel
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
    /// Today's date in UTC, for the shared daily world.
    let today: String
    /// Whether this is the smaller lab: five materials, three brushes, and none of the rest. See `SimpleLab`.
    let isSimple: Bool

    /// What has been typed into the search box.
    @State private var search = ""
    /// Which category is being shown, or nothing for all of them.
    @State private var category: ElementCategory?
    @FocusState private var isSearching: Bool
    /// The photograph being chosen, while the picker is open.
    @State private var photo: PhotosPickerItem?


    /// What the closed tray shows: the short list in the smaller lab, the handful most reached for otherwise.
    private var favourites: [(id: ElementID, name: String)] {
        guard isSimple else { return Self.favourites }
        return SimpleLab.materials.map { (id: $0, name: model.definition(of: $0).name) }
    }

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
            if isOpen {
                expanded
            } else {
                // Only while closed, which is what it is for — the name says so. It used to show in both
                // states, and open it sat directly beneath the category filter showing a fixed dozen
                // materials that the filter has no effect on. Choose "Gases" and the row underneath
                // still reads sand, water, lava: it looks exactly like a filter that does not work.
                collapsedStrip
            }
            transport
        }
        .background(alignment: .top) {
            // A hairline along the top edge and a shadow beneath it, so the dock reads as
            // sitting in front of the simulation rather than printed on it.
            Rectangle()
                .fill(Palette.border)
                .frame(height: 1)
        }
        // No soft shadow under it any more. A shadow of that size is a blur pass of its own — the
        // compositor filtering a band of the screen every frame — and the hairline above already says the
        // dock is in front of the world rather than printed on it.
        .solidPanel(in: Rectangle())
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
        .accessibilityIdentifier("tray.handle")
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
                HStack(spacing: 6) {
                    Text(name(of: model.brushElement))
                        .font(.labDisplay(14))
                        .tracking(-0.2)
                        .foregroundStyle(Palette.foreground)
                    // The colour being painted in, when it is not the material's own, so it is not a surprise.
                    if model.brushTint != 0 {
                        Circle()
                            .fill(tintBinding.wrappedValue)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                            .accessibilityLabel("Painting in your own colour")
                    }
                }
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
            .accessibilityIdentifier("tray.arrow")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    /// The ways into the other panels, inside the tray where there is room to name them.
    private var destinations: some View {
        LabFlow(spacing: 6) {
            // First, because it is the one that changes every day and so the one worth noticing.
            destination("Today · \(model.dailySceneName(day: today))", "sun.max", action: {
                model.loadDailyScene(day: today)
            })
            destination("Scenes", "square.grid.2x2", action: onShowScenes)
            if !isSimple {
                destination("Kept", "tray.full", action: onShowSaves)
                destination("Invent", "wand.and.stars", action: onShowEditor)
                destination("Periodic", "atom", action: onShowPeriodic)
            }
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

    /// The full set, only while the tray is open.
    ///
    /// ## One scrolling area, with a floor under it
    ///
    /// This used to be a plain stack with the materials in a scrolling box of their own, and the
    /// materials disappeared entirely. Opening the tray showed the headings, the brushes, the search
    /// box, the categories — and then nothing where the fifty materials should have been.
    ///
    /// The cause is worth writing down because it is invisible and it will happen again. The tray's
    /// natural height is taller than what is left of a phone screen below the world, so something has
    /// to give. A scrolling box is the only thing in that stack with no height of its own, so it is the
    /// thing that gives — all of it, down to nothing, in silence. Everything above it looked perfect,
    /// which is why it read as the materials having failed to load rather than as a layout fault.
    ///
    /// So: one scrolling area for the whole tray, the materials laid out at their natural height inside
    /// it, and **a minimum height** — which is the part that actually fixes it. A maximum alone still
    /// permits nought.
    private var expanded: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                destinations
                brushRow
                // Sand art, a photograph turned into powder, the search box and the fifty-material filter are all for
                // somebody who wants the whole lab. In the smaller one they are not there to be found by accident.
                if !isSimple {
                    colourRow
                    searchRow
                    categoryRow
                }
                palette
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(minHeight: 220, maxHeight: 380)
        // No rubber-banding when it all fits, so a short tray does not feel broken.
        .scrollBounceBehavior(.basedOnSize)
        .labScrollEdges()
    }

    /// How a touch paints, and the eyedropper.
    ///
    /// Six shapes have existed in the engine since it was ported and not one of them was reachable —
    /// the brush was permanently a circle. Flood fill and replace in particular change what the tool
    /// is for rather than merely how it looks.
    private var brushRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BRUSH")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                ForEach(shapes, id: \.shape) { option in
                    let selected = model.brushShape == option.shape && !model.isUsingTool
                    Button {
                        // Choosing a shape puts down the eyedropper, the lasso or the thermometer, since each describes
                        // what the next touch will do and only one of them can be true.
                        model.chooseShape(option.shape)
                    } label: {
                        brushLabel(option.name, option.symbol, selected: selected)
                    }
                    .buttonStyle(.plain)
                }

                // The eyedropper, which is a one-shot rather than a shape: it takes the material
                // under the next touch and switches itself off again.
                Button {
                    model.toggleSampling()
                } label: {
                    brushLabel("Pick", "eyedropper", selected: model.isSampling)
                }
                .buttonStyle(.plain)

                if !isSimple {

                // Not painting at all: a loop drawn round something, to move it, copy it, heat it or delete it. The tray
                // closes, because the loop is drawn on the world and the tray is covering half of it.
                Button {
                    Haptics.selection()
                    model.toggleLasso()
                    if model.isLassoing { withAnimation(.easeOut(duration: 0.22)) { isOpen = false } }
                } label: {
                    brushLabel("Lasso", "lasso", selected: model.isLassoing)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool.lasso")
                .disabled(model.isFollowingRoom)
                .opacity(model.isFollowingRoom ? 0.4 : 1)

                // A thermometer pushed into one place, that stays and keeps reading.
                Button {
                    Haptics.selection()
                    model.beginPlacingThermometer()
                    if model.isPlacingThermometer { withAnimation(.easeOut(duration: 0.22)) { isOpen = false } }
                } label: {
                    brushLabel(
                        model.thermometer == nil ? "Thermometer" : "Move thermometer",
                        "thermometer.medium",
                        selected: model.isPlacingThermometer
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool.thermometer")

                // Not a shape either: it copies whichever shape is chosen, so it sits beside them as a switch.
                Button {
                    Haptics.selection()
                    model.kaleidoscopeFolds = model.kaleidoscopeFolds > 1 ? 1 : 6
                } label: {
                    brushLabel("Kaleidoscope", "snowflake", selected: model.kaleidoscopeFolds > 1)
                }
                .buttonStyle(.plain)
                }
            }
            if model.isSampling {
                Text("Tap the world to pick up whatever is there.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.warn)
            } else if model.isLassoing {
                Text("Draw a loop round something on the world. The bar above the tray says what can be done with it.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.isPlacingThermometer {
                Text("Tap where the thermometer should go. It stays there, reading, until you take it out.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.brushShape == .replace {
                Text("Replaces only what you start the drag on, so you can swap one material for another.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
            } else if model.brushShape == .fill {
                Text("Floods the whole connected space you tap.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
            }
            if model.kaleidoscopeFolds > 1 {
                Text("Every stroke is copied six times round the middle, so one line of sand comes out as a snowflake "
                    + "— which then falls apart, being sand.")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Sand art — painting in a colour of your own — and a photograph turned into powder.
    private var colourRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("COLOUR")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)
            LabFlow(spacing: 6) {
                ColorPicker(selection: tintBinding, supportsOpacity: false) {
                    Text(model.brushTint == 0 ? "Paint in a colour" : "Your colour")
                        .font(.labBody(12, model.brushTint == 0 ? .regular : .semiBold))
                        .foregroundStyle(Palette.foreground)
                }
                .fixedSize()
                .padding(.leading, 11)
                .padding(.trailing, 5)
                .frame(height: 32)
                .background(Capsule().fill(Color.white.opacity(0.10)))

                if model.brushTint != 0 {
                    Button {
                        Haptics.selection()
                        model.brushTint = 0
                    } label: {
                        brushLabel("Own colours", "arrow.uturn.backward", selected: false)
                    }
                    .buttonStyle(.plain)
                }

                // The label written out rather than borrowed from `brushLabel`: the picker builds it outside the
                // main thread's view of the world, where this view's own methods cannot be called.
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 5) {
                        Image(systemName: "photo")
                            .font(.labBody(11, .medium))
                        Text("Photo into powder")
                            .font(.labBody(12, .regular))
                    }
                    .foregroundStyle(Palette.foreground)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            }
            Text(colourNote)
                .font(.labBody(11))
                .foregroundStyle(model.photoProblem == nil ? Palette.subtleForeground : Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: photo) { _, chosen in
            guard let chosen else { return }
            Task { @MainActor in
                // Loaded as data and made into a picture here, which is the one form every source of photographs is
                // guaranteed to offer.
                if let data = try? await chosen.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    model.placePhoto(image)
                    Haptics.firm()
                    withAnimation(.easeOut(duration: 0.22)) { isOpen = false }
                }
                photo = nil
            }
        }
    }

    /// What the colour row is for, or what went wrong with the last photograph.
    private var colourNote: String {
        if let problem = model.photoProblem { return problem }
        if model.brushTint != 0 {
            return "Everything you paint is this colour now, and stays it as it falls. Flood a layer with the same "
                + "material to recolour it."
        }
        return "Choose a colour for sand art, or turn a photo into a picture made of real sand, water and snow. "
            + "It holds still until you press play."
    }

    /// The colour picker's view of the brush colour. With no colour of its own chosen, it starts from the material's.
    private var tintBinding: Binding<Color> {
        Binding(
            get: {
                guard let channels = PowderEngine.tintChannels(model.brushTint) else {
                    return model.color(of: model.brushElement == Element.empty ? Element.sand : model.brushElement)
                }
                return Color(
                    .sRGB,
                    red: Double(channels.red) / 255,
                    green: Double(channels.green) / 255,
                    blue: Double(channels.blue) / 255,
                    opacity: 1
                )
            },
            set: { chosen in
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard UIColor(chosen).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
                model.brushTint = PowderEngine.tintWord(red: byte(red), green: byte(green), blue: byte(blue))
            }
        )
    }

    private func brushLabel(_ title: String, _ symbol: String, selected: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.labBody(11, .medium))
            Text(title)
                .font(.labBody(12, selected ? .semiBold : .regular))
        }
        .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10)))
    }

    /// The brushes offered: three in the smaller lab, all six otherwise.
    private var shapes: [(shape: BrushShape, name: String, symbol: String)] {
        guard isSimple else { return Self.shapes }
        return Self.shapes.filter { SimpleLab.shapes.contains($0.shape) }
    }

    private static let shapes: [(shape: BrushShape, name: String, symbol: String)] = [
        (.circle, "Round", "circle.fill"),
        (.square, "Square", "square.fill"),
        (.spray, "Spray", "aqi.medium"),
        (.line, "Line", "line.diagonal"),
        (.fill, "Flood", "drop.fill"),
        (.replace, "Replace", "arrow.2.squarepath"),
    ]

    /// The search box.
    ///
    /// Worth having rather than relying on the groups below: there are fifty built-in materials and
    /// up to fifty invented ones, and someone who knows they want obsidian should not have to
    /// remember which heading it lives under.
    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.labBody(12))
                .foregroundStyle(Palette.subtleForeground)
            TextField("Search materials", text: $search)
                .font(.labBody(13))
                .foregroundStyle(Palette.foreground)
                .focused($isSearching)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.labBody(13))
                        .foregroundStyle(Palette.subtleForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(Capsule().stroke(Palette.border, lineWidth: 1))
        )
    }

    /// The category filter.
    ///
    /// Hidden while searching, because a search already spans everything and leaving a category
    /// selected would silently hide matches — which reads as the search being broken.
    @ViewBuilder
    private var categoryRow: some View {
        if search.trimmingCharacters(in: .whitespaces).isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, "All")
                    ForEach(model.populatedCategories, id: \.self) { option in
                        categoryChip(option, Self.categoryTitle(option))
                    }
                }
            }
            .labScrollEdges()
        }
    }

    private func categoryChip(_ option: ElementCategory?, _ title: String) -> some View {
        let selected = category == option
        return Button {
            Haptics.selection()
            category = option
        } label: {
            Text(title)
                .font(.labBody(12, selected ? .semiBold : .regular))
                .foregroundStyle(selected ? Palette.primaryForeground : Palette.muted)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    /// "Custom" is the engine's word for it; "Yours" is what it is.
    private static func categoryTitle(_ category: ElementCategory) -> String {
        category == .custom ? "Yours" : category.rawValue
    }

    /// The materials themselves.
    private var palette: some View {
        // Read through paletteVersion so that inventing or deleting a material rebuilds this. The
        // registry is a class, and SwiftUI cannot see an edit inside one.
        let _ = paletteVersion
        let matches = isSimple
            ? SimpleLab.materials.map { model.definition(of: $0) }
            : model.paletteElements(category: category, search: search)

        // No scrolling box of its own — the tray around it does the scrolling. Two nested ones would
        // fight over a drag, and the inner one collapsing to nothing is exactly what hid all fifty
        // materials.
        return Group {
            if matches.isEmpty {
                Text("Nothing matches “\(search.trimmingCharacters(in: .whitespaces))”.")
                    .font(.labBody(12))
                    .foregroundStyle(Palette.subtleForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 84), spacing: 6)],
                    spacing: 6
                ) {
                    ForEach(matches, id: \.id) { element in
                        chip(element.id, element.name, wide: true)
                    }
                }
            }
        }
    }

    /// The favourites row, always visible.
    private var collapsedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(favourites, id: \.id) { item in
                    chip(item.id, item.name, wide: false)
                }
                chip(Element.empty, "Erase", wide: false)
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 38)
        .labScrollEdges()
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

            // Back through the last little while, beside play because it is about time too. Greyed out until there is
            // something to go back to — the first moment is kept about half a second in.
            Button {
                Haptics.tap()
                model.beginRewind()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.labBody(13, .medium))
                    .foregroundStyle(model.isRewinding ? Palette.primaryForeground : Palette.muted)
                    .frame(width: 40, height: 36)
                    .background(Circle().fill(model.isRewinding ? Palette.primary : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(!model.canRewind || model.isRewinding)
            .opacity(model.canRewind || model.isRewinding ? 1 : 0.35)
            .accessibilityLabel("Rewind")
            .accessibilityIdentifier("tray.rewind")
            .accessibilityHint("Go back through the last few seconds, and carry on from any moment")

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

            iconButton("trash", "Clear") {
                Haptics.firm()
                model.clear()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func chip(_ id: ElementID, _ name: String, wide: Bool) -> some View {
        let selected = model.brushElement == id
        return Button {
            Haptics.selection()
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
        .accessibilityIdentifier("material.\(name)")
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
