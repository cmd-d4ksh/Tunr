import AVFoundation

final class AudioSessionManager {

    static let shared = AudioSessionManager()
    private init() {}

    func configureAndActivate() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )

        try session.setPreferredSampleRate(44100)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}
