# Totem Simulator — Supabase

Totem de desenvolvimento conectado ao backend oficial Supabase. FastAPI não é requisito operacional. O browser usa somente o serviço confiável loopback; nenhuma chave técnica é enviada ao JavaScript.

```text
Frontend :8110 → serviço local :8765
                       ├─ /vision/analyze → AWS Rekognition / Gemini
                       └─ /bingo/* → Edge Functions → RPC/PostgreSQL
```

## Iniciar com Supabase local

Na pasta `Software`, com Docker e dependências locais instalados:

```powershell
node node_modules/supabase/dist/supabase.js start
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js functions serve --no-verify-jwt
```

O reset é exclusivamente local e carrega as seeds de desenvolvimento. As Functions exigem autenticação técnica de máquina mesmo com `verify_jwt = false`. O runtime local do CLI injeta sua Secret API Key no servidor; não copie essa chave para o serviço do Totem.

Em outro terminal, a partir da raiz do repositório:

```powershell
cd Software/apps/totem_simulator
python -m pip install -r vision/requirements.txt
Copy-Item vision/edge.env.example .env
```

Preencha o `.env` ignorado pelo Git:

| Variável                                                   | Uso                                                                                     |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `BINGO_SUPABASE_URL`                                       | Local: `http://127.0.0.1:54321`; DEV: URL pública do projeto                            |
| `BINGO_MACHINE_ID`                                         | UUID da máquina provisionada nesse ambiente                                             |
| `BINGO_MACHINE_API_KEY`                                    | Chave plaintext conhecida, mantida somente neste processo                               |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | Rekognition; credenciais/perfil AWS existentes                                          |
| `GEMINI_API_KEY`, `GEMINI_MODEL`                           | Confirmação/fallback; default `gemini-flash-lite-latest`                                |
| `BINGO_BACKEND_TIMEOUT_SECONDS`                            | Timeout de chamada ao backend, default 15                                               |
| `BINGO_ALLOWED_ORIGINS`                                    | Opcional: lista ainda restrita a origens localhost, por exemplo `http://127.0.0.1:8110` |

A máquina da seed **local** é `40000000-0000-4000-8000-000000000001`; sua chave de fixture é `edge-demo-key`. Use-a somente no Supabase local. Ela não corresponde à credencial hospedada conferida no preflight DEV desta entrega. Os PINs locais estão documentados exclusivamente na seed `database/seeds/008_seed_totem_simulator_rich_demo.sql`.

Nunca configure service role/Secret API Key Supabase nesse `.env`. AWS/Gemini e a chave da máquina ficam fora do browser. Não altere o backend configurado enquanto houver um evento pendente no browser.

Inicie o serviço e, em outro terminal, o frontend:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_vision.ps1
# Outro terminal, mesma pasta:
python -m http.server 8110 --bind 127.0.0.1
```

Abra `http://127.0.0.1:8110`. Não existe build do frontend. `/health` em :8765 indica apenas o serviço de visão; `/bingo/health` consulta readiness real. O processo permanece ligado durante o uso. `start_vision.ps1 -Python CAMINHO_DO_PYTHON` permite usar outro Python. Em Linux/macOS, exporte o ambiente e execute `python vision/edge_vision_service.py`.

`?visionUrl=URL` continua disponível para testes com outro endpoint **loopback**. Não aceita URL remota. O gateway do backend usa :8765.

## Usar bingo-dev

Exige as novas Functions e a migration 029 promovidas pelo procedimento de validação técnica, além de uma máquina com chave conhecida. Configure URL/ID/chave DEV no serviço local; o browser permanece em localhost. Não reexecute seeds locais nem rotacione `api_key_hash` para fazer o teste passar. Esta entrega validou DEV somente por consultas read-only: migrations alinhadas até 028, máquina existente com credencial configurada, mas sem chave plaintext conhecida correspondente. Promoção/smoke DEV permanecem pendentes dessa credencial.

## Operações reais

- Contexto: `/bingo/context` → `totem-context-v1`; escola derivada da máquina, turmas e alunos ACTIVE.
- PIN: `/bingo/student-pin` → `totem-student-pin-v1`; quatro dígitos, escola/turma/status/hash validados server-side, sem JWT.
- Resumo: `/bingo/student-summary` → `totem-student-summary-v1`; saldo, contagens e últimos cinco depósitos persistidos com snapshots.
- Ranking: `/bingo/rankings` → `totem-rankings-v1`; escola da máquina, ordenação saldo/XP DESC, nome ASC, UUID ASC. Preserva inclusão legada de INACTIVE no ranking.
- Readiness: `/bingo/health` → `health-v1`, existente.
- Registro/retry: `/bingo/deposits` → `register-deposit-v1`, existente.

O contexto não expõe PIN/hash/Auth/email/matrícula. Summary/Ranking continuam ferramentas de desenvolvimento. `machines.status` e `is_activated` não são novas barreiras de autenticação.

## Compromisso, recompensa e recuperação

Um ciclo recebe um UUID somente após readiness comprovada. Novo descarte exige HTTP 200, `status=AVAILABLE`, `can_start_deposit=true`, contexto e IA válidos. A confirmação final verifica readiness novamente e grava localmente os sete campos do evento **antes** de simular a queda física/enviar o registro. Falha do armazenamento interrompe antes do compromisso.

