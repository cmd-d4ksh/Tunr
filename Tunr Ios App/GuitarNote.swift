import Foundation

struct GuitarNote: Identifiable, Equatable {
    let id: String
    let name: String
    let stringNumber: Int   // 6 = low E, 1 = high E
    let frequency: Double
    let octave: Int

    /// Display name with octave (e.g. "E2", "A2")
    var displayName: String { "\(name)\(octave)" }

    /// Short label for string selector (e.g. "6E", "5A")
    var stringLabel: String { "\(stringNumber)\(name)" }

    static func == (lhs: GuitarNote, rhs: GuitarNote) -> Bool {
        lhs.id == rhs.id
    }
}

struct GuitarTuning {

    static let standard: [GuitarNote] = [
        GuitarNote(id: "6E", name: "E", stringNumber: 6, frequency: 82.41,  octave: 2),
        GuitarNote(id: "5A", name: "A", stringNumber: 5, frequency: 110.00, octave: 2),
        GuitarNote(id: "4D", name: "D", stringNumber: 4, frequency: 146.83, octave: 3),
        GuitarNote(id: "3G", name: "G", stringNumber: 3, frequency: 196.00, octave: 3),
        GuitarNote(id: "2B", name: "B", stringNumber: 2, frequency: 246.94, octave: 3),
        GuitarNote(id: "1E", name: "E", stringNumber: 1, frequency: 329.63, octave: 4),
    ]

    /// Find closest note using cents distance (logarithmic — perceptually uniform)
    static func closestNote(to frequency: Double) -> GuitarNote? {
        guard frequency > 0 else { return nil }

        return standard.min {
            abs(centsOff(from: frequency, target: $0.frequency)) <
            abs(centsOff(from: frequency, target: $1.frequency))
        }
    }

    /// Cents deviation from target frequency
    /// Positive = sharp, Negative = flat
    static func centsOff(from frequency: Double, target: Double) -> Double {
        guard target > 0, frequency > 0 else { return 0 }
        return 1200 * log2(frequency / target)
    }
}
