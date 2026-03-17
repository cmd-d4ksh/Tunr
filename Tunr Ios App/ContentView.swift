import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State
    @State private var micAuthorized = false
    @State private var permissionChecked = false
    @State private var errorMessage: String? = nil
    @State private var detectorStarted = false

    @StateObject private var detector = PitchDetector()

    private var inTune: Bool { abs(detector.cents) < 8 && detector.frequency > 0 }

    // MARK: - Body
    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            if !permissionChecked {
                loadingView
            } else if !micAuthorized {
                permissionDeniedView
            } else if let error = errorMessage {
                errorView(error)
            } else {
                tunerView
            }
        }
        .onAppear { setupAudioAndPermissions() }
        .onDisappear {
            if detectorStarted {
                detector.stop()
                detectorStarted = false
            }
        }
    }

    // MARK: - Background
    private var backgroundColor: some View {
        ZStack {
            Color.black
            if inTune {
                RadialGradient(
                    colors: [Color.green.opacity(0.1), Color.clear],
                    center: .center,
                    startRadius: 40,
                    endRadius: 300
                )
                .animation(.easeInOut(duration: 0.5), value: inTune)
            }
        }
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.6))
            Text("Setting up microphone...")
                .foregroundColor(.white.opacity(0.6))
                .font(.callout)
        }
    }

    // MARK: - Permission Denied
    private var permissionDeniedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.8))

            Text("Microphone Access Needed")
                .foregroundColor(.white)
                .font(.title3.bold())

            Text("Open Settings and enable microphone access to tune your guitar.")
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.horizontal, 40)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white))
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Error
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Setup Error")
                .foregroundColor(.white)
                .font(.title3.bold())
            Text(error)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .font(.callout)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Tuner UI
    private var tunerView: some View {
        VStack(spacing: 0) {

            Spacer().frame(height: 24)

            // Status bar
            HStack {
                StatusPill(
                    text: inTune ? "IN TUNE" : (detector.frequency > 0 ? "TUNING" : "LISTENING"),
                    color: tuneColor
                )
                Spacer()
                if detector.frequency > 0 {
                    Text(String(format: "%.1f Hz", detector.frequency))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Direction hint — tells you what to do
            if detector.frequency > 0 && !inTune {
                Text(detector.cents < 0 ? "TUNE UP" : "TUNE DOWN")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundColor(tuneColor.opacity(0.7))
                    .padding(.bottom, 6)
            }

            // Big note name
            Text(detector.noteName)
                .font(.system(size: 100, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(
                    color: inTune ? .green.opacity(0.5) : .clear,
                    radius: inTune ? 24 : 0
                )
                .animation(.easeInOut(duration: 0.3), value: inTune)

            // Target frequency (small, subtle)
            if detector.frequency > 0, let target = detector.closestTarget {
                Text("target: \(String(format: "%.1f", target.frequency)) Hz")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.25))
                    .padding(.top, 2)
            }

            Spacer()

            // Tuner gauge
            TunerGauge(
                cents: detector.cents,
                color: tuneColor,
                isActive: detector.frequency > 0
            )
            .frame(height: 72)
            .padding(.horizontal, 20)

            Spacer()

            // String selector
            StringSelector(
                strings: GuitarTuning.standard,
                selected: detector.lockedTarget ?? detector.closestTarget,
                autoDetected: detector.lockedTarget == nil ? detector.closestTarget : nil,
                inTuneNoteId: inTune ? (detector.lockedTarget ?? detector.closestTarget)?.id : nil,
                onSelect: { note in
                    withAnimation(.spring(response: 0.3)) {
                        detector.lockedTarget =
                            (detector.lockedTarget?.id == note.id) ? nil : note
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
            .padding(.horizontal, 16)

            Spacer().frame(height: 32)
        }
        .onChange(of: inTune) { _, newValue in
            if newValue {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: - Tune Color
    private var tuneColor: Color {
        guard detector.frequency > 0 else { return .gray }
        let c = abs(detector.cents)
        if c < 8 { return .green }
        if c < 20 { return .yellow }
        return .red
    }

    // MARK: - Audio + Permissions
    private func setupAudioAndPermissions() {
        requestMicrophonePermission { granted in
            micAuthorized = granted
            permissionChecked = true

            guard granted, !detectorStarted else { return }

            do {
                try AudioSessionManager.shared.configureAndActivate()
                detector.start()
                WatchSessionManager.shared.start()
                detectorStarted = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }
}

// MARK: - Status Pill
private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.2), lineWidth: 1))
        .foregroundColor(color)
    }
}

// MARK: - Tuner Gauge
private struct TunerGauge: View {
    let cents: Double
    let color: Color
    let isActive: Bool

    private var clamped: Double { max(-30, min(30, cents)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = w / 2
            let travel = w * 0.40
            let needleX = isActive
                ? center + CGFloat(clamped / 30.0) * travel
                : center

            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Flat / Sharp labels
                HStack {
                    Text("FLAT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.15))
                        .padding(.leading, 14)
                    Spacer()
                    Text("SHARP")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundColor(.white.opacity(0.15))
                        .padding(.trailing, 14)
                }

                // Tick marks
                HStack(spacing: 0) {
                    ForEach(-5...5, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i == 0 ? 0.5 : 0.15))
                            .frame(
                                width: i == 0 ? 2 : 1,
                                height: i == 0 ? 36 : 16
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 24)

                // Green zone indicator at center
                if isActive && abs(clamped) < 8 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.06))
                        .frame(width: travel * 2 * 5 / 30, height: h - 12)
                }

                // Needle
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 5, height: 48)
                    .shadow(color: color.opacity(0.6), radius: 8)
                    .position(x: needleX, y: h / 2)
                    .animation(
                        .spring(response: 0.25, dampingFraction: 0.8),
                        value: clamped
                    )
            }
        }
    }
}

// MARK: - String Selector
private struct StringSelector: View {
    let strings: [GuitarNote]
    let selected: GuitarNote?
    let autoDetected: GuitarNote?
    let inTuneNoteId: String?
    let onSelect: (GuitarNote) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(strings) { note in
                let isSelected = selected?.id == note.id
                let isAuto = autoDetected?.id == note.id && !isSelected
                let isInTune = inTuneNoteId == note.id

                Button { onSelect(note) } label: {
                    VStack(spacing: 2) {
                        Text(note.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text("\(note.stringNumber)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isInTune ? .green.opacity(0.6) : .white.opacity(0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isInTune ? Color.green.opacity(0.15)
                                  : (isSelected ? Color.white.opacity(0.15)
                                     : (isAuto ? Color.white.opacity(0.06)
                                        : Color.white.opacity(0.03))))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isInTune ? Color.green.opacity(0.5)
                                : (isSelected ? Color.white.opacity(0.45)
                                   : (isAuto ? Color.white.opacity(0.12)
                                      : Color.white.opacity(0.06))),
                                lineWidth: (isInTune || isSelected) ? 1.5 : 1
                            )
                    )
                    .foregroundColor(isInTune ? .green : (isSelected ? .white : .white.opacity(0.6)))
                    .animation(.easeInOut(duration: 0.3), value: isInTune)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
