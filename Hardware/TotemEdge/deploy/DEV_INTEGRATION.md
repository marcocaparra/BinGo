# Integração DEV do TotemEdge — Incrementos 3C.1 e 3C.1.1

Atualização de provisionamento: a política mínima exige somente project_ref,
machine_id e school_id. Turmas e alunos são consultados dinamicamente no contexto
da máquina autenticada; não é necessário duplicar o cadastro no JSON local.

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
O schema agora é v4, com cycles.simulated imutável e snapshots source/commands/
allowed_actions preservados, acrescidos de identity. Não há adoção ou cópia
automática entre volumes. A política mínima de três campos permanece intacta.

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

O RPC de contexto retorna a escola vinculada à máquina autenticada, suas turmas
e seus alunos ACTIVE. Não recebe escola escolhida pelo solicitante. A Function
passa à RPC somente o ID confiável produzido por machine-auth. O cliente verifica
o ID da máquina e compara school_id com a escola retornada; o ID local é uma
expectativa de consistência, não uma autoridade para escolher outra escola.

Antes do PIN, o cliente reconsulta o contexto e exige a turma e o aluno naquela
turma. A RPC get_totem_student_pin_record_v1 verifica novamente escola, turma,
aluno e ACTIVE, e a Function valida o hash do PIN. Mudanças entre as consultas não
permitem autenticar por um contexto antigo. Não há cache local de autorização.

O usuário confirmou que Escola Demo BinGo é exclusivamente fictícia. Seu nome
não é fixado no código: use o UUID esperado da escola. Continuam obrigatórios
projeto DEV, identidade técnica válida e dataset de desenvolvimento; não usar
escola com pessoas reais ou dados mistos.

Criar dois arquivos fora do checkout e das imagens, com acesso de leitura restrito
ao operador/Docker. Não enviar seu conteúdo ao chat ou a relatórios:

- Política JSON UTF-8, sem BOM, com os três campos abaixo; substituir os UUIDs
  fictícios pelos IDs existentes da máquina e da escola esperada.
- Arquivo de chave contendo somente a API key técnica da máquina, UTF-8 sem BOM.
  É aceito um terminador de linha de arquivo. JWTs e chaves Supabase sb_* são
  recusados; não fornecer anon, publishable, secret API key ou service_role.

```json
{
  "project_ref": "ddxmohrjcxuibswmrtla",
  "machine_id": "11111111-1111-4111-8111-111111111111",
  "school_id": "22222222-2222-4222-8222-222222222222"
}
```

Não há chave no JSON. Destino diferente, campos extras, arquivos ausentes,
symlinks, configuração de proxy, mistura de perfis ou credenciais em ambiente
provocam recusa. Marcador exclusivo .bingo-dev-integration-only é criado apenas
em diretório vazio; bancos físicos/econômicos são recusados antes da recuperação.

Para migrar manualmente uma política 3C.1, preserve project_ref, machine_id e
school_id e remova **ambos** class_ids e student_ids. Não altere o arquivo da chave.
test_data_only=true permanece aceito como declaração legada opcional; false,
números e outros valores continuam recusados. O novo formato não exige esse campo.

Compatibilidade: se as duas listas antigas permanecerem, continuam sendo
restrições adicionais, com a mesma recusa de contextos que contenham IDs fora
delas. Não são descartadas silenciosamente. Listas devem vir juntas, sem null,
sem duplicatas e com class_ids não vazio. student_ids=[] só funciona para contexto
sem alunos ACTIVE; não é um filtro remoto. Para descoberta dinâmica, omita as duas
listas. Novas turmas/alunos ACTIVE aparecerão em consultas subsequentes sem editar
ou reiniciar a política. A troca da política carregada exige reiniciar os serviços.

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
| GET /local/dev/context | Mesmo TotemContext existente | Escola/máquina e turmas/alunos ACTIVE consultados dinamicamente; sem PIN/hash/credencial |
| POST /local/dev/student-pin | class_id, student_id UUID e pin de quatro dígitos ASCII | Mesmo PinConfirmation existente; confirmed=true somente após resposta central validada |
| POST /local/dev/sessions/{event_id}/identity | Mesmo body de PIN, associado ao event_id | SimulationSnapshot com vínculo persistido; primeira confirmação leva a SAFETY; retry idêntico consulta; outra identidade conflita (3C.1.1) |

