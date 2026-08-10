# Mobile Engagement Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tornar o retorno ao app automatico, modernizar movimento e navegacao, reconstruir o Perfil e eliminar incoerencias de jornada.

**Architecture:** `BingoApp` vira uma porta de sessao que resolve `ProfileRepository` antes de escolher onboarding ou shell. Componentes de movimento ficam isolados em widgets compartilhados. O Perfil recebe o repositorio por injecao para redefinir PIN e encerrar a sessao sem acoplamento a `SharedPreferences`.

**Tech Stack:** Flutter, Dart, Material 3, shared_preferences, flutter_test.

---

### Task 1: Porta de sessao local

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/app.dart`
- Modify: `Software/mobile/bingo_app/lib/src/data/profile_repository.dart`
- Modify: `Software/mobile/bingo_app/lib/src/screens/onboarding_screen.dart`
- Modify: `Software/mobile/bingo_app/lib/src/screens/access_flow_screen.dart`
- Test: `Software/mobile/bingo_app/test/session_gate_test.dart`

- [ ] Escrever teste que injeta repositorio com perfil e espera `ShellScreen`, e repositorio vazio e espera onboarding.
- [ ] Rodar `flutter test test/session_gate_test.dart` e confirmar falha pela ausencia da porta de sessao.
- [ ] Adicionar `deleteProfile()` ao contrato e implementar remocao das tres chaves locais.
- [ ] Criar `SessionGate` que resolve o repositorio, usa `hasProfile()` e escolhe a tela inicial.
- [ ] Passar o mesmo repositorio por onboarding, acesso e shell.
- [ ] Rodar o teste e confirmar sucesso.

### Task 2: Energia de botao e Rota do descarte

**Files:**
- Modify: `Software/mobile/bingo_app/lib/src/widgets/bingo_action_button.dart`
- Modify: `Software/mobile/bingo_app/lib/src/screens/onboarding_screen.dart`
- Test: `Software/mobile/bingo_app/test/bingo_action_button_test.dart`
- Test: `Software/mobile/bingo_app/test/widget_test.dart`

- [ ] Escrever teste que habilita `disableAnimations` e confirma que o botao continua funcional sem animacao repetida.
- [ ] Rodar o teste e confirmar falha no comportamento ainda nao exposto.
- [ ] Substituir highlight fixo por `AnimationController` com faixa diagonal, ida e volta e opacidade baixa.
- [ ] Reduzir sombra e relevo para remover aparencia skeuomorfica.
- [ ] Substituir numeros do onboarding por quatro icones conectados e labels curtas.
- [ ] Rodar testes de botao e onboarding em 390x844, 430x932 e 1024x768.

### Task 3: Hotbar BinGo

**Files:**
- Create: `Software/mobile/bingo_app/lib/src/widgets/bingo_navigation_bar.dart`
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Test: `Software/mobile/bingo_app/test/bingo_navigation_bar_test.dart`

- [ ] Escrever teste que toca cada destino e confirma que a ordem Inicio, Carteira, Missoes, Ranking e Perfil nunca muda.
- [ ] Rodar o teste e confirmar falha porque o widget ainda nao existe.
- [ ] Implementar barra fixa com cinco destinos, indicador deslizante, icone ativo elevado e labels estaveis.
- [ ] Respeitar `disableAnimations` e areas seguras inferiores.
- [ ] Rodar teste e confirmar navegacao correta.

### Task 4: Perfil e gerenciamento de PIN

**Files:**
- Create: `Software/mobile/bingo_app/lib/src/screens/profile_screen.dart`
- Create: `Software/mobile/bingo_app/lib/src/screens/change_pin_screen.dart`
- Modify: `Software/mobile/bingo_app/lib/src/screens/shell_screen.dart`
- Test: `Software/mobile/bingo_app/test/profile_screen_test.dart`

- [ ] Escrever testes para recursos distintos, trilha 1 a 5, acesso a redefinicao e confirmacao antes de trocar conta.
- [ ] Rodar teste e confirmar falha na tela antiga.
- [ ] Extrair Perfil do arquivo monolitico `shell_screen.dart`.
- [ ] Implementar cabecalho com iniciais, nivel e progresso; resumo de recursos; trilha visual; uma fala de B1N; configuracoes compactas.
- [ ] Implementar redefinicao com PIN de quatro digitos e confirmacao usando `PinKeypad`.
- [ ] Implementar troca de conta com dialogo, `deleteProfile()` e retorno ao onboarding.
- [ ] Rodar os testes e confirmar sucesso.

### Task 5: Auditoria e validacao

**Files:**
- Modify: `Software/mobile/bingo_app/test/widget_test.dart`
- Create: `Software/docs/status/mobile-engagement-refresh-status-2026-07-12.md`

- [ ] Percorrer todas as rotas acionaveis e registrar qualquer destino duplicado, sem saida ou sem efeito.
- [ ] Criar testes de regressao para cada incoerencia confirmada antes de corrigir.
- [ ] Validar responsividade e ausencia de overflow em 390x844, 430x932 e 1024x768.
- [ ] Rodar `flutter analyze`, `flutter test` e `flutter build web`.
- [ ] Abrir a build no navegador, verificar console e revisar Inicio, Perfil, PIN e cada destino da hotbar.
- [ ] Atualizar status com decisoes, limitacoes e comandos executados.
