# BinGo! App Flutter

Protótipo Flutter criado a partir do wireframe `V7.1 B1N GUIDE`, já com os ajustes iniciais da revisão crítica de UX/UI.

## Onde Está

`Software/Frontend, UI e UX/App Flutter/bingo_app`

## Decisões De UX/UI

- Fonte do app: `Sora` para títulos e momentos de impacto; `Inter` para corpo, labels e navegação.
- Verde: descarte, sucesso e progresso ecológico.
- Azul: navegação e ações neutras.
- Roxo: eventos SCR4P.
- B1N aparece como guia em momentos úteis, sem virar mascote em toda tela.
- A aba principal de competição é `Ranking`; `Cenários` entra como subtela/contexto do ciclo atual.
- Cenário = lugar atacado pelo SCR4P; setor = parte recuperada; ciclo = período da disputa.
- `BinBazar` é a loja de recompensas do Tio B3N, tio do B1N e personagem exclusivo do bazar.
- Recompensas e alertas SCR4P usam roxo para manter a linguagem visual do antagonista.
- Para feiras e testes supervisionados, o app usa `modo piloto`: demonstra a jornada sem coletar dados reais de alunos.
- Toda validação simulada deve ser apresentada como demonstração. A validação real pertence ao fluxo Totem/professor/sensor.
- Mensagem pedagógica central: BinGo! recompensa descarte correto, seguro e validado; não recompensa volume por volume.
- O Totem ainda não tem telas próprias, mas o app já explica o fluxo físico.

## Assets No App

- Personagens e objetos usados sobre cards devem ter PNG com fundo transparente.
- Originais com fundo branco ficam preservados; o app aponta para variantes `*_transparent.png`.
- Cenários completos não devem ter fundo removido, porque o ambiente faz parte da composição.
- Assets transparentes usados pelo app: `logo_official_transparent.png`, `b1n_pose_transparent.png`, `scr4p_pose_transparent.png`, `b3n_tio_b1n_transparent.png`, `b1n_coin_transparent.png`, `bincoin_transparent.png`, `totem_concept_transparent.png`.
- A BinCoin principal na UI continua sendo `BinCoin - 3D v2.png`, já com transparência.

## Estrutura

- `lib/main.dart`: entrada do app.
- `lib/src/app.dart`: configuração do `MaterialApp`.
- `lib/src/theme`: cores, fontes, tema e caminhos de assets.
- `lib/src/widgets`: componentes reutilizáveis.
- `lib/src/screens`: telas do app.
- `lib/src/data`: dados temporários do protótipo.
- `assets/images`: cópia limpa dos assets oficiais usados pelo app.
- `assets/fonts`: fontes locais Sora e Inter.

## Comandos

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web
flutter run
```

Se o Flutter reclamar de pastas `ephemeral` dentro do OneDrive, apague as pastas temporárias de plataforma e rode o comando novamente. Isso é cache gerado pelo Flutter, não código do app.
