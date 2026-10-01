# BinBazar V1 — teto global e produtos administrativos

## Regra funcional e escopo

O [contrato Admin V1](admin-contract-v1.md) define A como responsável pelo teto global e B/C como operadores dos produtos da própria escola. DELETE continua fora do V1. A não cria produtos escolares por este fluxo.

Esta implementação acrescenta somente o teto do BinBazar. Não globaliza recompensa por descarte, XP, meta semanal ou bônus ambientais. Esses controles da tela Economia continuam explicitamente demonstrativos no Admin; suas regras persistidas anteriores não mudam.

Os contratos econômicos do aluno e de resgates da [022](binbazar-statement-v1.md), bem como entrega/cancelamento administrativos da [026](admin-binbazar-v1.md), permanecem intactos. Disponibilidade usa `is_active`; `rewards.status` continua legado; estoque `NULL` continua ilimitado. Não há expiração automática.

## Modelo e migrations

Trilhos equivalentes, incrementais, sem editar 022–026:

- `database/migrations/027_binbazar_global_price_cap_v1.sql`;
- `supabase/migrations/20261001120000_binbazar_global_price_cap_v1.sql`.

`global_economic_settings` possui uma única linha, identificada por boolean PK com CHECK que aceita somente true, `binbazar_max_price integer nullable`, `created_at` e `updated_at`. CHECK exige preço positivo quando informado. A linha inicial contém NULL: teto ainda não configurado. Nenhum valor é inferido do antigo mock 300.

`audit_logs.school_id` passa a aceitar NULL para **escopo global**. UUID continua significando escola, com a mesma FK RESTRICT. A ação global de A não recebe escola fictícia; logs escolares existentes permanecem intactos. Não havia regra funcional vigente exigindo NOT NULL: essa restrição era histórica do schema.

`rewards` recebe `created_by_admin_id` nullable com FK RESTRICT e `admin_creation_payload jsonb` nullable, com constraint de presença conjunta. Produtos anteriores continuam com ambos nulos, sem backfill. São um recibo privado da intenção original de criação administrativa: não são credenciais nem campos editáveis/retornados pelas RPCs. As operações de edição e de estoque nunca reescrevem esse recibo.

## RPCs e autorização

Todas derivam identidade por `auth.uid() → admins.auth_user_id`, exigem ACTIVE, usam SECURITY DEFINER com `search_path = ''` e EXECUTE somente authenticated. PUBLIC/anon não executam; helper interno não tem grant de cliente. RLS é fail-closed, sem leitura/escrita direta na configuração e sem novas policies ou grants de escrita Mobile.

| RPC                                         | Entrada                                                                                                                 | Resultado/permissão                                       |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `get_binbazar_price_cap_v1()`               | Nenhuma                                                                                                                 | Uma linha com `binbazar_max_price`, inclusive NULL; A/B/C |
| `update_binbazar_price_cap_v1(p_max_price)` | integer positivo                                                                                                        | Valor confirmado; somente A                               |
| `create_admin_binbazar_product_v1(...)`     | p_reward_id UUID, p_name, p_description nullable, p_category nullable, p_cost_points, p_stock_qty nullable, p_is_active | UUID; B/C, escola derivada                                |
| `update_admin_binbazar_product_v1(...)`     | p_reward_id, p_name, p_description, p_stock_qty, p_is_active, p_cost_points, p_category                                 | UUID; B/C, somente produto da própria escola              |

A assinatura anterior de update com cinco argumentos permanece como compatibilidade segura da 026: preserva preço/categoria. A assinatura completa com sete argumentos não tem defaults, evitando ambiguidade no PostgREST. Ambas chamam uma implementação privada compartilhada e reconhecem no-op.

Erros previsíveis: `55000 BINBAZAR_PRICE_CAP_UNCONFIGURED` para criação/alteração de preço sem configuração; `22023 BINBAZAR_PRICE_CAP_EXCEEDED` para preço acima do teto; `22023 BINBAZAR_PRICE_CAP_INVALID` para teto não positivo; `23505 ADMIN_PRODUCT_ID_CONFLICT` para reaproveitamento divergente do UUID. Falha de autorização usa 42501. Não se aceitam escola ou ator do cliente.

## Redução, idempotência e concorrência

Reduzir o teto não altera produtos, preços, disponibilidade, estoque reservado, saldos, resgates, snapshots ou Extrato. Um produto de 1400 continua igual após reduzir o teto para 1000. Edição que mantém 1400 pode mudar os demais campos; tentativa de mudar seu preço exige novo valor positivo até 1000. A mesma regra permite edições sem mudança de preço antes da primeira configuração.

Atualização do teto bloqueia a linha singleton com FOR UPDATE. Criação/edição de produto adquire FOR SHARE sobre a configuração **antes** do lock do produto e mantém o lock até commit. Assim, a validação de preço e a alteração do teto têm ordem serial: se o produto vence, valida o teto anterior e passa a ser histórico; se a redução vence, a operação valida o novo teto e pode falhar. Compartilhar o lock permite escritas em produtos distintos sem serializar todos entre si.