PIN é transitório, somente JSON, não entra em logs, URLs ou SQLite. O cliente
reconsulta contexto para verificar aluno/turma ACTIVE antes de confirmar. A
Function permanece autoridade da identificação. A rota student-pin é independente
do ciclo mecânico e não grava identidade. A rota vinculada sessions/{event_id}/identity
é a extensão 3C.1.1; sua sequência e persistência estão descritas abaixo.

Host/Origin local, escrita JSON com X-Totem-Request:1, ausência de query, recusa
de campos extras, erros sanitizados e Cache-Control:no-store são preservados.
403: guarda local/capacidade/IDs fora do contexto ou das restrições legadas; 422: contrato; 401: PIN inválido
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

Na entrega 3C.1 não foram feitas chamadas hospedadas. Foram identificadas configurações antigas
com URL do DEV e campos de máquina/chave preenchidos no Simulator e no deploy;
seus valores não foram exibidos nem reutilizados. Não foi fornecida a política
de escola/IDs exclusivamente sintéticos autorizada para este perfil. Como contexto
consulta a escola inteira, não foi presumida autorização para ler esses alunos.
A pendência é o conjunto de configuração aprovado, não ausência genérica de chave.
A comprovação de saldos/depósitos/XP inalterados
é local, pela sentinela; não é comparação SQL do Supabase remoto. Não foram
executados ARM64, hardware, câmera, navegador ou integração visual.

Resultados históricos do 3C.1, executados em 2026-10-28:

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

## Validação da simplificação do provisionamento

Branch feature/orange-pi-integration, HEAD c2ee3bb, working tree inicialmente
limpa. A análise confirmou que as listas anteriores eram restrições locais após
a consulta, não a origem da autorização escolar. A fonte de verdade permanece
nas Functions/RPCs versionadas, sem mudanças em autenticação, grants ou tabelas.

- Baseline reexecutada: 528 testes backend aprovados.
- Após a alteração: 552 testes backend aprovados, sem falhas/skips; 92 são do
  perfil DEV. Incluem política mínima, compatibilidade restritiva, descoberta de
  nova turma/aluno sem editar JSON, mudança de turma, aluno fora do contexto,
  contrato de PIN, recusa central após consulta, máquina/escola divergentes,
  bloqueio econômico, três runtimes e recuperação.
- Runtime/deploy: 7 testes; contratos JS existentes: 7 testes aprovados.
- Builds DEV/isolado e Dockerfile build check aprovados, sem alteração do Compose.
- Smoke DEV: 7 grupos aprovados, usando a política de três campos e HTTPS com
  Functions sintéticas. Evidência: .validation/bingo-dev-integration-test-f4812036cee4/report.json.
- Smoke isolado: 8 grupos aprovados. Evidência:
  .validation/bingo-simulation-test-c339c54eec43/report.json.
- Formatter e git diff --check aprovados.

Não foram lidos, montados ou alterados os arquivos reais de C:/BinGoDevSecrets;
os testes geraram seus próprios arquivos sintéticos em diretórios temporários.
Não houve chamadas hospedadas, operações econômicas reais, deploys, migrations,
commits ou alterações de frontend/SQLite. A homologação hospedada deve ocorrer
depois da atualização manual da política e recriação dos serviços, verificando
health, identidade/escola retornadas por contexto e PIN pelo broker existente.

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

## Associação durável de identidade — 3C.1.1

Em 29/10/2026, o usuário informou homologação hospedada de health, contexto da
Escola Demo BinGo/máquina Totem Dev Cloud 01 e PIN confirmado pelo broker.
Isso comprova a identificação stateless anterior; não comprova a nova associação.
Nenhum PIN, hash, cadastro ou credencial precisa ser alterado neste incremento.

