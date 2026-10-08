# Validação da containerização — 2026-10-08

## Ambiente e escopo

Branch `feature/totem-edge-backend-foundation`. Desenvolvimento em Windows,
Docker Desktop com engine Linux **x86_64**, kernel
`6.18.40.1-microsoft-standard-WSL2`, 4 CPUs e 10.382.225.408 bytes disponibilizados
à VM (~9,669 GiB). Docker 29.0.1, Compose 2.40.3 e Buildx 0.29.1.
Outros serviços de desenvolvimento preexistentes estavam ativos no engine.
Nenhum resultado é medição ou homologação do Orange Pi Zero 3.

Foram consultados todos os documentos exigidos. O código atual, LOCAL_API_V1 e
INTEGRATION_V1 já incluem frontend servido pelo FastAPI e SQLite. O diagnóstico
de migração e trechos do documento offline/STATUS descrevem etapas anteriores;
essas referências históricas não foram usadas para desfazer a integração local.
Não há conflito que exija alterar negócio, autenticação ou recuperação.

Não foram usados segredos reais, Supabase hospedado, descartes ou dispositivos.
Não houve commit, merge, push, publicação de imagem ou deploy no Orange Pi.

## Arquivos e arquitetura resultantes

Criados:

- `../.dockerignore`: contexto restrito aos inputs de produção.
- `Dockerfile`: build em estágios; Python 3.12.15 slim e uv 0.12.19 fixados por
  digest multiarch; lock existente, somente wheels/dependências de produção.
- `compose.yaml`: um serviço, loopback configurável, volume integral, filesystem
  somente leitura, capacidades removidas, logs limitados e stop gracioso.
- `.env.example`: configuração segura sem credenciais.
- `start.py`: guarda de volume/caminho absoluto e exec de Uvicorn com um worker.
- `healthcheck.py`: somente liveness local existente.
- `tests/test_runtime.py`: seis testes de configuração/healthcheck.
- `validation/container_smoke.py`: HTTP, segurança básica, integridade, fixtures
  SQLite, reinício/recriação e métricas em projetos/volumes exclusivos.
- `validation/browser_smoke.cjs`: navegador externo à imagem; modo real bloqueado
  e demonstração isolada sem erros de carregamento.
- `README.md` e `VALIDATION.md`: operação, instalação, atualização e evidências.

Alterados: `deploy/.gitignore` e `../README.md`.
**Nenhum arquivo do backend ou frontend funcional foi alterado.** Schema,
máquina de estados, idempotência, recuperação e lock permanecem originais.
UI de origem, Simulator, camera/controller, BinGoVision, documentos centrais,
migrations e Edge Functions permaneceram sem alterações nesta tarefa.

Layout: cwd `/opt/totem/backend`; frontend irmão `/opt/totem/frontend`, venv em
`/opt/venv`, SQLite configurável dentro do volume `/var/lib/bingo`.
UID/GID 10001:10001; diretório persistente 0700, umask 077. Sem root no runtime,
servidor adicional, uv/pytest ou downloads no startup.
Um processo Uvicorn; o launcher é substituído por exec. Healthchecks geram um
processo Python breve. Não há limite rígido CPU/RAM sem medição no equipamento.

## Verificações concluídas

