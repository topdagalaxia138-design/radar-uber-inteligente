# Radar Uber Inteligente — aplicativo nativo iOS (base inicial)

Esta pasta inicia o app iOS nativo separado do painel web V04.

## Arquitetura

1. O motorista inicia explicitamente a transmissão de tela da Apple pelo botão ReplayKit.
2. A extensão Broadcast recebe quadros de vídeo enquanto a transmissão está ativa.
3. O Vision executa OCR localmente no iPhone.
4. O parser tenta identificar valor, tempo e distância de embarque e viagem.
5. O motor calcula combustível e lucro estimado e decide.
6. A extensão envia uma notificação local para uma oferta aprovada. Ofertas reprovadas ficam silenciosas.

A tela não é enviada para um servidor. A transmissão pode ser interrompida pelo motorista ou pelo iOS.

## Gerar projeto Xcode

O projeto usa XcodeGen. Em um Mac com Xcode e XcodeGen instalados:

```sh
cd radar-ios
xcodegen generate
open RadarUber.xcodeproj
```

Depois:
- Configure um Apple Developer Team para os dois targets.
- Confirme os Bundle IDs se necessário.
- Ative App Groups nos dois targets e crie `group.br.com.radaruber.app`.
- Verifique a extensão Broadcast Upload no target RadarBroadcast.
- Instale em um iPhone real e autorize notificações.
- Inicie a transmissão e selecione Radar Leitura.

## Estado e limitações desta base

- É uma base técnica inicial, ainda não é um app pronto para uso em corridas reais.
- A extração OCR depende do layout real das ofertas Uber no aparelho. Precisamos validar com capturas de teste autorizadas e ajustar o parser.
- O parser é conservador: se não separar com confiança embarque e viagem, não recomenda aceitar.
- O valor de custo de combustível está inicialmente alinhado ao parâmetro histórico de R$ 0,28/km. A meta líquida por hora ainda não está configurada; por isso o motor não aprova ofertas até receber uma meta válida.
- Ainda não há leitura de destino, trânsito, demanda, retorno provável ou aprendizagem com corridas concluídas.
- A meta de resposta é até 7 segundos, mas latência, entrega de notificações e compatibilidade precisam ser medidas em iPhone real.
- A Apple exige autorização explícita para iniciar captura/transmissão e autorização separada para notificações.
- O build, assinatura e instalação precisam ser feitos em macOS/Xcode. Este repositório pode ser preparado no Windows, mas Windows sozinho não compila nem assina um app iOS.

## Referências técnicas

- ReplayKit: https://developer.apple.com/documentation/replaykit
- Vision OCR: https://developer.apple.com/documentation/vision/recognizing-text-in-images
- UserNotifications: https://developer.apple.com/documentation/usernotifications

## Continuidade em 16/11/2026

V04 preservado. OCR limitado a dois quadros por segundo; deduplicação por valores estruturados com expiração; propostas ambíguas e decisões atrasadas ficam silenciosas. Abaixo do mínimo exige 1,5 vezes a meta horária. O núcleo aceita custo/tempo de reposicionamento, mas ainda não há fonte automática desses dados. Não confundir parâmetros com integração operacional.

O pacote Swift testa parser, deduplicação, decisão e contabilidade. CI executa `swift test`, compila simulador e iPhone ARM64 sem assinatura e guarda o produto. O artefato sem assinatura NÃO instala no iPhone e não é um IPA distribuível.

A contabilidade separa cartão/PIX Uber de dinheiro/maquininha, evita duplicação por ID e desconta aluguel uma única vez. É núcleo sem importador de transações nem tela de finanças; ofertas detectadas não são lançadas como ganhos. A referência de 80 corridas vem do histórico do motorista, não representa confirmação atual dos benefícios Zarp Super. Sem contrato/regras atuais, não inventamos descontos.

