import SwiftUI

private enum RadarStyle {
    static let background = Color(red: 0.025, green: 0.045, blue: 0.075)
    static let panel = Color(red: 0.07, green: 0.10, blue: 0.15)
    static let green = Color(red: 0.30, green: 0.94, blue: 0.66)
    static let amber = Color(red: 1, green: 0.73, blue: 0.30)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fuelPricePerLiter", store: RadarEnvironment.sharedDefaults) private var price = 0.0
    @AppStorage("fuelKilometersPerLiter", store: RadarEnvironment.sharedDefaults) private var consumption = 9.0
    @AppStorage("targetNetPerHour", store: RadarEnvironment.sharedDefaults) private var target = 0.0
    @State private var finance = RadarFinanceState()
    @State private var reading: RadarReadingSnapshot?
    @State private var clock = Date()
    @State private var showDetails = false

    private var active: Bool { reading?.activity(at: clock) == "Recebendo imagens da tela" }
    private var version: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }
    private var trips: RadarFinanceObservation? { finance.latest(.weeklyTrips, now: clock) }
    private var balance: RadarFinanceObservation? { finance.latest(.walletBalance, now: clock) }
    private var cost: Double? { RadarFuelCost.perKilometer(pricePerLiter: price, kilometersPerLiter: consumption) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    readingControl
                    decision
                    wallet
                    sectionTitle("SEU DINHEIRO", subtitle: "Valores separados. Sem contar duas vezes.")
                    moneyGrid
                    weeklyProgress
                    NavigationLink {
                        RadarWeeklyPlanView()
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.xaxis").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Minha semana").font(.headline)
                                Text("Aluguel, Passe e leituras financeiras").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(20).background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)
                    limits
                    Text("RADAR  /  VERSÃO " + version + "  •  LEITURA LOCAL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.6).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }.padding(20)
            }
            .background(RadarStyle.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .tint(RadarStyle.green)
            .sheet(isPresented: $showDetails) { RadarDetailsView().preferredColorScheme(.dark) }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    clock = Date()
                    finance = RadarEnvironment.financeStore?.load() ?? RadarFinanceState()
                    reading = RadarEnvironment.readingStore?.load()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.title2).foregroundStyle(RadarStyle.green)
                    .frame(width: 48, height: 48)
                    .background(RadarStyle.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text("RADAR").font(.system(size: 26, weight: .black, design: .rounded)).tracking(3)
                    Text("CONTROLE DA SUA JORNADA").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { showDetails = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
                    .frame(width: 48, height: 48).background(RadarStyle.panel, in: Circle())
            }.accessibilityLabel("Configurações, notificações e diagnóstico")
        }
    }

    private var readingControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(active ? RadarStyle.green : RadarStyle.amber).frame(width: 8, height: 8)
                Text(active ? "LEITURA ATIVA" : "LEITURA PARADA OU SEM SINAL")
                    .font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
            }.foregroundStyle(active ? RadarStyle.green : RadarStyle.amber)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(active ? "Volte para a Uber" : "Ative o Radar Leitura").font(.title3.bold())
                    Text(active ? "A análise depende da oferta visível no iPhone." : "Toque no botão ou use a Central de Controle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                BroadcastPicker().frame(width: 60, height: 60)
                    .disabled(!RadarEnvironment.sharedContainerAvailable)
                    .background(RadarStyle.green.opacity(0.08), in: Circle())
                    .accessibilityLabel("Abrir transmissão Radar Leitura")
            }
            if !RadarEnvironment.sharedContainerAvailable {
                Text("Compartilhamento indisponível nesta instalação. Abra o diagnóstico.")
                    .font(.caption).foregroundStyle(.red)
            } else if let reading, !active {
                Text(reading.activity(at: clock)).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder private var decision: some View {
        if let record = reading?.decisionRecord {
            let recent = active && record.isRecent(at: clock)
            let accent = recent ? (record.accepted ? RadarStyle.green : Color.red) : Color.gray
            VStack(alignment: .leading, spacing: 10) {
                Text(recent ? "OFERTA ANALISADA AGORA" : "ÚLTIMA ANÁLISE • HISTÓRICO")
                    .font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(accent)
                Text(record.title).font(.title2.bold())
                Text(record.summary).font(.headline).monospacedDigit()
                Text(record.detail).font(.subheadline).foregroundStyle(.secondary)
                Text(recent ? "Aviso não confirma aceitação nem disponibilidade na Uber." : "Esta oferta pode ter expirado. Não representa uma corrida realizada.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(accent.opacity(0.4), lineWidth: 1))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "scope").font(.title2).foregroundStyle(RadarStyle.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aguardando uma oferta legível").font(.headline)
                    Text("Sem aviso não significa aprovação.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private var wallet: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(balance.map { $0.value > 0 ? "SALDO NA UBER" : "FALTA QUITAR NA UBER" } ?? "CARTEIRA UBER",
                      systemImage: "wallet.pass")
                    .font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
                Image(systemName: "arrow.down.right").foregroundStyle(RadarStyle.amber)
            }.foregroundStyle(.secondary)
            if let balance {
                Text(abs(balance.value), format: .currency(code: "BRL"))
                    .font(.system(size: 42, weight: .bold, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.65).lineLimit(1)
                Text(balance.value < 0 ? "Inclui os lançamentos da carteira. Não some o aluguel novamente."
                     : balance.value > 0 ? "Saldo positivo exibido na carteira; não é lucro líquido."
                     : "A carteira mostrou saldo zerado nesta leitura.")
                    .font(.caption).foregroundStyle(.secondary)
                stamp(balance)
            } else {
                Text("Aguardando leitura").font(.title2.bold())
                Text("Abra o saldo na Uber com a transmissão ativa.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(red: 0.10, green: 0.17, blue: 0.23), RadarStyle.panel],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var moneyGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            metric("DINHEIRO EXIBIDO", icon: "banknote", observation: finance.latest(.cashReceived, now: clock),
                   empty: "Não confirmado", note: "Ainda não acompanha a confirmação de cada pagamento.")
            metric("GANHOS DIGITAIS", icon: "creditcard", observation: finance.latest(.digitalEarnings, now: clock),
                   empty: "Ainda não lido", note: "Pagamentos pela Uber; não é dinheiro em mãos.")
            metric("RESULTADO SEMANAL", icon: "chart.line.uptrend.xyaxis", observation: finance.latest(.weeklyEarnings, now: clock),
                   empty: "Ainda não lido", note: "Total exibido pela Uber. Não é lucro após combustível.")
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "fuelpump").foregroundStyle(RadarStyle.amber)
                Text("COMBUSTÍVEL / KM").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
                Text(cost.map { String(format: "R$ %.3f", $0) } ?? "Configurar")
                    .font(.title3.bold()).monospacedDigit()
                Text("Estimativa por km. Reserva do turno e abastecimentos ainda não conciliados.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, minHeight: 175, alignment: .topLeading)
                .background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func metric(_ title: String, icon: String, observation: RadarFinanceObservation?,
                        empty: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(RadarStyle.green)
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
            if let observation {
                Text(observation.value, format: .currency(code: "BRL"))
                    .font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                stamp(observation)
            } else {
                Text(empty).font(.headline)
            }
            Text(note).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 175, alignment: .topLeading)
            .background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("META DA SEMANA", systemImage: "flag.checkered").font(.system(size: 11, weight: .bold)).tracking(1)
                Spacer()
                Text("80 VIAGENS").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }
            if let trips {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(trips.value))").font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("/ 80").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text("Faltam \(max(0, 80 - Int(trips.value)))").font(.headline).foregroundStyle(RadarStyle.green)
                }
                ProgressView(value: min(max(trips.value, 0), 80), total: 80).tint(RadarStyle.green)
                stamp(trips)
            } else {
                Text("Aguardando contagem da Uber").font(.headline)
                ProgressView(value: 0, total: 80).tint(.gray)
                Text("Ofertas analisadas não contam como viagens concluídas.").font(.caption).foregroundStyle(.secondary)
            }
            Text("A meta não confirma elegibilidade ao benefício da locadora.").font(.caption2).foregroundStyle(.secondary)
        }.padding(20).background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Critério das ofertas", systemImage: "slider.horizontal.3").font(.headline)
            Text(target > 0 ? String(format: "Meta: R$ %.2f/min após combustível", target / 60) : "Configure a meta para liberar recomendações.")
                .font(.subheadline).foregroundStyle(RadarStyle.green)
            Text("Busca + viagem. Aluguel, Passe, espera e caixa ainda não entram integralmente na decisão.")
                .font(.caption).foregroundStyle(.secondary)
            Divider().overlay(.white.opacity(0.1))
            Label("CarPlay ainda indisponível nesta instalação", systemImage: "car").font(.caption)
            Label("Nenhuma tela é enviada a um servidor", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            Button("Configurações e teste de aviso") { showDetails = true }.font(.subheadline.bold())
        }.padding(20).background(RadarStyle.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .bold)).tracking(1.5)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func stamp(_ observation: RadarFinanceObservation) -> some View {
        Text("Lido em " + observation.observedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption2).foregroundStyle(.secondary)
    }
}
