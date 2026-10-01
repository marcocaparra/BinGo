# Totem Simulator — integração Supabase V1

Branch `feature/totem-supabase-integration`. Escopo: simulador, gateway local,
quatro Functions e leituras PostgreSQL server-only. `apps/totem_ui` é referência
e permanece intacto. FastAPI continua no repositório como legado; deixou de ser
requisito operacional deste simulador.

## Contratos oficiais preservados

`data-contracts-totem-app-backend.md`, `supabase-edge-functions-mvp.md`,
`operacao-offline.md` e STATUS são a fonte das regras de autenticação técnica,
readiness, pontuação e recuperação. `health-v1`, `register-deposit-v1`,
`register_deposit_v1` e machine-auth mantêm seus contratos. Nenhuma nova regra
econômica ou policy Mobile foi criada.

A visão de `d8fff0b` mantém upload/drop, 15 imagens, Rekognition primário,
Gemini para confirmação/fallback e modelo configurável. Providers, assets e
testes originais não foram modificados. Falha técnica ou confirmação ausente
não viram classificação `rejected`; o browser bloqueia o registro nesses casos.

## Decisões técnicas desta entrega

O serviço Python existente em loopback :8765 concentra `/vision/analyze` e
`/bingo/*`. Apenas ele lê `BINGO_SUPABASE_URL`, `BINGO_MACHINE_ID` e
`BINGO_MACHINE_API_KEY`, e acrescenta os headers técnicos. Não possui Secret API
Key/service role Supabase. CORS e Host aceitam somente localhost/127.0.0.1;
nenhuma Function abre CORS para o browser. Logs locais omitem query/body/PIN.

Os quatro nomes HTTP abaixo são novos contratos técnicos versionados, não
endpoints históricos preexistentes:

| Gateway local                 | Function                   | RPC server-only                                   |
| ----------------------------- | -------------------------- | ------------------------------------------------- |
| GET `/bingo/context`          | `totem-context-v1`         | `get_totem_context_v1(uuid)`                      |
| POST `/bingo/student-pin`     | `totem-student-pin-v1`     | `get_totem_student_pin_record_v1(uuid,uuid,uuid)` |
| POST `/bingo/student-summary` | `totem-student-summary-v1` | `get_totem_student_summary_v1(uuid,uuid)`         |
| GET `/bingo/rankings`         | `totem-rankings-v1`        | `get_totem_rankings_v1(uuid)`                     |

As Functions autenticam com `_shared/machine-auth.ts`; o UUID de máquina passado
à RPC é o resultado confiável dessa autenticação. Nenhum body/query escolhe
escola ou máquina. PIN recebe somente class/student/pin; resumo, somente student.
O gateway rejeita campos extras antes do encaminhamento.

A migration **029** é equivalente nos dois trilhos:
`database/migrations/029_totem_server_reads_v1.sql` e
`supabase/migrations/20261001140000_totem_server_reads_v1.sql`. Ela foi necessária
porque o runtime privilegiado existente tem leitura técnica mínima de máquinas,
sem SELECT amplo de alunos/turmas/escolas/depósitos. As novas funções SQL são
STABLE, SECURITY DEFINER, `search_path=''`, EXECUTE somente service_role. Não há
alteração de schema, novos grants de tabela, escrita ou policies. O hash de PIN
só é retornado pela RPC privada necessária à validação server-side.

O runtime local do CLI injeta `SUPABASE_SECRET_KEYS.default` e rejeita overrides
`SUPABASE_*`. O resolver compartilhado aceita esse nome exclusivamente quando
`SUPABASE_URL=http://kong:8000`. Hospedado permanece exigindo `bingo_backend`;
configuração inválida continua fail-closed. Isso permite testar HTTP real local
sem mudar health/register/machine-auth ou colocar chaves privilegiadas no Totem.

## Identificação e leituras

Contexto contém escola/máquina mínimas, turmas e alunos ACTIVE da mesma escola;
não expõe email, matrícula, PIN/hash ou Auth UUID. PIN exige quatro dígitos ASCII,
mesma escola/turma, ACTIVE e hash válido. PBKDF2-HMAC-SHA256, 120000 iterações,
salt base64, digest 32 bytes, formato `salt$digest`, sem alterar hashes existentes.
PIN incorreto, ausente, INACTIVE ou fora do escopo não confirma identidade.
Resposta bem-sucedida: `confirmed=true` e id/nome/turma públicos. JWT FastAPI e
`studentToken` foram eliminados. `is_activated` não é condição adicional; status
da máquina não virou barreira de autenticação.

