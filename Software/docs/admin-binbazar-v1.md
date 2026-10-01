# Admin BinBazar V1 — operação escolar

Implementação local na branch `feature/admin-school-management-foundation`.

## Regras funcionais

A fonte funcional é [admin-contract-v1.md](admin-contract-v1.md). B/C operam produtos e resgates somente da própria escola; A não participa da operação cotidiana. Produtos não são excluídos. Pedidos não expiram automaticamente no V1. O teto global de preço pertence a A. A fatia 026 abaixo preserva sua implantação original; a conclusão do teto e dos produtos na 027 está documentada em [binbazar-global-price-cap-v1.md](binbazar-global-price-cap-v1.md).

O preflight consultou STATUS, contrato Admin, [binbazar-statement-v1.md](binbazar-statement-v1.md), database-model, migrations 022–025, schema local de rewards/redemptions/school_settings e referências de preço/configuração no Angular e legado. No preflight da 026 não existia fonte persistida do teto: `cost_points > 0` é apenas integridade de preço positivo; `school_settings` não contém teto; `300` existe somente no AdminStore demonstrativo. Portanto a 026 não oferecia criação de produto nem alteração de preço; DELETE continua fora do V1. A 027 acrescenta criação/preço validados pelo teto global, sem editar a 026. Na entrega da 026 a UI explicitava a pendência e não enviava preço em mutations. Nenhum valor, coluna, tabela ou configuração de teto foi inventado.

## O que veio da 022

Catálogo e pedidos do aluno, criação idempotente por UUID, débito, reserva de estoque, snapshots imutáveis, código interno BGO e Extrato continuam sob os contratos da migration 022. `is_active` define disponibilidade; `rewards.status` é legado. `stock_qty = NULL` significa ilimitado. Não se aplicam expiração, limite diário ou nova autenticação pelo código.

Os arquivos históricos da 022 não foram editados. A 026 substitui somente a implementação interna de `cancel_my_redemption_v1`, mantendo assinatura, validação de proprietário/canal Mobile, estados, erros, replay, resultado e metadata econômica original. O refund/restock/audit passa a chamar um núcleo privado compartilhado. Catálogo, solicitação, histórico e Extrato não foram redefinidos.

## Migration e contratos administrativos

Trilhos funcionalmente idênticos:

- `database/migrations/026_admin_binbazar_v1.sql`;
- `supabase/migrations/20260930150000_admin_binbazar_v1.sql`.

Não há tabela, coluna, constraint ou backfill novo. FKs e histórico permanecem intactos. A 026, assim como 023/024/025, está somente local, sem promoção ao bingo-dev. Esta tarefa não consultou nem alterou ambiente remoto.

| RPC                                            | Entrada                                                                                                       | Resultado                                                                                                                                                               |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `get_admin_binbazar_products_v1()`             | Nenhuma                                                                                                       | reward_id, name, description, category, cost_points, is_active, stock_qty; inclui inativos e estoque zero                                                               |
| `update_admin_binbazar_product_v1(...)`        | p_reward_id UUID, p_name text, p_description text nullable, p_stock_qty integer nullable, p_is_active boolean | UUID do produto; não aceita preço/escola/ator                                                                                                                           |
| `get_admin_redemptions_v1()`                   | Nenhuma                                                                                                       | redemption_id, code, status, student_id/name/registration, class_id/name atuais, reward_id, snapshots, created_at/delivered_at/canceled_at e delivered_by_admin_id/name |
| `deliver_admin_redemption_v1(p_redemption_id)` | UUID do pedido                                                                                                | UUID; PENDING → DELIVERED; retry DELIVERED sem efeitos                                                                                                                  |
| `cancel_admin_redemption_v1(p_redemption_id)`  | UUID do pedido                                                                                                | UUID; PENDING → CANCELED; retry CANCELED sem efeitos                                                                                                                    |

Toda RPC reutiliza `require_school_admin_v1(false)`: Auth → admins.auth_user_id → ACTIVE + B/C + escola obrigatória. O parâmetro false significa permitir ambos os papéis escolares, inclusive nas escritas deste domínio; a restrição B das mutations escolares da 024 continua intacta. Cliente não escolhe escola nem ator. Produtos e pedidos externos são recusados, inclusive relações históricas inconsistentes entre escola do pedido/aluno/produto.

