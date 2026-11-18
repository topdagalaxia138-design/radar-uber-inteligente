import SwiftUI

struct RadarWeeklyPlanView: View {
    @AppStorage("weeklyRentalPlan", store: RadarEnvironment.sharedDefaults) private var rental = 835.0
    @AppStorage("monthlyPersonalGoal", store: RadarEnvironment.sharedDefaults) private var monthlyGoal = 1000.0
    @AppStorage("plannedWorkDays", store: RadarEnvironment.sharedDefaults) private var days = 7
    @AppStorage("plannedHoursPerDay", store: RadarEnvironment.sharedDefaults) private var hours = 6.0
    @AppStorage("weeklyPassBudgetKnown", store: RadarEnvironment.sharedDefaults) private var passKnown = false
    @AppStorage("weeklyPassBudget", store: RadarEnvironment.sharedDefaults) private var passBudget = 0.0

    private var plan: RadarWeeklyPlan {
        RadarWeeklyPlan(rental: rental, monthlyPersonalGoal: monthlyGoal,
                        workDays: days, hoursPerDay: hours, passBudget: passKnown ? passBudget : nil)
    }
    private var overview: RadarWeeklyOverview {
        var ledger: RadarWeeklyLedger?
        if let data = RadarEnvironment.sharedDefaults?.data(forKey: "confirmedWeeklyLedger") {
            ledger = try? JSONDecoder().decode(RadarWeeklyLedger.self, from: data)
            ledger?.referenceDate = nil
        }
        return RadarWeeklyOverview(plan: plan, ledger: ledger)
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
                Toggle("Informei a previsão semanal do Passe", isOn: $passKnown)
                if passKnown {
                    HStack {
                        Text("Previsão do Passe na semana")
                        Spacer()
                        TextField("Valor", value: $passBudget, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                    }
                    Text("Informe zero somente se não houver esse custo. Previsão não confirma pagamento nem validade do Passe.")
                        .font(.caption)
                } else {
                    Text("Custo do Passe ainda não informado; não será tratado como zero.")
                        .font(.caption)
                }
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
            Section("Semana — somente valores confirmados") {
                if overview.ledger == nil {
                    Text("Ganhos e abatimentos ainda não sincronizados")
                        .font(.headline)
                    Text("Não vou mostrar zero como se não houvesse ganhos. A fonte de corridas concluídas e lançamentos da Uber ainda precisa ser conectada.")
                }
                valueRow("Ganhos registrados", overview.confirmedReceived)
                valueRow("Dinheiro e maquininha registrados", overview.cashAndOwnTerminal)
                valueRow("Créditos digitais registrados", overview.digitalCredits)
                valueRow("Combustível das viagens registradas", overview.registeredFuel)
                valueRow("Aluguel restante estimado pelos registros", overview.estimatedRentalRemaining)
                if let count = overview.registeredTrips {
                    Text("Corridas concluídas registradas: \(count)")
                    Text("Registros podem ser parciais; confira o total oficial da Uber.")
                } else {
                    Text("Corridas concluídas: não sincronizadas")
                }
                Text("Meta semanal: 80 corridas concluídas")
                Text("Ofertas lidas não contam como corridas feitas, ganhos ou benefício confirmado. O benefício Zarp depende da confirmação no contrato/extrato.")
                    .font(.caption)
            }
            Section("Como interpretar o saldo") {
                Text("Dinheiro recebido diretamente e pagamentos na sua maquininha entram no seu caixa; não abatem automaticamente o aluguel na Uber.")
                Text("Pagamentos digitais pela Uber podem compor a retenção. O saldo oficial também pode conter taxas e ajustes: confira os lançamentos antes de atribuir tudo ao aluguel.")
                Text("A previsão do aluguel não é o saldo oficial da Uber. O Radar não cobra aluguel novamente nem confirma que ele foi quitado.")
                    .font(.caption)
            }
        }
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
                Text("Não confirmado").foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
