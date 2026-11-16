import SwiftUI
import ReplayKit

struct ContentView: View {
    @State private var notificationsEnabled = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
                Text("Radar Uber Inteligente")
                    .font(.largeTitle.bold())
                Text("Leitura local de ofertas por transmissão de tela autorizada.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                BroadcastPicker()
                    .frame(height: 52)

                Text("Toque em Iniciar transmissão e escolha Radar Leitura. Depois volte para a Uber. O iPhone mostrará o indicador de gravação/transmissão enquanto a leitura estiver ativa.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label("As imagens são processadas no aparelho. O Radar não envia a tela para um servidor.", systemImage: "lock.shield")
                    .font(.footnote)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                Spacer()
            }
            .padding()
            .navigationTitle("Radar")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refreshNotificationStatus() }
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: .zero)
        picker.preferredExtension = "br.com.radaruber.app.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
