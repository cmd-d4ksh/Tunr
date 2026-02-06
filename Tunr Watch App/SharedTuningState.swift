import Foundation
import Combine

final class SharedTuningState: ObservableObject {
    @Published var frequency: Double = 0
    @Published var noteName: String = "--"
    @Published var cents: Double = 0
    @Published var isInTune: Bool = false
}
