import SwiftUI
import ReplayKit
import UserNotifications
import UIKit

struct ContentView: View {
    @AppStorage("fuelCostPerKm", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var fuelCostPerKm = 0.28
    @AppStorage("targetNetPerHour", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var targetNetPerHour = 0.0
    @State private var notificationStatus = "Verificando autorização…"

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 46))
                    .foregroundStyle(.green)
                Text("Radar Uber Inteligente")
                    .font(.largeTitle.bold())
                Text("Leitura local das ofertas durante transmissão de tela autorizada.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Configuração inicial")
                        .font(.headline)
                    HStack {
                        Text("Custo de combustível por km")
                        Spacer()
                        TextField("0,28", value: $fuelCostPerKm, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("Meta líquida por hora (R$)")
                        Spacer()
                        TextField("Defina sua meta", value: $targetNetPerHour, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 125)
                    }
                    Text("A meta é configurada uma vez. Sem ela, o Radar não libera recomendações de PEGAR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                BroadcastPicker()
                    .frame(height: 52)

                Text("Inicie a transmissão, selecione Radar Leitura e volte para a Uber. O iPhone mantém o indicador de transmissão visível.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label(notificationStatus, systemImage: "bell")
                    .font(.footnote)

                Label("O processamento OCR é local. A tela não é enviada para um servidor.", systemImage: "lock.shield")
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
        notificationStatus = settings.authorizationStatus == .authorized
            ? "Notificações autorizadas"
            : "Notificações ainda não autorizadas"
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
