import Foundation
import UIKit
import ImageIO

enum RegexHelper {
    /// Ritorna i gruppi catturati (indice 0 = intera corrispondenza) oppure nil.
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: text) else { return "" }
            return String(text[swiftRange])
        }
    }

    static func matches(_ pattern: String, in text: String) -> Bool {
        captures(pattern, in: text) != nil
    }

    static func removing(_ pattern: String, from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }
}

/// Converte il recupero scritto sulla scheda ("90''", "1'30", "2 min") in secondi.
enum RestTimeParser {
    static func seconds(from text: String) -> Int? {
        let compact = text
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "”", with: "''")
            .replacingOccurrences(of: "″", with: "''")
            .replacingOccurrences(of: "\"", with: "''")
        guard !compact.isEmpty else { return nil }

        // 1'30 / 1'30'' / 1:30
        if let c = RegexHelper.captures(#"^(\d{1,2})[':](\d{1,2})(?:'')?$"#, in: compact),
           let minutes = Int(c[1]), let seconds = Int(c[2]) {
            return minutes * 60 + seconds
        }
        // 2' / 2min / 2m
        if let c = RegexHelper.captures(#"^(\d{1,2})(?:'|min|minuti|m)$"#, in: compact),
           let minutes = Int(c[1]) {
            return minutes * 60
        }
        // 90'' / 90s / 90sec / 90
        if let c = RegexHelper.captures(#"^(\d{1,3})(?:''|s|sec|secondi)?$"#, in: compact),
           let seconds = Int(c[1]) {
            return seconds
        }
        return nil
    }

    static func format(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

extension UIImage {
    /// Ridimensiona l'immagine per non gonfiare il database.
    func resized(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
