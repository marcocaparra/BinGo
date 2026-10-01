# Admin Web V1 — Auth e sessão local

Implementado em `2026-09-30`, na branch `feature/admin-auth-foundation`.

## Fronteira implementada

`Supabase Auth → auth.uid() → admins.auth_user_id → get_my_admin_context_v1() → sessão Angular`.

Supabase Auth prova a identidade; `admins` define o principal de domínio. O banco
resolve role, escola e status. Angular apresenta a experiência A/B/C somente após
receber um contexto válido e ACTIVE. Nenhum formulário, URL, metadata Auth ou
role persistido manualmente participa dessa resolução.

Na entrega original de Auth, os demais dados e operações continuavam no
`AdminStore` demonstrativo. A fatia posterior de alunos/turmas passou a usar RPCs
escolares reais; consulte `admin-school-management-foundation.md`. Os demais
domínios mantêm indicadores de demonstração. Não há integração administrativa
com FastAPI ou Edge Functions.

## Banco

Migrations incrementais com conteúdo executável idêntico:

- `database/migrations/023_admin_auth_foundation.sql`;
- `supabase/migrations/20260930120000_admin_auth_foundation.sql`.

As anteriores terminavam em `022` / `20260923120000`. Nenhuma migration histórica
foi editada. `admins` é alterada incrementalmente, sem recriação ou alteração de IDs.

| Campo | Regra final relevante |
| --- | --- |
| `id` | UUID, PK e default existentes preservados |
| `name`, `email` | Text NOT NULL; unicidade de email preservada |
| `auth_user_id` | UUID opcional, UNIQUE quando preenchido |
| `role` | Text NOT NULL, somente ADMIN_A / ADMIN_B / ADMIN_C |
| `school_id` | UUID nullable, FK RESTRICT existente preservada |
| `status` | Text NOT NULL, default ACTIVE, CHECK ACTIVE / INACTIVE |
| `password_hash` | Nullable; legado FastAPI, sem sincronização com Auth |
| `created_at`, `updated_at` | Tipos, defaults e valores anteriores preservados |

A constraint `admins_role_school_check` exige A sem escola e B/C com escola.
O vínculo Auth segue o padrão atual de `students.auth_user_id` nos dois trilhos:
UUID lógico e único, sem FK para `auth.users`, sem cascade e sem presumir a
existência dessa tabela no PostgreSQL comum. O teste de integração cria usuários
pela API administrativa local do Auth, sem escrever SQL em `auth.users`.

`get_my_admin_context_v1()` não recebe parâmetros. É SQL, STABLE, SECURITY
DEFINER, com `search_path = ''` e referências qualificadas. Retorna zero ou uma
linha: `id, name, email, role, school_id, status`, exclusivamente por
`admins.auth_user_id = auth.uid()`. Não devolve hash, vínculo Auth, token ou segredo.
INACTIVE é devolvido para informar o bloqueio da própria conta. Isso não concede
autorização operacional: futuras RPCs administrativas deverão verificar ACTIVE,
role e school server-side a cada operação.

EXECUTE é revogado de PUBLIC, anon, authenticated e service_role e concedido
explicitamente somente a authenticated. A tabela admins mantém RLS fechada,
sem policies e sem grants diretos de leitura ou escrita aos clientes. As policies
e os grants das outras tabelas não mudam.

`redemptions.delivered_by_admin_id → admins.id ON DELETE RESTRICT` continua
intacta. `audit_logs.actor_id` é uma referência lógica, sem FK de admins, como
antes; histórico, metadata e IDs não são atualizados pela migration.

## Papéis legados e promoção futura

Não há documentação posterior que prove equivalência entre ADMIN,
ADMIN_CONQUISTA, BINGO_ADMIN e os papéis oficiais. A migration adquire lock e
aborta **antes do DDL** se encontrar qualquer role não canônica, explicando a
necessidade de classificação manual. Não usa NOT VALID para aceitar registros
antigos, não mapeia roles e não apaga contas ou histórico.

