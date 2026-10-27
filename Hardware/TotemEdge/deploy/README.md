# Execução containerizada do Totem Edge V1

Um container executa FastAPI/Uvicorn e serve o frontend oficial na mesma origem.
SQLite ocupa um volume Docker persistente. O navegador permanece no Linux do
equipamento, acessando loopback. Não há Node, Nginx, Chromium, IA local, serviços
auxiliares ou acesso a dispositivos nesta imagem.

**O Totem continua indisponível para descartes reais.** Um healthcheck saudável
confirma somente o processo. `/local/status` permanece `OFFLINE` e
`can_start_deposit=false`, inclusive com o backend central disponível. A
demonstração em `/?runtime=demo` mantém seu aviso e isolamento existentes.

## Fontes, compatibilidade e diretórios

Foram consultados STATUS atual, operação offline, README do Totem Edge/backend,
LOCAL_API_V1, INTEGRATION_V1 e MIGRATION_DIAGNOSTIC. O diagnóstico descreve uma
etapa histórica; INTEGRATION_V1 e o código atual já têm hospedagem da UI e SQLite.
A referência ao serviço local como futuro no documento offline é histórica.
FastAPI legado central e FastAPI local são componentes distintos. Nenhuma dessas
divergências exige mudança funcional para containerizar o serviço atual.

Python `>=3.12` no projeto, `.python-version=3.12`; a imagem fixa Python
**3.12.15 slim-bookworm**, pelo digest de um índice multiarch. O `uv` **0.12.19**
também tem digest fixado e fica apenas no build. Builder e runtime usam a mesma
base. `uv sync --locked --no-dev --no-build` instala somente as 24 dependências
de produção; lock incompatível ou ausência de wheel impede o build. Bytecode
das dependências é preparado no build; inicialização não instala pacotes.

```text
deploy/
├── Dockerfile
├── compose.yaml
├── .env.example
├── start.py                 valida volume/caminho, substitui processo por Uvicorn
├── healthcheck.py           GET /health via biblioteca padrão
├── tests/test_runtime.py    guardas de execução
├── validation/              smokes isolados de container e navegador
├── README.md
└── VALIDATION.md            resultados e limites da comprovação

Container:
/opt/venv/                   dependências de produção
/opt/totem/backend/app/      código; cwd /opt/totem/backend
/opt/totem/frontend/         HTML, CSS, três JS e 45 assets
/opt/totem/deploy/           somente start.py e healthcheck.py
/var/lib/bingo/              volume gravável, UID/GID 10001:10001
```

O contexto de build é `Hardware/TotemEdge/`, pois backend/frontend são irmãos.
A `.dockerignore` permite apenas inputs de produção; o Dockerfile copia arquivos
explicitamente. Testes, documentos, `.env`, bancos, caches, ambientes virtuais,
controller e camera não entram na imagem. A fundação de containerização não
alterou arquivos funcionais; a atualização de visão interna acrescenta boto3 e
Pillow ao backend. Evidências atuais e contratos pendentes estão em
[VISION_INTERNAL_V1.md](../backend/VISION_INTERNAL_V1.md); VALIDATION.md preserva
o histórico da fundação anterior.

## Requisitos e instalação do Docker

Antes de instalar no Orange Pi Zero 3 2 GB, confirmar no próprio equipamento:

```sh
cat /etc/os-release
uname -m
getconf LONG_BIT
free -h
df -h
```

O alvo esperado é `aarch64`/64 bits; não foi escolhida distribuição nem kernel.
Usar Docker Engine com containers Linux, BuildKit e o plugin Compose V2. Buildx
é necessário para o teste de outra arquitetura. Não é necessário Docker Desktop
no Orange Pi, nem Python/uv/Node no host para executar a aplicação containerizada.

