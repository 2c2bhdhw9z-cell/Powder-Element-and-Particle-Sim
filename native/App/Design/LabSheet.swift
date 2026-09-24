import SwiftUI

/// The chrome every panel in the lab shares.
///
/// ## Why not the system's own sheet furniture
///
/// The app's panels were built out of `NavigationStack` and `Form`, which is the quickest way to get
/// something that works and looks like the iOS Settings app: inset grey rows on a lighter grey
/// background, a bar with a title. Crucible does not look like that. It is a near-black room, and its
/// panels are translucent black glass with a grab handle and a rounded top, sitting over the world
/// rather than replacing it.
///
/// So this is the reference implementation's sheet, measured from its stylesheet:
///
///   - the panel is black at seven tenths under a heavy blur, outlined at sixteen percent white;
///   - the top corners are rounded by twenty-eight points and the bottom ones not at all, because it
///     is anchored to the bottom edge;
///   - a grab handle above the title, six points tall and forty-eight wide, at forty percent white;
///   - the title in the display face, and a forty-four point round close button;
///   - dragging down more than eighty-eight points closes it, and anything less springs back.
///
/// The drag is the part worth having rather than leaving to the system: the reference dismisses on a
/// deliberate pull and springs back otherwise, and the threshold is what makes it feel intentional
/// rather than twitchy.
struct LabSheet<Content: View>: View {
    let title: String
    /// A line under the title, where one helps.
    var subtitle: String?
    let glass: GlassLevel
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var dragOffset: CGFloat = 0

    /// How far down the sheet has to be pulled before it closes.
    private static var dismissDistance: CGFloat { 88 }

    var body: some View {
        VStack(spacing: 0) {
            handle
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(panelBackground)
        .overlay(alignment: .top) {
            RoundedCorners(radius: 28, corners: [.topLeft, .topRight])
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .clipShape(RoundedCorners(radius: 28, corners: [.topLeft, .topRight]))
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Downward only. Dragging up would let the panel lift off the bottom edge and
                    // show the world underneath it, which looks like a rendering fault.
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > Self.dismissDistance {
                        dismiss()
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { dragOffset = 0 }
                    }
                }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .tint(Palette.primary)
        .preferredColorScheme(.dark)
    }

    // MARK: Chrome

    private var handle: some View {
        Capsule()
            .fill(Color.white.opacity(0.4))
            .frame(width: 48, height: 6)
            .padding(.top, 10)
            .padding(.bottom, 6)
            // The whole strip is tappable, not just the bar, because a six-point target is not one.
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.labDisplay(16))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(.labBody(11))
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.labBody(14, .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var panelBackground: some View {
        switch glass {
        case .flat:
            Palette.elevated
        case .subtle:
            Color.black.opacity(0.7).background(.ultraThinMaterial)
        case .full:
            Color.black.opacity(0.7).background(.regularMaterial)
        }
    }
}

/// A shape with only some corners rounded.
///
/// SwiftUI can round all four or none. A sheet anchored to the bottom of the screen wants two, and
/// rounding the bottom pair leaves two slivers of the world showing through at the very edge.
struct RoundedCorners: Shape {
    let radius: CGFloat
    let corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        Path(
            UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: corners,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )
    }
}

// MARK: - The pieces panels are built from
//
// Enough to replace what `Form` was providing, in the lab's own language rather than the system's.

/// A titled group of controls.
struct LabGroup<Content: View>: View {
    let title: String?
    /// A line of explanation under the group, where one is worth having.
    var footnote: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.labBody(10, .semiBold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.subtleForeground)
            }
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            if let footnote {
                Text(footnote)
                    .font(.labBody(11))
                    .foregroundStyle(Palette.subtleForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A label with a value on the right.
struct LabRow: View {
    let label: String
    let value: String
    var tint: Color = Palette.foreground

    var body: some View {
        HStack {
            Text(label)
                .font(.labBody(13))
                .foregroundStyle(Palette.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(.labNumeric(13))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}

/// A slider with its label and current value above it.
struct LabSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
                Spacer(minLength: 12)
                Text(format(value))
                    .font(.labNumeric(12))
                    .foregroundStyle(Palette.muted)
            }
            if step > 0 {
                Slider(value: $value, in: range, step: step) { Text(label) }
            } else {
                Slider(value: $value, in: range) { Text(label) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A switch with a label.
struct LabToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.labBody(13))
                .foregroundStyle(Palette.foreground)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}

/// A row that does something when tapped.
struct LabAction: View {
    let label: String
    var detail: String?
    var symbol: String?
    var isDestructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.labBody(13, .medium))
                        .foregroundStyle(isDestructive ? Palette.danger : Palette.muted)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.labBody(13))
                        .foregroundStyle(isDestructive ? Palette.danger : Palette.foreground)
                    if let detail {
                        Text(detail)
                            .font(.labBody(11))
                            .foregroundStyle(Palette.subtleForeground)
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row of choices, one of which is selected.
///
/// Used instead of the system's segmented control, which draws its own light background and a
/// sliding white thumb — both of which look like a different app in this interface.
struct LabChoice<Value: Hashable>: View {
    let label: String?
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let label {
                Text(label)
                    .font(.labBody(13))
                    .foregroundStyle(Palette.foreground)
            }
            // Wraps rather than scrolling, so nothing is hidden off the edge of a panel.
            LabFlow(spacing: 6) {
                ForEach(options, id: \.value) { option in
                    let selected = selection == option.value
                    Button {
                        selection = option.value
                    } label: {
                        Text(option.title)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Lays children out in rows, wrapping when one runs out of width.
///
/// A plain `HStack` pushes chips off the edge and a `LazyVGrid` forces every chip to the same width,
/// which looks wrong when the labels are "Up" and "Sideways".
///
/// ## The bug that was in here, because it will look tempting to undo
///
/// Measuring and placing have to agree about **one** width, and they did not.
///
/// `sizeThatFits` worked out its rows against the width it was offered, and then reported the width it
/// had actually used — the width of its widest row, which is narrower. The parent, reasonably, then
/// placed it in a box exactly that narrow. So `placeSubviews` decided where to wrap against a different,
/// tighter width than the one the height was calculated from. A row that ended exactly at the edge —
/// and a fraction of a point of text measurement is enough — wrapped one more time than the reported
/// height had room for, and that extra row drew straight over whatever came next.
///
/// It was visible in the settings panel as "Heaviness" sitting on top of "Temperatures in", and "None"
/// sitting on top of the wind slider. Not a clipped row, not a gap: two controls overlapping, which
/// reads as the panel being broken rather than as arithmetic being a hair out.
///
/// So it now reports the width it was *offered*, so that placement happens in exactly the box the
/// height was computed for — plus half a point of slack in both, so an exact fit stays an exact fit.
/// Returning the tight width looks tidier and is what caused this.
struct LabFlow: Layout {
    var spacing: CGFloat = 6

    /// Half a point, so a row that fits precisely is not pushed onto the next one by a rounding
    /// difference in how a piece of text was measured.
    private static let slack: CGFloat = 0.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > limit + Self.slack {
                totalHeight += rowHeight + spacing
                widest = max(widest, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        widest = max(widest, rowWidth)

        // The offered width, not the used one. Every caller puts this in a leading-aligned stack, so
        // filling the width changes nothing visible — and it is what makes the box these rows are placed
        // in the same box their height was measured against.
        return CGSize(width: limit.isFinite ? limit : widest, height: totalHeight + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // The same comparison as above, against the same width, with the same slack.
            if x > bounds.minX, x + size.width > bounds.maxX + Self.slack {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A hairline between rows inside a group.
struct LabDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}
