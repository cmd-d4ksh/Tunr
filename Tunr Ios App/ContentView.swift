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
        VStack(spacing: 18) {

            // Top bar: status + freq
            HStack {
                let inTune = abs(detector.cents) < 5
                Text(inTune ? "IN TUNE" : (detector.frequency > 0 ? "TUNING" : "LISTENING"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(colorForCents(detector.cents).opacity(0.18)))
                    .overlay(Capsule().stroke(colorForCents(detector.cents).opacity(0.35), lineWidth: 1))
                    .foregroundColor(colorForCents(detector.cents))

                Spacer()

                Text(String(format: "%.1f Hz", detector.frequency))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            // Big note
            Text(detector.noteName)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Needle gauge
            TunerNeedleGauge(cents: detector.cents, tint: colorForCents(detector.cents))
                .frame(height: 96)

            // String selector (tap to lock)
            StringSelectorRow(
                strings: GuitarTuning.standard,
                selected: detector.lockedTarget ?? detector.closestTarget,   // 👈 auto-detect selects it
                onSelect: { note in
                    // optional: tap to lock/unlock
                    if detector.lockedTarget?.id == note.id {
                        detector.lockedTarget = nil
                    } else {
                        detector.lockedTarget = note
                    }
                }
            )

            // Bottom readout
            let displayCents = max(-50, min(50, detector.cents))
            Text(String(format: "%+.1f¢", displayCents))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundColor(colorForCents(detector.cents))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .padding(18)
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

private struct TunerNeedleGauge: View {
    let cents: Double
    let tint: Color

    private var clamped: Double { max(-25, min(25, cents)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let center = w / 2
            let travel: CGFloat = w * 0.38
            let x = center + (CGFloat(clamped) / 25.0) * travel

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                // ticks
                HStack(spacing: 0) {
                    ForEach(-5...5, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i == 0 ? 0.55 : 0.18))
                            .frame(width: i == 0 ? 2 : 1, height: i == 0 ? 42 : 22)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)

                // needle
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: 6, height: 52)
                    .shadow(radius: 10)
                    .position(x: x, y: geo.size.height / 2)
                    .animation(.spring(response: 0.22, dampingFraction: 0.82), value: clamped)
            }
        }
    }
}

private struct StringSelectorRow: View {
    let strings: [GuitarNote]
    let selected: GuitarNote?
    let onSelect: (GuitarNote) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(strings) { note in
                let isSelected = selected?.id == note.id

                Button {
                    onSelect(note)
                } label: {
                    Text(note.name)
                        .font(.headline.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(
                                isSelected ? Color.white.opacity(0.22)
                                           : Color.white.opacity(0.06)
                            )
                        )
                        .overlay(
                            Circle().stroke(
                                isSelected ? Color.white.opacity(0.60)
                                           : Color.white.opacity(0.10),
                                lineWidth: 1
                            )
                        )
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }
}