Criação recebe UUID gerado pelo browser, serializa retries pela chave com advisory transaction lock e compara ator/escola/payload normalizado ao recibo original. Replay idêntico retorna o mesmo UUID sem reinserir/auditar, inclusive depois de edição, consumo de estoque ou redução do teto. Payload divergente ou outro ator conflita. Nome tem whitespace externo removido; categoria vazia torna-se NULL. Campos do produto atual não são usados como recibo porque são mutáveis.

Enviar novamente o mesmo teto ou exatamente o estado atual do produto é no-op: não muda timestamp nem duplica auditoria. A UI mantém o UUID após resposta perdida; alteração do formulário cria uma nova intenção com outro UUID.

Auditoria transacional: `BINBAZAR_PRICE_CAP_UPDATED_V1` global registra ator A e old/new do teto; `ADMIN_PRODUCT_CREATED_V1` registra escola, ator e intenção; `ADMIN_PRODUCT_UPDATED_V1` registra campos old/new. Falha da auditoria reverte a mutation inteira.

## Angular e reprodução

`BinbazarPriceCapRepository` concentra consulta/edição do teto e descarta respostas de sessões anteriores. Economia de A usa componente específico, mostra NULL como “Ainda não configurado” e confirma somente após resposta do backend. Outros cards continuam rotulados como demonstrativos.

`AdminBinbazarRepository` usa UUID real e RPCs completas. Produtos de B/C mostram teto vigente, permitem criação/preço quando configurado e refazem leitura após mutations. Erro/NULL do teto bloqueia somente criação/preço; demais edições continuam disponíveis. Redução durante um formulário é validada pelo backend e produz erro com nova consulta do teto. Nenhum erro faz fallback para mocks.

Com Docker/Supabase local iniciado, executar na raiz Software:

```powershell
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js test db
$env:PYTHONPATH = 'backend/src'
$env:BINGO_RPC_TEST_DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
$env:BINGO_MIGRATION_TEST_DATABASE_URL = $env:BINGO_RPC_TEST_DATABASE_URL
.venv/Scripts/python.exe -m pytest backend/tests -q
```

Em apps/admin_web, com dev server na porta 8106:

```powershell
npm test
$env:BINGO_ADMIN_INTEGRATION = '1'
npm run test:integration
npm run build
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json
```

Não executar backend de migrações e integração ao mesmo tempo no banco compartilhado. As integrações são sequenciais, usam somente loopback, usuários Auth efêmeros, chave pública no browser e cleanup/restauração da configuração original. As corridas reais são exercidas dentro dos testes backend, comprovando espera pelo lock em ambos os possíveis ordenamentos para create/update versus redução do teto.

A 027, assim como 023–026, permanece local, sem promoção ao bingo-dev. Resultados finais desta validação estão no STATUS; não houve commit, push, PR, deploy ou ação remota.

## Validação local — 2026-10-01

| Comando/suíte                                                  | Resultado                                                                                          |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `node node_modules/supabase/dist/supabase.js db reset --local` | Passou, 27 migrations e seeds existentes                                                           |
| `node node_modules/supabase/dist/supabase.js test db`          | 20 arquivos, 576 verificações passaram                                                             |
| `pytest backend/tests/test_binbazar_price_cap_v1.py -q`        | 30 passaram, incluindo quatro corridas reais e rollback de auditoria                               |
| `pytest backend/tests -q` com PYTHONPATH e URLs locais acima   | 151 passaram; 13 advertências JWT legadas preexistentes                                            |
| `npm test`                                                     | 55 browser passaram, oito novos; responsividade/composição/Auth/escola/trocas/resgates preservados |
| `BINGO_ADMIN_INTEGRATION=1 npm run test:integration`           | Cinco smokes reais locais passaram, um novo A/B/C                                                  |
| `npm run build`                                                | Passou                                                                                             |
| `tsc --noEmit -p tsconfig.app.json`                            | Passou                                                                                             |
| Prettier `--check` nos arquivos Angular/testes/docs alterados  | Passou                                                                                             |
| `git diff --check`                                             | Passou                                                                                             |

Não houve falha ou skip nas suítes finais. Não há target lint Angular ou Ruff/Black configurados/disponíveis. Flutter e Edge Functions não foram executados porque não foram alterados. O FastAPI não recebeu endpoint nem alteração de domínio.

O smoke novo valida A definindo o primeiro teto pela interface, B criando produto com preço 1400, aluno Auth solicitando resgate, redução para 1000, edição não-preço permitida, preço 1300 recusado e preço 1000 aceito. Replay do UUID original continua válido depois dessas edições. Snapshot do resgate e saldo não mudam; cancelamento Mobile restitui exatamente 1400 e restaura uma unidade. C cria produto no teto com estoque ilimitado; B/C não alteram configuração global. Cleanup remove usuários/fixtures e restaura o singleton original.

As suites existentes de 022/026 exercitam solicitação/cancelamento Mobile, entrega/cancelamento Admin, snapshots e deliver × cancel Admin/Mobile com os dois vencedores. Nenhum contrato econômico anterior foi redefinido nesta migration.
