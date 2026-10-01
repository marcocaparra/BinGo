# Admin Web V1 — gestão escolar local

Implementado em `2026-09-30`, na branch `feature/admin-school-management-foundation`.
Somente working tree e Supabase local. O contrato funcional permanece intacto.

## Preflight e decisões

Foram consultados, em ordem, STATUS, contrato Admin, modelo de banco, documentos
Auth/RLS, migration 023, schema/migrations de alunos/turmas, seeds, pgTAP, Angular,
testes de navegador e FastAPI legado. O schema real do Supabase local confirmou
23 migrations, alunos sem matrícula/email e turmas sem status. RLS continha as
cinco policies existentes; os clientes tinham somente grants de leitura de
colunas próprias do Mobile. Não foi encontrado conflito impeditivo.

A autoridade segue Auth → `admins.auth_user_id` → admin ACTIVE → role/escola
derivados no PostgreSQL. `get_my_admin_context_v1()` e a fundação de sessão 023
não precisaram mudar. ADMIN_A não recebe uma escola implícita; sua assistência
à implantação permanece futura, sem alterar a permissão funcional do contrato.

## Schema incremental

Os dois trilhos têm conteúdo executável idêntico:

- `database/migrations/024_admin_school_management_foundation.sql`;
- `supabase/migrations/20260930130000_admin_school_management_foundation.sql`.

Nenhuma migration histórica foi editada. Não há recriação de tabelas, mudança de
IDs, remoção de aluno ou reescrita de histórico. Seeds não precisaram mudar.

| Campo/regra | Resultado |
| --- | --- |
| `students.registration` | text nullable; RA/matrícula administrativa |
| `students.email` | text nullable; email institucional independente de Auth |
| `students_school_registration_unique` | UNIQUE index `(school_id, registration) WHERE registration IS NOT NULL` |
| `students_registration_normalized_check` | permite NULL; rejeita branco e whitespace nas extremidades |
| `students_email_nonblank_check` | permite NULL; rejeita string vazia ou só whitespace |
| `students.status` | CHECK ACTIVE/INACTIVE preexistente preservada |
| `students.class_id`, `school_id` | UUID, NOT NULL e FKs RESTRICT preexistentes |
| `students.auth_user_id`, `pin_hash`, `is_activated`, saldo | responsabilidades e defaults preservados |
| `classes.segment`, `grade`, `name` | text NOT NULL, sem enum inventado |
| `classes.points_class_balance` | default zero e integridade preexistentes |
| `classes.status` | não existe; também removido das telas/formulários reais |

Matrículas preservam zeros à esquerda, caixa e whitespace interno. RPCs removem
whitespace das extremidades antes de gravar; a CHECK exige forma normalizada
também em inserts privilegiados. `001` e `001` conflitam na mesma escola, mas
podem coexistir em escolas distintas. `001` e `001a` são valores diferentes.
Históricos recebem NULL nos dois novos campos; nenhuma identidade é inventada.
Email não cria nem vincula usuário Auth. RPCs rejeitam email branco quando
informado; o formulário opcional vazio envia NULL. Não foi criada uma regra
adicional de unicidade de email ou enum de série/segmento.

## RPCs e autorização

| RPC | Parâmetros | Resultado | Permissão |
| --- | --- | --- | --- |
| `get_admin_students_v1()` | nenhum | student_id, name, email, registration, class_id, class_name, status, points_student_balance, class_points_balance | B/C ativos, própria escola |
| `get_admin_classes_v1()` | nenhum | class_id, segment, grade, name, points_class_balance, student_count | B/C ativos, própria escola |
| `create_admin_student_v1` | p_name text, p_email text nullable, p_registration text, p_class_id uuid, p_status text default ACTIVE | UUID criado | B ativo |
| `update_admin_student_v1` | p_student_id uuid, p_name text, p_email text nullable, p_registration text, p_class_id uuid, p_status text | UUID atualizado | B ativo |
| `create_admin_class_v1` | p_segment text, p_grade text, p_name text | UUID criado | B ativo |
| `update_admin_class_v1` | p_class_id uuid, p_segment text, p_grade text, p_name text | UUID atualizado | B ativo |

`require_school_admin_v1(boolean)` é helper interno, sem EXECUTE para nenhum papel
cliente. Resolve Auth, vínculo, ACTIVE, role B/C, escola e B para escrita.
Todas as seis RPCs são SECURITY DEFINER com `search_path = ''`, referências
qualificadas e EXECUTE somente para authenticated. PUBLIC/anon/service_role não
executam. Não há parâmetros de escola, role ou ator, nem de saldo/XP/PIN/Auth.

