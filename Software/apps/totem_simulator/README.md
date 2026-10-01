# Totem Simulator — Supabase

Totem de desenvolvimento conectado ao backend oficial Supabase. FastAPI não é requisito operacional. No modo local, o browser usa somente o serviço confiável loopback; no modo cloud, frontend e APIs usam a mesma origem. Nenhuma chave técnica é enviada ao JavaScript.

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

As credenciais da seed **local** são fixtures e devem ser usadas somente no Supabase local; consulte `database/seeds/008_seed_totem_simulator_rich_demo.sql`. A homologação hospedada usa uma máquina DEV específica do Totem Simulator, provisionada com credencial conhecida, sem publicar seus dados de acesso aqui.

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

Homologado em **2026-10-01**, exclusivamente no `bingo-dev`: a migration 029 (`20261001140000_totem_server_reads_v1.sql`) foi aplicada e ficou alinhada local/remoto. `totem-context-v1`, `totem-student-pin-v1`, `totem-student-summary-v1` e `totem-rankings-v1` foram deployadas, e uma máquina DEV específica foi provisionada com credencial conhecida. Configure URL/ID/chave DEV no serviço local; o browser permanece em localhost. Não reexecute seeds locais nem rotacione `api_key_hash` para fazer o teste passar.

O smoke hospedado comprovou `health-v1` com `AVAILABLE` e `can_start_deposit=true`, contexto real e validação de PIN. Um aluno demo recebeu PIN apenas para smoke DEV. AWS Rekognition e Gemini foram exercitados ao vivo; um descarte completo pelo simulador foi persistido por `register-deposit-v1`, atualizando BinCoins do aluno e XP da turma conforme os snapshots do backend. Todos os testes e o smoke end-to-end passaram, e o PR #41 foi mergeado em `develop`. Essa comprovação **não se estende à produção**.

## Cloud Run temporário (preparação local, sem deploy)

Um único processo Python (`http.server`) serve o frontend e `/vision/analyze` e
`/bingo/*` em uma única porta. Não requer Vercel, servidor frontend separado,
nginx ou novo framework. Essa hospedagem serve apenas à apresentação temporária
com `bingo-dev`; não representa a arquitetura final do Totem físico nem uma
homologação de produção. Nenhum recurso Cloud Run foi criado por esta adaptação.

- **Local (default):** `BINGO_RUNTIME_MODE=local` ou ausente, frontend separado
  em :8110 e serviço em `127.0.0.1:8765`. Bind/origens não-loopback continuam
  rejeitados. O catálogo de 15 samples permanece disponível. `?visionUrl=`
  continua aceitando somente endpoints loopback nesse modo.
- **Cloud:** `BINGO_RUNTIME_MODE=cloud`, bind `0.0.0.0`, porta obrigatoriamente
  lida de `PORT`. O serviço entrega apenas o sinal público de modo em
  `runtime.js`; o browser usa `/vision/analyze` e `/bingo/*` na mesma origem,
  ignorando `?visionUrl=`. Não há abertura de CORS para origens externas.

Configure no ambiente **server-side**, sem incluir valores no Git/imagem:

