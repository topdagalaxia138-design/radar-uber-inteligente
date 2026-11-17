import SwiftUI
import ReplayKit
import UserNotifications
import UIKit

struct ContentView: View {
    @AppStorage("fuelCostPerKm", store: RadarEnvironment.sharedDefaults)
    private var fuelCostPerKm = 0.28
    @AppStorage("targetNetPerHour", store: RadarEnvironment.sharedDefaults)
    private var targetNetPerHour = 0.0
    @AppStorage("observedOfferCount", store: RadarEnvironment.sharedDefaults)
    private var observedOfferCount = 0
    @AppStorage("adaptiveTarget", store: RadarEnvironment.sharedDefaults)
    private var adaptiveTarget = 0.0
    @Environment(\.scenePhase) private var scenePhase
    @State private var reading: RadarReadingSnapshot?
    @State private var clock = Date()
    @State private var testStatus = ""
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
                        Text("Meta por hora após combustível (R$)")
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

                if !RadarEnvironment.sharedContainerAvailable {
                    Text("Permissão de compartilhamento ausente. A leitura não pode operar nesta instalação.")
                        .foregroundStyle(.red).font(.footnote)
                }
                Text("Transmissão de tela").font(.headline)
                BroadcastPicker()
                    .frame(width: 60, height: 60)
                    .disabled(!RadarEnvironment.sharedContainerAvailable)

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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Atividade da leitura").font(.headline)
                    if let reading {
                        Text(reading.activity(at: clock)).font(.subheadline.bold())
                        Text("Quadros recebidos para análise: \(reading.frames)").font(.caption)
                        Text(reading.readStatus).font(.caption)
                        if reading.lastProcessedAt != nil {
                            Text(String(format: "Último OCR e decisão: %.2f s", reading.processingSeconds)).font(.caption)
                        }
                        Text(reading.notificationStatus).font(.caption)
                        if !reading.offerSummary.isEmpty {
                            Text("Última oferta confirmada").font(.caption)
                            Text(reading.offerSummary).font(.headline)
                            if let date = reading.offerAt {
                                Text("Confirmada há \(Int(max(0, clock.timeIntervalSince(date)))) s; não é saldo nem oferta ativa.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Inicie Radar Leitura pela Central de Controle.").font(.caption)
                    }
                    Text("Versão de teste: " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")).font(.caption)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Button("Testar banner em 3 segundos") {
                    Task { await testBanner() }
                }.buttonStyle(.borderedProminent)
                Text("Teste apenas do aviso; não representa uma corrida. Após tocar, abra Fotos para observar o banner fora do Radar.")
                    .font(.caption).foregroundStyle(.secondary)
                if !testStatus.isEmpty { Text(testStatus).font(.caption) }
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
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await refreshNotificationStatus()
                while !Task.isCancelled {
                    clock = Date()
                    reading = RadarEnvironment.readingStore?.load()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    @MainActor
    private func testBanner() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            testStatus = "Autorize notificações nos Ajustes para testar o banner."
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "RADAR • TESTE DE AVISO"
        content.body = "Teste de apresentação. Não é recomendação de corrida."
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: "radar-banner-test", content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
            testStatus = "Teste agendado. Abra Fotos e observe por alguns segundos."
        } catch {
            testStatus = "Não consegui agendar o teste: " + error.localizedDescription
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized {
            notificationStatus = settings.alertSetting == .enabled
                ? "Notificações autorizadas; alertas permitidos"
                : "Notificações autorizadas, mas alertas desativados nos Ajustes"
        } else {
            notificationStatus = "Notificações ainda não autorizadas para alertas"
        }
    }
}

private struct BroadcastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        // Discover the actual signed extension ID instead of assuming the original ID.
        if let plugins = Bundle.main.builtInPlugInsURL,
           let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) {
            picker.preferredExtension = urls.compactMap { Bundle(url: $0) }.first {
                ($0.infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload"
            }?.bundleIdentifier
        }
        picker.showsMicrophoneButton = false
        picker.tintColor = .systemGreen
        picker.overrideUserInterfaceStyle = .dark
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
