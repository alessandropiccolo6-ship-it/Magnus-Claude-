import SwiftUI
import SwiftData
import Charts

/// Tab "Progressi": statistiche, calendario e grafici per esercizio.
struct ProgressDashboardView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    @State private var selectedExerciseID: PersistentIdentifier?
    @State private var metric: ChartMetric = .maxWeight

    enum ChartMetric: String, CaseIterable, Identifiable {
        case maxWeight = "Peso max"
        case volume = "Volume"
        var id: String { rawValue }
    }

    private var finished: [WorkoutSession] {
        sessions.filter { $0.isFinished && !$0.completedSets.isEmpty }
    }

    private var activePlan: WorkoutPlan? {
        plans.first { $0.isActive } ?? plans.first
    }

    private var planExercises: [Exercise] {
        activePlan?.sortedDays.flatMap(\.sortedExercises) ?? []
    }

    private var selectedExercise: Exercise? {
        if let selectedExerciseID, let match = planExercises.first(where: { $0.persistentModelID == selectedExerciseID }) {
            return match
        }
        return planExercises.first { !$0.completedLogs().isEmpty } ?? planExercises.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatsGrid(sessions: finished)
                    CalendarHeatmap(sessions: finished)
                    WeeklyWorkoutsChart(sessions: finished)
                    exerciseChartCard
                    TargetsCard(exercises: planExercises)
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Progressi")
        }
    }

    // MARK: Grafico esercizio

    private var exerciseChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Andamento esercizio")
                    .font(.headline)
                Spacer()
                Picker("Metrica", selection: $metric) {
                    ForEach(ChartMetric.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }

            if planExercises.isEmpty {
                Text("Crea una scheda per vedere i grafici.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Menu {
                    ForEach(activePlan?.sortedDays ?? []) { day in
                        Section(day.name) {
                            ForEach(day.sortedExercises) { exercise in
                                Button {
                                    selectedExerciseID = exercise.persistentModelID
                                } label: {
                                    if exercise.persistentModelID == selectedExercise?.persistentModelID {
                                        Label(exercise.name, systemImage: "checkmark")
                                    } else {
                                        Text(exercise.name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedExercise?.name ?? "Scegli esercizio")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let exercise = selectedExercise {
                    ExerciseProgressChart(exercise: exercise, metric: metric)
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Statistiche

struct StatsGrid: View {
    let sessions: [WorkoutSession]

    private var thisWeekCount: Int {
        let calendar = Calendar.current
        return sessions.filter { calendar.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }.count
    }

    private var last30DaysSets: Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        return sessions.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.completedSets.count }
    }

    /// Settimane consecutive con almeno un allenamento (la settimana corrente conta solo se ti sei già allenato).
    private var weekStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var reference = Date.now
        let hasWorkout: (Date) -> Bool = { date in
            sessions.contains { calendar.isDate($0.date, equalTo: date, toGranularity: .weekOfYear) }
        }
        if !hasWorkout(reference) {
            reference = calendar.date(byAdding: .weekOfYear, value: -1, to: reference) ?? reference
        }
        while hasWorkout(reference) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: reference) else { break }
            reference = previous
        }
        return streak
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Allenamenti", value: "\(sessions.count)", icon: "dumbbell.fill", color: Theme.red)
            StatTile(title: "Questa settimana", value: "\(thisWeekCount)", icon: "calendar", color: Theme.navyLight)
            StatTile(title: "Serie (30 gg)", value: "\(last30DaysSets)", icon: "list.number", color: Theme.navyLight)
            StatTile(title: "Settimane di fila", value: "\(weekStreak)", icon: "flame.fill", color: Theme.red)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

// MARK: - Calendario

struct CalendarHeatmap: View {
    let sessions: [WorkoutSession]
    private let weeks = 16

    private struct DayCell: Identifiable {
        let id: Date
        let sets: Int
        let isFuture: Bool
    }

    private var columns: [[DayCell]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeekStart) else {
            return []
        }

        var setsByDay: [Date: Int] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.date)
            setsByDay[day, default: 0] += session.completedSets.count
        }

        return (0..<weeks).map { weekOffset in
            (0..<7).compactMap { dayOffset in
                guard let date = calendar.date(byAdding: .day, value: weekOffset * 7 + dayOffset, to: start) else { return nil }
                return DayCell(id: date, sets: setsByDay[date] ?? 0, isFuture: date > today)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Giorni di allenamento")
                    .font(.headline)
                Spacer()
                Text("ultime \(weeks) settimane")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    VStack(spacing: 4) {
                        ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 14, height: 14)
                        }
                    }
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: 4) {
                            ForEach(week) { cell in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color(for: cell))
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)

            HStack(spacing: 6) {
                Text("Meno")
                ForEach([0, 4, 10, 20], id: \.self) { sets in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(for: DayCell(id: .now, sets: sets, isFuture: false)))
                        .frame(width: 12, height: 12)
                }
                Text("Più")
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
        }
        .cardStyle()
    }

    private func color(for cell: DayCell) -> Color {
        if cell.isFuture { return Color.clear }
        switch cell.sets {
        case 0: return Theme.surfaceElevated
        case 1...5: return Theme.red.opacity(0.4)
        case 6...12: return Theme.red.opacity(0.7)
        default: return Theme.red
        }
    }
}

// MARK: - Allenamenti per settimana

struct WeeklyWorkoutsChart: View {
    let sessions: [WorkoutSession]

    private struct WeekBucket: Identifiable {
        let id: Date
        let count: Int
    }

    private var buckets: [WeekBucket] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<8).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            let count = sessions.filter { calendar.isDate($0.date, equalTo: start, toGranularity: .weekOfYear) }.count
            return WeekBucket(id: start, count: count)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allenamenti a settimana")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Settimana", bucket.id, unit: .weekOfYear),
                    y: .value("Allenamenti", bucket.count)
                )
                .foregroundStyle(Theme.navyGradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated), centered: true)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 140)
        }
        .cardStyle()
    }
}

