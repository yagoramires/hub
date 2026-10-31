# Domo (Hub no Grafite) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hub vira "Domo" para quem usa, com a UI no tema Grafite do NeyHub (direção C + Halo), controle da TV completo, ícone `house-wifi`, e o NeyHub sai do Dock com a janela fechada.

**Architecture:** O visual do Hub passa quase todo por `Theme.swift` (`Theme.room/matte/well/tileCorner/accent/font`, `.glow`, `.card`): trocar esses tokens pelo Grafite muda todas as telas de uma vez; depois cada view ajusta o que o token não cobre (power → `GSwitch`, controle da TV). O nome novo é só de exibição: arquivos, assets, ids e pastas continuam "Hub" (o atualizador avulso e o `PluginStore` do NeyHub procuram `Hub-*`); o app avulso mostra "Domo" por `InfoPlist.strings` localizado e o NeyHub por um campo opcional `displayName` no manifest e no catálogo (NeyHubs antigos ignoram o campo e seguem mostrando "Hub", sem quebrar).

**Tech Stack:** Swift 6 / SwiftUI / AppKit, SwiftPM sem Xcode, testes por `--selftest` (preconditions), `--render` (PNG das telas), Lucide (fonte `lucide.ttf`).

**Spec:** `docs/superpowers/specs/2026-10-30-domo-grafite-design.md` (mockup: `docs/design/mockup-domo.html`)

Repos: `hub` = `/Users/yagoramires/Documents/personal-projects/hub`, `neyhub` = `/Users/yagoramires/Documents/personal-projects/neyhub`. Para compilar o Hub contra o NeyKit local: `NEYHUB_PATH=../neyhub`.

## Global Constraints

- Ficam iguais: id `local.hub`, `hubmac://`, `~/Library/Application Support/Hub`, `~/Library/Logs/Hub`, defaults `local.hub`, repo `yagoramires/hub`, `Hub.app`, `Hub-<v>.zip`, `Hub-<v>.neyplugin`, `Updater(name: "Hub", …)`, `name: "Hub"` no `plugin.json` e no `catalog.json`.
- Tudo que o usuário lê diz "Domo" (barra de menus, janelas, Ajustes, Loja, README).
- Cores: `Grafite.bg #121315`, `card #1a1b1f`, `cardBorder #25272c`, `accent #c6ff3d`, raio `Grafite.cardRadius` (10). Ar azul `(0.25, 0.70, 1.00)`, luz âmbar `(1.00, 0.71, 0.20)` / `Theme.lightFill`, tomada verde `(0.25, 0.82, 0.55)`; TV e ração = `Grafite.accent`. Nada vermelho/rosa nas cores do app (cor que o usuário escolhe para uma luz continua).
- Halo (aparelho ligado): gradiente radial do canto superior esquerdo, cor a 13% até 60% do card; borda a 30%; sombra raio ~14 pt, y +8, cor a 38%; ícone com fundo a 18%. Luz no fundo: 18% no popover, 12% na tela grande.
- Só escuro (`.environment(\.colorScheme, .dark)`). Fonte do sistema (Outfit sai). Sem emoji. Ícones só Lucide (lucide-static 1.65.0) + `FoodBowl`.
- macOS 15 mínimo do Hub; NeyHub macOS 14.

## Review Focus

1. NeyHub antigo lendo o `catalog.json` novo (com `displayName`) e o `plugin.json` novo: continua instalando/atualizando `Hub-*.neyplugin` e mostra "Hub". → teste em Task 2.
2. JSON sem `displayName` (todos os outros apps): título = `name`. → teste em Task 2.
3. Luz com cor escolhida vermelha continua vermelha mesmo com "nada vermelho" (só `accent(.tv/.feeder)` e `tvLight` mudam). → teste em Task 4.
4. Plugin sem a pasta de fontes (`missingResources`): ícones caem no SF Symbol e o ícone da barra cai em `house`. → teste em Task 3.
5. Quem já escolheu "Mostrar ícone no Dock" ligado continua com ele ligado depois da mudança de padrão. → teste em Task 1.

---

### Task 1: NeyHub fora do Dock com a janela fechada (repo neyhub)

