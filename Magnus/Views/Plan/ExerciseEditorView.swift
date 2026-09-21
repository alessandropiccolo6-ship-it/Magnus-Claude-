import SwiftUI
import SwiftData

/// Crea o modifica un esercizio della scheda.
struct ExerciseEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let existing: Exercise?
    private let day: WorkoutDay?

    @State private var name: String
    @State private var sets: Int
    @State private var reps: String
    @State private var restTime: String
    @State private var notes: String
    @State private var targetWeight: Double?
    @State private var muscleGroup: MuscleGroup
    @State private var groupTouched: Bool
    @State private var isTimed: Bool
    @State private var minutes: Int
    @State private var showDeleteConfirm = false

    /// Modifica un esercizio esistente.
    init(exercise: Exercise) {
        existing = exercise
        day = exercise.day
        _name = State(initialValue: exercise.name)
        _sets = State(initialValue: exercise.sets)
        _reps = State(initialValue: exercise.reps)
        _restTime = State(initialValue: exercise.restTime)
        _notes = State(initialValue: exercise.notes)
        _targetWeight = State(initialValue: exercise.targetWeight)
        _muscleGroup = State(initialValue: exercise.muscleGroup)
        _groupTouched = State(initialValue: true)
        _isTimed = State(initialValue: exercise.isTimed)
        _minutes = State(initialValue: exercise.durationMinutes ?? 10)
    }

    /// Nuovo esercizio in un giorno.
    init(day: WorkoutDay) {
        existing = nil
        self.day = day
        _name = State(initialValue: "")
        _sets = State(initialValue: 3)
        _reps = State(initialValue: "10")
        _restTime = State(initialValue: "")
        _notes = State(initialValue: "")
        _targetWeight = State(initialValue: nil)
        _muscleGroup = State(initialValue: .altro)
        _groupTouched = State(initialValue: false)
        _isTimed = State(initialValue: false)
        _minutes = State(initialValue: 10)
    }

    var body: some View {
        Form {
            Section("Esercizio") {
                TextField("Nome (es. Chest press)", text: $name)
                    .onChange(of: name) { _, newValue in
                        if !groupTouched {
                            muscleGroup = MuscleGroup.classify(newValue)
                        }
                    }
                Picker("Gruppo muscolare", selection: $muscleGroup) {
                    ForEach(MuscleGroup.allCases) { group in
                        Label(group.label, systemImage: group.icon).tag(group)
                    }
                }
                .onChange(of: muscleGroup) { _, _ in
                    groupTouched = true
                }
                Toggle("Esercizio a tempo (cardio, riscaldamento)", isOn: $isTimed)
                    .tint(Theme.red)
            }

            if isTimed {
                Section("Durata") {
                    Stepper(value: $minutes, in: 1...180) {
                        HStack {
                            Text("Minuti")
                            Spacer()
                            Text("\(minutes)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } else {
                Section {
                    Stepper(value: $sets, in: 1...12) {
                        HStack {
                            Text("Serie")
                            Spacer()
                            Text("\(sets)")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack {
                        Text("Ripetizioni")
                        Spacer()
                        TextField("10 oppure 8-12", text: $reps)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                    HStack {
                        Label("Recupero", systemImage: "lock.fill")
                        Spacer()
                        TextField("50''", text: $restTime)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                    }
                } header: {
                    Text("Schema")
                } footer: {
                    Text("Il recupero è quello indicato sulla scheda: durante l'allenamento non si modifica, viene usato per il timer.")
                }

                Section {
                    HStack {
                        Text("Peso obiettivo")
                        Spacer()
                        TextField("kg", value: $targetWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        Text("kg")
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Obiettivo")
                } footer: {
                    Text("Il nuovo peso che vuoi raggiungere. Comparirà nei grafici come linea tratteggiata.")
                }
            }

            Section("Note") {
                TextField("Es. presa larga, fermo al petto", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            if existing != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Elimina esercizio", systemImage: "trash")
                    }
                }
            }
        }
        .themedList()
        .navigationTitle(existing == nil ? "Nuovo esercizio" : "Modifica esercizio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Eliminare l'esercizio dalla scheda?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let existing {
                    modelContext.delete(existing)
                }
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Le serie già registrate restano nello storico.")
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedReps = reps.trimmingCharacters(in: .whitespaces)
        let trimmedRest = restTime.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.name = trimmedName
            existing.sets = sets
            existing.reps = trimmedReps.isEmpty ? "10" : trimmedReps
            existing.restTime = isTimed ? "" : trimmedRest
            existing.notes = notes
            existing.targetWeight = isTimed ? nil : targetWeight
            existing.muscleGroup = muscleGroup
            existing.durationMinutes = isTimed ? minutes : nil
        } else if let day {
            let order = (day.exercises.map(\.order).max() ?? -1) + 1
            let exercise = Exercise(
                name: trimmedName,
                order: order,
                sets: sets,
                reps: trimmedReps.isEmpty ? "10" : trimmedReps,
                restTime: isTimed ? "" : trimmedRest,
                notes: notes,
                targetWeight: isTimed ? nil : targetWeight,
                muscleGroup: muscleGroup,
                durationMinutes: isTimed ? minutes : nil
            )
            modelContext.insert(exercise)
            exercise.day = day
        }
        dismiss()
    }
}
