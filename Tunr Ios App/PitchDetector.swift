import Foundation
import AVFoundation
import Combine
import QuartzCore

final class PitchDetector: ObservableObject {

    // MARK: - Audio
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096
    private var sampleRate: Double = 44100  // Default, will be updated
    private var isRunning = false
    private var audioBuffer: [Float] = []
    private let bufferCapacity = 8192
    private var smoothedFreq: Double = 0
    private var smoothedCents: Double = 0
    private let smoothing: Double = 0.20
    private var lastPublishTime: CFTimeInterval = 0

    // MARK: - Published (UI)
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0
    @Published var closestTarget: GuitarNote? = nil
    @Published var lockedTarget: GuitarNote? = nil

    // MARK: - Init
    init() {
        print("🔧 PitchDetector init - engine created")
    }

    // MARK: - Control
    func start() {
        guard !isRunning else { return }
        isRunning = true

        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        // Capture actual sample rate from the format
        sampleRate = Double(format.sampleRate)
        
        print("🎛 Audio Format - sampleRate: \(format.sampleRate), channels: \(format.channelCount)")
        print("🎛 Stored sampleRate: \(sampleRate)")

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
            print("✅ Audio engine started")
        } catch {
            print("❌ Audio engine failed:", error)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        isRunning = false
    }

    // MARK: - Buffer Handling
    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        let newSamples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Add to rolling buffer
        audioBuffer.append(contentsOf: newSamples)
        if audioBuffer.count > bufferCapacity {
            audioBuffer.removeFirst(audioBuffer.count - bufferCapacity)
        }

        // Process a fixed-size recent window (more stable + faster)
        let windowSize = 4096
        guard audioBuffer.count >= windowSize else { return }
        let window = Array(audioBuffer.suffix(windowSize))
        process(signal: window)
    }

    // MARK: - Processing
    private func process(signal: [Float]) {
        // Apply Hann window
        let windowed = applyHannWindow(signal)

        // RMS gate
        let rms = sqrt(windowed.map { $0 * $0 }.reduce(0, +) / Float(windowed.count))
        print("📈 RMS: \(String(format: "%.6f", rms))")
        
        guard rms > 0.001 else {
            print("🔇 Signal too quiet")
            return
        }

        // Detect frequency using autocorrelation
        let detectedFrequency = autocorrelationPitch(signal: windowed)
        print("🔍 Autocorrelation returned: \(detectedFrequency) Hz")
        
        guard detectedFrequency > 70 && detectedFrequency < 400 else {
            print("❌ Frequency \(detectedFrequency) out of range [70-400]")
            return
        }

        print("✅ Valid detection: \(detectedFrequency) Hz")
        
        
        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.08 else { return }
        lastPublishTime = now
        
        DispatchQueue.main.async {

            // Smooth frequency (stability)
            let f = detectedFrequency
            self.smoothedFreq = (self.smoothedFreq == 0)
                ? f
                : (self.smoothing * f + (1 - self.smoothing) * self.smoothedFreq)

            self.frequency = self.smoothedFreq

            // Decide target: locked string OR auto-detected
            let target = self.lockedTarget
                ?? GuitarTuning.closestNote(to: self.smoothedFreq)

            if let note = target {
                self.closestTarget = note
                self.noteName = note.name

                let rawCents = GuitarTuning.centsOff(
                    from: self.smoothedFreq,
                    target: note.frequency
                )

                // Smooth cents
                self.smoothedCents = (self.smoothedCents == 0)
                    ? rawCents
                    : (self.smoothing * rawCents + (1 - self.smoothing) * self.smoothedCents)

                self.cents = self.smoothedCents
            }
        }

    }

    // MARK: - Hann Window
    private func applyHannWindow(_ signal: [Float]) -> [Float] {
        let n = signal.count
        return signal.enumerated().map { i, sample in
            let window = Float(0.5 * (1 - cos(2 * .pi * Double(i) / Double(n - 1))))
            return sample * window
        }
    }

    // MARK: - Autocorrelation Pitch Detection
    private func autocorrelationPitch(signal: [Float]) -> Double {
        let n = signal.count
        guard n >= 2048 else {
            print("⚠️ Signal too short: \(n) samples")
            return 0
        }

        // Compute autocorrelation
        let maxLag = n / 2
        var autocorr = [Float](repeating: 0, count: maxLag)

        let energy = signal.map { $0 * $0 }.reduce(0, +)
        guard energy > 0 else {
            print("⚠️ Zero energy signal")
            return 0
        }

        for lag in 0..<maxLag {
            var sum: Float = 0
            for i in 0..<(n - lag) {
                sum += signal[i] * signal[i + lag]
            }
            autocorr[lag] = sum / energy
        }

        // Find pitch period as the strongest peak after the first dip
        let minLagHz400 = max(Int(sampleRate / 400), 10)
        let maxLagHz70 = min(Int(sampleRate / 70), maxLag - 1)

        guard minLagHz400 < maxLagHz70 else { return 0 }

        // 1) Find first dip (correlation stops decreasing)
        var dip = minLagHz400
        for lag in (minLagHz400 + 1)..<maxLagHz70 {
            if autocorr[lag] > autocorr[lag - 1] {
                dip = lag
                break
            }
        }

        // 2) Find strongest peak after dip
        var bestLag = dip
        var bestValue: Float = -Float.greatestFiniteMagnitude

        for lag in dip..<maxLagHz70 {
            if autocorr[lag] > bestValue {
                bestValue = autocorr[lag]
                bestLag = lag
            }
        }

        // Reject weak peaks (noise)
        guard bestValue > 0.15 else { return 0 }

        let lag = bestLag


        if lag > 0 && lag < maxLag - 1 && autocorr.count > lag + 1 {
            let a = autocorr[lag - 1]
            let b = autocorr[lag]
            let c = autocorr[lag + 1]

            let denom = 2 * (a - 2 * b + c)
            if abs(denom) > 0.001 {
                let shift = (a - c) / denom
                let refinedLag = Float(lag) + shift
                let freq = sampleRate / Double(max(refinedLag, 1))
                return freq
            }
        }

        let freq = sampleRate / Double(max(lag, 1))
        return freq

    }
}
