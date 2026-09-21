import Foundation
import UIKit
import Vision

/// Esercizio riconosciuto dalla foto (modificabile prima del salvataggio).
struct ParsedExercise: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var sets: Int
    var reps: String
    var restTime: String
    var hasExplicitSets: Bool = false
}

struct ParsedDay: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var exercises: [ParsedExercise]
}

struct ParsedPlan: Identifiable, Hashable {
    var id = UUID()
    var days: [ParsedDay]
    var rawRows: [String]

    var exerciseCount: Int { days.reduce(0) { $0 + $1.exercises.count } }
}

/// Legge il testo della scheda con Vision (tutto sul dispositivo) e lo trasforma
/// in giorni ed esercizi.
enum PlanOCRService {

    // MARK: Riconoscimento testo

    static func recognizeRows(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["it-IT", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            try handler.perform([request])
            return PlanOCRService.groupIntoRows(request.results ?? [])
        }.value
    }

    /// Le tabelle vengono riconosciute cella per cella: qui le celle sulla stessa
    /// riga vengono unite in un'unica stringa, da sinistra a destra.
    private static func groupIntoRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        struct Item {
            let text: String
            let box: CGRect
        }

        let items = observations
            .compactMap { observation -> Item? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return Item(text: text, box: observation.boundingBox)
            }
            .sorted { $0.box.midY > $1.box.midY } // Vision: origine in basso a sinistra

        var rows: [[Item]] = []
        for item in items {
            if let current = rows.last, let reference = current.first {
                let tolerance = max(reference.box.height, item.box.height) * 0.6
                if abs(reference.box.midY - item.box.midY) < tolerance {
                    rows[rows.count - 1].append(item)
                    continue
                }
            }
            rows.append([item])
        }

        return rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    // MARK: Parsing

    static func parse(rows: [String]) -> [ParsedDay] {
        var days: [ParsedDay] = []
        var current = ParsedDay(name: "Giorno A", exercises: [])

        for raw in rows {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let dayName = dayHeader(in: line) {
                if !current.exercises.isEmpty {
                    days.append(current)
                }
                current = ParsedDay(name: dayName, exercises: [])
                continue
            }

            if isTableHeader(line) { continue }

            var remainder = line
            let setsReps = extractSetsReps(&remainder)
            let rest = extractRest(&remainder)
            let name = cleanName(remainder)

            if name.isEmpty {
                // Riga solo numerica (es. "4x10 90''" su una riga separata): completa l'esercizio precedente.
                if let index = current.exercises.indices.last {
                    if let setsReps, !current.exercises[index].hasExplicitSets {
                        current.exercises[index].sets = setsReps.sets
                        current.exercises[index].reps = setsReps.reps
                        current.exercises[index].hasExplicitSets = true
                    }
                    if let rest, current.exercises[index].restTime.isEmpty {
                        current.exercises[index].restTime = rest
                    }
                }
                continue
            }

            // Righe troppo corte senza dati numerici sono rumore (es. "A", "kg").
            if name.count < 3 && setsReps == nil { continue }

            current.exercises.append(
                ParsedExercise(
                    name: name,
                    sets: setsReps?.sets ?? 3,
                    reps: setsReps?.reps ?? "10",
                    restTime: rest ?? "",
                    hasExplicitSets: setsReps != nil
                )
            )
        }

        if !current.exercises.isEmpty || days.isEmpty {
            days.append(current)
        }
        return days
    }

    private static let weekdays = [
        "lunedì", "lunedi", "martedì", "martedi", "mercoledì", "mercoledi", "giovedì", "giovedi",
        "venerdì", "venerdi", "sabato", "domenica",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"
    ]

    private static let splitNames = ["push", "pull", "legs", "gambe", "upper", "lower", "full body", "fullbody", "spinta", "tirata", "petto", "schiena", "spalle", "braccia"]

