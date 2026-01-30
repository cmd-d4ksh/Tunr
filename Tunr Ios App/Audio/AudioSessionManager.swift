import AVFoundation

final class AudioSessionManager {

    static let shared = AudioSessionManager()
    private init() {}

    func configureAndActivate() throws {
        let session = AVAudioSession.sharedInstance()

        // For a tuner we only need mic input. Use a very compatible config.
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers])

        // Don't force these unless you really need them; they can cause paramErr (-50)
        // try session.setPreferredSampleRate(44_100)
        // try session.setPreferredIOBufferDuration(0.023)
        // try session.setPreferredInputNumberOfChannels(1)

        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Optional: log what we actually got
        print("✅ AudioSession ACTIVE")
        print("Route:", session.currentRoute)
        print("Sample rate:", session.sampleRate)
        print("IO buffer:", session.ioBufferDuration)
        print("Inputs:", session.availableInputs ?? [])
    }
}

