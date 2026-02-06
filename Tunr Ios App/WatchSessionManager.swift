import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject {

    static let shared = WatchSessionManager()

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.activate()
        print("📱 iPhone WCSession activated")
    }

    func sendTuningUpdate(freq: Double, note: String, cents: Double) {
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
    }}