Implementação anterior: SimulationFlow criava fixtures class_only em SAFETY em
ambos os perfis; student-pin somente retornava uma confirmação. Agora somente o
DEV cria sessões student em IDENTIFYING e exige associação antes de safety/open.
A fábrica isolada mantém as fixtures e não consulta Supabase. Operacional
continua UnavailableController, OFFLINE/can_start_deposit=false.

O contrato novo local é POST `/local/dev/sessions/{event_id}/identity`, usando
o mesmo body class_id/student_id/pin do contrato central. Não há outro token,
login, Function ou broker. `/local/dev/student-pin` permanece stateless para
diagnóstico e nunca libera uma sessão. Consultar [LOCAL_API_V1](../backend/LOCAL_API_V1.md)
para entradas, snapshots, ações e códigos de erro.

Fluxo: criação idempotente → IDENTIFYING → confirmação real pelo Supabase →
commit local de associação e histórico → SAFETY → declaração de segurança →
PHYSICAL_BLOCKED → abertura/fechamento/review-fixture/alçapão/retorno simulados.
Somente depois de persistir o vínculo aparece safety em allowed_actions.
IDs da instalação e da turma/aluno validados vêm do contexto/confirmação central;
nomes públicos são projetados na Session, sem armazenar catálogo ou saldo local.
O placeholder da turma inicial não constitui autorização. O nome da escola não
é condição de segurança nem é fixado no código.

SQLite migra automaticamente de v1/v2/v3 para v4 via PRAGMA user_version,
BEGIN IMMEDIATE e o inicializador existente. A única tabela nova,
simulation_identities, usa event_id como PK/FK, guarda project_ref, machine_id,
school_id, class_id, student_id, validated_at UTC e source=SUPABASE_DEV_PIN_V1.
Class/student IDs são repetidos nessa evidência mínima imutável para correlacionar
e conferir a projeção Session; nomes não são duplicados. Triggers impedem
UPDATE/DELETE do vínculo e troca dos IDs associados em cycles. Auditoria reutiliza
transitions, sem segundo journal. Não há PIN/hash/chave/body sensível no SQLite.
Não executar uma imagem antiga sobre o banco v4; ela recusa versão não suportada.

Não há transação distribuída: a chamada remota ocorre sem transação SQLite.
Após confirmed=true e IDs consistentes, o commit revalida versão/estado/slot.
Mesmo par de IDs concorrente converge; identidade divergente dá 409. Cancelamento
durante HTTP impede commit tardio. Queda antes do commit deixa IDENTIFYING e exige
nova validação; depois dele, GET recupera o vínculo mesmo sem rede. POST repetido
continua exigindo confirmação central atual, preservando o vínculo anterior.
AUTHENTICATING e SAFETY são auditados juntos após a confirmação, sem deixar uma
reserva de autenticação pendente por timeout/cancelamento da requisição.

Correção de segurança após homologação: retry de identidade já vinculada também
revalida health, contexto e PIN na Function. PIN incorreto de quatro dígitos
retorna 401; indisponibilidade retorna erro, inclusive após restart. PIN correto
retorna o snapshot atual, sem alterar vínculo, validated_at ou histórico.
Outra identidade sempre conflita. GET é recuperação idempotente sem PIN;
POST é tentativa efetiva de autenticação. Vínculo é histórico, não autorização
reutilizável em requisições futuras nem em outra sessão.

POSTs open/hatch agora exigem pin no JSON, além do comando existente, e validam
o segredo na Function para o aluno/turma do vínculo. Isso impede atuar apenas
conhecendo event_id. Reconsultam health/contexto e exigem o aluno ainda ACTIVE.
Falha central impede sua intenção/despacho. Replay via POST também autentica;
após confirmação retorna o mesmo comando sem redisparo. GET de sessão/comando
continua disponível sem PIN ou rede. close/confirm-initial
mantêm as pré-condições e journal existentes, sem exigir rede, para permitir
encerramento seguro do mecanismo. Estado indeterminado permanece bloqueado.
Sessões legadas sem vínculo não são adotadas: cancelar as pré-físicas seguras
e criar outra; após movimento não há associação retroativa ou cancelamento
artificial. Não foi acrescentada reconciliação pública.

