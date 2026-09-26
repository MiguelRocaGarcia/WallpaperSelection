import XCTest
@testable import WallpaperSelection

final class FilterTests: XCTestCase {
    private let settings = FilterSettings.defaults

    // MARK: Metadata

    func testPortraitPhotoPasses() {
        XCTAssertTrue(MetadataFilter.passes(width: 3024, height: 4032, isScreenshot: false, minShortSide: 1080))
    }

    func testLandscapeAndSquareAreRejected() {
        XCTAssertFalse(MetadataFilter.passes(width: 4032, height: 3024, isScreenshot: false, minShortSide: 1080))
        XCTAssertFalse(MetadataFilter.passes(width: 3024, height: 3024, isScreenshot: false, minShortSide: 1080))
    }

    func testScreenshotIsRejected() {
        XCTAssertFalse(MetadataFilter.passes(width: 1179, height: 2556, isScreenshot: true, minShortSide: 1080))
    }

    func testLowResolutionIsRejected() {
        XCTAssertFalse(MetadataFilter.passes(width: 720, height: 1280, isScreenshot: false, minShortSide: 1080))
        XCTAssertTrue(MetadataFilter.passes(width: 720, height: 1280, isScreenshot: false, minShortSide: 720))
    }

    // MARK: Vision results

    func testCleanLandscapePasses() {
        XCTAssertTrue(AnalysisResult(isPortrait: true).passes(settings))
    }

    func testTinyDistantPersonPasses() {
        let result = AnalysisResult(isPortrait: true, maxPersonArea: 0.004, maxPersonHeight: 0.08)
        XCTAssertTrue(result.passes(settings))
    }

    func testProminentPersonIsRejected() {
        let result = AnalysisResult(isPortrait: true, maxPersonArea: 0.15, maxPersonHeight: 0.6)
        XCTAssertFalse(result.passes(settings))
    }

    func testTallButThinPersonIsRejected() {
        let result = AnalysisResult(isPortrait: true, maxPersonArea: 0.015, maxPersonHeight: 0.35)
        XCTAssertFalse(result.passes(settings))
    }

    func testLooserSettingsAllowCloserPeople() {
        var loose = settings
        loose.maxPersonArea = 0.10
        loose.maxPersonHeight = 0.50
        let result = AnalysisResult(isPortrait: true, maxPersonArea: 0.05, maxPersonHeight: 0.3)
        XCTAssertFalse(result.passes(settings))
        XCTAssertTrue(result.passes(loose))
    }

    func testAnimalFoodAndTextAreRejected() {
        XCTAssertFalse(AnalysisResult(isPortrait: true, hasAnimal: true).passes(settings))
        XCTAssertFalse(AnalysisResult(isPortrait: true, excludedLabel: "food").passes(settings))
        XCTAssertFalse(AnalysisResult(isPortrait: true, textCoverage: 0.3).passes(settings))
    }

    func testOrientedLandscapeIsRejected() {
        XCTAssertFalse(AnalysisResult(isPortrait: false).passes(settings))
    }

    func testAnalysisResultRoundTripsThroughJSON() throws {
        let original = AnalysisResult(isPortrait: true, maxPersonArea: 0.01, maxPersonHeight: 0.1,
                                      hasAnimal: false, excludedLabel: "document", textCoverage: 0.02)
        let decoded = try JSONDecoder().decode(AnalysisResult.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    // MARK: Order and dates

    func testDefaultsAreRandomWithoutDateLimit() {
        XCTAssertEqual(settings.order, .random)
        XCTAssertFalse(settings.limitDates)
    }

    func testOrderAndDateChangesAreDetected() {
        var newest = settings
        newest.order = .newestFirst
        XCTAssertNotEqual(newest, settings)

        var limited = settings
        limited.limitDates = true
        XCTAssertNotEqual(limited, settings)

        var otherRange = limited
        otherRange.startDate = limited.startDate.addingTimeInterval(-86_400)
        XCTAssertNotEqual(otherRange, limited)
    }

    func testDatesAreIgnoredWhileDateLimitIsOff() {
        var shifted = settings
        shifted.startDate = settings.startDate.addingTimeInterval(-86_400 * 30)
        XCTAssertEqual(shifted, settings)
    }

    func testDatePredicateIncludesWholeEndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        func date(_ string: String) -> Date {
            let f = ISO8601DateFormatter()
            f.timeZone = calendar.timeZone
            f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]
            return f.date(from: string)!
        }
        let predicate = PhotoLibraryService.datePredicate(
            start: date("2024-03-10T15:00:00"), end: date("2024-03-20T08:00:00"), calendar: calendar)
        func matches(_ s: String) -> Bool { predicate.evaluate(with: ["creationDate": date(s)] as NSDictionary) }

        XCTAssertFalse(matches("2024-03-09T23:59:59"))
        XCTAssertTrue(matches("2024-03-10T00:00:00"), "start day counts from midnight")
        XCTAssertTrue(matches("2024-03-15T12:00:00"))
        XCTAssertTrue(matches("2024-03-20T23:59:59"), "end day is included entirely")
        XCTAssertFalse(matches("2024-03-21T00:00:00"))
    }
}
