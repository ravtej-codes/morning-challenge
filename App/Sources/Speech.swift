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
        let prefix = text.isEmpty ? "" : text + " "
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

            task = Self.recognise(with: recognizer, request: request) { [weak self] transcript, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let transcript { self.text = prefix + transcript }
                    if finished { self.stop() }
                }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
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
                                              onUpdate: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }
}
