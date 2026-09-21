import Foundation
import SwiftData

// MARK: - Scheda

/// La scheda di allenamento (importata da foto o creata a mano).
@Model
final class WorkoutPlan {
    var name: String
    var createdAt: Date
    var isActive: Bool
    @Attribute(.externalStorage) var photoData: Data?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutDay.plan) var days: [WorkoutDay] = []

    init(name: String, createdAt: Date = .now, isActive: Bool = true, photoData: Data? = nil) {
        self.name = name
        self.createdAt = createdAt
        self.isActive = isActive
        self.photoData = photoData
    }

    var sortedDays: [WorkoutDay] {
        days.sorted { $0.order < $1.order }
    }

    var exerciseCount: Int {
        days.reduce(0) { $0 + $1.exercises.count }
    }
}

/// Un giorno della scheda (es. "Giorno A", "Push", "Lunedì").
@Model
final class WorkoutDay {
    var name: String
    var order: Int
    var plan: WorkoutPlan?
    @Relationship(deleteRule: .cascade, inverse: \Exercise.day) var exercises: [Exercise] = []
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSession.day) var sessions: [WorkoutSession] = []

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }

    var sortedExercises: [Exercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

/// Un esercizio della scheda. Il recupero (`restTime`) è fisso: è quello scritto
/// sulla scheda e non si modifica durante l'allenamento.
@Model
final class Exercise {
    var name: String
    var order: Int
    var sets: Int
    var reps: String          // "10" oppure "8-12"
    var restTime: String      // es. "90''", "1'30", "2'"
    var notes: String
    var targetWeight: Double? // nuovo peso da raggiungere
    var day: WorkoutDay?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise) var logs: [SetLog] = []

    init(name: String, order: Int, sets: Int = 3, reps: String = "10", restTime: String = "", notes: String = "", targetWeight: Double? = nil) {
        self.name = name
        self.order = order
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
        self.notes = notes
        self.targetWeight = targetWeight
    }

    var setsRepsLabel: String { "\(sets) × \(reps)" }

    var restSeconds: Int? { RestTimeParser.seconds(from: restTime) }

    /// Numero di ripetizioni "base" (il primo numero di "8-12" è 8).
    var defaultReps: Int {
        let numbers = reps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.first ?? 10
    }

    /// Ripetizioni massime del range ("8-12" → 12).
    var targetRepsUpper: Int {
        let numbers = reps.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numbers.max() ?? defaultReps
    }

    // MARK: Storico

    func completedLogs(excluding session: WorkoutSession? = nil) -> [SetLog] {
        logs.filter { log in
            guard log.completed else { return false }
            if let session, log.session?.persistentModelID == session.persistentModelID {
                return false
            }
            return true
        }
    }

    func personalRecord(excluding session: WorkoutSession? = nil) -> Double? {
        completedLogs(excluding: session).map(\.weight).max()
    }

    /// Le serie dell'ultimo allenamento completato (escludendo eventualmente quello in corso).
    func lastSessionLogs(excluding session: WorkoutSession? = nil) -> [SetLog] {
        let completed = completedLogs(excluding: session)
        guard let latest = completed.max(by: { $0.date < $1.date }) else { return [] }
        let latestID = latest.session?.persistentModelID
        return completed
            .filter { $0.session?.persistentModelID == latestID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    func lastWeight(forSet index: Int, excluding session: WorkoutSession? = nil) -> Double? {
        let last = lastSessionLogs(excluding: session)
        return last.first { $0.setIndex == index }?.weight ?? last.last?.weight
    }

    func lastSessionSummary(excluding session: WorkoutSession? = nil) -> String? {
        let last = lastSessionLogs(excluding: session)
        guard !last.isEmpty else { return nil }
        let series = last.map { "\($0.weight.kgString)×\($0.reps)" }.joined(separator: "  ")
        let date = last[0].date.formatted(.dateTime.day().month(.abbreviated))
        return "\(date) · \(series)"
    }

    /// Se nell'ultima sessione hai completato tutte le serie con le ripetizioni massime,
    /// suggerisce il prossimo peso (+2,5 kg).
    func suggestedNextWeight(excluding session: WorkoutSession? = nil) -> Double? {
        let last = lastSessionLogs(excluding: session)
        guard !last.isEmpty, last.count >= sets else { return nil }
        guard last.allSatisfy({ $0.reps >= targetRepsUpper }) else { return nil }
        let best = last.map(\.weight).max() ?? 0
        guard best > 0 else { return nil }
        return best + 2.5
    }

    /// Un punto per ogni allenamento: peso massimo, volume, numero serie.
    var progressPoints: [ProgressPoint] {
        let completed = completedLogs()
        let grouped = Dictionary(grouping: completed) { $0.session?.persistentModelID }
        return grouped.values.compactMap { group -> ProgressPoint? in
            guard let first = group.first else { return nil }
            let date = first.session?.date ?? first.date
            let maxWeight = group.map(\.weight).max() ?? 0
            let volume = group.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            return ProgressPoint(date: date, maxWeight: maxWeight, volume: volume, sets: group.count)
        }
        .sorted { $0.date < $1.date }
    }
}

struct ProgressPoint: Identifiable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
    let volume: Double
    let sets: Int
}

// MARK: - Allenamenti registrati

/// Un allenamento svolto in un certo giorno.
@Model
final class WorkoutSession {
    var date: Date
    var finishedAt: Date?
    var notes: String
    var day: WorkoutDay?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session) var sets: [SetLog] = []

    init(date: Date = .now, notes: String = "") {
        self.date = date
        self.notes = notes
    }

    var dayName: String { day?.name ?? "Allenamento" }

    var isFinished: Bool { finishedAt != nil }

    var completedSets: [SetLog] { sets.filter(\.completed) }

    var totalVolume: Double {
        completedSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
    }

    func logs(for exercise: Exercise) -> [SetLog] {
        let id = exercise.persistentModelID
        return sets
            .filter { $0.exercise?.persistentModelID == id }
            .sorted { $0.setIndex < $1.setIndex }
    }

    /// Serie completate raggruppate per esercizio, nell'ordine della scheda.
    var completedSetsByExercise: [(name: String, order: Int, logs: [SetLog])] {
        let grouped = Dictionary(grouping: completedSets) { $0.exercise?.persistentModelID }
        return grouped.values.compactMap { group -> (name: String, order: Int, logs: [SetLog])? in
            guard let first = group.first else { return nil }
            return (
                name: first.exercise?.name ?? "Esercizio",
                order: first.exercise?.order ?? Int.max,
                logs: group.sorted { $0.setIndex < $1.setIndex }
            )
        }
        .sorted { $0.order < $1.order }
    }
}

/// Una singola serie registrata: peso, ripetizioni e se è stata completata.
@Model
final class SetLog {
    var setIndex: Int
    var weight: Double
    var reps: Int
    var completed: Bool
    var date: Date
    var exercise: Exercise?
    var session: WorkoutSession?

    init(setIndex: Int, weight: Double, reps: Int, completed: Bool = false, date: Date = .now) {
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.completed = completed
        self.date = date
    }
}

// MARK: - Formattazione

extension Double {
    /// "60" oppure "62,5" (segue la lingua del telefono).
    var kgString: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}
