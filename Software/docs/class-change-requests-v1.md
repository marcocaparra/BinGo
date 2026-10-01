# Troca de turma administrativa V1 — implementação local

Entrega de `2026-09-30`, branch `feature/admin-school-management-foundation`.
Preflight encontrou working tree limpo, migrations 023/024 como últimas e nenhum
modelo/RPC persistido posterior de troca. Não houve conflito documental.

## Regras funcionais do contrato

Fonte: `admin-contract-v1.md`, seções Troca de turma e Pendências da escola.
B pode mudar turma diretamente; C solicita e o aluno permanece na origem até
aprovação B. B aprova/rejeita; C cancela somente solicitação própria pendente.
A não participa. Várias solicitações por aluno são permitidas, históricos
terminais permanecem e uma solicitação antiga não sobrescreve turma mais recente.

## Decisões técnicas desta implementação

Migrations equivalentes e incrementais, sem editar 023/024:

- `database/migrations/025_class_change_requests_v1.sql`;
- `supabase/migrations/20260930140000_class_change_requests_v1.sql`.

`class_change_requests` possui id UUID PK fornecido pelo cliente; school_id,
student_id, source_class_id, destination_class_id e requested_by_admin_id UUID
NOT NULL; status text NOT NULL default PENDING; resolved_by_admin_id UUID nullable;
created_at timestamptz NOT NULL default now() e resolved_at timestamptz nullable.
As seis FKs são RESTRICT, sem cascade. CHECK exige origem diferente de destino,
status PENDING/APPROVED/REJECTED/CANCELED, PENDING com ambos campos de resolução
nulos e terminais com ambos preenchidos. Índices atendem escola/autor por data
e aluno. Não há unicidade por aluno nem status STALE persistido.

RLS habilitada sem policies/grants diretos para browser. As cinco policies Mobile
e os grants anteriores permanecem intactos; agora há 20 tabelas locais com RLS.
RPCs SECURITY DEFINER, search_path vazio, EXECUTE somente authenticated,
explicitamente revogado de PUBLIC/anon/service_role. Reutilizam
`require_school_admin_v1(false)` para Auth/vínculo/ACTIVE/escola e validam role
específica. `resolve_class_change_request_v1(uuid,text)` é helper interno sem
EXECUTE para clientes; o browser não escolhe status de decisão.

| RPC | Contrato de entrada | Permissão |
| --- | --- | --- |
| get_class_change_requests_v1 | nenhum | B: escola; C: somente próprias |
| create_class_change_request_v1 | p_request_id, p_student_id, p_destination_class_id UUID | C ativo, própria escola |
| approve_class_change_request_v1 | p_request_id UUID | B ativo, própria escola |
| reject_class_change_request_v1 | p_request_id UUID | B ativo, própria escola |
| cancel_class_change_request_v1 | p_request_id UUID | C ativo, autor |

Mutations devolvem o UUID persistido. A leitura fornece request/student IDs,
nome/matrícula do aluno, IDs/nomes de origem/destino/turma atual, status, is_stale,
solicitante e resolvedor (ID/nome), created_at/resolved_at. Não há PIN, Auth ID,
hash, email de administrador ou credenciais. `is_stale` é calculado somente para
PENDING com turma atual diferente da origem.

Criação usa advisory transaction lock sobre hash de 64 bits do request UUID para
serializar inclusive antes da linha existir. Colisão de hash apenas serializa
UUIDs distintos; a PK continua sendo a autoridade de identidade. Um registro
existente compara escola/autor/aluno/destino: replay idêntico retorna o mesmo UUID
inclusive após conclusão, sem recapturar origem ou auditar. Divergência gera
23505 / CLASS_CHANGE_REQUEST_ID_CONFLICT. Na primeira criação, o aluno é lido
FOR UPDATE e a origem é capturada server-side; origem/destino são validados na
escola e bloqueados FOR SHARE. A mesma trava de aluno é usada pela edição B de 024.

Decisões bloqueiam primeiro request, depois aluno. O lock de request serializa
approve/reject/cancel. Um terminal com a mesma decisão retorna seu UUID preservando
o resolvedor original; decisões incompatíveis geram P0001 /
CLASS_CHANGE_DECISION_CONFLICT. Roles/escola/autor continuam validados antes do
replay; outro C nunca cancela. Uma aprovação PENDING compara turma atual com
source_class_id sob lock: divergência gera P0001 / CLASS_CHANGE_REQUEST_STALE,
sem mutation. Um retry de APPROVED posterior a outra troca também não reexecuta
a alteração. Rejeição/cancelamento podem concluir PENDING stale sem mudar aluno.
Entrada inválida gera 22023; acesso negado, 42501. Conflitos semânticos P0001
usam o padrão SQL do projeto e são apresentados explicitamente pela aplicação.

## Auditoria e preservação

Criação e transições gravam CLASS_CHANGE_REQUEST_CREATED_V1,
CLASS_CHANGE_REQUEST_APPROVED_V1, CLASS_CHANGE_REQUEST_REJECTED_V1 ou
CLASS_CHANGE_REQUEST_CANCELED_V1, com ator ADMIN derivado, request/aluno/origem/
destino, status e turma old/new pertinentes. Um único evento representa toda a
aprovação; retries não duplicam logs. Aluno, request e auditoria são da mesma
transação: falha de audit reverte tudo. Aprovação altera **somente class_id**,
sem saldos, PIN, Auth, ativação, updated_at ou reescrita de depósitos/XP histórico,
Missões/Jornada/resgates. Não há deleção de solicitações pela aplicação.

## Angular

