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

    var allExercises: [Exercise] {
        sortedDays.flatMap(\.sortedExercises)
    }
}

/// Un giorno della scheda (es. "Giorno A", "Push", "Lunedì").
/// Gli allenamenti registrati NON vengono eliminati con il giorno: lo storico resta.
@Model
final class WorkoutDay {
    var name: String
    var order: Int
    var plan: WorkoutPlan?
    @Relationship(deleteRule: .cascade, inverse: \Exercise.day) var exercises: [Exercise] = []
    @Relationship(deleteRule: .nullify, inverse: \WorkoutSession.day) var sessions: [WorkoutSession] = []

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
/// Gli esercizi "a tempo" (riscaldamento, corsa, cyclette) hanno `durationMinutes`.
@Model
final class Exercise {
    var name: String
    var order: Int
    var sets: Int
    var reps: String          // "10" oppure "8-12"
    var restTime: String      // es. "50''", "1'30", "2'"
    var notes: String
    var targetWeight: Double? // nuovo peso da raggiungere
    var muscleGroupRaw: String = MuscleGroup.altro.rawValue
    var durationMinutes: Int?
    var day: WorkoutDay?
    /// Le serie registrate restano anche se l'esercizio viene eliminato (storico tra schede).
    @Relationship(deleteRule: .nullify, inverse: \SetLog.exercise) var logs: [SetLog] = []

    init(
        name: String,
        order: Int,
        sets: Int = 3,
        reps: String = "10",
        restTime: String = "",
        notes: String = "",
        targetWeight: Double? = nil,
        muscleGroup: MuscleGroup? = nil,
        durationMinutes: Int? = nil
    ) {
        self.name = name
        self.order = order
        self.sets = sets
        self.reps = reps
        self.restTime = restTime
        self.notes = notes
        self.targetWeight = targetWeight
        self.muscleGroupRaw = (muscleGroup ?? MuscleGroup.classify(name)).rawValue
        self.durationMinutes = durationMinutes
    }

    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .altro }
        set { muscleGroupRaw = newValue.rawValue }
    }

    var isTimed: Bool { durationMinutes != nil }

    /// Chiave per riconoscere lo stesso esercizio in schede diverse.
    var normalizedName: String { name.normalizedKey }

    var scheduleLabel: String {
        if let durationMinutes { return "\(durationMinutes) min" }
        return "\(sets) × \(reps)"
    }

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
}

struct ProgressPoint: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let maxWeight: Double
    let volume: Double
    let sets: Int
}

// MARK: - Allenamenti registrati

/// Un allenamento svolto in un certo giorno. Sopravvive alla cancellazione della scheda.
@Model
final class WorkoutSession {
    var date: Date
    var finishedAt: Date?
    var notes: String
    var dayNameSnapshot: String = ""
    var day: WorkoutDay?
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session) var sets: [SetLog] = []

    init(date: Date = .now, dayName: String = "", notes: String = "") {
        self.date = date
        self.dayNameSnapshot = dayName
        self.notes = notes
    }

    var dayName: String {
        if let day { return day.name }
        return dayNameSnapshot.isEmpty ? "Allenamento" : dayNameSnapshot
    }

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

    /// Gruppi muscolari allenati, in ordine di apparizione.
    var muscleGroups: [MuscleGroup] {
        var seen: [MuscleGroup] = []
        for group in completedSetsByExercise.map(\.group) where !seen.contains(group) {
            seen.append(group)
        }
        return seen
    }

    /// Serie completate raggruppate per esercizio, nell'ordine della scheda.
    var completedSetsByExercise: [ExerciseSetGroup] {
        let grouped = Dictionary(grouping: completedSets) { $0.normalizedName }
        return grouped.values.compactMap { group -> ExerciseSetGroup? in
            guard let first = group.first else { return nil }
            return ExerciseSetGroup(
                id: first.normalizedName,
                name: first.exerciseName,
                group: first.muscleGroup,
                isTimed: first.isTimed,
                order: first.exercise?.order ?? Int.max,
                firstDate: group.map(\.date).min() ?? first.date,
                logs: group.sorted { $0.setIndex < $1.setIndex }
            )
        }
        .sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.firstDate < $1.firstDate
        }
    }
}

struct ExerciseSetGroup: Identifiable {
    let id: String
    let name: String
    let group: MuscleGroup
    let isTimed: Bool
    let order: Int
    let firstDate: Date
    let logs: [SetLog]
}

/// Una singola serie registrata: peso, ripetizioni e se è stata completata.
/// Nome e gruppo muscolare sono copiati dall'esercizio, così lo storico resta
/// leggibile anche quando la scheda cambia o viene eliminata.
@Model
final class SetLog {
    var setIndex: Int
    var weight: Double
    var reps: Int              // per gli esercizi a tempo: minuti
    var completed: Bool
    var date: Date
    var exerciseName: String = ""
    var muscleGroupRaw: String = MuscleGroup.altro.rawValue
    var isTimed: Bool = false
    var exercise: Exercise?
    var session: WorkoutSession?

    init(snapshotOf exercise: Exercise, setIndex: Int, weight: Double, reps: Int, completed: Bool = false, date: Date = .now) {
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.completed = completed
        self.date = date
        self.exerciseName = exercise.name
        self.muscleGroupRaw = exercise.muscleGroupRaw
        self.isTimed = exercise.isTimed
    }

    var normalizedName: String { exerciseName.normalizedKey }

    var muscleGroup: MuscleGroup {
        MuscleGroup(rawValue: muscleGroupRaw) ?? .altro
    }
}

// MARK: - Formattazione

extension Double {
    /// "60" oppure "62,5" (segue la lingua del telefono).
    var kgString: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}

extension String {
    /// Chiave normalizzata: minuscolo, senza accenti e punteggiatura, spazi singoli.
    var normalizedKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
