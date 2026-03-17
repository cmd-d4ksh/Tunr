import AVFoundation

final class AudioSessionManager {

    static let shared = AudioSessionManager()
    private var isConfigured = false

    private init() {}

    func configureAndActivate() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )

        try session.setPreferredSampleRate(44100)
        try session.setPreferredIOBufferDuration(0.005) // Low latency (~5ms)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        isConfigured = true
    }

    func deactivate() {
        guard isConfigured else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isConfigured = false
    }
}
