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
    var muscleGroup: MuscleGroup
    var durationMinutes: Int? = nil
    var hasExplicitSets: Bool = false
    var groupWasEdited: Bool = false

    var isTimed: Bool { durationMinutes != nil }
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
/// in giorni ed esercizi. Gestisce tabelle tipo ESERCIZIO | SERIE | REC. | KG,
/// blocchi separati da una riga vuota, recupero scritto una sola volta e
/// righe a tempo (riscaldamento, corsa, cyclette).
enum PlanOCRService {

    /// Riga vuota usata come separatore tra blocchi della tabella.
    static let separator = ""

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

    /// Le tabelle vengono riconosciute cella per cella: le celle sulla stessa riga
    /// vengono unite da sinistra a destra. Uno spazio verticale insolitamente grande
    /// (la riga vuota tra due blocchi) produce un separatore.
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

        let texts = rows.map { row in
            row.sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }
        let centers = rows.map { row in row.map(\.box.midY).reduce(0, +) / CGFloat(row.count) }

        // Distanza tipica tra righe consecutive: un salto molto più grande indica una riga vuota.
        var gaps: [CGFloat] = []
        for index in 1..<max(centers.count, 1) {
            gaps.append(centers[index - 1] - centers[index])
        }
        let median = gaps.sorted()[safe: gaps.count / 2] ?? 0

