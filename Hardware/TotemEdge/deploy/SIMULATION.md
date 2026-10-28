# TotemEdge — simulação isolada (3A) e contratos HTTP/estados (3B)

Este perfil executa FastAPI, SimulatedController e o mesmo journal mecânico.
No 3B, sessões simuladas identificadas no SQLite v3 usam os estados persistidos
de abertura/fechamento/alçapão. Não há integração do frontend, atuação física ou
registro de pontos. A demonstração visual anterior permanece independente.

## Arquitetura e isolamento

| Item | Simulação | Operacional existente |
| --- | --- | --- |
| Compose independente | `compose.simulation.yaml` | `compose.yaml` |
| Target Docker | `simulation`, explícito | `runtime`, último/default |
| Imagem | `bingo-totem-edge:simulation-dev` | `bingo-totem-edge:v1` |
| Entrada | `start_simulation.py` → `app.simulation:create_simulation_app` | `start.py` → `app.main:app` |
| Controller | SimulatedController, contexto development/test | UnavailableController por padrão |
| Central | BlockedCentralClient, sem HTTP/credenciais | Cliente existente preservado |
| SQLite | `/var/lib/bingo-simulation/simulation.sqlite3` | `/var/lib/bingo/totem.sqlite3` por padrão |
| Volume | `<projeto>_simulation-data` | `<projeto>_sqlite-data` |
| Rede do backend | Interna, sem rota default/DNS externo/porta no host | Publicação loopback existente |
| Ingresso HTTP 3B | simulation-http encaminha TCP fixo; host 127.0.0.1:8001 | Não participa |

Use somente o Compose específico, sem combiná-lo com `compose.yaml`. Ele não
interpola credenciais nem usa `env_file`. O `--env-file simulation.env` explícito
seleciona um arquivo versionado sem valores e evita carregar `.env` automaticamente.
Variáveis operacionais do shell não são encaminhadas. Proxies são vazios.

O backend recusa contexto não autorizado, parâmetros desconhecidos do perfil,
credenciais/configurações Supabase/AWS/Gemini/proxy não vazias e caminho SQLite
diferente do reservado. Não constrói cliente Supabase ou provedores de visão.
BlockedCentralClient recusa contexto, PIN e registro mesmo após mudanças no
ambiente do processo. O transporte HTTP de saída também é bloqueado.

O marcador `.bingo-simulation-only` só é criado em diretório vazio. Banco sem
marcador, arquivos estranhos, symlinks, confirmação física, payload/recibo/escopo
central ou comandos de origem física são recusados antes da recuperação.
Não há adoção automática de bancos existentes. O runtime operacional recusa esse
marcador e qualquer `BINGO_SIMULATION_*`, preservando a recuperação de seus bancos
normais. O 3A não alterou schema/estados; o 3B acrescenta somente a procedência
imutável cycles.simulated (schema 3) e liga a máquina existente ao mesmo journal.

Mantidos UID/GID 10001, rootfs readonly, capabilities removidas, nenhum dispositivo
ou privilégio, um worker e healthcheck existente. Somente o volume de simulação
é gravável. SIGTERM e lifespan drenam tarefas antes de fechar o store.

## Construir e iniciar

Use Docker Desktop com engine Linux iniciado. Comandos a partir de
`C:/Projetos/BinGo/Hardware/TotemEdge/deploy/` ou equivalente Linux:

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml config --quiet
docker compose --env-file simulation.env -f compose.simulation.yaml build
docker compose --env-file simulation.env -f compose.simulation.yaml up -d --no-build --wait --wait-timeout 90
docker compose --env-file simulation.env -f compose.simulation.yaml ps
```

O projeto padrão é `bingo-totem-edge-simulation`. Para um conjunto independente,
acrescente `--project-name NOME` em todos os comandos. Não são necessários
Supabase, Python no host ou credenciais para executar o perfil.

O backend continua sem porta publicada. Para o navegador, o serviço
simulation-http fica também numa rede de ingresso bridge e publica somente
`127.0.0.1:8001:8000`. Ele encaminha bytes para o destino fixo
totem-edge-simulation:8000, sem interpretar HTTP ou reescrever Host/Origin.
Não possui volume SQLite, clientes centrais ou controller. O backend permanece
somente na rede interna, com transporte externo e economia bloqueados.
O target Docker default e o Compose operacional continuam independentes.

O 3A havia tentado publicar porta na rede internal e encontrado recusa no Docker
Desktop. A solução 3B adiciona esse ingresso separado, preservando o isolamento
do backend, em vez de remover as guardas HTTP ou a rede interna.

## HTTP local e sequência do 3B

Abra `http://127.0.0.1:8001/` ou consulte a API nessa origem. A página original
continua exibindo bloqueio operacional: os arquivos do frontend não foram alterados.
Para a integração visual 3C, os [contratos completos](../backend/LOCAL_API_V1.md)
descrevem snapshots, ações permitidas e erros. Não usar a prontidão operacional
como autorização de simulação.

