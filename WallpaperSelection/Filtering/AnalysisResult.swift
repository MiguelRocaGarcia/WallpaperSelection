import Foundation

/// Raw Vision measurements for one photo. Thresholds are applied later in `passes(_:)`,
/// so changing a setting doesn't require re-analyzing the library.
struct AnalysisResult: Codable, Equatable {
    var isPortrait: Bool
    var maxPersonArea: Double = 0
    var maxPersonHeight: Double = 0
    var hasAnimal: Bool = false
    var excludedLabel: String? = nil
    var textCoverage: Double = 0

    func passes(_ settings: FilterSettings) -> Bool {
        isPortrait
            && maxPersonArea <= settings.maxPersonArea
            && maxPersonHeight <= settings.maxPersonHeight
            && !hasAnimal
            && excludedLabel == nil
            && textCoverage <= settings.maxTextCoverage
    }
}