| Verificação | Resultado |
| --- | --- |
| `docker compose --env-file .env.example config --quiet` | Aprovado |
| `docker buildx build --check -f Dockerfile ..` | Aprovado, sem warnings do Dockerfile |
| Build nativo `linux/amd64` | Aprovado, Python 3.12.15 e 16 pacotes locked; sem compilação |
| Build cruzado `linux/arm64 --load` | Aprovado, os mesmos 16 pacotes e wheel nativa de pydantic-core |
| Execução ARM64 emulada (override de teste) | Aprovada: health, status OFFLINE/false, 50 arquivos íntegros, entrada demo, restart/recreate e UUID/payload/journal preservados |
| Testes de deploy no host | 6/6, inclusive escape por symlink, recusa de volume ausente e liveness inválida |
| Testes de deploy no container Linux AMD64 | 6/6; tests montados readonly e tmpfs temporário somente no teste |
| Testes de deploy no container ARM64 emulado | 6/6, inclusive symlink; mesma imagem sem pacotes de teste instalados |
| Backend `uv run --locked pytest -q` | 137/137 em Python 3.12, Supabase controlado/SQLite temporário |
| Backend `uv format --check -- app tests` | 24 arquivos aprovados |
| Integridade frontend existente | 43 arquivos idênticos à origem; três ajustes anteriores preservados; três assets adicionais idênticos |
| Verificador HTTP/sintaxe frontend existente | 51 arquivos HTTP; 41 referências locais; sintaxe dos três JS aprovada |
| Cliente JS `node --test validation/local_api.test.cjs` | 7/7 |
| Smoke demonstrativo existente | 29 telas, três pares de screenshots idênticos, 10 fluxos; 815 requests, zero erros |
| Smoke operacional existente | 6 verificações, zero erros na execução final isolada |
| Smoke browser no container AMD64 | Real bloqueado, revisão URL sem sucesso artificial, demo sem `/local/*`, imagens/fontes carregadas; zero erros |
| HTTP/estáticos no container AMD64 | `/health`, `/local/status`, sessão ativa e demo acessíveis; 50 arquivos de runtime idênticos byte a byte |
| Persistência AMD64 | Reinício e force-recreate preservaram volume, mesmo event_id/payload de sete campos e pending sem recibo; uma linha, SQLite integrity_check=ok |
| Startup e segurança AMD64 | Healthcheck healthy, UID não root, rootfs readonly, sem privilégios/dispositivos, porta publicada somente em 127.0.0.1 |
| Startup sem volume | Recusado antes de iniciar FastAPI, mensagem de configuração sem credenciais |
| Credencial fictícia via `.env` → Compose → processo | `$`, `#` e espaços nas extremidades preservados exatamente; nenhum valor real usado |
| Formatação/sintaxe deploy | Python format-check e node --check aprovados |
| `git diff --check` / escopo Git | Aprovados; diff backend/frontend vazio |

O smoke operacional preexistente falhou inicialmente no timeout curto de startup
do seu harness quando houve outras verificações simultâneas. Reexecução isolada
passou; nenhum código funcional foi alterado para acomodar o teste.
Uma execução inicial dos testes unitários dentro de rootfs readonly não tinha
diretório temporário gravável. O comando de **teste** foi corrigido com tmpfs
restrito em `/tmp`, e 6/6 passaram; Compose de produção não ganhou esse mount.

## Persistência controlada

Cada smoke usa nome de projeto aleatório `bingo-container-test-*`, ambiente
central vazio e arquivo `/var/lib/bingo/controlled/totem.sqlite3`, exercitando o
caminho customizável. A fixture contém um único evento REGISTRATION_PENDING com
metadados de software controlados; não representa confirmação física produzida
pelo runtime. Não foi reenviada ao Supabase.

Banco e trava estão dentro do volume; WAL/SHM quando presentes usam o mesmo
diretório. Esses auxiliares podem desaparecer após checkpoint/fechamento, conforme
SQLite; não são movidos à camada descartável. O serviço usa a recuperação original.
Os smokes encerram somente seus containers/redes com `down`, **sem `-v`**.
Volumes controlados e relatórios `.validation/*/report.json` permanecem locais,
fora do Git e da imagem. Nenhum volume de desenvolvimento/operação foi removido.

A execução AMD64 final confirmou a presença de `totem.sqlite3`, `-wal`, `-shm`
e `.lock` no mesmo diretório durante a fixture, uma transição preservada depois
dos dois restarts e `Application shutdown complete` na parada graciosa.

## Medições e limitações

Primeiro smoke AMD64, sem navegador ativo nas três amostras de repouso:

- Conteúdo da imagem: **66.057.193 bytes (66,1 MB)**, segundo image inspect.
- `docker image ls`: **249 MB de DISK USAGE**, distinto do conteúdo comprimido
  reportado por esse engine com image store containerd.
- Memória: **36,31 MiB** nas três amostras de `docker stats`.
- CPU: **0,30%, 0,98%, 0,28%**.
- `docker top`: **um processo Python/Uvicorn**; `stats` reportou PIDs=2, que também
  conta threads e não deve ser interpretado como dois servidores.
- Subida até healthy pelo comando Compose: **18,77s**, incluindo criação e espera
  do healthcheck; não é tempo isolado de boot do aplicativo.
