# BinBazar + Extrato V1

Atualizado em: `2026-09-23`

Este documento registra a implementação do BinBazar e do Extrato autenticados, incorporada ao `develop` pelo PR #33 e evoluída incrementalmente na branch `fix/binbazar-pickup-flow`. O contrato funcional vigente é o de `admin-contract-v1.md`; o FastAPI permanece apenas como referência histórica e não define as novas regras.

## Preflight do DEV

O preflight somente leitura foi executado antes de qualquer alteração local. `supabase migration list --linked` confirmou as mesmas `21` migrations no repositório de partida, no banco local e no `bingo-dev`, de `20260527120000` a `20260922120000`. A seção final de `STATUS_12-08.md` que ainda tratava a Jornada como pendente estava desatualizada: a migration `20260922120000_class_journey_v1.sql` já constava no histórico remoto.

O dump somente leitura do schema e dos dados públicos do DEV mostrou `0 rewards` e `0 redemptions`. Portanto não existem nesse ambiente linhas `EXPIRED`, canais de pedido legados, pedidos sem snapshot, produtos ou preços históricos que precisem ser inventados. As colunas antigas ainda aceitavam somente `TOTEM` e não possuíam `client_request_id`, snapshots ou `canceled_at`, mas a evolução é segura no DEV porque não há linhas para backfill.

O único aluno vinculado ao Auth, `Aluno Smoke Test`, possui `3300` BinCoins. O valor é reconciliado exatamente por dois depósitos de `1600` BinCoins e uma aplicação `BINCOINS` de Missão de `100`, sem resgates: `1600 + 1600 + 100 = 3300`. Não foi encontrado delta histórico nem outro saldo não nulo de aluno que exigisse movimento inventado.

## Schema local

As migrations equivalentes `database/migrations/022_binbazar_statement_v1.sql` e `supabase/migrations/20260923120000_binbazar_statement_v1.sql` acrescentaram a implementação inicial. O PR #33 foi integrado ao repositório, mas as evidências disponíveis continuam sem comprovar aplicação da `022` no DEV ou em produção.

`redemptions` passa a aceitar `MOBILE` sem remover a compatibilidade histórica com `TOTEM` ou `EXPIRED`. Novos pedidos Mobile não usam expiração. Foram acrescentados:

- `client_request_id uuid`, nulo somente para linhas legadas;
- `reward_name_snapshot text` e `cost_points_snapshot integer`;
- `stock_was_finite boolean`, necessário para que uma alteração posterior do modo de estoque não invente restauração em pedido antigo;
- `canceled_at timestamptz`;
- índice único parcial de `client_request_id` quando não nulo;
- índice de leitura histórica por aluno, instante e UUID.

Nenhum valor é preenchido automaticamente em linha legada. O Extrato recusa explicitamente um histórico de resgate sem snapshots em vez de usar nome ou preço atuais do produto.

## Decisão posterior: retirada sem código

A decisão anterior de gerar um código amigável `BGO-*` foi substituída em `2026-09-23`. As migrations incrementais e funcionalmente equivalentes `database/migrations/023_redemption_without_pickup_code.sql` e `supabase/migrations/20260923130000_redemption_without_pickup_code.sql` tornam `redemptions.code` nullable e substituem somente a RPC de criação. A coluna e sua unicidade são preservadas para códigos históricos; nenhuma linha antiga é apagada ou reescrita.

Novos pedidos Mobile persistem `code = NULL`. A escola identifica operacionalmente a retirada pelo aluno e pelo pedido, sem PIN, QR ou código. Essa mudança não altera idempotência, locks, saldo, estoque, snapshots, auditoria, cancelamento ou o Extrato.

## RPCs autenticadas

Todas as RPCs são `SECURITY DEFINER`, usam `search_path` vazio, derivam identidade de `auth.uid()` e concedem `EXECUTE` somente a `authenticated`.

