import SwiftUI
import SwiftData

/// Tab "Storico": tutti gli allenamenti registrati, mese per mese,
/// filtrabili per gruppo muscolare (così restano confrontabili tra schede diverse).
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var filterGroup: MuscleGroup?

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let sessions: [WorkoutSession]
    }

    private var filtered: [WorkoutSession] {
        sessions.filter { session in
            guard session.isFinished else { return false }
            guard let filterGroup else { return true }
            return session.muscleGroups.contains(filterGroup)
        }
    }

    private var groups: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { session -> String in
            let components = calendar.dateComponents([.year, .month], from: session.date)
            return "\(components.year ?? 0)-\(components.month ?? 0)"
        }
        return grouped.values
            .compactMap { items -> MonthGroup? in
                guard let first = items.first else { return nil }
                let title = first.date.formatted(.dateTime.month(.wide).year()).capitalized
                return MonthGroup(id: title, title: title, sessions: items.sorted { $0.date > $1.date })
            }
            .sorted { ($0.sessions.first?.date ?? .distantPast) > ($1.sessions.first?.date ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.red)
                        Text(filterGroup == nil ? "Ancora nessun allenamento" : "Nessun allenamento per \(filterGroup?.label ?? "")")
                            .font(.title3.weight(.semibold))
                        Text("Gli allenamenti terminati compariranno qui.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    List {
                        ForEach(groups) { group in
                            Section(group.title) {
                                ForEach(group.sessions) { session in
                                    NavigationLink {
                                        SessionDetailView(session: session)
                                    } label: {
                                        SessionRow(session: session)
                                    }
                                }
                                .onDelete { offsets in
                                    for index in offsets {
                                        modelContext.delete(group.sessions[index])
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    .themedList()
                }
            }
            .screenBackground()
            .navigationTitle("Storico")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            filterGroup = nil
                        } label: {
                            if filterGroup == nil {
                                Label("Tutti", systemImage: "checkmark")
                            } else {
                                Text("Tutti")
                            }
                        }
                        ForEach(MuscleGroup.allCases) { group in
                            Button {
                                filterGroup = group
                            } label: {
                                if filterGroup == group {
                                    Label(group.label, systemImage: "checkmark")
                                } else {
                                    Label(group.label, systemImage: group.icon)
                                }
                            }
                        }
                    } label: {
                        Label(filterGroup?.label ?? "Filtra", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(session.date.formatted(.dateTime.day()))
                    .font(.title3.weight(.bold))
                Text(session.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 48, height: 48)
            .background(Theme.navyGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(session.dayName)
                    .font(.body.weight(.semibold))
                Text("\(session.completedSets.count) serie · \(session.totalVolume.kgString) kg sollevati")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                let groups = session.muscleGroups
                if !groups.isEmpty {
                    Text(groups.prefix(5).map(\.label).joined(separator: " · "))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.red)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// Dettaglio di un allenamento passato.
struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Data", systemImage: "calendar")
                    Spacer()
                    Text(session.date.formatted(date: .long, time: .shortened))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack {
                    Label("Volume totale", systemImage: "scalemass")
                    Spacer()
                    Text("\(session.totalVolume.kgString) kg")
                        .foregroundStyle(Theme.textSecondary)
                }
                if !session.notes.isEmpty {
                    Text(session.notes)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .listRowBackground(Theme.surface)

            ForEach(session.completedSetsByExercise) { group in
                Section {
                    if group.isTimed {
                        HStack {
                            Label("Durata", systemImage: "timer")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(group.logs.first?.reps ?? 0) min")
                                .font(.body.weight(.semibold))
                        }
                    } else {
                        ForEach(group.logs) { log in
                            HStack {
                                Text("Serie \(log.setIndex)")
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text("\(log.weight.kgString) kg × \(log.reps)")
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text(group.group.label)
                            .foregroundStyle(Theme.red)
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        .navigationTitle(session.dayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
