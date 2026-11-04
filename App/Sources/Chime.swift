import AVFoundation

/// Loops the deadline bells from the app itself, from the deadline until the challenge is decided.
/// Uses the playback category, so it rings even with the silent switch on (while the app is open).
@MainActor
enum Chime {
    private static var player: AVAudioPlayer?

    static func startLooping() {
        guard player == nil,
              let url = Bundle.main.url(forResource: "deadline_bells", withExtension: "wav") else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 1
            p.play()
            player = p
        } catch {
            player = nil
        }
    }

    static func stop() {
        guard let p = player else { return }
        p.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