`get_my_binbazar_catalog_v1()` lista somente produtos ativos da escola do aluno `ACTIVE`. `is_active` é a autoridade administrativa; `rewards.status` não participa. Estoque `NULL` permanece ilimitado e estoque zero permanece visível como esgotado.

`request_redemption_v1(p_request_id, p_reward_id)` serializa a chave idempotente, bloqueia aluno e produto na mesma ordem, valida vínculo, estado, escola, disponibilidade, estoque e saldo, fotografa nome/preço/modo de estoque, debita saldo, reserva estoque finito, cria um pedido `PENDING/MOBILE` com `code = NULL` e registra uma auditoria na mesma transação. Replay idêntico retorna o pedido persistido e o saldo autoritativo sem novo efeito; reutilização divergente é conflito.

`cancel_my_redemption_v1(p_redemption_id)` bloqueia primeiro o pedido para preservar a futura corrida com entrega Admin. Somente o próprio aluno e um pedido Mobile `PENDING` podem realizar a primeira transição. Essa transição devolve exatamente `cost_points_snapshot`, restaura uma unidade somente quando o pedido reservou estoque finito e o produto ainda usa estoque finito, grava `canceled_at`, muda o estado e audita. Se o produto tiver mudado de estoque finito para ilimitado, `stock_qty` permanece `NULL`; a auditoria distingue a reserva finita histórica (`finite_stock_reserved`) do incremento realmente executado (`finite_stock_restored`). Retry de `CANCELED` somente retorna a fotografia atual. `DELIVERED` é recusado.

`get_my_redemptions_v1()` lista somente os pedidos do próprio aluno, usa exclusivamente snapshots e continua retornando `code` nullable para manter linhas históricas legíveis. `get_my_bincoin_statement_v1()` consolida depósitos positivos, aplicações `BINCOINS` de Missão, débitos de criação e créditos de cancelamento. XP e entrega não produzem movimentos. A ordenação é `occurred_at DESC`, seguida por ordem de fonte e UUID. O saldo autoritativo permanece `students.points_student_balance`; não existe saldo paralelo e `audit_logs` não é ledger.

## Mobile

O Mobile possui um repository autenticado próprio para catálogo, pedidos, mutações e Extrato. Widgets não consultam o Supabase diretamente. A composição visual existente foi preservada e os produtos autenticados usam uma apresentação local neutra, sem Storage ou upload.

Cada intenção cria um UUID v4 uma única vez e conserva o mesmo valor após falha/retry até receber uma resposta válida. Criação e cancelamento usam o saldo retornado pelo servidor imediatamente; a própria rota aberta recarrega catálogo e pedidos mesmo quando a resposta é um replay, e a Carteira pai recarrega catálogo, pedidos e Extrato. A Wallet autenticada deriva toda informação de catálogo da resposta remota e não exibe texto ou métrica de simulação.

“Seus pedidos” mostra exclusivamente pedidos `PENDING`; `DELIVERED` e `CANCELED` desaparecem imediatamente após sincronização, sem apagar o histórico do banco ou do Extrato. O fluxo autenticado não mostra códigos e a confirmação orienta retirada presencial com carteirinha. O piloto continua usando `SessionWalletController` e preserva sua simulação local, inclusive seu código explicitamente demonstrativo; ele não materializa redemptions reais.

## Validação local

Após a implementação foram aprovados:

- `supabase db reset` com todas as `23` migrations locais e seeds;
- `supabase test db`: `15` arquivos e `350` testes;
- pgTAP específico do BinBazar/Extrato: `37` testes;
- testes PostgreSQL de paridade e concorrência: `3` testes;
- testes Flutter direcionados de BinBazar/repository/piloto: `10` testes;
- suíte Flutter completa: `250` testes aprovados e `1` teste hospedado ignorado;
- `flutter analyze` sem problemas;
- `git diff --check` sem erros;
- verificação equivalente com índice temporário incluindo arquivos não rastreados, sem erros.

Não houve `db push`, commit, push, merge ou operação em produção nesta evolução. A `023` foi aplicada somente pelo reset local.
