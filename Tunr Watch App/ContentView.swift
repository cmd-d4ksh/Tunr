import SwiftUI

struct ContentView: View {

    @StateObject private var session = WatchSessionManager.shared

    private var inTune: Bool { session.isInTune && session.frequency > 0 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !session.isConnected {
                disconnectedView
            } else if session.frequency == 0 {
                waitingView
            } else {
                tunerView
            }
        }
        .onAppear {
            WatchSessionManager.shared.start()
        }
    }

    // MARK: - Disconnected
    private var disconnectedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 28))
                .foregroundColor(.gray)

            Text("Open Tunr\non iPhone")
                .font(.caption.weight(.medium))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Waiting for Signal
    private var waitingView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.4))
                .symbolEffect(.variableColor.iterative)

            Text("Listening...")
                .font(.caption2.weight(.medium))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Tuner
    private var tunerView: some View {
        VStack(spacing: 4) {
            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)

                Text(inTune ? "IN TUNE" : "TUNING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.3)
            }
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.15))
            )

            Spacer().frame(height: 2)

            // Note
            Text(session.noteName)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(
                    color: inTune ? .green.opacity(0.5) : .clear,
                    radius: inTune ? 12 : 0
                )

            // Frequency
            Text(String(format: "%.1f Hz", session.frequency))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))

            Spacer().frame(height: 4)

            // Tuner bar
            WatchTunerBar(cents: session.cents, tint: tint)
                .frame(height: 18)
                .padding(.horizontal, 6)

            Spacer().frame(height: 2)

            // Cents
            Text(String(format: "%+.1f¢", session.cents))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(tint)
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        guard session.frequency > 0 else { return .gray }
        if abs(session.cents) < 3 { return .green }
        if abs(session.cents) < 10 { return .yellow }
        return .red
    }
}

// MARK: - Watch Tuner Bar
private struct WatchTunerBar: View {
    let cents: Double
    let tint: Color

    private var clamped: Double {
        max(-25, min(25, cents))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let center = width / 2
            let x = center + (CGFloat(clamped) / 25.0) * (width * 0.42)

            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.white.opacity(0.08))

                // Center tick
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1.5, height: height * 0.7)

                // Side ticks
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: height * 0.4)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: height * 0.4)
                }
                .padding(.horizontal, width * 0.25)

                // Needle
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 4, height: height - 4)
                    .shadow(color: tint.opacity(0.6), radius: 4)
                    .position(x: x, y: height / 2)
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: clamped)
            }
        }
    }
}