Resumo usa saldo persistido, contagens valid/invalid, soma histórica dos snapshots
de `points_awarded_student` válidos e últimos cinco depósitos, ordenados por
created_at DESC/UUID DESC. Categoria vem da FK existente; taxas/bônus/pontos vêm
da fotografia do depósito. Rankings são limitados à escola, ordenados por
saldo/XP DESC, nome ASC e UUID ASC. A documentação vigente não decide excluir
INACTIVE do ranking; preservou-se o comportamento legado de inclusão. Resumo
também mantém consulta histórica por identidade scoped, enquanto seleção normal
no contexto e confirmação de PIN exigem ACTIVE.

## Compromisso e recuperação

Health precisa retornar HTTP 200, AVAILABLE e can_start_deposit=true no início
do ciclo e antes da confirmação final. Não há polling. Antes do compromisso,
falhas de backend/IA/storage interrompem sem receber item nem prometer pontos.

Um UUID é criado por ciclo. A confirmação final é a queda física **simulada**:
grava primeiro `event_id` e os sete campos completos do payload em localStorage,
sem PIN/imagem/secrets, e depois chama register via gateway. Modo turma usa
student_id=null. A recompensa apresentada é exclusivamente `points_awarded_student`,
`points_awarded_class` e `bonus_bincoins_awarded` retornados pela Function existente.

201/200 confirmam criação/replay e removem a pendência. Resposta perdida,
timeout/rede/500 ou corpo inválido mantêm evento, payload e bloqueio de novos
ciclos. Reload/reabertura na mesma origem permite retry idempotente. 409 exige
diagnóstico do evento divergente; 401, credencial; 404/422, contexto/contrato.
Nunca gerar UUID substituto. Não existe fila de novos descartes offline ou sync.
Read failure após confirmação não desfaz sucesso. Cleanup failure do storage
mantém confirmação e replay seguro, sem liberar outro ciclo.

## Validação local e DEV

Foram executados reset local com 029, pgTAP completo, Deno fmt/lint/check/test,
regressão backend, HTTP real local, Node/Python e navegador. O smoke HTTP prova
readiness, contexto/PIN, ACTIVE/is_activated/machine.status, resumo/ranking,
depósito identificado/inválido/turma, snapshots, saldos/XP e replay sem duplicação.
O smoke navegador usa gateway/Functions/banco reais e resposta de visão controlada
no harness, preservando a fronteira original; grava dois eventos locais e confere
linhas SQL. Eventos e efeitos históricos de smoke ficam no banco local até reset.
Suítes que manipulam a fila global de Missões devem rodar sequencialmente.

AWS/Gemini ao vivo não foram chamados nesta fatia: não havia suas credenciais no
ambiente. Os 16 testes Node e 15 Python originais foram preservados e passaram.

Preflight DEV read-only confirmou projeto linked `bingo-dev`
(`ddxmohrjcxuibswmrtla`), histórico local/remoto alinhado até 028 e somente
health/register/recover implantadas. Máquina
`40000000-0000-4000-8000-000000000001`, Totem Dev Cloud 01, ONLINE, tem hash de
credencial configurado. Comparação privada comprovou que ele **não** corresponde
a `edge-demo-key`. Não havia chave plaintext correspondente configurada no `.env`.
Nenhum hash foi alterado; **029 e as quatro novas Functions permanecem locais**.
Promoção/smoke hospedado dependem da chave conhecida ou de provisionamento/rotação
explicitamente autorizados. Não houve escrita/deploy remoto, commit, push ou PR.

Procedimentos e variáveis sem segredos: `apps/totem_simulator/README.md`.

## Resultados das suítes e comandos

| Validação                                                           | Resultado                                                  |
| ------------------------------------------------------------------- | ---------------------------------------------------------- |
| `supabase db reset --local`                                         | 29 migrations e seeds aplicadas                            |
| `supabase test db`                                                  | 609 verificações em 22 arquivos, passaram                  |
| Deno `task fmt:check`, `task lint`, `task check`                    | Passaram                                                   |
| Deno `task test`                                                    | 62 passaram                                                |
| Deno `task test:integration`, com todos os flags locais habilitados | 6 passaram, nenhum ignore                                  |
| Backend `pytest backend/tests -q -rs`                               | 176 passaram, nenhum skip                                  |
| Node `--test` visão + client                                        | 33 passaram: 16 originais + 17 client/recovery             |
| Python `unittest discover` visão/gateway                            | 22 passaram: 15 originais + 7 gateway                      |
| Browser `local_http_smoke.py`                                       | 8 passaram, incluindo smoke Supabase/gateway/browser e SQL |
| `node --check` app/client e `py_compile` serviço/harness            | Passaram                                                   |
| Prettier nos JS/HTML/Markdown modificados                           | Passou                                                     |
| `git diff --check`                                                  | Passou                                                     |

