import Foundation

struct GuitarNote: Identifiable {
    let id = UUID()
    let name: String
    let frequency: Double
}

struct GuitarTuning {

    static let standard: [GuitarNote] = [
        GuitarNote(name: "E", frequency: 82.41),
        GuitarNote(name: "A", frequency: 110.00),
        GuitarNote(name: "D", frequency: 146.83),
        GuitarNote(name: "G", frequency: 196.00),
        GuitarNote(name: "B", frequency: 246.94),
        GuitarNote(name: "E", frequency: 329.63)
    ]

    static func closestNote(to frequency: Double) -> GuitarNote? {
        guard frequency > 0 else { return nil }

        return standard.min {
            abs($0.frequency - frequency) < abs($1.frequency - frequency)
        }
    }

    static func centsOff(from frequency: Double, target: Double) -> Double {
        1200 * log2(frequency / target)
    }
}
