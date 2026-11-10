# Comunicação operacional Python ↔ C bloqueada — 07/11/2026

## Vigente: lifecycle Python/C integrado, ativação supervisionada pendente — 10/11/2026

O caminho privado existente agora acompanha o executor `joint-v1` pelo IPC V1
com origem PHYSICAL. `CProcessController._connect_joint` prepara o mesmo receptor
C; `MechanicalService` aceita essa capacidade configurada, vinculada ao mesmo
journal Python. Não existe outro driver, serviço, protocolo, endpoint ou flag
de habilitação. **`open_operational` continua retornando UnavailableController
para configurações físicas executáveis**, antes de iniciar o processo. O
FastAPI operacional permanece bloqueado por PHYSICAL_SUPERVISION_PENDING,
com execution_ready=false. Apenas testes com o harness existente exercitam a
composição preparada; nenhum PWM real foi acessado.

### Identidade, snapshot e duração

- O serviço persiste INTENT e o snapshot JSON na mesma transação, depois reivindica
  DISPATCHING com versão/lock existentes, antes de qualquer SUBMIT. O adaptador
  verifica novamente a intenção durável e o snapshot antes de escrever no IPC.
- `mechanical_controller_bindings` é uma extensão aditiva e imutável **dentro do
  SQLite Python existente**, com FK para o mesmo mechanical_command_id. Não altera
  as colunas/identidades/históricos atuais nem a versão SQLite Python. Registros
  antigos permanecem sem binding; nenhuma configuração é inferida para eles.
- O filho lê uma cópia estável dos bytes do mesmo JSON por `--config` e um FD
  herdado em `/proc/self/fd`. É somente congelamento da configuração existente,
  não transporte alternativo. Edições posteriores no arquivo não mudam a ordem
  em andamento. Os bytes completos são retidos nos journals Python e C v4.
- IDs/eventos/timeout não são alterados. Repetição retorna a entrada Python já
  existente, sem reclamar INTENT nem reenviar. Deriva de snapshot bloqueia uso do ID.
- O orçamento preparado é **30 s**: 5000 ms abertos + 5000 ms de estabilização +
  20 s para readback inicial, SQLite, sysfs, escalonamento e IPC. É margem técnica,
  não tempo mecânico nem prova. A configuração/CLI informa
  `physical_command_timeout_seconds=30`. O prazo genérico histórico de 10 s em
  MechanicalCommand continua inalterado; novos ciclos físicos devem declarar
  pelo menos 30 s (até o limite C de 86400 s). Outro opcode físico é recusado.
- SUBMIT/handshake mantêm o limite curto de I/O configurado (exemplo: 2 s).
  GET/wait de uma ordem aceita usa o **restante** do prazo monotônico original,
  sem reiniciar o orçamento a cada consulta. Não há polling/reenvio automático.

### Resultado operacional, encerramento e recuperação

COMPLETED/SUCCEEDED/PHYSICAL é registrado no journal mecânico como conclusão
operacional reportada pelo C, sob o snapshot `operational-sequence-v1`. Não mede
posição/queda nem escreve physical_confirmed, payload, recibo, pontuação ou
registro econômico. O bloqueio anterior da sessão após conclusão PHYSICAL é
preservado: ela permanece INDETERMINATE com slot retido, pois o descarte físico
continua sem conclusão autorizada. A conclusão do comando e a da sessão são distintas.
Não se envia CONFIRM_INITIAL_STATE automaticamente nem se recupera porta superior.

Recusas do C podem vir com origem UNAVAILABLE mesmo no canal PHYSICAL. O adaptador
preserva essa resposta; o journal aceita somente essa recusa correlata mantendo
a origem imutável da intenção PHYSICAL. Nunca normaliza uma resposta de sucesso
UNAVAILABLE/SIMULATED para sucesso físico.

