# Instalação e homologação presencial — Orange Pi Zero 3

Entrega de 10/11/2026. **Estes comandos não foram executados na placa.**
Nenhuma aprovação física nova acompanha os arquivos. A montagem continua
impedida para alunos. O caminho implementado permite um ensaio presencial
quando houver evidências reais de segurança; não converte PWM em sensor.

## Arquitetura instalada

Instalar Python/FastAPI **nativos no host**, com o C ARM64 como seu filho por
stdin/stdout IPC V1. Não iniciar outro daemon C: o lifespan Python abre/encerra
o filho. Um worker, lock Python, journal C exclusivo e locks globais PWM3/PWM4.
Não existe socket TCP de comandos ou protocolo novo. A imagem Docker Python
atual continua apropriada aos perfis anteriores; não contém o binário físico
nem deve receber `--privileged`, `/dev`, `/sys` inteiro gravável ou o socket Docker.

Esta escolha evita transportar o IPC entre containers e evita supor que o
sysfs/PWM do host pode ser exposto com segurança pela imagem atual. A câmera
pode continuar no bridge existente (local HTTP autenticado); o serviço mecânico
não recebe dispositivos de câmera. Configurar/selecionar a câmera pelo contrato
CAMERA_V1 antes do ensaio. O status é apenas leitura e não fotografa.

## Pré-requisitos que exigem pessoas e hardware

1. Identificar conector/pad/pinmux na montagem; preservar direita chip0/pwm3 e
   esquerda chip0/pwm4. Não inventar RX/TX. Registrar força/velocidade e proteção
   contra acesso às partes móveis, alimentação externa e GND comum.
2. Instalar/identificar corte **físico** de alimentação dos atuadores, acessível
   ao responsável fora da área de movimento. Homologar seu efeito, energia
   residual, torque, queda por gravidade e reenergização. SIGTERM, EOF, PWM
   fechado, processo morto ou `enable=0` não são comprovação de parada segura.
3. Responsável presente durante todo o ensaio, sem alunos; controlar acesso.
   Homologar procedimento para obstrução/falha de canal/posição desconhecida:
   interromper uso, isolar energia, verificar ausência de energia/movimento,
   inspecionar/desobstruir, retirar o objeto quando seguro. Nunca tentar fechar
   por software, forçar mecanismo ou criar novo ID para recuperar uma falha.
4. Homologar perda de energia/sinal/reinício. Startup não exporta, habilita,
   reposiciona ou faz homing. A preparação manual de PWM fechado só pode ocorrer
   sob o procedimento presencial aprovado, considerando reenergização inesperada.
5. Validar durabilidade SQLite/FULL/WAL no armazenamento e exclusão dos canais
   entre processos. Não reutilizar `~/bingo-c-test/controller.sqlite3`.

O teste C direto informado em 10/11 comprova ciclo, calibração e duplicação do
executor. **Não aprova itens 1–5, Python/C, câmera/IA nem recuperação.** Se corte
seguro/proteções não existirem, não emitir autorização; o backend ficará indisponível.

## Preparação dos arquivos, sem partida automática

Executar futuramente no Orange Pi, em janela de manutenção. Copiar este checkout
revisado para `/opt/bingo/TotemEdge`, pertencente a root e sem escrita de grupo/outros.
Preservar o `.env`/credenciais atuais; não exibir seu conteúdo. Requer Python >=3.12
e `uv` instalado pelo procedimento local, compilador nativo e desenvolvimento SQLite.

```sh
uname -m                         # deve ser aarch64
sudo apt-get install gcc libc6-dev libsqlite3-dev file
sudo groupadd --system bingo     # somente se ainda não existir
sudo useradd --system --gid bingo --no-create-home --shell /usr/sbin/nologin bingo
sudo install -d -o root -g root -m 0755 /opt/bingo/bin /etc/bingo/physical /etc/bingo/physical/evidence
sudo install -d -o bingo -g bingo -m 0700 /var/lib/bingo/python /var/lib/bingo/controller
cd /opt/bingo/TotemEdge/backend
sudo env UV_PROJECT_ENVIRONMENT=/opt/bingo/venv uv sync --locked --no-dev --no-install-project --no-editable --no-build
cd ../controller
cc -std=c11 -O2 -Wall -Wextra -Werror -Wno-unused-function bingo_controller.c -lsqlite3 -o /tmp/bingo_controller.arm64
file /tmp/bingo_controller.arm64
sudo install -o root -g root -m 0755 /tmp/bingo_controller.arm64 /opt/bingo/bin/bingo_controller
sudo install -o root -g root -m 0644 operational.example.json /etc/bingo/physical/controller.json
```