Para backend completo, foram habilitados `BINGO_RPC_TEST_DATABASE_URL` e
`BINGO_MIGRATION_TEST_DATABASE_URL` exclusivamente em 127.0.0.1:54322. A primeira
invocação sem todas as configurações deixou sete skips; a execução final não
teve skips. A prova de recuperadores falhou numa execução que coincidiu com
outra suíte manipulando a mesma fila; reset limpo + execução sequencial passou.
Configurações incompletas dos testes Deno e o caminho inicial de browser foram
corrigidos sem enfraquecer assertions. Uma checagem Deno inicialmente invocada
fora de `supabase/functions` foi interrompida; as verificações finais usaram o
escopo correto. O primeiro reset detectou uma referência incorreta à categoria
como coluna do depósito; a 029 foi corrigida para usar a FK existente e então
reset/pgTAP passaram. Nenhum erro de suíte ficou pendente.

Avisos preservados: JWT curto em fixtures FastAPI legadas, depreciação do bloco
inbucket do CLI e normalização LF/CRLF do Git. Não alteram o fluxo sem JWT do
simulador. Não existe build Angular nesta fatia estática; Admin/Mobile/Flutter
não foram alterados nem compilados. AWS/Gemini ao vivo e smoke bingo-dev não
executados pelos motivos de credencial descritos acima.

## Working tree na entrega

Branch `feature/totem-supabase-integration`; 28 arquivos da fatia, todos sem
stage/commit. A alteração pré-existente em `apps/admin_web/package-lock.json`
foi preservada byte a byte (SHA256
`870730811EAF8585C39301792CFB3E7DDC15FC0C8B1163C769B83F98368147CB`).
Nenhum arquivo Admin foi alterado por esta tarefa.

`git status --short --untracked-files=all`, cwd `C:\Projetos\BinGo\Software`:

```text
 M apps/admin_web/package-lock.json
 M apps/totem_simulator/README.md
 M apps/totem_simulator/app.js
 M apps/totem_simulator/index.html
 M apps/totem_simulator/start_vision.ps1
 M apps/totem_simulator/vision/edge.env.example
 M apps/totem_simulator/vision/edge_vision_service.py
 M docs/STATUS_12-08.md
 M supabase/config.toml
 M supabase/functions/_shared/supabase-admin.ts
 M supabase/functions/deno.json
 M supabase/functions/tests/supabase-admin.test.ts
?? apps/totem_simulator/backend_client.js
?? apps/totem_simulator/tests/backend_client.test.cjs
?? apps/totem_simulator/tests/browser.test.cjs
?? apps/totem_simulator/tests/local_http_smoke.py
?? apps/totem_simulator/vision/tests/bingo_gateway_test.py
?? database/migrations/029_totem_server_reads_v1.sql
?? docs/totem-supabase-integration-v1.md
?? supabase/functions/_shared/student-pin.ts
?? supabase/functions/_shared/totem-handler.ts
?? supabase/functions/tests/totem-v1.integration.test.ts
?? supabase/functions/tests/totem-v1.test.ts
?? supabase/functions/totem-context-v1/index.ts
?? supabase/functions/totem-rankings-v1/index.ts
?? supabase/functions/totem-student-pin-v1/index.ts
?? supabase/functions/totem-student-summary-v1/index.ts
?? supabase/migrations/20261001140000_totem_server_reads_v1.sql
?? supabase/tests/totem_server_reads_v1.sql
```

`git diff --exit-code -- apps/totem_ui` retornou 0, sem diff; não há arquivos
novos nesse diretório. Providers/testes originais de visão, assets e sample
library também não têm diff.

Ações remotas executadas: somente preflight read-only — projects list,
migration list, functions list e queries de schema/RPCs/máquina, além da
comparação privada do hash contra a fixture conhecida. Postflight confirmou
local 029 pendente e remoto ainda 028. Sem rotação/provisionamento de chave,
escrita de dados/schema, deploy, commit, push ou PR.
