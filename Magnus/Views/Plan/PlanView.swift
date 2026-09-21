import SwiftUI
import SwiftData

/// Tab "Scheda": la scheda attiva, con giorni ed esercizi.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]
    @Query(filter: #Predicate<SetLog> { $0.completed }) private var completedLogs: [SetLog]

    @State private var showImport = false
    @State private var showPlanList = false
    @State private var showPhoto = false
    @State private var showNewDayAlert = false
    @State private var newDayName = ""
    @State private var showRenameAlert = false
    @State private var dayToRename: WorkoutDay?
    @State private var renameText = ""
    @State private var showDeletePlanConfirm = false

    private var activePlan: WorkoutPlan? {
        plans.first { $0.isActive } ?? plans.first
    }

    private var history: ExerciseHistory {
        ExerciseHistory(logs: completedLogs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let plan = activePlan {
                    planContent(plan)
                } else {
                    emptyState
                }
            }
            .screenBackground()
            .navigationTitle(activePlan?.name ?? "Scheda")
            .toolbar {
                if activePlan != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showImport = true
                        } label: {
                            Label("Nuova scheda da foto", systemImage: "camera.viewfinder")
                        }
                        Button {
                            createManualPlan()
                        } label: {
                            Label("Nuova scheda manuale", systemImage: "square.and.pencil")
                        }
                        if plans.count > 1 {
                            Button {
                                showPlanList = true
                            } label: {
                                Label("Le mie schede", systemImage: "list.bullet.rectangle")
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showImport) {
                PhotoImportView()
            }
            .sheet(isPresented: $showPlanList) {
                PlanListView()
            }
        }
    }

    // MARK: Stato vuoto

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 72))
                .foregroundStyle(Theme.red)
            Text("Nessuna scheda")
                .font(.title.weight(.bold))
            Text("Fotografa la scheda che ti ha dato il tuo istruttore: Magnus legge esercizi, serie e recuperi e ti prepara tutto per segnare i pesi.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showImport = true
            } label: {
                Label("Carica foto della scheda", systemImage: "camera.viewfinder")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                createManualPlan()
            } label: {
                Label("Crea a mano", systemImage: "square.and.pencil")
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
        }
        .padding()
    }

    // MARK: Contenuto scheda

    private func planContent(_ plan: WorkoutPlan) -> some View {
        List {
            Section {
                PlanHeaderCard(plan: plan) {
                    showPhoto = true
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            ForEach(plan.sortedDays) { day in
                Section {
                    ForEach(day.sortedExercises) { exercise in
                        NavigationLink {
                            ExerciseEditorView(exercise: exercise)
                        } label: {
                            ExerciseRow(exercise: exercise, history: history)
                        }
                    }
                    .onDelete { offsets in
                        deleteExercises(at: offsets, in: day)
                    }
                    .onMove { offsets, destination in
                        moveExercises(from: offsets, to: destination, in: day)
                    }

                    NavigationLink {
                        ExerciseEditorView(day: day)
                    } label: {
                        Label("Aggiungi esercizio", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.red)
                    }
                } header: {
                    HStack {
                        Text(day.name)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .textCase(nil)
                        Spacer()
                        Menu {
                            Button {
                                dayToRename = day
                                renameText = day.name
                                showRenameAlert = true
                            } label: {
                                Label("Rinomina", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                modelContext.delete(day)
                            } label: {
                                Label("Elimina giorno", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button {
                    newDayName = ""
                    showNewDayAlert = true
                } label: {
                    Label("Aggiungi giorno", systemImage: "calendar.badge.plus")
                }
                Button(role: .destructive) {
                    showDeletePlanConfirm = true
                } label: {
                    Label("Elimina scheda", systemImage: "trash")
                }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .fullScreenCover(isPresented: $showPhoto) {
            PlanPhotoViewer(data: plan.photoData)
        }
        .alert("Nuovo giorno", isPresented: $showNewDayAlert) {
            TextField("Es. Giorno B", text: $newDayName)
            Button("Aggiungi") { addDay(to: plan) }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Rinomina giorno", isPresented: $showRenameAlert, presenting: dayToRename) { day in
            TextField("Nome", text: $renameText)
            Button("Salva") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { day.name = trimmed }
            }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Eliminare la scheda?", isPresented: $showDeletePlanConfirm, titleVisibility: .visible) {
            Button("Elimina scheda", role: .destructive) {
                deletePlan(plan)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Gli allenamenti già registrati restano nello storico e nei grafici.")
        }
    }

    // MARK: Azioni

    private func createManualPlan() {
        for plan in plans where plan.isActive {
            plan.isActive = false
        }
        let plan = WorkoutPlan(name: "Nuova scheda")
        modelContext.insert(plan)
        let day = WorkoutDay(name: "Giorno A", order: 0)
        modelContext.insert(day)
        day.plan = plan
    }

    private func addDay(to plan: WorkoutPlan) {
        let trimmed = newDayName.trimmingCharacters(in: .whitespaces)
        let fallback = "Giorno \(Character(UnicodeScalar(65 + min(plan.days.count, 25))!))"
        let day = WorkoutDay(name: trimmed.isEmpty ? fallback : trimmed, order: (plan.days.map(\.order).max() ?? -1) + 1)
        modelContext.insert(day)
        day.plan = plan
    }

    private func deleteExercises(at offsets: IndexSet, in day: WorkoutDay) {
        let sorted = day.sortedExercises
        for index in offsets {
            modelContext.delete(sorted[index])
        }
        for (index, exercise) in day.sortedExercises.enumerated() {
            exercise.order = index
        }
    }

    private func moveExercises(from offsets: IndexSet, to destination: Int, in day: WorkoutDay) {
        var items = day.sortedExercises
        items.move(fromOffsets: offsets, toOffset: destination)
        for (index, exercise) in items.enumerated() {
            exercise.order = index
        }
    }

    private func deletePlan(_ plan: WorkoutPlan) {
        modelContext.delete(plan)
        if let next = plans.first(where: { $0.persistentModelID != plan.persistentModelID }) {
            next.isActive = true
        }
    }
}

// MARK: - Componenti

struct PlanHeaderCard: View {
    let plan: WorkoutPlan
    var onTapPhoto: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let data = plan.photoData, let image = UIImage(data: data) {
                Button(action: onTapPhoto) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "doc.text")
                    .font(.title)
                    .frame(width: 72, height: 72)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(plan.name)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Text("\(plan.days.count) giorni · \(plan.exerciseCount) esercizi")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                Text("Creata il \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                if plan.photoData != nil {
                    Text("Tocca la foto per ingrandirla")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.navyGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.white)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    let history: ExerciseHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name)
                .font(.body.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Chip(text: exercise.scheduleLabel, style: .navy)
                    Chip(text: exercise.muscleGroup.label, systemImage: exercise.muscleGroup.icon, style: .neutral)
                    if !exercise.isTimed && !exercise.restTime.isEmpty {
                        Chip(text: exercise.restTime, systemImage: "lock.fill", style: .neutral)
                    }
                    if let target = exercise.targetWeight {
                        Chip(text: "→ \(target.kgString) kg", systemImage: "target", style: .red)
                    }
                    if let pr = history.personalRecord(for: exercise) {
                        Chip(text: "max \(pr.kgString) kg", systemImage: "trophy.fill", style: .success)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Foto della scheda a schermo intero, con zoom.
struct PlanPhotoViewer: View {
    let data: Data?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let data, let image = UIImage(data: data) {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width * scale)
                            .frame(minHeight: proxy.size.height)
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(5, max(1, lastScale * value))
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
            } else {
                Text("Nessuna foto")
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white, Theme.red)
                    .padding()
            }
        }
    }
}

/// Elenco di tutte le schede salvate: scegli quella attiva.
struct PlanListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutPlan.createdAt, order: .reverse) private var plans: [WorkoutPlan]

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans) { plan in
                    Button {
                        for other in plans { other.isActive = false }
                        plan.isActive = true
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(plan.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(plan.days.count) giorni · \(plan.exerciseCount) esercizi · \(plan.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if plan.isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.red)
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                .onDelete { offsets in
                    for index in offsets {
                        modelContext.delete(plans[index])
                    }
                }
            }
            .themedList()
            .navigationTitle("Le mie schede")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}