O exemplo é deliberadamente incompleto. Em manutenção, preencher **somente**
campos comprovados (`connector_pin`, `soc_pad`, `safety_recovery_reference`);
trocar `journal` para `/var/lib/bingo/controller/controller.sqlite3`. Preservar
todos os pulsos, período, polaridade, plano conjunto e tempos aprovados. Não
reutilizar IDs/snapshots históricos para uma configuração editada.

Copiar os arquivos de serviço e runtime, revisando caminhos antes:

```sh
cd /opt/bingo/TotemEdge/deploy/physical
sudo install -o root -g root -m 0644 bingo-totem-physical.service /etc/systemd/system/
sudo install -o root -g root -m 0644 runtime.env.example /etc/bingo/physical/runtime.env
sudo systemd-analyze verify /etc/systemd/system/bingo-totem-physical.service
sudo systemctl daemon-reload
```

`/etc/bingo/totem.env` deve ser o arquivo secreto existente ou uma cópia privada
dele, root:root 0600, sem sobrescrever o original. `runtime.env` é separado e
carregado depois: paths mecânicos e câmera remota não alteram as credenciais.
Na primeira instalação, com o destino ainda inexistente, usar
`sudo install -o root -g root -m 0600 /CAMINHO/DO/ENV_EXISTENTE /etc/bingo/totem.env`.
Verificar a sintaxe `EnvironmentFile` sem imprimir o conteúdo; não executar o
`.env` como script. Apontar para o token privado existente do bridge e preservar
suas permissões de leitura restritas à conta `bingo`.
Não usar `systemctl enable`: o unit não tem `[Install]` e não reinicia sozinho.

### Transferir o SQLite Python existente do Docker, quando aplicável

Não iniciar host e container sobre cópias divergentes. Identificar primeiro o
container/volume efetivo com `docker compose ps`/`docker inspect`. Parar somente
o serviço TotemEdge em manutenção, sem remover container, volume ou `.env`.
Com o container parado, preservar **todo** o diretório SQLite, incluindo WAL/SHM,
num backup exclusivo. Exemplo, substituindo o nome pelo container verificado:

```sh
docker stop NOME_VERIFICADO_DO_CONTAINER
sudo install -d -o root -g root -m 0700 /var/backups/bingo/ANTES-DA-MIGRACAO
sudo docker cp NOME_VERIFICADO_DO_CONTAINER:/var/lib/bingo/. /var/backups/bingo/ANTES-DA-MIGRACAO/
# Conferir que o destino de produção está vazio; nunca sobrescrever outro histórico.
sudo cp -a /var/backups/bingo/ANTES-DA-MIGRACAO/. /var/lib/bingo/python/
sudo chown -R bingo:bingo /var/lib/bingo/python
```

Se `BINGO_SQLITE_PATH` tinha outro diretório, adaptar o caminho **verificado**,
incluindo sidecars. Conferir `PRAGMA integrity_check` e identidade/históricos
em cópia de backup antes de iniciar. Não usar banco DEV/simulado como produção.
Não copiar o C de laboratório; o novo diretório C é separado. O volume antigo
permanece preservado. Rollback precisa incluir os novos históricos: não voltar
ao backup antigo após um comando para contornar UNKNOWN ou duplicar operação.

## Permissões e condição inicial

Com serviço parado, responsáveis presentes e preparação física aprovada já
executada manualmente, os canais precisam estar **já exportados/habilitados e
comandados fechados**. Os arquivos entregues não fazem essa preparação.

```sh
sudo /opt/bingo/venv/bin/python /opt/bingo/TotemEdge/deploy/physical/prepare_access.py
sudo -u bingo /opt/bingo/bin/bingo_controller --physical-initial-check /etc/bingo/physical/controller.json
```