Um banco existente com esses registros exige inventário e decisão humana por
conta sobre role, school e situação do acesso. A preparação dessa decisão terá
de coordenar a substituição da antiga CHECK de role e a nulabilidade da escola
em uma manutenção controlada, preservando IDs e relações. Não basta executar
um UPDATE para a nova role sob a CHECK antiga. Essa preparação não foi criada
nem aplicada em ambiente hospedado nesta tarefa.

`database/seeds/004_seed_admins.sql` foi reformulada como fixture explícita A/B/C:
principal da escola B, operacional C e global A. Não cria usuários Auth, senhas
ou vínculos e não é um algoritmo de migração dos registros históricos. O reset
Supabase usa as seeds 008 e 011 e não cria administradores automaticamente.
O código e a suíte SQLite do FastAPI continuam legados, incluindo seus enums e
password_hash. Eles não fornecem autenticação ou autorização para o Admin Web;
esta feature não afirma paridade deles com o novo contrato administrativo.

## Angular

- `core/supabase-client.ts`: um cliente SDK sob demanda; configuração pública
  por ambiente, persistência/refresh do SDK e timeout de rede de 15 segundos.
- `core/admin-context.ts`: valida resposta mínima, unicidade, UUIDs, role,
  status e regra de escola; nenhuma role default em resposta vazia/malformada.
- `core/admin-auth.service.ts`: estado central em signal readonly, gate do
  contexto, um listener Auth e cleanup com DestroyRef.
- `app.ts`: monta o shell somente com o admin ACTIVE resolvido.
- `features/access.component.ts`: email/senha vazios, loading, erro, bloqueios,
  retry e logout; sem seletor de role ou credenciais demo preenchidas.
- `layout/admin-shell.component.ts`: role somente do contexto, nome real,
  escopo global/escola vinculada e logout; sem troca de perfil demonstrativo.
- `core/admin-store.ts`: role computada da sessão, nula fora dela; limpa
  diálogos/feedback transitórios ao perder o contexto; dados de negócio mock mantidos.

`admin-access.ts`, `roles/`, componentes de domínio, CSS e layout geral estão
preservados. O nome da escola e os dados apresentados pelos dashboards ainda
são demonstrativos; o cabeçalho de sessão indica apenas escola vinculada, sem
inventar o nome da escola real ou consultar seu domínio.

Login usa `signInWithPassword`, exige sessão e chama a RPC sem argumentos.
Credenciais inválidas permanecem no login. Auth sem admin ou admin INACTIVE
ficam bloqueados com mensagem própria e logout. Erro de rede/backend ou payload
inválido fecha o gate e oferece retry, sem fallback demo.

Refresh consulta `getSession()` e resolve novamente a RPC. Somente os tokens
são persistidos pelo SDK; role/school/status não são cache confiado. SIGNED_IN,
TOKEN_REFRESHED e USER_UPDATED relevantes resolvem o contexto fora do callback
Auth, evitando chamadas assíncronas sob seu lock. SIGNED_OUT limpa o contexto
imediatamente. Eventos de foco com o mesmo token já resolvido são deduplicados.
Uma geração de operação impede que respostas atrasadas reabram uma sessão já
encerrada. O SDK segue responsável pela renovação/remoção de tokens; um JWT já
emitido não é invalidado instantaneamente por uma mudança de domínio.

Logout usa `auth.signOut({ scope: 'local' })`, remove imediatamente o contexto e
volta ao login ao concluir. Falha de logout mantém o painel bloqueado e permite
tentar sair novamente; não simula remoção bem-sucedida de uma sessão do SDK.

## Executar localmente

Na raiz `Software`, com Docker ativo:

```powershell
npx supabase start
npx supabase db reset --local
```

O reset é destrutivo somente para o banco local. Configure o browser usando apenas
URL/chave pública. As mesmas chaves de configuração do Mobile são usadas aqui:
`SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`. Não use service_role / sb_secret.

