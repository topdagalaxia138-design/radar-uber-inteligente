# Versão 18 — conciliação e jornadas

Implementação de 24/11/2026. Não equivale a aprovação de produção: GPS em segundo plano, OCR e notificações precisam de verificação no aparelho. Testes do núcleo: 143 aprovados após corrigir o extrato Comfort.

## Funcionamento

A transmissão cria e encerra jornadas automaticamente. Pausa encerra o trecho como interrompido; retomada abre outro. O tempo só cresce com pulsos recentes, sem preencher lacunas após travamento. Isto mede captura, não presença online na Uber.

A localização é opcional e precisa da autorização do iPhone. Ative Quilômetros e combustível por GPS, prepare o GPS e inicie a transmissão em até um minuto. Com autorização já concedida, abrir o Radar prepara o GPS automaticamente se a opção estiver ativa. Nenhuma coordenada é persistida; somente totais de quilômetros, litros e custo por jornada. Estado térmico sério/crítico interrompe também o GPS. Sem cobertura suficiente, o cálculo fica parcial. Configurações de preço e consumo são aplicadas a cada trecho, sem reprecificar o passado.

A nova tela Jornada e resultado abre tanto pelo Início como por Minha semana. Mostra conclusões, confirmações de recebimento, distância, combustível estimado e recebimentos menos combustível. Esse último valor é parcial e não é lucro após todos os custos.

## Conciliação

Dois saldos distintos observados formam um intervalo. São somados uma única vez os lançamentos capturados entre eles; a diferença permanece explicitamente não explicada. Recebimentos não são adicionados de novo aos lançamentos da carteira. Conferência numérica não comprova completude do extrato. Extratos com horário apenas em minutos podem deixar diferenças de fronteira. O saldo da carteira não é renomeado como dívida de aluguel e não recebe um segundo desconto do aluguel.

Dinheiro, Pix Uber e pagamento no app continuam separados, com valores pendentes quando faltam evidências. Conclusão da corrida não prova recebimento. A captura não acessa páginas ocultas nem dados internos da Uber.

## Histórico e planejamento

Referências de horário são calculadas pela mediana de resultados de dias distintos, dentro das últimas oito semanas. São necessários ao menos três dias na mesma faixa de dia da semana e horário de início, jornadas encerradas com ao menos 30 minutos, duas conclusões ou mais, recebimentos confirmados e GPS sem lacunas. Reiniciar várias vezes no mesmo dia não cria três amostras independentes. Sem evidência suficiente, a tela diz que faltam dados.

As taxas usam recebimentos capturados menos combustível e tempo acompanhado, não lucro total ou demanda prevista. O planejamento não muda automaticamente a meta do semáforo e não promete renda.

## Instalação e evidência

Codemagic usa o workflow existente radar-ios-altserver no Mac mini M2. O IPA agora inclui a versão no nome, por exemplo RadarUber-v18-resign.ipa. Confira também version.txt e source-commit.txt. Instalar preservando o aplicativo anterior evita apagar os dados existentes. Os nomes de grupo compartilhado e bundle permanecem os mesmos.

A implementação mantém os custos planejados separados de cobranças observadas para carro alugado, próprio e financiado. Gastos não exibidos na tela, abastecimentos não registrados e quilômetros perdidos não são inventados. Ainda não há CarPlay ou leitura por voz. O IPA de assinatura local não é distribuição comercial para terceiros.
