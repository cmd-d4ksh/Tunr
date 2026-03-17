import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    private override init() {
        super.init()
    }

    // MARK: - Activation
    func start() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Send Tuning Data to Watch
    func sendTuningUpdate(freq: Double, note: String, cents: Double) {
        guard let session, session.activationState == .activated else { return }

        // Only send if Watch is paired and reachable via context
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let context: [String: Any] = [
            "freq": freq,
            "note": note,
            "cents": cents,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            try session.updateApplicationContext(context)
        } catch {
            print("Watch context update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - WCSessionDelegate (Required for iOS)
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("WCSession activation error: \(error.localizedDescription)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // iOS only — session transitioning
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after deactivation (e.g. Watch switch)
        session.activate()
    }
}