Timeout, cancelamento, desconexão, resposta ambígua ou regressão terminal tornam
o fluxo desconhecido e inutilizam o canal quando necessário. O ciclo fica bloqueado
e não há reconnect, reenvio, fechamento corretivo ou movimento de recuperação.
No encerramento físico, o adaptador fecha stdin e envia SIGTERM ao handler C
existente, aguarda de forma limitada e mantém um waiter se o processo não sair.
Não usa SIGKILL nesse caminho. Isso **não comprova parada mecânica**: o último PWM
pode continuar aplicado. Se o kernel/processo não encerrar, o lock C pode continuar
retido; não se remove lock nem se inicia outro executor para contorná-lo.

Após reinício, a recuperação já existente transforma DISPATCHING/ACCEPTED Python
em INDETERMINATE/UNKNOWN; INTENT não despachado é ABORTED. O C v4 mantém sua
recuperação ACCEPTED → FAILED/UNKNOWN. `MechanicalService.reconcile(id)` é uma
consulta interna **explícita GET do mesmo ID**, sem endpoint novo. Acrescenta ao
histórico Python uma observação RECOVERY_C_* mantendo INDETERMINATE/UNKNOWN,
mesmo se o C já tiver COMPLETED durável. NOT_FOUND também não autoriza SUBMIT.
Observações repetidas iguais não criam versões extras. Não promove a sessão
ou um resultado indeterminado automaticamente.

Como V1 GET não transporta o snapshot, o C agora recusa resultados de configuração
diferente da carregada com o frame existente `V1 ERROR CONFIGURATION_CONFLICT`.
Não altera registros, campos/opcodes V1 ou schema C v4. A consulta histórica sem
configuração continua disponível no receptor bloqueado; o backend exige binding
exato para sua recuperação física. IDs antigos sem binding não são reinterpretados.

### FastAPI, tela e próximos passos

O lifespan reconhece a origem do CProcessController e usa o mesmo MechanicalService,
inclusive no encerramento e em falha de composição. A composição física preparada
foi testada por injeção controlada de subprocesso/harness. A composição operacional
por ambiente/JSON permanece bloqueada, sem override de homologação.
Rotas, modelos HTTP, fluxos de sessão e regras econômicas não foram alterados.

Para conectar o fluxo real da tela ainda é necessário:

1. Homologar o executor C **e o lifecycle Python** supervisionados no Orange Pi:
   condição inicial PWM, ciclo conjunto, timeout/interrupção/shutdown/reinício e
   intervenção segura. Calibração já aprovada não foi inventada ou substituída.
2. Homologar parada/recuperação e reconciliação operacional; o código atual apenas
   inibe novas escritas e retém UNKNOWN. Não há desbloqueio automático.
3. Após essa homologação, conectar explicitamente a composição operacional ao
   caminho preparado. Não basta preencher JSON ou mudar uma flag.
4. Ligar as ações **existentes** de sessão/retirada da mão/aprovação ao
   MechanicalService com ID mecânico estável, event_id e orçamento de 30 s,
   preservando o fluxo sem porta superior. Hoje `SessionService.safety` para em
   PHYSICAL_BLOCKED e `hand_removed` ainda recusa integração física. Nenhuma
   dessas ações despacha motores neste incremento. A política de retorno/exibição
   da sessão após resultado operacional também precisa dessa ligação explícita;
   sucesso do comando continua insuficiente para finalizar descarte/economia.

### Validação e arquivos

