# Versão de teste 7

## Alterações
- Uma oferta mantém o vínculo entre resumo, decisão, horário e estado do aviso.
- Callback atrasado do aviso de A não atualiza o estado da oferta B.
- Agendar no iOS não é confirmação de que um banner foi visto.
- Quadros repetidos não renovam a idade da decisão.
- Oferta continuamente visível não volta a contar ou notificar a cada 45 segundos.
- Depois de 7 segundos a decisão fica como histórico, sem presumir oferta ativa.
- Tela Minha semana: aluguel previsto, meta pessoal, jornada até 6 h/dia, previsão opcional do Passe, meta de 80 viagens.
- Custo do Passe desconhecido permanece desconhecido. Orçamento não confirma compra/validade.
- Ganhos, créditos digitais, dinheiro, combustível e viagens exigem ledger confirmado; ausência de fonte não aparece como zero.
- Configuração local, sem digitar cada oferta.

## Pendências explícitas
A nova tela não conecta a conta Uber e não lê automaticamente o extrato. Não há importador de viagens concluídas em produção. Precisamos de amostras reais das telas de extrato/recibo para definir extração verificável. Até lá nenhuma oferta vira ganho, saldo de aluguel, viagem concluída ou benefício Zarp.
O planejamento não altera automaticamente o filtro enquanto despesas e progresso não estão confirmados.
CarPlay não foi liberado: a instalação retornou carPlaySetting=notSupported.
Voz no carro e leitura da central não foram implementadas.
Compilar no Codemagic workflow radar-ios-altserver, branch main; instalar IPA pelo AltServer sobre a versão anterior. Testes do núcleo não substituem Xcode nem teste no aparelho.

## Fontes ainda necessárias
- Extrato semanal da Uber com retenção do aluguel e lançamentos atuais.
- Recibo de corrida concluída digital e em dinheiro, sem dados de passageiro.
- Preço/condições do Passe contratado; não deduzir pela duração.
