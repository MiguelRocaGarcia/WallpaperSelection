import CoreML
import UIKit
import Vision

/// On-device analysis of a small thumbnail: people, animals, and "not a wallpaper" content
/// such as documents, food and text.
enum VisionFilter {
    static let labelConfidence: Float = 0.5

    /// Image classification needs the GPU/Neural Engine. The simulator can't create its model context and
    /// returns meaningless labels on the CPU, so classification only runs on a real device.
    static var isClassificationAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
    static let animalConfidence: Float = 0.6

    static let animalLabels: Set<String> = [
        "animal", "mammal", "pet", "dog", "cat", "canine", "feline", "puppy", "kitten",
        "bird", "horse", "cow", "sheep", "rodent", "rabbit", "reptile", "insect", "fish",
    ]

    static let excludedLabels: Set<String> = [
        "document", "receipt", "paper", "text", "handwriting", "screenshot", "menu",
        "whiteboard", "blackboard", "book", "computer", "monitor",
        "food", "meal", "dessert", "baked_goods", "drink", "beverage", "fruit", "vegetable",
        "tableware", "plate", "utensil",
        "selfie",
    ]

    static func analyze(_ image: UIImage) -> AnalysisResult {
        // UIImage.size is already oriented, unlike the raw pixel dimensions.
        var result = AnalysisResult(isPortrait: image.size.height > image.size.width)
        guard result.isPortrait, let cgImage = image.cgImage else { return result }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation)
        )

        let humans = VNDetectHumanRectanglesRequest()
        humans.upperBodyOnly = false
        let faces = VNDetectFaceRectanglesRequest()
        let animals = VNRecognizeAnimalsRequest()
        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false

        var requests: [VNRequest] = [humans, faces, animals, text]
        if isClassificationAvailable { requests.append(classify) }
        useCPUOnSimulator(requests)
        // Run one at a time so a failure in one request doesn't discard the others.
        for request in requests {
            try? handler.perform([request])
        }

        let personBoxes = (humans.results ?? []).map(\.boundingBox) + (faces.results ?? []).map(\.boundingBox)
        for box in personBoxes {
            result.maxPersonArea = max(result.maxPersonArea, Double(box.width * box.height))
            result.maxPersonHeight = max(result.maxPersonHeight, Double(box.height))
        }

        if (animals.results ?? []).contains(where: { $0.confidence >= animalConfidence }) {
            result.hasAnimal = true
        }

        for observation in classify.results ?? [] where observation.confidence >= labelConfidence {
            if animalLabels.contains(observation.identifier) {
                result.hasAnimal = true
            } else if result.excludedLabel == nil, excludedLabels.contains(observation.identifier) {
                result.excludedLabel = observation.identifier
            }
        }

        let textArea = (text.results ?? []).reduce(0.0) { sum, obs in
            sum + Double(obs.boundingBox.width * obs.boundingBox.height)
        }
        result.textCoverage = min(textArea, 1)

        return result
    }

    /// The simulator has no Neural Engine; some Vision requests fail unless forced onto the CPU.
    private static func useCPUOnSimulator(_ requests: [VNRequest]) {
        #if targetEnvironment(simulator)
        for request in requests {
            guard let devices = try? request.supportedComputeStageDevices else { continue }
            for (stage, stageDevices) in devices {
                if let cpu = stageDevices.first(where: { if case .cpu = $0 { return true } else { return false } }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
