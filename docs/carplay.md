# CarPlay — preparação na versão 6
Pedido: motorista usa CarPlay e quer decisão visível também na central.

Implementado:
- Pedido de autorização UserNotifications .carPlay junto de .alert/.sound/.badge.
- Categorias distintas RADAR_OFFER e RADAR_TEST com .allowInCarPlay.
- Categorias associadas aos avisos reais e ao teste de banner.
- Diagnóstico de UNNotificationSettings.carPlaySetting: permitido, desativado ou não suportado.
- Aviso claro de que a leitura captura o iPhone, não o display CarPlay.

Limite: isto NÃO constitui um app CarPlay aprovado. O projeto não adiciona entitlement CarPlay sem perfil autorizado. A conta gratuita/AltServer atual não comprova esse suporte. Não prometer avisos visuais no carro nem solicitar adesão paga como solução garantida. A Apple exige enquadramento e aprovação para app CarPlay; precisa avaliar elegibilidade de driving task, perfil e versão do iOS (avisos dessa categoria desde iOS 18.4).

Validação pendente: compilar app/extensão em Xcode, verificar permissão real no aparelho, testar banner com carro parado, verificar oferta real visível na Uber no iPhone enquanto conectado ao CarPlay. Permissão habilitada não comprova entrega. Não há leitura da central nem aceite automático.

Referências primárias:
- https://developer.apple.com/download/files/CarPlay-Developer-Guide.pdf (Notifications)
- https://developer.apple.com/carplay/
- https://developer.apple.com/videos/play/tech-talks/110356/
