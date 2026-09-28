import CrucibleCore
import SwiftUI

/// The movie studio, in the field's tray: stops to look from, how to travel between them, and play or record.
///
/// ## How it is used
///
/// Put the view somewhere worth looking from and add it as a stop. Move the view, add another. Each stop after the
/// first says how long the journey to it takes, how fast the world runs on the way and while there — slow motion is
/// anything below one — how long to stay, and what to say while there. Play runs it on the world; Record a clip runs it
/// and writes the world, and nothing else on the screen, into a video to keep or send.
///
/// A separate view from the tray, because the tray is already one of the largest views in the app and every part of
/// it is rebuilt together: a text field for a caption, typed into, would otherwise rebuild the whole tray per letter.
struct FieldMovieControls: View {
    let model: ParticleFieldModel

    private static let travels: [Double] = [1, 2, 3, 5, 8, 12]
    private static let holds: [Double] = [0, 1, 2, 4, 8]
    private static let speeds: [Double] = [0.1, 0.25, 0.5, 1, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOVIE")
                .font(.labBody(10, .semiBold))
                .tracking(0.8)
                .foregroundStyle(Palette.subtleForeground)

            Text(summary)
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(model.movie.stops.enumerated()), id: \.offset) { index, stop in
                stopRow(index, stop)
            }

