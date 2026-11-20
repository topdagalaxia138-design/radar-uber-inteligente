import SwiftUI
import UIKit

private enum RadarPalette {
    static let ink = Color(red: 0.08, green: 0.14, blue: 0.20)
    static let green = Color(red: 0.03, green: 0.47, blue: 0.30)
    static let canvas = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let gold = Color(red: 0.67, green: 0.39, blue: 0.03)
}

private enum RadarPanel: String, Identifiable {
    case wallet, cash, digital, earnings, fuel, goal, reading, notifications
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wallet: return "Carteira Uber"
        case .cash: return "Dinheiro recebido"
        case .digital: return "Pagamentos pela Uber"
        case .earnings: return "Resultado semanal"
        case .fuel: return "Combustível"
        case .goal: return "Meta de 80 viagens"
        case .reading: return "Radar Leitura"
        case .notifications: return "Avisos no iPhone"
        }
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("fuelPricePerLiter", store: RadarEnvironment.sharedDefaults) private var price = 0.0
    @AppStorage("fuelKilometersPerLiter", store: RadarEnvironment.sharedDefaults) private var consumption = 9.0
    @AppStorage("targetNetPerHour", store: RadarEnvironment.sharedDefaults) private var target = 0.0
    @State private var selectedTab = 0
    @State private var panel: RadarPanel?
    @State private var finance = RadarFinanceState()
    @State private var reading: RadarReadingSnapshot?
    @State private var clock = Date()

    private var active: Bool { reading?.activity(at: clock) == "Recebendo imagens da tela" }
    private var cost: Double? { RadarFuelCost.perKilometer(pricePerLiter: price, kilometersPerLiter: consumption) }
    private var trips: RadarFinanceObservation? { finance.latest(.weeklyTrips, now: clock) }
    private var wallet: RadarFinanceObservation? { finance.latest(.walletBalance, now: clock) }
    private var version: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?" }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                home
                    .toolbar(.hidden, for: .navigationBar)
            }.tabItem { Label("Início", systemImage: "house.fill") }.tag(0)
            NavigationStack { RadarWeeklyPlanView() }
                .tabItem { Label("Semana", systemImage: "chart.bar.fill") }.tag(1)
            NavigationStack { offerSettings }
                .tabItem { Label("Ofertas", systemImage: "slider.horizontal.3") }.tag(2)
            RadarDetailsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }.tag(3)
        }
        .tint(RadarPalette.green)
        .preferredColorScheme(.light)
        .sheet(item: $panel) { destination in
            NavigationStack {
                panelContents(destination)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { panel = nil } } }
            }.tint(RadarPalette.green).preferredColorScheme(.light)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            // Initial values confirmed for this installation; existing saved settings win.
            if price <= 0 { price = 4.20 }
            if consumption <= 0 { consumption = 9 }
            while !Task.isCancelled {
                clock = Date()
                finance = RadarEnvironment.financeStore?.load() ?? RadarFinanceState()
                reading = RadarEnvironment.readingStore?.load()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seu próximo passo,").font(.subheadline).foregroundStyle(.secondary)
                        Text("mais rentável.").font(.system(size: 30, weight: .bold, design: .rounded))
                    }
                    Spacer()
                    Button { panel = .notifications } label: {
                        Image(systemName: "bell.badge").font(.title3).frame(width: 46, height: 46)
                            .background(.white, in: Circle())
                    }.accessibilityLabel("Abrir avisos e notificações")
                }.foregroundStyle(RadarPalette.ink)
                HStack {
                    Label("RADAR", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .black)).tracking(2)
                    Spacer()
                    Text("VERSÃO " + version).font(.system(size: 10, weight: .semibold, design: .monospaced))
                }.foregroundStyle(RadarPalette.green)

                weekHero
                monitorCard
                if reading?.decisionRecord != nil { lastDecision }
                HStack {
                    Text("Seu dinheiro").font(.title3.bold())
                    Spacer()
                    Button("Ver semana →") { selectedTab = 1 }.font(.subheadline.bold())
                }
                financeGrid
                criteriaCard
                Text("Valores lidos na Uber. Não há conexão direta com sua conta.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }.padding(20)
        }.background(RadarPalette.canvas.ignoresSafeArea())
    }

    private var weekHero: some View {
        Button { panel = .wallet } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("SUA CARTEIRA UBER", systemImage: "wallet.pass.fill")
                        .font(.system(size: 11, weight: .bold)).tracking(1)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.foregroundStyle(.white.opacity(0.8))
                if let wallet {
                    Text(wallet.value < 0 ? "Falta quitar" : "Saldo exibido")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    Text(abs(wallet.value), format: .currency(code: "BRL"))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    if stale(wallet) {
                        Label("DESATUALIZADO • última leitura", systemImage: "clock.badge.exclamationmark")
                            .font(.caption.bold()).foregroundStyle(Color.yellow)
                    }
                    Text(wallet.observedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text("Abra o saldo na Uber").font(.title2.bold())
                    Text("Aguardando a primeira leitura confirmada.").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Divider().overlay(.white.opacity(0.3))
                HStack {
                    Image(systemName: "flag.checkered")
                    Text(trips.map { "\(Int($0.value)) de 80 viagens lidas" } ?? "Meta semanal: 80 viagens")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("Detalhes ›").font(.caption.bold())
                }
                Text("Inclui lançamentos da carteira. Não some o aluguel novamente.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.8))
            }.padding(22).foregroundStyle(.white)
                .background(LinearGradient(colors: [RadarPalette.green, Color(red: 0.025, green: 0.27, blue: 0.23)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
    }

    private var monitorCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "trafficlight.fill").font(.title2)
                    .foregroundStyle(active ? RadarPalette.green : RadarPalette.gold)
                    .frame(width: 48, height: 48)
                    .background((active ? RadarPalette.green : RadarPalette.gold).opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Radar de ofertas").font(.headline)
                    Text(active ? "Avaliando a tela do iPhone" : "Monitoramento parado")
                        .font(.caption).foregroundStyle(active ? RadarPalette.green : RadarPalette.gold)
                }
                Spacer(minLength: 8)
                BroadcastPicker().frame(width: 60, height: 60)
                    .background(RadarPalette.green.opacity(0.06), in: Circle())
                    .disabled(!RadarEnvironment.sharedContainerAvailable)
                    .accessibilityLabel("Iniciar ou encerrar transmissão Radar Leitura")
            }
            Text(active ? "Mantenha a oferta visível na Uber. O aviso chega pelo iPhone."
                 : "Use o botão ao lado para iniciar a transmissão Radar Leitura.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Label("UBER", systemImage: "car.fill").font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RadarPalette.canvas, in: Capsule())
                Spacer()
                Button("Como ativar ›") { panel = .reading }.font(.caption.bold())
                Button { selectedTab = 2 } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Ajustar critério das ofertas")
            }
        }.padding(18).cardSurface()
    }

    private var financeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            moneyTile(.cash, title: "Dinheiro", icon: "banknote.fill", metric: .cashReceived, empty: "Não confirmado")
            moneyTile(.digital, title: "Pela Uber", icon: "creditcard.fill", metric: .digitalEarnings, empty: "Ainda não lido")
            moneyTile(.earnings, title: "Resultado semanal", icon: "chart.bar.fill", metric: .weeklyEarnings, empty: "Ainda não lido")
            Button { panel = .fuel } label: {
                VStack(alignment: .leading, spacing: 10) {
                    tileHeader("Combustível", icon: "fuelpump.fill")
                    Text(cost.map { String(format: "R$ %.3f/km", $0) } ?? "Configurar")
                        .font(.headline).monospacedDigit()
                    Text("Preço e consumo salvos").font(.caption2).foregroundStyle(.secondary)
                    Text("AJUSTAR ›").font(.system(size: 10, weight: .bold)).foregroundStyle(RadarPalette.green)
                }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(16).cardSurface()
            }.buttonStyle(.plain)
        }
    }

    private func moneyTile(_ route: RadarPanel, title: String, icon: String,
                           metric: RadarFinanceMetric, empty: String) -> some View {
        let observation = finance.latest(metric, now: clock)
        return Button { panel = route } label: {
            VStack(alignment: .leading, spacing: 10) {
                tileHeader(title, icon: icon)
                if let observation {
                    Text(observation.value, format: .currency(code: "BRL"))
                        .font(.headline).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
                    Text(stale(observation) ? "Última leitura • desatualizado" : "Valor lido na tela")
                        .font(.caption2).foregroundStyle(stale(observation) ? RadarPalette.gold : .secondary)
                } else {
                    Text(empty).font(.subheadline.bold())
                    Text("Abra para entender").font(.caption2).foregroundStyle(.secondary)
                }
                Text("VER DETALHES ›").font(.system(size: 10, weight: .bold)).foregroundStyle(RadarPalette.green)
            }.frame(maxWidth: .infinity, minHeight: 142, alignment: .leading).padding(16).cardSurface()
        }.buttonStyle(.plain).foregroundStyle(RadarPalette.ink)
    }

    private func tileHeader(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(RadarPalette.green)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Suas faixas", systemImage: "slider.horizontal.3").font(.headline)
                Spacer()
                Button("Ajustar ›") { selectedTab = 2 }.font(.caption.bold())
            }
            HStack(spacing: 12) {
                rateBlock("APROVAR", value: target > 0 ? String(format: "≥ R$ %.2f/min", target / 60) : "Definir meta", color: RadarPalette.green)
                rateBlock("ABAIXO DA META", value: target > 0 ? String(format: "< R$ %.2f/min", target / 60) : "Sem avaliação", color: .red)
            }
            Divider()
            HStack {
                Text("Combustível por km").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(cost.map { String(format: "R$ %.3f  ✎", $0) } ?? "Configurar  ✎") { panel = .fuel }
                    .font(.subheadline.bold())
            }
            Text("Busca + viagem, após combustível. O critério é igual para corridas curtas e longas.")
                .font(.caption).foregroundStyle(.secondary)
            Button { panel = .goal } label: {
                HStack {
                    Label("Objetivo de 80 viagens", systemImage: "flag.checkered")
                    Spacer()
                    Text(trips.map { "\(Int($0.value))/80 ›" } ?? "Ver ›")
                }.font(.subheadline.bold())
            }
        }.padding(18).cardSurface()
    }

    private func rateBlock(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(value).font(.caption.bold()).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var lastDecision: some View {
        if let record = reading?.decisionRecord {
            Button { selectedTab = 3 } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ÚLTIMA ANÁLISE • HISTÓRICO").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    Text(record.title).font(.headline)
                    Text(record.summary).font(.subheadline).monospacedDigit()
                    Text(record.detail).font(.caption).foregroundStyle(.secondary)
                    Text("Não confirma disponibilidade, aceite nem corrida realizada.").font(.caption2).foregroundStyle(.secondary)
                }.padding(18).cardSurface()
            }.buttonStyle(.plain).foregroundStyle(RadarPalette.ink)
        }
    }

    private var offerSettings: some View {
        Form {
            Section("Decisão rápida") {
                LabeledContent("Meta após combustível") {
                    TextField("R$/h", value: $target, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                }
                Text(target > 0 ? String(format: "Equivale a R$ %.2f/min após combustível.", target / 60)
                     : "Defina uma meta positiva para liberar avaliação.")
                Text("Não há piso de R$ 25. Corridas curtas e longas usam a mesma meta.")
            }
            Section("Combustível usado na análise") {
                fuelFields
            }
            Section("Limites atuais") {
                Text("A análise inclui busca e viagem. Ainda não inclui integralmente espera, aluguel, Passe, deslocamentos sem passageiro ou conciliação do caixa.")
                Text("Não é garantia de lucro nem de disponibilidade da oferta. Sem aviso não significa aprovação.")
            }
            Section {
                Button("Como iniciar a leitura") { panel = .reading }
                Button("Avisos e notificações") { panel = .notifications }
            }
        }.navigationTitle("Ofertas").navigationBarTitleDisplayMode(.large)
    }

    @ViewBuilder private var fuelFields: some View {
        LabeledContent("Preço por litro") {
            TextField("R$/l", value: $price, format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
        LabeledContent("Consumo real") {
            TextField("km/l", value: $consumption, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
        }
        if let cost {
            LabeledContent("Custo estimado por km", value: String(format: "R$ %.3f", cost))
        } else {
            Text("Valores inválidos: recomendações ficam indisponíveis.").foregroundStyle(.red)
        }
        Text("Dados guardados no aparelho. Atualize apenas quando preço ou consumo mudarem. Abastecimento e consumo do turno ainda não são conciliados.")
            .font(.caption)
    }

    @ViewBuilder private func panelContents(_ route: RadarPanel) -> some View {
        Form {
            switch route {
            case .fuel:
                Section("Cálculo automático") { fuelFields }
            case .reading:
                Section("Iniciar a transmissão") {
                    Text("1. Toque no botão abaixo e selecione Radar Leitura.")
                    BroadcastPicker().frame(width: 60, height: 60)
                    Text("2. Inicie a transmissão e abra a Uber no iPhone.")
                    Text("3. Aguarde o estado de leitura ativa. A transmissão não captura a tela do CarPlay.")
                    Text("Se o seletor não abrir: na Central de Controle, mantenha pressionado o botão de gravação e escolha Radar Leitura.")
                }
                Section("Estado atual") {
                    Text(reading?.activity(at: clock) ?? "Nenhuma transmissão iniciada")
                }
            case .notifications:
                Section("Apresentação dos avisos") {
                    Text("Confira permissão de alertas, banners e entrega imediata nos ajustes do iPhone.")
                    Button("Abrir ajustes de notificações") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Button("Abrir teste de aviso e diagnóstico") { panel = nil; selectedTab = 3 }
                    Text("CarPlay continua indisponível nesta instalação.")
                }
            case .goal:
                Section("Viagens lidas nesta semana") {
                    if let trips {
                        Text("\(Int(trips.value)) de 80")
                        ProgressView(value: min(max(trips.value, 0), 80), total: 80)
                        Text("Faltam \(max(0, 80 - Int(trips.value)))")
                        observationDate(trips)
                    } else { Text("Abra o resumo semanal da Uber com Radar Leitura ativo.") }
                    Text("Ofertas analisadas não contam como viagens concluídas. A contagem não comprova elegibilidade ao benefício da locadora.")
                }
            case .wallet, .cash, .digital, .earnings:
                let metric: RadarFinanceMetric = route == .wallet ? .walletBalance : route == .cash ? .cashReceived
                    : route == .digital ? .digitalEarnings : .weeklyEarnings
                Section("Último valor observado") {
                    if let observation = finance.latest(metric, now: clock) {
                        Text(observation.value, format: .currency(code: "BRL")).font(.largeTitle.bold())
                        observationDate(observation)
                        if stale(observation) { Label("Desatualizado: abra a tela correspondente na Uber.", systemImage: "clock") }
                    } else { Text("Nenhum valor confirmado para este campo.") }
                }
                Section("Como interpretar") {
                    if route == .wallet {
                        Text("É o saldo da carteira, incluindo seus lançamentos. Não some o aluguel novamente. O Radar precisa ver uma nova tela de saldo para atualizar.")
                    } else if route == .cash {
                        Text("O acompanhamento de Recolher pagamento → Dinheiro → Pagamento recolhido ainda não foi implementado. Viagem marcada como dinheiro ou diferença entre saldos não comprova quanto recebeu.")
                    } else if route == .digital {
                        Text("Pagamento no app e Pix pelo QR Code da Uber entram na carteira dela. Não representam dinheiro disponível nas suas mãos.")
                    } else {
                        Text("Resultado exibido em Ganhos, que pode incluir aluguel e ajustes. Não é lucro após combustível. Confira o período e os lançamentos em Minha semana.")
                    }
                }
                Section {
                    Button("Abrir Minha semana") { panel = nil; selectedTab = 1 }
                    Button("Como atualizar pela leitura") { panel = .reading }
                }
            }
        }
    }

    private func stale(_ observation: RadarFinanceObservation) -> Bool {
        clock.timeIntervalSince(observation.observedAt) > 15 * 60
    }

    private func observationDate(_ observation: RadarFinanceObservation) -> some View {
        Text("Lido em " + observation.observedAt.formatted(date: .abbreviated, time: .shortened)
             + " • " + observation.screen).font(.caption).foregroundStyle(.secondary)
    }
}

private struct RadarCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.black.opacity(0.045), lineWidth: 1))
            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
    }
}
private extension View {
    func cardSurface() -> some View { modifier(RadarCardSurface()) }
}
