import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State

    @State private var micAuthorized = false
    @State private var permissionChecked = false
    @State private var errorMessage: String? = nil

    @StateObject private var detector = PitchDetector()

    // MARK: - UI

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !permissionChecked {
                Text("Checking microphone…")
                    .foregroundColor(.white)
                    .font(.title2)

            } else if !micAuthorized {
                VStack(spacing: 16) {
                    Text("Microphone Access Needed")
                        .foregroundColor(.red)
                        .font(.title2)
                        .bold()

                    Text("Enable microphone access in Settings to tune your guitar.")
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("Setup Error")
                        .foregroundColor(.red)
                        .font(.title2)
                        .bold()

                    Text(error)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

            } else {
                tunerView
            }
        }
        .onAppear {
            setupAudioAndPermissions()
        }
        .onDisappear {
            detector.stop()
        }
    }

    // MARK: - Tuner UI

    private var tunerView: some View {
        VStack(spacing: 24) {
            // Note name (large)
            Text(detector.noteName)
                .font(.system(size: 96, weight: .bold, design: .monospaced))
                .foregroundColor(colorForCents(detector.cents))
                .minimumScaleFactor(0.5)

            // Frequency
            Text(String(format: "%.1f Hz", detector.frequency))
                .font(.title2)
                .foregroundColor(.white)
                .monospaced()

            // Cents indicator
            VStack(spacing: 8) {
                HStack(spacing: 20) {
                    Text("♭").font(.title).foregroundColor(.red)
                    
                    ZStack(alignment: .center) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForCents(detector.cents))
                            .frame(width: 4, height: 12)
                            .offset(x: CGFloat(detector.cents) * 2)
                    }
                    .frame(height: 20)

                    Text("♯").font(.title).foregroundColor(.green)
                }
                .padding(.horizontal, 24)

                Text(String(format: "%.1f¢", detector.cents))
                    .font(.caption)
                    .foregroundColor(colorForCents(detector.cents))
            }
        }
        .padding()
    }

    // MARK: - Helpers

    private func colorForCents(_ cents: Double) -> Color {
        if abs(cents) < 5 {
            return .green
        } else if abs(cents) < 15 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Audio + Permissions

    private func setupAudioAndPermissions() {

        requestMicrophonePermission { granted in
            micAuthorized = granted
            permissionChecked = true

            guard granted else {
                print("❌ Mic permission denied")
                return
            }

            do {
                try AudioSessionManager.shared.configureAndActivate()
                detector.start()
                print("🎧 Detector started AFTER permission + session")
            } catch {
                print("❌ Audio setup failed:", error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