            LabFlow(spacing: 6) {
                pill(
                    model.movie.isEmpty ? "Add this view as the first stop" : "Add this view as a stop",
                    symbol: "plus.viewfinder",
                    lit: false,
                    enabled: !model.isPlayingMovie && model.movie.stops.count < ParticleMovie.mostStops
                ) {
                    Haptics.selection()
                    model.addMovieStop()
                }
                .accessibilityIdentifier("movie.add")

                if model.isPlayingMovie {
                    pill(model.isRecordingClip ? "Stop recording" : "Stop", symbol: "stop.fill", lit: true, enabled: true) {
                        Haptics.firm()
                        model.stopMovie()
                    }
                    .accessibilityIdentifier("movie.stop")
                } else {
                    pill("Play", symbol: "play.fill", lit: false, enabled: model.movie.canPlay) {
                        Haptics.firm()
                        model.playMovie(recording: false)
                    }
                    .accessibilityIdentifier("movie.play")
                    pill("Record a clip", symbol: "film", lit: false, enabled: model.movie.canPlay) {
                        Haptics.firm()
                        model.playMovie(recording: true)
                    }
                    .accessibilityIdentifier("movie.record")
                }
            }
            // Two more ways to keep a moment, beside the movie because they are the same sort of thing.
            LabFlow(spacing: 6) {
                pill("Send this moment in 3D", symbol: "cube", lit: false, enabled: true) {
                    Haptics.firm()
                    model.sendMoment3D()
                }
                .accessibilityIdentifier("movie.moment3d")
                pill("Keep three seconds as a Live Photo", symbol: "livephoto", lit: model.clipPairing != nil,
                     enabled: !model.isRecordingClip) {
                    Haptics.firm()
                    model.recordLivePhoto()
                }
                .accessibilityIdentifier("movie.live")
            }
            Text("The 3D moment opens on any iPhone, iPad or Mac to be turned in the hand or stood in the room. The Live "
                + "Photo goes into your photos and moves when pressed. Neither has been tried on a phone yet.")
                .font(.labBody(10))
                .foregroundStyle(Palette.subtleForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let note = model.livePhotoNote {
                Text(note)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movie.liveNote")
            }
            if let problem = model.clipProblem {
                Text(problem)
                    .font(.labBody(10))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: String {
        let movie = model.movie
        if movie.isEmpty {
            return "Move the view somewhere worth looking from and add it as a stop, then another. Played, the camera "
                + "flies from one to the next, easing in and out, and says each stop's caption when it arrives."
        }
        if !movie.canPlay { return "One stop is a photograph. Move the view and add another to make a movie." }
        let seconds = Int(movie.duration.rounded())
        return "\(movie.stops.count) stops, \(seconds) seconds. The clip is the world alone, without the tray or the "
            + "tools, and silent."
    }

    private func stopRow(_ index: Int, _ stop: ParticleMovie.Stop) -> some View {
        let playingHere = model.isPlayingMovie && model.movieStop == index
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(index + 1)")
                    .font(.labNumeric(12))
                    .foregroundStyle(playingHere ? Palette.primaryForeground : Palette.foreground)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(playingHere ? Palette.primary : Color.white.opacity(0.10)))
                CaptionField(model: model, index: index, caption: stop.caption)
                Button {
                    Haptics.tap()
                    model.lookFromMovieStop(index)
                } label: {
                    Image(systemName: "eye")
                        .font(.labBody(12, .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Look from stop \(index + 1)")
                .accessibilityIdentifier("movie.look.\(index)")
                Menu {
                    if index > 0 {
                        Button("Move earlier") { model.movie.moveEarlier(index) }
                    }
                    Button("Replace with this view") {
                        let kept = model.movie.stops[index]
                        let replaced = ParticleMovie.Stop(
                            camera: model.camera, travel: kept.travel, hold: kept.hold, speed: kept.speed,
                            caption: kept.caption
                        )
                        model.movie.stops[index] = replaced
                    }
                    Button("Delete", role: .destructive) { model.movie.remove(at: index) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.labBody(12, .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("More for stop \(index + 1)")
                .accessibilityIdentifier("movie.more.\(index)")
            }
            .disabled(model.isPlayingMovie)

            HStack(spacing: 6) {
                if index > 0 {
                    choice(
                        "Getting here", stop.travel, Self.travels, id: "movie.travel.\(index)",
                        label: { "\(Self.number($0)) s" }
                    ) { model.movie.update(index, travel: $0) }
                }
                choice("Stay", stop.hold, Self.holds, id: "movie.hold.\(index)", label: { "\(Self.number($0)) s" }) {
                    model.movie.update(index, hold: $0)
                }
                choice(
                    "World", stop.speed, Self.speeds, id: "movie.speed.\(index)",
                    label: { $0 == 1 ? "real time" : "\(Self.number($0))×" }
                ) { model.movie.update(index, speed: $0) }
            }
            .disabled(model.isPlayingMovie)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    /// One setting of a stop, as a small menu: what it is, and its value.
    private func choice(
        _ title: String,
        _ value: Double,
        _ options: [Double],
        id: String,
        label: @escaping (Double) -> String,
        set: @escaping (Double) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(label(option)) { set(option) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.labBody(9))
                    .foregroundStyle(Palette.subtleForeground)
                Text(label(value))
                    .font(.labNumeric(11))
                    .foregroundStyle(Palette.foreground)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .accessibilityIdentifier(id)
    }

    private func pill(
        _ title: String,
        symbol: String,
        lit: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.labBody(12, .semiBold))
                .foregroundStyle(lit ? Palette.primaryForeground : Palette.foreground)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Capsule().fill(lit ? Palette.primary : Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(0 ... 2)))
    }
}

/// A stop's caption, typed into.
///
/// Held in its own state while being typed and written to the movie when the typing is done, so each letter does not
/// rebuild the list of stops — and a stop deleted mid-sentence cannot be written to.
private struct CaptionField: View {
    let model: ParticleFieldModel
    let index: Int
    let caption: String

    @State private var text = ""
    @FocusState private var isTyping: Bool

    var body: some View {
        TextField("Caption, if any", text: $text)
            .font(.labBody(12))
            .foregroundStyle(Palette.foreground)
            .focused($isTyping)
            .submitLabel(.done)
            .onSubmit { keep() }
            .onChange(of: isTyping) { _, typing in if !typing { keep() } }
            .onAppear { text = caption }
            .onChange(of: caption) { _, new in if !isTyping { text = new } }
            .accessibilityIdentifier("movie.caption.\(index)")
    }

    private func keep() {
        guard model.movie.stops.indices.contains(index) else { return }
        let trimmed = String(text.prefix(ParticleMovie.Stop.longestCaption))
        if model.movie.stops[index].caption != trimmed { model.movie.update(index, caption: trimmed) }
    }
}

/// What the movie is saying, on the world while it plays. The same words the clip has burnt into it.
struct MovieCaptionView: View {
    let model: ParticleFieldModel

    var body: some View {
        if let caption = model.movieCaption {
            Text(caption)
                .font(.labBody(15, .medium))
                .foregroundStyle(Palette.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Palette.elevated.opacity(Palette.overWorld(0.78))))
                .opacity(model.movieCaptionOpacity)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .allowsHitTesting(false)
                .accessibilityIdentifier("movie.caption")
        }
    }
}