```powershell
$adminLocalConfig = npx supabase status -o json | ConvertFrom-Json
@{
  SUPABASE_URL = $adminLocalConfig.API_URL
  SUPABASE_PUBLISHABLE_KEY = $adminLocalConfig.ANON_KEY
} | ConvertTo-Json | Set-Content -Encoding utf8 apps/admin_web/public/supabase-config.json
Remove-Variable adminLocalConfig
cd apps/admin_web
npm ci
npm start -- --host 127.0.0.1 --port 8106
```

`public/supabase-config.json` é ignorado pelo Git. O exemplo versionado contém
apenas localhost e chave vazia. O Angular copia esse arquivo público para o
build como asset; sem configuração válida o acesso fica bloqueado com erro.
A checagem de tipo de chave evita configurar credenciais técnicas por engano.
Crie o arquivo antes de iniciar o dev server; se ele já estiver aberto quando o
arquivo for criado, reinicie-o para descobrir o novo asset.

Para uma conta persistente de desenvolvimento, abra [Studio local](http://127.0.0.1:54323),
crie um usuário em Authentication com email/senha definidos localmente e copie
o UUID. Execute como postgres local, preenchendo os placeholders, por exemplo:

```sql
insert into public.admins(name, email, role, school_id, auth_user_id, status)
values ('Admin local', '<email local>', 'ADMIN_A', null, '<UUID Auth local>', 'ACTIVE');
```

Para B/C, use a respectiva role e um UUID de escola existente; a seed de reset
tem a escola demo `10000000-0000-4000-8000-000000000001`. Não preencha
password_hash. Somente provisionamento confiável decide role/escola; o formulário
de login não cria contas. Para provar ausência de vínculo, crie outro usuário
Auth sem linha admins. Para provar inatividade, altere status local para INACTIVE.
As contas de teste automático são temporárias, criadas pela API Auth e removidas
ao final juntamente com suas fixtures de domínio sem histórico.

## Validação

Com o dev server acima aberto:

```powershell
npm test
$env:BINGO_ADMIN_INTEGRATION = '1'
npm run test:integration
Remove-Item Env:BINGO_ADMIN_INTEGRATION
npm run build
```

Na raiz Software:

```powershell
npx supabase test db
$env:PYTHONPATH = 'backend/src'
.venv/Scripts/python.exe -m pytest backend/tests/test_admin_auth_foundation_migration.py -q
git diff --check
```

O teste real de integração obtém configuração exclusivamente de `supabase status`
local, exige hosts loopback e usa a chave técnica apenas no processo Node de
fixture. O browser recebe somente ANON_KEY. Prova credenciais inválidas, login,
próprio contexto, refresh, bloqueio após inativação, usuário sem admin, logout,
anon sem EXECUTE, SELECT/escrita direta negados e rejeição de admin_id escolhido.
Não possui caminho para projeto remoto.

Os testes HTTP de interface usam o SDK e interceptam os endpoints em Playwright;
isso é fixture de teste, sem mock de autenticação importado na aplicação.
Preservam os seis testes anteriores de navegação, composição e responsividade.
Cobrem A/B/C, senha inválida, ausência/inatividade, refresh, logout, rede/backend,
payload inválido, URL/storage/metadata não confiáveis, Auth events, resposta
atrasada após sign-out e isolamento dos dados demonstrativos.

`supabase/tests/admin_auth_foundation.sql` cobre constraints, grants, assinatura,
retorno mínimo, resolução própria A/B/C, sem vínculo/inativo, RLS, leitura/escrita
direta bloqueadas e FK de entrega. As provas Python com rollback verificam
equivalência dos trilhos, recusa dos três papéis antigos antes do DDL e
preservação literal de administrador, resgate e audit log durante a evolução.

Resultados e fotografia final do working tree:
[`admin-auth-foundation-report-2026-09-30.md`](admin-auth-foundation-report-2026-09-30.md).
