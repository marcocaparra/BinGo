# Integração DEV do TotemEdge — Incremento 3C.1

Perfil explícito para leituras e identificação no Supabase DEV com mecânica
simulada. Não integra frontend, câmera ou hardware. Não registra descartes,
recibos, BinCoins ou XP. O target Docker default continua operacional e bloqueado.

## Diagnóstico dos contratos e permissões

Inspeção inicial: feature/orange-pi-integration, HEAD b40751b, working tree limpa.
O STATUS de 2026-10-23 e totem-supabase-integration-v1.md documentam entregas
posteriores ao relatório de agosto: health-v1 e register-deposit-v1 existem;
contexto/PIN/resumo/ranking e a migration 029 foram homologados em bingo-dev em
2026-10-01. A pendência HTTP de agosto é histórica. Não foi feita consulta remota
para confirmar o estado atual dos deployments ou grants nesta entrega.

Código inspecionado: _shared/machine-auth.ts, totem-handler.ts, student-pin.ts,
register-deposit-v1/handler.ts, migration 20261001140000_totem_server_reads_v1.sql,
tests/machine_auth_permissions.sql e contratos centrais. Autenticação técnica usa
X-Machine-Id/X-Api-Key, PBKDF2-HMAC-SHA256 e escola derivada server-side. PIN exige
quatro dígitos ASCII, aluno ACTIVE e mesma turma/escola. Não há novo JWT/PIN/RPC.

As RPCs de leitura são STABLE/SECURITY DEFINER, search_path vazio, EXECUTE somente
service_role; anon/authenticated não podem executá-las ou ler pin_hash. A leitura
técnica de machines é restrita às colunas necessárias. As evidências pgTAP e
hospedadas citadas são históricas, não testes reexecutados neste incremento.

**A chave da máquina não tem escopo somente leitura.** A mesma autenticação é
aceita por register-deposit-v1, cuja Function privilegiada chama a RPC econômica
e o processamento de missões. RLS do navegador não restringe essa capacidade HTTP.
Por isso a chave nunca é entregue ao processo que executa o simulador. Autenticar
máquina/aluno não constitui confirmação física.

## Três contextos

| Contexto | Fábrica / API | Central | SQLite / volume | HTTP host |
| --- | --- | --- | --- | --- |
| Operacional | app.main:app; /local/sessions e /local/context | Cliente existente; controller indisponível | /var/lib/bingo/totem.sqlite3; sqlite-data | Compose operacional preservado |
| Simulação isolada | app.simulation:create_simulation_app; /local/simulation/sessions | Bloqueada, sem credenciais ou saída externa | /var/lib/bingo-simulation/simulation.sqlite3; simulation-data | 127.0.0.1:8001 |
| Integração DEV | app.dev_integration:create_dev_app; /local/simulation/sessions + /local/dev | Somente três capacidades via dev-central | /var/lib/bingo-dev-integration/simulation.sqlite3; dev-integration-data | 127.0.0.1:8002 |

Os dois perfis simulados **não montam as rotas operacionais**, incluindo consultas,
cancelamento, PIN, retry e finish. Tentativas retornam 404 sem tocar no store.
O operacional não monta as rotas simuladas/DEV e recusa ambiente/marcador DEV.
No DEV, ciclos antigos simulated=0 continuam recusados pela API simulada.
O schema permanece v3, com cycles.simulated imutável e snapshots source/commands/
allowed_actions preservados. Não há adoção ou cópia automática entre volumes.

## Fronteira de capacidade

Frontend → FastAPI → coordenador → journal → SimulatedController permanece intacto.
Separadamente, o cliente de leitura do FastAPI chama dev-central por rede interna.
Somente dev-central recebe a chave por Docker secret e possui rede de saída.

