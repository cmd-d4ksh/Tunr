import Foundation
import WatchConnectivity
import Combine

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    // MARK: - Published state (UI reads THESE)
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0
    @Published var isInTune: Bool = false

    private override init() {
        super.init()
    }

    // MARK: - Start session
    func start() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()

        print("⌚️ Watch WCSession activated")
    }

    // MARK: - Receive CONTEXT (this is what fixes 0.0 Hz)
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String : Any]
    ) {
        DispatchQueue.main.async {
            self.frequency = applicationContext["freq"] as? Double ?? 0
            self.noteName = applicationContext["note"] as? String ?? "--"
            self.cents = applicationContext["cents"] as? Double ?? 0
            self.isInTune = abs(self.cents) < 5

            print("⌚️ Watch updated:",
                  self.frequency,
                  self.noteName,
                  self.cents)
        }
    }

    // MARK: - Required delegate (watchOS)
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("❌ Watch WCSession error:", error)
        }
    }
}