// MARK: - Grafico per esercizio

struct ExerciseProgressChart: View {
    let exercise: Exercise
    let metric: ProgressDashboardView.ChartMetric

    private var points: [ProgressPoint] { exercise.progressPoints }

    private func value(_ point: ProgressPoint) -> Double {
        metric == .maxWeight ? point.maxWeight : point.volume
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if points.isEmpty {
                Text("Nessun allenamento registrato per questo esercizio.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 30)
            } else {
                summary

                Chart {
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Data", point.date),
                            y: .value(metric.rawValue, value(point))
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.red.opacity(0.35), Theme.red.opacity(0)], startPoint: .top, endPoint: .bottom)
                        )

                        LineMark(
                            x: .value("Data", point.date),
                            y: .value(metric.rawValue, value(point))
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .foregroundStyle(Theme.red)

                        PointMark(
                            x: .value("Data", point.date),
                            y: .value(metric.rawValue, value(point))
                        )
                        .symbolSize(60)
                        .foregroundStyle(Theme.red)
                    }

                    if metric == .maxWeight, let target = exercise.targetWeight {
                        RuleMark(y: .value("Obiettivo", target))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .foregroundStyle(Theme.navyLight)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Obiettivo \(target.kgString) kg")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                        AxisValueLabel().foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(height: 220)
            }
        }
    }

    private var summary: some View {
        let first = points.first.map(value) ?? 0
        let last = points.last.map(value) ?? 0
        let best = points.map(value).max() ?? 0
        let delta = last - first
        let unit = metric == .maxWeight ? "kg" : "kg tot."

        return HStack(spacing: 12) {
            SummaryValue(title: "Inizio", value: "\(first.kgString) \(unit)")
            SummaryValue(title: "Ultimo", value: "\(last.kgString) \(unit)")
            SummaryValue(title: "Migliore", value: "\(best.kgString) \(unit)", color: Theme.success)
            SummaryValue(
                title: "Variazione",
                value: (delta >= 0 ? "+" : "") + delta.kgString,
                color: delta >= 0 ? Theme.success : Theme.red
            )
        }
    }
}

struct SummaryValue: View {
    let title: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Obiettivi

struct TargetsCard: View {
    let exercises: [Exercise]

    private var withTarget: [Exercise] {
        exercises.filter { $0.targetWeight != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pesi da raggiungere")
                .font(.headline)

            if withTarget.isEmpty {
                Text("Imposta un peso obiettivo su un esercizio (dalla scheda o durante l'allenamento) per seguirlo qui.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(withTarget) { exercise in
                    let target = exercise.targetWeight ?? 0
                    let best = exercise.personalRecord() ?? 0
                    let ratio = target > 0 ? min(1, best / target) : 0

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(best.kgString) / \(target.kgString) kg")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ratio >= 1 ? Theme.success : Theme.textSecondary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.surfaceElevated)
                                Capsule()
                                    .fill(ratio >= 1 ? Theme.success : Theme.red)
                                    .frame(width: proxy.size.width * ratio)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
        .cardStyle()
    }
}