O broker expõe apenas GET health-v1, GET totem-context-v1 e POST
totem-student-pin-v1, nos caminhos /functions/v1 existentes. Não há proxy genérico,
CONNECT, URL arbitrária, RPC, resumo, ranking, registration ou forwarding de headers
de autenticação do solicitante. Host/destino HTTPS são fixados no projeto DEV
ddxmohrjcxuibswmrtla, identificado na documentação mobile-supabase-auth-profile.md.
TLS é verificado; redirects, proxies de ambiente e configurações centrais diretas
são recusados. O transporte valida novamente método, origem e caminho exatos.

O FastAPI não recebe a chave Supabase, não monta o secret e está exclusivamente
em duas redes internal, sem rota externa. O ingresso TCP não participa da rede do
broker, não possui SQLite ou secrets e encaminha somente ao backend fixo.
Broker não tem porta publicada nem volume SQLite. Todas as imagens usam UID/GID
10001, rootfs readonly, cap_drop ALL e no-new-privileges, sem dispositivos.

DevCentralClient.register recusa; o transporte e o broker também recusam qualquer
caminho econômico. As sessões continuam sem payload/recibo/central_scope e com
physical_confirmed=0. Leituras/PIN não alteram esses campos. A chave ampla fica
restrita à fronteira; proteger seu arquivo e o acesso administrativo ao Docker
continua necessário. O perfil não recebe nem utiliza service_role localmente.

## Configuração inicial, sem credenciais no repositório

Não reutilizar automaticamente a máquina do Simulator antigo: aquele fluxo pode
gravar economia DEV. É necessária uma máquina já autorizada em **escola de teste
exclusivamente sintética**. Este incremento não cria nem altera máquina, escola,
turma, aluno, PIN, hash ou grants no Supabase.

O RPC de contexto retorna toda a escola da máquina. A lista de IDs não filtra a
consulta remota: o broker recusa respostas contendo IDs não aprovados antes de
repassá-las ao FastAPI. Portanto, não usar escola com pessoas reais ou dados mistos.
test_data_only=true é declaração explícita do responsável pelo dataset; o software
não consegue provar, pelo nome de um aluno, que ele é fictício. Sem esse conjunto
e credencial aprovados, não configurar o perfil conectado.

Criar dois arquivos fora do checkout e das imagens, com acesso de leitura restrito
ao operador/Docker. Não enviar seu conteúdo ao chat ou a relatórios:

- Política JSON UTF-8, sem BOM, com os campos abaixo; substituir todos os UUIDs
  pelos IDs autorizados da escola sintética. IDs devem ser únicos; class_ids não
  pode ser vazio. student_ids pode ser vazio, impedindo identificação por PIN.
- Arquivo de chave contendo somente a API key técnica da máquina, UTF-8 sem BOM.
  É aceito um terminador de linha de arquivo. JWTs e chaves Supabase sb_* são
  recusados; não fornecer anon, publishable, secret API key ou service_role.

```json
{
  "project_ref": "ddxmohrjcxuibswmrtla",
  "test_data_only": true,
  "machine_id": "<UUID-da-maquina-DEV-de-teste>",
  "school_id": "<UUID-da-escola-sintetica>",
  "class_ids": ["<UUID-da-turma-de-teste>"],
  "student_ids": ["<UUID-do-aluno-sintetico>"]
}
```

Não há chave no JSON. Destino diferente, campos extras, arquivos ausentes,
symlinks, configuração de proxy, mistura de perfis ou credenciais em ambiente
provocam recusa. Marcador exclusivo .bingo-dev-integration-only é criado apenas
em diretório vazio; bancos físicos/econômicos são recusados antes da recuperação.

## Construir, iniciar, consultar e encerrar

Na pasta Hardware/TotemEdge/deploy, Docker Desktop com containers Linux:

```powershell
# Somente caminhos externos; nunca colocar a chave em variável/comando.
$env:BINGO_DEV_POLICY_FILE = 'C:/BinGoDevSecrets/dev-policy.json'
$env:BINGO_DEV_MACHINE_KEY_FILE = 'C:/BinGoDevSecrets/dev-machine-key'
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml config --quiet
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml build
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml up -d --no-build --wait --wait-timeout 90
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml ps
Invoke-RestMethod 'http://127.0.0.1:8002/local/dev/health'
```

