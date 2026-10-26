# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-10-25

### Adicionado
- Hub no NeyHub: instale o `Hub-0.2.0.neyplugin` pela Loja e ele roda dentro do NeyHub, com as mesmas contas, TVs pareadas e ajustes do avulso.
- Tela do Hub (janela do NeyHub, ou o modo Janela no avulso), com o tema do próprio Hub: abas Casa, TV e Ração. Na Casa, o ar-condicionado, a TV, os aparelhos e a ração lado a lado, e o detalhe do aparelho escolhido sempre aberto à direita. Na TV, o controle inteiro; na Ração, as refeições programadas.
- Modos de exibição no avulso: Janela, Barra de menus ou os dois, nos ajustes.
- Atualização automática: confere sozinho se tem versão nova, baixa e troca o app quando você fecha o Hub (ou em "Reiniciar agora"), e mostra as novidades na abertura seguinte.
- Menu Editar no modo Janela (⌘C, ⌘V e companhia nos campos de texto).

### Alterado
- Ícone novo no padrão do NeyHub: o mesmo desenho, em fundo grafite com detalhe verde-limão.
- O popover fecha ao clicar em outro app.
- Sem as fontes ou os logos empacotados, o Hub usa a fonte do sistema e ícones genéricos (e avisa no registro) em vez de mostrar quadrados vazios.
- O build exige o certificado local de assinatura (sem fallback ad-hoc).

## [0.1.0] - 2026-10-25

### Adicionado
- Primeira versão: aparelhos da casa pela barra de menus, de contas Smart Life, Tuya Smart, Positivo (login por QR code) e SmartThings (login no navegador).
- Cartão do ar-condicionado com régua de temperatura, modos e ventilação.
- TV Google TV / Android TV pelo protocolo do controle remoto v2, com pareamento por código, volume, apps, controle completo e busca; abrir apps e digitar texto pelo ADB, opcional.
- Luzes, tomadas e alimentador, com refeições programadas (listar, criar, editar, ativar e apagar).
- Credenciais num arquivo legível só pelo usuário, no lugar do Chaveiro.
- Interface escura e clara, com a cor de cada aparelho.
- Modo terminal para depurar (`--dump`, `--render` e outros).
