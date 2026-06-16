# Estado do App Flutter Mobile UI V2 - 2026-06-15

Este documento registra o estado atual do app Flutter visual que substitui o mobile V0/placeholder presente em `develop`.

## Evidencia rapida

- Repositorio base: `https://github.com/marcocaparra/BinGo.git`
- Branch base: `origin/develop`
- Branch local de trabalho: `feature/mobile-ui-v2-local-snapshot`
- Publicacao para o time: integrado em `origin/develop` em 2026-06-15.
- Commit local do snapshot visual: `fd782e6 feat(mobile): add current Flutter UI snapshot`
- Commit local deste status: `docs(status): map mobile UI v2 snapshot`.
- Pasta do app no repo: `Software/mobile/bingo_app`
- Origem do app copiado: `Software/Frontend, UI e UX/App Flutter/bingo_app`
- Verificacao em 2026-06-15:
  - `flutter analyze`: sem issues
  - `flutter test --no-pub`: 7 testes passaram
  - `flutter build web --no-pub --no-wasm-dry-run`: build web gerado com sucesso

Observacao: este trabalho foi preparado na pasta local `_github_work/BinGo_mobile_ui_v2` e deve ser consumido pelo time pela branch `develop`. A `main` continua intocada.

## O que esta pronto

- App Flutter visual atual foi colocado em `Software/mobile/bingo_app`.
- Estrutura principal reorganizada em `lib/src`.
- Tema visual com fonte Sora e apoio de Inter.
- Assets principais do projeto foram adicionados ao app, incluindo B1N, SCR4P, B3N, BinCoin e cenarios da Praca Central.
- Logo dark foi removida do snapshot por decisao de produto.
- Onboarding, login/piloto visual, shell principal, inicio, missoes, carteira/BinBazar, ranking e perfil existem como prototipo navegavel.
- Testes de widget cobrem responsividade basica do onboarding, entrada no app, fluxo de missao, alerta SCR4P, carteira, ranking e perfil.
- Build web funciona, o que ajuda para demonstracoes em navegador e feiras.

## O que esta em andamento

- O app ainda usa dados demo em `lib/src/data/demo_data.dart`.
- As telas representam a direcao visual e narrativa atual, mas ainda nao estao conectadas ao backend V1.
- A economia de pontos, BinCoins, ranking, recompensa e limites antifarm ainda precisa ser alinhada com as regras reais do backend.
- O BinBazar esta visualmente montado, mas os itens, imagens e regras de resgate ainda dependem de refinamento de produto.
- A narrativa de cenarios/Bingopolis ainda esta em definicao; ranking continua sendo a prioridade principal da experiencia.
- O app esta preparado visualmente para piloto/feira, mas nao deve ser tratado como produto final funcional.

## O que esta pendente

- Conectar login real do app ao fluxo definido pelo backend/Supabase.
- Consumir endpoints `/v1/me/profile`, `/v1/me/deposits`, `/v1/me/redemptions` e `/v1/rewards`.
- Separar claramente pontos de turma, pontos individuais e BinCoins.
- Definir regra final de recompensas para evitar incentivo a consumo/descarte excessivo.
- Criar estados reais de carregamento, erro, sem internet e dados vazios.
- Revisar textos para reforcar "descarte seguro e consciente" em vez de "descarte mais para ganhar".
- Validar visual em celulares reais, desktop e modo feira.
- Revisar acessibilidade: contraste, tamanho de toque, leitura por criancas e adolescentes.
- Definir assets faltantes para itens do BinBazar e possiveis poses novas dos personagens.

## Relacao com o backend V1

O backend V1 em `develop` ja tem bases importantes que devem guiar a integracao futura:

- Depositos idempotentes por `event_id`.
- Pontuacao separada para aluno e turma.
- Limite diario para itens pequenos.
- Rotas de totem, recompensas, resgates, maquinas, admin e perfil do aluno.
- Autenticacao tecnica de maquina por `X-Machine-Id` e `X-Api-Key`.
- Preparacao para Supabase Auth em `students.auth_user_id`.

O app mobile deve consumir essa base, nao recriar regra de negocio no cliente.

## Fora deste snapshot

- Totem fisico em Orange Pi com Ubuntu.
- Servico local do Edge/Orange Pi.
- Webcam/visao computacional real.
- Admin Lite visual.
- Integracao Supabase Auth no app.
- Pull request para `main`.

## Recomendacoes imediatas

1. Manter `main` intocada ate o time decidir promover uma versao estavel.
2. Usar `develop` como base de integracao.
3. Quem for desenvolver deve usar `develop` como ponto de partida.
4. Abrir PR para `main` somente quando houver versao estavel e validada pelo time.
5. Criar novos status sempre que uma parte importante mudar: app mobile, totem, backend, banco, feira/piloto e hardware.
