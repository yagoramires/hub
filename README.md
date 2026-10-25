# Hub

Aparelhos da casa pela barra de menus do macOS: ar-condicionado, TV, luzes, tomadas e alimentador, de Smart Life, Tuya Smart, Positivo e SmartThings.

![Hub](docs/print.png)

O print usa aparelhos de exemplo.

[Baixar a última versão](https://github.com/yagoramires/hub/releases/latest) · [Reportar problema](https://github.com/yagoramires/hub/issues/new)

## Instalar

1. Baixe o `Hub-x.y.z.dmg` (ou o `.zip`) na [página de releases](https://github.com/yagoramires/hub/releases/latest) e arraste o **Hub.app** pra pasta **Aplicativos**.
2. Abra o Hub. Como ele não é assinado com um certificado pago da Apple, na primeira vez o macOS avisa que não conseguiu verificar o desenvolvedor. Vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o fim e clique em **Abrir Mesmo Assim**. Pelo Terminal também resolve: `xattr -dr com.apple.quarantine /Applications/Hub.app`

Requer macOS 15 ou mais novo. Roda nativo em Apple Silicon e Intel. Também dá pra compilar do código (veja **Build local**).

### Pelo NeyHub

Quem usa o [NeyHub](https://github.com/yagoramires/neyhub) pode instalar o Hub pela Loja dele (o `Hub-x.y.z.neyplugin` do release). Aí o Hub roda dentro do NeyHub, com as mesmas contas, TVs pareadas e ajustes do avulso: o ícone e o popover da barra são os mesmos, a **tela do Hub** aparece na janela do NeyHub, o NeyHub cuida do login, das atualizações e de mostrar ou esconder o ícone, e os ajustes não têm **Abrir ao iniciar a sessão**, **Janela / Barra de menus**, **Sair** nem a linha **Atualização pronta**. Feche o Hub avulso antes: se o NeyHub já roda o Hub, o avulso avisa e fecha.

O NeyHub roda no macOS 14, mas o Hub precisa do 15: num Mac com macOS 14 o card do Hub mostra **Precisa do macOS 15** e ele não carrega.

O retorno do login do SmartThings (`hubmac://`) vai para um app só. Com o Hub instalado no NeyHub, entre pela Samsung de dentro do NeyHub: é ele quem recebe o retorno e entrega ao Hub (o avulso, aberto ao mesmo tempo, sai sozinho). Se o retorno não for de um login em andamento, o NeyHub avisa em vez de perder a URL em silêncio.

### Desinstalar

1. Nos Ajustes, desligue **Abrir ao iniciar a sessão** e clique em **Sair do Hub**.
2. Apague o **Hub.app** de Aplicativos. Pelo NeyHub, é só desinstalar no card do Hub (para os timers, a busca e as conexões com as TVs na hora).
3. Os dados continuam em `~/Library/Application Support/Hub/`. Pra apagar tudo (sem volta, inclusive os tokens e o pareamento das TVs): `rm -rf ~/Library/Application\ Support/Hub ~/Library/Logs/Hub; defaults delete local.hub`

## Permissões

- **Rede local**: o Hub conversa direto com a sua TV na rede de casa para ligar, mudar o volume e abrir apps. O macOS pede a permissão na primeira vez (dentro do NeyHub, a permissão é do NeyHub).
- Não pede Acessibilidade, Gravação de Tela nem Câmera.
- Os tokens das contas ficam só no seu Mac, em `~/Library/Application Support/Hub/credentials.json` (arquivo legível só pelo seu usuário), e não no Chaveiro. Versões antigas guardavam no Chaveiro: só o avulso traz de lá, uma vez; dentro do NeyHub o Hub nunca lê o Chaveiro.

### Privacidade

Tokens, pareamento das TVs e log ficam todos locais, os mesmos no avulso e no NeyHub. Além das nuvens (Tuya e SmartThings) e da TV na rede de casa, a única conexão é a consulta à API pública do GitHub (`api.github.com`) pra saber se tem versão nova do Hub, e o download dela.

| O quê | Onde |
| --- | --- |
| Credenciais | `~/Library/Application Support/Hub/credentials.json` (arquivo 0600, pasta 0700) |
| Certificado do pareamento com as TVs | `~/Library/Application Support/Hub/androidtv.p12` (0600) |
| Apps da TV e touchpad ou setas | `UserDefaults` (domínio `local.hub`) |
| Log | `~/Library/Logs/Hub/hub.log` |

## Como usar

Clique no ícone do Hub na barra de menus. Sem contas conectadas, o Hub mostra **Conecte suas contas**; o botão **Conectar** abre os Ajustes.

- **Smart Life, Tuya Smart e Positivo** (luzes, tomadas, alimentador, controles): em Ajustes, escolha o app, cole o código de usuário (no app do celular: **Eu → Configurações → Conta e segurança → Código de usuário**), clique em **Gerar QR** e escaneie com o leitor do app. Cada app vira uma conta separada.
- **SmartThings** (ar-condicionado): **Entrar com a Samsung** abre o login no navegador; depois de autorizar, volte ao Hub. Também aceita um token de `account.smartthings.com/tokens`, que vale só 24 h e serve pra testar.
- **TV Google TV / Android TV**: o Hub procura TVs na rede e pareia com o código de 6 caracteres que aparece na TV, uma vez só. Depois controla tudo localmente, sem nuvem: liga e desliga, volume, apps, controle completo (touchpad ou setas, teclas e busca). Abrir apps e digitar texto pelo Hub usam o ADB, que é opcional e precisa da depuração pela rede ligada na TV.

Na tela principal:

- **Ar-condicionado**: arraste na régua para escolher a temperatura (a régua vai do frio ao quente), modos e ventilação ficam embaixo.
- **TV**: cartão com os apps, o volume e voltar, início e tocar/pausar.
- **Luzes e tomadas**: o círculo da direita liga e desliga; clicar no resto abre o menu com as opções do aparelho (brilho, temperatura de cor, consumo e outras).
- **Alimentador**: o anel conta o tempo até a próxima refeição, **Servir** solta uma porção e clicar no resto abre as refeições programadas (listar, criar, editar, ativar e apagar) e os ajustes.
- Aparelhos sem conexão aparecem apagados com o aviso "Sem conexão".

Em Ajustes também ficam **Abrir ao iniciar a sessão**, **Janela** e **Barra de menus**, **Abrir registro** e **Sair do Hub** (no avulso).

### Tela do Hub

No modo **Janela** do avulso, ou na janela do NeyHub, o Hub ganha uma tela inteira com o mesmo tema do popover (fonte arredondada, cartões grandes e o brilho de cada aparelho ligado no fundo). No topo, a saudação com o resumo da casa, as abas **Casa**, **TV** e **Ração**, ⟳ e ⚙︎.

- **Casa**: o ar-condicionado à esquerda; a TV, os aparelhos (em duas colunas) e a ração no meio; à direita, o detalhe do aparelho escolhido, sempre aberto (o mesmo do popover: brilho, tom e cores da luz, porções e ajustes do alimentador…). Clique num aparelho para ver o detalhe ali; sem nada escolhido, aparece a dica. Numa janela mais estreita o ar, a TV e os aparelhos ficam numa coluna só, com o detalhe ao lado; bem estreita, tudo numa coluna.
- **TV**: o controle completo (apps, touchpad ou setas, teclas, volume e busca). Clicar no cartão da TV na Casa também abre esta aba.
- **Ração**: o alimentador e as refeições programadas.

## Atalhos

O Hub não tem atalho global. No controle completo da TV, as setas, o Enter e o Delete do teclado também comandam a TV.

| Atalho | O que faz |
| --- | --- |
| `⌘,` | No modo **Janela**: abre os Ajustes |
| `⌘Q` | No modo **Janela**: fecha o Hub |

Nos campos de texto valem os atalhos de edição de sempre (`⌘Z`, `⇧⌘Z`, `⌘X`, `⌘C`, `⌘V`, `⌘A`), pelo menu **Editar**.

## Modos de exibição

A interface é escura ou clara conforme o macOS, e cada aparelho acende na sua cor. As animações do ar-condicionado param com "Reduzir movimento" ligado em Acessibilidade.

Nos Ajustes do avulso você escolhe onde o Hub aparece, e a troca vale na hora:

- **Barra de menus** (o padrão, como na 0.1.0): só o ícone com o popover.
- **Janela**: ícone no Dock e a tela do Hub. Clicar no ícone do Dock traz a janela de volta; o menu **Hub → Ajustes…** (`⌘,`) abre os ajustes.
- **Os dois**.

Desligar os dois não vale: o outro volta a ligar. Dentro do NeyHub o modo é escolhido no card do Hub, na Loja.

## Atualizações

Desde a 0.2.0, o Hub se atualiza: confere 5 s depois de abrir e a cada 6 h se tem versão nova, baixa sozinho e só troca o app quando você fecha o Hub (ou clica em **Reiniciar agora**, nos Ajustes): nunca reinicia sozinho no meio do uso. Na próxima abertura, mostra uma vez a janela **Novidades** com o que mudou. A versão baixada só é instalada se tiver sido assinada pelo mesmo certificado do app em uso. Dentro do NeyHub, quem atualiza é o NeyHub.

Quem está na 0.1.0 precisa instalar a 0.2.0 uma vez à mão (ela ainda não tinha atualização automática). Os dados ficam onde estão.

## Build local

Precisa só das Command Line Tools (`xcode-select --install`), não do Xcode.

```sh
git clone https://github.com/yagoramires/hub.git && cd hub
scripts/setup-signing.sh   # uma vez: certificado local de assinatura
scripts/build.sh --run     # compila, assina e abre build/Hub.app
scripts/selftest.sh        # testes; imprime "selftest ok"
```

O NeyKit (`@ViewState`, contrato de plugin) e o NeyKitApp (atualização, novidades) vêm do checkout do
[neyhub](https://github.com/yagoramires/neyhub) ao lado (`../neyhub`); para outro lugar, defina `NEYHUB_PATH`.

Sem o certificado "Aero Local Signing" o build falha: o NeyHub só carrega plugins e as atualizações só entram com ela.

Modo terminal, para depurar sem abrir a interface (usa os mesmos tokens do app):

| Comando | O que faz |
| --- | --- |
| `Hub --dump` | Lista aparelhos, pontos de dados e valores |
| `Hub --tuya <id> <código> <valor JSON>` | Manda um comando Tuya |
| `Hub --st <id> <capability> <comando> [argumentos JSON]` | Manda um comando SmartThings |
| `Hub --import-st-app <saída.json>` | Guarda o app OAuth criado pelo SmartThings CLI |
| `Hub --atv-scan` | Procura TVs Google TV / Android TV na rede |
| `Hub --render <tela> <arquivo.png> [light\|dark]` | Desenha uma tela com aparelhos de exemplo, sem abrir nada na tela, sem rede e sem as credenciais: `home`, `device:ID`, `settings`, `settings:hosted` (os ajustes dentro do NeyHub), `screen` (a tela do Hub), `screen:tv`, `screen:racao`, `screen:narrow` e `screen:empty` |
| `Hub --selftest` | Roda as verificações internas e imprime `selftest ok` (rode com `scripts/selftest.sh`; usa uma pasta temporária e um Chaveiro falso, nunca as credenciais de verdade) |

O binário fica em `build/Hub.app/Contents/MacOS/Hub`.

> O SDK atual transformou `@State` num macro cujo plugin só vem com o Xcode; as telas usam o `@ViewState` do NeyKit, que faz a mesma coisa.

### Como funciona

O miolo fica em `Sources/HubCore` e é o mesmo no app avulso e no plugin do NeyHub:

| Arquivo | Papel |
| --- | --- |
| `HubApp.swift` | Ícone e popover da barra, modos de exibição, ajustes, retorno do login (`handleURL`, só `hubmac://` com o `state` certo) e `stop()` (desinstalar no NeyHub: para os timers de 10 s e 12 h, a busca e as conexões com as TVs, o monitor de cliques, as janelas e o ícone). Recebe os `UserDefaults`, se está hospedado, a versão e a pasta de recursos. |
| `HubStore.swift` | Junta as nuvens e as TVs numa lista só e manda os comandos. |
| `TuyaClient.swift`, `SmartThingsClient.swift`, `AndroidTV.swift` | Cada nuvem e o controle da TV pela rede. |
| `ScreenView.swift`, `RootView.swift`, `SettingsView.swift` e os cartões | A tela do Hub, o popover e os ajustes, no tema do próprio Hub (`Theme.swift`). |
| `SelfTest.swift`, `Render.swift` | `--selftest` e `--render`. |

Fontes e logos ficam em `Resources/Bundle/`: o build copia para o `.app` e o release também para o `.neyplugin`, e o Hub lê da pasta que recebe (nunca do `Bundle.main` dentro do NeyHub).

As cascas: `Sources/Hub` (app avulso: confere se o NeyHub já roda o Hub, atualização e novidades do NeyKitApp, o retorno `hubmac://` e o modo terminal) e `Sources/HubPlugin` (o `libHubPlugin.dylib` que o NeyHub carrega; linka só o NeyKit). O `Info.plist` declara `NeyHubAware = true` porque o avulso chama `HubCheck.leaveForHub` ao abrir; o `plugin.json` declara `minMacOS` 15.0.

### Publicar uma versão

1. Suba a versão em `Resources/Info.plist` (`CFBundleShortVersionString` e `CFBundleVersion`) e escreva a seção `## [x.y.z]` do `CHANGELOG.md` (vira a nota do release e a janela Novidades).
2. `scripts/release.sh` gera em `dist/` o `Hub-x.y.z.dmg`, o `Hub-x.y.z.zip` (o app, que a atualização automática baixa) e o `Hub-x.y.z.neyplugin` (o plugin do NeyHub). Só empacota.
3. Commit, push e `NEYHUB_CONFIRM_PUBLISH=yes scripts/release.sh --publish` para criar o release.

O release **precisa ser assinado com o mesmo certificado** das versões anteriores, senão os apps já instalados recusam a atualização automática.

## Patch notes

Veja o [CHANGELOG](CHANGELOG.md).

## Licença

[MIT](LICENSE) (os logos de terceiros em `Resources/Bundle/AppLogos` ficam de fora; veja o `LICENSE`)
