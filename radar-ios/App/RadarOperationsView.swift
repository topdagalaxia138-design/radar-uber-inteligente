import SwiftUI

struct RadarOperationsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("journeyGPSEnabled", store: RadarEnvironment.sharedDefaults) private var gpsEnabled = false
    @State private var finance = RadarFinanceState()
    @State private var payments = RadarPaymentState()
    @State private var journeys = RadarJourneyState()
    @State private var distances = RadarDistanceState()
    @State private var now = Date()
    @State private var gpsStatus = "GPS ainda não ativado"
    private var reports: [RadarJourneyReport] {
        journeys.journeys.suffix(100).reversed().map {
            RadarJourneyReport(journey: $0, payments: payments, distances: distances)
        }
    }
    var body: some View {
        Form {
            trackingSection
            if let latest = reports.first { currentSection(latest) }
            tripSection
            walletSection
            costsSection
            planningSection
            historySection
        }
        .navigationTitle("Jornada e resultado")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                now = Date()
                finance = RadarEnvironment.financeStore?.load() ?? .init()
                payments = RadarEnvironment.paymentStore?.load() ?? .init()
                journeys = RadarEnvironment.journeyStore?.load() ?? .init()
                distances = RadarEnvironment.distanceStore?.load() ?? .init()
                gpsStatus = RadarEnvironment.sharedDefaults?.string(forKey: "journeyGPSStatus") ?? "GPS ainda não ativado"
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    private var trackingSection: some View {
        Section("Acompanhamento automático") {
            Toggle("Quilômetros e combustível por GPS", isOn: $gpsEnabled)
                .onChange(of: gpsEnabled) { _, enabled in
                    if enabled { RadarLocationTracker.shared.start(requestPermission: true) }
                    else { RadarLocationTracker.shared.stop() }
                }
            Text(gpsStatus).font(.caption)
            if gpsEnabled {
                Button("Preparar GPS para iniciar a leitura") { RadarLocationTracker.shared.start(requestPermission: true) }
            }
            Text("Autorize uma vez, prepare o GPS e inicie Radar Leitura em até um minuto. A jornada acompanha a transmissão; pausas e interrupções ficam identificadas. A localização continua em segundo plano durante a captura. Coordenadas não são guardadas.")
                .font(.caption)
            Text("Tempo de captura não é confirmação de tempo online na Uber. Combustível é estimado pelos quilômetros acompanhados e pelo preço e consumo configurados.").font(.caption)
        }
    }
    private func currentSection(_ report: RadarJourneyReport) -> some View {
        let closeout = RadarShiftCloseout(report: report, payments: payments, finance: finance)
        return Section(report.journey.endedAt == nil ? "Última jornada iniciada" : "Última jornada encerrada") {
            Text(closeout.status).font(.headline)
            Text(report.journey.startedAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Tempo acompanhado", value: String(format: "%.0f min", report.journey.trackedSeconds / 60))
            LabeledContent("Conclusões capturadas", value: String(report.completed.count))
            LabeledContent("Recebimentos por confirmar", value: String(report.pending))
            money("Dinheiro confirmado • parcial", closeout.cash)
            money("Pela Uber confirmado • parcial", closeout.digital)
            money("Ganhos individuais • lidos ou estimados", closeout.earnings)
            if let distance = report.distance {
                LabeledContent("Quilômetros GPS", value: String(format: "%.2f km", distance.kilometers))
                LabeledContent("Consumo estimado", value: String(format: "%.2f litros", distance.fuelLiters))
                money("Combustível estimado", report.fuelCost)
                if !report.gpsComplete { Text("GPS parcial: faltam trechos ou cobertura nas extremidades da jornada.").foregroundStyle(.orange) }
            } else { Text("Sem distância acompanhada: consumo do turno ainda desconhecido.") }
            money("Ganhos menos combustível estimado", closeout.marginAfterFuel)
            money("Aluguel, Passe e ajustes capturados no turno", closeout.capturedExpense)
            money("Resultado após despesas capturadas • parcial", closeout.resultAfterCapturedExpenses)
            Text("Recebimento é diferente de ganho: o valor recolhido pode incluir a parte da Uber. O resultado usa ganhos individuais exibidos ou um lançamento associado por horário. A associação por horário é uma estimativa, não uma identidade confirmada da viagem. Despesas semanais fora deste turno não estão rateadas aqui; o resultado não é lucro líquido. Abastecimento não é descontado novamente como consumo.").font(.caption)
            if report.journey.interrupted || (report.journey.endedAt == nil && now.timeIntervalSince(report.journey.lastHeartbeat) > 30) {
                Text("Jornada interrompida ou sem sinal recente; histórico não presume acompanhamento contínuo.").foregroundStyle(.orange)
            }
        }
    }
    private var tripSection: some View {
        let entries = RadarTripReconciler.settlements(payments: payments, finance: finance)
        return Section("Corridas e recebimentos") {
            if payments.receipts.isEmpty { Text("Nenhuma etapa de corrida acompanhada ainda.") }
            ForEach(payments.receipts.suffix(20).reversed()) { receipt in
                VStack(alignment: .leading, spacing: 5) {
                    Text(receipt.phase?.label ?? "Etapa anterior à atualização").font(.headline)
                    Text(receipt.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                    if let offer = receipt.offer {
                        Text(String(format: "Oferta de referência: R$ %.2f • %.0f min • %.1f km", offer.fare, offer.minutes, offer.kilometers)).font(.caption)
                    }
                    Text(receipt.method == .cash ? "Dinheiro" : receipt.method == .uberPix ? "Pix Uber" : receipt.method == .uberApp ? "Pagamento no app" : "Forma ainda não confirmada").font(.caption)
                    money(receipt.status == .received ? "Recebido confirmado" : "Valor ainda não confirmado", receipt.amount)
                    if let settlement = entries.first(where: { $0.receipt.id == receipt.id }) {
                        money("Ganhos da viagem", settlement.driverEarnings)
                        Text(settlement.source).font(.caption)
                    }
                    if let reason = receipt.missingEvidence { Text(reason).font(.caption).foregroundStyle(.orange) }
                    if receipt.status == .unpaid { Text("Não pago: fora dos recebimentos").font(.caption).foregroundStyle(.orange) }
                }
            }
            Text("Oferta não gera recebimento. As etapas e confirmações visíveis ficam vinculadas à mesma corrida; cancelamentos e não pagamentos são separados.").font(.caption)
        }
    }
    private var walletSection: some View {
        let check = RadarWalletReconciliation(finance: finance, payments: payments, now: now)
        return Section("Conciliação da carteira") {
            money("Saldo inicial observado", check.opening?.balance)
            if let date = check.opening?.observedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
            money("Saldo final observado", check.closing?.balance)
            if let date = check.closing?.observedAt { Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
            money("Variação entre os saldos", check.change)
            money("Lançamentos capturados nesse intervalo", check.opening == nil ? nil : check.movementTotal)
            money("Diferença por explicar", check.unexplained)
            Text(check.message).font(.caption)
            Text("\(check.movementCount) lançamentos no intervalo. Horários do extrato têm precisão de minuto; itens perto dos saldos podem exigir nova conferência. Recebimentos digitais não são somados novamente aos lançamentos da carteira.").font(.caption)
            Text("\(check.pendingReceipts) recebimentos pendentes de confirmação. Diferença não é automaticamente dinheiro, dívida de aluguel ou lucro.").font(.caption)
        }
    }
    private var costsSection: some View {
        let movements = finance.capturedThisWeek(now: now)
        let rentals = movements.filter { $0.kind == .rentalDebit || $0.kind == .rentalCredit }
        let passes = movements.filter { $0.kind == .passDebit || $0.kind == .passCredit }
        return Section("Custos capturados da semana") {
            money("Aluguel debitado menos créditos", rentals.isEmpty ? nil : -rentals.reduce(0) { $0 + $1.amount })
            money("Passe debitado menos créditos", passes.isEmpty ? nil : -passes.reduce(0) { $0 + $1.amount })
            Text("Valores parciais do extrato. Não são cobrados novamente sobre o saldo da carteira. Abastecimento é saída de caixa; consumo é custo estimado do percurso. Um não deve ser descontado junto do outro como se fossem dois consumos.").font(.caption)
        }
    }
    private var planningSection: some View {
        let windows = RadarHistoryPlanner.windows(reports: reports, now: now)
        return Section("Planejamento pelo seu histórico") {
            if windows.isEmpty {
                Text("Ainda faltam jornadas comparáveis com cobertura suficiente.")
                Text("Cada faixa precisa de pelo menos três dias distintos, nas últimas oito semanas, com jornadas encerradas, GPS sem lacunas, duas conclusões ou mais e todos os recebimentos e ganhos individuais dessas conclusões confirmados.").font(.caption)
            }
            ForEach(windows.prefix(5)) { window in
                VStack(alignment: .leading) {
                    Text("\(weekday(window.weekday)) • início entre \(window.startHour)h e \(window.startHour + 3)h")
                    Text(String(format: "Mediana R$ %.2f/h após combustível • %d dias", window.medianHourlyAfterFuel, window.samples))
                        .font(.caption)
                }
            }
            Text("Referência pessoal do período acompanhado, não previsão garantida de demanda nem lucro após todos os custos. Não altera automaticamente os critérios das ofertas.").font(.caption)
        }
    }
    private var historySection: some View {
        Section("Histórico de jornadas") {
            if reports.isEmpty { Text("A primeira jornada será criada quando Radar Leitura iniciar.") }
            ForEach(reports.prefix(12)) { report in
                VStack(alignment: .leading, spacing: 5) {
                    Text(report.journey.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                    Text("\(report.completed.count) conclusões • \(report.confirmed.count) recebimentos confirmados")
                    if let rate = report.hourlyAfterFuel { Text(String(format: "R$ %.2f/h após combustível", rate)) }
                    else { Text("Dados parciais; não usado no planejamento").foregroundStyle(.secondary) }
                }.font(.caption)
            }
        }
    }
    private func weekday(_ value: Int) -> String {
        ["", "Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"][min(max(value, 1), 7)]
    }
    @ViewBuilder private func money(_ label: String, _ amount: Double?) -> some View {
        HStack {
            Text(label); Spacer()
            if let amount { Text(amount, format: .currency(code: "BRL")).monospacedDigit() }
            else { Text("Não confirmado").foregroundStyle(.secondary) }
        }
    }
}