Trade-off: há chamadas centrais e fornecimento transitório de PIN em cada POST
de identificação/open/hatch. Evita emitir tokens próprios ou guardar PIN/login
em memória. Não reutilizar o PIN automaticamente em timers/caches do futuro
frontend. O 3C.2 deverá acomodar a confirmação por ação ou obter aprovação para
outro contrato de autorização, sem promover vínculo histórico a credencial.

Risco residual explícito: as APIs são do dispositivo local de desenvolvimento,
não um sistema de autorização entre usuários locais. event_id é consultável por
GET; Host/Origin/header não autenticam um processo local. cancelamento seguro,
close e confirm-initial continuam disponíveis sem Supabase, por recuperação;
safety/review-fixture podem ser solicitados por um cliente local que satisfaça
essas guardas. Não permitem open/hatch sem PIN, mudar a identidade ou gerar
economia. Um cliente local malicioso ainda pode interromper checkpoints ou pedir
movimentos simulados de recuperação. Exigir host confiável e não expor o DEV;
autorização de dispositivo/operador precisa de contrato próprio antes do hardware.

PIN fica somente no processamento da chamada; referências explícitas no body e
serviço são descartadas em finally, sem cache/tarefas/histórico/log de body.
Python/HTTP não garantem apagamento criptográfico imediato de strings em memória.
Não há limite de tentativas definido/implementado no contrato central existente;
este incremento não inventa contador, TTL ou bloqueio com política própria.

### Verificação manual hospedada do novo vínculo

Reutilize os mesmos arquivos externos e o Compose. Não apague volumes. Na pasta
deploy, carregue somente os caminhos e recrie as imagens/serviços após a atualização:

```powershell
$env:BINGO_DEV_POLICY_FILE = 'C:/BinGoDevSecrets/dev-policy.json'
$env:BINGO_DEV_MACHINE_KEY_FILE = 'C:/BinGoDevSecrets/dev-machine-key'
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml config --quiet
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml build
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml up -d --no-build --force-recreate --wait --wait-timeout 90
```

Consulte health/contexto e confira os UUIDs de máquina/escola com o cadastro
autorizado. Escolha somente aluno fictício ACTIVE da turma retornada. Antes de
criar uma sessão, consulte a ativa: sessão indeterminada não deve ser apagada ou
substituída. Preserve o command_id em caso de timeout da criação.

```powershell
$base = 'http://127.0.0.1:8002'
$headers = @{ 'X-Totem-Request' = '1' }
Invoke-RestMethod "$base/local/dev/health"
$context = Invoke-RestMethod "$base/local/dev/context"
$active = Invoke-RestMethod "$base/local/simulation/sessions/active"
# Se não houver ativa, criar; se houver, recuperar seu event_id e estado primeiro.
$commandId = [guid]::NewGuid().ToString()
$snapshot = Invoke-RestMethod "$base/local/simulation/sessions" -Method Post -Headers $headers -ContentType 'application/json' -Body (@{command_id=$commandId} | ConvertTo-Json)
$eventId = $snapshot.session.event_id
# Informar IDs retornados pelo contexto, não PIN no comando/histórico do shell.
$classId = Read-Host 'UUID da turma fictícia autorizada'
$studentId = Read-Host 'UUID do aluno fictício autorizado'
$securePin = Read-Host 'PIN de teste existente (quatro dígitos)' -AsSecureString
try {
  $body = @{class_id=$classId; student_id=$studentId; pin=([System.Net.NetworkCredential]::new('', $securePin)).Password}
  $snapshot = Invoke-RestMethod "$base/local/dev/sessions/$eventId/identity" -Method Post -Headers $headers -ContentType 'application/json' -Body ($body | ConvertTo-Json)
} finally {
  $body = $null
  $securePin.Dispose()
  $securePin = $null
}
$snapshot.identity
$snapshot.session.state  # SAFETY após primeiro vínculo
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml restart totem-edge-dev
docker compose --env-file dev-integration.env -f compose.dev-integration.yaml up -d --no-build --wait --wait-timeout 90
$restored = Invoke-RestMethod "$base/local/simulation/sessions/$eventId"
$restored.identity  # Mesmos IDs, origem e validated_at
```