A checagem adquire os dois locks e usa o driver C existente para ler canais,
`enable`, período, polaridade e duty. Verifica permissão de abrir os dois
`duty_cycle` para escrita sem escrever valor nem truncar. Não abre journals.
Condição divergente recusa. Repetida no startup operacional e, pelo executor,
depois da intenção durável antes de cada ciclo. Readback não mede posição.
Permissão de escrita é concedida **apenas** a dois `duty_cycle` e aos locks fixos;
o serviço não pode alterar export/enable/period/polarity. Confirmar os caminhos
resolvidos do sysfs e as restrições do unit no kernel/systemd da placa.
`prepare_access.py` deve ser repetido manualmente após boot/reexport; não é
serviço de boot. Ele nunca substitui/remove os inodes de lock existentes.

## Evidências e autorização para um único ensaio

Criar relatórios reais no formato de `evidence.template.json`, um arquivo por
critério: `mapping_calibration`, `direct_c_cycle`, `power_isolation`,
`obstruction_recovery`, `power_loss_recovery`, `guards_force_speed`,
`storage_durability` e, depois do primeiro ensaio Python/C, `python_c_cycle`.
O template é inválido e não aprova nada. Cada relatório aprovado precisa de
`outcome=PASSED`, responsável, instante Unix numérico, achados/evidências e hashes
SHA256 **do JSON e do binário instalados**. Arquivos/ancestrais root, sem escrita
de grupo/outros, sem symlinks/hardlinks. Hashes e referências são auditados;
o software verifica a integridade da aprovação, não mede proteção física.
Para confirmar `direct_c_cycle` no binário final, usar o roteiro de bancada de
[PHYSICAL_PWM_DRIVER.md](../../controller/PHYSICAL_PWM_DRIVER.md), somente
sob supervisão e com journal de ensaio novo e separado. Nunca apontar o ensaio
direto para o journal de produção ou reutilizar os IDs anteriores.

```sh
sha256sum /etc/bingo/physical/controller.json /opt/bingo/bin/bingo_controller
cd /opt/bingo/TotemEdge/backend
sudo /opt/bingo/venv/bin/python -m app.commissioning_cli \
  --config /etc/bingo/physical/controller.json \
  --backend-journal /var/lib/bingo/python/totem.sqlite3 \
  --reports /etc/bingo/physical/evidence --operator 'RESPONSAVEL_PRESENTE' \
  --purpose python-c-validation
```

`python-c-validation` exige todos os relatórios anteriores, exceto o próprio
ensaio Python/C, para evitar dependência circular. Após sua execução documentada,
`integrated-validation` exige também `python_c_cycle`. **Ambos são exclusivos
de técnicos presentes**; nenhum concede uso por alunos. O CLI não testa motores,
não cria relatórios PASSED e não inicia processos C.

A autorização é root-owned, vinculada ao boot/configuração/binário/journals,
vale no máximo 600 s (também pelo relógio de boot, sem prorrogação por ajuste
de hora) e fica consumida por **um** mechanical_command_id no SQLite
Python antes de SUBMIT. Repetir o mesmo ID só consulta. Atualizar qualquer hash
exige evidências novas. Ausência, vencimento, arquivo alterado, journal C incerto
ou Python incerto ou condição inicial divergente conservam indisponibilidade. Expiração não tenta
parar um ciclo aceito; este conserva o prazo original de 30 s e o responsável
continua presente até encerramento/isolamento.

## Ensaio futuro pelo fluxo real

Somente após os passos anteriores e corte seguro disponível:

```sh
sudo systemctl start bingo-totem-physical.service
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:8000/local/status
```

Abrir a tela local. Identificação → Segurança → inserir um único item →
Retirei a mão (declaração, não sensor) → captura/análise reais → confirmar/corrigir
o item → **autorização explícita** → CYCLE_LOWER_HATCH com ID derivado da sessão
e orçamento total 30 s → abrir ambas → 5 s → fechar ambas → 5 s estabilizando →
resultado durável. Não há porta superior. GET/refresh/startup não fotografam,
analisam ou submetem movimentos. Offline ou falha câmera/IA bloqueiam o ciclo.
Testar cliques repetidos e refresh consultando o mesmo ID, nunca fabricando outro.