dev-integration.env é versionado sem valores. Não combinar arquivos Compose dos
três perfis, não usar .env operacional e não passar credenciais por -e/env_file.
Somente os dois caminhos declarados são interpolados; valores de BINGO_MACHINE_*,
SUPABASE_*, AWS e proxies do shell não são encaminhados. Não imprimir docker
inspect/env ou arquivos secretos como diagnóstico.

```powershell
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml restart
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml up -d --no-build --force-recreate --wait --wait-timeout 90
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml stop
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml down
```

down sem --volumes conserva o histórico. restart:unless-stopped permite voltar
com o Docker após a configuração inicial; os arquivos externos devem continuar
disponíveis. Reiniciar explicitamente os serviços após rotação autorizada do
segredo/política. A indisponibilidade central não simula autenticação nem altera
o estado mecânico; pode-se repetir consultas explicitamente. Healthcheck confirma
processo/configuração, enquanto /local/dev/health verifica o central no momento.
/local/status permanece OFFLINE/false, inclusive quando o central responde AVAILABLE.

## API local DEV

| Método/caminho | Contrato | Efeito |
| --- | --- | --- |
| GET /local/dev/health | Sem body/query | central=AVAILABLE, scope=SUPABASE_DEV_READ_ONLY, mechanical_source=SIMULATED, economic_registration=false; não autoriza descarte real |
| GET /local/dev/context | Mesmo TotemContext existente | Escola/máquina, turmas e alunos aprovados do DEV; sem PIN/hash/credencial |
| POST /local/dev/student-pin | class_id, student_id UUID e pin de quatro dígitos ASCII | Mesmo PinConfirmation existente; confirmed=true somente após resposta central validada |

PIN é transitório, somente JSON, não entra em logs, URLs ou SQLite. O cliente
reconsulta contexto para verificar aluno/turma ACTIVE antes de confirmar. A
Function permanece autoridade da identificação. A verificação é independente do
ciclo mecânico: não autentica automaticamente a fixture class_only do 3B nem
grava identidade do aluno em uma sessão. Isso será contratado no 3C.2.

Host/Origin local, escrita JSON com X-Totem-Request:1, ausência de query, recusa
de campos extras, erros sanitizados e Cache-Control:no-store são preservados.
403: guarda local/capacidade/IDs fora da política; 422: contrato; 401: PIN inválido
ou machine-auth detectado pelo health; 503: central indisponível/resposta recusada;
502 pode representar validação inesperada no cliente. Negação upstream é tratada
pelos normalizadores existentes, sem repassar body remoto ou fabricar confirmação.
Rotas inexistentes/cruzadas retornam 404. Nenhuma API oferece registro econômico.

## Testes e evidências

```powershell
# backend/
uv run --locked pytest -q
# deploy/
python -B -m unittest discover -s tests -p test_runtime.py -v
node --test ../frontend/validation/local_api.test.cjs
python -B validation/simulation_smoke.py --skip-build
python -B validation/dev_integration_smoke.py --skip-build
```

O smoke DEV usa o Compose real, processos/SQLite/redes reais e Functions
**sintéticas** via HTTPS com CA exclusiva de uma imagem temporária de validação.
DNS na rede de fixture aponta o hostname DEV para o servidor local, sem saída
externa nessa rede. Não há verify=false no perfil real. A chave TLS de fixture
e a chave de máquina sintética não são credenciais hospedadas. O mock registra
somente método/caminho e contém sentinela de depósitos/saldo/XP.

O smoke verifica contexto/PIN correto e incorreto, segregação de redes/segredos,
rotas cruzadas, negativa econômica direta, fluxo mecânico completo, replay,
restart/recreate e SIGKILL com UNKNOWN/INDETERMINATE sem redisparo. Apenas projetos
UUID próprios são removidos com seus volumes no teardown; dados do usuário não
são apagados. Evidências ficam em deploy/.validation/bingo-dev-integration-test-*.