O payload contém apenas `event_id`, `class_id`, `student_id`, `is_valid`, `detected_type`, `waste_category_code`, `category_source`. Modo turma usa `student_id=null`. O backend calcula pontos/bônus/XP; a UI usa apenas os valores retornados.

HTTP 201 confirma criação; 200 confirma replay idêntico. Timeout/rede/500 ou resposta inválida preservam a pendência e não prometem pontuação. O painel permite retry com **mesmo UUID e payload**, inclusive após reload/reabertura na mesma origem/browser. 401 indica credencial inválida; 404/422, contexto/contrato inválido; 409, UUID com payload divergente. Pendências de conflito são preservadas para diagnóstico, sem gerar UUID substituto. Nenhum novo ciclo começa enquanto houver pendência; não existe fila offline nem `/deposits/sync`.

Após confirmação, a pendência é removida e leituras são atualizadas. Falha de leitura posterior não transforma um descarte confirmado em falha de registro. Falha ao limpar o armazenamento mantém replay seguro e bloqueia novo ciclo até recuperação. IA indisponível/sem confirmação não é um item rejeitado e não gera depósito. Recusa efetiva da IA pode registrar evento inválido, sem recompensa.

## Acervo local de imagens

A etapa de imagem inclui 15 amostras em `assets/samples`, selecionadas por clique ou arrastadas para a área de upload/prévia. O acervo funciona sem downloads externos e não dispara análise automaticamente. Os filtros de dificuldade são estimativas para organizar testes, não resultados medidos da IA.

Há fotos de eletrônicos e controles de recusa, além de ilustrações identificadas no título. Placa eletrônica, cabo com fios expostos e duas pilhas são casos de limite: reconhecer o objeto não confirma segurança, autorização ou quantidade. O acervo não substitui avaliação com capturas reais do equipamento.

As fotos foram copiadas do acervo já existente em `tools/Vision API Tester/storage/uploads/2026/07`; as ilustrações vêm dos assets existentes de Totem e mobile. São cópias locais para teste, sem mudança nas fontes. A origem/licença das fotos externas não foi verificada para redistribuição pública.

## Resultado normalizado

O frontend recebe somente um resultado normalizado:

- `recognized`: eletrônico autorizado identificado;
- `needs-secondary`: primeira leitura inconclusiva, acionando o fallback;
- `rejected`: item não confirmado ou não autorizado;
- `itemId`: `battery`, `cable`, `phone` ou `small`;
- `confidence`: confiança entre zero e um;
- `origin`: `AWS_REKOGNITION` ou `GEMINI_FALLBACK`.

O mapeamento para `waste_category_code`, `detected_type` e `category_source` acontece no simulador. A imagem nunca é enviada ao endpoint de depósito.

## Preservação da visão

Integração original da branch `feature/totem-simulator-vision-upload`, commit `d8fff0b`: providers, cascata AWS/Gemini, upload/drop, 15 imagens e testes originais preservados. Somente o serviço local foi ampliado para gateway/CORS/logs seguros; não há novo provedor nem novo modo IA de produção.

## Testes locais

Na pasta `Software`:

```powershell
node --test apps/totem_simulator/vision/tests/vision_provider.test.cjs apps/totem_simulator/tests/backend_client.test.cjs
.venv/Scripts/python.exe -m unittest discover -s apps/totem_simulator/vision/tests -p '*_test.py'
.venv/Scripts/python.exe apps/totem_simulator/tests/local_http_smoke.py
node --check apps/totem_simulator/app.js
node --check apps/totem_simulator/backend_client.js
node node_modules/supabase/dist/supabase.js test db
```

O smoke requer Functions locais servidas, portas 8765/8110 livres, psycopg e Playwright já instalados em `apps/admin_web/node_modules`. Usa Edge instalado (ou `BINGO_BROWSER_PATH`) e resposta de IA controlada **apenas no harness de teste**, mantendo autenticação/Functions/banco reais. Executa os testes browser e grava dois eventos locais, identificado e turma, com replay e conferência SQL. Esses eventos locais e seus históricos permanecem no banco de teste até o próximo reset.

Em `Software/supabase/functions`: `npx deno task fmt:check`, `npx deno task lint`, `npx deno task check`, `npx deno task test`. Para a integração HTTP, configurar `BINGO_EDGE_TOTEM_INTEGRATION=1` e `BINGO_EDGE_TEST_DATABASE_URL` com banco exclusivamente localhost, e executar `npx deno test --allow-env --allow-net tests/totem-v1.integration.test.ts`. Os testes preexistentes de integração têm seus próprios flags e credenciais locais de fixture.

Execute suítes que manipulam fila de Missões de forma sequencial, após reset limpo. Mobile/Flutter, Admin e `apps/totem_ui` não são alterados. Detalhes em `../../docs/totem-supabase-integration-v1.md`.

### Diagnóstico

- Visão falha: confira credenciais/permissões/cotas AWS/Gemini, serviço :8765 e `/health`.
- Contexto/readiness falha: confira Functions, migrations, URL e credencial da máquina no serviço local; não substitua por mocks.
- Item já recebido sem confirmação: preserve armazenamento, não mude backend/identidade da máquina, use retry do mesmo evento.
- Credencial DEV desconhecida: obter/provisionar por canal autorizado; nunca sobrescrever o hash silenciosamente.
