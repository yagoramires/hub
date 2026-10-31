# Domo: Hub renomeado e no padrão Grafite do NeyHub

Data: 30/10/2026 · Mockup aprovado: `docs/design/mockup-domo.html` (abre direto no navegador) · Ícone: `docs/design/domo-icon.svg`

## Por quê

O Hub tem um visual próprio (fundo "quarto escuro", cards de raio 24, fonte Outfit, brilho laranja) que destoa dos outros apps do NeyHub (Dose, Pauta, Deck), todos no tema Grafite do NeyKit. O dono quer o app com a cara do NeyHub, um nome que diga o que ele faz e um ícone de verdade (não desenhado à mão). A única coisa do visual atual que ele quer manter é o **efeito de luz acesa**: aparelho ligado acende e a luz vaza pela tela.

Junto vai um ajuste no NeyHub: fechar a janela tira o ícone (e o pontinho) do Dock, como o OrbStack.

## O que foi decidido (pelo dono)

1. **Nome: Domo.** De *domus*/*domótica*. Vale em tudo que o usuário lê: barra de menus, títulos de janela, Ajustes ("Sair do Domo", "Domo 2.4.0"), card da Loja do NeyHub, README, release notes.
2. **Direção C: Grafite + cor por aparelho.**
   - Base inteira no Grafite do NeyKit (`Grafite.bg #121315`, `card #1a1b1f`, `cardBorder #25272c`, `text`, `muted`, `label`, `accent #c6ff3d`) e nas peças `GCard`, `GPill`, `GSwitch`, `GSectionLabel`.
   - Cada tipo de aparelho mantém uma cor **só no ícone** (quadradinho de 30 pt com fundo da cor a ~12%): ar azul, luz âmbar (ou a cor real da luz), tomada verde.
   - **TV e ração usam o verde do app (`Grafite.accent`)**, inclusive no ícone. Nada vermelho ou rosa na tela: anel de progresso da ração, dias da semana das refeições, barra de volume e brilho da TV ligada, tudo em verde-limão.
   - Ligar/desligar é `GSwitch` (verde quando ligado), não mais o botão redondo de power.
   - Ações principais (Servir, Gerar QR, Abrir) são `GPill` primário; secundárias (Entrada, Desconectar, Procurar TV) são `GPill` ghost.
3. **Efeito de luz acesa: Halo (opção 1 do mockup), na intensidade reduzida.** Vale para todo aparelho ligado, cada um na sua cor de brilho (ar: azul; luz: a cor real que o `Theme.lightFill` já calcula, quente/fria/colorida; TV: verde do app; tomada: verde). O card continua grafite e:
   - acende por dentro: gradiente radial do canto superior esquerdo, cor do brilho a ~13% sumindo até ~60% do card;
   - borda tingida na cor a ~30%;
   - brilho por trás, curto: equivalente a `box-shadow: 0 8px 28px -10px` com a cor a ~38%;
   - ícone com fundo da cor a ~18% e um brilho leve (~10 pt, 30%);
   - a luz espalha no fundo do popover/tela atrás do card (mancha desfocada, ~18% de opacidade no popover, ~12% na tela grande).
   Referência exata de valores: classes `.halo` e `.spill` no CSS do mockup. Mais forte que isso o dono já rejeitou.
4. **Sem emojis. Ícones de verdade: Lucide** (a família que o Hub já embute) e o `FoodBowl` que já existe para a ração. Logos dos apps da TV continuam sendo os de `Resources/Bundle/AppLogos`.
5. **Controle da TV completo** (detalhe da TV), de cima para baixo:
   - linha: ligar, entrada, voz, menu, ajustes;
   - Setas | Touchpad (como hoje);
   - VOL +/− à esquerda e CH ▲/▼ à direita do direcional com OK no centro;
   - linha: voltar, início, info, legenda, mudo;
   - linha de mídia: anterior, retroceder, play/pause (verde), avançar, próximo.
   Continuam: grade de apps com logos e a barra de volume.
6. **Ícone do app: Lucide `house-wifi`**, sem redesenho. Casa em branco e as ondas + ponto em verde-limão, no fundo grafite dos ícones da Loja (`neyhub/Resources/icon-src/apps.html`, mesmo quadrado, gradiente e borda). Na barra de menus é o mesmo `house-wifi` em traço (template). Na barra lateral do NeyHub vale o que já acontece com todo app: o `AppIcon` colorido (`Resources/icons/hub.png` regenerado), não um traço só para o Domo. O SVG de referência (1024 px) está em `docs/design/domo-icon.svg`.
7. **NeyHub fora do Dock com a janela fechada.** O comportamento já existe ("Mostrar ícone no Dock" desligado → `.accessory` com a janela fechada, `.regular` com ela aberta, em `neyhub/Sources/NeyHub/HubPresence.swift`). Muda só o **padrão**: desligado. Quem já mexeu na opção mantém o que escolheu.

## Telas cobertas pelo mockup

Todas no mesmo vocabulário acima:

- **Popover (Casa):** cabeçalho "Boa noite" + resumo (ex.: "2 luzes acesas"), botões atualizar e ajustes; card do ar (temperatura grande, umidade, −/+ quando ligado); card da TV (Entrada + switch); luzes em grade de 2 colunas (ícone e switch em cima, nome e estado embaixo); tomadas; ração (anel verde com o pote, horário, Servir).
- **Detalhe da luz:** brilho (barra larga que acende na cor da luz), tom (quente→frio), modo (Branca/Colorida), cores rápidas. O "Cena" e o "Timer" do mockup **não entram**: o Hub hoje esconde de propósito `scene_data*` e `countdown*` (`DeviceOptions.handled`), e eles seriam comportamento novo.
- **Detalhe da TV:** item 5.
- **Detalhe da ração:** Servir agora com porções (−/+), refeições com horário, porções, dias da semana e switch, Adicionar refeição, ajustes (Chamar pelo som, Servir devagar), bateria e última refeição no cabeçalho.
- **Ajustes:** contas (Smart Life, SmartThings, Tuya) com estado e ação, TVs pareadas, Procurar TV, Abrir registro, versão. Dentro do NeyHub continuam escondidos "Abrir ao iniciar", "Janela / Barra de menus", "Sair" e "Atualização pronta".
- **Tela dentro do NeyHub:** cabeçalho e abas segmentadas iguais às da tela do Dose (Casa | TV | Ração); ar grande com régua, modos e chips de vento; TV + ração; luzes e tomadas; a luz dos aparelhos ligados espalha pelo fundo da área do app. O mockup não desenha a coluna de detalhe que a aba Casa tem hoje (260 pt à direita, preenchida ao clicar num aparelho, com as quebras em 800 e 560 pt): **ela continua como hoje**, só no visual novo; as colunas de aparelhos se reorganizam no espaço que sobra.

O mockup mostra os dados do dono como exemplo. Telas e estados que o Hub já tem e o mockup não desenha (vazio, "Conecte suas contas", buscando, pareando TV, erros, plano de refeições completo, OAuth) seguem o mesmo vocabulário.

## Restrições

- **Nada se perde na troca de nome.** Um Hub já instalado (avulso ou no NeyHub) atualiza para o Domo sozinho e continua com as mesmas contas, tokens, TVs pareadas, ajustes e log. Por isso ficam iguais: o id `local.hub` (bundle id, plugin id, defaults), o esquema `hubmac://` do retorno do SmartThings, as pastas `~/Library/Application Support/Hub` e `~/Library/Logs/Hub`, e o repositório `yagoramires/hub`.
- **O atualizador do avulso procura o nome antigo.** `Updater(name:)` do NeyKitApp busca o asset `\(name)-\(versão).zip` com `\(name).app` dentro, e versões já instaladas foram compiladas com `name: "Hub"`. A primeira versão "Domo" precisa ser encontrada por esse atualizador antigo.
- **O NeyHub também procura o nome antigo, e lê o catálogo ao vivo.** `PluginStore.receive` baixa `\(nome do catálogo)-\(versão).neyplugin`, exige `manifest.name == nome do catálogo` e instala em `Plugins/\(nome).neyplugin`. Trocar só o `name` do `catalog.json` faz todo NeyHub já instalado procurar `Domo-*.neyplugin` na hora e poderia deixar `Domo.neyplugin` ao lado de `Hub.neyplugin` (dois bundles `local.hub`). NeyHubs instalados, atualizados ou não, não podem quebrar nem duplicar o plugin. Separar nome exibido de nome de asset/pasta, ordem de release (NeyHub antes do catálogo) ou outro caminho fica com o builder.
- **Popover, tela no NeyHub e app avulso iguais**, como hoje (mesmas views do `HubCore`).
- **Só escuro**, como o resto do NeyHub (o Grafite não tem tema claro).
- macOS 15 continua o mínimo do app.
- O `Hub --render` (ImageRenderer, não desenha blur) continua gerando os PNGs iguais à tela: o brilho segue no padrão do `SoftGlow` (gradiente radial no lugar de blur).

## Não-objetivos

- Mudar como os aparelhos são controlados ou adicionar aparelhos/integrações. O único comportamento novo são os botões extras do controle da TV.
- Tema claro.
- Mudar o nome interno do código (módulos `HubCore`, `HubPlugin`, tipos `HubStore` etc.).

## Anti-objetivos (falhou mesmo funcionando se…)

- alguém perde login, TV pareada ou ajuste depois de atualizar;
- o brilho fica forte/chamativo como o laranja atual, ou some de vez;
- aparece emoji, ícone desenhado à mão no lugar de um Lucide que existe, ou vermelho/rosa na tela;
- o Hub instalado para de receber atualização.

## Decisões minhas (o dono pode revisar)

- **Fonte do sistema no lugar da Outfit**, como o resto do NeyHub. A Outfit sai do pacote.
- **Raio dos cards 10** (`Grafite.cardRadius`) no lugar de 24; popover com cantos de janela.
- **Largura do popover continua 380 pt** (o mockup usa 340 só por espaço).
- **O nome visível muda; os nomes internos não** (ver Restrições).
- **"Nada vermelho/rosa"** vale para as cores do app, não para a cor que o usuário escolhe para uma luz (vermelho nas cores rápidas continua).
- **Sem Cena e Timer na luz** e **coluna de detalhe da tela do NeyHub mantida** (ver Telas).
- **Ícone da barra de menus:** hoje alterna `house`/`house.fill` conforme algo ligado. Fica `house-wifi` em traço; se algo estiver ligado, o builder pode manter uma variação equivalente, desde que continue template.

## Fica com o builder

- Como fazer a primeira versão "Domo" ser achada pelo atualizador antigo e ainda aparecer como "Domo" no Finder/Dock (manter os nomes de asset/`.app` antigos por uma versão, publicar os dois, renomear depois, etc.).
- Como ter o `house-wifi` no app: ele não existe na `lucide.ttf` embutida (lucide-static 0.460.0), só nas versões novas (ex.: 1.65.0). Atualizar a fonte exige refazer o mapa de códigos do `Icon` (os códigos mudam entre versões); desenhar o `house-wifi` como `Shape` (como o `FoodBowl`) a partir do SVG oficial também vale, desde que seja o desenho oficial.
- Quais `KeyCode`s do Android TV usar para os botões novos (`AndroidTV.Key` hoje tem home, back, setas, center, settings, input, delete). Se a TV não aceitar algum, esse botão sai em vez de ficar mudo. "Voz" abre o assistente/busca da TV; não precisa capturar áudio do Mac.
- Organização do código do tema (substituir `Theme`, criar modificador `.halo(color:on:)`, etc.).
- Atualizar `docs/print.png`, README, CHANGELOG e os PNGs do `--render`.

## No NeyHub (repositório `neyhub`)

- Catálogo e `PluginStore`: o card mostra "Domo" sem quebrar quem já tem o Hub instalado (ver Restrições).
- `Resources/icon-src/apps.html`: glifo `hub` vira o `house-wifi` do item 6; regenerar `Resources/icons/hub.png`.
- `HubPresence.load`: padrão de `presence.dock` passa a `false`; ajustar o selftest (`SelfTest.swift`, linha que espera `dock: true` no padrão) e o README ("continua rodando quando você fecha a janela" + o ícone sai do Dock).
- README do NeyHub: tabela de apps, seção Permissões (Rede local) e Retorno de login falam "Hub" → "Domo".
