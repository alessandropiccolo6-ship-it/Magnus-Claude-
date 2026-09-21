import SwiftUI
import SwiftData

/// Passo 2: controlla e correggi ciò che è stato letto, poi salva la scheda.
struct ImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [WorkoutPlan]

    @State private var planName = "La mia scheda"
    @State private var days: [ParsedDay]
    @State private var showRawText = false

    private let rawRows: [String]
    private let image: UIImage?
    private let onSaved: () -> Void

    init(plan: ParsedPlan, image: UIImage?, onSaved: @escaping () -> Void) {
        _days = State(initialValue: plan.days.isEmpty ? [ParsedDay(name: "Giorno A", exercises: [])] : plan.days)
        self.rawRows = plan.rawRows
        self.image = image
        self.onSaved = onSaved
    }

    private var totalExercises: Int {
        days.reduce(0) { $0 + $1.exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count }
    }

    var body: some View {
        List {
            Section {
                TextField("Nome scheda", text: $planName)
            } header: {
                Text("Nome")
            } footer: {
                if totalExercises == 0 {
                    Text("Nessun esercizio riconosciuto: aggiungili a mano oppure riprova con una foto più nitida.")
                        .foregroundStyle(Theme.red)
                } else {
                    Text("Riconosciuti \(totalExercises) esercizi. Il recupero è quello scritto sulla scheda e resterà fisso.")
                }
            }
            .listRowBackground(Theme.surface)

            ForEach($days) { $day in
                Section {
                    ForEach($day.exercises) { $exercise in
                        ParsedExerciseRow(exercise: $exercise)
                    }
                    .onDelete { offsets in
                        $day.exercises.wrappedValue.remove(atOffsets: offsets)
                    }
                    .onMove { offsets, destination in
                        $day.exercises.wrappedValue.move(fromOffsets: offsets, toOffset: destination)
                    }

                    Button {
                        $day.exercises.wrappedValue.append(ParsedExercise(name: "", sets: 3, reps: "10", restTime: ""))
                    } label: {
                        Label("Aggiungi esercizio", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        TextField("Nome giorno", text: $day.name)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .textCase(nil)
                        Spacer()
                        if days.count > 1 {
                            Button(role: .destructive) {
                                days.removeAll { $0.id == day.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button {
                    let letter = Character(UnicodeScalar(65 + min(days.count, 25))!)
                    days.append(ParsedDay(name: "Giorno \(letter)", exercises: []))
                } label: {
                    Label("Aggiungi giorno", systemImage: "calendar.badge.plus")
                }

                if !rawRows.isEmpty {
                    Button {
                        showRawText.toggle()
                    } label: {
                        Label(showRawText ? "Nascondi testo letto" : "Mostra testo letto", systemImage: "text.alignleft")
                    }
                    if showRawText {
                        ForEach(Array(rawRows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .navigationTitle("Controlla la scheda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { save() }
                    .disabled(totalExercises == 0 || planName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        for plan in plans where plan.isActive {
            plan.isActive = false
        }

        let plan = WorkoutPlan(
            name: planName.trimmingCharacters(in: .whitespaces),
            photoData: image?.jpegData(compressionQuality: 0.8)
        )
        modelContext.insert(plan)

        for (dayIndex, parsedDay) in days.enumerated() {
            let day = WorkoutDay(name: parsedDay.name.isEmpty ? "Giorno \(dayIndex + 1)" : parsedDay.name, order: dayIndex)
            modelContext.insert(day)
            day.plan = plan

            let valid = parsedDay.exercises.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            for (exerciseIndex, parsed) in valid.enumerated() {
                let exercise = Exercise(
                    name: parsed.name.trimmingCharacters(in: .whitespaces),
                    order: exerciseIndex,
                    sets: max(1, parsed.sets),
                    reps: parsed.reps.isEmpty ? "10" : parsed.reps,
                    restTime: parsed.restTime
                )
                modelContext.insert(exercise)
                exercise.day = day
            }
        }

        onSaved()
    }
}

/// Riga modificabile di un esercizio riconosciuto.
struct ParsedExerciseRow: View {
    @Binding var exercise: ParsedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nome esercizio", text: $exercise.name)
                .font(.body.weight(.semibold))

            HStack(spacing: 12) {
                Stepper(value: $exercise.sets, in: 1...12) {
                    Text("\(exercise.sets) serie")
                        .font(.subheadline)
                }
                .fixedSize()

                Spacer()
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("×")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("10", text: $exercise.reps)
                        .frame(width: 60)
                    Text("rip.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                Divider()

                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .foregroundStyle(Theme.textSecondary)
                    TextField("90''", text: $exercise.restTime)
                        .frame(width: 70)
                    Text("recupero")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