Exemplo PowerShell, servidor iniciado:

```powershell
$base = 'http://127.0.0.1:8001/local/simulation/sessions'
$headers = @{'X-Totem-Request'='1'; 'Origin'='http://127.0.0.1:8001'}
$start = @{command_id=[guid]::NewGuid().ToString()} | ConvertTo-Json
$snapshot = Invoke-RestMethod -Uri $base -Method Post -Headers $headers -ContentType 'application/json' -Body $start
$eventId = $snapshot.session.event_id
Invoke-RestMethod -Uri "$base/$eventId/safety" -Method Post -Headers $headers -ContentType 'application/json' -Body '{"has_risk":false}'
$motion = @{mechanical_command_id=[guid]::NewGuid().ToString()} | ConvertTo-Json
Invoke-RestMethod -Uri "$base/$eventId/open" -Method Post -Headers $headers -ContentType 'application/json' -Body $motion
Invoke-RestMethod -Uri "$base/$eventId" -Headers $headers
```

Não gere outro mechanical_command_id para repetir uma requisição sem resposta.
Reenvie o mesmo body ou consulte GET da sessão/active/comando. As durações
continuam no backend; GET não dispara operações nem fabrica conclusão.

Sequência: SAFETY → PHYSICAL_BLOCKED → OPENING → DOOR_OPEN → CLOSING →
DOOR_CLOSED → REVIEW → HATCH_IN_PROGRESS → COMPLETED. Cada movimento usa novo
ID próprio; fechamento exige hand_removed=true. Antes de hatch, chamar
review-fixture com `{}`: é checkpoint fictício, sem visão/classificação/categoria.
Após conclusão do alçapão, o estado permanece HATCH_IN_PROGRESS e libera apenas
confirm-initial. Sua conclusão simulada encerra sem recibo ou pontos.

Durante INTENT/DISPATCHING/ACCEPTED, allowed_actions é vazio. Aceitação não comprova
movimento concluído. Ação em estágio incorreto, ID conflitante ou tentativa de
cancelar porta aberta/movimento/indeterminação é recusada. Falha/timeout bloqueiam;
replay do ID original apenas retorna o resultado persistido.

Sessões 3A/anteriores recebem simulated=0 na migração e não são adotadas como
sessões da API 3B. O harness de baixo nível abaixo permanece disponível, mas deve
usar projeto/volume diferente daquele usado pela API. Se houver sessão legada
ativa, a API retorna SIMULATION_LEGACY_SESSION_ACTIVE, sem limpar ou promover dados.
Use outro --project-name para novos cenários; não edite a procedência.

## Verificar controller, saúde e SQLite

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml exec -T totem-edge-simulation python -m app.simulation_harness config
docker compose --env-file simulation.env -f compose.simulation.yaml exec -T totem-edge-simulation python /opt/totem/deploy/healthcheck.py
docker compose --env-file simulation.env -f compose.simulation.yaml logs --tail 30 totem-edge-simulation
docker compose --env-file simulation.env -f compose.simulation.yaml exec -T totem-edge-simulation python -c "from urllib.request import urlopen; print(urlopen('http://127.0.0.1:8000/local/status').read().decode())"
```

`config` mostra SimulatedController, central BLOCKED, SQLite e planos, sem abrir
store ou expor segredos. O log registra `SIMULATION ONLY`. Healthcheck termina
com código 0. `/local/status` mantém OFFLINE e can_start_deposit=false.
O volume padrão é `bingo-totem-edge-simulation_simulation-data`, montado em
`/var/lib/bingo-simulation`, contendo o banco, marcador e sidecars WAL/SHM/lock.

## Harness interno de baixo nível (compatibilidade 3A)

Pare o servidor antes de abrir o journal pelo harness. A trava de instância
única recusa duas instâncias no mesmo arquivo. Apenas `config` pode ser usado
com o servidor ativo, pois não abre CycleStore.

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml stop
docker compose --env-file simulation.env -f compose.simulation.yaml run --rm --no-deps totem-edge-simulation python -m app.simulation_harness run OPEN_INSERTION_DOOR
```

