import UIKit
import Vision
import XCTest
@testable import WallpaperSelection

/// Runs the real Vision pipeline on sample photos sorted into folders by expected outcome.
/// Photos are downscaled to 512 px first, like the thumbnails the app analyzes.
final class VisionFilterTests: XCTestCase {
    private let settings = FilterSettings.defaults

    private enum Expectation: String, CaseIterable {
        case keep, person, animal, food, text
    }

    func testFixturesAreClassifiedAsExpected() throws {
        var failures: [String] = []
        var report: [String] = []

        for expectation in Expectation.allCases {
            for url in try fixtures(in: expectation.rawValue) {
                let image = try thumbnail(url)
                let result = VisionFilter.analyze(image)
                let deviceOnly = !VisionFilter.isClassificationAvailable && (expectation == .food || expectation == .text)
                let ok = matches(result, expectation)
                let line = String(
                    format: "%@ %@/%@ area=%.3f height=%.2f animal=%@ label=%@ text=%.3f",
                    ok ? "✅" : (deviceOnly ? "⏭️" : "❌"), expectation.rawValue, url.lastPathComponent,
                    result.maxPersonArea, result.maxPersonHeight, result.hasAnimal ? "yes" : "no",
                    result.excludedLabel ?? "-", result.textCoverage
                )
                report.append(line)
                // Food and documents are caught by image classification, which only runs on a real device.
                if !ok && !deviceOnly { failures.append(line) }
            }
        }

        print("\n==== Vision fixture report ====\n" + report.joined(separator: "\n") + "\n===============================\n")
        XCTAssertTrue(failures.isEmpty, "Misclassified:\n" + failures.joined(separator: "\n"))
    }

    func testHorizontalPhotoIsRejectedAfterOrientation() throws {
        let url = try XCTUnwrap(fixtures(in: "metadata").first { $0.lastPathComponent == "horizontal_waterfall.jpg" })
        XCTAssertFalse(VisionFilter.analyze(try thumbnail(url)).passes(settings))
    }

    // MARK: Helpers

    private func matches(_ result: AnalysisResult, _ expectation: Expectation) -> Bool {
        let personTooBig = result.maxPersonArea > settings.maxPersonArea || result.maxPersonHeight > settings.maxPersonHeight
        switch expectation {
        case .keep: return result.passes(settings)
        case .person: return personTooBig
        case .animal: return result.hasAnimal
        case .food, .text: return !result.passes(settings) && !personTooBig
        }
    }

    private func fixtures(in folder: String) throws -> [URL] {
        let root = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Fixtures", withExtension: nil))
        return try FileManager.default
            .contentsOfDirectory(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func thumbnail(_ url: URL) throws -> UIImage {
        let image = try XCTUnwrap(UIImage(contentsOfFile: url.path))
        let scale = 512 / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
