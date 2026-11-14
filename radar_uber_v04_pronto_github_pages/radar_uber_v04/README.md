# Radar Uber Inteligente — versão 0.4

Aplicativo independente para acompanhar jornada, recebimentos informados manualmente, quilometragem estimada por GPS e saldo líquido estimado.

## Publicação no GitHub Pages

O repositório inclui o workflow `.github/workflows/deploy.yml`, que publica os arquivos estáticos automaticamente.

1. Crie um repositório novo chamado `radar-uber-inteligente` na conta GitHub destinada ao Radar Uber.
2. Envie **todo o conteúdo desta pasta** para a branch `main`, incluindo a pasta oculta `.github`.
3. No GitHub, abra **Settings → Pages** e selecione **GitHub Actions** como fonte de publicação.
4. Abra **Actions** e aguarde o fluxo **Publicar Radar Uber no GitHub Pages** terminar com sucesso.
5. O endereço será `https://SEU-USUARIO.github.io/radar-uber-inteligente/`.

O site usa caminhos relativos para funcionar no endereço de projeto do GitHub Pages. O HTTPS do GitHub Pages permite solicitar localização no iPhone, após a pessoa autorizar a localização no navegador.

## Executar localmente

Requer Node.js instalado.

```bash
npm install
npm run dev
```

## Observações importantes

- A chave de armazenamento local `radar-uber-v02` foi mantida no código para compatibilidade com versões anteriores no mesmo endereço de site.
- Atenção: os dados salvos no endereço `localhost` não são compartilhados automaticamente com o endereço `github.io`, pois o navegador separa o armazenamento por site. Antes de migrar, exporte o histórico CSV e guarde uma cópia; os parâmetros podem ser conferidos em Configurações.
- O recebimento é lançado manualmente; não existe integração com a API da Uber.
- A quilometragem é estimada pelo GPS e deve ser conferida com o odômetro. O GPS pode pausar quando o navegador fica em segundo plano.
- O saldo exibido desconta aluguel rateado e combustível estimado; não inclui manutenção, lavagem, alimentação, impostos e outras despesas.