| Variável | Uso em cloud |
| --- | --- |
| `BINGO_RUNTIME_MODE` | `cloud` |
| `PORT` | Porta fornecida pelo Cloud Run; obrigatória, sem default cloud |
| `BINGO_DEMO_USERNAME`, `BINGO_DEMO_PASSWORD` | Credenciais obrigatórias da demonstração; username sem `:` |
| `BINGO_SUPABASE_URL` | URL do `bingo-dev` |
| `BINGO_MACHINE_ID`, `BINGO_MACHINE_API_KEY` | Máquina DEV e credencial já provisionadas, somente no servidor |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` | Integração Rekognition existente |
| `GEMINI_API_KEY`, `GEMINI_MODEL` | Integração Gemini existente |

Basic Auth protege frontend e todas as rotas operacionais, com comparação segura
no servidor. Acesso ausente/incorreto recebe 401 e `WWW-Authenticate`.
Credenciais de demo ausentes impedem o startup cloud; as rotas também falham
fechado se a configuração estiver ausente. `/healthz` é a única rota pública,
retornando somente `{"status":"ok"}` como liveness do processo, sem comprovar
readiness de Supabase/IA. Use HTTPS na apresentação; Cloud Run termina TLS.
Nenhum username/password, segredo AWS/Gemini, chave de máquina ou configuração
privilegiada Supabase é enviado ao HTML/JS. Não configure service role.

O Dockerfile copia somente os arquivos necessários, roda como usuário sem
privilégios e não contém `.env`, exemplos de ambiente, testes ou `assets/samples`.
O servidor usa uma whitelist de estáticos, sem file server aberto. O catálogo
cloud é vazio e sua seção fica oculta; upload/drag-and-drop manual continuam
funcionando. Os samples no repositório/local permanecem intactos, pois a licença
de redistribuição pública de parte do acervo não foi comprovada.

Build local, sem credenciais, a partir de `Software/apps/totem_simulator`:

```powershell
docker build -t bingo-totem-cloud-demo:local .
```

Para experimentar a imagem localmente, forneça `PORT` e as demais variáveis de
runtime por um arquivo de ambiente privado fora do contexto de build:

```powershell
docker run --rm -p 8080:8080 --env-file CAMINHO_DO_ENV_PRIVADO bingo-totem-cloud-demo:local
```

Abra `http://127.0.0.1:8080` e use a autenticação do browser. Não passe secrets
como build args. Não há push/deploy nesses comandos. O armazenamento de eventos
pendentes continua por origem/browser: recuperar na mesma origem, sem trocar
backend ou identidade da máquina. A demo pode gerar efeitos reais no `bingo-dev`
e custos de IA; Basic Auth é proteção de apresentação, não gestão de usuários
nem limitação de consumo por usuário.

Novos testes, a partir de `Software`:

```powershell
python -m unittest discover -s apps/totem_simulator/vision/tests -p '*_test.py'
node --test apps/totem_simulator/tests/runtime.test.cjs
python apps/totem_simulator/tests/cloud_http_smoke.py
```

O smoke cloud roda exclusivamente em loopback, exercita o servidor e Basic Auth
reais e controla as fronteiras de Supabase/IA no harness. Não usa credenciais
reais nem faz deploy, chamadas externas ou escritas em banco.

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

O smoke requer Functions locais servidas, psycopg e Playwright já instalados em `apps/admin_web/node_modules`. Usa Edge instalado (ou `BINGO_BROWSER_PATH`) e resposta de IA controlada **apenas no harness de teste**, mantendo autenticação/Functions/banco reais. Executa os testes browser e grava dois eventos locais, identificado e turma, com replay e conferência SQL. O harness usa portas loopback temporárias próprias, sem encerrar servidores existentes; os URLs padrão da aplicação permanecem inalterados. Esses eventos locais e seus históricos permanecem no banco de teste até o próximo reset.

Em `Software/supabase/functions`: `npx deno task fmt:check`, `npx deno task lint`, `npx deno task check`, `npx deno task test`. Para a integração HTTP, configurar `BINGO_EDGE_TOTEM_INTEGRATION=1` e `BINGO_EDGE_TEST_DATABASE_URL` com banco exclusivamente localhost, e executar `npx deno test --allow-env --allow-net tests/totem-v1.integration.test.ts`. Os testes preexistentes de integração têm seus próprios flags e credenciais locais de fixture.

Execute suítes que manipulam fila de Missões de forma sequencial, após reset limpo. Mobile/Flutter, Admin e `apps/totem_ui` não são alterados. Detalhes em `../../docs/totem-supabase-integration-v1.md`.

### Diagnóstico

- Visão falha: confira credenciais/permissões/cotas AWS/Gemini, serviço :8765 e `/health`.
- Contexto/readiness falha: confira Functions, migrations, URL e credencial da máquina no serviço local; não substitua por mocks.
- Item já recebido sem confirmação: preserve armazenamento, não mude backend/identidade da máquina, use retry do mesmo evento.
- Credencial DEV desconhecida: obter/provisionar por canal autorizado; nunca sobrescrever o hash silenciosamente.
