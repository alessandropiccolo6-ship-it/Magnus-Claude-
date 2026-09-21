import SwiftUI
import SwiftData

/// Tab "Allena": scegli il giorno della scheda e inizia a segnare i pesi.
struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var activeSession: WorkoutSession?

    private var activePlan: WorkoutPlan? {
        plans.first { $0.isActive } ?? plans.first
    }

    private var openSession: WorkoutSession? {
        sessions.first { !$0.isFinished }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let open = openSession {
                        openSessionCard(open)
                    }

                    if let plan = activePlan, !plan.days.isEmpty {
                        HStack {
                            Text("Scegli il giorno")
                                .font(.headline)
                            Spacer()
                            Text(plan.name)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.horizontal, 4)

                        ForEach(plan.sortedDays) { day in
                            DayStartCard(
                                day: day,
                                lastDate: lastFinishedDate(for: day),
                                onStart: { start(day) }
                            )
                        }
                    } else {
                        emptyState
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Allenamento")
            .navigationDestination(item: $activeSession) { session in
                SessionView(session: session)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.red)
            Text("Prima crea la scheda")
                .font(.title3.weight(.semibold))
            Text("Vai nella sezione Scheda e carica la foto della tua scheda oppure creala a mano.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle()
    }

    private func openSessionCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Allenamento in corso", systemImage: "flame.fill")
                    .font(.headline)
                Spacer()
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text(session.dayName)
                .font(.title2.weight(.bold))
            Text("\(session.completedSets.count) serie completate")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Button {
                activeSession = session
            } label: {
                Label("Continua", systemImage: "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(Theme.navyGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }

    private func lastFinishedDate(for day: WorkoutDay) -> Date? {
        sessions.first { $0.isFinished && $0.day?.persistentModelID == day.persistentModelID }?.date
    }

    private func start(_ day: WorkoutDay) {
        if let open = openSession, open.day?.persistentModelID == day.persistentModelID {
            activeSession = open
            return
        }
        let session = WorkoutSession(date: .now, dayName: day.name)
        modelContext.insert(session)
        session.day = day
        activeSession = session
    }
}

struct DayStartCard: View {
    let day: WorkoutDay
    let lastDate: Date?
    var onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.redGradient)
                        .frame(width: 48, height: 48)
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(day.exercises.count) esercizi")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    if let lastDate {
                        Text("Ultima volta: \(lastDate.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Mai allenato")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textSecondary)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}