Ainda pendentes: OCR validado com ofertas reais, destino, fonte de reposicionamento/ociosidade, integração financeira, aprendizagem a partir de resultados confirmados e benefícios Zarp. Não há promessa de captura invisível: ReplayKit exige início explícito pelo usuário em cada sessão.

### Instalação a partir do Windows

A compilação ocorre em runner macOS do GitHub Actions. Para distribuição via TestFlight, são indispensáveis Apple Developer Program ativo, cadastro dos dois identificadores e App Group, certificados/perfis e acesso ao App Store Connect. Não colocar certificados, senhas ou chaves no código nem no chat. Sem essa configuração, só é possível gerar/testar builds não assinados aqui.

### Validação física pendente

Após assinatura e instalação: autorizar notificações, iniciar Radar Leitura e abrir ofertas em ambiente de teste com veículo parado. Registrar instante em que a oferta aparece e instante do alerta, taxa de leitura incorreta, ofertas perdidas e consumo/memória da extensão. Exigir ausência de alertas para ofertas rejeitadas e dados incompletos. Medir p50/p95/máximo fim a fim; `lastProcessingSeconds` mede apenas OCR + decisão e não comprova a meta de sete segundos.

## Histórico adaptativo local

O Broadcast agora mantém até 500 observações legíveis por sete dias, sem guardar texto de tela, endereços ou imagens. Após 20 observações, o percentil 60 das taxas após combustível pode elevar o filtro até 25% acima da meta configurada. Nunca reduz a meta. Uma oferta repetida não gera outra observação dentro da janela de deduplicação. O filtro da oferta atual usa somente observações anteriores.

Esse aprendizado usa ofertas observadas: não identifica corridas aceitas, não registra ganhos e não aprende tempos reais de viagens. Esses resultados continuam dependendo de uma fonte de viagens concluídas. A tela informa quantidade observada e filtro aplicado. Falhas de OCR são registradas no diagnóstico sem gerar alertas para o motorista.

## Separação semanal do núcleo financeiro

As consultas agora separam a semana operacional, de segunda-feira às 04:00 até a segunda seguinte às 04:00 (fim exclusivo), no fuso America/Sao_Paulo. O histórico completo é preservado, inclusive para consultas de semanas anteriores com `referenceDate`. Esse corte operacional não confirma a elegibilidade do contrato Zarp nem concede descontos. Registros antigos sem o novo campo de referência continuam decodificáveis.

Ainda não existe importador conectado de viagens/pagamentos. Portanto, o núcleo financeiro testado não deve ser apresentado como sincronização automática com a Uber.

## Experimento de instalação pelo Windows (ainda não validado no aparelho)

CI agora empacota `RadarUber-resign.ipa` com assinatura ad hoc local e entitlements preservados, destinado a reassinatura pelo instalador. A assinatura ad hoc NÃO autoriza executar no iPhone. O pacote ainda precisa ser assinado para o aparelho por uma ferramenta como AltStore Classic/AltServer. A extensão RadarBroadcast deve ser mantida na instalação.

O app resolve o grupo compartilhado a partir dos metadados ALTAppGroups que o AltStore ajusta durante a reassinatura, e descobre o identificador efetivo da extensão embutida. Isso corrige IDs fixos incompatíveis com reassinatura; NÃO comprova que a conta gratuita consegue provisionar o conjunto no iPhone do usuário. Sem acesso ao grupo, o app mostra erro e a extensão encerra, sem gerar recomendações com parâmetros ausentes.

Referências consultadas: documentação oficial https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows e https://faq.altstore.io/altstore-classic/your-altstore ; implementação de referência https://github.com/altstoreio/AltStore/blob/develop/AltServer/Devices/ALTDeviceManager%2BInstallation.swift (registro de grupos e metadados de assinatura). Com conta gratuita, as instalações expiram em sete dias e precisam ser renovadas. A compatibilidade de captura, grupo e notificações precisa ser testada fisicamente. Não usar este experimento como prova de funcionamento em corridas.