`core/class-change-requests.repository.ts` centraliza leitura/mutations/estado,
UUID e payload de retry, limpa contexto em logout/restauração e invalida respostas
antigas. UUID é crypto.randomUUID(); retry do formulário aberto conserva payload
e UUID. Mudar a intenção do formulário gera outro UUID. Recarregar o navegador
descarta o rascunho; solicitações persistidas continuam na leitura autoritativa.
Não existe fallback para mocks ou armazenamento local confiado de role/escola.

`features/class-requests.component.ts` reutiliza layout, EntityRow e StatePanel:
C lista/cria/cancela usando alunos/turmas reais e UUIDs; B analisa/aprova/rejeita.
Loading/empty/error/submitting/conflito são explícitos. Stale mostra turma atual,
desabilita aprovação e mantém rejeição. Conflito vindo do backend refaz leitura.
Após mutations, solicitações e AdminSchoolRepository são recarregados; inclusive
alunos/turmas após approve. Nenhum source/school/admin/status vai no payload.

Management compõe o bloco real em Pendências e a view Solicitações; o shell remove
o seletor demonstrativo nessas views e identifica Pendências como mista. O bloco
de resgates continua demonstrativo, identificado separadamente. AdminStore e
OperationDialog perderam classRequests e todos os caminhos request-create/review/
cancel; demoStudents, usado somente na antiga solicitação, também foi removido.
DemoClasses permanece no dashboard demonstrativo. Nenhum outro domínio foi
integrado; o dashboard ainda contém seus exemplos estáticos identificados.

## Validação e reprodução

Configuração pública e provisionamento manual local seguem
`admin-supabase-auth-session.md`. Os testes reais usam somente URLs loopback,
criam Auth users efêmeros pela API local e limpam usuários e domínio no finally.
Chave técnica fica apenas no processo Node de fixture; o browser recebe anon.

Comandos na raiz Software:

```powershell
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js test db supabase/tests/class_change_requests_v1.sql
node node_modules/supabase/dist/supabase.js test db
$env:PYTHONPATH='backend/src'
$env:BINGO_RPC_TEST_DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:54322/postgres'
$env:BINGO_MIGRATION_TEST_DATABASE_URL=$env:BINGO_RPC_TEST_DATABASE_URL
.venv/Scripts/python.exe -m pytest backend/tests -q
```

Em apps/admin_web, com ng serve em outro terminal:

```powershell
node node_modules/@angular/cli/bin/ng.js serve --host 127.0.0.1 --port 8106
npm test
node --test class_requests.test.cjs
$env:BINGO_ADMIN_INTEGRATION='1'
npm run test:integration
npm run build
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json
# Prettier --write/--check nos onze arquivos Angular/testes/package alterados.
```

| Suíte/check | Resultado local |
| --- | --- |
| Supabase reset | 25 migrations e seeds aplicadas |
| pgTAP completo | 547 aprovados / 18 arquivos; 80 novos de solicitações |
| Backend completo | 87 aprovados; nove novos, incluindo oito provas concorrentes |
| Admin/browser completo | 38 aprovados; sete novos de solicitações |
| Integração Auth/RPC/Angular | três testes aprovados, incluindo os três cenários novos abaixo |
| Build, TypeScript, Prettier, git diff --check | aprovados |

Concorrência cobre criação idêntica/divergente, approve/reject/cancel em pares e
em disputa tripla, dois requests tentando aprovar o mesmo aluno e criação
disputando lock com edição direta B. Provas SQL cobrem constraints/RLS/grants,
isolamento/roles, autoria, idempotência, stale, audit rollback e depósito completo
preservado. O baseline mantém 45 asserts; somente o total legítimo de tabelas com
RLS foi atualizado de 19 para 20, sem enfraquecer checks de policies/grants.

Smoke novo: C cria → B aprova → aluno muda → C vê APPROVED; C cria A→B → B muda
A→C diretamente → approve antigo conflita → aluno permanece C (e B pode rejeitar);
C cria → C cancela → B não consegue aprovar. Também prova retries sem logs novos,
campos protegidos intactos, histórico de depósito preservado e leitura direta
negada. Fixtures foram removidas. Nenhum skip ou falha final. Permanecem 13 avisos
preexistentes de JWT HMAC curta no FastAPI de teste. Flutter/Edge Functions não
foram alterados nem executados; não há target ESLint configurado.

023, 024 e 025 continuam **somente locais**, sem promoção ao bingo-dev. Não houve
commit/push/PR/merge/deploy/migration remota, nem consulta a ambiente hospedado.

Fotografia final: nove arquivos modificados e nove novos, sem staged. `git status --short`:

```text
 M apps/admin_web/admin_flow.test.cjs
 M apps/admin_web/package.json
 M apps/admin_web/src/app/core/admin-store.ts
 M apps/admin_web/src/app/features/management.component.ts
 M apps/admin_web/src/app/layout/admin-shell.component.ts
 M apps/admin_web/src/app/shared/operation-dialog.component.ts
 M apps/admin_web/test/supabase-fixture.cjs
 M docs/STATUS_12-08.md
 M supabase/tests/authorization_rls_baseline.sql
?? apps/admin_web/class_requests.integration.test.cjs
?? apps/admin_web/class_requests.test.cjs
?? apps/admin_web/src/app/core/class-change-requests.repository.ts
?? apps/admin_web/src/app/features/class-requests.component.ts
?? backend/tests/test_class_change_requests.py
?? database/migrations/025_class_change_requests_v1.sql
?? docs/class-change-requests-v1.md
?? supabase/migrations/20260930140000_class_change_requests_v1.sql
?? supabase/tests/class_change_requests_v1.sql
```

Após cleanup: 25 migrations, 70 alunos/sete turmas seed preservados e zero
requests/admins/auditorias/usuários Auth de teste restantes. Servidor Angular
de validação encerrado; Supabase local permanece disponível.
