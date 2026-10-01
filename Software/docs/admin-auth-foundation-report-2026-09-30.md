# Relatório — fundação de autenticação administrativa

Data: `2026-09-30`. Branch: `feature/admin-auth-foundation`. Entrega local, sem commit.

## 1. Implementação

A fatia `Supabase Auth → identidade administrativa → role/school/status → sessão
Angular` está implementada e comprovada localmente. Login, restauração, logout,
ausência de administrador e inatividade usam a fronteira real de Auth/RPC.
As outras telas continuam demonstrativas. Nenhum domínio administrativo
adicional, endpoint FastAPI ou Edge Function foi integrado.

## 2. Decisões e preflight

O preflight foi somente leitura, na ordem solicitada: STATUS, contrato Admin,
documentos de banco/Auth/Supabase, migrations dos dois trilhos, testes SQL e
integração existentes, Angular e referências legadas. A branch foi confirmada.
O working tree já continha 14 arquivos de cache Angular staged; eles foram
preservados, incluindo seu conteúdo original do índice.

Não surgiu conflito impeditivo. As referências antigas de preparação Auth/RLS
foram interpretadas como históricas diante do STATUS e migrations atuais.
O contrato Admin permaneceu intacto. Supabase Auth prova a identidade; admins
define o principal; PostgreSQL resolve contexto; Angular apenas apresenta.

Foi adotado `@supabase/supabase-js@2.111.0`, mesma versão do runtime das Functions
no repositório. A configuração Angular reutiliza os nomes públicos do Mobile,
com asset JSON por ambiente e SDK carregado sob demanda. O cliente valida tipo
de chave para recusar service_role/sb_secret por engano.

## 3. Migrations

| Trilho | Nova migration | Anterior mais recente |
| --- | --- | --- |
| PostgreSQL | `database/migrations/023_admin_auth_foundation.sql` | `022_binbazar_statement_v1.sql` |
| Supabase | `supabase/migrations/20260930120000_admin_auth_foundation.sql` | `20260923120000_binbazar_statement_v1.sql` |

Os dois arquivos são idênticos e transacionais. A tabela não foi recriada.
Há lock e verificação de roles históricos antes do DDL; não há conversão de dados.

## 4. Schema relevante final

`admins.id`, nome, email único, timestamps e password_hash legados permanecem.
`auth_user_id UUID NULL UNIQUE` liga a conta ao Auth. `status TEXT NOT NULL
DEFAULT 'ACTIVE'` aceita ACTIVE/INACTIVE. `role TEXT NOT NULL` aceita somente
ADMIN_A/B/C. `school_id UUID NULL` conserva a FK RESTRICT de schools, com CHECK
que exige A NULL e B/C NOT NULL.

Não há FK Auth nem cascade: foi seguido o vínculo lógico que já existe em
students nos dois trilhos. `redemptions.delivered_by_admin_id` continua com FK
RESTRICT para admins. `audit_logs.actor_id` continua referência lógica, sem nova
FK. IDs, registros de entrega, auditoria, metadata e hashes históricos foram
preservados nas provas transacionais de evolução.

## 5. RPC

`get_my_admin_context_v1()` não recebe argumentos e resolve exclusivamente
`auth.uid() → admins.auth_user_id`. Retorna zero ou uma linha com
`id, name, email, role, school_id, status`. Não devolve password_hash,
auth_user_id, tokens, credenciais ou outros campos internos.

É SQL, STABLE, SECURITY DEFINER, com search_path vazio. INACTIVE é retornado
somente para informar a situação da própria conta; o comentário no banco e no
serviço exige que futuras operações validem ACTIVE/role/school server-side.

## 6. Grants e RLS

EXECUTE revogado de PUBLIC/anon/authenticated/service_role e concedido apenas
a authenticated. admins segue com RLS habilitada, nenhuma policy, nenhum SELECT
amplo/de coluna e nenhuma escrita direta concedida ao cliente. As demais
policies/grants não mudaram. pgTAP, integração HTTP e postflight confirmaram isso.

## 7. Arquivos Angular

