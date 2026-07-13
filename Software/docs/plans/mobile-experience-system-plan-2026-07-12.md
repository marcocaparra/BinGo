# BinGo Mobile Experience System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Renovar as telas internas e subtelas do app com hotbar rotativa, B1N contextual, recursos proprios do BinGo e navegacao sem caminhos sem saida.

**Architecture:** Manter `ShellScreen` como coordenador das cinco abas, extrair componentes visuais compartilhados para `widgets/` e evoluir as telas existentes sem alterar os dados demonstrativos. A hotbar calcula uma ordem circular apenas para apresentacao e continua enviando o indice original ao `ShellScreen`; subtelas permanecem em rotas `push` com retorno preservado.

**Tech Stack:** Flutter, Dart, Material 3, testes de widget com `flutter_test`, assets locais oficiais.

---

### Task 1: Hotbar em carrossel completo

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/widgets/bingo_navigation_bar.dart`
- Modify: `Software/mobile/bingo_app/test/bingo_navigation_bar_test.dart`

- [ ] **Step 1: Escrever testes que exigem a aba ativa no centro**

Adicionar casos que selecionam os cinco indices e verificam que o destino ativo possui `Key('bingo-nav-slot-2')`, enquanto cada item preserva `Key('bingo-nav-destination-$originalIndex')`.

```dart
for (var selected = 0; selected < 5; selected++) {
  await tester.pumpWidget(navHarness(selectedIndex: selected));
  await tester.pumpAndSettle();
  final center = find.descendant(
    of: find.byKey(const Key('bingo-nav-slot-2')),
    matching: find.byKey(Key('bingo-nav-destination-$selected')),
  );
  expect(center, findsOneWidget);
}
```

- [ ] **Step 2: Rodar o teste e confirmar a falha**

Run: `flutter test test/bingo_navigation_bar_test.dart`

Expected: FAIL porque os destinos ainda usam posicoes fixas.

- [ ] **Step 3: Implementar ordem circular com indice original preservado**

Criar uma funcao pura e testavel:

```dart
List<int> centeredDestinationOrder(int selectedIndex) => [
  (selectedIndex + 3) % 5,
  (selectedIndex + 4) % 5,
  selectedIndex,
  (selectedIndex + 1) % 5,
  (selectedIndex + 2) % 5,
];
```

Renderizar os slots com `AnimatedSwitcher`/`AnimatedSlide`, usando o indice original no callback. Com `disableAnimations`, usar duracao zero.

- [ ] **Step 4: Validar toque, centro e movimento reduzido**

Run: `flutter test test/bingo_navigation_bar_test.dart`

Expected: PASS, incluindo callback com indice original.

- [ ] **Step 5: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/widgets/bingo_navigation_bar.dart Software/mobile/bingo_app/test/bingo_navigation_bar_test.dart
git commit -m "feat(mobile): center active navigation destination"
```

### Task 2: Componentes de identidade BinGo

**Files:**
- Create: `Software/mobile/bingo_app/lib/src/widgets/bincoin_amount.dart`
- Create: `Software/mobile/bingo_app/lib/src/widgets/b1n_context_message.dart`
- Create: `Software/mobile/bingo_app/lib/src/widgets/impact_comparison.dart`
- Create: `Software/mobile/bingo_app/test/bingo_identity_widgets_test.dart`
- Modify: `Software/mobile/bingo_app/lib/src/widgets/bingo_widgets.dart`

- [ ] **Step 1: Escrever testes dos contratos visuais**

```dart
testWidgets('BinCoin amount uses the official asset and semantic label', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: BinCoinAmount(value: 120)));
  expect(find.bySemanticsLabel('120 BinCoins'), findsOneWidget);
  expect(find.byType(Image), findsOneWidget);
});

testWidgets('context message renders one character asset and one message', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: B1nContextMessage(
    asset: AppAssets.b1nIdeaInstruction,
    message: 'Estamos perto de recuperar outro setor!',
  )));
  expect(find.byType(Image), findsOneWidget);
  expect(find.text('Estamos perto de recuperar outro setor!'), findsOneWidget);
});
```

- [ ] **Step 2: Rodar e confirmar falha por componentes ausentes**

Run: `flutter test test/bingo_identity_widgets_test.dart`

Expected: FAIL por classes inexistentes.

- [ ] **Step 3: Implementar componentes com dimensoes estaveis**