O JSON contém aceitação, conclusão SIMULATED, IDs e tempo observado no backend.
O harness usa o mesmo lifespan e serviços e cria somente uma fixture lógica via
store.create e SAFETY → PHYSICAL_BLOCKED. Não chama contexto/PIN central nem
avança para estados físicos. Outra operação explícita pode usar o mesmo ciclo
de teste enquanto ele permanecer PHYSICAL_BLOCKED.

Copie o mechanical_command_id retornado:

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml run --rm --no-deps totem-edge-simulation python -m app.simulation_harness show UUID_DO_COMANDO
docker compose --env-file simulation.env -f compose.simulation.yaml run --rm --no-deps totem-edge-simulation python -m app.simulation_harness replay UUID_DO_COMANDO
```

`show` retorna resultado e histórico; `replay` não redispara. `run --id UUID`
permite testar duplicação/conflito. Cada abertura do store realiza a recuperação
existente de startup; operações desconhecidas não são retomadas.

## Durações e falhas

Defaults ilustrativos existentes: abrir 3s, fechar 3s, alçapão 4s, confirmar estado
inicial 1s. Não são medições físicas. BINGO_SIMULATION_PLANS recebe JSON de
overrides por operação: duration_seconds finito não negativo e outcome SUCCEEDED,
FAILURE, UNAVAILABLE ou TIMEOUT. O harness aceita `run --timeout SEGUNDOS`.

Exemplo PowerShell com espera curta, servidor parado:

```powershell
$plans = '{"OPEN_INSERTION_DOOR":{"duration_seconds":0.05}}'
docker compose --env-file simulation.env -f compose.simulation.yaml run --rm --no-deps -e "BINGO_SIMULATION_PLANS=$plans" totem-edge-simulation python -m app.simulation_harness run OPEN_INSERTION_DOOR
```

FAILURE/TIMEOUT mantêm o ciclo indeterminado. Use projetos/volumes novos para
cenários independentes; não há reset ou reconciliação que apague o bloqueio.
O smoke usa volumes separados para essas falhas.

Interrupção abrupta após aceitação durável:

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml run --rm --no-deps totem-edge-simulation python -m app.simulation_harness run CYCLE_LOWER_HATCH --interrupt-after-accept
docker compose --env-file simulation.env -f compose.simulation.yaml up -d --no-build --wait --wait-timeout 90
```

O primeiro comando usa os._exit deliberadamente neste harness isolado. Startup
recupera UNKNOWN/INDETERMINATE e mantém o slot. Restart, recreate e replay não
reexecutam. Preserve esse volume como evidência e use outro projeto para continuar.

## Reiniciar e encerrar preservando dados

```powershell
docker compose --env-file simulation.env -f compose.simulation.yaml restart
docker compose --env-file simulation.env -f compose.simulation.yaml up -d --no-build --force-recreate --wait --wait-timeout 90
docker compose --env-file simulation.env -f compose.simulation.yaml stop
```

Restart/recreate preservam volume, procedência e estados estáveis compatíveis.
Uma intenção sem claim é abortada/restaurada; operação possivelmente despachada
sem conclusão persistida mantém UNKNOWN/INDETERMINATE, sem redisparo. `down` sem
`--volumes` remove containers/rede preservando dados. Somente o smoke remove
seus próprios volumes UUID efêmeros no teardown, sem tocar nos volumes padrão.

## Comandos de teste e evidência histórica 3A

Backend: `uv run --locked pytest -q`. Na pasta deploy:

```powershell
python -B -m unittest discover -s tests -p test_runtime.py -v
python -B validation/simulation_smoke.py --skip-build
```

Sem --skip-build, o smoke também constrói. Os comandos Compose foram exercitados
em projetos temporários com essa composição e credenciais-isca no shell.

