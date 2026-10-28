# TotemEdge — simulação isolada (Incremento 3A)

Este perfil executa FastAPI, SimulatedController e o journal SQLite v2 existentes.
Não integra movimentos ao frontend, não libera estados físicos e não registra
descartes ou pontos. A demonstração visual anterior permanece independente.

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
| Rede | Interna, sem rota default, DNS externo ou porta no host | Publicação loopback existente |

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
normais. Não houve alteração de schema, journal ou máquina de estados no 3A.

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

Não há porta publicada no host no 3A. No Docker Desktop testado, rede `internal`
deixou o container saudável mas não encaminhou a porta publicada. A publicação
foi removida; HTTP é verificado por exec no container. Isso atende aos testes
internos do 3A. O ingresso do navegador será definido no 3B sem liberar saída.

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

## Harness interno, sem endpoints mecânicos

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

Restart/recreate preservam o volume e a procedência simulada. `down` sem
`--volumes` remove containers/rede preservando dados. Somente o smoke remove
seus próprios volumes UUID efêmeros no teardown, sem tocar nos volumes padrão.

## Testes executados

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
| Backend completo após 3A | 415 aprovados, incluindo 46 novos, zero falhas/skips. |
| Runtime/deploy | 7 aprovados, zero skips. |
| Dockerfile build check | Aprovado, sem avisos. |
| Builds de simulação e default operacional AMD64 | Aprovados; target default continua operacional. |
| Smoke da imagem default, sem rede e rootfs readonly | UnavailableController e OFFLINE/false confirmados. |
| Smoke Compose | 7 grupos aprovados: configuração isolada; startup/rede; temporização/journal; restart/recreate; configuração perigosa; falha/timeout; interrupção/UNKNOWN sem redisparo. |

Evidência final: `deploy/.validation/bingo-simulation-test-20c0a68e1fc2/report.json`.
A primeira tentativa, `bingo-simulation-test-a20513d9dd2b`, falhou no acesso à
porta host com rede interna; a composição final não publica portas e passou.
Não foram executados ARM64, navegador ou homologação física.

## Problemas preexistentes e limites

O `.env.example` operacional começa com `g#`, inválido para Compose; foi
preservado e não participa deste perfil. O verificador histórico procura
frontend/camera_controller.js ausente; não foi reexecutado ou corrigido no 3A.

Não participam: hardware, câmera, provedores de visão, contexto/PIN central,
economia, frontend mecânico e estados físicos positivos. O histórico não tem
expurgo automático. O perfil não protege contra um administrador que altere
deliberadamente código, imagem, rede ou volumes para contornar suas guardas.
Não houve commit, push, merge, deploy ou ação em Supabase real.

## Recomendação para o 3B

Definir ingresso HTTP local para o navegador mantendo o backend na rede interna.
Definir ações/snapshots simulados e persistir transições junto ao journal/CAS,
reutilizando event_id e IDs após reload. O frontend deve acompanhar estados do
backend sem temporizadores de movimento e preservar bloqueio diante de UNKNOWN.
Manter BlockedCentralClient, volume marcado e guardas econômicas. Não alterar
ONLINE/can_start_deposit operacional para liberar a interface de desenvolvimento.
