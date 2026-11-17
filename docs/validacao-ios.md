# Validação manual do Radar iOS

## Estado em 17/11/2026

Aplicativo instalado no iPhone do usuário pelo Windows/AltServer usando assinatura de teste. Versão mais recente validada nesta sessão: build 5, código funcional no commit 720768f2628bbe2dfb95bc96a0995771d2d1314f. O modelo do aparelho e a versão do iOS não foram informados.

As evidências são capturas enviadas na conversa; imagens, endereços e dados de passageiros não são incluídos neste documento.

## Evidências observadas

| Caso | Versão / evidência | Leitura extraída | Banner observado | Cálculo após combustível |
| --- | --- | --- | --- | --- |
| UberX, oferta de R$ 87,43 | Builds 3–4, teste com foto | 18 + 34 min; 15,6 + 36,0 km | Sim, inclusive entrega inicial na Central durante Foco Sono | R$ 72,98; taxa projetada R$ 84,21/h |
| Priority, oferta de R$ 29,78 | Build 5, teste com foto | 6 + 16 min; 3,1 + 11,4 km | Sim, banner sobre a foto | R$ 25,72; taxa projetada R$ 70,15/h |
| UberX em foto de central do carro, oferta de R$ 9,40 | Build 5 | 2 + 4 min; 1,2 + 2,3 km | Sim, banner sobre a foto | R$ 8,42; taxa projetada R$ 84,20/h |

Parâmetros usados: combustível R$ 0,28/km e meta R$ 40/h após combustível. O adicional Priority de R$ 4,01 já estava incluído no preço de R$ 29,78 e não foi somado novamente.

A oferta de R$ 9,40 passou pela exceção abaixo de R$ 25: taxa após combustível acima de 1,5 vez a meta. Essa taxa extrapola somente o tempo e a distância informados no cartão; não é dinheiro recebido por uma hora real de trabalho.

## Diagnóstico da sessão

- Foco Sono reteve uma notificação na Central. Banner posteriormente observado fora do Radar, sobre fotos.
- O usuário encontrou Tela Compartilhada desativada durante a investigação de banners; não atribuir causalidade exclusiva sem teste isolado.
- Na versão 4 houve captura mostrando 21 quadros e fase encerrada. Não foi estabelecido se o encerramento foi manual.
- Capturas posteriores mostraram recepção ativa (72 quadros no build 4; 23 e 123 quadros em capturas do build 5).
- O diagnóstico de última tentativa pode mostrar preço ambíguo depois de uma aprovação porque a captura lê o próprio banner, com preço líquido e taxa horária adicionais. Isso não desfaz a última oferta confirmada. Continua sendo uma limitação de apresentação/diagnóstico.
- O texto transcrito da Priority passava nos testes, mas o fluxo rápido do build 4 podia impedir OCR preciso. No build 5 a etapa precisa pode ser tentada com indícios de oferta, mantendo confirmação de medidas em duas leituras.

## Ainda não comprovado / não implementado

- Leitura e apresentação do alerta durante ofertas novas, ao vivo, dentro do Uber Driver.
- Latência completa desde a aparição da oferta até o banner, inclusive p95/máximo. O campo Último OCR e decisão mede o último quadro processado, que pode ser a própria interface, e não comprova a meta de sete segundos.
- Estabilidade durante um turno, consumo de energia e memória, retomada, outros formatos e taxas de falsos positivos/negativos.
- Custos e tempo reais de espera, trânsito, retorno e reposicionamento automáticos.
- Importação automática de viagens concluídas, saldo de aluguel e benefícios Zarp Super.
- Aprendizado de lucro realizado. O histórico atual usa ofertas observadas e inclui imagens de teste; não equivale a corridas feitas nem a ganhos.
- O uso cotidiano requer renovar a assinatura de teste. Não confundir esta instalação de teste com distribuição definitiva.

## Próxima validação

Usar uma oferta nova em ambiente estacionado e controlado, documentando os valores exibidos, o horário de aparição, o horário do banner e o diagnóstico. Não concluir que o sistema está pronto para decisões reais somente a partir dos testes com fotos. Não alterar limites financeiros para forçar aprovação.