**Files:**
- Modify: `Sources/NeyHub/HubPresence.swift:9` (padrão de `presence.dock` → `false`), `:6` (`var dock = false`)
- Test: `Sources/NeyHub/SelfTest.swift:31`
- Modify: `README.md` (parágrafo "O NeyHub entra nos itens de login…")

- [ ] **Step 1: Ajustar o teste do padrão e cobrir o valor salvo**

```swift
precondition(HubPresence.load(d) == HubPresence(dock: false, menuBar: true))
d.set(true, forKey: "presence.dock")
precondition(HubPresence.load(d).dock, "quem ligou o Dock continua com ele")
d.removeObject(forKey: "presence.dock")
```

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL na primeira linha.
- [ ] **Step 3:** padrão `false` em `load` e no `var dock`.
- [ ] **Step 4:** `scripts/selftest.sh` → `selftest ok`.
- [ ] **Step 5:** README: fechar a janela tira o ícone do Dock (volta pelo ícone da barra de menus ou abrindo o app); "Mostrar ícone no Dock" no menu do ícone deixa fixo. Commit `feat: NeyHub sai do Dock ao fechar a janela (padrão do ícone no Dock desligado)`.

### Task 2: Nome de exibição dos plugins (repo neyhub)

**Files:**
- Modify: `Sources/NeyKit/Plugin.swift:31-46` (`PluginManifest`), `Sources/NeyHub/Catalog.swift:6-18` (`CatalogEntry`)
- Modify (exibição `name` → `title`): `MainWindow.swift:33-37`, `Views/StoreView.swift:261-318`, `Views/AppDetailView.swift:28-46`, `Views/Sidebar.swift:68-69`, `Views/PermissionsView.swift:9-11`, `PluginHost.swift:110,184` (`offerClose`), `AppDelegate.swift:119` (WhatsNew usa `AppliedUpdate.name`: guardar o título)
- Modify: `catalog.json:7` e `Resources/catalog.json:7` → acrescentar `"displayName": "Domo"`
- Modify: `Resources/icon-src/apps.html` glifo `hub` → `house-wifi`; rodar `scripts/icon.sh` (gera `Resources/icons/hub.png` e `../hub/Resources/AppIcon.icns`)
- Modify: `README.md` (tabela de apps, Permissões, Retorno de login: "Hub" → "Domo"; nota de que o repo segue `yagoramires/hub`)
- Test: `Sources/NeyHub/SelfTest.swift`, `Sources/NeyKit/NeyKitSelfTest.swift`

**Interfaces:**
- Produces: `PluginManifest.displayName: String?`, `PluginManifest.title: String { displayName ?? name }`; `CatalogEntry.displayName: String?`, `CatalogEntry.title: String`. `name` continua a chave de asset/pasta/validação.

- [ ] **Step 1: Testes**

```swift
// NeyKitSelfTest
let m = try! JSONDecoder().decode(PluginManifest.self, from: Data(#"{"id":"local.hub","name":"Hub","displayName":"Domo","version":"1.0.0","contract":1,"hasScreen":true,"permissions":[],"binary":"libHubPlugin.dylib"}"#.utf8))
precondition(m.name == "Hub" && m.title == "Domo")
let old = try! JSONDecoder().decode(PluginManifest.self, from: Data(#"{"id":"local.dose","name":"Dose","version":"1.0.0","contract":1,"hasScreen":true,"permissions":[],"binary":"x.dylib"}"#.utf8))
precondition(old.title == "Dose")
// SelfTest (NeyHub)
let e = Catalog.decode(Data(#"[{"id":"local.hub","name":"Hub","displayName":"Domo","repo":"yagoramires/hub","summary":"s","hasScreen":true}]"#.utf8))!
precondition(e[0].name == "Hub" && e[0].title == "Domo")
precondition(Catalog.decode(Data(#"[{"id":"local.dose","name":"Dose","repo":"yagoramires/dose","summary":"s","hasScreen":true}]"#.utf8))![0].title == "Dose")
precondition(Catalog.load(cache: missing, bundled: bundledCatalog).first { $0.id == "local.hub" }?.title == "Domo")
```