        var result: [String] = []
        for (index, text) in texts.enumerated() {
            if index > 0, median > 0, gaps[index - 1] > median * 1.7 {
                result.append(separator)
            }
            result.append(text)
        }
        return result
    }

    // MARK: Parsing

    static func parse(rows: [String]) -> [ParsedDay] {
        var days: [ParsedDay] = []
        var current = ParsedDay(name: dayName(at: 0), exercises: [])
        var currentRest: String?

        func closeDay(nextName: String? = nil) {
            if !current.exercises.isEmpty {
                days.append(current)
            }
            current = ParsedDay(name: nextName ?? dayName(at: days.count), exercises: [])
            currentRest = nil
        }

        for raw in rows {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            // Riga vuota tra due blocchi = nuovo giorno
            if line.isEmpty {
                closeDay()
                continue
            }

            if let header = dayHeader(in: line) {
                closeDay(nextName: header)
                continue
            }

            if isTableHeader(line) { continue }

            var remainder = line
            let setsReps = extractSetsReps(&remainder)

            // Righe a tempo: "5 min riscaldamento", "10 min corsa", "Cyclette 10 min"
            if setsReps == nil, let timed = extractTimed(line) {
                let isWarmup = timed.name.normalizedKey.contains("riscaldamento") || timed.name.normalizedKey.contains("warm")
                if isWarmup, current.exercises.contains(where: { !$0.isTimed }) {
                    closeDay()
                }
                current.exercises.append(
                    ParsedExercise(
                        name: timed.name,
                        sets: 1,
                        reps: "",
                        restTime: "",
                        muscleGroup: MuscleGroup.classify(timed.name),
                        durationMinutes: timed.minutes
                    )
                )
                continue
            }

            let rest = extractRest(&remainder)
            let name = cleanName(remainder)

            if name.isEmpty {
                // Riga solo numerica (es. "4x10 50''" su una riga separata): completa l'esercizio precedente.
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
                if let rest { currentRest = rest }
                continue
            }

            // Righe troppo corte senza dati numerici sono rumore (es. "A", "kg").
            if name.count < 3 && setsReps == nil { continue }

            if let rest { currentRest = rest }
            let group = MuscleGroup.classify(name)
            let defaultReps = group == .addome ? "15" : "10"

            current.exercises.append(
                ParsedExercise(
                    name: name,
                    sets: setsReps?.sets ?? 3,
                    reps: setsReps?.reps ?? defaultReps,
                    restTime: rest ?? currentRest ?? "",
                    muscleGroup: group,
                    hasExplicitSets: setsReps != nil
                )
            )
        }

        if !current.exercises.isEmpty || days.isEmpty {
            days.append(current)
        }
        return days
    }

    static func dayName(at index: Int) -> String {
        let letter = Character(UnicodeScalar(65 + min(index, 25))!)
        return "Giorno \(letter)"
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
        "esercizio", "esercizi", "exercise", "exercises", "serie", "sets", "set", "ripetizioni", "rip", "reps", "rep",
        "recupero", "rec", "rest", "riposo", "pausa", "peso", "kg", "carico", "note", "tempo", "tut",
        "n", "nr", "num", "numero", "total", "body", "uomo", "donna", "scheda"
    ]

    private static func isTableHeader(_ line: String) -> Bool {
        let tokens = line.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { headerWords.contains($0) }
    }

    /// "5 min riscaldamento", "10 min corsa", "Cyclette 10 min", "5' riscaldamento"
    private static func extractTimed(_ line: String) -> (name: String, minutes: Int)? {
        if let c = RegexHelper.captures(#"^(\d{1,3})\s*(?:min|minuti|mins|m|['’′])\s*(?:di\s+)?([a-zà-ù].*)$"#, in: line),
           let minutes = Int(c[1]) {
            let name = cleanName(c[2])
            if !name.isEmpty { return (name, minutes) }
        }
        if let c = RegexHelper.captures(#"^([a-zà-ù].*?)\s+(\d{1,3})\s*(?:min|minuti|mins)\b.*$"#, in: line),
           let minutes = Int(c[2]) {
            let name = cleanName(c[1])
            if !name.isEmpty { return (name, minutes) }
        }
        return nil
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

    /// Doppi apici in tutte le forme che l'OCR può restituire: '' ’’ ‘‘ " ” “ ″
    private static let secondsMark = #"(?:''|’’|‘‘|'’|’'|"|”|“|″)"#
    private static let minuteMark = #"['’‘′]"#

    private static func extractRest(_ text: inout String) -> String? {
        let patterns = [
            // rec 50'' / recupero: 1'30 / rest 2 min
            #"(?:rec(?:upero)?|rest|riposo|pausa)\.?\s*[:=]?\s*(\d{1,2}\#(minuteMark)\s*\d{0,2}\#(secondsMark)?|\d{1,3}\s*(?:\#(secondsMark)|sec|secondi|s|min|minuti|m)?)"#,
            // 1'30 / 1'30''
            #"\b(\d{1,2}\#(minuteMark)\s*\d{1,2}\#(secondsMark)?)"#,
            // 50'' / 50" / 50 sec / 50s
            #"\b(\d{1,3}\s*(?:\#(secondsMark)|sec|secondi|s))(?![a-z])"#,
            // 2 min / 2m
            #"\b(\d{1,2}\s*(?:min|minuti|m))\b"#,
            // 2'
            #"\b(\d{1,2}\#(minuteMark))(?!\d)"#
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
            .replacingOccurrences(of: "’’", with: "''")
            .replacingOccurrences(of: "‘‘", with: "''")
            .replacingOccurrences(of: "”", with: "''")
            .replacingOccurrences(of: "“", with: "''")
            .replacingOccurrences(of: "″", with: "''")
            .replacingOccurrences(of: "\"", with: "''")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "′", with: "'")

        if let c = RegexHelper.captures(#"^(\d+)(?:sec|secondi|s)$"#, in: value) {
            value = "\(c[1])''"
        } else if let c = RegexHelper.captures(#"^(\d+)(?:min|minuti|m)$"#, in: value) {
            value = "\(c[1])'"
        } else if let c = RegexHelper.captures(#"^(\d+)$"#, in: value) {
            value = "\(c[1])''"
        } else if let c = RegexHelper.captures(#"^(\d+)'$"#, in: value), let n = Int(c[1]), n >= 10 {
            // "50'" letto male: nessuno recupera 50 minuti, sono secondi
            value = "\(n)''"
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
        // Numeri isolati alla fine
        value = RegexHelper.removing(#"\s+\d{1,3}\s*$"#, from: value)

        value = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–•.,;()|'\"’”‘“\t"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)

        guard value.rangeOfCharacter(from: .letters) != nil else { return "" }
        return value.prefix(1).uppercased() + value.dropFirst()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
