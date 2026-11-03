# Comunicação local Python ↔ C — laboratório com PWM simulado

Etapa de 02/11/2026, branch `feature/totem-edge-mechanical-integration`.
O processo C real recebe ordens do adaptador Python. Somente PWM **simulado em
compilação** é executável nesta entrega. Não conectar este laboratório ao perfil
econômico DEV, volumes operacionais, servos ou GPIO. O runtime FastAPI operacional
continua com `UnavailableController`; `MechanicalService` continua recusando
`source="PHYSICAL"`. Não há endpoint ou variável operacional nova.

## O que foi reaproveitado e o que estava incompatível

O C original recebia os eventos por chamadas diretas a `bingo_evento_*`; seu
`executar_teste_automatico` fabricava esses sinais e chamava `bingo_processar`.
Não existia receptor externo. A máquina C encadeava classificação, confirmação,
queda e tela final. Agora a camada IPC recebe operações mecânicas individuais;
o backend conserva as decisões de negócio, a declaração da mão, revisão e journal.
O loop demonstrativo antigo fica preservado, mas sem caminho a partir de `main`.

| Entrada original | Operação oficial / tratamento nesta etapa |
| --- | --- |
| `bingo_evento_toque_iniciar` | Inicia a máquina demonstrativa; não equivale a `OPEN_INSERTION_DOOR`. Abertura agora recebe sua própria ordem identificada e usa `abrir_porta_superior`. |
| `bingo_evento_area_segura` | Fazia o fechamento depender de câmera. Não é sensor homologado nem a declaração “Retirei a mão”. `CLOSE_INSERTION_DOOR` vem do backend após suas guardas; o laboratório usa a mesma sequência PWM extraída para `fechar_porta_superior_autorizada`. O wrapper antigo mantém a sua guarda. Não se injeta um falso evento de câmera. |
| `bingo_evento_classificacao_item` | Decisão de negócio que permanece no Python; não é comando mecânico. Não se envia classificação sintética ao C. |
| `bingo_evento_confirmacao_item` | Não equivale por si só a autorização mecânica. Após revisão, Python solicita `CYCLE_LOWER_HATCH`. No laboratório, reutilizam-se abrir/fechar escotilha, sem executar o antigo loop de negócio. |
| Tempo de seis segundos / `TELA_DESCARTE_CONCLUIDO` | Não provam conclusão física. O laboratório modela somente um ciclo simulado; não envia evento econômico ou tela de sucesso real. |
| `bingo_inicializar` / `estado_inicial_fisico` | Movimentavam mecanismos; não equivalem a `CONFIRM_INITIAL_STATE`. A inicialização agora recusa atuação. A confirmação do laboratório só verifica o checkpoint simulado após o hatch, sem PWM ou homing. |

Pulsos, canais, funções de sysfs, abrir porta e abrir/fechar escotilha mantêm o
código existente. Alterações em `bingo_controller.c`:

1. Diagnósticos antigos passam a `stderr`, reservando `stdout` ao protocolo.
2. `mover_servo` recebe um ramo `#ifdef BINGO_PWM_SIMULATED`: registra canal/pulso
   sem abrir arquivos PWM. O ramo físico original permanece intacto.
3. Extração da sequência de fechamento sem mudar canais, pulsos ou ordem; evita
   tratar o sinal simulado de câmera como uma autorização real.
4. `bingo_inicializar` retorna falha sem exportar/configurar/energizar PWM ou
   pressupor posição. O corpo antigo fica em função estática não chamada.
5. O `main` antigo fica estático e inacessível pelo executável. O novo entrypoint,
   em `bingo_ipc.inc`, só aceita laboratório compilado com PWM simulado. Sem essa
   macro, **qualquer argumento** resulta em saída 2, antes de abrir o journal.
   O antigo `--teste` também é recusado.

## Transporte e identidade

