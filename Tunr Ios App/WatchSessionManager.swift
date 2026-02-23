import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        print("📱 iPhone WCSession activated")
    }

    func sendTuningUpdate(freq: Double, note: String, cents: Double) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        let context: [String: Any] = [
            "freq": freq,
            "note": note,
            "cents": cents
        ]

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("❌ Watch context update failed:", error)
        }
    }

    // MARK: - WCSessionDelegate (required on iOS)

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("❌ iPhone WCSession error:", error)
        } else {
            print("📱 iPhone WCSession active — paired: \(session.isPaired), watch app installed: \(session.isWatchAppInstalled)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
