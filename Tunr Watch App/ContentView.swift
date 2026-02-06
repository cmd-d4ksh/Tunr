import SwiftUI

struct ContentView: View {

    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 8) {

                // Status pill
                Text(session.isInTune ? "IN TUNE" : "TUNING")
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.2))
                    )
                    .foregroundColor(tint)

                // Note
                Text(session.noteName)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                // Frequency
                Text(String(format: "%.1f Hz", session.frequency))
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))

                // Tuner bar
                TunerBar(cents: session.cents)
                    .frame(height: 14)
                    .padding(.horizontal, 10)

                // Cents
                Text(String(format: "%+.1f¢", session.cents))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tint)
            }
            .padding(.top, 8)
        }
        .onAppear {
            WatchSessionManager.shared.start()
        }
    }

    private var tint: Color {
        abs(session.cents) < 5 ? .green :
        abs(session.cents) < 15 ? .yellow : .red
    }
}

// MARK: - Tuner Bar

private struct TunerBar: View {
    let cents: Double

    private var clamped: Double {
        max(-25, min(25, cents))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = (clamped + 25) / 50 * width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.12))

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red)
                    .frame(width: 3, height: geo.size.height)
                    .offset(x: x - 1.5)
                    .animation(.easeOut(duration: 0.12), value: clamped)
            }
        }
    }
}