SECURITY DEFINER usa `search_path = ''`. EXECUTE de PUBLIC/anon/service_role é revogado; somente authenticated recebe execução das cinco RPCs. O helper `refund_pending_redemption_v1(uuid,text,uuid,uuid)` não recebe grant de cliente. RLS fail-closed e ausência de escrita direta em rewards/redemptions permanecem, sem policies Mobile novas ou ampliadas.

## Transações, concorrência e auditoria

Entrega e cancelamento bloqueiam a mesma redemption com FOR UPDATE antes de qualquer outra linha de negócio. Após adquirir o lock, conferem escola e status. A primeira transição terminal vence; uma decisão oposta recebe SQLSTATE 55000. Retry compatível não muda timestamps/ator nem duplica audit log. Isso vale também para cancelamento Mobile concorrente com entrega Admin.

Entrega altera somente status, delivered_at e delivered_by_admin_id derivado. Não cobra saldo e não modifica estoque.

O núcleo de cancelamento exige snapshots completos, devolve exatamente cost_points_snapshot, e restaura uma unidade somente quando stock_was_finite e o estoque atual do produto ainda é finito. Produto posteriormente ilimitado mantém NULL; snapshot originalmente ilimitado não aumenta estoque posteriormente finito. Aluno e produto são atualizados depois do lock do pedido, na ordem já usada na 022. Pedido legado sem snapshots permanece visível com lacuna explícita, sem reconstrução pelo preço/nome atual; cancelamento econômico desse legado é recusado.

Auditoria ADMIN usa ator derivado da sessão e as ações ADMIN_PRODUCT_UPDATED_V1, ADMIN_REDEMPTION_DELIVERED_V1 e ADMIN_REDEMPTION_CANCELED_V1. Produto inclui campos antigos/novos seguros; pedido inclui IDs e transição; cancelamento inclui valor restituído, reserva finita e restauração efetiva. Auditoria e mutation compartilham transação: erro de auditoria reverte tudo. Não se alteram depósitos, XP, Missões, Jornada ou snapshots antigos.

## Angular

`AdminBinbazarRepository` concentra RPCs, fotografias por domínio, geração de leitura e descarte de resposta após mudança de contexto Auth. Logout elimina listas/operação/feedback. Telas usam UUIDs, estados loading/empty/error/submitting, conflito explícito, retry e refetch autoritativo após mutations; erro não usa mocks.

A entrega original da 026 permitia nome/descrição/estoque/ativo, com preço e criação bloqueados. A 027 habilita criação/preço/categoria conforme o teto real; confira a documentação complementar. Campo estoque vazio representa ilimitado; zero é finito esgotado.

Resgates e bloco de Pendências usam a mesma fonte real, filtros PENDING/DELIVERED/CANCELED/histórico, busca visual por código/nome/matrícula, snapshots e turma atual. Código BGO é identificador administrativo, sem PIN/QR/autenticação adicional. Expiração demonstrativa foi removida. Trocas de turma reais continuam; overview, ajuda, depósitos, máquinas, administradores, escolas e Missões continuam demonstrativos. Economia agora integra somente o teto real da 027; os demais controles continuam demonstrativos. Métricas estáticas do overview permanecem explicitamente demo e separadas da fila real.

## Reprodução local

Na raiz Software, com Docker/Supabase local iniciado:

```powershell
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js test db
$env:PYTHONPATH = 'backend/src'
$env:BINGO_RPC_TEST_DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
$env:BINGO_MIGRATION_TEST_DATABASE_URL = $env:BINGO_RPC_TEST_DATABASE_URL
.venv/Scripts/python.exe -m pytest backend/tests -q
```

Em apps/admin_web, iniciar em outro terminal `node node_modules/@angular/cli/bin/ng.js serve --host 127.0.0.1 --port 8106`; então:

```powershell
npm test
$env:BINGO_ADMIN_INTEGRATION = '1'
npm run test:integration
npm run build
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json
```

A integração usa exclusivamente loopback, Auth local, credenciais aleatórias efêmeras e cleanup. Chave técnica fica no processo Node de provisionamento; browser recebe apenas anon/publicável. Não se criam usuários remotos.

## Validação local da entrega 026 — 2026-10-01