O endpoint de identidade permite retry com os mesmos IDs e PIN correto se a resposta
se perder; GET é o contrato de refresh e recuperação offline. Após restart,
repetir POST com PIN errado deve retornar 401 e manter identity/validated_at.
PIN de três dígitos deve retornar 422. Uma sessão cancelada mantém seu vínculo
somente como histórico e não permite retomar safety/open. Não exibir respostas
como recibos ou recompensa. Os comandos de safety/movimento continuam nos
contratos 3B, com pin obrigatório no JSON de open/hatch no DEV; usar IDs mecânicos
persistidos e GET de comandos para acompanhar,
sem inferir conclusão a partir do tempo decorrido. Nunca chamar register.

O smoke DEV agora reserva outra porta loopback efêmera com override exclusivo de
teste (Compose com suporte a !override), preservando o DEV hospedado em :8002.
Ele monta somente política/chave sintéticas, verifica identidade antes do fluxo,
replay após conclusão/restart/recreate e mantém a sentinela econômica inalterada.

### Validação do 3C.1.1 — 29/10/2026

Baseline reexecutada: 552 testes backend aprovados. Suíte completa final:
597 aprovados, sem falhas/skips, incluindo 45 novos testes em test_dev_identity.py.
Cobertura: vínculo/PIN correto/incorreto, IDs fora do contexto, ACTIVE,
máquina/escola divergentes, resposta inconsistente, rede/timeout, replay e conflito,
duas confirmações concorrentes, cancelamento durante HTTP, rollback de transições
e INSERT, restart antes/depois do commit, imutabilidade, ausência de segredos em
SQLite/logs/snapshots, disponibilidade antes de novos movimentos e continuidade
segura sem rede. Migrações v1/v2/v3 preservam sessões/journal/histórico; simulação
isolada e operacional continuam cobertos pelas suítes anteriores.

Runtime/deploy: 7 aprovados. Contratos JavaScript existentes: 7 aprovados.
Ruff format e git diff --check aprovados. Dockerfile build check sem avisos.
Smoke isolado: oito grupos aprovados, com build, HTTP protegido, fluxo completo,
restart/recreate e SIGKILL. Evidência:
.validation/bingo-simulation-test-f2effe2c2723/report.json.
Smoke DEV da imagem final: sete grupos aprovados, com associação antes de safety,
quatro movimentos lógicos, replay/conflito, restart/recreate e SIGKILL mantendo
UNKNOWN/INDETERMINATE. Evidência:
.validation/bingo-dev-integration-test-c1f4c6198d11/report.json.
A sentinela sintética permaneceu com zero depósitos, saldo 800 e XP 1900 em todos
os checkpoints. Containers/volumes de teste foram removidos pelo teardown;
os três containers DEV hospedados do usuário não foram parados/recriados.
Os smokes Docker usam somente arquivos sintéticos, nunca C:/BinGoDevSecrets ou
o Supabase hospedado. As verificações hospedadas acima foram informadas pelo
usuário; a nova associação exige a verificação manual descrita nesta seção.

