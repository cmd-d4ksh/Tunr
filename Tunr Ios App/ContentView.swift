import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State
    @State private var micAuthorized = false
    @State private var permissionChecked = false
    @State private var errorMessage: String? = nil
    @State private var detectorStarted = false

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
            if detectorStarted {
                detector.stop()
                detectorStarted = false
            }
        }
    }

    // MARK: - Tuner UI
    private var tunerView: some View {
        VStack(spacing: 18) {

            // Status + Frequency
            HStack {
                let inTune = abs(detector.cents) < 5

                Text(
                    inTune
                    ? "IN TUNE"
                    : (detector.frequency > 0 ? "TUNING" : "LISTENING")
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(colorForCents(detector.cents).opacity(0.18))
                )
                .overlay(
                    Capsule().stroke(colorForCents(detector.cents).opacity(0.35), lineWidth: 1)
                )
                .foregroundColor(colorForCents(detector.cents))

                Spacer()

                Text(String(format: "%.1f Hz", detector.frequency))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            // Big Note
            Text(detector.noteName)
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            // Needle
            TunerNeedleGauge(
                cents: detector.cents,
                tint: colorForCents(detector.cents)
            )
            .frame(height: 96)

            // String Selector
            StringSelectorRow(
                strings: GuitarTuning.standard,
                selected: detector.lockedTarget ?? detector.closestTarget,
                onSelect: { note in
                    detector.lockedTarget =
                        (detector.lockedTarget?.id == note.id) ? nil : note
                }
            )

            // Cents Readout
            Text(String(format: "%+.1f¢", detector.cents))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundColor(colorForCents(detector.cents))
        }
        .padding(18)
    }

    // MARK: - Helpers
    private func colorForCents(_ cents: Double) -> Color {
        if abs(cents) < 5 { return .green }
        if abs(cents) < 15 { return .yellow }
        return .red
    }

    // MARK: - Audio + Permissions
    private func setupAudioAndPermissions() {

        requestMicrophonePermission { granted in
            micAuthorized = granted
            permissionChecked = true

            guard granted else { return }
            guard !detectorStarted else { return }

            do {
                try AudioSessionManager.shared.configureAndActivate()
                detector.start()
                WatchSessionManager.shared.start()
                detectorStarted = true
                print("🎧 Detector started safely")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestMicrophonePermission(
        completion: @escaping (Bool) -> Void
    ) {
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

// MARK: - Needle Gauge
private struct TunerNeedleGauge: View {
    let cents: Double
    let tint: Color

    private var clamped: Double { max(-25, min(25, cents)) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let center = width / 2
            let travel: CGFloat = width * 0.38
            let x = center + (CGFloat(clamped) / 25.0) * travel

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                HStack(spacing: 0) {
                    ForEach(-5...5, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i == 0 ? 0.6 : 0.2))
                            .frame(
                                width: i == 0 ? 2 : 1,
                                height: i == 0 ? 44 : 22
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 18)

                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: 6, height: 54)
                    .shadow(radius: 10)
                    .position(x: x, y: geo.size.height / 2)
                    .animation(
                        .spring(response: 0.22, dampingFraction: 0.82),
                        value: clamped
                    )
            }
        }
    }
}

// MARK: - String Selector
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
                                isSelected
                                ? Color.white.opacity(0.25)
                                : Color.white.opacity(0.06)
                            )
                        )
                        .overlay(
                            Circle().stroke(
                                isSelected
                                ? Color.white.opacity(0.65)
                                : Color.white.opacity(0.12),
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