Depois de identificar a distribuição, seguir a instalação pelo repositório
oficial correspondente: [Docker Engine](https://docs.docker.com/engine/install/),
[Debian](https://docs.docker.com/engine/install/debian/) ou
[Ubuntu](https://docs.docker.com/engine/install/ubuntu/). Instalar os pacotes
`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` e
`docker-compose-plugin` conforme essa distribuição/versão e arquitetura.
Não usar procedimento Ubuntu em uma imagem derivada sem verificar suporte.

Em Linux com systemd, verificar o daemon e ferramentas:

```sh
sudo systemctl enable --now docker
docker version
docker compose version
docker buildx version
docker info --format '{{.OSType}} {{.Architecture}}'
```

Usar `sudo docker ...` quando o operador não tiver acesso ao daemon. O acesso ao
daemon é administrativo; não há montagem de seu socket no container. Em Windows
de desenvolvimento, usar Docker Desktop com engine Linux já iniciado.

## Configurar, construir e iniciar

Todos os comandos desta página partem de `Hardware/TotemEdge/deploy/`.
No Linux:

```sh
cp .env.example .env
chmod 600 .env
# Editar .env localmente pelo canal autorizado, se necessário.
docker compose --env-file .env config --quiet
docker compose --env-file .env build
docker compose --env-file .env up -d --no-build --wait --wait-timeout 90
```

No PowerShell, copiar com `Copy-Item .env.example .env`; os comandos Docker são
os mesmos. Não é preciso preencher credenciais para acessar a interface,
demonstração ou liveness. O modo real continua bloqueado. `.env` é ignorado pelo
Git e pelo build; os valores são injetados pelo Compose no processo, sem arquivo
de credenciais na imagem. Variáveis já exportadas no shell têm precedência sobre
o arquivo; confirmar o ambiente antes de iniciar. `config --quiet` valida sem
imprimir os valores de credenciais.

| Variável | Configuração |
| --- | --- |
| `BINGO_SUPABASE_URL` | URL raiz do projeto existente; sem `/functions/v1`. Vazia mantém configuração central indisponível. HTTPS remoto; HTTP apenas loopback segundo contrato do backend. |
| `BINGO_MACHINE_ID` | UUID provisionado, exclusivamente backend. |
| `BINGO_MACHINE_API_KEY` | Chave técnica da máquina; nunca anon, service role ou Secret API Key. Manter bytes exatos. |
| `BINGO_BACKEND_TIMEOUT_SECONDS` | Default `5`, finito positivo; timeout técnico existente, sem política de polling. |
| `BINGO_SQLITE_PATH` | Default `/var/lib/bingo/totem.sqlite3`. Absoluto, dentro do volume; subdiretórios permitidos. Manter o mesmo caminho em reinícios/atualizações. |
| `BINGO_HTTP_PORT` | Somente infraestrutura Compose; default `8000`, publicado em `127.0.0.1`. Porta interna fixa `8000`. |

Credenciais com `$`, `#` ou espaços devem ficar entre aspas simples no `.env`,
como `BINGO_MACHINE_API_KEY='valor-fornecido-pelo-canal-autorizado'`.
Esse texto é ilustrativo, não uma chave. Não imprimir `.env`, ambiente completo
ou `docker inspect` completo em relatórios: Docker administra o ambiente contendo
segredos. Logs da aplicação não incluem PIN, chave ou resposta central bruta.

Para desenvolvimento com Supabase no host, `127.0.0.1` dentro do container refere-se
ao próprio container. Não alterar proteção de URL/autenticação nem inventar um
alias HTTP para contornar isso; os smokes usam credenciais vazias e não consultam
Supabase. O projeto hospedado existente usa HTTPS quando autorizado.

## Navegador, logs e saúde

Abrir no navegador **do próprio host**:

- `http://127.0.0.1:8000/` — interface oficial, modo seguro.
- `http://127.0.0.1:8000/?runtime=demo` — demonstração explícita.
- `http://127.0.0.1:8000/health` — `{"status":"ok"}`.
- `http://127.0.0.1:8000/local/status` — disponibilidade operacional bloqueada.

Usar a porta configurada, se diferente. O futuro Chromium kiosk do Linux acessará
essa mesma URL; sua instalação/inicialização não fazem parte desta entrega.
O bind externo é loopback. Internamente Uvicorn escuta `0.0.0.0` para permitir
o encaminhamento Docker, preservando as verificações Host/origem da aplicação.

```sh
docker compose --env-file .env ps
docker compose --env-file .env logs --tail 100 -f totem-edge
docker compose --env-file .env exec -T totem-edge python /opt/totem/deploy/healthcheck.py
docker inspect --format '{{json .State.Health}}' "$(docker compose --env-file .env ps -q totem-edge)"
```

O healthcheck usa Python padrão, timeout HTTP 2s, execução limitada a 3s,
intervalo 30s, tolerância inicial 15s e três falhas. Esses parâmetros verificam
liveness e não instituem polling operacional/Supabase. `unhealthy` é um sinal de
diagnóstico: Compose não reinicia automaticamente um processo ainda vivo somente
por esse estado. `unless-stopped` reinicia o processo/container quando ele termina
ou o daemon retorna, exceto se o operador o parou explicitamente.

Há um worker, sem `--reload`, access log ou confiança em proxy headers. O launcher
usa `exec`, fazendo Uvicorn receber SIGTERM diretamente como PID 1. Uvicorn tem
20s para requests pendentes; Compose aguarda 30s. O lifespan fecha a trava SQLite.
Logs `json-file` são rotacionados em três arquivos de até `10m` por container.

## Persistência, permissões e atualização

O volume nomeado `sqlite-data` é montado em **todo** `/var/lib/bingo`, incluindo
banco, `-wal`, `-shm`, `.lock` e subdiretórios. A criação de um volume novo usa
as permissões da imagem: UID/GID `10001:10001`, diretório `0700`; o processo usa
umask `077`. O filesystem da imagem é somente leitura. Não há entrypoint root,
chown recursivo, truncamento, seed ou substituição de banco no startup.

O launcher recusa banco fora do diretório (inclusive escapes por symlink) e
ausência de montagem em `/var/lib/bingo`, para evitar persistência acidental na
camada descartável. Volumes existentes com ownership incorreto falham; corrigir
permissões somente após identificar o volume e preservar seus dados. O Compose
usa volume Docker, sem bind de diretórios do host. Não substituir por bind mount
sem preparar explicitamente ownership e filesystem compatível com SQLite.

O nome de projeto é fixo `bingo-totem-edge`: por padrão o volume efetivo é
`bingo-totem-edge_sqlite-data`. Manter projeto, nome do volume e caminho do banco.
Mudar `-p`, `COMPOSE_PROJECT_NAME` ou `BINGO_SQLITE_PATH` pode selecionar um banco
novo; isso não é migração dos eventos. Não apontar duas instâncias ao mesmo banco.

```sh
# Reiniciar a aplicação sem trocar banco:
docker compose --env-file .env restart totem-edge
# Interromper preservando container/volume:
docker compose --env-file .env stop
# Remover container/rede; volume permanece:
docker compose --env-file .env down
# Atualizar código autorizado e reconstruir; mesmo projeto, env e volume:
docker compose --env-file .env build
docker compose --env-file .env up -d --no-build --force-recreate --wait --wait-timeout 90
```

Não usar `down -v`, prune de volumes ou remoção do volume operacional. Antes de
manutenção/migração, parar o serviço e fazer backup autorizado do **diretório
inteiro** ou usar a API de backup SQLite; copiar somente o `.sqlite3` enquanto há
escrita/WAL pode perder transações. Backup/restauração e falhas de energia no
armazenamento do Orange Pi ainda precisam de procedimento homologado.

Schema, journal, estados e recuperação são os originais. UUID e payload pendente
são recuperados pelo FastAPI; conclusão física desconhecida segue indeterminada.
Não existe sincronizador novo, nem autorização para novos descartes offline.

## Recursos e ARM64

Não há limites rígidos de memória/CPU sem medição no equipamento. O objetivo de
2 GB exige orçamento conjunto para Linux, navegador e futuras integrações; as
medições desta entrega não homologam esse orçamento. Se necessário, adicionar
um override local com `mem_limit`/`cpus` somente após medir pico/margem no Orange
Pi e validar reinícios/pendências sob carga. Não aumentar workers para compensar
desempenho: a trava SQLite exige uma instância por banco.

```sh
docker image inspect bingo-totem-edge:v1 --format '{{.Architecture}} {{.Size}}'
docker image ls bingo-totem-edge
docker stats --no-stream
docker compose --env-file .env top
docker inspect --format '{{.RestartCount}} {{.State.OOMKilled}}' "$(docker compose --env-file .env ps -q totem-edge)"
```

Registrar versões/arquitetura, amostras em repouso sem browser de teste, picos de
startup/carga, número de processos, tamanho reportado pelo engine e duração. Os
comandos com `$(...)` são para shell Linux; no PowerShell, guardar primeiro o ID
em uma variável. Atualização dos digests/base/lock é manutenção explícita seguida
de regressão, não download no startup.

O build Compose usa a arquitetura nativa do engine; não fixa AMD64. Para verificar
ARM64 em desenvolvimento com Buildx e emulação já disponíveis:

```sh
docker buildx build --platform linux/arm64 --load -f Dockerfile -t bingo-totem-edge:arm64-test ..
python -B validation/container_smoke.py --image bingo-totem-edge:arm64-test --platform linux/arm64 --emulated
```

Não instala emulação ou concede privilégios como parte da aplicação. Build ARM64
e execução emulada são evidências distintas de execução física. No próprio
Orange Pi ARM64, o `docker compose build` nativo selecionará ARM64.

`--emulated` é exclusivamente um override do smoke ARM64 em host x86: timeout
do probe 90s, tolerância inicial 180s e espera de startup de até 600s. No QEMU
disponível, o Python do healthcheck levou 11,91s para iniciar/importar e verificar
o processo, excedendo os 3s de produção. O override não muda o código da imagem,
Compose de produção, timeout HTTP de 2s ou `/local/status`. O tempo do probe e
startup nativos deve ser medido no Orange Pi; a configuração padrão de saúde
ARM64 não é considerada homologada apenas pelo teste emulado.

## Testes e próxima homologação

```sh
docker compose --env-file .env.example config --quiet
docker buildx build --check -f Dockerfile ..
python -B -m unittest discover -s tests -v
python -B validation/container_smoke.py --browser
```

`--browser` é opcional, exige Node/Playwright/navegador **no host de teste**, e
aceita `PLAYWRIGHT_MODULE` e `BROWSER_EXECUTABLE`. Não são dependências da imagem.
O smoke cria projeto/volume únicos, remove variáveis de negócio herdadas e usa
o `.env.example`. Dados SQLite são fixtures identificadas, sem movimentação ou
registro remoto. Verifica todos os arquivos servidos, bloqueio real, demonstração,
reinício/recriação, UUID/payload/journal e coleta métricas. Encerra só seus próprios
containers/rede; não remove volumes. Relatórios ficam em `.validation/` ignorado.

Regressão: executar os comandos existentes em backend/README e
frontend/INTEGRATION_V1. Resultados desta entrega em [VALIDATION.md](VALIDATION.md).

Depois da revisão, homologar **esta infraestrutura** no Orange Pi: confirmar OS,
kernel/ARM64, build nativo, permissões/WAL/trava em armazenamento real, restart e
recriação com fixtures, encerramento e queda de energia controlada, ocupação de
disco/logs, memória/CPU/picos/temperatura e estabilidade prolongada. Reservar margem
medida para navegador e futuras integrações. Ajustar recursos depois dessas
medições. Kiosk, câmera e equipamentos físicos continuam fora desta entrega.

Referências: [uv em Docker](https://docs.astral.sh/uv/guides/integration/docker/),
[imagem oficial Python](https://hub.docker.com/_/python),
[volumes Docker](https://docs.docker.com/engine/storage/volumes/) e
[nome do projeto Compose](https://docs.docker.com/compose/how-tos/project-name/).
