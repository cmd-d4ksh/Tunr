import Foundation
import WatchConnectivity
import Combine

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    // MARK: - Published state
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0
    @Published var isInTune: Bool = false
    @Published var isConnected: Bool = false

    // Track last update to detect stale data
    private var lastUpdateTime: Date = .distantPast
    private var staleTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Start session
    func start() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Check for stale data periodically
        staleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkForStaleData()
        }
    }

    // MARK: - Receive context from iOS
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.frequency = applicationContext["freq"] as? Double ?? 0
            self.noteName = applicationContext["note"] as? String ?? "--"
            self.cents = applicationContext["cents"] as? Double ?? 0
            self.isInTune = abs(self.cents) < 3 && self.frequency > 0
            self.isConnected = true
            self.lastUpdateTime = Date()
        }
    }

    // MARK: - Activation delegate
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isConnected = (activationState == .activated)
        }

        if let error {
            print("Watch WCSession error: \(error.localizedDescription)")
        }

        // Load any existing context on activation
        if activationState == .activated {
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                self.session(session, didReceiveApplicationContext: context)
            }
        }
    }

    // MARK: - Stale data check
    private func checkForStaleData() {
        let elapsed = Date().timeIntervalSince(lastUpdateTime)
        // If no update for 5 seconds, assume iPhone app closed
        if elapsed > 5 && frequency > 0 {
            DispatchQueue.main.async {
                self.frequency = 0
                self.noteName = "--"
                self.cents = 0
                self.isInTune = false
            }
        }
    }
}
