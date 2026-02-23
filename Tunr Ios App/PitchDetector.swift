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

    // YIN threshold — lower = stricter pitch confidence
    private let yinThreshold: Float = 0.15

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

        let rms = sqrt(signal.map { $0 * $0 }.reduce(0, +) / Float(signal.count))
        guard rms > 0.005 else { return }

        let detectedFrequency = yinPitch(signal: applyHannWindow(signal))
        guard detectedFrequency > 70 && detectedFrequency < 400 else { return }

        let now = CACurrentMediaTime()
        guard now - lastPublishTime > 0.06 else { return }
        lastPublishTime = now

        DispatchQueue.main.async {
            self.smoothedFreq = (self.smoothedFreq == 0)
                ? detectedFrequency
                : (self.smoothing * detectedFrequency
                   + (1 - self.smoothing) * self.smoothedFreq)

            self.frequency = self.smoothedFreq

            let target = self.lockedTarget
                ?? GuitarTuning.closestNote(to: self.smoothedFreq)

            self.closestTarget = target
            self.noteName = target?.name ?? "--"

            if let note = target {
                let rawCents = GuitarTuning.centsOff(
                    from: self.smoothedFreq,
                    target: note.frequency
                )

                self.smoothedCents = (self.smoothedCents == 0)
                    ? rawCents
                    : (self.smoothing * rawCents
                       + (1 - self.smoothing) * self.smoothedCents)

                self.cents = self.smoothedCents
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
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(signal, 1, window, 1, &windowed, 1, vDSP_Length(n))
        return windowed
    }

    // MARK: - YIN Pitch Detection
    private func yinPitch(signal: [Float]) -> Double {
        let halfLen = signal.count / 2
        let minLag = Int(sampleRate / 400)   // highest freq we care about
        let maxLag = min(Int(sampleRate / 70), halfLen)  // lowest freq
        guard maxLag > minLag else { return 0 }

        // Step 1 & 2: Difference function + cumulative mean normalized difference
        var diff = [Float](repeating: 0, count: maxLag)
        var cmndf = [Float](repeating: 0, count: maxLag)

        for tau in 1..<maxLag {
            var sum: Float = 0
            for i in 0..<halfLen {
                let delta = signal[i] - signal[i + tau]
                sum += delta * delta
            }
            diff[tau] = sum
        }

        cmndf[0] = 1.0
        var runningSum: Float = 0
        for tau in 1..<maxLag {
            runningSum += diff[tau]
            cmndf[tau] = (runningSum > 0) ? diff[tau] * Float(tau) / runningSum : 1.0
        }

        // Step 3: Absolute threshold — find the first dip below threshold
        var bestTau = 0
        for tau in minLag..<maxLag {
            if cmndf[tau] < yinThreshold {
                bestTau = tau
                // Walk to the local minimum
                while bestTau + 1 < maxLag && cmndf[bestTau + 1] < cmndf[bestTau] {
                    bestTau += 1
                }
                break
            }
        }

        // Fallback: if no dip below threshold, pick the global minimum
        if bestTau == 0 {
            var minVal: Float = .greatestFiniteMagnitude
            for tau in minLag..<maxLag {
                if cmndf[tau] < minVal {
                    minVal = cmndf[tau]
                    bestTau = tau
                }
            }
        }

        guard bestTau > 0 else { return 0 }

        // Step 4: Parabolic interpolation for sub-sample accuracy
        let refinedTau = parabolicInterpolation(cmndf, bestTau)

        return sampleRate / Double(refinedTau)
    }

    // MARK: - Parabolic Interpolation
    private func parabolicInterpolation(_ data: [Float], _ peak: Int) -> Float {
        guard peak > 0, peak < data.count - 1 else { return Float(peak) }

        let a = data[peak - 1]
        let b = data[peak]
        let c = data[peak + 1]

        let denominator = 2.0 * (a - 2.0 * b + c)
        guard abs(denominator) > 1e-10 else { return Float(peak) }

        let shift = (a - c) / denominator
        return Float(peak) + shift
    }
}
