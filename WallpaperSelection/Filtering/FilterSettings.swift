import Foundation

/// The order in which the library is walked.
enum PhotoOrder: String, CaseIterable {
    /// Shuffled again on every launch, rescan or settings change.
    case random
    case newestFirst
}

/// User-tunable filters and browsing options. Stored in UserDefaults so SettingsView can bind them with @AppStorage.
struct FilterSettings: Equatable {
    /// Reject if any person/face box covers more than this fraction of the image.
    var maxPersonArea: Double = 0.02
    /// Reject if any person/face box is taller than this fraction of the image height.
    var maxPersonHeight: Double = 0.20
    /// Reject if recognized text covers more than this fraction of the image.
    var maxTextCoverage: Double = 0.08
    /// Minimum pixel length of the shorter side (iPhone 16 screen is 1179 px wide).
    var minShortSide: Int = 1080

    var order: PhotoOrder = .random
    /// When on, only photos taken between `startDate` and the end of `endDate` are shown.
    var limitDates = false
    var startDate: Date = FilterSettings.defaultStartDate
    var endDate: Date = FilterSettings.defaultEndDate

    static let defaults = FilterSettings()

    static var defaultStartDate: Date {
        let calendar = Calendar.current
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        return calendar.startOfDay(for: yearAgo)
    }

    static var defaultEndDate: Date { Calendar.current.startOfDay(for: Date()) }

    enum Key {
        static let maxPersonArea = "filter.maxPersonArea"
        static let maxPersonHeight = "filter.maxPersonHeight"
        static let minShortSide = "filter.minShortSide"
        static let order = "filter.order"
        static let limitDates = "filter.limitDates"
        /// Stored as seconds since 1970 so @AppStorage can bind it.
        static let startDate = "filter.startDate"
        static let endDate = "filter.endDate"
    }

    static var current: FilterSettings {
        let d = UserDefaults.standard
        var s = FilterSettings()
        s.maxPersonArea = d.object(forKey: Key.maxPersonArea) as? Double ?? defaults.maxPersonArea
        s.maxPersonHeight = d.object(forKey: Key.maxPersonHeight) as? Double ?? defaults.maxPersonHeight
        s.minShortSide = d.object(forKey: Key.minShortSide) as? Int ?? defaults.minShortSide
        s.order = d.string(forKey: Key.order).flatMap(PhotoOrder.init(rawValue:)) ?? defaults.order
        s.limitDates = d.bool(forKey: Key.limitDates)
        if let start = d.object(forKey: Key.startDate) as? Double {
            s.startDate = Date(timeIntervalSince1970: start)
        }
        if let end = d.object(forKey: Key.endDate) as? Double {
            s.endDate = Date(timeIntervalSince1970: end)
        }
        return s
    }

    /// Dates only matter while the date limit is on, so a default date rolling over at midnight
    /// doesn't count as a change (which would restart the deck).
    static func == (lhs: FilterSettings, rhs: FilterSettings) -> Bool {
        lhs.maxPersonArea == rhs.maxPersonArea
            && lhs.maxPersonHeight == rhs.maxPersonHeight
            && lhs.maxTextCoverage == rhs.maxTextCoverage
            && lhs.minShortSide == rhs.minShortSide
            && lhs.order == rhs.order
            && lhs.limitDates == rhs.limitDates
            && (!lhs.limitDates || (lhs.startDate == rhs.startDate && lhs.endDate == rhs.endDate))
    }
}
