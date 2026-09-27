import CrucibleCore
import SwiftUI
// For turning a chosen colour into the engine's packed form.
import UIKit

// MARK: - Marks drawn over the world

/// What the tools draw over the powder world: the lasso's loop, the outline of a piece being carried, and the
/// thermometer.
///
/// Shapes rather than a canvas, so the drawing is worked out from plain values handed to it and never reaches back into
/// the model from wherever SwiftUI decides to draw. Only the thermometer's close button can be touched; everything
/// else lets touches through to the world, which is what the loop is being drawn on.
struct PowderWorldMarks: View {
    let model: SimulationModel
    let unit: TemperatureUnit

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let grid = CGSize(width: max(1, model.gridSize.width), height: max(1, model.gridSize.height))
            ZStack(alignment: .topLeading) {
                loop(in: size, grid: grid)
                carried(in: size, grid: grid)
                if let probe = model.thermometer {
                    ThermometerPin(model: model, probe: probe, unit: unit, viewSize: size, grid: grid)
                }
            }
        }
    }

    /// The loop being drawn, or closed round what it holds.
    @ViewBuilder
    private func loop(in size: CGSize, grid: CGSize) -> some View {
        if !model.lassoLoop.isEmpty {
            let points = model.lassoLoop.map { CGPoint(x: $0.x, y: $0.y) }
            let closed = !model.isDrawingLasso
            // Faint while a piece lifted from inside it is being carried somewhere else: it marks where the piece came
            // from, not what is selected.
            let faint = model.lassoPlacing == .move
            ZStack {
                if closed, !faint {
                    LassoShape(points: points, grid: grid, closed: true)
                        .fill(Color.white.opacity(0.08))
                }
                // Twice, dark under light, so the line shows over sand and over snow alike.
                LassoShape(points: points, grid: grid, closed: closed)
                    .stroke(Color.black.opacity(faint ? 0.25 : 0.6), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                LassoShape(points: points, grid: grid, closed: closed)
                    .stroke(
                        Color.white.opacity(faint ? 0.35 : 0.95),
                        style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [6, 4])
                    )
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    /// The outline of a lifted piece, under the finger that is carrying it.
    @ViewBuilder
    private func carried(in size: CGSize, grid: CGSize) -> some View {
        if model.lassoPlacing != nil, let at = model.heldAt, !model.heldOutline.isEmpty {
            let points = model.heldOutline.map { CGPoint(x: $0.x + Double(at.x), y: $0.y + Double(at.y)) }
            ZStack {
                LassoShape(points: points, grid: grid, closed: true)
                    .fill(Palette.primary.opacity(0.18))
                LassoShape(points: points, grid: grid, closed: true)
                    .stroke(Color.black.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                LassoShape(points: points, grid: grid, closed: true)
                    .stroke(Palette.primary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }
}

/// A loop through points given in the grid's cells, drawn at whatever size the world is shown.
struct LassoShape: Shape {
    let points: [CGPoint]
    let grid: CGSize
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, grid.width > 0, grid.height > 0 else { return path }
        let sx = rect.width / grid.width
        let sy = rect.height / grid.height
        path.move(to: CGPoint(x: rect.minX + first.x * sx, y: rect.minY + first.y * sy))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + point.x * sx, y: rect.minY + point.y * sy))
        }
        if closed { path.closeSubpath() }
        return path
    }
}

/// A small line graph of a run of readings, lowest at the bottom and highest at the top.
struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, let lowest = finite.min(), let highest = finite.max() else { return path }
        // A flat line through the middle when nothing has changed, rather than dividing by nought.
        let span = highest - lowest
        let step = rect.width / CGFloat(finite.count - 1)
        for (index, value) in finite.enumerated() {
            let fraction = span > 0 ? (value - lowest) / span : 0.5
            let point = CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.maxY - CGFloat(fraction) * rect.height)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The thermometer: a dot where it was pushed in, and beside it the reading, a little graph of what it has read, and a
/// button to take it out.
struct ThermometerPin: View {
    let model: SimulationModel
    let probe: PowderThermometer
    let unit: TemperatureUnit
    let viewSize: CGSize
    let grid: CGSize

    private static let cardWidth: CGFloat = 132
    private static let cardHeight: CGFloat = 62

    var body: some View {
        let x = (CGFloat(probe.x) + 0.5) / grid.width * viewSize.width
        let y = (CGFloat(probe.y) + 0.5) / grid.height * viewSize.height
        // Above the dot, unless that would be off the top of the world; kept inside it from side to side.
        let above = y - 14 - Self.cardHeight >= 0
        let cardX = min(max(Self.cardWidth / 2 + 4, x), max(Self.cardWidth / 2 + 4, viewSize.width - Self.cardWidth / 2 - 4))
        let cardY = above ? y - 14 - Self.cardHeight / 2 : y + 14 + Self.cardHeight / 2

        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Palette.danger)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 1.5)
                .position(x: x, y: y)
                .allowsHitTesting(false)

            card
                .frame(width: Self.cardWidth, height: Self.cardHeight)
                .position(x: cardX, y: cardY)
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.labBody(10, .medium))
                        .foregroundStyle(Palette.danger)
                    Text(probe.current.map { unit.format(celsius: $0) } ?? "—")
                        .font(.labNumeric(13))
                        .foregroundStyle(Palette.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                SparklineShape(values: probe.readings)
                    .stroke(Palette.danger, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                    .frame(height: 16)
                Text(range)
                    .font(.labNumeric(9))
                    .foregroundStyle(Palette.subtleForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Button {
                Haptics.tap()
                model.removeThermometer()
            } label: {
                Image(systemName: "xmark")
                    .font(.labBody(10, .semiBold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Take the thermometer out")
        }
        .padding(.leading, 9)
        .padding(.trailing, 2)
        .padding(.vertical, 6)
        .solidPanel(in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Thermometer")
        .accessibilityValue(probe.current.map { "Reads \(unit.format(celsius: $0))" } ?? "Not read yet")
    }

    /// The lowest and highest it has read, so a graph of a few degrees is not mistaken for one of hundreds.
    private var range: String {
        guard probe.lowest.isFinite, probe.highest.isFinite else { return "reading…" }
        if probe.lowest == probe.highest { return "steady" }
        return "\(unit.format(celsius: probe.lowest)) to \(unit.format(celsius: probe.highest))"
    }
}

// MARK: - Bars along the bottom of the world

/// Whatever tool bar the powder world needs at the moment: the rewind's slider, or the lasso's actions.
struct PowderToolBars: View {
    let model: SimulationModel

    var body: some View {
        if model.isRewinding {
            RewindBar(model: model)
        } else if model.isLassoing {
            LassoBar(model: model)
        }
    }
}

/// The rewind: a slider back through the last little while, with the world held still at whichever moment it is on.
///
/// Left is the past, right is now, as on every video player. Nothing is lost by scrubbing: "Back to now" puts the world
/// exactly as it was, and only "Carry on from here" lets go of what came after — and even that is one undo away.
struct RewindBar: View {
    let model: SimulationModel

    var body: some View {
        let count = max(1, model.rewindCount)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Rewind", systemImage: "backward.fill")
                    .font(.labBody(12, .semiBold))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 8)
                Text(model.rewindStepsBack == 0 ? "Now" : "\(Self.seconds(model.rewindSecondsBack)) ago")
                    .font(.labNumeric(12))
                    .foregroundStyle(model.rewindStepsBack == 0 ? Palette.muted : Palette.foreground)
            }
            HStack(spacing: 6) {
                stepButton("chevron.left", "A moment further back", enabled: model.rewindStepsBack < model.rewindCount) {
                    model.scrubRewind(to: model.rewindStepsBack + 1)
                }
                Slider(
                    value: Binding(
                        get: { Double(count - min(count, model.rewindStepsBack)) },
                        set: { value in
                            guard value.isFinite else { return }
                            model.scrubRewind(to: count - Int(value.rounded()))
                        }
                    ),
                    in: 0 ... Double(count),
                    step: 1
                ) {
                    Text("How far back")
                }
                .tint(Palette.primary)
                stepButton("chevron.right", "A moment nearer now", enabled: model.rewindStepsBack > 0) {
                    model.scrubRewind(to: model.rewindStepsBack - 1)
                }
            }
            HStack(spacing: 8) {
                Text("Up to \(Self.seconds(model.rewindReachSeconds)) back")
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
                Spacer(minLength: 6)
                chip("Back to now", selected: false, id: "rewind.now") { model.finishRewind(keeping: false) }
                chip("Carry on from here", selected: true, id: "rewind.keep") { model.finishRewind(keeping: true) }
                    .disabled(model.rewindStepsBack == 0)
                    .opacity(model.rewindStepsBack == 0 ? 0.4 : 1)
            }
        }
        .padding(12)
        .solidPanel(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    /// Seconds, as somebody would say them: tenths below ten, whole ones above, minutes past a minute.
    static func seconds(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "0 s" }
        if value < 10 { return "\(value.formatted(.number.precision(.fractionLength(1)))) s" }
        if value < 60 { return "\(Int(value.rounded())) s" }
        let whole = Int(value.rounded())
        return "\(whole / 60) min \(whole % 60) s"
    }

    private func stepButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.labBody(12, .semiBold))
                .foregroundStyle(enabled ? Palette.foreground : Palette.subtleForeground)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The lasso's actions: what to do with what the loop holds, or where to put what it lifted.
struct LassoBar: View {
    let model: SimulationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.labBody(12))
                .foregroundStyle(model.lassoProblem == nil ? Palette.foreground : Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            LabFlow(spacing: 6) {
                switch model.lassoPlacing {
                case .move:
                    chip("Put it back", symbol: "arrow.uturn.backward", selected: false) { model.putLassoBack() }
                case .copy:
                    chip("Stop copying", symbol: "checkmark", selected: true) { model.stopCopying() }
                case nil:
                    if model.hasLassoSelection {
                        chip("Move", symbol: "arrow.up.and.down.and.arrow.left.and.right", selected: false) {
                            model.liftLasso(copying: false)
                        }
                        chip("Copy", symbol: "plus.square.on.square", selected: false) { model.liftLasso(copying: true) }
                        chip("Heat", symbol: "flame", selected: false) {
                            model.warmLasso(by: SimulationModel.lassoWarmth)
                        }
                        chip("Cool", symbol: "snowflake", selected: false) {
                            model.warmLasso(by: -SimulationModel.lassoWarmth)
                        }
                        recolour
                        chip("Delete", symbol: "trash", selected: false) { model.deleteLasso() }
                    }
                    chip("Done", symbol: "checkmark", selected: true, id: "lasso.done") { model.finishLasso() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .solidPanel(in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }

    private var message: String {
        switch model.lassoPlacing {
        case .move:
            return "Drag it, or tap, to where it should go."
        case .copy:
            return "Drag or tap to put a copy down, as many as you like. Each one can be undone by itself."
        case nil:
            if let problem = model.lassoProblem { return problem }
            if model.hasLassoSelection {
                let cells = model.lassoSelection.count
                return "\(cells.formatted()) cells inside the loop. Heat and cool change them by "
                    + "\(Int(SimulationModel.lassoWarmth)) degrees a press."
            }
            return "Draw a loop round something to move it, copy it, heat it, cool it, recolour it or delete it."
        }
    }

    /// The colour of what the loop holds, and a way to change it — the system's own colour picker, which recolours
    /// everything inside as the colour is chosen.
    private var recolour: some View {
        ColorPicker(
            selection: Binding(
                get: { heldColour },
                set: { chosen in
                    guard let word = TintColour.word(of: chosen) else { return }
                    model.recolourLasso(word)
                }
            ),
            supportsOpacity: false
        ) {
            Text("Colour")
                .font(.labBody(12))
                .foregroundStyle(Palette.foreground)
        }
        .fixedSize()
        .padding(.leading, 11)
        .padding(.trailing, 5)
        .frame(height: 32)
        .background(Capsule().fill(Color.white.opacity(0.10)))
    }

    /// The colour the first grain inside the loop is shown in: its own colour if it has one, or its material's.
    private var heldColour: Color {
        let engine = model.engine
        for cell in model.lassoSelection where cell >= 0 && cell < engine.cellCount {
            let id = engine.type[cell]
            guard id != Element.empty else { continue }
            if let colour = TintColour.color(of: engine.tint[cell]) { return colour }
            return model.color(of: id)
        }
        return .white
    }
}

/// A rounded button in the lab's style, as the brush row's.
///
/// - Parameter id: a name the app's own tap-through test finds it by. Nobody sees or hears it.
@MainActor
private func chip(
    _ title: String,
    symbol: String? = nil,
    selected: Bool,
    id: String? = nil,
    action: @escaping () -> Void
) -> some View {
    Button {
        Haptics.tap()
        action()
    } label: {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.labBody(11, .medium))
            }
            Text(title)
                .font(.labBody(12, selected ? .semiBold : .regular))
        }
        .foregroundStyle(selected ? Palette.primaryForeground : Palette.foreground)
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Capsule().fill(selected ? Palette.primary : Color.white.opacity(0.10)))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(id ?? "chip.\(title)")
}

// MARK: - Colours

/// Between a colour as SwiftUI holds one and a colour as the engine packs one for a grain.
enum TintColour {
    /// A chosen colour, packed for the engine. Nothing if it cannot be read as red, green and blue.
    @MainActor
    static func word(of colour: Color) -> UInt32? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(colour).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        func byte(_ value: CGFloat) -> Int { Int((min(1, max(0, value.isFinite ? value : 0)) * 255).rounded()) }
        return PowderEngine.tintWord(red: byte(red), green: byte(green), blue: byte(blue))
    }

    /// A grain's own colour as SwiftUI shows one, or nothing for a grain in its material's colour.
    static func color(of word: UInt32) -> Color? {
        guard let channels = PowderEngine.tintChannels(word) else { return nil }
        return Color(
            .sRGB,
            red: Double(channels.red) / 255,
            green: Double(channels.green) / 255,
            blue: Double(channels.blue) / 255,
            opacity: 1
        )
    }
}
