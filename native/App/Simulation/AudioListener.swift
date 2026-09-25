import Accelerate
import AVFoundation
import CrucibleCore

/// Listening to the microphone, and turning what it hears into three numbers.
///
/// The three numbers — how much low end, how much middle, how loud — are what the field reacts to, and
/// everything that decides *what* they do lives in the engine where it can be tested. This is only the
/// listening: opening the microphone, breaking the sound into frequencies, and handing the result over.
///
/// ## What it does not do
///
/// It does not play anything, and it never connects the microphone to the speaker. That is worth stating
/// because a microphone wired to a speaker is a howl, and it is a single line away at all times.
@MainActor
@Observable
final class AudioListener {
    /// What the microphone is currently reporting, already smoothed.
    private(set) var signal = ParticleAudioSignal.silence
    /// Whether it is listening.
    private(set) var isListening = false
    /// Why it could not listen, if it could not.
    private(set) var problem: String?

    /// How quickly the three numbers rise and fall.
    var envelope: ParticleAudioEnvelope {
        get { follower.envelope }
        set { follower.envelope = newValue }
    }

    @ObservationIgnored
    private var engine: AVAudioEngine?
    @ObservationIgnored
    private var follower = ParticleAudioFollower()

    /// How many samples go into one look at the frequencies.
    ///
    /// A thousand and twenty-four. At the usual sample rates that is about twenty milliseconds of sound —
    /// short enough that a beat is not smeared across the window, long enough to tell a bass note from a
    /// kick drum. It has to be a power of two for the frequency transform to work at all.
    private static let windowSize = 1_024

    /// The plan the frequency transform follows, made once.
    ///
    /// Working this out is the expensive part; doing it per frame rather than once would cost more than the
    /// transform itself.
    ///
    /// Kept out of the observation machinery. It is not state anything watches, and leaving it in makes the
    /// macro generate code that touches the type — which matters because the type is deprecated-adjacent
    /// enough that the generated code produced errors of its own, in a file with no name a person could
    /// find.
    @ObservationIgnored
    private var transform: vDSP.DiscreteFourierTransform<Float>?

    /// Somewhere to put the sound while the transform runs.
    ///
    /// Held rather than made per window, because this runs some fifty times a second and allocating five
    /// buffers each time is the sort of thing that shows up as the interface stuttering while music plays.
    @ObservationIgnored
    private var windowed = [Float](repeating: 0, count: windowSize)
    @ObservationIgnored
    private var realOut = [Float](repeating: 0, count: windowSize)
    @ObservationIgnored
    private var imaginaryOut = [Float](repeating: 0, count: windowSize)
    @ObservationIgnored
    private var magnitudes = [Float](repeating: 0, count: windowSize / 2)
    @ObservationIgnored
    private var zeros = [Float](repeating: 0, count: windowSize)

    /// The shape the sound is faded in and out with before being transformed.
    ///
    /// Without it, the two ends of the window are a sudden jump, and a sudden jump contains every frequency
    /// there is — so a smooth tone comes back as a smear across the whole range and the three bands all
    /// read the same. Fading the ends to nothing removes that.
    @ObservationIgnored
    private let taper: [Float] = {
        var window = [Float](repeating: 0, count: AudioListener.windowSize)
        vDSP_hann_window(&window, vDSP_Length(AudioListener.windowSize), Int32(vDSP_HANN_NORM))
        return window
    }()

    init() {
        transform = try? vDSP.DiscreteFourierTransform(
            previous: nil,
            count: Self.windowSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
    }

    /// Starts listening, asking for permission if it has not been given.
    func start() {
        guard !isListening else { return }
        problem = nil

        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.problem = "Crucible needs permission to use the microphone. "
                        + "It is in Settings, under Crucible."
                    return
                }
                self.begin()
            }
        }
    }

    /// Stops listening and releases the microphone.
    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isListening = false
        follower.reset()
        signal = .silence
        // Handed back, so music from another app is not left ducked and the microphone indicator goes out.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Recording *and* playing, so the app's own sounds still work while it is listening — the
            // record-only category silences everything else the app is doing.
            //
            // `mixWithOthers` is what lets somebody play music from another app and have the field react to
            // it through the microphone, which is the obvious thing to want and impossible without it.
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            problem = "The microphone could not be opened."
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = "This device reported no microphone."
            return
        }

        // Deliberately never connected to the output. A microphone wired to a speaker is a howl, and it is
        // one line away from here at all times.
        input.installTap(onBus: 0, bufferSize: UInt32(Self.windowSize), format: format) {
            [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            // Copied out, because the buffer belongs to the audio system and is reused the moment this
            // returns — which is on a different thread from everything else here.
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            let rate = format.sampleRate
            Task { @MainActor in
                self?.consume(samples, sampleRate: rate)
            }
        }

        do {
            try engine.start()
        } catch {
            problem = "The microphone could not be started."
            return
        }
        self.engine = engine
        isListening = true
    }

    /// Turns one window of sound into the three numbers.
    private func consume(_ samples: [Float], sampleRate: Double) {
        guard let transform else { return }
        let taken = min(samples.count, Self.windowSize)
        guard taken > 0 else { return }

        // Faded at both ends, and padded with nothing if the window came up short.
        for index in 0 ..< Self.windowSize {
            windowed[index] = index < taken ? samples[index] * taper[index] : 0
        }

        transform.transform(
            inputReal: windowed,
            inputImaginary: zeros,
            outputReal: &realOut,
            outputImaginary: &imaginaryOut
        )

        // How much energy is at each frequency. Only the first half is meaningful — the second is the
        // mirror image of it, which is a property of transforming a real signal.
        //
        // Divided by the window size, so the numbers mean the same thing whatever the window length, and
        // scaled up because ordinary room sound sits at a small fraction of what the microphone can report.
        let scale = 24.0 / Float(Self.windowSize)
        for index in 0 ..< magnitudes.count {
            let real = realOut[index]
            let imaginary = imaginaryOut[index]
            let size = (real * real + imaginary * imaginary).squareRoot() * scale
            magnitudes[index] = size.isFinite ? min(1, size) : 0
        }

        follower.follow(ParticleAudio.bands(magnitudes: magnitudes, sampleRate: sampleRate))
        signal = follower.held
    }
}