Subprocesso POSIX com pipes privados de `stdin/stdout`, sem shell, TCP, HTTP,
daemon ou broker. É suficiente para comunicação no mesmo Orange Pi, tem ciclo
de vida explícito e não abre acesso pela rede. É uma capacidade local de processo:
usuário, executável e diretório precisam ser confiáveis e privados. Não há
autenticação de múltiplos clientes ou protocolo de parada física homologado.

`app.services.c_controller.CProcessController.connect` exige contexto explícito
`test`/`development`, lança apenas `--ipc-simulated` e valida o handshake
`V1 READY SIMULATED`. Não herda `_MemoryController` e não está ligado à fábrica
operacional nem ao TotemEdge DEV existente. Sua composição de teste usa os mesmos
`MechanicalService`, `SimulationFlow` e `CycleStore`, sem alterar seus contratos.

Mensagens ASCII de uma linha, até 511 bytes incluindo newline; campos separados
por whitespace, UUIDs canônicos minúsculos, timeout positivo/finito em segundos:

```text
V1 SUBMIT <mechanical_command_id> <event_id> <operation> <timeout_seconds>
V1 GET <mechanical_command_id>

V1 RESULT <id> <event_id> <operation> <timeout_seconds> <state> <result> <error-ou-> SIMULATED
V1 ERROR <code>
```

As quatro operações são as oficiais. O timeout é serializado pelo Python com
`.17g`; sua representação é parte dos parâmetros imutáveis retidos no C.
O Python valida a correlação integral, estados/resultados e origem de cada
resposta. Aceite é `ACCEPTED/PENDING`; o resultado é consultado por `GET`.
O C processa uma ordem de cada vez, terminando a execução simulada antes de ler
a próxima mensagem; não há fila autônoma ou eventos de conclusão não solicitados.
Durante uma ordem, `get()` do adaptador mostra o último snapshot local;
`wait()`/`query(command)` aguardam a consulta externa limitada por prazo.

Duplicata idêntica de `SUBMIT` recebe `ERROR DUPLICATE`; identidade com parâmetros
diferentes recebe `ERROR ID_CONFLICT`. Nenhuma delas repete PWM. `GET` recupera
o resultado. O adaptador pode consultar uma duplicata, mas replay normal passa
primeiro pelo journal Python, que nem chama o C. Comando inválido, quadro longo,
ID desconhecido ou capacidade esgotada recebem erro sem atuação. Recusa por
sequência é `REJECTED/UNAVAILABLE/CONTROLLER_BUSY`, retida pelo mesmo ID.

O C mantém apenas intertravamento mecânico de laboratório: OPEN → CLOSE → HATCH
→ CONFIRM para o mesmo evento; novo evento só após CONFIRM. Não aceita iniciar
outra sequência por um event_id já concluído. Isso não autoriza negócio: no
backend, CLOSE exige declaração da mão e HATCH exige revisão. A fixture inicial
é exclusivamente simulada; não afirma posições reais. Reabertura para devolução,
geometria do retorno e critérios físicos de cada operação continuam bloqueados.

## Journal, timeout e reconexão

O SQLite do C é separado do SQLite Python. Usa WAL, `synchronous=FULL`, versão e
application_id próprios, checagem de integridade e um lock exclusivo por processo.
Guarda id/evento/operação/timeout, estado, resultado e erro. Triggers protegem
identidade e impedem apagar ordens. Não há expurgo; capacidade de 1024 identidades
é uma recusa conservadora, nunca eviction ou autorização para apagar evidências.
O banco novo é criado com permissões privadas. Bancos estranhos, versões futuras
ou ausência das proteções esperadas bloqueiam o processo.

O aceite é commitado e emitido **antes** de chamar qualquer sequência simulada.
Falha de banco encerra o processo, sem sucesso fictício. No startup, ordens
`ACCEPTED` viram `FAILED/UNKNOWN/EXECUTION_ERROR`: não são executadas novamente,
mesmo se o crash ocorreu antes do primeiro PWM. Falha parcial fica
`FAILED/FAILURE/OPERATION_FAILED`. Qualquer falha/indeterminação retida bloqueia
novas ordens. O journal Python mantém seu histórico transacional e a reserva;
os snapshots do C não substituem essa auditoria.