- Logs mostraram startup completo, sem erros ou acesso HTTP com queries.

Esse perfil pequeno no desktop não comprova orçamento de 2 GB, pico no Orange Pi,
temperatura, consumo de navegador, câmera ou futuras integrações. Amostras curtas
não constituem teste prolongado. Medições ARM emuladas também não predizem ARM real.

Reexecução AMD64 com verificação explícita dos auxiliares/journal e medição do
pico: 36,31 MiB nas três amostras, CPU 0,26%/1,04%/0,20%, Compose healthy em
9,79s. Pico cgroup observado no smoke após recriação: **54.820.864 bytes
(52,28 MiB)**, incluindo subprocessos de teste/probe e cache; não é pico isolado
de inicialização. `/proc/1/status` reportou VmHWM/VmRSS 52.380 kB e duas threads.
`docker stats` desconta cache conforme o engine; as métricas não são equivalentes.

Primeira execução ARM64 emulada com healthcheck padrão ficou unhealthy: os
logs do engine registraram `Health check exceeded timeout (3s)`. O FastAPI
posteriormente iniciou e respondeu `/health` e `/local/status` corretamente.
Uma execução manual do mesmo probe saiu com código 0 em **11,91s**. O build
e os testes de configuração passaram, mas o timeout de produção não foi
validado nesse emulador. O smoke tem `--emulated` para aumentar somente a
tolerância de seu override local; não flexibiliza contratos ou bloqueio real.

A primeira tentativa com override encontrou também uma espera de reinício curta
no harness. A espera foi ajustada para deadline de até 300s **somente no modo de
teste emulado**, e a execução final passou sem mudar a imagem ou o serviço.
O Compose de produção manteve timeout 3s e start-period 15s; testar esses valores
nativamente no Orange Pi permanece uma pendência concreta.

Resultados finais ARM64 **em QEMU no host x86_64**, não no equipamento:

| Métrica | Resultado observado |
| --- | --- |
| Imagem | 65.567.510 bytes de conteúdo (~65,6 MB); 274 MB de DISK USAGE reportado |
| Python / arquitetura projetada pelo emulador | 3.12.15 / aarch64, imagem arm64 |
| Subida até healthy com override | 63,51s, incluindo criação e espera do probe |
| Memória das três amostras | 115,4 / 125,1 / 132,5 MiB |
| CPU das três amostras | 114,55% / 123,49% / 156,04% |
| Pico cgroup no smoke após recriação | 171.450.368 bytes (~163,51 MiB), incluindo subprocessos/cache |
| Processos | Um processo da aplicação sob qemu-aarch64 no snapshot; probes executam outro processo emulado; PIDs=5 inclui threads |
| Persistência | Mesmo event_id e sete campos; um ciclo e uma transição; integrity_check=ok; encerramento gracioso confirmado |

As amostras ARM estavam sem navegador/cliente ativo, mas incluíram o custo elevado
de QEMU e de probes Python emulados. **Não são uma linha de base de repouso nativo
nem evidência de consumo aceitável no Orange Pi.** A emulação confirma funcionamento
de software/persistência neste kernel x86 com tradução, não desempenho/homologação.

Evidências finais locais: `.validation/bingo-container-test-987420af3a0e/report.json`
(AMD64) e `.validation/bingo-container-test-0af8451eb22d/report.json` (ARM emulado).
Volumes desses testes, das tentativas anteriores e do teste de ambiente foram
preservados; nenhum container de smoke permaneceu executando ao fim da validação.

## Pendências antes de homologar

Confirmar OS/kernel/ARM64 e armazenamento no Orange Pi; repetir build nativo,
HTTP/demo e persistência com fixtures, validar fcntl/WAL e parada segura, preparar
backup/restauração e teste controlado de interrupção de energia. Medir picos,
repouso, disco/logs e estabilidade prolongada no equipamento, reservando margem
para Linux e navegador antes de fixar limites. Não declarar Totem operacional:
`/local/status` permanece OFFLINE/false e integrações físicas não estão homologadas.

A próxima etapa depende da revisão desta containerização. Não foi configurado
Chromium kiosk, acesso a câmera, controller, GPIO ou fluxo físico.