Não foram feitas chamadas hospedadas. Foram identificadas configurações antigas
com URL do DEV e campos de máquina/chave preenchidos no Simulator e no deploy;
seus valores não foram exibidos nem reutilizados. Não foi fornecida a política
de escola/IDs exclusivamente sintéticos autorizada para este perfil. Como contexto
consulta a escola inteira, não foi presumida autorização para ler esses alunos.
A pendência é o conjunto de configuração aprovado, não ausência genérica de chave.
A comprovação de saldos/depósitos/XP inalterados
é local, pela sentinela; não é comparação SQL do Supabase remoto. Não foram
executados ARM64, hardware, câmera, navegador ou integração visual.

Resultados executados em 2026-10-28:

| Verificação | Resultado |
| --- | --- |
| Baseline backend antes de alterações | 460 aprovados |
| Backend completo após implementação | 528 aprovados, incluindo 68 novos, sem skips/falhas |
| Runtime/deploy e contratos JS preservados | 7 + 7 aprovados |
| Docker build check | Aprovado, sem avisos |
| Targets simulation, dev_integration e default AMD64 | Builds aprovados |
| Imagem default sem rede/rootfs readonly | UnavailableController, OFFLINE/false; APIs DEV/simulada ausentes |
| Smoke isolado existente | 8 grupos aprovados; report bingo-simulation-test-7f41245ecea7 |
| Smoke DEV final | 7 grupos aprovados; report bingo-dev-integration-test-91a1e1e1501e |

O smoke DEV final também recusou contexto production e chave com formato JWT,
confirmou ausência de saída direta no backend e verificou a sentinela econômica
antes dos reinícios/recriações do próprio fixture, além da recuperação final.
Não se presume preservação do contador em memória do mock após recriá-lo.

## Arquivos deste incremento

Criados:

- backend/app/dev_integration.py: política, composição DEV, transporte restrito e
  cliente que reutiliza os contratos Supabase existentes;
- backend/app/dev_broker.py: fronteira interna, única portadora da chave técnica;
- backend/app/routes/dev.py: três projeções HTTP locais de leitura/identificação;
- backend/tests/test_dev_integration.py: segurança, escopo, contratos e recuperação;
- deploy/compose.dev-integration.yaml, dev-integration.env e
  start_dev_integration.py: perfil explícito, segredos e inicialização;
- deploy/validation/dev_integration_smoke.py e dev_mock.py: smoke sintético TLS;
- deploy/DEV_INTEGRATION.md: configuração, garantias, evidência e pendências.

Modificados: app/main.py (fábricas/rotas), app/simulation.py (reuso de composição
e marcador exclusivo), app/simulation_proxy.py (destino DEV fixo),
app/clients/supabase.py (injeção explícita de settings sem mudar contratos),
tests/test_simulation.py e test_simulation_flow.py (rotas cruzadas agora 404),
.dockerignore/Dockerfile (target e launcher DEV), backend/LOCAL_API_V1.md,
MECHANICAL_INTERNAL_V1.md, README.md e deploy/SIMULATION.md/README.md.
Frontend, schema/migrations/Functions/RLS Supabase e regras econômicas intactos.

## Dependências para 3C.2 e roadmap de retenção

Contratar a associação durável de seleção/PIN à sessão simulada, incluindo replay,
troca de turma, indisponibilidade e reload, antes de conectar as telas. Reutilizar
os estados existentes; não prometer login persistido por causa de uma resposta
stateless. A conclusão simulada continua COMPLETED/receipt=null, sem economia.
Classificação/revisão real e devolução continuam fora do contrato 3B.

A manutenção e retenção do SQLite permanece etapa obrigatória antes da homologação
física: distinguir reconciliados/terminais de ativos, pendentes e indeterminados;
preservar identidades, parâmetros, procedência, FK, histórico e barreiras de replay.
Não foram adicionados TTL, exclusão, expurgo ou reconciliação pública.

Problemas preexistentes .env.example (g# inicial) e verificador de migração que
procura camera_controller.js continuam separados e não foram corrigidos.
