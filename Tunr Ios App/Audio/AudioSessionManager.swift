import AVFoundation

final class AudioSessionManager {

    static let shared = AudioSessionManager()
    private init() {}

    func configureAndActivate() throws {
        let session = AVAudioSession.sharedInstance()

        // Disable speaker output to prevent feedback
        try session.setCategory(
            .record,
            mode: .measurement,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        
        try session.setPreferredSampleRate(44_100)
        try session.setPreferredIOBufferDuration(0.023) // ~1024 samples at 44.1kHz
        try session.setPreferredInputNumberOfChannels(1)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        print("✅ AudioSession ACTIVE")
        print("🔊 Current route:", session.currentRoute)
        print("📊 Sample rate:", session.sampleRate)
        print("📏 Buffer duration:", session.ioBufferDuration)
    }
}