`BinCoinAmount` usa `AppAssets.bincoinV2`, valor, tamanho configuravel e `Semantics`. `B1nContextMessage` aceita `asset`, `message`, `tone` e `compact`. `ImpactComparison` recebe imagens antes/agora e usa `AspectRatio` para impedir cortes divergentes.

- [ ] **Step 4: Rodar testes**

Run: `flutter test test/bingo_identity_widgets_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/widgets Software/mobile/bingo_app/test/bingo_identity_widgets_test.dart
git commit -m "feat(mobile): add BinGo identity widgets"
```

### Task 3: Ajuste pontual do Perfil

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/screens/profile_screen.dart`
- Modify: `Software/mobile/bingo_app/test/profile_screen_test.dart`

- [ ] **Step 1: Escrever regressao de espacamento e BinCoin**

Exigir `Key('profile-resource-bincoins')`, `BinCoinAmount`, altura compacta comum e ausencia de `Icons.bolt_rounded` dentro do recurso de BinCoins.

- [ ] **Step 2: Confirmar falha**

Run: `flutter test test/profile_screen_test.dart`

Expected: FAIL no asset e na altura antiga de 136 px.

- [ ] **Step 3: Compactar os tres recursos**

Alterar `_ResourceTile` para altura entre 112 e 120 px, trocar `Spacer` por espacamentos fixos e aceitar `Widget leading`. Pontos usam icones; BinCoins usa `BinCoinAmount`/asset oficial.

- [ ] **Step 4: Testar em largura estreita**

Run: `flutter test test/profile_screen_test.dart`

Expected: PASS sem overflow em 390 px.

- [ ] **Step 5: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/screens/profile_screen.dart Software/mobile/bingo_app/test/profile_screen_test.dart
git commit -m "fix(mobile): compact profile resources"
```

### Task 4: Renovar Inicio e Como Funciona

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`

- [ ] **Step 1: Escrever teste da nova hierarquia da Inicio**

Verificar cenario, uma fala contextual, uma CTA `Comecar no Totem` e uma acao unica `Como funciona o BinGo`. Confirmar que o antigo `IconButton` de ajuda nao existe.

- [ ] **Step 2: Confirmar falha**

Run: `flutter test test/widget_test.dart --plain-name "home presents one clear path"`

Expected: FAIL pela ajuda ainda isolada no AppBar.

- [ ] **Step 3: Reorganizar Inicio**

Manter `ImageHeroCard`, inserir `B1nContextMessage` curto entre cenario e missao, manter uma CTA dominante e substituir o icone superior por `InlineHelpAction(label: 'Como funciona o BinGo')` no fim do conteudo.

- [ ] **Step 4: Simplificar Como Funciona**

Usar quatro etapas com icones: preparar, Totem, validar, impacto. Separar seguranca de pontos e remover textos repetidos.

- [ ] **Step 5: Validar entrada e retorno**

Run: `flutter test test/widget_test.dart --plain-name "home presents one clear path"`

Expected: PASS e retorno para Inicio.

- [ ] **Step 6: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/screens/shell_screen.dart Software/mobile/bingo_app/test/widget_test.dart
git commit -m "feat(mobile): refresh home experience"
```

### Task 5: Renovar Carteira e BinBazar

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`

- [ ] **Step 1: Escrever testes de saldo, historico e bazar**

Exigir `BinCoinAmount(value: 120)`, uma CTA `Abrir BinBazar`, historico com rotulos `Ganhou`/`Usou` e cards do bazar com imagem, custo e estado.

- [ ] **Step 2: Confirmar falha**

Run: `flutter test test/widget_test.dart --plain-name "wallet and bazaar use official rewards language"`

Expected: FAIL nos rotulos do historico.

- [ ] **Step 3: Implementar Carteira**

Usar superficie clara azul/verde, moeda oficial e historico com icones semanticos. Evitar amarelo dominante.

- [ ] **Step 4: Implementar BinBazar**

Manter B3N apenas no cabecalho, exibir custo com `BinCoinAmount`, imagem do item e estados `Reservar`/`Faltam X`.

- [ ] **Step 5: Rodar teste**

Run: `flutter test test/widget_test.dart --plain-name "wallet and bazaar use official rewards language"`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/screens/shell_screen.dart Software/mobile/bingo_app/test/widget_test.dart
git commit -m "feat(mobile): refresh wallet and BinBazar"
```