**430 testes focados aprovados, zero falhas/skips, 34,15 s**, sem hardware,
com compilações C11 (-Wall -Wextra -Werror). A imagem de testes existente foi
reutilizada sem alteração de Docker. O novo `test_c_physical_backend.py` exercita
IPC/journal/executor C reais por meio do harness de syscalls existente: sucesso
além do limite curto de I/O, falha de um canal, fechamento/interrupção, timeout,
desconexão, cancelamento, shutdown sem SIGKILL, duplicação, crash, recuperação GET,
bindings históricos ausentes, snapshots divergentes e lifecycle/gate FastAPI.

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_physical_backend.py tests/test_c_joint_executor.py tests/test_c_joint_cycle.py tests/test_c_project_mapping.py tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py tests/test_sessions.py --tb=short
```

Arquivos deste incremento: `app/services/c_controller.py`, `controller_config.py`,
`mechanical.py`; `app/main.py`, `mechanical.py`, `mechanical_journal.py`, `storage.py`;
`tests/test_c_physical_backend.py`, `test_c_joint_executor.py`;
`controller/bingo_ipc.inc`, `controller/tests/pwm_driver_test.c`; este contrato,
`MECHANICAL_INTERNAL_V1.md`, `controller/PHYSICAL_PWM_DRIVER.md` e
`Software/docs/STATUS_12-08.md`. Alterações dos incrementos anteriores já presentes
na branch foram preservadas. Sem motores, deploy, commit, push ou merge.

## Histórico: executor C operacional, backend ainda bloqueado — 10/11/2026

O executor C existente executa o plano conjunto somente com a extensão explícita
`completion_policy=operational-sequence-v1`, `initial_condition=closed_pwm_readback`,
`close_settle_ms=5000`. Hold aberto continua 5000 ms após ambas as escritas.
Plano C/Python: REQUIRE_CLOSED_PWM → OPEN_BOTH → HOLD_OPEN → CLOSE_BOTH → SETTLE_CLOSED.
O responsável aprovou 5000 ms após fechamento, já utilizados no script presencial
`/tmp/bingo_teste_duas_escotilhas.sh`. Não é tempo mínimo nem confirmação de pose.
Sucesso C é conclusão operacional sem erro detectado, sem posição medida ou
prova independente de queda. Detalhes: [driver](../controller/PHYSICAL_PWM_DRIVER.md).

`controller_config.py` valida estritamente o grupo da extensão, preserva os planos
sem ela e projeta os mesmos campos que o C. `diagnose_operational` compara também
`c_executor_configured`; esse indicador é capacidade **configurada**, sem I/O físico.
`execution_ready` Python permanece false. O `open_operational` retorna
UnavailableController com PHYSICAL_BACKEND_INTEGRATION_PENDING **antes de iniciar
o processo ativo**. Configurações antigas ainda conectam em CONNECTED_BLOCKED.
Isso evita utilizar o encerramento/timeout do adaptador bloqueado para controlar
um processo que esteja movimentando motores. Diagnóstico genérico sem configuração
continua histórico; não substitui o diagnóstico configurado.

IPC V1 não ganhou opcodes. O C ativo anuncia
`V1 READY PHYSICAL DOORLESS_V1 OPERATIONAL_SEQUENCE_V1`; SUBMIT/GET/resultados
mantêm seus campos. Journal físico v4 migra v2/v3 preservando rowids, IDs, resultados
e snapshots; somente novos snapshots com política operacional podem registrar
COMPLETED/SUCCEEDED/PHYSICAL. ACCEPTED recuperado vira UNKNOWN sem PWM. Journal
Python, protocolos/perfis simulados, locks e idempotência permanecem inalterados.

Para ligar o backend em incremento posterior, faltam especificamente:

- `CProcessController._launch`, parsing/respostas e composição operacional:
  capacidade PHYSICAL explícita, prazos de I/O/consulta compatíveis com >10 s e
  encerramento que preserve UNKNOWN sem matar/reiniciar/reenviar como recuperação.
- `MechanicalService`/modelos e journal Python: aceitar resultado operacional
  sem convertê-lo em `physical_confirmed`, validar origem/basis/snapshot e
  reconciliar o mesmo ID após perda de resposta, preservando INDETERMINATE.
- Homologar intervenção/parada/recuperação presencial para erros. O C apenas
  inibe novas escritas; o último PWM pode continuar ativo. Nenhuma política de
  recuperação, reconciliação automática, sensor ou crédito econômico foi criada.

## Histórico: comunicação bloqueada e preparação do plano

Plano conjunto implementado em 10/11: o schema existente aceita o modo
`physical.cycle.mode="joint-v1"` e exige inteiro `hold_open_ms=5000`, marco
`after_both_open_commands` e relógio `monotonic`. C/Python produzem o mesmo plano
de cinco etapas e o adaptador confere também `cycle_policy`. Modo ausente mantém
a sequência/ausência de plano anterior; não há defaults conjuntos. O JSON de
exemplo usa o novo modo, com ordens sequenciais nulas. Não há execução da
permanência nem liberação física por esse diagnóstico. IPC/journals e políticas
de resultado desconhecido permanecem. Contrato: [PROJECT_MAPPING.md](../controller/PROJECT_MAPPING.md).

Mapeamento atualizado em 10/11, após os testes reais relatados no Orange Pi Zero 3:
[PROJECT_MAPPING.md](../controller/PROJECT_MAPPING.md). Olhando pela frente, o
JSON define direita em pwmchip0/canal 3 e esquerda em pwmchip0/canal 4. RX/TX
ficam desconhecidos (`null`), sem alteração do cabeamento. Python encaminha o JSON
explicitamente ao C e verifica o mapa/plano retornados. A dependência anterior
da variável herdada pelo filho não se aplica mais. Atuação permanece bloqueada.

Calibração e decisão registradas em 10/11: período 20.000.000 ns, polaridade
normal, direita fechada/aberta 1.750.000/600.000 ns e esquerda
1.350.000/2.300.000 ns. O teste conjunto montado teve alinhamento, abertura e
queda de objeto aprovados pelo responsável. Abertura/fechamento devem ser
conjuntos, praticamente simultâneos; as opções sequenciais `open_order` e
`close_order` permanecem `null`, representando-se a decisão pelo novo modo.
Não foi implementado executor ou liberado PHYSICAL. Evoluções e pendências:
[PROJECT_MAPPING.md](../controller/PROJECT_MAPPING.md).

Atualização C de 09/11: o journal físico migra agora para v3, com snapshot de
configuração e retenção de intenções UNKNOWN. As primitivas PWM foram preparadas,
mas o handshake e o bloqueio operacional Python permanecem. O estado vigente
do driver C está em [PHYSICAL_PWM_DRIVER.md](../controller/PHYSICAL_PWM_DRIVER.md);
as descrições de schema físico exclusivamente de recusas abaixo registram a
etapa anterior.

O backend agora pode compor `CProcessController` no lifespan operacional,
usando o protocolo V1 e os contratos/journals existentes. O processo C físico
atual **somente registra e recusa comandos**. A comunicação pode funcionar com
`source=UNAVAILABLE`; isso não autoriza movimento nem confirma descarte.
Não foram criados simuladores, endpoints HTTP ou outro transporte.

## Configuração explícita

`BINGO_C_CONTROLLER_CONFIG` indica o caminho absoluto de um JSON local no
formato de [operational.example.json](../controller/operational.example.json).
O exemplo é um modelo não instalado, com caminhos ilustrativos. Ele deixa
todos os dados físicos desconhecidos como `null`; não há defaults Linux,
pulsos calculados, sensor presumido ou chave para habilitar movimento.

- `schema`: `bingo-c-controller-v1`; campos extras são recusados.
- `executable`: caminho absoluto do binário compilado **sem**
  `BINGO_PWM_SIMULATED`. Não há shell ou argumentos arbitrários no JSON.
- `journal`: caminho absoluto do SQLite exclusivo do C, separado do SQLite
  Python. O diretório deve existir e permitir escrita pelo usuário do serviço.
  A composição não cria diretórios nem muda permissões de dispositivos.
- `profile`: somente `doorless-v1`. Não há configuração operacional com porta
  superior nem opções de falha/latência do laboratório.
- `io_timeout_seconds`: prazo de I/O positivo, finito e até 60 s (padrão 2 s).
  Não é tempo de queda; o prazo total do comando no coordenador é preservado.
- `physical`: declarações por lado de conector/pad, chip/canal e pulsos;
  período/polaridade e referências dos registros de mapeamento, calibração,
  conclusão e segurança/recuperação. Referências textuais não comprovam
  homologação por si só. Canal compartilhado e pulso >= período são inválidos.

O JSON registra o mapa físico confirmado: direita/canal 3 com 70°/175° e
esquerda/canal 4 com 113°/5°, ambas no chip 0, vistas pela frente. O C e o Python
leem esse arquivo; não deduzem canais de RX/TX. Referências e resultados históricos
conservam seus significados originais. Os pulsos atuais vêm da calibração física
aprovada, não de conversão dos graus ou de valores nominais históricos.

Sem variável de configuração, o padrão continua `UnavailableController` e
nenhum processo C é criado. Arquivo inválido, ausente, maior que 16 KiB,
caminhos relativos ou colisão entre bancos/sidecars também deixam o controller
indisponível. Symlinks e hardlinks existentes entram na verificação de colisão.
Configuração operacional combinada com factory injetada/perfil DEV é recusada,
antes da abertura do store. Não existe fallback para o binário simulado.

## Diagnóstico e composição

Da pasta backend, com Python do projeto:

```sh
python -m app.controller_cli --config /caminho/absoluto/controller.json --backend-journal /caminho/absoluto/totem.sqlite3
```

Esse comando apenas valida a configuração e consulta `--physical-preflight`.
Não abre/cria journals, não envia SUBMIT/GET e não testa sua escrita/lock. O
modo anterior `--executable /caminho/binario` também continua disponível.
O código de saída permanece 2 porque a atuação continua bloqueada.

`CProcessController.diagnose_operational` retorna configuração e prontidão.
`CProcessController.open_operational`, chamado pelo lifespan, reaproveita esse
diagnóstico e inicia o **mesmo adaptador**, com:

```text
binario --ipc-physical /caminho/absoluto/controller.sqlite3 --profile doorless-v1
V1 READY UNAVAILABLE DOORLESS_V1 PHYSICAL_BLOCKED
```

O primeiro é o formato de invocação interno, não um procedimento de deploy.
Não são enviados comandos de inicialização, homing ou confirmação automática.
O C físico não aceita `--ipc-simulated`, perfis com porta ou opções de falhas.
Um C simulado não pode fornecer preflight/handshake operacional válido.

| Dimensão | Estados e significado |
| --- | --- |
| `configuration` | `NOT_CONFIGURED`, `INVALID`, `INCOMPLETE` ou `DECLARED` (somente preenchida; não homologada) |
| `transport` | `NOT_CONNECTED`, `DIAGNOSTIC_OK` (preflight válido), `CONNECTED_BLOCKED` (IPC e journal C abertos) ou `FAILED` |
| `execution_ready` | Sempre `false` nesta entrega |
| `source` | Sempre `UNAVAILABLE` no caminho operacional |
| `blockers` | Falhas de configuração/comunicação e impedimentos físicos preservados pelo C |

Prontidão inicial privada em `app.state.controller_readiness`; o C conectado
também expõe `app.state.controller.readiness`, que informa fechamento/desconexão
observados localmente. Não foi criada rota pública. Consultar prontidão não
desbloqueia o serviço nem altera `/health`, `/local/status` ou economia.

## Journal, idempotência e falhas

O `MechanicalService` continua coordenando INTENT → DISPATCHING → observação
durável no journal Python. Sua recusa de origem PHYSICAL permanece. O lifespan
usa `source=UNAVAILABLE` para o C operacional, permitindo registrar recusas
reais sem promover qualquer ciclo a confirmação física.

O receptor C reaproveita SUBMIT/GET/RESULT V1, correlação integral por
`mechanical_command_id`/evento/operação/timeout/perfil, WAL, synchronous=FULL,
lock exclusivo por journal e triggers de identidade/retenção. Cada ordem válida
recebe `REJECTED/UNAVAILABLE/CONTROLLER_UNAVAILABLE/UNAVAILABLE`, duravelmente
gravado antes da resposta. Inclusive `CONFIRM_HAND_REMOVED` e
`CONFIRM_INITIAL_STATE` são recusados; não existe sucesso físico implícito.
Comandos de porta também nunca são aceitos.

O journal C operacional tem `application_id=1112098640`, distinto do laboratório
(`1112098627`). A identidade é conferida antes de mudar o modo de journal.
Os dois binários recusam o banco do outro; a migração histórica v1 continua
exclusiva do laboratório. O schema operacional permite apenas recusas, impedindo
gravá-las como ACCEPTED/COMPLETED. Não houve migração/schema novo no journal
Python, nem alteração de IDs existentes.

Duplicata idêntica recupera o resultado retido, inclusive depois de reiniciar
os dois processos. Parâmetros divergentes no mesmo ID são conflito. GET não
redispara nem recupera elegibilidade. IDs não são apagados/reciclados; a
capacidade existente de 1024 ordens do C continua fechando ao atingir o limite.

Falha antes de conectar (permissão/lock/banco incompatível/handshake)
mantém o default indisponível com diagnóstico de transporte. Erro no I/O de
uma ordem já despachada, timeout ou perda de resposta ficam UNKNOWN/
INDETERMINATE no journal Python, mesmo se o C já tiver registrado uma recusa.
Reiniciar/consultar não transforma incerteza em sucesso nem reenvia a ordem.
Resposta com identidade/origem/estado inconsistente fecha o canal. Não há
reconnect, fila, redisparo ou comando corretivo automático. Encerramento mata
apenas um filho que se anunciou simulado ou incapaz de atuar; isso não define
parada física segura para um futuro driver habilitado.

## O que ainda precisa da placa e da homologação

1. Resolver presencialmente cada ligação RX/TX → conector/pad/pinmux →
   controlador/canal Linux, incluindo conflito com UART/console. A divergência
   de lados do legado continua aberta.
2. Calibração real já aprovada e registrada no JSON. Vincular sua referência
   formal na evolução de prontidão, sem remover os demais bloqueios.
3. Confirmar alimentação externa/GND comum e comportamento sob carga; homologar
   permanência aberta, conclusão, parada, obstrução, falha parcial e recuperação após perda de
   energia/sinal ou posição desconhecida.
4. Evoluir os contratos sequenciais para etapas conjuntas e definir a evidência
   de conclusão do ciclo e retorno inicial.
   Não foi presumido sensor. Escrita PWM/aceite/tempo não confirmam movimento.
5. Homologar durabilidade no armazenamento do Orange Pi e exclusão do dispositivo
   entre processos/journals distintos. O lock atual protege um mesmo journal;
   como não há atuação, não representa ainda um lock global de hardware.

Após isso será necessário implementar/homologar o executor físico e sua
resposta terminal. **Preencher o JSON não o implementa nem o habilita.** As
declarações físicas são diagnosticadas no Python; não são aplicadas ao sysfs
pelo C atual. O C mantém todos os bloqueios de homologação, além de
`PHYSICAL_DISPATCH_DISABLED`, mesmo com `configuration=DECLARED`. A futura
semântica física deve vincular mapa/calibração versionados à identidade durável
e conservar os resultados atuais como recusas, sem reinterpretar/reexecutar IDs.

## Validação sem hardware

Os testes novos usam o executável C compilado e SQLite temporário, incluindo
composição do lifespan, reabertura de ambos os journals, conflitos, lock,
incompatibilidade de origem, corrupção, aliases/sidecars, perda de resposta,
timeout e desconexão, além de conferir que declarações completas não habilitam
movimento. Os testes de regressão focados existentes verificam os demais
bloqueios do coordenador e o fluxo sem porta.

Execução em container efêmero da imagem de ferramentas existente, checkout
somente leitura, sem rede/dispositivos, tmpfs temporário, capacidades removidas.
Nenhum Dockerfile, compose ou imagem operacional foi alterado nesta continuação.
Não houve alteração de frontend, IA ou Supabase, nem commit, push ou deploy.

Resultado final: **264 aprovados, zero falhas/skips, 25,16 s**. As fixtures
compilaram ambas as variantes C com `-std=c11 -Wall -Wextra -Werror
-Wno-unused-function`, ligadas ao SQLite. Arquivos executados:

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_controller_operational.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py tests/test_auto_initial.py tests/test_routes.py --tb=short
```

O harness dos testes de CLI reserva até 10 s à partida do interpretador/imports,
independente do prazo de I/O com o C (padrão 2 s), que não foi ampliado. Na
rodada final, o teste do CLI anterior levou 2,79 s nesse ambiente de bind mount.
Não foram executados testes físicos, Orange Pi/ARM64, servos ou GPIO.
