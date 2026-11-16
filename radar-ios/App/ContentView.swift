import SwiftUI
import ReplayKit
import UserNotifications
import UIKit

struct ContentView: View {
    @AppStorage("fuelCostPerKm", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var fuelCostPerKm = 0.28
    @AppStorage("targetNetPerHour", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var targetNetPerHour = 0.0
    @AppStorage("lastProcessingSeconds", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var lastProcessingSeconds = 0.0
    @AppStorage("lastNotificationStatus", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var lastNotificationStatus = "Nenhuma notificação agendada"
    @AppStorage("observedOfferCount", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var observedOfferCount = 0
    @AppStorage("adaptiveTarget", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var adaptiveTarget = 0.0
    @AppStorage("lastReadStatus", store: UserDefaults(suiteName: "group.br.com.radaruber.app"))
    private var lastReadStatus = "Nenhuma leitura realizada"
    @State private var notificationStatus = "Verificando autorização…"

    var body: some View {
        NavigationStack {
            ScrollView {
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

                Text(lastProcessingSeconds > 0 ? String(format: "Último processamento: %.2f s (OCR + decisão)", lastProcessingSeconds) : "Aguardando oferta legível")
                    .font(.caption)
                Text(lastNotificationStatus).font(.caption)
                Text(lastReadStatus).font(.caption)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Aprendizado de ofertas").font(.headline)
                    Text("\(observedOfferCount) ofertas legíveis no histórico local")
                    if adaptiveTarget > 0 {
                        Text(String(format: "Filtro atual: R$ %.2f/h após combustível", adaptiveTarget))
                    }
                    Text("Após 20 ofertas, o filtro pode subir até 25% acima da sua meta. Nunca reduz sua meta. Esse histórico não confirma corridas realizadas nem ganhos.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Text("Tempo desde a aparição da oferta e entrega da notificação ainda precisam ser medidos no iPhone. Finanças automáticas e Zarp Super ainda sem fonte conectada.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            }
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
