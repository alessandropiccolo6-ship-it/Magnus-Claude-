import Foundation
import SwiftData

/// Serie storica di un esercizio, unita tra tutte le schede per nome.
struct ExerciseSeries: Identifiable, Hashable {
    let id: String
    let name: String
    let group: MuscleGroup
    let points: [ProgressPoint]

    var best: Double? { points.map(\.maxWeight).max() }
    var last: Double? { points.last?.maxWeight }
    var first: Double? { points.first?.maxWeight }
    var sessionsCount: Int { points.count }
}

struct WeekBucket: Identifiable {
    let id: Date
    let value: Double
}

/// Tutte le serie completate, lette per nome esercizio e gruppo muscolare:
/// così i dati restano confrontabili anche quando la scheda cambia.
struct ExerciseHistory {
    let logs: [SetLog]

    init(logs: [SetLog]) {
        self.logs = logs.filter(\.completed)
    }

    private func isExcluded(_ log: SetLog, _ session: WorkoutSession?) -> Bool {
        guard let session else { return false }
        return log.session?.persistentModelID == session.persistentModelID
    }

    // MARK: Per esercizio

    func logs(named key: String, excluding session: WorkoutSession? = nil) -> [SetLog] {
        logs.filter { $0.normalizedName == key && !$0.isTimed && !isExcluded($0, session) }
    }

    func logs(for exercise: Exercise, excluding session: WorkoutSession? = nil) -> [SetLog] {
        logs(named: exercise.normalizedName, excluding: session)
    }

    func personalRecord(for exercise: Exercise, excluding session: WorkoutSession? = nil) -> Double? {
        logs(for: exercise, excluding: session).map(\.weight).max()
    }

    /// Le serie dell'ultimo allenamento in cui hai fatto questo esercizio (anche con un'altra scheda).
    func lastSessionLogs(for exercise: Exercise, excluding session: WorkoutSession? = nil) -> [SetLog] {
        let all = logs(for: exercise, excluding: session)
        guard let latest = all.max(by: { $0.date < $1.date }) else { return [] }
        let latestID = latest.session?.persistentModelID
        return all
            .filter { $0.session?.persistentModelID == latestID }
            .sorted { $0.setIndex < $1.setIndex }
    }

    func lastWeight(forSet index: Int, for exercise: Exercise, excluding session: WorkoutSession? = nil) -> Double? {
        let last = lastSessionLogs(for: exercise, excluding: session)
        return last.first { $0.setIndex == index }?.weight ?? last.last?.weight
    }

    func lastSessionSummary(for exercise: Exercise, excluding session: WorkoutSession? = nil) -> String? {
        let last = lastSessionLogs(for: exercise, excluding: session)
        guard !last.isEmpty else { return nil }
        let series = last.map { "\($0.weight.kgString)×\($0.reps)" }.joined(separator: "  ")
        let date = last[0].date.formatted(.dateTime.day().month(.abbreviated))
        return "\(date) · \(series)"
    }

    /// Se nell'ultima sessione hai completato tutte le serie con le ripetizioni massime,
    /// suggerisce il prossimo peso (+2,5 kg).
    func suggestedNextWeight(for exercise: Exercise, excluding session: WorkoutSession? = nil) -> Double? {
        let last = lastSessionLogs(for: exercise, excluding: session)
        guard !last.isEmpty, last.count >= exercise.sets else { return nil }
        guard last.allSatisfy({ $0.reps >= exercise.targetRepsUpper }) else { return nil }
        let best = last.map(\.weight).max() ?? 0
        guard best > 0 else { return nil }
        return best + 2.5
    }

    // MARK: Grafici

    /// Un punto per ogni allenamento: peso massimo, volume, numero serie.
    static func points(from logs: [SetLog]) -> [ProgressPoint] {
        let grouped = Dictionary(grouping: logs) { $0.session?.persistentModelID }
        return grouped.values.compactMap { group -> ProgressPoint? in
            guard let first = group.first else { return nil }
            let date = first.session?.date ?? first.date
            let maxWeight = group.map(\.weight).max() ?? 0
            let volume = group.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            return ProgressPoint(date: date, maxWeight: maxWeight, volume: volume, sets: group.count)
        }
        .sorted { $0.date < $1.date }
    }

    /// Tutte le serie storiche, più gli esercizi della scheda attiva ancora senza dati.
    func series(including exercises: [Exercise] = []) -> [ExerciseSeries] {
        var result: [String: ExerciseSeries] = [:]

        let strength = logs.filter { !$0.isTimed }
        for (key, group) in Dictionary(grouping: strength, by: { $0.normalizedName }) {
            guard let latest = group.max(by: { $0.date < $1.date }) else { continue }
            result[key] = ExerciseSeries(id: key, name: latest.exerciseName, group: latest.muscleGroup, points: ExerciseHistory.points(from: group))
        }

        for exercise in exercises where !exercise.isTimed {
            let key = exercise.normalizedName
            let points = result[key]?.points ?? []
            result[key] = ExerciseSeries(id: key, name: exercise.name, group: exercise.muscleGroup, points: points)
        }

        return result.values.sorted { lhs, rhs in
            if lhs.group != rhs.group { return lhs.group.sortOrder < rhs.group.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Volume settimanale (kg × ripetizioni) per gruppo muscolare, ultime N settimane.
    func weeklyVolume(for group: MuscleGroup?, weeks: Int = 8) -> [WeekBucket] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        let relevant = logs.filter { !$0.isTimed && (group == nil || $0.muscleGroup == group) }
        return (0..<weeks).reversed().compactMap { offset -> WeekBucket? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            let volume = relevant
                .filter { calendar.isDate($0.date, equalTo: start, toGranularity: .weekOfYear) }
                .reduce(0.0) { $0 + $1.weight * Double($1.reps) }
            return WeekBucket(id: start, value: volume)
        }
    }

    var groupsWithData: [MuscleGroup] {
        MuscleGroup.allCases.filter { group in
            logs.contains { $0.muscleGroup == group && !$0.isTimed }
        }
    }
}