Também: `displayName` com `/` ou vazio é ignorado (título cai no `name`), igual à regra do `name`.

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL (`title` não existe).
- [ ] **Step 3:** campos opcionais (`decodeIfPresent`), `title`, e as views/alerts listados usando `title`. `AppIcon(name:)` recebe o título.
- [ ] **Step 4:** `scripts/selftest.sh` → `selftest ok`; `scripts/build.sh` e abrir: Loja e barra lateral mostram "Domo" com o ícone novo.
- [ ] **Step 5:** Commit `feat: nome de exibição dos plugins (Hub aparece como Domo) e ícone house-wifi`.

### Task 3: Lucide 1.65.0 com `house-wifi` (repo hub)

**Files:**
- Modify: `Resources/Bundle/Fonts/lucide.ttf` (de `https://unpkg.com/lucide-static@1.65.0/font/lucide.ttf`), `Lucide-LICENSE.txt`
- Modify: `Sources/HubCore/Theme.swift` — mapa `Icon.lucide` regenerado de `font/info.json` 1.65.0 (mesmas chaves SF → mesmos nomes Lucide de hoje), mais as chaves novas: `"house.wifi"`, `"mic"`, `"menu"`, `"info"`, `"captions"`, `"skip.back"`, `"skip.forward"`, `"rewind"`, `"fast.forward"`, `"play"`, `"pause"`, `"chevron.up"`/`"chevron.down"` (já existem), `"volume.x"` (`speaker.slash.fill` já existe).
- Create: `Theme.menuBarImage(anyOn: Bool) -> NSImage` em `Theme.swift`: `house-wifi` da fonte desenhado num `NSImage` 18×18 template; sem a fonte, `NSImage(systemSymbolName: anyOn ? "house.fill" : "house")`.
- Modify: `Sources/HubCore/HubApp.swift:163-170` (`updateIcon`) usa `Theme.menuBarImage`.
- Test: `Sources/HubCore/SelfTest.swift`

- [ ] **Step 1: Testes**

```swift
// com a fonte registrada (do .app): todo nome do mapa existe na fonte
for (name, code) in Icon.lucideCodes { precondition(Theme.lucideHasGlyph(code), "sem glifo: \(name)") }
precondition(Icon.lucideCodes["house.wifi"] == 0xe63c)
precondition(Theme.menuBarImage(anyOn: false).isTemplate)
// em missingResources (sem fonte): continua devolvendo imagem
precondition(Theme.menuBarImage(anyOn: true).isTemplate)
```

(`Icon.lucideCodes` = o dicionário hoje `private static let lucide`, passa a `static let lucideCodes`; `Theme.lucideHasGlyph(_ code: UInt32) -> Bool` via `CTFontGetGlyphsForCharacters` na fonte "lucide".)

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL.
- [ ] **Step 3:** trocar fonte e mapa (script Python lendo `info.json`, `encodedCode` `\eXXXX`), implementar as duas funções e o `updateIcon`.
- [ ] **Step 4:** `scripts/selftest.sh` → ok; `build/Hub.app/Contents/MacOS/Hub --render home` e conferir que os ícones aparecem (nenhum quadrado vazio).
- [ ] **Step 5:** Commit `feat: Lucide 1.65.0 (house-wifi) e ícone da barra de menus`.

### Task 4: Tokens Grafite e Halo (repo hub)

**Files:**
- Modify: `Sources/HubCore/Theme.swift`:
  - `tileCorner` → `Grafite.cardRadius`; `room` → `Grafite.bg`; `matte` → `Grafite.card`; `well` → `Color.white.opacity(0.06)`.
  - `font(_:_:)` e `number(_:_:)` → `.system(size:weight:)` (assinaturas iguais; 94 chamadas não mudam). `registerFonts` deixa de exigir `Outfit.ttf`; apagar `Resources/Bundle/Fonts/Outfit.ttf` e `Outfit-OFL.txt`; `outfit(_:weight:)` sai.
  - `accent(.tv)` e `accent(.feeder)` → `Grafite.accent`.
  - `.glow(_:on:radius:opacity:)` vira o Halo: mantém a assinatura, ignora `radius/opacity` dos chamadores e aplica os valores fixos da Global Constraints (sombra + gradiente interno + borda). `card(_:edge:corner:)`: corner padrão `Grafite.cardRadius`, borda padrão `Grafite.cardBorder`.
  - `SoftGlow` (luz no fundo): opacidade final 0.18 no popover (chamadores em `DeviceDetailView:26`, `TVViews:390`, `RoomGlows`) e 0.12 na tela (`ScreenView.RoomGlows`).