O prazo global de `MechanicalService` continua valendo para este adaptador;
o IPC tem ainda timeout de leitura/escrita (default 2 s), configurável apenas
pela construção explícita de laboratório. Os hooks `delay_ms` e `fail_after`
só existem no executável de PWM simulado para testar perdas e falhas parciais.
Não medem tempo de queda nem comprovam movimento. O C simulado pode terminar
uma ordem cujo observador perdeu o prazo: isso nunca promove o journal Python
de timeout/indeterminação a sucesso.

Perda/cancelamento de leitura invalida o canal e encerra o filho **simulado**,
evitando que bytes atrasados respondam a outra ordem. Não há reconexão, respawn
ou redisparo automático. Uma nova instância exige `connect` explícito e pode
usar `query` com a identidade antiga; a consulta é diagnóstica, não desbloqueia
sessão nem concede elegibilidade econômica. `cancel` não envia movimento ou
parada física: só cancela o acompanhamento lógico e mantém resultado desconhecido.
Esse encerramento de processo não é um mecanismo de parada segura para hardware.

## Executar no Linux / Orange Pi sem servos

Use checkout completo do repositório, Python >=3.12 e `uv` disponível. Instale
o compilador e headers SQLite pelo gerenciador do sistema (em Debian/Ubuntu:
`sudo apt-get install gcc libc6-dev libsqlite3-dev`). Execute o laboratório como
usuário comum, sem sudo e sem conectar os servos.

Da raiz do repositório:

```sh
cd Hardware/TotemEdge/backend
uv run --locked pytest -q tests/test_c_controller.py
```

Os testes compilam dois binários temporários com `-std=c11 -Wall -Wextra -Werror`
e `-Wno-unused-function` (rotinas legadas preservadas), depois executam o processo
C real a partir do Python. O binário físico só é usado para comprovar a recusa
do entrypoint; nenhum PWM físico é acessado. O teste `test_full_flow_uses_existing_python_service_and_journal`
exercita as quatro operações pelo orquestrador Python e confirma ausência de
evidência física e econômica. No Windows, esses casos são marcados Linux-only;
use o container abaixo. Para regressão local completa: `uv run --locked pytest -q`.

Alternativa Docker, da raiz, sem alterar a implantação existente:

```sh
docker build -f Hardware/TotemEdge/controller/Dockerfile.test -t bingo-mechanical-ipc:test Hardware/TotemEdge
docker run --rm --network none --read-only --tmpfs /tmp:rw,exec,nosuid,nodev --cap-drop ALL --security-opt no-new-privileges bingo-mechanical-ipc:test
```

A imagem é exclusiva de testes, usa o `uv.lock` existente e roda como UID 10001.
O build baixa ferramentas/dependências; a execução não tem rede, volumes de
dados, dispositivos, credenciais ou acesso a PWM do host. `exec` no tmpfs é
necessário para executar os binários C temporários. Não é deploy do TotemEdge.

Para inspecionar manualmente o protocolo (ainda somente PWM simulado), da raiz:

```sh
cc -std=c11 -Wall -Wextra -Werror -Wno-unused-function -DBINGO_PWM_SIMULATED Hardware/TotemEdge/controller/bingo_controller.c -lsqlite3 -o /tmp/bingo_controller_simulated
lab_dir="$(mktemp -d -t bingo-ipc.XXXXXX)"
/tmp/bingo_controller_simulated --ipc-simulated "$lab_dir/controller.sqlite3"
```

O processo exibe `V1 READY SIMULATED`. Digite, por exemplo:

```text
V1 SUBMIT 11111111-1111-4111-8111-111111111111 22222222-2222-4222-8222-222222222222 OPEN_INSERTION_DOOR 10
V1 GET 11111111-1111-4111-8111-111111111111
```

O primeiro retorno é `ACCEPTED/PENDING`; a consulta retorna
`COMPLETED/SUCCEEDED/SIMULATED`. As linhas `SIMULATED_PWM` aparecem em stderr.
Repetir SUBMIT retorna DUPLICATE sem novas linhas PWM. Preserve o mesmo arquivo
ao testar reinício; não apague banco para contornar bloqueio. Esse diagnóstico
manual não substitui o caminho coordenado e nunca deve ser ligado ao fluxo real.

## O que permanece bloqueado para a equipe de hardware

Todas as quatro operações físicas; energização/inicialização; retorno corretivo,
homing, devolução e liberação de um estado indeterminado; confirmação de descarte,
ONLINE e crédito econômico por esta integração. O código de produção não é
habilitado por compilar sem a macro de simulação.

É necessário acordar pinagem, calibração, geometria/posições e a proteção física
do fechamento autorizado, resolver o mapeamento do ciclo inferior/retorno, definir
e homologar evidências de cada resultado e o significado de falha parcial.
Escrita PWM, aceite e tempo decorrido não bastam. Também faltam parada/intervenção
segura, recuperação com posição desconhecida, perda de energia e validação da
durabilidade/IDs no armazenamento real do Orange Pi. A equipe poderá aproveitar
o receptor e as sequências existentes; a habilitação física exigirá uma etapa
explícita posterior, sem retirar as guardas atuais para facilitar o driver.

## Evidências desta rodada

- Build Linux amd64 da imagem `bingo-mechanical-ipc:test`: aprovado com as
  dependências Python do `uv.lock` vigente. As duas variantes C foram compiladas
  com GCC 12, warnings como erros (exceto funções legadas não usadas).
- Imagem final executada com o comando isolado acima: **28 aprovados**, zero
  falhas/skips, em 1,72 s. Inclui protocolo, quatro operações via serviço/journal,
  comandos inválidos/fora de ordem, duplicata/conflito, falha parcial, timeout do
  backend e do IPC, desconexão, reinício de ambos os journals, consulta sem
  redisparo, retenção/imutabilidade, lock exclusivo, banco incompatível/corrompido,
  evento já concluído e recusa de execução física/rotulagem indevida.
- Regressão completa Linux, checkout completo montado somente leitura no mesmo
  ambiente de ferramentas: **802 aprovados**, zero falhas/skips, em 82,43 s.
- Regressão completa Windows: **774 aprovados, 28 skips** exclusivos da suíte C
  Linux, em 123,18 s. Esses 28 foram executados e aprovados no Linux acima.
- `uv format --check -- app/services/c_controller.py tests/test_c_controller.py`
  e `git diff --check`: aprovados.

A imagem mínima contém apenas os arquivos necessários à integração C. A
regressão completa também depende do frontend e do arquivo de política legado
em `Software`; por isso usa o checkout completo. Da raiz, em shell Linux:

```sh
docker run --rm --network none --read-only --tmpfs /tmp:rw,exec,nosuid,nodev --cap-drop ALL --security-opt no-new-privileges --mount "type=bind,source=$PWD,target=/repo,readonly" -w /repo/Hardware/TotemEdge/backend bingo-mechanical-ipc:test python -m pytest -q -p no:cacheprovider --tb=short
```

As primeiras tentativas do harness identificaram tmpfs sem permissão de execução
e falta desses arquivos na coleta completa; o ambiente foi ajustado, sem mudar
os testes antigos ou suas expectativas. Os resultados acima são das execuções
finais. Não foram executados Orange Pi/ARM64, servos, PWM físico, deploy,
Supabase hospedado, commit, push ou merge. O Docker foi usado somente para
build e containers efêmeros de teste, sem alterar os serviços BinGo existentes.