Criados: `core/admin-context.ts`, `core/supabase-client.ts`,
`core/admin-auth.service.ts`, exemplo de configuração pública e testes Auth.
Alterados: `app.ts`, `features/access.component.ts`,
`layout/admin-shell.component.ts`, `core/admin-store.ts`, dependências/lockfile,
suíte anterior, README e gitignore. `admin-access.ts`, `roles/`, componentes de
negócio e CSS não foram alterados. Detalhes no procedimento
[`admin-supabase-auth-session.md`](admin-supabase-auth-session.md).

## 8. Login

Email/senha → signInWithPassword → sessão → RPC sem parâmetros → validação de
resposta/status/escola → experiência A/B/C. Os seletores de perfil do login e
shell foram removidos. A senha não tem valor demo e é limpa do formulário após
submissão. Não há fallback para role C ou perfil mock. Nome do operador e escopo
do cabeçalho vêm do contexto; os dashboards continuam identificados como demo.

## 9. Restauração e eventos Auth

getSession restaura os tokens gerenciados pelo SDK; a RPC é chamada novamente.
Role/escola/status não são confiados a cache, URL ou metadata. Há um único
listener, cleanup por DestroyRef, deduplicação de eventos com token já resolvido
e tratamento de SIGNED_IN/TOKEN_REFRESHED/USER_UPDATED/SIGNED_OUT. Chamadas
Supabase adicionais ocorrem fora do callback do listener; isso segue a
[orientação do Supabase sobre o lock do callback](https://supabase.com/docs/guides/troubleshooting/why-is-my-supabase-api-call-not-returning-PGzXw0).
Gerações de operação impedem resposta atrasada de reabrir o shell após sign-out.

## 10. Logout

signOut com scope local; contexto removido imediatamente, role computada do
AdminStore volta a NULL e diálogos transitórios são fechados. Sucesso retorna
ao login sem refresh. Falha mantém o shell bloqueado e permite nova tentativa,
sem fingir que os tokens foram removidos. O logout não encerra outros aparelhos.

## 11. Auth sem administrador

Zero linhas da RPC gera estado de acesso administrativo não autorizado. Nenhuma
tela administrativa abre; logout permanece disponível. Nenhuma conta de domínio
ou role é criada automaticamente.

## 12. Administrador inativo

Contexto INACTIVE gera mensagem específica e bloqueia o shell. A conta Auth
pode continuar válida. Não é autorização para operações futuras: o backend
de cada operação deverá validar ACTIVE novamente.

## 13. Testes adicionados/adaptados

- 36 verificações pgTAP: constraints, A/B/C/escola, status, unicidade Auth,
  roles inválidos/legados, assinatura sem argumentos, anonimato, própria
  identidade, ausência/inatividade, retorno mínimo, grants/RLS e FK de entrega.
- 5 testes Python: equivalência literal dos trilhos, recusa de cada um dos três
  papéis legados antes de DDL e preservação literal de conta/entrega/auditoria.
- 18 testes de browser Auth/session com SDK real e HTTP controlado: login sem
  selector, A/B/C, credenciais inválidas, bloqueios, restauração, logout, erro de
  rede/backend, payload malformado, ausência de confiança em URL/cache/metadata,
  eventos Auth, resposta atrasada e falha de logout.
- 6 testes anteriores de navegação, ações mock, composição e responsividade
  preservados; login passou a usar fixture HTTP e asserts aguardam renderização.
- 1 integração opt-in real local: Auth → RPC → Angular, credenciais inválidas,
  login ativo A, refresh, INACTIVE após atualização server-side, Auth sem vínculo,
  logout, anon bloqueado, leitura/escrita negadas e parâmetro de identidade rejeitado.

## 14–15. Comandos e resultados finais

| Comando / operação | Resultado |
| --- | --- |
| `git status --short`, `git branch --show-current`, leituras/rg do preflight | Branch correta, cache staged preexistente, sem conflito impeditivo |
| Iniciar Docker Desktop local; `docker ps` | Banco/Auth/REST locais disponíveis |
| `npm install --save-exact @supabase/supabase-js@2.111.0` no Admin | SDK e lockfile atualizados |
| `npx supabase db reset --local` | PASS, 23 migrations e seeds 008/011 aplicadas somente localmente |
| `npx supabase test db` | PASS, 384 testes em 16 arquivos, incluindo 36 novos; baseline preservado |
| `npm test` no Admin Web | PASS final, 24/24, zero skips |
| `BINGO_ADMIN_INTEGRATION=1; npm run test:integration` | PASS, 1/1 real local; contas/fixtures temporárias removidas |
| `npm run build` | PASS, bundle inicial 314,80 kB, orçamento existente preservado, SDK lazy |
| `npx tsc --noEmit -p tsconfig.app.json` | PASS |
| `npx prettier --write` / `--check` nos arquivos Angular/testes alterados | PASS final |
| `PYTHONPATH=backend/src; .venv/Scripts/python.exe -m pytest backend/tests/test_admin_auth_foundation_migration.py -q` | PASS, 5/5 |
| `PYTHONPATH=backend/src; BINGO_RPC_TEST_DATABASE_URL` e `BINGO_MIGRATION_TEST_DATABASE_URL` locais; `.venv/Scripts/python.exe -m pytest backend/tests -q` | PASS final, 74/74, zero skips; 13 warnings preexistentes de chave JWT curta no legado |
| SQL de pre/postflight via `docker exec ... psql` | Constraints/FKs/grants/contagens confirmados, 23 migrations, zero fixtures Auth restantes |
| `git diff --check` e `git diff --check --cached` | PASS |
| `npm audit --json` no Admin | 1 advisory high preexistente em Angular Router 22.1.8 para SSR, GHSA-ff3f-86qr-9cv3; sem upgrade amplo nesta fatia SPA |

Os primeiros testes detectaram ausência de cabeçalho CORS na fixture de erro
Auth, preparação incompleta da CHECK na fixture Python e contagem de botão
antes de renderização em um teste existente. Foram corrigidas as fixtures/esperas,
mantendo os asserts. As execuções finais acima passaram.

O arquivo público local ignorado foi configurado exclusivamente com URL/anon
do Supabase local. O procedimento de criação de conta persistente está
documentado; nenhuma senha persistente foi criada ou versionada pela tarefa.
A conferência sem interceptação HTTP retornou configuração 200 e login pronto
sem alerts ou shell administrativo. O dev server de validação foi encerrado;
Supabase local permaneceu ativo. Use `npm start` para abrir novamente o Admin.

## 16. Não executado e limites

Não há target de lint Angular/ESLint configurado nesta aplicação; a análise
TypeScript e a compilação Angular foram executadas. As suítes Deno das Functions
não foram executadas (Deno ausente do PATH; Functions não alteradas). Auth/RLS
administrativo foi comprovado pela integração real nova e pgTAP. Mobile, Totem,
outros domínios e produção não foram testados nesta fatia, sem alterações neles.

A primeira execução do backend teve 11 skips por variáveis opt-in ausentes;
essas variáveis foram configuradas exclusivamente para localhost e a suíte
final passou com zero skips. Não resta teste obrigatório desta fatia pendente.

## 17–18. Compatibilidade e dados históricos

Não houve mapeamento de ADMIN/ADMIN_CONQUISTA/BINGO_ADMIN. A fixture SQL de
desenvolvimento foi reformulada explicitamente como A/B/C, com A global e B/C
escolares; não é conversão de dados existentes. FastAPI e suas fixtures/enums
SQLite continuam legados, sem promessa de autorização canônica A/B/C.
password_hash permanece para sua compatibilidade histórica e não é usado pelo Admin.

No banco local havia zero admins antes do reset, e zero auditorias/resgates;
nenhum dado administrativo antigo impediu a aplicação local. O ambiente remoto
não foi consultado. Se contiver qualquer role antiga, a migration abortará e
exigirá classificação manual por conta e preparação coordenada das constraints,
preservando IDs/histórico, antes de eventual promoção. Não há promoção automática
segura inferida do nome desses papéis.

## 19. Arquivos modificados/criados nesta tarefa

```text
apps/admin_web/.gitignore
apps/admin_web/README.md
apps/admin_web/package.json
apps/admin_web/package-lock.json
apps/admin_web/admin_flow.test.cjs
apps/admin_web/admin_auth.test.cjs
apps/admin_web/admin_auth.integration.test.cjs
apps/admin_web/test/supabase-fixture.cjs
apps/admin_web/public/supabase-config.example.json
apps/admin_web/src/app/app.ts
apps/admin_web/src/app/core/admin-store.ts
apps/admin_web/src/app/core/admin-context.ts
apps/admin_web/src/app/core/admin-auth.service.ts
apps/admin_web/src/app/core/supabase-client.ts
apps/admin_web/src/app/features/access.component.ts
apps/admin_web/src/app/layout/admin-shell.component.ts
backend/tests/test_admin_auth_foundation_migration.py
database/migrations/023_admin_auth_foundation.sql
database/seeds/004_seed_admins.sql
supabase/migrations/20260930120000_admin_auth_foundation.sql
supabase/tests/admin_auth_foundation.sql
docs/STATUS_12-08.md
docs/admin-supabase-auth-session.md
docs/admin-auth-foundation-report-2026-09-30.md
```

Fora do Git: configuração pública local em
`apps/admin_web/public/supabase-config.json`; build/cache gerados pela validação.
Os 14 arquivos staged de cache anteriores à tarefa não são alterações autorais
desta entrega. Nenhum arquivo desta feature foi staged.

## 20. Git status final

Fotografia do working tree ao encerrar a tarefa, abaixo. `A` de cache é staged
preexistente; ` M` e `??` fora do cache correspondem à implementação local.

```text
A  apps/admin_web/.angular/cache/22.1.8/admin_web/.tsbuildinfo
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/@angular_common.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/@angular_core.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/@angular_platform-browser.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/@angular_router.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/@angular_router.js.map
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/_metadata.json
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/common-COyYoF61.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/common-COyYoF61.js.map
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/core-Gi4yMOCN.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/core-Gi4yMOCN.js.map
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/package.json
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/platform-browser-BpBtVwPy.js
A  apps/admin_web/.angular/cache/22.1.8/admin_web/vite/deps/platform-browser-BpBtVwPy.js.map
 M apps/admin_web/.gitignore
 M apps/admin_web/README.md
 M apps/admin_web/admin_flow.test.cjs
 M apps/admin_web/package-lock.json
 M apps/admin_web/package.json
 M apps/admin_web/src/app/app.ts
 M apps/admin_web/src/app/core/admin-store.ts
 M apps/admin_web/src/app/features/access.component.ts
 M apps/admin_web/src/app/layout/admin-shell.component.ts
 M database/seeds/004_seed_admins.sql
 M docs/STATUS_12-08.md
?? apps/admin_web/admin_auth.integration.test.cjs
?? apps/admin_web/admin_auth.test.cjs
?? apps/admin_web/public/supabase-config.example.json
?? apps/admin_web/src/app/core/admin-auth.service.ts
?? apps/admin_web/src/app/core/admin-context.ts
?? apps/admin_web/src/app/core/supabase-client.ts
?? apps/admin_web/test/
?? backend/tests/test_admin_auth_foundation_migration.py
?? database/migrations/023_admin_auth_foundation.sql
?? docs/admin-auth-foundation-report-2026-09-30.md
?? docs/admin-supabase-auth-session.md
?? supabase/migrations/20260930120000_admin_auth_foundation.sql
?? supabase/tests/admin_auth_foundation.sql
```

## 21. Confirmação de escopo externo

Nenhuma ação remota no Supabase ou Git foi executada. Não houve commit, push,
PR, merge, deploy de site/Function, migration hospedada, alteração de bingo-dev
ou produção. Todos os resets, provisionamentos Auth e writes de domínio foram
no Supabase/PostgreSQL local. A instalação da dependência usou o registro npm.
