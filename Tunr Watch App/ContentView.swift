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

    // MARK: - Waiting
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
            .background(Capsule().fill(tint.opacity(0.15)))

            Spacer().frame(height: 2)

            // Note
            Text(session.noteName)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(
                    color: inTune ? .green.opacity(0.5) : .clear,
                    radius: inTune ? 12 : 0
                )

            // Direction hint instead of cents
            if !inTune {
                Text(session.cents < 0 ? "Tune Up" : "Tune Down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint.opacity(0.8))
            } else {
                Text(String(format: "%.1f Hz", session.frequency))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer().frame(height: 4)

            // Tuner bar
            WatchTunerBar(cents: session.cents, tint: tint)
                .frame(height: 16)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        guard session.frequency > 0 else { return .gray }
        if abs(session.cents) < 8 { return .green }
        if abs(session.cents) < 20 { return .yellow }
        return .red
    }
}

// MARK: - Watch Tuner Bar
private struct WatchTunerBar: View {
    let cents: Double
    let tint: Color

    private var clamped: Double { max(-25, min(25, cents)) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = w / 2
            let x = center + CGFloat(clamped / 25.0) * (w * 0.42)

            ZStack {
                // Track
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))

                // Center tick
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 1.5, height: h * 0.65)

                // Needle
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 4, height: h - 4)
                    .shadow(color: tint.opacity(0.5), radius: 3)
                    .position(x: x, y: h / 2)
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: clamped)
            }
        }
    }
}
