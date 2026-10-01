# Admin V1 — escolas e identidades administrativas

## Regras oficiais

O [contrato Admin V1](admin-contract-v1.md) define A global, B/C escolares, gestão global de contas por A e gestão somente dos C da própria escola por B. C não administra contas. Contas são inativadas, nunca apagadas; auto-inativação é proibida e deve ser preservado ao menos um A ACTIVE.

Esta fatia integra somente criação/listagem de escolas e gestão de identidades administrativas. Escola continua com UUID, nome e timestamps. Não se criam cidade, endereço, status ou implantação, nem unicidade global de nome. Dashboard, máquinas, Missões e demais configurações econômicas continuam demonstrativos.

## Migrations e contratos

Trilhos equivalentes, sem editar 023–027:

- `database/migrations/028_admin_structure_management_v1.sql`;
- `supabase/migrations/20261001130000_admin_structure_management_v1.sql`.

Não há alteração das colunas de admins/schools/audit_logs, IDs, FKs ou dados históricos. A única tabela nova, `admin_structure_creation_receipts`, é um recibo técnico privado de criação por tipo/UUID, ator derivado, payload original e timestamp. RLS é fail-closed, sem grants de cliente ou policies. Um recibo original evita confundir replay com o estado posteriormente editado de uma conta.

| RPC                            | Entrada                                                                  | Permissão/resultado                                                                                          |
| ------------------------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `get_admin_schools_v1()`       | Nenhuma                                                                  | A ACTIVE; school_id/name e contagens reais de alunos, turmas, admins e máquinas                              |
| `create_admin_school_v1(...)`  | p_school_id UUID, p_name                                                 | A ACTIVE; UUID confirmado                                                                                    |
| `get_managed_admins_v1()`      | Nenhuma                                                                  | A global; B somente C da própria escola; admin_id/name/email/role/school_id/school_name/status/access_linked |
| `create_managed_admin_v1(...)` | p_admin_id UUID, p_name, p_email, p_role, p_school_id nullable, p_status | A cria A/B/C; B cria somente C, escola derivada                                                              |
| `update_managed_admin_v1(...)` | p_admin_id, p_name, p_email, p_status                                    | A global ou B sobre C da própria escola; UUID confirmado                                                     |

Na criação por A, school_id é a escolha explícita da entidade escolar: NULL obrigatório para A; escola existente obrigatória para B/C. Na criação por B, o parâmetro deve ser NULL e o backend deriva a escola do ator; enviar escola, mesmo a própria, é recusado. Atualização não aceita role/escola/Auth/hash/ator. Nome/email são normalizados nas extremidades e validados; email preserva a unicidade existente, sem inventar equivalência case-insensitive.

Todas as RPCs derivam `auth.uid() → admins.auth_user_id`, exigem ACTIVE e usam SECURITY DEFINER/search_path vazio. PUBLIC/anon/service_role não executam; somente authenticated tem EXECUTE. O helper interno não é executável pelo cliente. Não há DELETE, edição estrutural de escola, leitura ampla de tabelas ou escrita direta do browser. A policy/colunas de leitura Mobile da própria escola continuam intactas; Admin utiliza exclusivamente RPC.

## Identidade de domínio versus acesso

Criar uma identidade em admins **não cria acesso Auth**. Auth_user_id e password_hash ficam NULL; a RPC não recebe esses campos, senha ou convite. A listagem devolve somente o boolean `access_linked`, sem UUID Auth ou hash.

O Angular mostra “Sem vínculo de acesso” e informa que a conta não pode entrar antes do vínculo. A edição de email em admins também não altera o email de login do Auth já vinculado. O provisionamento de usuário Auth/vínculo continua sendo uma operação confiável separada, sem ferramenta nova nesta fatia. O primeiro A também exige bootstrap confiável conforme [Auth Admin local](admin-supabase-auth-session.md); reset não inventa conta ou credencial. Testes criam usuários somente na API Auth local, com cleanup; o browser recebe exclusivamente configuração pública.

## Idempotência, último A e auditoria

Criação recebe UUID do browser. Retry com mesmo ator, UUID e payload normalizado retorna a mesma entidade sem duplicar auditoria. Reutilização divergente conflita (23505); o recibo não muda após edição de nome/email/status. Escola existente sem recibo não é adotada como uma criação nova. UUIDs por tipo são independentes; nomes de escolas podem se repetir.

As mutations de contas adquirem o mesmo advisory transaction lock **antes** de resolver o ator. O ator é revalidado após a espera e bloqueado com FOR UPDATE; depois bloqueia-se o alvo. A inativação do último A é recusada (55000 `MANAGED_ADMIN_LAST_ACTIVE_A`), assim como auto-inativação (`MANAGED_ADMIN_SELF_DEACTIVATION`). A disputa A1 inativa A2 × A2 inativa A1 tem apenas um vencedor; o outro encontra o próprio ator INACTIVE (42501). Em REPEATABLE READ, o lock do ator detecta o snapshot antigo e aborta com 40001, preservando a mesma integridade.

