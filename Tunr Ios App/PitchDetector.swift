import Foundation
import AVFoundation
import Combine
import QuartzCore
import WatchConnectivity
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
    private let smoothing: Double = 0.20
    private var lastPublishTime: CFTimeInterval = 0

    // MARK: - Published (UI)
    @Published var frequency: Double = 0.0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0.0
    @Published var closestTarget: GuitarNote? = nil
    @Published var lockedTarget: GuitarNote? = nil

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
            print("✅ PitchDetector engine started")
        } catch {
            print("❌ Engine start failed:", error)
        }
    }

    func stop() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()

        audioBuffer.removeAll(keepingCapacity: true)
        smoothedFreq = 0
        smoothedCents = 0
        lastPublishTime = 0

        isRunning = false
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

        // RMS gate (ignore silence)
        let rms = sqrt(signal.map { $0 * $0 }.reduce(0, +) / Float(signal.count))
        guard rms > 0.001 else { return }

        // Pitch detection
        let detectedFrequency = autocorrelationPitch(signal: signal)
        guard detectedFrequency > 70 && detectedFrequency < 400 else { return }

        // Throttle UI updates
        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.08 else { return }
        lastPublishTime = now

        DispatchQueue.main.async {

            // Smooth frequency
            self.smoothedFreq = (self.smoothedFreq == 0)
                ? detectedFrequency
                : (self.smoothing * detectedFrequency
                   + (1 - self.smoothing) * self.smoothedFreq)

            self.frequency = self.smoothedFreq

            // Determine target note
            let target = self.lockedTarget
                ?? GuitarTuning.closestNote(to: self.smoothedFreq)

            self.closestTarget = target
            self.noteName = target?.name ?? "--"

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
            }
            WatchSessionManager.shared.sendTuningUpdate(
                    freq: self.frequency,
                    note: self.noteName,
                    cents: self.cents)
        }
    }

    // MARK: - Autocorrelation Pitch Detection
    private func autocorrelationPitch(signal: [Float]) -> Double {

        let n = signal.count
        guard n >= 2048 else { return 0 }

        let minLag = Int(sampleRate / 400)
        let maxLag = min(Int(sampleRate / 70), n / 2)

        var bestLag = 0
        var bestValue: Float = 0

        for lag in minLag..<maxLag {
            var sum: Float = 0
            for i in 0..<(n - lag) {
                sum += signal[i] * signal[i + lag]
            }
            if sum > bestValue {
                bestValue = sum
                bestLag = lag
            }
        }

        guard bestLag > 0 else { return 0 }
        return sampleRate / Double(bestLag)
    }
}
