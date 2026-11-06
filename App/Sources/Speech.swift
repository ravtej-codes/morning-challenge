import AVFoundation
import Speech

/// Live speech-to-text with Apple's built-in recogniser (on-device when the phone supports it).
@MainActor
final class Transcriber: ObservableObject {
    @Published var text = ""
    @Published private(set) var isRecording = false
    @Published private(set) var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN")) ?? SFSpeechRecognizer()

    // After a pause iOS starts a fresh transcript for the next utterance, so we keep
    // everything already heard in `committed` and only replace the current utterance.
    private var committed = ""
    private var partial = ""
    private var utteranceEnded = false
    private var run = 0  // ignores late callbacks from an earlier recording

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        error = nil
        let speechAllowed = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        let micAllowed = await AVAudioApplication.requestRecordPermission()
        guard speechAllowed, micAllowed else {
            error = "Allow Microphone and Speech Recognition in Settings → Morning."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            error = "Speech recognition isn't available right now. You can type instead."
            return
        }
        Chime.stop()
        run += 1
        let thisRun = run
        committed = text.isEmpty ? "" : text + " "
        partial = ""
        utteranceEnded = false
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            self.request = request

            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()
            isRecording = true

            task = Self.recognise(with: recognizer, request: request) { [weak self] transcript, endOfUtterance, finished in
                Task { @MainActor in
                    guard let self, self.run == thisRun else { return }
                    if let transcript, !transcript.isEmpty { self.receive(transcript) }
                    if endOfUtterance { self.utteranceEnded = true }
                    if finished { self.stop() }
                }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        run += 1  // text is already up to date; late results must not overwrite later typing
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        if isRecording {
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func receive(_ transcript: String) {
        if Self.isNewUtterance(previous: partial, next: transcript, afterPause: utteranceEnded) {
            committed += partial + " "
        }
        utteranceEnded = false
        partial = transcript
        text = committed + transcript
    }

    /// True when `next` is a fresh utterance rather than a revision of `previous`.
    nonisolated static func isNewUtterance(previous: String, next: String, afterPause: Bool) -> Bool {
        guard !previous.isEmpty else { return false }
        let p = previous.lowercased().filter(\.isLetter)
        let n = next.lowercased().filter(\.isLetter)
        let k = min(10, p.count, n.count)
        let samePrefix = k > 0 && p.prefix(k) == n.prefix(k)
        if samePrefix { return false }                 // still growing / revising the same utterance
        if afterPause { return true }                  // iOS marked the end of an utterance
        return Double(n.count) <= Double(p.count) * 0.8 // restarted: much shorter and different start
    }

    // audio callbacks run off the main thread, so keep them out of the main-actor class
    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognise(with recognizer: SFSpeechRecognizer,
                                              request: SFSpeechAudioBufferRecognitionRequest,
                                              onUpdate: @escaping @Sendable (String?, Bool, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString,
                     result?.speechRecognitionMetadata != nil,   // set when a pause ends an utterance
                     error != nil || (result?.isFinal ?? false))
        }
    }
}