| Verificação | Resultado |
| --- | --- |
| Baseline do Incremento 2 | 369 aprovados, zero falhas/skips. |
| Backend completo após 3A (histórico) | 415 aprovados, incluindo 46 novos, zero falhas/skips. |
| Runtime/deploy | 7 aprovados, zero skips. |
| Dockerfile build check | Aprovado, sem avisos. |
| Builds de simulação e default operacional AMD64 | Aprovados; target default continua operacional. |
| Smoke da imagem default, sem rede e rootfs readonly | UnavailableController e OFFLINE/false confirmados. |
| Smoke Compose | 7 grupos aprovados: configuração isolada; startup/rede; temporização/journal; restart/recreate; configuração perigosa; falha/timeout; interrupção/UNKNOWN sem redisparo. |

Evidência histórica 3A: `deploy/.validation/bingo-simulation-test-20c0a68e1fc2/report.json`.
A primeira tentativa, `bingo-simulation-test-a20513d9dd2b`, falhou no acesso à
porta host com rede interna; a composição final daquele incremento não publicava
portas e passou. O ingresso HTTP separado foi acrescentado e validado no 3B.
Não foram executados ARM64, navegador ou homologação física.

## Validação do Incremento 3B — 28/10/2026

Baseline 3A reexecutado antes das alterações: **415 testes backend aprovados**.
Após a integração: **460 aprovados**, incluindo 45 novos testes, sem falhas/skips.
Cobrem sequência, rollback atômico, persistência antes do despacho, concorrência,
replay/conflitos, cancelamento, falhas/timeouts, respostas incompatíveis,
recuperação nas janelas de interrupção, migração real de v1/v2, procedência e
isolamento econômico. As asserções antigas de versão passaram de 2 para 3;
o OpenAPI operacional continua idêntico nas fábricas, com rotas adicionais
exclusivamente no namespace simulado.

Também executados: 7 testes de runtime/deploy; 7 testes JS existentes de contrato
local (sem alteração de frontend); formatter de 41 arquivos Python aprovado;
Dockerfile build check sem avisos; build da simulação e do target default AMD64.
O smoke da nova imagem operacional, com rede desabilitada/rootfs readonly,
confirmou UnavailableController, OFFLINE/false e 404 no namespace simulado.

O smoke Compose passou em **8 grupos**, preservando os 7 cenários 3A e acrescentando
HTTP real no loopback: Host/Origin/header, abertura/fechamento/alçapão/confirmação,
snapshot/replay sem redisparo, recreate com dados preservados e SIGKILL durante
abertura aceita. Após recuperação, o journal permaneceu indeterminado e cancelamento
foi recusado. Nenhuma chamada central, confirmação física ou recompensa foi criada.
Evidência: `deploy/.validation/bingo-simulation-test-d9ae4d01eae8/report.json`.
Os volumes criados por esse smoke foram removidos somente no teardown de seus
projetos UUID; volumes de desenvolvimento e operação não foram tocados.

Não executados: integração visual num navegador, ARM64, sensores ou hardware.
HTTP foi exercitado pelo cliente real do smoke no host e por TestClient em testes.

## Problemas preexistentes e limites

O `.env.example` operacional começa com `g#`, inválido para Compose; foi
preservado e não participa deste perfil. O verificador histórico procura
frontend/camera_controller.js ausente; não foi reexecutado ou corrigido no 3A.

Não participam: hardware, câmera, provedores de visão, contexto/PIN central,
economia e frontend mecânico. Os estados físicos nomeados são apenas simulados.
O histórico não tem
expurgo automático. O perfil não protege contra um administrador que altere
deliberadamente código, imagem, rede ou volumes para contornar suas guardas.
Não houve commit, push, merge, deploy ou ação em Supabase real.

## Dependências para o 3C e retenção futura

Conectar a UI oficial somente à API simulada quando explicitamente selecionada
na composição de desenvolvimento. Preservar event_id e IDs de ações; usar active
após reload, GET durante movimento e consulta por event_id para ciclos terminais.
Exibir procedência simulada, allowed_actions e fases do journal. Não introduzir
timers JavaScript que avancem estados nem retry automático de movimento.

Ainda decidir contratos de contexto/turmas/PIN de teste, classificação/revisão
visual e apresentação de conclusão sem recompensa. O checkpoint review-fixture
não substitui essas decisões. Manter BlockedCentralClient e não alterar o
significado de ONLINE/can_start_deposit operacional.

A etapa posterior de retenção/ manutenção deve distinguir terminais reconciliados
de ativos, pendentes e indeterminados, mantendo identidade, parâmetros, procedência,
FK, histórico imutável e barreiras de replay. Não há expurgo ou TTL neste incremento.
