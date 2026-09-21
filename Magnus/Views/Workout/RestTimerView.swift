import SwiftUI
import UIKit

/// Timer di recupero con il tempo fisso indicato sulla scheda.
struct RestTimerView: View {
    let request: RestTimerRequest
    @Environment(\.dismiss) private var dismiss

    @State private var remaining: Int
    @State private var endDate: Date
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    init(request: RestTimerRequest) {
        self.request = request
        _remaining = State(initialValue: request.seconds)
        _endDate = State(initialValue: Date().addingTimeInterval(TimeInterval(request.seconds)))
    }

    private var progress: Double {
        guard request.seconds > 0 else { return 1 }
        return 1 - Double(remaining) / Double(request.seconds)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Recupero")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text(request.exerciseName)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            ZStack {
                Circle()
                    .stroke(Theme.navy, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.red, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
                Text(RestTimeParser.format(seconds: remaining))
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 180, height: 180)

            Text("Tempo fisso da scheda: \(RestTimeParser.format(seconds: request.seconds))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            Button {
                dismiss()
            } label: {
                Text("Salta")
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .padding()
        .screenBackground()
        .onReceive(timer) { _ in
            let left = Int(endDate.timeIntervalSinceNow.rounded(.up))
            remaining = max(0, left)
            if remaining == 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}
