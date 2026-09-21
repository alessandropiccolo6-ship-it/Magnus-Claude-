import SwiftUI
import SwiftData
import Charts

/// Tab "Progressi": statistiche, calendario, gruppi muscolari e grafici per esercizio.
/// I dati sono uniti tra tutte le schede: per nome esercizio e per gruppo muscolare.
struct ProgressDashboardView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]
    @Query(filter: #Predicate<SetLog> { $0.completed }) private var completedLogs: [SetLog]

    @State private var selectedSeriesID: String?
    @State private var selectedGroup: MuscleGroup?
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

    private var history: ExerciseHistory {
        ExerciseHistory(logs: completedLogs)
    }

    private var allSeries: [ExerciseSeries] {
        history.series(including: activePlan?.allExercises ?? [])
    }

    private var selectedSeries: ExerciseSeries? {
        if let selectedSeriesID, let match = allSeries.first(where: { $0.id == selectedSeriesID }) {
            return match
        }
        return allSeries.first { !$0.points.isEmpty } ?? allSeries.first
    }

    /// Obiettivo dell'esercizio nella scheda attiva con lo stesso nome.
    private func target(for series: ExerciseSeries) -> Double? {
        activePlan?.allExercises.first { $0.normalizedName == series.id }?.targetWeight
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    StatsGrid(sessions: finished)
                    CalendarHeatmap(sessions: finished)
                    WeeklyWorkoutsChart(sessions: finished)
                    MuscleGroupCard(
                        history: history,
                        series: allSeries,
                        selectedGroup: $selectedGroup,
                        onSelectSeries: { selectedSeriesID = $0.id }
                    )
                    exerciseChartCard
                    TargetsCard(exercises: activePlan?.allExercises ?? [], history: history)
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

            if allSeries.isEmpty {
                Text("Crea una scheda e registra un allenamento per vedere i grafici.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Menu {
                    ForEach(MuscleGroup.allCases) { group in
                        let items = allSeries.filter { $0.group == group }
                        if !items.isEmpty {
                            Section(group.label) {
                                ForEach(items) { series in
                                    Button {
                                        selectedSeriesID = series.id
                                    } label: {
                                        if series.id == selectedSeries?.id {
                                            Label(series.name, systemImage: "checkmark")
                                        } else {
                                            Text(series.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedSeries?.name ?? "Scegli esercizio")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if let selectedSeries {
                                Text("\(selectedSeries.group.label) · \(selectedSeries.sessionsCount) allenamenti")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(12)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let series = selectedSeries {
                    ExerciseProgressChart(series: series, target: target(for: series), metric: metric)
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

    private var buckets: [WeekBucket] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<8).reversed().compactMap { offset -> WeekBucket? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            let count = sessions.filter { calendar.isDate($0.date, equalTo: start, toGranularity: .weekOfYear) }.count
            return WeekBucket(id: start, value: Double(count))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allenamenti a settimana")
                .font(.headline)

            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Settimana", bucket.id, unit: .weekOfYear),
                    y: .value("Allenamenti", bucket.value)
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

// MARK: - Gruppi muscolari

/// Confronto per gruppo muscolare: funziona anche quando la scheda cambia,
/// perché ogni serie registrata ricorda il proprio gruppo.
struct MuscleGroupCard: View {
    let history: ExerciseHistory
    let series: [ExerciseSeries]
    @Binding var selectedGroup: MuscleGroup?
    var onSelectSeries: (ExerciseSeries) -> Void

    private var groups: [MuscleGroup] {
        let withData = history.groupsWithData
        let fromPlan = MuscleGroup.allCases.filter { group in series.contains { $0.group == group } }
        return MuscleGroup.allCases.filter { withData.contains($0) || fromPlan.contains($0) }
    }

    private var effectiveGroup: MuscleGroup? {
        if let selectedGroup, groups.contains(selectedGroup) { return selectedGroup }
        return groups.first
    }

    private var groupSeries: [ExerciseSeries] {
        guard let effectiveGroup else { return [] }
        return series
            .filter { $0.group == effectiveGroup }
            .sorted { ($0.points.last?.date ?? .distantPast) > ($1.points.last?.date ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gruppi muscolari")
                .font(.headline)

            if groups.isEmpty {
                Text("Registra un allenamento per vedere il confronto per gruppo muscolare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups) { group in
                            Button {
                                selectedGroup = group
                            } label: {
                                Chip(
                                    text: group.label,
                                    systemImage: group.icon,
                                    style: group == effectiveGroup ? .red : .neutral
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let effectiveGroup {
                    let buckets = history.weeklyVolume(for: effectiveGroup)
                    if buckets.contains(where: { $0.value > 0 }) {
                        Text("Volume settimanale (kg × ripetizioni)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Chart(buckets) { bucket in
                            BarMark(
                                x: .value("Settimana", bucket.id, unit: .weekOfYear),
                                y: .value("Volume", bucket.value)
                            )
                            .foregroundStyle(Theme.redGradient)
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
                        .frame(height: 120)
                    }

                    ForEach(groupSeries) { item in
                        Button {
                            onSelectSeries(item)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(item.points.isEmpty ? "Nessun dato" : "\(item.sessionsCount) allenamenti")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if let last = item.last {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(last.kgString) kg")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.textPrimary)
                                        if let best = item.best, let first = item.first {
                                            let delta = last - first
                                            Text("max \(best.kgString) · \(delta >= 0 ? "+" : "")\(delta.kgString)")
                                                .font(.caption2)
                                                .foregroundStyle(delta >= 0 ? Theme.success : Theme.red)
                                        }
                                    }
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(10)
                            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Grafico per esercizio

struct ExerciseProgressChart: View {
    let series: ExerciseSeries
    let target: Double?
    let metric: ProgressDashboardView.ChartMetric

    private var points: [ProgressPoint] { series.points }

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

                    if metric == .maxWeight, let target {
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
    let history: ExerciseHistory

    private var withTarget: [Exercise] {
        exercises.filter { $0.targetWeight != nil && !$0.isTimed }
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
                    let best = history.personalRecord(for: exercise) ?? 0
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