- Modify: `TVViews.swift:133` `tvLight` → `Grafite.accent` (o brilho da TV não segue mais a cor do app aberto).
- Modify: `HubApp.swift:107`, `Render.swift:46`, `RootView.swift:38`: fundo `Grafite.bg` + `.environment(\.colorScheme, .dark)`.
- Modify: `ScreenView.swift:157,166` (`corner: 26` → padrão), `TVViews.swift:380,488`, `DeviceDetailView.swift:468` (corners fixos → padrão).
- Test: `Sources/HubCore/SelfTest.swift`

- [ ] **Step 1: Testes**

```swift
precondition(Theme.accent(.tv) == Grafite.accent && Theme.accent(.feeder) == Grafite.accent)
precondition(Theme.tileCorner == Grafite.cardRadius)
// luz vermelha escolhida pelo usuário continua vermelha
var red = HubDevice.sample(kind: .light, status: ["work_mode": "colour", "colour_data_v2": #"{"h":0,"s":1000,"v":1000}"#])
let c = NSColor(Theme.lightFill(red).glow).usingColorSpace(.sRGB)!
precondition(c.redComponent > 0.9 && c.greenComponent < 0.3)
```

(Se não houver `HubDevice.sample`, montar o `HubDevice` como os testes de `mealPlan()` já fazem.)

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `scripts/selftest.sh` → ok; `Hub --render home`, `--render screen`, `--render device:<id>` e comparar com o mockup (fundo grafite, cards raio 10, sem laranja/vermelho, halo discreto).
- [ ] **Step 5:** Commit `feat: tema Grafite do NeyHub com a luz acesa em halo`.

### Task 5: Cards e detalhes no padrão da direção C (repo hub)

**Files:**
- Modify: `DeviceTile.swift:21-71` — ícone em quadrado 30 pt raio 8 com a cor do tipo a 12% (`Theme.accent`), aceso a 18%; o botão redondo de power (`:41-44`) vira `GSwitch(isOn:label:)` ligado ao mesmo comando; layout do tile: linha 1 ícone + switch, linha 2 nome, linha 3 estado.
- Modify: `ACCard.swift:279-297` (`GlowPower`) → `GSwitch`; `SoftChipStyle` selecionado = cor do ar (não branco).
- Modify: `TVViews.swift:149-219` (`TVCard`) power → `GSwitch`, "Entrada" vira `GPill(style: .ghost)` com `Icon("rectangle.connected.to.line.below")`.
- Modify: `DeviceTile.swift:109-188` (`FeederCard`) anel e "Servir" (`GPill`) em `Grafite.accent`; `MealPlan.swift:117,128,209,224` e `DeviceDetailView.swift:420,427` já seguem `accent(.feeder)` (Task 4).
- Modify: `ScreenView.swift:189-200` (`TabStyle`) → abas segmentadas do Dose: fundo `Grafite.card`, borda `Grafite.border`, selecionada `#2a2d33` texto branco.
- Modify: `SettingsView.swift`: botões de ação → `GPill` (primário: Entrar/Gerar QR/Usar/Parear; ghost: Desconectar/Remover/Abrir registro/Cancelar); "Hub \(version)" → "Domo \(version)"; "Sair do Hub" → "Sair do Domo".
- Test: `--render` (visual) + `scripts/selftest.sh` (nada quebra)

- [ ] **Step 1:** `Hub --render home`, `screen`, `screen:racao`, `settings` antes (guardar PNGs).
- [ ] **Step 2:** implementar.
- [ ] **Step 3:** `scripts/selftest.sh` → ok; renders de novo e comparar com o mockup (seções 1–3): switches verdes, nada de botão redondo de power, ração verde.
- [ ] **Step 4:** Commit `feat: cards, ração, abas e ajustes no padrão do NeyHub`.

### Task 6: Controle da TV completo (repo hub)

