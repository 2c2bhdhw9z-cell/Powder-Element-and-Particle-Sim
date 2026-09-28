import AVFoundation
import CrucibleCore
import Foundation
import Speech

/// Listens for things said to the lab, and hands over each one it understands.
///
/// The phone's speech recogniser turns sound into words; what the words mean is `VoiceCommands` in the engine, where
/// every sentence it understands is checked. This is the plumbing between the two: permission, the microphone, and
/// starting the recogniser again when it stops — it listens for about a minute at a time and then has to be asked
/// again, which nobody talking to a sandbox should have to know.
///
/// ## Not tested on a phone
///
/// Built on a machine with no microphone, and the checks' Macs have none either. Everything it decides is tested; that
/// it hears is not, yet.
@MainActor
@Observable
final class SpeechListener {
    /// Whether it is listening.
    private(set) var isListening = false
    /// The last thing it heard, as words, for showing that it is hearing.
    private(set) var lastHeard = ""
    /// What it last did about something said, for saying so back.
    private(set) var lastUnderstood: String?
    /// Why it cannot listen, if it cannot.
    private(set) var problem: String?

    /// Given each command as it is understood.
    @ObservationIgnored var onCommand: ((LabVoiceCommand) -> Void)?
    /// The names it listens for, set by whoever knows them: every material, every arrangement, every scene.
    @ObservationIgnored var materials: [(ElementID, String)] = []
    @ObservationIgnored var arrangements: [VoiceCommands.Name] = []
    @ObservationIgnored var scenes: [VoiceCommands.Name] = []

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
        ?? SFSpeechRecognizer()
    @ObservationIgnored private var listener = VoiceCommandListener()
    @ObservationIgnored private var wantsListening = false
    @ObservationIgnored private var recognitionFailures = 0
    /// Which round of listening this is, so a result arriving late from a round already ended is ignored.
    @ObservationIgnored private var round = 0

    /// Asks for permission if it has not been given, and starts listening.
    func start() {
        wantsListening = true
        guard !isListening else { return }
        problem = nil
        guard AudioSessionUsers.claimMicrophone(for: .speech) else {
            wantsListening = false
            problem = "The microphone is already listening to music. Switch Listen off first."
            return
        }
        Task { @MainActor [weak self] in
            let speech = await Self.speechPermission()
            guard let self, self.wantsListening, AudioSessionUsers.microphone == .speech else { return }
            guard speech else {
                self.fail("Crucible needs permission to recognise speech. It is in Settings, under Crucible.")
                return
            }
            let microphone = await AVAudioApplication.requestRecordPermission()
            guard self.wantsListening, AudioSessionUsers.microphone == .speech else { return }
            guard microphone else {
                self.fail("Crucible needs permission to use the microphone. It is in Settings, under Crucible.")
                return
            }
            guard let recogniser = self.recogniser, recogniser.isAvailable else {
                self.fail("Speech recognition is not available on this phone just now.")
                return
            }
            self.begin(with: recogniser)
        }
    }

    /// Stops listening and gives the microphone back.
    func stop() {
        wantsListening = false
        stopHardware()
    }

    /// Stops hardware while the app is away and resumes only if the switch is still wanted.
    func sceneChanged(active: Bool) {
        if active {
            if wantsListening, !isListening { start() }
        } else {
            stopHardware()
        }
    }

    private func stopHardware() {
        round += 1
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isListening = false
        AudioSessionUsers.releaseMicrophone(for: .speech)
        let session = AVAudioSession.sharedInstance()
        if AudioSessionUsers.speaker {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private nonisolated static func speechPermission() async -> Bool {
        await withCheckedContinuation { done in
            SFSpeechRecognizer.requestAuthorization { status in done.resume(returning: status == .authorized) }
        }
    }

    private func begin(with recogniser: SFSpeechRecognizer) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            fail("The microphone could not be opened.")
            return
        }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("This phone reported no microphone.")
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On the phone itself where it can be, so what is said to a sandbox is not sent anywhere.
        if recogniser.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: Self.tap(feeding: RequestBox(request)))
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            fail("The microphone could not be started.")
            return
        }
        self.engine = engine
        self.request = request
        recognitionFailures = 0
        isListening = true
        listen(with: recogniser, request: request)
    }

    private func fail(_ message: String) {
        problem = message
        wantsListening = false
        stopHardware()
    }

    /// One round of recognition. The recogniser ends a round by itself after about a minute, or after a pause; each
    /// time, another is begun on the same microphone.
    private func listen(with recogniser: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        round += 1
        let thisRound = round
        listener.newSentence()
        task = recogniser.recognitionTask(with: request, resultHandler: Self.handler(for: self, round: thisRound))
    }

    /// What happens to each guess the recogniser makes. Outside the main thread's view of the world, because that is
    /// where the recogniser calls it; only plain words cross back.
    private nonisolated static func handler(
        for listener: SpeechListener,
        round: Int
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak listener] result, error in
            let words = result?.bestTranscription.formattedString
            let failed = error != nil
            let finished = result?.isFinal ?? false || failed
            Task { @MainActor in
                guard let listener, listener.round == round else { return }
                if let words { listener.heard(words) }
                if finished { listener.roundEnded(failed: failed) }
            }
        }
    }

    private func heard(_ words: String) {
        recognitionFailures = 0
        lastHeard = words
        guard let command = listener.heard(words, materials: materials, arrangements: arrangements, scenes: scenes)
        else { return }
        lastUnderstood = command.said { id in materials.first { $0.0 == id }?.1 ?? "that" }
        onCommand?(command)
    }

    /// A round has ended. Another begins on a fresh request, still on the same microphone, for as long as listening
    /// is on.
    private func roundEnded(failed: Bool) {
        guard isListening, let engine, let recogniser else { return }
        if failed {
            recognitionFailures += 1
            guard recognitionFailures < 3 else {
                fail("Speech recognition kept stopping. Try again when the phone has a better connection.")
                return
            }
        } else {
            recognitionFailures = 0
        }
        task = nil
        request?.endAudio()
        let fresh = SFSpeechAudioBufferRecognitionRequest()
        fresh.shouldReportPartialResults = true
        if recogniser.supportsOnDeviceRecognition { fresh.requiresOnDeviceRecognition = true }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(
            onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0), block: Self.tap(feeding: RequestBox(fresh))
        )
        request = fresh
        listen(with: recogniser, request: fresh)
    }

    /// The microphone's tap, made outside the main actor: it is called on the audio thread, where a closure belonging
    /// to the main thread would stop the app for being in the wrong place.
    private nonisolated static func tap(feeding box: RequestBox) -> AVAudioNodeTapBlock {
        { buffer, _ in box.request.append(buffer) }
    }
}

/// A recognition request carried to the audio thread. It is made to be fed from there; the box only says so.
final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}
