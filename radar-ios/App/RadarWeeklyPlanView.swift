import SwiftUI

struct RadarWeeklyPlanView: View {
    @AppStorage("weeklyRentalPlan", store: RadarEnvironment.sharedDefaults) private var rental = 835.0
    @AppStorage("monthlyPersonalGoal", store: RadarEnvironment.sharedDefaults) private var monthlyGoal = 1000.0
    @AppStorage("plannedWorkDays", store: RadarEnvironment.sharedDefaults) private var days = 7
    @AppStorage("plannedHoursPerDay", store: RadarEnvironment.sharedDefaults) private var hours = 6.0

    @State private var finance = RadarFinanceState()
    @State private var clock = Date()
    @State private var financeStatus = "Abra uma tela de ganhos ou saldo na Uber com Radar Leitura ativo."

    private var plan: RadarWeeklyPlan {
        RadarWeeklyPlan(rental: rental, monthlyPersonalGoal: monthlyGoal,
                        workDays: days, hoursPerDay: hours, passBudget: nil)
    }
    var body: some View {
        Form {
            Section("Planejamento — configure uma vez") {
                HStack {
                    Text("Aluguel previsto por semana")
                    Spacer()
                    TextField("835", value: $rental, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                }
                HStack {
                    Text("Meta pessoal por mês")
                    Spacer()
                    TextField("1000", value: $monthlyGoal, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                }
                Stepper("Dias planejados por semana: \(days)", value: $days, in: 1...7)
                Stepper("Horas planejadas por dia: \(Int(hours))", value: $hours, in: 1...6, step: 1)
                Text("Preço do Passe: leitura automática na tela correspondente. O preço unitário não é convertido em despesa semanal sem confirmação de compra.")
                    .font(.caption)
                if let goal = plan.weeklyPersonalGoal, let totalHours = plan.plannedHours {
                    valueRow("Meta pessoal equivalente por semana", goal)
                    Text(String(format: "Jornada planejada: %.0f h por semana", totalHours))
                } else {
                    Text("Revise os valores. O planejamento aceita até 6 horas por dia.").foregroundStyle(.red)
                }
                if let hourly = plan.plannedHourlyRequirement {
                    valueRow("Referência por hora após combustível", hourly)
                    Text("Distribui aluguel previsto, Passe previsto e meta pessoal pelas horas planejadas. Não prevê demanda, espera ou retorno e não altera o filtro das ofertas.")
                        .font(.caption)
                }
            }
            Section("Leitura financeira automática") {
                Text(financeStatus).font(.footnote)
                Text("Com Radar Leitura ligado, os valores são atualizados quando você abre as telas reconhecidas da Uber. Não é preciso enviar extratos ou cadastrar viagens.")
                    .font(.caption)
                ForEach(RadarFinanceMetric.allCases, id: \.rawValue) { metric in
                    VStack(alignment: .leading, spacing: 3) {
                        let observation = finance.latest(metric, now: clock)
                        if metric == .weeklyTrips {
                            HStack {
                                Text(metric.label)
                                Spacer()
                                Text(observation.map { String(Int($0.value)) } ?? "Ainda não lido")
                                    .foregroundStyle(observation == nil ? Color.secondary : Color.primary)
                            }
                        } else {
                            valueRow(metric.label, observation?.value)
                        }
                        if let observation {
                            Text("Lido em " + observation.observedAt.formatted(date: .abbreviated, time: .shortened)
                                 + " • tela " + observation.screen)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("São valores observados na tela, não acesso direto à conta. Um saldo negativo não é classificado como aluguel sem um rótulo explícito. Ler um preço do Passe não confirma compra.")
                    .font(.caption)
            }
            Section("Lançamentos capturados — parcial") {
                let captured = finance.capturedThisWeek(now: clock)
                let passDebits = captured.filter { $0.kind == .passDebit }.reduce(0) { $0 - $1.amount }
                let rentalDebits = captured.filter { $0.kind == .rentalDebit }.reduce(0) { $0 - $1.amount }
                let rentalCredits = captured.filter { $0.kind == .rentalCredit }.reduce(0) { $0 + $1.amount }
                valueRow("Cobranças do Passe capturadas", captured.contains(where: { $0.kind == .passDebit }) ? passDebits : nil)
                valueRow("Débitos Localiza capturados", captured.contains(where: { $0.kind == .rentalDebit }) ? rentalDebits : nil)
                valueRow("Créditos Localiza capturados", captured.contains(where: { $0.kind == .rentalCredit }) ? rentalCredits : nil)
                Text("Somente linhas com data, hora e valor reconhecidos. A lista pode estar incompleta; não é o total oficial da semana nem o saldo restante do aluguel.")
                    .font(.caption)
                ForEach(captured.prefix(12)) { movement in
                    VStack(alignment: .leading, spacing: 3) {
                        valueRow(movement.kind.label, movement.amount)
                        Text(movement.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("Um lançamento de viagem em dinheiro não informa quanto você recebeu em mãos. Nenhuma linha deste extrato é somada como nova corrida concluída.")
                    .font(.caption)
            }
            Section("Objetivo de 80 corridas") {
                if let trips = finance.latest(.weeklyTrips, now: clock) {
                    Text("Viagens exibidas nesta semana: \(Int(trips.value))")
                    Text("Faltam \(max(0, 80 - Int(trips.value))) para a meta de 80")
                    Text("Contagem lida na tela da Uber; benefício depende das regras e confirmação da Zarp.")
                        .font(.caption)
                } else {
                    Text("Aguardando leitura da contagem desta semana na Uber")
                }
                Text("Ofertas analisadas não são usadas como viagens concluídas. A semana anterior não é somada à atual.")
                    .font(.caption)
            }
            Section("Como interpretar o saldo") {
                Text("Dinheiro recebido diretamente e pagamentos na sua maquininha entram no seu caixa; não abatem automaticamente o aluguel na Uber.")
                Text("Pagamentos digitais pela Uber podem compor a retenção. O saldo oficial também pode conter taxas e ajustes: confira os lançamentos antes de atribuir tudo ao aluguel.")
                Text("A previsão do aluguel não é o saldo oficial da Uber. O Radar não cobra aluguel novamente nem confirma que ele foi quitado.")
                    .font(.caption)
            }
        }
        .task {
            while !Task.isCancelled {
                clock = Date()
                finance = RadarEnvironment.financeStore?.load() ?? RadarFinanceState()
                financeStatus = RadarEnvironment.readingStore?.load()?.financeReadStatus
                    ?? "Abra uma tela de ganhos ou saldo na Uber com Radar Leitura ativo."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(red: 0.025, green: 0.045, blue: 0.075))
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.30, green: 0.94, blue: 0.66))
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("Minha semana")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func valueRow(_ label: String, _ value: Double?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let value {
                Text(value, format: .currency(code: "BRL"))
                    .multilineTextAlignment(.trailing)
            } else {
                Text("Ainda não lido").foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