**Files:**
- Modify: `AndroidTV.swift:433-437` `ATVRemote.Key`: acrescentar `menu = 82, search = 84, mediaPrevious = 88, mediaRewind = 89, mediaFastForward = 90, mediaNext = 87, channelUp = 166, channelDown = 167, info = 165, captions = 175, assist = 219`.
- Modify: `TVViews.swift:350-540` (`TVRemoteView`) — layout de cima para baixo: grade de apps; volume; linha `power, input, assist, menu, settings`; Setas|Touchpad; `VOL +/−` | direcional + OK | `CH ▲/▼`; linha `back, home, info, captions, mute`; linha `mediaPrevious, mediaRewind, playPause (GPill primário), mediaFastForward, mediaNext`. Botões com `TVKey` (raio 8, borda `Grafite.cardBorder`).
- Test: `Sources/HubCore/SelfTest.swift`

- [ ] **Step 1: Teste**

```swift
precondition(ATVRemote.Key.channelUp.rawValue == 166 && ATVRemote.Key.channelDown.rawValue == 167)
precondition(ATVRemote.Key.info.rawValue == 165 && ATVRemote.Key.captions.rawValue == 175 && ATVRemote.Key.assist.rawValue == 219)
precondition(ATVRemote.Key.mediaPrevious.rawValue == 88 && ATVRemote.Key.mediaNext.rawValue == 87)
precondition(ATVRemote.Key.mediaRewind.rawValue == 89 && ATVRemote.Key.mediaFastForward.rawValue == 90 && ATVRemote.Key.menu.rawValue == 82)
```

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL.
- [ ] **Step 3:** enum + layout.
- [ ] **Step 4:** `scripts/selftest.sh` → ok; `Hub --render screen:tv` bate com o mockup. Na TV de verdade: cada botão novo faz algo; o que não fizer nada sai do layout (anotar no CHANGELOG).
- [ ] **Step 5:** Commit `feat: controle da TV com canal, mídia, info, legenda, menu e assistente`.

### Task 7: Nome "Domo" no app avulso e no plugin (repo hub)

**Files:**
- Modify: `Resources/Info.plist` → `LSHasLocalizedDisplayName = true` (CFBundleName/DisplayName continuam "Hub" no plist).
- Create: `Resources/pt-BR.lproj/InfoPlist.strings` e `Resources/en.lproj/InfoPlist.strings` com `CFBundleDisplayName = "Domo"; CFBundleName = "Domo";`; `scripts/build.sh` copia os `.lproj` para `Contents/Resources`.
- Modify: `Resources/plugin.json` → `"displayName": "Domo"` (name continua "Hub").
- Modify: textos visíveis "Hub" → "Domo": `HubApp.swift:135,144,164`, `SettingsView.swift:50,57,58`, `TVViews.swift:712`, `Hub/AppDelegate.swift:21` (`leaveForHub(name:)`), `:39` (`WhatsNew.show(name:)`), `:82` ("Sair do Domo"), `HubStore.swift:407` (`clientName: "Domo no Mac"`). Não mudam: `Updater(name: "Hub", …)`, caminhos de pasta/log, `--render`/`--dump` (uso de dev).
- Modify: `README.md` (título, textos, `docs/print.png` novo pelo `--render`), `CHANGELOG.md` (versão nova: nome Domo, visual do NeyHub, controle da TV, ícone).
- Test: `Sources/HubCore/SelfTest.swift` + verificação do bundle

- [ ] **Step 1: Teste**

```swift
let plugin = try! JSONDecoder().decode([String: AnyCodable].self, …) // ler Resources/plugin.json do bundle
precondition(plugin["name"] == "Hub" && plugin["displayName"] == "Domo")
```

(Use `JSONSerialization` sobre `Bundle.main.url(forResource: "plugin", withExtension: "json")` se o build copiar; senão sobre o arquivo do repo no `selftest.sh`.)

- [ ] **Step 2:** `scripts/selftest.sh` → FAIL.
- [ ] **Step 3:** implementar.
- [ ] **Step 4:** `scripts/selftest.sh` → ok; `scripts/build.sh` e `mdls -name kMDItemDisplayName build/Hub.app` → `"Domo"`; abrir o app: menu do app e barra de menus dizem Domo; `grep -rn '"[^"]*\bHub\b' Sources` só sobra o que a lista acima deixa.
- [ ] **Step 5:** Commit `feat: Hub passa a se chamar Domo (só o nome que aparece; ids e arquivos iguais)`.