| Comando/suíte                                                   | Resultado                                                                                      |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `supabase db reset --local` via CLI Node                        | Passou com 26 migrations e seeds existentes                                                    |
| `supabase test db` via CLI Node                                 | 19 arquivos, 561 verificações passaram; 14 novas de segurança Admin BinBazar                   |
| `pytest backend/tests -q` com URLs locais                       | 121 passaram; 34 novas, incluindo concorrência real e rollback de auditoria nas três mutations |
| `npm test`                                                      | 47 browser passaram; nove novas de BinBazar, preservando Auth/escola/trocas/responsividade     |
| `BINGO_ADMIN_INTEGRATION=1 npm run test:integration`            | Quatro passaram com Auth local; um novo smoke BinBazar B/C                                     |
| `npm run build`                                                 | Passou                                                                                         |
| `tsc --noEmit -p tsconfig.app.json`                             | Passou                                                                                         |
| Prettier `--check` nos arquivos Angular/testes/README alterados | Passou                                                                                         |
| `git diff --check`                                              | Passou                                                                                         |

As corridas testadas bloqueiam o pedido em uma transação enquanto a decisão concorrente aguarda efetivamente o lock: deliver × cancel Admin e deliver Admin × cancel Mobile, com cada um dos dois possíveis vencedores. Verificam estado final, saldo, estoque, ator e auditoria única após retry. Outros testes cobrem B/C, A/inativo/sem vínculo, isolamento, estoque zero/NULL, inativação, snapshots, ausência de preço/escola/ator nas entradas, histórico de depósitos intacto e recusa econômica de legado sem snapshot.

Smoke real: aluno Auth solicita dois pedidos → B altera produto e entrega um → C lista/cancela outro → saldo/estoque/snapshots/ator/auditoria conferidos; C muda estoque para ilimitado e cancela novo pedido sem transformar NULL em estoque finito. Fixtures e usuários Auth efêmeros foram removidos.

Nenhum skip nas execuções finais. Os 13 avisos JWT são preexistentes nos testes FastAPI legados. Execuções iniciais de browser falharam por codificação/seletor e foram corrigidas antes da repetição completa. Uma execução paralela de backend e integração falhou em quatro testes da 023: fixture efêmera ADMIN_A com escola NULL impedia reconstruir schema legado NOT NULL. A repetição isolada, após cleanup confirmado, passou todos os 121. Execute testes de migração e integrações em sequência no banco local compartilhado; as corridas de domínio são exercidas dentro dos testes específicos.

Não há target lint Angular nem Ruff/Black configurados/disponíveis; checagens de disponibilidade desses formatadores Python não os executaram. Flutter e Edge Functions não foram executados porque não foram alterados. Não há falha ou skip pendente nas suítes aplicáveis.

## Inventário e Git

Working tree na branch `feature/admin-school-management-foundation`; sem arquivos staged, commit, push, PR, merge, deploy, migration hospedada ou qualquer consulta/alteração em bingo-dev/produção. Apenas reset e fixtures locais foram utilizados.

`git status --short` após as alterações:

```text
 M apps/admin_web/README.md
 M apps/admin_web/admin_flow.test.cjs
 M apps/admin_web/class_requests.test.cjs
 M apps/admin_web/package.json
 M apps/admin_web/src/app/core/admin-store.ts
 M apps/admin_web/src/app/features/management.component.ts
 M apps/admin_web/src/app/features/overview.component.ts
 M apps/admin_web/src/app/features/redemptions.component.ts
 M apps/admin_web/src/app/layout/admin-shell.component.ts
 M apps/admin_web/src/app/shared/operation-dialog.component.ts
 M apps/admin_web/test/supabase-fixture.cjs
 M docs/STATUS_12-08.md
?? apps/admin_web/binbazar.integration.test.cjs
?? apps/admin_web/binbazar.test.cjs
?? apps/admin_web/src/app/core/admin-binbazar.repository.ts
?? apps/admin_web/src/app/features/products.component.ts
?? backend/tests/test_admin_binbazar_v1.py
?? database/migrations/026_admin_binbazar_v1.sql
?? docs/admin-binbazar-v1.md
?? supabase/migrations/20260930150000_admin_binbazar_v1.sql
?? supabase/tests/admin_binbazar_v1.sql
```
