import Foundation
import AVFoundation
import Combine
import QuartzCore
import Accelerate

final class PitchDetector: ObservableObject {

    // MARK: - Audio Engine
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096
    private var sampleRate: Double = 44100
    private var isRunning = false

    // Rolling audio buffer
    private var audioBuffer: [Float] = []
    private let bufferCapacity = 8192

    // Smoothing & timing
    private var smoothedFreq: Double = 0
    private var smoothedCents: Double = 0
    private let smoothing: Double = 0.25
    private var lastPublishTime: CFTimeInterval = 0

    // Median filter for stability
    private var recentFrequencies: [Double] = []
    private let medianWindowSize = 5

    // Confidence tracking
    private var consecutiveInTune = 0

    // MARK: - Published (UI)
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0
    @Published var closestTarget: GuitarNote? = nil
    @Published var lockedTarget: GuitarNote? = nil
    @Published var isActive: Bool = false
    @Published var signalStrength: Double = 0.0

    // MARK: - Start / Stop
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        sampleRate = format.sampleRate

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format
        ) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        engine.prepare()

        do {
            try engine.start()
            DispatchQueue.main.async { self.isActive = true }
        } catch {
            print("Engine start failed: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        audioBuffer.removeAll(keepingCapacity: true)
        recentFrequencies.removeAll()
        smoothedFreq = 0
        smoothedCents = 0
        lastPublishTime = 0
        consecutiveInTune = 0

        isRunning = false
        DispatchQueue.main.async {
            self.isActive = false
            self.frequency = 0
            self.noteName = "--"
            self.cents = 0
            self.signalStrength = 0
        }
    }

    // MARK: - Audio Buffer Handling
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        audioBuffer.append(contentsOf: samples)

        if audioBuffer.count > bufferCapacity {
            audioBuffer.removeFirst(audioBuffer.count - bufferCapacity)
        }

        let windowSize = 4096
        guard audioBuffer.count >= windowSize else { return }

        let window = Array(audioBuffer.suffix(windowSize))
        process(signal: window)
    }

    // MARK: - Signal Processing
    private func process(signal: [Float]) {

        // RMS for signal strength and silence gating
        let rms = computeRMS(signal)
        guard rms > 0.005 else {
            // Signal too quiet — reset display after brief delay
            let now = CACurrentMediaTime()
            if now - lastPublishTime > 0.5 {
                DispatchQueue.main.async {
                    self.signalStrength = 0
                    if self.frequency > 0 {
                        self.frequency = 0
                        self.noteName = "--"
                        self.cents = 0
                        self.consecutiveInTune = 0
                    }
                }
                lastPublishTime = now
            }
            return
        }

        // Apply Hann window to reduce spectral leakage
        let windowed = applyHannWindow(signal)

        // Pitch detection via normalized autocorrelation
        guard let detectedFrequency = normalizedAutocorrelationPitch(signal: windowed) else { return }

        // Frequency must be in guitar range (drop D to high E + headroom)
        guard detectedFrequency > 60 && detectedFrequency < 400 else { return }

        // Median filter to reject outlier readings
        recentFrequencies.append(detectedFrequency)
        if recentFrequencies.count > medianWindowSize {
            recentFrequencies.removeFirst()
        }
        let stableFreq = medianValue(recentFrequencies)

        // Throttle UI updates (~16ms = 60fps max)
        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.05 else { return }
        lastPublishTime = now

        DispatchQueue.main.async {

            // Smooth frequency with exponential moving average
            self.smoothedFreq = (self.smoothedFreq == 0)
                ? stableFreq
                : (self.smoothing * stableFreq
                   + (1 - self.smoothing) * self.smoothedFreq)

            self.frequency = self.smoothedFreq
            self.signalStrength = min(Double(rms) * 10, 1.0)

            // Determine target note
            let target = self.lockedTarget
                ?? GuitarTuning.closestNote(to: self.smoothedFreq)

            self.closestTarget = target
            self.noteName = target?.displayName ?? "--"

            if let note = target {
                let rawCents = GuitarTuning.centsOff(
                    from: self.smoothedFreq,
                    target: note.frequency
                )

                // Smooth cents
                self.smoothedCents = (self.smoothedCents == 0)
                    ? rawCents
                    : (self.smoothing * rawCents
                       + (1 - self.smoothing) * self.smoothedCents)

                self.cents = self.smoothedCents

                // Track consecutive in-tune readings
                if abs(self.smoothedCents) < 3 {
                    self.consecutiveInTune += 1
                } else {
                    self.consecutiveInTune = 0
                }
            }

            WatchSessionManager.shared.sendTuningUpdate(
                freq: self.frequency,
                note: self.noteName,
                cents: self.cents
            )
        }
    }

    // MARK: - Hann Window
    private func applyHannWindow(_ signal: [Float]) -> [Float] {
        let n = signal.count
        var windowed = [Float](repeating: 0, count: n)
        var window = [Float](repeating: 0, count: n)

        // Use Accelerate to generate Hann window efficiently
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(signal, 1, window, 1, &windowed, 1, vDSP_Length(n))

        return windowed
    }

    // MARK: - Normalized Autocorrelation Pitch Detection
    private func normalizedAutocorrelationPitch(signal: [Float]) -> Double? {

        let n = signal.count
        guard n >= 2048 else { return nil }

        // Lag range for guitar: ~60 Hz (low) to ~400 Hz (high)
        let minLag = Int(sampleRate / 400)   // ~110 samples
        let maxLag = min(Int(sampleRate / 60), n / 2)  // ~735 samples

        // Compute energy at lag 0 for normalization
        var energy0: Float = 0
        vDSP_dotpr(signal, 1, signal, 1, &energy0, vDSP_Length(n))

        guard energy0 > 0 else { return nil }

        // Compute normalized autocorrelation for each lag
        var bestLag = 0
        var bestCorrelation: Float = 0
        var correlations = [Float](repeating: 0, count: maxLag + 1)

        for lag in minLag...maxLag {
            // Cross-correlation at this lag
            var crossCorr: Float = 0
            vDSP_dotpr(signal, 1,
                       Array(signal[lag..<n]), 1,
                       &crossCorr,
                       vDSP_Length(n - lag))

            // Energy of the shifted signal segment
            let shifted = Array(signal[lag..<n])
            var energyLag: Float = 0
            vDSP_dotpr(shifted, 1, shifted, 1, &energyLag, vDSP_Length(n - lag))

            // Normalized correlation
            let denom = sqrt(energy0 * energyLag)
            let normalized = denom > 0 ? crossCorr / denom : 0
            correlations[lag] = normalized

            if normalized > bestCorrelation {
                bestCorrelation = normalized
                bestLag = lag
            }
        }

        // Require minimum correlation confidence
        guard bestCorrelation > 0.3, bestLag > 0 else { return nil }

        // Parabolic interpolation for sub-sample accuracy
        let refinedLag = parabolicInterpolation(
            correlations: correlations,
            peak: bestLag,
            minLag: minLag,
            maxLag: maxLag
        )

        let frequency = sampleRate / refinedLag

        // Octave error correction: check if half-lag has similar correlation
        let halfLag = bestLag / 2
        if halfLag >= minLag {
            let halfCorr = correlations[halfLag]
            // If half-lag correlation is close to best, we likely have an octave error
            if halfCorr > bestCorrelation * 0.85 {
                let correctedFreq = sampleRate / Double(halfLag)
                if correctedFreq > 60 && correctedFreq < 400 {
                    return correctedFreq
                }
            }
        }

        return frequency
    }

    // MARK: - Parabolic Interpolation
    private func parabolicInterpolation(
        correlations: [Float],
        peak: Int,
        minLag: Int,
        maxLag: Int
    ) -> Double {
        guard peak > minLag && peak < maxLag else {
            return Double(peak)
        }

        let alpha = correlations[peak - 1]
        let beta = correlations[peak]
        let gamma = correlations[peak + 1]

        let denominator = alpha - 2 * beta + gamma
        guard abs(denominator) > 1e-10 else { return Double(peak) }

        let delta = 0.5 * Double(alpha - gamma) / Double(denominator)
        return Double(peak) + delta
    }

    // MARK: - Utilities
    private func computeRMS(_ signal: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(signal, 1, &rms, vDSP_Length(signal.count))
        return rms
    }

    private func medianValue(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
