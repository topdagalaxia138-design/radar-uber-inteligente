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