    private static func dayHeader(in line: String) -> String? {
        let lower = line.lowercased().trimmingCharacters(in: .whitespaces)

        // "Giorno A", "Day 1", "Scheda B - Push", "Allenamento 2"
        if let c = RegexHelper.captures(#"^(?:giorno|day|scheda|workout|allenamento|sessione)\s*[:\-–]?\s*([a-d1-7])\b\s*[:\-–(]?\s*(.*?)\)?$"#, in: lower) {
            let label = c[1].uppercased()
            let extra = c[2].trimmingCharacters(in: .whitespaces)
            if extra.isEmpty || extra.count > 25 {
                return "Giorno \(label)"
            }
            return "Giorno \(label) · \(extra.capitalized)"
        }

        // Riga con una sola lettera: "A", "B:"
        if RegexHelper.matches(#"^[a-d]\s*[:\-–]?$"#, in: lower) {
            return "Giorno \(String(lower.prefix(1)).uppercased())"
        }

        // Giorno della settimana come intestazione
        if let weekday = weekdays.first(where: { lower.hasPrefix($0) }), lower.count <= weekday.count + 20 {
            return line.capitalized
        }

        // "Push", "Pull", "Legs", "Upper" da soli (senza numeri)
        let hasDigits = lower.contains { $0.isNumber }
        if !hasDigits, splitNames.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }), lower.count <= 20 {
            return line.capitalized
        }

        return nil
    }

    private static let headerWords: Set<String> = [
        "esercizio", "esercizi", "exercise", "serie", "sets", "set", "ripetizioni", "rip", "reps", "rep",
        "recupero", "rec", "rest", "riposo", "pausa", "peso", "kg", "carico", "note", "tempo", "tut",
        "n", "nr", "num", "numero"
    ]

    private static func isTableHeader(_ line: String) -> Bool {
        let tokens = line.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { headerWords.contains($0) }
    }

    private static func extractSetsReps(_ text: inout String) -> (sets: Int, reps: String)? {
        // 4x10, 4 x 8-12, 3×12, 4*10, 3 x 10/12, 4 x max
        let pattern = #"(\d{1,2})\s*[x×X*]\s*(\d{1,3}(?:\s*[-–/]\s*\d{1,3})?|max)"#
        if let c = RegexHelper.captures(pattern, in: text), let sets = Int(c[1]) {
            text = RegexHelper.removing(pattern, from: text)
            return (sets, c[2].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "–", with: "-"))
        }

        // "4 serie da 10", "4 serie x 8-12"
        let pattern2 = #"(\d{1,2})\s*serie\s*(?:da|x|di|per)?\s*(\d{1,3}(?:\s*[-–/]\s*\d{1,3})?)"#
        if let c = RegexHelper.captures(pattern2, in: text), let sets = Int(c[1]) {
            text = RegexHelper.removing(pattern2, from: text)
            return (sets, c[2].replacingOccurrences(of: " ", with: ""))
        }
        return nil
    }

    private static func extractRest(_ text: inout String) -> String? {
        let patterns = [
            // rec 90'' / recupero: 1'30 / rest 2 min
            #"(?:rec(?:upero)?|rest|riposo|pausa)\.?\s*[:=]?\s*(\d{1,2}['’′]\s*\d{0,2}(?:''|"|”)?|\d{1,3}\s*(?:''|"|”|″|sec|secondi|s|min|minuti|m)?)"#,
            // 1'30 / 1'30''
            #"\b(\d{1,2}['’′]\s*\d{1,2}(?:''|"|”)?)"#,
            // 90'' / 90" / 90 sec / 90s
            #"\b(\d{1,3}\s*(?:''|"|”|″|sec|secondi|s))(?![a-z])"#,
            // 2 min / 2m
            #"\b(\d{1,2}\s*(?:min|minuti|m))\b"#,
            // 2'
            #"\b(\d{1,2}['’′])(?!\d)"#
        ]
        for pattern in patterns {
            if let c = RegexHelper.captures(pattern, in: text), !c[1].trimmingCharacters(in: .whitespaces).isEmpty {
                text = RegexHelper.removing(pattern, from: text)
                return normalizeRest(c[1])
            }
        }
        return nil
    }

    private static func normalizeRest(_ raw: String) -> String {
        var value = raw
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "′", with: "'")
            .replacingOccurrences(of: "”", with: "''")
            .replacingOccurrences(of: "″", with: "''")
            .replacingOccurrences(of: "\"", with: "''")

        if let c = RegexHelper.captures(#"^(\d+)(?:sec|secondi|s)$"#, in: value) {
            value = "\(c[1])''"
        } else if let c = RegexHelper.captures(#"^(\d+)(?:min|minuti|m)$"#, in: value) {
            value = "\(c[1])'"
        } else if let c = RegexHelper.captures(#"^(\d+)$"#, in: value) {
            value = "\(c[1])''"
        }
        return value
    }

    private static func cleanName(_ text: String) -> String {
        var value = text
        // Parole residue e pesi ("kg 40", "40 kg")
        value = RegexHelper.removing(#"\b\d+(?:[.,]\d+)?\s*kg\b"#, from: value)
        value = RegexHelper.removing(#"\bkg\s*\d+(?:[.,]\d+)?\b"#, from: value)
        value = RegexHelper.removing(#"\b(?:rec(?:upero)?|rest|riposo|pausa|serie|reps?|rip\.?)\b"#, from: value)
        // Numerazione iniziale "1." / "1)" / "1 -"
        value = RegexHelper.removing(#"^\s*\d{1,2}\s*[.)\-–]\s*"#, from: value)
        // Sequenze di sola punteggiatura o numeri isolati alla fine
        value = RegexHelper.removing(#"\s+\d{1,3}\s*$"#, from: value)

        value = value
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–•.,;()|'\"\t"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        guard value.rangeOfCharacter(from: .letters) != nil else { return "" }
        return value.prefix(1).uppercased() + value.dropFirst()
    }
}
