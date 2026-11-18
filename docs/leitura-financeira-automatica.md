# Leitura financeira automática — versão 8

## Operação
Com Radar Leitura ativo, abrir telas financeiras reconhecidas na Uber dispara duas leituras OCR precisas do mesmo quadro. Valores estruturados são salvos no App Group local. Não se solicita envio semanal de extratos ou cadastro de cada viagem. Nenhuma imagem ou texto OCR completo é persistido ou enviado a um servidor.

## Padrões iniciais
- Saldo da Carteira ou cabeçalho Saldo • R$...
- Saldo detalhado com linhas UberX/Priority/Wait & Save e datas visíveis.
- Débito/crédito Taxa relativa a veículos - Retenção Localiza.
- Cobrança por assinatura / Pagamento do Passe para Motoristas.
- Ajuste de ganhos do Passe, separado de cobrança.
- Ganhos e contagem de viagens com contexto explícito da semana atual.
- Preço do Passe quando explicitamente rotulado; não é contabilizado como compra.

O parser exige marcador visível relacionado à Uber, rejeita a tela do próprio Radar, notificações e cartões de oferta. ReplayKit não informa a identidade do aplicativo: isto é reconhecimento do conteúdo, não prova de origem/autenticidade.
Valores e movimentos precisam concordar nas duas leituras. Datas não visíveis não são inferidas. Cabeçalhos de período ambíguos e valores conflitantes não são importados. A leitura parcial pode deixar campos pendentes.

## Regras contra falsas contas
- Saldo Uber não é automaticamente saldo do aluguel.
- Valores das linhas de viagem em dinheiro neste extrato são movimentos do saldo, não o dinheiro recebido.
- Lançamentos de viagens não contam como novas viagens concluídas nem ganhos; a contagem semanal vem de resumo explicitamente semanal.
- Reabrir/rolar a tela atualiza observações e deduplica movimentos por data/hora/tipo/valor/produto; não soma o mesmo total várias vezes.
- Cobranças do Passe capturadas e débitos/créditos Localiza são somas PARCIAIS dos lançamentos visíveis, não extrato completo.
- Preços observados não são despesas presumidas.
- Não conecta API Uber, não lê tela da central CarPlay, não altera automaticamente o filtro após combustível e não garante leitura de qualquer layout.

## Validação
Fixtures sintéticas reproduzem estrutura e rótulos, sem publicar registros financeiros do usuário. Validar padrão OCR no aparelho com as telas reais; testes de texto não provam leitura perfeita de pixels. Testar semana anterior, sinal negativo, linhas parciais, duplicações, crédito de aluguel, cobrança/ajuste do Passe e retorno ao Radar.