Arquivos da extensão: app/cycles.py (modelo), app/storage.py (v4/transações),
app/services/simulation_flow.py (orquestração), app/main.py (injeção),
app/routes/dev.py (contrato), tests/test_dev_identity.py (novo),
tests/test_dev_integration.py (fluxo DEV), test_controller.py,
test_mechanical_journal.py e test_simulation_flow.py (fixtures/versão de schema),
validation/dev_integration_smoke.py e simulation_smoke.py,
LOCAL_API_V1.md, MECHANICAL_INTERNAL_V1.md, SIMULATION.md e este documento.
A simplificação anterior de app/dev_integration.py foi preservada integralmente.
Não foram alterados Compose, Dockerfile, frontend, Functions ou PostgreSQL.

### Correção de segurança do replay — 29/10/2026

Causa raiz: SimulationFlow.identify retornava antes de chamar Supabase quando
encontrava vínculo com os mesmos IDs. A política anterior tratava POST como
consulta de replay e aceitava PIN incorreto sintaticamente válido. Essa decisão
foi substituída: todo POST de identidade autentica; somente GET recupera estado
sem autenticar. A gravação continua idempotente, com validated_at original e sem
duplicar associação/transitions. Não há nova migration: schema permanece v4.

Revisão da atuação: event_id/identity podem ser obtidos por GET e não comprovam
autoria da ação. POST open/hatch agora valida PIN pela Function para os IDs
persistidos, também em replay. O PIN é transitório e não compõe o journal.
A correção não fornece isolamento entre processos locais: checkpoints e ações
de recuperação mantêm as exceções seguras e o requisito de host confiável acima.

Baseline reexecutada: 597 testes backend aprovados. Após a correção: 617
aprovados, sem falhas/skips, com 20 casos adicionais. Os 202 focados passaram.
Incluem primeira identificação e retry, PIN correto/incorreto/formato inválido,
falha central sem perda do vínculo, GET após restart sem central, concorrência
com PIN correto/incorreto, autorização open/hatch, replay sem novo comando,
continuidade segura offline, ausência de segredos/economia e contrato isolado.
Runtime/deploy e JavaScript existentes: 7 + 7 aprovados. Format, diff-check e
Dockerfile build check aprovados. Nenhum segredo/configuração externa,
PostgreSQL, Function, frontend ou Compose foi modificado nesta correção.
Smoke DEV corrigido: sete grupos aprovados, remote_supabase=false, incluindo
PIN errado após restart, confirmação de chamada à Function e SQLite inalterado;
open/hatch recusam ausência de PIN e PIN incorreto antes do comando. Evidência:
.validation/bingo-dev-integration-test-fc3dd90266a6/report.json.
Zero depósitos, saldo 800 e XP 1900 em todos os checkpoints sintéticos.
A nova correção não foi executada contra o Supabase hospedado, e os containers
do usuário em :8002 não foram recriados. Rebuild/recreate manual pelos comandos
acima é necessário para carregar o código corrigido sem apagar o volume.
Smoke isolado: oito grupos aprovados, incluindo HTTP protegido, restart/recreate
e SIGKILL sem redisparo. Evidência:
.validation/bingo-simulation-test-92e0c42324e2/report.json.
Todos os containers/volumes dos projetos UUID de teste foram removidos pelo
teardown, preservando os serviços e volumes do usuário.

## Dependências para 3C.2 e roadmap de retenção

Consumir a associação durável e allowed_actions do 3C.1.1 nas telas existentes,
preservando command_id/event_id/IDs mecânicos durante timeout e reload. Não usar
student-pin stateless como autorização de sessão. Tratar 401/403/409/503 e identidade
imutável, sem tentar trocar o aluno silenciosamente ou recriar ciclo indeterminado.
A conclusão simulada continua COMPLETED/receipt=null, sem economia.
Classificação/revisão real e devolução continuam fora do contrato 3B.

A manutenção e retenção do SQLite permanece etapa obrigatória antes da homologação
física: distinguir reconciliados/terminais de ativos, pendentes e indeterminados;
preservar identidades, parâmetros, procedência, FK, histórico e barreiras de replay.
Não foram adicionados TTL, exclusão, expurgo ou reconciliação pública.

Problemas preexistentes .env.example (g# inicial) e verificador de migração que
procura camera_controller.js continuam separados e não foram corrigidos.