O aluno/turma alvo é localizado dentro da escola do principal. O destino de turma
também deve pertencer à escola. Alvos externos ou inexistentes resultam no mesmo
erro de acesso. Os updates bloqueiam a linha alvo e a validação de turma usa
lock compartilhado. RLS, policies e grants de tabela permanecem inalterados,
inclusive nenhuma escrita direta em students/classes/admins/audit_logs e nenhum
SELECT amplo escolar. C recebe lookup de turmas para leitura, sem nova view.

Erros previsíveis: `42501` acesso negado; `22023` entrada inválida;
`23505 / ADMIN_REGISTRATION_CONFLICT` matrícula repetida. O índice único é a
autoridade final sob concorrência; não existe checagem select-then-insert como
única barreira. Outros erros de unicidade são repropagados sem falsa atribuição.

## Auditoria e preservação

Cada mutation grava um evento `ADMIN_STUDENT_CREATED_V1`,
`ADMIN_STUDENT_UPDATED_V1`, `ADMIN_CLASS_CREATED_V1` ou `ADMIN_CLASS_UPDATED_V1`
em `audit_logs`, com `actor_type=ADMIN`, `actor_id=admins.id` e escola derivados.
Criações guardam entidade e campos mínimos. Updates guardam old/new dos cinco
campos administrativos do aluno ou dos três campos estruturais da turma.
Turma/status antigos e novos são explícitos, sem snapshots técnicos ou hashes.

Uma edição que muda turma/status é representada por uma auditoria de update
contendo essas mudanças, sem eventos redundantes. Falha na auditoria reverte a
mutation inteira. Duplicação de matrícula não deixa evento parcial. Novos alunos
usam defaults: saldo zero, PIN/Auth nulos, is_activated false. Turmas usam XP zero.
Somente o class_id atual do aluno muda; o teste preserva a fotografia completa
de um depósito anterior. Missões/completions/Jornada não são atualizadas.

## Angular e isolamento dos mocks

- `core/admin-school.repository.ts`: tipos reais, fotografia escolar central,
  load/error/loaded (listas vazias apresentam empty), operações e erros de save;
  chama apenas as seis RPCs e recarrega a fotografia depois de salvar.
- `features/management.component.ts`: alunos B editáveis/C somente leitura e
  turmas B reais; track por UUID, RA/email nulos históricos explícitos, saldo/XP
  somente leitura, loading/empty/error com retry.
- `features/admin-school-dialog.component.ts`: formulário real reutilizando
  classes visuais existentes; email opcional type=email, RA type=text, seleção
  class_id, status do aluno, segmento/série/nome livres da turma.
- `layout/admin-shell.component.ts`: indicador de dados escolares reais e
  ausência de seletor demonstrativo apenas nessas duas views; compõe o diálogo.
- `shared/entity-row.component.ts`: status opcional, sem tag fictícia em turma.
- `core/admin-store.ts`, `shared/operation-dialog.component.ts` e
  `features/overview.component.ts`: removidos caminhos de mutation demonstrativa
  de aluno/turma; os mocks auxiliares restantes chamam-se demoStudents/demoClasses
  e alimentam somente demonstrações de dashboard/solicitações.

Sessão/role continuam exclusivamente no AdminAuthService; a matriz admin-access
e a navegação por role permanecem iguais. A fotografia e o diálogo reais são
limpos ao perder/trocar contexto, e respostas pendentes são invalidadas.
Falha não usa mocks. Mutation com sucesso fecha diálogo e consulta novamente;
falha da recarga mostra erro de leitura, sem fingir rollback do save confirmado.

Demais dados/ações continuam demonstrativos e identificados: visão geral,
escolas, administradores, pendências/solicitações de troca, descartes, ajuda,
produtos, resgates, Missões, máquinas e economia. As demonstrações de aprovação
de solicitação não alteram alunos reais. Não houve redesenho, CSS novo ou mudança
de negócio nesses domínios. FastAPI não recebe endpoints nem mudanças de modelos.
Mobile e seus arquivos não foram alterados.

## Reprodução e validação local

Configuração pública/login seguem `admin-supabase-auth-session.md`. Provisionar
manualmente usuários de desenvolvimento pelo Auth local/Studio e vincular admins
B/C à escola, sem SQL em auth.users e sem contas/credenciais reais versionadas.
É preciso existir ao menos uma turma da escola para cadastrar aluno; B pode
criá-la pela tela Turmas. Alunos antigos com RA NULL podem ser consultados; uma
edição administrativa exige informar matrícula aprovada pela escola.

Comandos executados a partir de Software, ou do diretório indicado:
O servidor Angular foi executado em um terminal separado durante as suítes de
navegador e integração; depois da validação foi encerrado.

