import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State
    @State private var micAuthorized = false
    @State private var permissionChecked = false
    @State private var errorMessage: String? = nil
    @State private var detectorStarted = false

    @StateObject private var detector = PitchDetector()

    private var inTune: Bool { abs(detector.cents) < 3 && detector.frequency > 0 }
    private var nearTune: Bool { abs(detector.cents) < 8 }

    // MARK: - UI
    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

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
    private var backgroundGradient: some View {
        ZStack {
            Color.black

            // Subtle radial glow when in tune
            if inTune {
                RadialGradient(
                    colors: [Color.green.opacity(0.08), Color.clear],
                    center: .center,
                    startRadius: 50,
                    endRadius: 350
                )
                .animation(.easeInOut(duration: 0.6), value: inTune)
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

            Spacer().frame(height: 20)

            // Status pill + Frequency
            HStack {
                StatusPill(
                    text: inTune ? "IN TUNE" : (detector.frequency > 0 ? "TUNING" : "LISTENING"),
                    color: colorForCents(detector.cents),
                    isActive: detector.frequency > 0
                )

                Spacer()

                if detector.frequency > 0 {
                    Text(String(format: "%.1f Hz", detector.frequency))
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.06))
                        )
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            // Big Note Display
            noteDisplay
                .padding(.bottom, 4)

            // Cents readout
            if detector.frequency > 0 {
                HStack(spacing: 4) {
                    Image(systemName: detector.cents < -1 ? "arrow.down" : (detector.cents > 1 ? "arrow.up" : "checkmark"))
                        .font(.caption2.weight(.bold))
                    Text(String(format: "%+.1f¢", detector.cents))
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
                .foregroundColor(colorForCents(detector.cents))
                .padding(.bottom, 8)
            }

            Spacer()

            // Needle gauge
            TunerNeedleGauge(
                cents: detector.cents,
                tint: colorForCents(detector.cents),
                isActive: detector.frequency > 0
            )
            .frame(height: 80)
            .padding(.horizontal, 16)

            Spacer()

            // String selector
            StringSelectorRow(
                strings: GuitarTuning.standard,
                selected: detector.lockedTarget ?? detector.closestTarget,
                autoDetected: detector.lockedTarget == nil ? detector.closestTarget : nil,
                onSelect: { note in
                    withAnimation(.spring(response: 0.3)) {
                        detector.lockedTarget =
                            (detector.lockedTarget?.id == note.id) ? nil : note
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }
            )
            .padding(.horizontal, 12)

            Spacer().frame(height: 30)
        }
        .onChange(of: inTune) { _, newValue in
            if newValue {
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            }
        }
    }

    // MARK: - Note Display
    private var noteDisplay: some View {
        VStack(spacing: 2) {
            Text(detector.noteName)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(
                    color: inTune ? .green.opacity(0.4) : .clear,
                    radius: inTune ? 20 : 0
                )
                .animation(.easeInOut(duration: 0.3), value: inTune)

            if detector.frequency > 0, let target = detector.closestTarget {
                Text(String(format: "%.2f Hz", target.frequency))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.3))
            }
        }
    }

    // MARK: - Helpers
    private func colorForCents(_ cents: Double) -> Color {
        guard detector.frequency > 0 else { return .gray }
        if abs(cents) < 3 { return .green }
        if abs(cents) < 10 { return .yellow }
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

    private func requestMicrophonePermission(
        completion: @escaping (Bool) -> Void
    ) {
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
    let isActive: Bool

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
        .background(
            Capsule().fill(color.opacity(0.12))
        )
        .overlay(
            Capsule().stroke(color.opacity(0.25), lineWidth: 1)
        )
        .foregroundColor(color)
    }
}

// MARK: - Needle Gauge
private struct TunerNeedleGauge: View {
    let cents: Double
    let tint: Color
    let isActive: Bool

    private var clamped: Double { max(-30, min(30, cents)) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let center = width / 2
            let travel: CGFloat = width * 0.40
            let x = isActive ? center + (CGFloat(clamped) / 30.0) * travel : center

            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                // Tick marks
                HStack(spacing: 0) {
                    ForEach(-6...6, id: \.self) { i in
                        let isMajor = i == 0
                        let isMinor = abs(i) == 3 || abs(i) == 6

                        Rectangle()
                            .fill(Color.white.opacity(isMajor ? 0.5 : (isMinor ? 0.2 : 0.1)))
                            .frame(
                                width: isMajor ? 2 : 1,
                                height: isMajor ? 40 : (isMinor ? 24 : 14)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)

                // Center zone highlight (green when close)
                if isActive && abs(clamped) < 5 {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.08))
                        .frame(width: travel * 2 * 5 / 30, height: height - 8)
                }

                // Needle
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: 5, height: 52)
                    .shadow(color: tint.opacity(0.5), radius: 8)
                    .position(x: x, y: height / 2)
                    .animation(
                        .spring(response: 0.25, dampingFraction: 0.78),
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
    let autoDetected: GuitarNote?
    let onSelect: (GuitarNote) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(strings) { note in
                let isSelected = selected?.id == note.id
                let isAuto = autoDetected?.id == note.id && !isSelected

                Button {
                    onSelect(note)
                } label: {
                    VStack(spacing: 3) {
                        Text(note.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        Text("\(note.stringNumber)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isSelected
                                ? Color.white.opacity(0.18)
                                : (isAuto ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected
                                ? Color.white.opacity(0.5)
                                : (isAuto ? Color.white.opacity(0.15) : Color.white.opacity(0.06)),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
