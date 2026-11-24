# Radar iOS 21 — acompanhamento e conciliação

## Cinco entregas

1. **Leitura e avisos:** mantém a economia de OCR da versão 20: descanso depois do processamento, descarte de oferta lenta e cache de tela confirmada. Estado térmico sério reduz a frequência; somente crítico interrompe. Pagamento/viagem tem prioridade sobre detecção genérica de oferta, evitando cortar a tela de conclusão só porque há produto e preço. A disposição espacial das estatísticas associa o número à coluna Viagens. O semáforo continua verde/amarelo/vermelho e o diagnóstico distingue solicitação aceita pelo iOS de banner efetivamente visto.
2. **Ciclo por corrida:** uma oferta isolada não cria receita nem conclusão. O acompanhamento persiste aceite, início, cobrança, conclusão e cancelamento. Botões de UberX e Comfort são reconhecidos. A oferta é referência estimada separada. Reiniciar o aplicativo mantém o registro; uma próxima corrida abre outro, mesmo com preço igual. Perder uma etapa deixa pendência explícita.
3. **Recebimentos:** dinheiro, Pix Uber e pagamento no app permanecem separados. Valor, forma, confirmação e encerramento são exigidos para recebimento. Ver botões de opções não equivale a saber qual foi escolhido. Não pagamento fica fora do recebido. Valores divergentes exigem valor final explícito. Campo de ganhos da viagem não vira valor bruto recolhido do passageiro.
4. **Semana e carteira:** contagem oficial é diferente de conclusões locais posteriores. Estatísticas de dia selecionado não substituem o total semanal só porque o cabeçalho mostra a semana. O número visível é mostrado com “período a confirmar”; falta de leitura não aparece como zero viagens. Lançamento individual só é associado quando há uma única correspondência temporal nos dois sentidos. Recebimento digital não é somado novamente à movimentação da carteira. Diferenças sem explicação continuam identificadas.
5. **Fechamento e histórico:** jornada tem recebimentos por canal, ganhos individuais conferidos, consumo GPS estimado e despesas capturadas no turno. Ganho conferido usa campo explícito ou lançamento individual associado por horário (estimativa a conferir); dinheiro recolhido pode incluir a parte da Uber. Ausência de dados não vira custo zero nem lucro. A cobrança semanal de aluguel fora do turno não é subtraída novamente. O planejamento usa jornadas com cobertura suficiente e ganhos individuais conhecidos; valores brutos recolhidos não viram amostras de rentabilidade.

## Onde conferir

- Início: carteira, acompanhamento da corrida, dinheiro e pagamento pela Uber.
- “Jornada, combustível e conciliação”: etapas, pendências, associação com extrato, fechamento e histórico.
- Semana: observações com data/período e meta de 80.
- Ajustes: diagnóstico da leitura, tempo de processamento e estado do envio de notificações.

## Verificação e limites

- Suíte do núcleo: 162 testes, incluindo 19 cenários novos de fluxo, dinheiro/Pix/app, cancelamento, não pagamento, recuperação de conflito, repetição, semana e conciliação.
- Duas verificações adicionais em macOS executam Vision sobre telas sintéticas: ciclo de pagamento e estatísticas em duas colunas. Exercitam OCR real do Mac; não substituem a observação do iPhone em uso.
- O Radar só acompanha telas realmente entregues pela transmissão. Não consulta a conta Uber por API, não vê um botão oculto, não controla a Uber e não recupera automaticamente telas anteriores à captura. Captura interrompida pode deixar lacunas.
- GPS exige autorização e permanece uma estimativa pelo preço/consumo configurados, não uma medição do tanque. Trechos sem cobertura ficam parciais.
- Exibição/tempo do banner e comportamento térmico precisam de confirmação no iPhone. Um teste de núcleo ou uma compilação não comprova que o banner apareceu em até sete segundos.
- O resultado do turno permanece parcial se faltarem ganhos, despesas, GPS ou etapas. Não há garantia de lucro, previsão de corridas seguintes nem certificação de benefício da locadora.
- CarPlay e voz não foram acrescentados nesta entrega.

Instalar a IPA de número 21 por cima do Radar existente preserva os dados locais. Não apagar o aplicativo para atualizar.