O resultado PHYSICAL/SUCCEEDED conserva a sessão em INDETERMINATE e o slot
reservado; a tela distingue **sequência operacional concluída** de queda/crédito.
Não há `physical_confirmed`, payload, recibo, registro central ou pontos.
Assim, este ensaio não libera automaticamente uma segunda sessão nem alunos.

## Falha, desligamento, inspeção e recuperação

Obstrução, ruído inesperado, falha parcial, timeout ou posição incerta: impedir
acesso, usar o corte homologado presencial, verificar energia residual e inspeção
antes de tocar. SIGTERM/EOF apenas inibem novas escritas: o último PWM pode
persistir. O unit não envia SIGKILL; processo/lock que não sair exige manutenção,
nunca remoção de lock ou partida de segundo executor. Falta de energia não é
evidência de retorno inicial. Nenhum reinício reenvia ACCEPTED.

Depois de parar o serviço e preservar os journals, consultar o mesmo ID sem
autorização de movimento e sem requisito de PWM fechado:

```sh
cd /opt/bingo/TotemEdge/backend
sudo -u bingo /opt/bingo/venv/bin/python -m app.controller_recovery \
  --config /etc/bingo/physical/controller.json \
  --backend-journal /var/lib/bingo/python/totem.sqlite3 --id UUID_ORIGINAL
```

Esse caminho abre o mesmo C para **GET somente**, vincula o snapshot original e
acrescenta RECOVERY_C_* no histórico Python. COMPLETED, NOT_FOUND ou ausência de
resposta nunca autorizam SUBMIT, liberação de slot, pontos ou conversão de UNKNOWN.
O lock do runtime precisa estar livre. Não editar o JSON do comando histórico.

Inspeção auditável opcional: arquivo JSON protegido com `mechanical_command_id`,
`inspector`, `power_isolation_reference`, `findings` e
`disposition="RETAIN_BLOCKED"`; acrescentar `--inspection /caminho/inspecao.json`
ao comando. É retenção append-only no mesmo SQLite, sem reinterpretação do resultado.

**Liberação após falha permanece pendente**: faltam evidência homologada de estado
seguro/posição e procedimento validado de reenergização/recuperação. Não existe
botão ou SQL de reset entregue. O responsável deve manter o Totem bloqueado;
após aprovação física, será necessária evolução explícita do contrato/journals
para auditar a liberação sem apagar UNKNOWN. Também falta provedor homologado
de confirmação física para finalizar descarte/economia. Relatórios administrativos
não substituem essas evidências. Não há alegação de sensores instalados.

## Testes de software reproduzíveis, sem placa

Da estação de desenvolvimento, na imagem de toolchain existente, checkout readonly,
sem rede/dispositivos e apenas `/tmp` temporário executável:

```powershell
$bingoTestScript = @'
set -eu
mkdir -p /tmp/bingo/Hardware/TotemEdge /tmp/bingo/Software/apps/totem_ui
tar -C /checkout/Hardware/TotemEdge --exclude=__pycache__ -cf - backend/app backend/tests backend/pyproject.toml controller frontend/index.html frontend/styles.css frontend/script.js frontend/operational.js frontend/local_api.js frontend/assets | tar -xf - -C /tmp/bingo/Hardware/TotemEdge
cp /checkout/Software/apps/totem_ui/edge_vision_service.py /tmp/bingo/Software/apps/totem_ui/
cd /tmp/bingo/Hardware/TotemEdge/backend
exec python -m pytest -q -p no:cacheprovider tests --tb=short
'@
docker run --rm --network none --cap-drop ALL --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,exec,nosuid,nodev,size=512m -v C:/Projetos/BinGo:/checkout:ro bingo-mechanical-ipc:test sh -ec $bingoTestScript
node C:/Projetos/BinGo/Hardware/TotemEdge/frontend/validation/physical_flow_smoke.cjs
```

O harness compila C nativo e intercepta syscalls/relógio. Nenhum canal real é
acessado. Isso não é aprovação ARM64, elétrica, de durabilidade da placa ou
segurança mecânica. O smoke de frontend abre apenas porta efêmera em loopback,
com câmera/IA/central controladas, Docker descartável sem mounts de dispositivos
e Playwright do repositório. Também usa o harness, nunca hardware.
