import Foundation
import AVFoundation
import Combine

final class PitchDetector: ObservableObject {

    // MARK: - Audio
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 4096
    private var sampleRate: Double = 44100  // Default, will be updated
    private var isRunning = false
    private var audioBuffer: [Float] = []
    private let bufferCapacity = 8192

    // MARK: - Published (UI)
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0

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

        // Process when we have enough samples
        if audioBuffer.count >= 2048 {
            process(signal: audioBuffer)
        }
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
        
        DispatchQueue.main.async {
            print("📡 Publishing to UI: \(detectedFrequency) Hz")
            self.frequency = detectedFrequency

            if let note = GuitarTuning.closestNote(to: detectedFrequency) {
                self.noteName = note.name
                self.cents = GuitarTuning.centsOff(
                    from: detectedFrequency,
                    target: note.frequency
                )
                print("🎵 \(note.name) @ \(String(format: "%.1f", detectedFrequency)) Hz (\(String(format: "%.1f", self.cents)) ¢)")
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

        // Find first minimum after initial peak
        var minLag = 1
        var minValue: Float = 1.0

        // Start search from lag corresponding to ~400 Hz (high note) to ~70 Hz (low note)
        let minLagHz400 = max(Int(sampleRate / 400), 10)
        let maxLagHz70 = min(Int(sampleRate / 70), maxLag - 1)

        print("🔎 Search range: \(minLagHz400)..<\(maxLagHz70) (sample rate: \(sampleRate))")

        // Ensure valid range
        guard minLagHz400 < maxLagHz70 else {
            print("⚠️ Invalid search range")
            return 0
        }

        for lag in minLagHz400..<maxLagHz70 {
            if autocorr[lag] < minValue {
                minValue = autocorr[lag]
                minLag = lag
            }
        }

        print("📊 Min lag: \(minLag), Min value: \(String(format: "%.4f", minValue))")

        // Parabolic interpolation for sub-sample accuracy
        if minLag > 0 && minLag < maxLag - 1 && autocorr.count > minLag + 1 {
            let a = autocorr[minLag - 1]
            let b = autocorr[minLag]
            let c = autocorr[minLag + 1]

            let denom = 2 * (a - 2 * b + c)
            if abs(denom) > 0.001 {
                let shift = (a - c) / denom
                let refinedLag = Float(minLag) + shift
                let freq = sampleRate / Double(max(refinedLag, 1))
                print("🎯 Refined lag: \(String(format: "%.2f", refinedLag)) → \(String(format: "%.2f", freq)) Hz")
                return freq
            }
        }

        let freq = sampleRate / Double(max(minLag, 1))
        print("🎯 Direct lag: \(minLag) → \(String(format: "%.2f", freq)) Hz")
        return freq
    }
}
