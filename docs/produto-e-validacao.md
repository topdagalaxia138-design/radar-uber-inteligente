# Radar: decisões e fechamento financeiro

Pesquisa e implementação inicial: 24/11/2026. Fontes são descrições dos fornecedores, não testes independentes nem prova de aumento de renda.

## Referências estudadas

| Referência | Aplicação no Radar | Limite |
|---|---|---|
| [Rota Pro](https://rotapro.app/ajuda/semaforo/) | Critérios claros, faixas e diagnóstico de avisos | No iPhone a apresentação depende do iOS |
| [GigU](https://gigu.app/br) | Análise orientada a metas e custo configurado | Não presumir lucro ou recebimento pela oferta |
| [DSW](https://drivesocial.io/dsw/) | Métricas por km/minuto e demanda | Mapa coletivo precisa de cobertura real; marketing de IA não prova precisão |
| [Corridex](https://corridex.app/) | Mínimo e ideal, faixa intermediária, leitura local | Mesmo custo e retorno precisam ser identificados como estimativa |
| [CPMA](https://cpmacontrole.com.br/) | Veículo alugado, próprio e financiado | Custos contratados não podem ser deduzidos do saldo da carteira |
| [Drivvo](https://www.drivvo.com/pt-BR/personal-use/) | Abastecimento separado de consumo; despesas e manutenção | Abastecer não significa consumir todo o valor naquele turno |
| [Gridwise](https://help.gridwise.io/hc/en-us/articles/24112893729815-How-Insights-are-Measured) | Medianas, janela recente e comparação por horário | Comunidade não representa todos os motoristas; não inventar demanda local |
| [Solo](https://www.worksolo.com/faq) | Planejamento por horário e previsão baseada em histórico | Não transferir promessas de garantia para o Radar |
| [DriveLens](https://drivelens.app/support) | Comparação entre previsto e realizado, histórico pessoal | Recursos Android não equivalem a recursos iOS |

## Contrato do produto

Oferta é uma estimativa, não uma corrida aceita. Conclusão é um evento separado do pagamento. Dinheiro recebido é entrada no caixa do motorista, não crédito automático na Uber. Pix pelo QR da Uber pertence ao canal digital. Crédito digital também não prova sozinho o abatimento final da carteira: taxas, ajustes e outros lançamentos interferem. Aluguel observado não é cobrado novamente sobre o saldo da carteira.

Cada valor deve indicar origem, período e condição: oficial observado, evento capturado, estimativa ou pendência. Uma etapa perdida não pode ser preenchida com dados inventados. Resumos oficiais substituem referências anteriores, sem acumular o mesmo valor duas vezes.

## Implementado neste incremento (versão 17)

- Verde na meta, amarelo entre 90% e 100% da meta, vermelho abaixo de 90% ou margem após combustível não positiva. Sem penalidade por valor baixo isoladamente. Faixas consideram busca e viagem; ainda não representam lucro após todos os custos.
- Início observado abre acompanhamento de viagem. Conclusão explícita é registrada uma única vez; cancelamento não conta. Recebimento continua exigindo valor, forma e confirmação mais encerramento. A etiqueta UberX em uma tela de cobrança não deve bloquear o leitor de pagamentos como se fosse oferta.
- Meta de 80 combina a última contagem oficial com conclusões posteriores capturadas. Resultado é provisório, pois a própria Uber pode atualizar com atraso. Sem base oficial, somente contagem parcial; não presumir zero viagens anteriores.
- Estatísticas de um dia selecionado no gráfico não podem substituir a semana apenas porque o cabeçalho conserva as datas da semana.
- Planejamento distingue alugado, próprio quitado e financiado; orçamento próprio não desconta aluguel. Valores existentes são preservados. Novo padrão de aluguel é R$832,22; não é uma cobrança oficial.
- Mantidas proteções térmicas da versão 16. Não há prova de estabilidade no aparelho nem medição de temperatura em graus.

## Pendente para completar a proposta

1. Validar OCR com sequências reais de início, encerramento, dinheiro, Pix Uber, pagamento no app e não pagamento. Fixtures textuais não validam captura visual.
2. Identificar ajustes, recebimentos e despesas na conciliação por evento. Calcular divergência entre carteira inicial, movimentos e carteira final. Não classificar automaticamente a diferença como dinheiro.
3. Acompanhar km reais e trechos vazios com permissão de localização; separar previsão de oferta, consumo estimado do turno e abastecimentos. Sem esses dados, não mostrar lucro completo.
4. Histórico de turnos: tempo online, espera, ganhos confirmados e custos; medir ganho por hora online, não só equivalente horário da oferta.
5. Planejamento com mediana de turnos comparáveis e amostra visível. Sem amostra suficiente, dizer que faltam dados. Não presumir futura corrida no destino.
6. Voz e CarPlay dependem de implementação e compatibilidade específicas; não estão habilitados por este incremento.
7. Disponibilização comercial, instalação e atualização para terceiros exigem distribuição apropriada; o IPA de teste com Apple ID gratuito não é o produto comercial pronto.

## Critérios de validação

- Medir tempo desde a chegada da oferta até a solicitação de notificação e registrar descartes e falhas; observar separadamente o banner no dispositivo.
- Testar turno completo com Uber e outros apps, incluindo aquecimento, bloqueio de tela, pausa da transmissão e reinício. Interromper capture em estado térmico sério/crítico e mostrar motivo.
- Repetir telas, reiniciar o app e mudar a semana sem duplicar corridas ou dinheiro. Comparar centavos e contagens com os registros oficiais e recebimentos efetivos.
- Testar carro alugado, próprio e financiado. Orçamento não altera o saldo oficial nem implica despesa efetivamente paga.
- Publicar limitações e resultados medidos antes de anunciar automação completa ou superioridade de rendimento.
