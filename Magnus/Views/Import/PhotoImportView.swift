import SwiftUI
import PhotosUI

/// Passo 1: scegli o scatta la foto della scheda e lanciane la lettura.
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var parsedPlan: ParsedPlan?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                preview

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Galleria", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Fotocamera", systemImage: "camera.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Button {
                    analyze()
                } label: {
                    if isAnalyzing {
                        ProgressView().tint(.white)
                    } else {
                        Label("Leggi la scheda", systemImage: "text.viewfinder")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(image == nil || isAnalyzing)

                Text("Il testo viene letto direttamente sul telefono. Potrai correggere nomi, serie e recuperi prima di salvare.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
            .screenBackground()
            .navigationTitle("Importa scheda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { _, newValue in
                loadPickerItem(newValue)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { picked in
                    image = picked.resized(maxDimension: 2200)
                }
                .ignoresSafeArea()
            }
            .navigationDestination(item: $parsedPlan) { plan in
                ImportReviewView(plan: plan, image: image) {
                    dismiss()
                }
            }
            .alert("Errore", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.navyLight, lineWidth: 2)
                )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.red)
                Text("Fotografa la tua scheda")
                    .font(.title3.weight(.semibold))
                Text("Inquadra bene la tabella con esercizi, serie × ripetizioni e recuperi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .cardStyle()
        }
    }

    private func loadPickerItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let loaded = UIImage(data: data) {
                image = loaded.resized(maxDimension: 2200)
            } else {
                errorMessage = "Non riesco a leggere questa immagine."
            }
        }
    }

    private func analyze() {
        guard let image else { return }
        isAnalyzing = true
        Task {
            defer { isAnalyzing = false }
            do {
                let rows = try await PlanOCRService.recognizeRows(in: image)
                let days = PlanOCRService.parse(rows: rows)
                parsedPlan = ParsedPlan(days: days, rawRows: rows)
            } catch {
                errorMessage = "Lettura non riuscita: \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    PhotoImportView()
        .preferredColorScheme(.dark)
}