### Task 6: Renovar Missoes e subtelas SCR4P

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Modify: `Software/mobile/bingo_app/lib/src/widgets/bingo_widgets.dart`
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`

- [ ] **Step 1: Escrever testes dos estados de missao**

Exigir identificadores `mission-active`, `mission-event`, `mission-complete`, objetivo, progresso e recompensa visiveis antes do toque.

- [ ] **Step 2: Confirmar falha**

Run: `flutter test test/widget_test.dart --plain-name "missions expose useful states"`

Expected: FAIL por cards sem estados explicitos.

- [ ] **Step 3: Evoluir MissionCard**

Adicionar enum `MissionVisualState { active, event, complete, future }`, selo de estado e recompensa com `BinCoinAmount` quando aplicavel.

- [ ] **Step 4: Revisar detalhe, SCR4P e Totem**

Detalhe responde objetivo/cuidado/recompensa; `Quem e SCR4P?` leva ao alerta; alerta possui uma unica CTA para o passo a passo; acompanhamento no Totem preserva retorno e nao recebe a hotbar.

- [ ] **Step 5: Rodar testes de fluxo**

Run: `flutter test test/widget_test.dart`

Expected: PASS, incluindo `Inicio -> Missao -> Totem -> Impacto -> Voltar`.

- [ ] **Step 6: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/screens/shell_screen.dart Software/mobile/bingo_app/lib/src/widgets/bingo_widgets.dart Software/mobile/bingo_app/test/widget_test.dart
git commit -m "feat(mobile): clarify mission states and flows"
```

### Task 7: Renovar Ranking, Cenario e Impacto

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`

- [ ] **Step 1: Escrever testes de prioridade e superficies claras**

Verificar posicao da turma antes do podio, distancia de 50 pontos, acesso ao cenario, comparacao antes/agora e ausencia de `AppColors.navy` como cor do card de impacto.

- [ ] **Step 2: Confirmar falha**

Run: `flutter test test/widget_test.dart --plain-name "ranking and impact prioritize the student context"`

Expected: FAIL pela ordem atual e card navy.

- [ ] **Step 3: Reorganizar Ranking**

Colocar `Sua turma · 9ºA` primeiro, podio condensado depois, premio do ciclo em faixa curta e cenario como unica subtela contextual.

- [ ] **Step 4: Reorganizar Impacto e Cenario atual**

Usar `ImpactComparison`, superficie clara, barra de progresso e proxima meta. Manter cenario como explicacao curta de setores/ciclo.

- [ ] **Step 5: Rodar teste**

Run: `flutter test test/widget_test.dart --plain-name "ranking and impact prioritize the student context"`

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add Software/mobile/bingo_app/lib/src/screens/shell_screen.dart Software/mobile/bingo_app/test/widget_test.dart
git commit -m "feat(mobile): refresh ranking and impact"
```

### Task 8: Auditoria de subtelas, responsividade e entrega

**Files:**
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`
- Create: `Software/docs/status/mobile-experience-system-status-2026-07-12.md`

- [ ] **Step 1: Criar matriz de navegacao em teste**

Cobrir entradas e retornos de detalhe da missao, Totem, SCR4P, Impacto, Cenario atual, BinBazar, Como funciona, dados da escola e redefinicao de PIN.

- [ ] **Step 2: Auditar callbacks e rotas estaticamente**

Run:

```powershell
rg -n "pushAndRemoveUntil|onPressed:|onTap:|TODO|FIXME" lib/src
```

Expected: `pushAndRemoveUntil` somente em acesso/troca de sessao; nenhum callback vazio.

- [ ] **Step 3: Rodar validacao completa**

```powershell
flutter analyze
flutter test
flutter build web --no-pub
```

Expected: zero issues, todos os testes aprovados e build web concluido.

- [ ] **Step 4: Inspecionar visualmente**

Validar 390x844, 430x932 e 1024x768: sem overflow, textos cortados, fundos brancos nos assets, botoes divergentes, superficies escuras ou hotbar em subtelas. Conferir console do navegador.

- [ ] **Step 5: Atualizar status**

Documentar telas alteradas, rotas verificadas, testes, URL local e itens adiados, incluindo a futura animacao de descarte do B1N.

- [ ] **Step 6: Commit**

```powershell
git add Software/mobile/bingo_app/test/widget_test.dart Software/docs/status/mobile-experience-system-status-2026-07-12.md
git commit -m "test(mobile): audit refreshed experience"
```

