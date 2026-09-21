import SwiftUI
import SwiftData
import UIKit

struct RestTimerRequest: Identifiable {
    let id = UUID()
    let seconds: Int
    let exerciseName: String
}

/// Schermata di allenamento: per ogni esercizio segni peso e ripetizioni serie per serie.
struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession

    @State private var restTimer: RestTimerRequest?
    @State private var showFinishConfirm = false
    @State private var showCancelConfirm = false

    private var exercises: [Exercise] {
        session.day?.sortedExercises ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(exercises) { exercise in
                    ExerciseLogCard(exercise: exercise, session: session) { seconds in
                        restTimer = RestTimerRequest(seconds: seconds, exerciseName: exercise.name)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .font(.headline)
                    TextField("Come è andata?", text: $session.notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(10)
                        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .cardStyle()

                Button {
                    showFinishConfirm = true
                } label: {
                    Label("Termina allenamento", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle(session.dayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showCancelConfirm = true
                    } label: {
                        Label("Annulla allenamento", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear(perform: ensureLogs)
        .sheet(item: $restTimer) { request in
            RestTimerView(request: request)
                .presentationDetents([.medium])
                .presentationBackground(Theme.background)
        }
        .confirmationDialog("Terminare l'allenamento?", isPresented: $showFinishConfirm, titleVisibility: .visible) {
            Button("Termina e salva") { finish() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("\(session.completedSets.count) serie completate · volume \(session.totalVolume.kgString) kg")
        }
        .confirmationDialog("Annullare l'allenamento?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("Annulla allenamento", role: .destructive) {
                modelContext.delete(session)
                dismiss()
            }
            Button("Continua", role: .cancel) {}
        } message: {
            Text("Le serie di oggi non verranno salvate.")
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Crea in anticipo una riga per ogni serie prevista, precompilata con i pesi dell'ultima volta.
    private func ensureLogs() {
        for exercise in exercises {
            let existing = session.logs(for: exercise)
            let count = max(exercise.sets, 1)
            for index in 1...count where !existing.contains(where: { $0.setIndex == index }) {
                let weight = exercise.lastWeight(forSet: index, excluding: session) ?? 0
                let log = SetLog(setIndex: index, weight: weight, reps: exercise.defaultReps, completed: false, date: session.date)
                modelContext.insert(log)
                log.exercise = exercise
                log.session = session
            }
        }
    }

    private func finish() {
        let completed = session.completedSets
        if completed.isEmpty {
            modelContext.delete(session)
        } else {
            for log in session.sets where !log.completed {
                modelContext.delete(log)
            }
            session.finishedAt = .now
        }
        dismiss()
    }
}

/// Scheda di un esercizio durante l'allenamento.
struct ExerciseLogCard: View {
    @Environment(\.modelContext) private var modelContext
    let exercise: Exercise
    let session: WorkoutSession
    var onStartRest: (Int) -> Void

    @State private var showTargetAlert = false
    @State private var targetText = ""

    private var logs: [SetLog] { session.logs(for: exercise) }
    private var previousRecord: Double? { exercise.personalRecord(excluding: session) }

    private var isNewRecord: Bool {
        let completed = logs.filter(\.completed)
        guard let best = completed.map(\.weight).max(), best > 0 else { return false }
        if let previousRecord { return best > previousRecord }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let summary = exercise.lastSessionSummary(excluding: session) {
                Label(summary, systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            if let suggestion = exercise.suggestedNextWeight(excluding: session) {
                Label("Pronto ad aumentare: prova \(suggestion.kgString) kg", systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.red)
            }

            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text("Serie").frame(width: 36, alignment: .leading)
                Text("Kg").frame(maxWidth: .infinity)
                Text("Rip.").frame(width: 60)
                Text("Fatta").frame(width: 44)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)

            ForEach(logs) { log in
                SetRow(log: log) {
                    if let seconds = exercise.restSeconds, seconds > 0 {
                        onStartRest(seconds)
                    }
                }
            }
        }
        .cardStyle()
        .alert("Peso obiettivo", isPresented: $showTargetAlert) {
            TextField("kg", text: $targetText)
                .keyboardType(.decimalPad)
            Button("Salva") {
                let normalized = targetText.replacingOccurrences(of: ",", with: ".")
                exercise.targetWeight = Double(normalized)
            }
            Button("Rimuovi", role: .destructive) {
                exercise.targetWeight = nil
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il nuovo peso che vuoi raggiungere per \(exercise.name).")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Chip(text: exercise.setsRepsLabel, style: .navy)

                    if let seconds = exercise.restSeconds, seconds > 0 {
                        Button {
                            onStartRest(seconds)
                        } label: {
                            Chip(text: exercise.restTime, systemImage: "timer", style: .neutral)
                        }
                        .buttonStyle(.plain)
                    } else if !exercise.restTime.isEmpty {
                        Chip(text: exercise.restTime, systemImage: "lock.fill", style: .neutral)
                    }

                    Button {
                        targetText = exercise.targetWeight.map { $0.kgString } ?? ""
                        showTargetAlert = true
                    } label: {
                        if let target = exercise.targetWeight {
                            Chip(text: "→ \(target.kgString) kg", systemImage: "target", style: .red)
                        } else {
                            Chip(text: "Obiettivo", systemImage: "target", style: .neutral)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            if isNewRecord {
                VStack(spacing: 2) {
                    Image(systemName: "trophy.fill")
                    Text("NUOVO\nRECORD")
                        .font(.system(size: 9, weight: .heavy))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Theme.red)
            } else if let previousRecord {
                VStack(spacing: 2) {
                    Text("max")
                        .font(.system(size: 9))
                    Text("\(previousRecord.kgString) kg")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Riga di una singola serie: peso, ripetizioni, spunta "fatta".
struct SetRow: View {
    @Bindable var log: SetLog
    var onCompleted: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(log.setIndex)")
                .font(.body.weight(.bold))
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(log.completed ? Theme.success : Theme.textPrimary)

            HStack(spacing: 4) {
                stepButton("minus") {
                    log.weight = max(0, log.weight - 2.5)
                }
                TextField("kg", value: $log.weight, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 6)
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                stepButton("plus") {
                    log.weight += 2.5
                }
            }
            .frame(maxWidth: .infinity)

            TextField("rip", value: $log.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(.vertical, 6)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(width: 60)

            Button {
                withAnimation(.snappy) {
                    log.completed.toggle()
                }
                if log.completed {
                    log.date = .now
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onCompleted()
                }
            } label: {
                Image(systemName: log.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(log.completed ? Theme.success : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44)
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(Theme.navy, in: Circle())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