Estas proteções estão nas operações SQL autorizadas, com escrita direta negada. Manutenção/fixture executada pelo proprietário do banco não é um fluxo do Admin. Não se oferece exceção ou bypass ao cliente. Reativação por outro administrador autorizado continua permitida. Update com nome/email/status já iguais é no-op, sem mudar timestamp ou duplicar audit log.

Auditoria transacional:

- `ADMIN_SCHOOL_CREATED_V1`: global (school_id NULL), escola criada em metadata;
- `MANAGED_ADMIN_CREATED_V1`: NULL para A; escola da entidade para B/C;
- `MANAGED_ADMIN_UPDATED_V1`: mesmo escopo da entidade e old/new de nome/email/status, cobrindo ativação/inativação.

Ator nunca vem do formulário. Erro de auditoria reverte entidade/recibo/mutation. Email duplicado é 23505 `MANAGED_ADMIN_EMAIL_CONFLICT`; UUID divergente usa `ADMIN_SCHOOL_ID_CONFLICT` ou `MANAGED_ADMIN_ID_CONFLICT`. Histórico de outros domínios não é modificado.

## Angular e reprodução

`AdminStructureRepository` concentra RPCs, estados e refetch. Mudança de sessão elimina listas/operação/feedback e descarta respostas atrasadas. Telas usam UUID, loading/empty/error/submitting, conflitos e retry, sem fallback. B não consulta escolas globais e não escolhe role/escola. Edição preserva role/escola; auto-inativação fica indisponível na UI e também é recusada pelo banco.

Os formulários antigos demo de escola/admin foram removidos. O dashboard mantém sua fotografia explicitamente demonstrativa em `demoSchools`; não foi integrado nesta fatia.

Na raiz Software, com Supabase/Docker local iniciado:

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

Executar reset, pgTAP, backend e integração em sequência no banco compartilhado. Integração somente loopback, com usuários efêmeros; corridas reais de contas são exercidas dentro dos testes específicos. A 028 e as migrations 023–027 continuam sem promoção ao bingo-dev. Não houve commit, push, PR, deploy ou ação remota.

## Validação local — 2026-10-01

| Comando/suíte                                        | Resultado                                                                                      |
| ---------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `supabase db reset --local` via CLI Node             | Reset final isolado passou, 28 migrations e seeds existentes                                   |
| `supabase test db` via CLI Node                      | 21 arquivos, 590 verificações; 14 novas                                                        |
| `pytest backend/tests -q` com ambiente local acima   | 176 passaram; 25 novas, incluindo quatro corridas A × A e rollback nas três mutations          |
| `npm test`                                           | 66 browser passaram; onze novas de estrutura; asserts de composição/responsividade preservados |
| `BINGO_ADMIN_INTEGRATION=1 npm run test:integration` | Seis smokes reais passaram, um novo de estrutura A/B/C                                         |
| `npm run build`                                      | Passou                                                                                         |
| `tsc --noEmit -p tsconfig.app.json`                  | Passou                                                                                         |
| Prettier `--check` nos arquivos alterados            | Passou                                                                                         |
| `git diff --check`                                   | Passou                                                                                         |

Nenhum skip ou falha nas execuções finais. As 13 advertências JWT vêm dos testes FastAPI legados. Não há target lint Angular nem Ruff/Black configurados/disponíveis. Flutter/Edge Functions não foram executados porque não foram alterados.

Falhas iniciais resolvidas: uma execução pytest sem PYTHONPATH não encontrou app; a execução configurada e a suíte completa passaram. Um seletor browser parcial confundiu nome do administrador com o nome da escola no subtitle; passou a selecionar texto exato. Asserts antigos consultavam diálogos antes de renderizar; esperas explícitas foram adicionadas mantendo os mesmos asserts. Os testes de renovação A/B passaram a aguardar a restauração do contexto Auth existente antes de retornar à view, onde confirmam nova consulta autoritativa; o fluxo Auth não foi alterado. A suíte browser limita arquivos simultâneos a dois para reduzir contenção local. Um segundo reset foi iniciado antes de o anterior terminar e interrompeu a conexão; foi cancelado, e o reset final isolado mais as suítes completas confirmaram o estado íntegro.

Smoke novo: A autenticado cria escola por Angular e confirma replay por RPC; cria C sem vínculo/credencial/Auth user; inativa C e confirma no-op sem duplicar auditoria; cria A global sem vínculo; auto-inativação é recusada. B autenticado lista apenas C locais e reativa C, sem editar role/escola; gestão global é recusada. C não tem navegação nem RPC de gestão. Cleanup remove identidades/recibos/auditoria de fixture e usuários Auth locais. Os cinco smokes anteriores de Auth/escola/troca/BinBazar/teto continuaram passando.