```powershell
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js test db supabase/tests/admin_school_management.sql
node node_modules/supabase/dist/supabase.js test db
$env:PYTHONPATH='backend/src'
$env:BINGO_RPC_TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
$env:BINGO_MIGRATION_TEST_DATABASE_URL=$env:BINGO_RPC_TEST_DATABASE_URL
.venv/Scripts/python.exe -m pytest backend/tests -q
# Em apps/admin_web:
npm run build
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json
node node_modules/@angular/cli/bin/ng.js serve --host 127.0.0.1 --port 8106
npm test
$env:BINGO_ADMIN_INTEGRATION='1'
npm run test:integration
# Prettier --write e --check nos arquivos Angular/testes/package alterados.
# Em Software:
git diff --check
git status --short
```

| Validação | Resultado |
| --- | --- |
| Reset Supabase local | 24 migrations e seeds aplicadas |
| pgTAP completo | 467 testes, 17 arquivos, aprovados; 83 novos desta fatia |
| Backend completo | 78 aprovados, sem skips; quatro novos, incluindo criação/edição concorrentes |
| Angular/navegador | 31 aprovados, sem skips; sete novos, incluindo layout estreito |
| Integração real local | 2 aprovadas, sem skips; Auth anterior e novo smoke B/C |
| Build / TypeScript / Prettier / diff-check | aprovados |

O smoke cria usuários Auth e escola/turmas efêmeros somente via API/local SQL,
usa anon no browser, valida contexto/login/refresh, lista real, cria/edita aluno,
muda turma/status, cria/edita turma, comprova auditoria e campos protegidos, nega
escola forjada/externa, testa as quatro escritas rejeitadas para C e revalida
ACTIVE server-side. O finally remove as fixtures e usuários Auth. Chave técnica
local só existe no processo Node de provisionamento, nunca no Angular.

As primeiras execuções encontraram erros de montagem de fixture SQL (VALUES
sem espaço no pgTAP e depósito sem snapshot de categoria) e referência renomeada
no dashboard; foram corrigidos e as suítes completas repetidas com aprovação.
O backend emite 13 avisos preexistentes de chave HMAC curta nas fixtures JWT
legadas. Não há suite ESLint configurada no projeto; análise disponível foi
build Angular/TypeScript. Testes Flutter/Edge Functions não foram executados:
nenhum arquivo dessas aplicações mudou, e suas fronteiras PostgreSQL continuam
cobertas pelo pgTAP completo. Não houve skip inesperado.

## Limites e promoção

Sem integração de solicitação C, CRUD de administradores/escolas/Auth users,
outros domínios, dashboard real, exports, Mobile, Totem, Orange Pi ou simulator.
Não há paginação nesta fatia; as RPCs devolvem a fotografia da escola inteira.
Sem nome real da escola, porque gestão/leitura do domínio schools fica fora
desta entrega; a UI identifica a escola vinculada pelo contexto de sessão.

023 e 024 permanecem somente locais. O bloqueio de promoção de 023 para papéis
históricos ADMIN/ADMIN_CONQUISTA/BINGO_ADMIN permanece: classificação manual
por conta, sem conversão heurística. 024 não inventa valores para históricos e
não acrescenta outro bloqueio de migração de dados. Toda promoção futura exige
preflight próprio; nada hospedado foi consultado ou alterado nesta tarefa.
Não houve commit, push, PR, merge, deploy ou migration remota.

## Arquivos e fotografia do working tree

O preflight encontrou working tree limpo. A entrega contém 11 arquivos existentes
modificados e nove arquivos novos, sem alterações staged. `git status --short`
na branch `feature/admin-school-management-foundation`:

```text
 M apps/admin_web/admin_flow.test.cjs
 M apps/admin_web/package.json
 M apps/admin_web/src/app/core/admin-store.ts
 M apps/admin_web/src/app/features/management.component.ts
 M apps/admin_web/src/app/features/overview.component.ts
 M apps/admin_web/src/app/layout/admin-shell.component.ts
 M apps/admin_web/src/app/shared/entity-row.component.ts
 M apps/admin_web/src/app/shared/operation-dialog.component.ts
 M apps/admin_web/test/supabase-fixture.cjs
 M docs/STATUS_12-08.md
 M docs/admin-supabase-auth-session.md
?? apps/admin_web/admin_school.integration.test.cjs
?? apps/admin_web/admin_school.test.cjs
?? apps/admin_web/src/app/core/admin-school.repository.ts
?? apps/admin_web/src/app/features/admin-school-dialog.component.ts
?? backend/tests/test_admin_school_management.py
?? database/migrations/024_admin_school_management_foundation.sql
?? docs/admin-school-management-foundation.md
?? supabase/migrations/20260930130000_admin_school_management_foundation.sql
?? supabase/tests/admin_school_management.sql
```

Após cleanup, o Supabase local contém 24 migrations, 70 alunos seed, sete turmas,
zero admins/usuários Auth/auditorias de smoke e zero matrículas/emails inventados
nos históricos. As contas persistentes de teste manual precisam ser provisionadas
localmente pelo procedimento documentado. Nenhum arquivo de secrets/configuração
real foi adicionado ao Git.
