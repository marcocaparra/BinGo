# Mapeamento físico pela frente e ciclo C/Python — 10/11/2026

## Vigente: execução operacional conjunta no C — 10/11/2026

O executor do plano existente foi implementado no C, com a política explícita
`physical.cycle.completion_policy="operational-sequence-v1"`,
`initial_condition="closed_pwm_readback"` e `close_settle_ms=5000`.
Plano concordante C/Python: REQUIRE_CLOSED_PWM → OPEN_BOTH → HOLD_OPEN → CLOSE_BOTH
→ SETTLE_CLOSED. Mantêm-se hold_open_ms=5000, marco após ambas as escritas e
CLOCK_MONOTONIC. A condição inicial exige comandos PWM habilitados e calibrados
como fechados; não mede posição. Abertura e fechamento são pares de escritas
consecutivas, sem espera de motor entre elas, sem garantia de sincronismo elétrico.

O responsável confirmou 5000 ms após fechamento no script físico
`/tmp/bingo_teste_duas_escotilhas.sh` (3000 ms inicial fechado, 5000 ms aberto,
5000 ms fechado), no Orange Pi Zero 3 em 10/11. É duração operacional aprovada,
não mínimo necessário nem comprovação física por tempo. O mapa/pulsos abaixo
permanecem; RX/TX continuam desconhecidos. Conclusão passou a admitir execução
operacional integral sem erro detectado, separada de posição/queda medida.

O mesmo IPC V1 e driver agora podem executar CYCLE_LOWER_HATCH no C quando a
política e suas referências estiverem completas. Não há flag de habilitação.
Intento durável, locks do journal/canais e snapshot imutável precedem movimento;
falha/interrupção/timeout mantém UNKNOWN e impede repetição. Journal físico v4
estende v3 apenas para resultados operacionais novos, preservando históricos.
Sem a extensão, as configurações antigas continuam bloqueadas e os planos antigos
mantêm seu significado. Sem homing, fechamento corretivo ou desligamento automático.

Python valida/compara a extensão e diagnostica `c_executor_configured`, mas
**recusa iniciar esse receptor ativo**; backend/economia permanecem bloqueados.
Faltam o tratamento PHYSICAL no adaptador/serviço, prazos para o ciclo >10 s,
lifecycle de interrupção e reconciliação sem redisparo. Não reutilizar o encerramento
do subprocesso bloqueado como política de parada física.
Contrato vigente, roteiro presencial e limites:
[PHYSICAL_PWM_DRIVER.md](PHYSICAL_PWM_DRIVER.md).

Validação final do executor: 376 testes focados aprovados, zero falhas/skips,
44,48 s, com compilações C e sem hardware. Comando, falhas cobertas e registro
do timeout transitório da CLI estão no documento do driver acima.

## Histórico: plano sem executor

Esta atualização usa o driver físico, JSON operacional, IPC V1 e journals já
implementados. Não há novo transporte, API HTTP, simulador ou executor alternativo.
A atuação permanece bloqueada, inclusive quando todos os campos forem declarados.

## Plano conjunto joint-v1 implementado — 10/11/2026

O contrato `physical.cycle`, os validadores e os construtores do plano em C e
Python agora reconhecem explicitamente o modo conjunto. A calibração e o mapa
aprovados abaixo permanecem iguais. Não foi implementado executor, relógio de
execução, confirmação física ou liberação de despacho neste incremento.

Trecho do modelo JSON operacional:

```json
"cycle": {
  "mode": "joint-v1",
  "hold_open_ms": 5000,
  "hold_start": "after_both_open_commands",
  "hold_clock": "monotonic",
  "open_order": null,
  "close_order": null,
  "drop_reference": null,
  "homologation_reference": null
}
```

`joint-v1` versiona a semântica do plano dentro do schema existente
`bingo-c-controller-v1`; não altera perfis históricos, opcodes IPC ou schemas
dos journals. Os quatro campos do modo/tempo são obrigatórios quando o modo
conjunto é declarado. A duração é um inteiro estrito de **5.000 ms**, não 5,
5000.0, string ou booleano. Outro valor exige uma evolução explícita da política;
não é aceito silenciosamente no mesmo modo. O relógio deve ser `monotonic` e o
marco `after_both_open_commands`. Modo desconhecido, dados de tempo sem modo ou
mistura com ordem sequencial são rejeitados por ambos os validadores, antes de
abrir o journal C. Não se redefine `left_then_right`/`right_then_left` como conjunto.

O plano é uma tupla/lista de nomes de etapa, com metadados de tempo separados:

| Etapa | Semântica para o futuro executor |
| --- | --- |
| `REQUIRE_INITIAL_CLOSED` | Exigir estado inicial fechado comprovado conforme a política homologada; não fazer homing ou presumir posição após restart |
| `OPEN_BOTH` | Comandar ambas no mesmo estágio, sem esperar a conclusão física de uma para iniciar a outra |
| `HOLD_OPEN` | Manter o comando de abertura por 5.000 ms de relógio monotônico a partir da conclusão bem-sucedida das escritas dos **dois** comandos de abertura |
| `CLOSE_BOTH` | Após essa permanência, comandar ambas no mesmo estágio, sem espera entre conclusões de motores |
| `AWAIT_INITIAL_EVIDENCE` | Aguardar critério físico homologado de conclusão/retorno; não converter escrita ou tempo em SUCCEEDED |

O marco escolhido é **após ambos os comandos**, não após o primeiro, aceite
IPC, partida do processo ou pose aberta supostamente atingida. Se um canal
falhar, não há dois comandos bem-sucedidos: não se inicia uma permanência para
justificar fechamento automático ou conclusão. Os cinco segundos representam
permanência comandada, não prova de cinco segundos em posição fisicamente aberta,
nem prova de queda. Expirar esse tempo só habilitaria a próxima etapa do plano
homologado, jamais uma confirmação física.

`pwm_build_cycle()` e `CycleDeclarations.plan()` constroem as mesmas cinco
etapas sem I/O PWM, sleep, avanço de relógio ou criação de intenção. O diagnóstico
C acrescenta `cycle_policy` somente para `joint-v1`; Python valida e compara
esse objeto (modo, duração, marco e relógio), além das etapas já comparadas.
Mesmas etapas com tempo ausente/divergente também falham fechadas. A prontidão
privada expõe `cycle_plan` e `cycle_policy`, mantendo `execution_ready=false`,
`source=UNAVAILABLE` e `CYCLE_POLICY_UNVERIFIED` enquanto as referências da
política não estiverem declaradas. Mesmo referências preenchidas não concedem
o permit físico: confirmação, parada e recuperação continuam sem executor homologado.

### Compatibilidade e resultados desconhecidos

Sem `mode` (ou com `mode:null` e sem dados de tempo), configurações antigas
continuam vazias/parciais ou produzem exatamente o plano sequencial anterior de
sete etapas, conforme seus próprios campos e referências. Não recebem `joint-v1`
ou cinco segundos por default. O diagnóstico legado conserva sua forma anterior,
sem `cycle_policy`. Novos dados de tempo exigem o novo modo; não há fallback
para sequência se um documento conjunto for inválido.

O snapshot JSON imutável do journal físico v3 inclui os novos campos de forma
natural, sem migração. Reusar um ID antigo com configuração conjunta é conflito,
não upgrade ou execução. O mesmo ID com seu snapshot original continua
consultando/repetindo a resposta original. Journals Python e C, locks e protocolo
V1 não foram modificados. Intenção física pendente continua virando UNKNOWN no
restart; timeout, interrupção e resposta perdida não provocam redisparo.
O laboratório doorless-v1 conserva seus parâmetros/relógio virtual históricos.

### O que falta para executar no controlador C existente

O receptor ainda tem `allowed=0`, anuncia UNAVAILABLE/PHYSICAL_BLOCKED e recusa
CYCLE_LOWER_HATCH. O schema físico v3 continua sem COMPLETED/SUCCEEDED. O novo
plano não chama `pwm_pose` nem abre uma rota alternativa de controle.

É necessário implementar e homologar, no mesmo driver/IPC/journals:

1. Critério para estado inicial fechado e confirmação física do ciclo/retorno,
   com correlação do mesmo ID e configuração. Não foi escolhido ou inventado sensor.
2. Executor das duas saídas por estágio, reutilizando os locks; `pwm_pose()`
   atual atua por lado e inibe após resultado desconhecido, portanto um loop
   chamando-a duas vezes não executa o estágio conjunto corretamente. Medir e
   homologar a defasagem admissível, sem alegar atomicidade de escritas sysfs.
3. Contagem monotônica real conforme o marco acima, somente quando os dois
   comandos de abertura forem bem-sucedidos; a contagem não será retomada para
   reacionar ou fechar automaticamente uma intenção indeterminada após restart.
4. Parada segura e recuperação em falha parcial, obstrução, timeout, cancelamento,
   perda de sinal/energia e posição desconhecida. Matar o processo não é parada física.
5. Integração controlada de resultados PHYSICAL e conclusão comprovada no C,
   adaptador, MechanicalService e guardas de journal/estado. Qualquer evolução
   futura de resultado/schema requer critério homologado e retenção do histórico.
   O acompanhamento limitado de `wait/GET` também deve ser adequado ao executor:
   `io_timeout_seconds` é prazo de comunicação, não os cinco segundos de
   permanência nem o prazo total da operação. O contrato atual do filho
   sequencial não constitui ainda um executor físico cooperativo.

RX/TX, pad/conector e referências formais não foram inferidos ou preenchidos.
Não foi alterada a interface, câmera, IA, Supabase, economia ou Docker.

### Validação deste incremento

Resultado final: **329 testes focados aprovados, zero falhas/skips, 23,02 s**.
Inclui os dois builds C e o harness nativo com `-std=c11 -Wall -Wextra -Werror
-Wno-unused-function -lsqlite3`. Execução em container efêmero da imagem de
ferramentas existente, sem rede/dispositivos, checkout readonly e tmpfs temporário.
Nenhum container operacional, Dockerfile ou compose foi alterado.

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_joint_cycle.py tests/test_c_project_mapping.py tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```

Os novos testes verificam tipos/duração/marco/relógio inválidos, mistura de
políticas, cinco etapas e metadados iguais entre C/Python, ausência de I/O ao
planejar, diagnósticos temporais ausentes/divergentes, arquivos legados sem
promoção implícita, snapshots/IDs retidos, UNKNOWN no restart e ausência de
redisparo. Foram reutilizados os ensaios de falha parcial das primitivas por
ambos os lados e os ensaios de timeout/desconexão/resposta perdida do backend,
agora também com configuração conjunta. Isso não é homologação de um executor
conjunto físico, que continua ausente.

Uma rodada anterior teve timeout de 10 s no harness do CLI Python (163 outros
testes aprovados); o mesmo teste passou isolado em 2,03 s e na rodada final em
1,48 s. Nenhum limite de I/O ou do harness foi ampliado para obter aprovação.
Formatação dos arquivos Python alterados e `git diff --check` verificados.

Arquivos do incremento (caminhos a partir de `Hardware/TotemEdge`, salvo STATUS):

- `controller/operational.example.json`: novo modo e política temporal explícita.
- `controller/bingo_pwm.inc`: parser, validação, construção do plano e diagnóstico.
- `backend/app/services/controller_config.py`: contrato Python e política tipada.
- `backend/app/services/c_controller.py`: comparação/exposição da política e bloqueio.
- `controller/tests/pwm_driver_test.c`: aceita cinco etapas novas ou sete históricas.
- `backend/tests/test_c_joint_cycle.py`: testes novos de contrato, tempo e segurança.
- `backend/tests/test_c_project_mapping.py`: expectativa do modelo conjunto atual.
- `controller/PROJECT_MAPPING.md`, `controller/README.md`,
  `controller/PHYSICAL_PWM_DRIVER.md`, `backend/OPERATIONAL_C_CONTROLLER.md`,
  `backend/MECHANICAL_INTERNAL_V1.md` e `Software/docs/STATUS_12-08.md`: contrato,
  estado atual, compatibilidade e pendências, preservando os registros anteriores.

As alterações de calibração/documentação do incremento anterior que já estavam
na árvore foram preservadas. Sem commit, push, merge ou deploy.

## Calibração física aprovada e movimento conjunto — 10/11/2026

O responsável informou testes reais no Orange Pi Zero 3, com as duas escotilhas
montadas: fechamento perfeitamente alinhado, abertura adequada, ciclo conjunto
de abertura/fechamento e queda bem-sucedida de um objeto. Essa é uma evidência
observacional fornecida pelo responsável, não uma execução feita pelo Codex ou
uma confirmação automática produzida pelo backend. Não foram fornecidos
sensores, registros elétricos de RX/TX ou tolerância temporal numérica.

Calibração aprovada, **olhando o Totem pela frente**:

| Lado | Saída Linux | Pulso fechada | Pulso aberta | Graus preservados fechada/aberta |
| --- | --- | --- | --- | --- |
| Direita | pwmchip0/canal 3 | 1.750.000 ns | 600.000 ns | 70° / 175° |
| Esquerda | pwmchip0/canal 4 | 1.350.000 ns | 2.300.000 ns | 113° / 5° |

Período aprovado: **20.000.000 ns**. Polaridade aprovada: **normal**. Esses seis
valores foram copiados para o modelo JSON; não foram calculados a partir dos
graus nem substituídos por pulsos nominais do legado. Os graus, canais e chip
existentes foram preservados.

Decisão funcional aprovada pelo responsável:

1. Ambas começam fechadas, nas posições calibradas.
2. Ambas recebem comandos de abertura praticamente simultâneos e descem juntas.
3. Permanecem abertas por cinco segundos contados pela política explícita
   `joint-v1` descrita acima; tempo não comprova posição ou queda.
4. Ambas recebem comandos de fechamento praticamente simultâneos e sobem juntas.
5. Retornam às posições calibradas de fechamento.

O teste conjunto já foi realizado com sucesso. **Abertura sequencial não é o
comportamento final aprovado.** A permanência aberta, o critério de conclusão e
a recuperação após falha não foram homologados por esse relato. A decisão
posterior aprovou os cinco segundos e o plano foi implementado, mantendo a
execução bloqueada. Não se adota seis segundos, confirmação por tempo, homing automático nem posição inicial
presumida depois de restart. O alinhamento observado na bancada não resolve a
posição de um mecanismo após perda de energia ou comunicação.

O incremento anterior limitou a alteração operacional aos quatro pulsos, período e
polaridade. `calibration_reference` permanece `null`, assim como as referências
de conclusão/segurança/ciclo; a aprovação física está registrada nesta seção.
Consequentemente, o diagnóstico conservador ainda pode listar
`PULSE_CALIBRATION_UNVERIFIED` por falta dessa referência formal, embora os
valores físicos já estejam aprovados. Isso não é uma solicitação para repetir
a calibração. RX/TX, pad e conector permanecem desconhecidos. O modelo não foi
instalado na placa e nenhum despacho foi liberado.

## Convenção e fonte de configuração

A convenção definitiva de orientação é **olhando o Totem pela frente**. O
responsável informou que os dois canais foram testados fisicamente no Orange Pi
Zero 3 e movimentaram os motores correspondentes. Esse relato de 10/11/2026 é a
evidência registrada em `mapping_reference`; não é uma execução física feita
pelos testes automatizados desta alteração. Não alterar o cabeamento.

O mapa confirmado está em [operational.example.json](operational.example.json).
Esse arquivo é o modelo de configuração, não um arquivo instalado na placa.
O arquivo local indicado por `BINGO_C_CONTROLLER_CONFIG` é a fonte efetivamente
carregada. Não foram modificados arquivos operacionais fora do repositório.

| Lado visto pela frente | Chip Linux | Canal Linux confirmado | Fechada | Aberta | RX/TX |
| --- | --- | --- | --- | --- | --- |
| Direita | pwmchip0 | 3 | 70° | 175° | Não confirmado |
| Esquerda | pwmchip0 | 4 | 113° | 5° | Não confirmado |

`pwm_channel`, `closed_degrees`, `open_degrees` e `intended_signal` são campos
explícitos por lado. O driver usa somente chip/canal e pulsos declarados; não
deriva canais de RX/TX ou de nomes PWM. Graus são metadados, sem conversão em ns.
Chip/canal e ângulos agora refletem o teste relatado. `intended_signal` permanece
`null` nos dois lados; não se atribui RX/TX por posição, nome ou convenção
anterior. Não há segunda tabela ativa de mapeamento em C ou Python.

O modelo declara `pwm_chip=0` nos dois lados e agora contém período, polaridade
e pulsos aprovados na tabela acima. Pad/conector e referências formais de
calibração/conclusão/segurança continuam `null`. A evidência histórica de
`dafc9ab` não foi alterada nem usada para recalcular a calibração atual.

O preflight sem JSON agora informa `pwm_label=null`: ele não conhece o mapa
operacional. O diagnóstico configurado informa os números realmente lidos do
JSON. O laboratório antigo doorless-v1 conserva RIGHT/PWM3 e LEFT/PWM4 para
não reinterpretar seus IDs/resultados; esses rótulos não participam do driver
físico. A configuração física vigente é direita/3 e esquerda/4, ambas no chip 0.
O relato real substitui a convenção provisória inversa de 09/11. O objeto
`legacy_evidence` do preflight continua descrevendo `dafc9ab` (esquerda/3,
direita/4); não foi reescrito para aparentar que aquele commit já continha a
orientação física confirmada agora.

## Integração com o backend

`CProcessController` reaproveita seu leitor JSON com limite de 8 KiB e prazo de
I/O configurado para consultar tanto `--physical-preflight` quanto
`--physical-config ARQUIVO`. Antes de abrir o canal operacional, compara entre
C e Python o mapa, pulsos, ângulos, ligação pretendida, período, polaridade,
classificação da configuração e plano de ciclo.

Falha na validação/diagnóstico ou divergência entre interpretações deixa o
controller indisponível, sem criar journal C. Não há fallback para simulação.
O filho C recebe explicitamente `--config ARQUIVO`, inclusive em chamadas
programáticas de `open_operational`, sem depender da configuração herdada no
ambiente. Nenhum arquivo é reescrito para preencher defaults ou calibrar.

`ControllerReadiness` expõe `configured_physical` e `cycle_plan` no diagnóstico
privado existente. `execution_ready=false` e `source=UNAVAILABLE` são preservados.
Sem plano explícito acrescenta `CYCLE_POLICY_UNVERIFIED`; os bloqueios de mapa,
calibração, segurança, conclusão e despacho físico permanecem.

Diagnóstico existente, da pasta backend:

```sh
python -m app.controller_cli --config /caminho/absoluto/controller.json --backend-journal /caminho/absoluto/totem.sqlite3
```

O CLI retorna 2 por atuação bloqueada. No C, `--physical-config ARQUIVO` é somente
leitura e retorna 0 quando consegue emitir o relatório, sempre com prontidão falsa.

## Contrato sequencial anterior — compatibilidade histórica

O bloco opcional `physical.cycle` contém:

- `open_order`: `left_then_right` ou `right_then_left`;
- `close_order`: as mesmas opções, independentemente da abertura;
- `drop_reference`: referência ao critério de queda que ainda precisa de homologação;
- `homologation_reference`: registro da política de ciclo aprovada.

Esses campos permanecem `null` no modelo conjunto. `open_order` e `close_order`
não representam movimento conjunto: a nova representação usa `mode=joint-v1` e
campos explícitos de tempo. As opções antigas abaixo continuam válidas somente
no contrato legado sem modo. `simultaneous` não é um alias de ordem sequencial.

Quando explicitamente declarado, `pwm_build_cycle` em C e o modelo Python
produzem o mesmo plano sequencial de sete passos, mantido somente como contrato
anterior e cobertura de regressão; ele não é a especificação final do produto:

1. Abrir o primeiro lado configurado.
2. Abrir o outro lado.
3. Aguardar evidência de abertura.
4. Aguardar evidência de queda.
5. Fechar o primeiro lado configurado.
6. Fechar o outro lado.
7. Aguardar evidência de retorno inicial.

O plano é preparação de comandos, **não um motor de simulação nem autorização
para executar**. Ele não escreve PWM, cria intenções ou avança estados por tempo.
Não foi criado um provedor fictício de evidência. O executor que correlacionará
essas etapas com evidências reais e o mesmo ID/configuração ainda depende dos
critérios de conclusão/parada homologados. As primitivas atuais continuam
retendo UNKNOWN quando um movimento não é comprovado; o receptor de produção
recusa CYCLE_LOWER_HATCH e CONFIRM_INITIAL_STATE sem fabricar confirmação.

## Inventário anterior à implementação do plano conjunto — histórico

O quadro abaixo registra a análise do incremento anterior. Os itens de
contrato/validadores/construtores/diagnóstico do plano agora foram implementados
na seção `joint-v1` acima. Os itens de executor, confirmação, parada, recuperação
e resultados físicos seguem pendentes; nenhuma análise antiga autoriza despacho.

| Contrato/componente existente | Divergência ou bloqueio exato | Evolução necessária |
| --- | --- | --- |
| `operational.example.json`, schema `bingo-c-controller-v1`, `physical.cycle` | `open_order`/`close_order` só descrevem sequência; `null` mantém plano ausente | Definir contrato explícito/versionado de etapas conjuntas, permanência aberta e evidências; não reaproveitar um valor sequencial como sinônimo de conjunto |
| Python `app/services/controller_config.py`: `CycleDeclarations.open_order`, `close_order`, `configured()`, `plan()` | `Literal` aceita somente `left_then_right`/`right_then_left`; `plan()` emite OPEN e CLOSE separados por lado | Evoluir validação, completude e plano para uma etapa de abrir ambas e uma de fechar ambas, mantendo as esperas por evidência |
| C `bingo_pwm.inc`: `PWMConfig.open_first/close_first`, `pwm_keys_valid()`, `pwm_load_config()` | Representação interna e parser aceitam somente a política sequencial | Representar e validar a nova política conjunta no mesmo driver/JSON, sem inventar campos de sensor ou ativação |
| C `pwm_build_cycle()` e `pwm_config_report()`; Python `PhysicalConfigDiagnostic` e `ControllerReadiness.cycle_plan` | Ambos os lados expõem o plano sequencial de sete passos; somente possuir um plano não autoriza atuar | Acordar a representação e o diagnóstico das etapas conjuntas e da homologação, sem enfraquecer prontidão física |
| Python `CProcessController.diagnose_operational()` | Compara exatamente o plano calculado em Python e o retornado pelo C | Evoluir ambos de forma coordenada; discrepância continua falhando fechada |
| C `pwm_pose()`, `pwm_open_channel()`, `pwm_stop()`; `pwm_lock_channels()` | A primitiva atua por lado e marca UNKNOWN/inibe novas poses até mesmo após escrita integral; chamar duas vezes não implementa ciclo conjunto | Preparar e comandar as duas saídas como etapa comum, com a menor defasagem homologada e medida; reutilizar locks por canal e primitivas existentes; definir falha parcial e parada do par antes de permitir execução |
| C `bingo_ipc.inc`: `ipc_submit()`, `ipc_pwm_pose()`, `IPC_RESULT_CONSTRAINT`, recuperação em `ipc_start()` | `allowed=0`; helper é por pose e termina em UNKNOWN; schema físico v3 não aceita COMPLETED/SUCCEEDED | Integrar futuro executor conjunto sob intenção durável de CYCLE_LOWER_HATCH; qualquer evolução de resultado/schema precisa de evidência homologada, migração explícita e retenção de IDs/snapshots |
| Python `app/mechanical.py`: `MechanicalController`, `MechanicalResponse`, `checked_response()`; `CProcessController` handshake/decodificação/cancelamento/fechamento | O caminho operacional anuncia/espera UNAVAILABLE e apenas recusas; matar o filho não é parada física segura | Definir aceite, conclusão, timeout e parada física correlacionados ao mesmo comando, preservando o IPC V1 e sem tratar cancelamento lógico como mecanismo parado |
| Python `MechanicalService` e `MechanicalJournal` (`request/claim/observe/unknown/has_risk`) | Serviço recusa PHYSICAL; resultados desconhecidos ou PHYSICAL/COMPLETED mantêm bloqueios conservadores | Integrar a origem física somente após homologação dos critérios, mantendo exclusão, prazos e UNKNOWN/INDETERMINATE; não promover histórico antigo automaticamente |
| Python `app/main.py` e `CycleStore` em `app/storage.py` (`begin_simulated_motion`, `check_simulated_claim`, `apply_simulated_response`) | Composição usa origem operacional UNAVAILABLE; transições positivas existentes são do caminho simulado, não prova física do par | Rever composição e guardas para o contrato físico homologado, sem reaproveitar sucesso simulado ou alterar regras econômicas |
| Testes `test_c_project_mapping.py`, `test_c_pwm_driver.py`, `test_c_controller_operational.py`, `test_c_controller_doorless.py` e harness `controller/tests/pwm_driver_test.c` | Casos atuais comprovam o contrato sequencial antigo ou primitivas por lado, não execução conjunta homologada | Cobrir etapas conjuntas, defasagem, falha em uma das saídas, permanência, parada, timeout e restart; manter os testes/semântica dos perfis históricos |

Os validadores numéricos de `ConfiguredHatch`/`HatchWiring`, `PhysicalDeclarations`
e do parser PWM C já aceitam os seis valores aprovados: não precisam mudar para
registrar esta calibração. `cycle_plan` é uma tupla de strings no Python; esse
tipo isoladamente não impõe sequência. A restrição sequencial efetiva está nos
campos Literal/parser e nos dois construtores de plano, cuja concordância é
exigida pelo adaptador.

Esse inventário histórico não autoriza execução física.
`CYCLE_LOWER_HATCH` e o IPC V1 existentes são reaproveitáveis; não se propõe outro
driver ou transporte. As escritas sysfs atuais são separadas por arquivo, e o
relato de movimento praticamente simultâneo não fornece uma garantia de
atomicidade nem um limite numérico de defasagem. A tolerância aceitável deverá
ser definida e medida na homologação, sem confundir sequência de chamadas de
baixo nível com abertura sequencial funcional de uma escotilha por vez.

## Journal e recuperação

Não houve alteração dos schemas/journals nesta atualização. O C físico mantém
schema v3, origem e snapshot JSON imutáveis; o Python mantém seu journal durável
e a recusa de origem PHYSICAL. Alterar canais, ligação pretendida, calibração ou
plano muda o snapshot: o mesmo ID não é reinterpretado com os novos bytes.
Replays no journal Python conservam o resultado retido; consultas diretas ao C
com o mesmo ID e outra configuração recebem ID_CONFLICT.

Timeout, perda de resposta, falha parcial e reinício continuam conservando
UNKNOWN/INDETERMINATE e bloqueios. Não se apagam journals para trocar mapa ou
supor posição. O perfil legado e as suas migrações não foram recalibrados.

## Confirmações exatas no Orange Pi

1. Chip/canais e motores correspondentes já foram confirmados pelo teste
   relatado: direita/chip 0/canal 3 e esquerda/chip 0/canal 4, pela frente.
   Documentar imagem/kernel/overlays e identificar eletricamente conector,
   pad/pinmux, RX/TX e eventuais conflitos UART/console. RX/TX não são deduzidos
   desse teste e o cabeamento deve permanecer como está.
2. Registrar as permissões e exclusividade dos canais na instalação do serviço.
   O movimento observado não homologa por si só a operação concorrente,
   recuperação ou persistência do controller.
3. Período/polaridade e os quatro pulsos já estão aprovados conforme a tabela.
   Vincular o registro formal de calibração na evolução de prontidão pertinente;
   isso não substitui os demais critérios de autorização física.
4. Preservar o cabeamento e a montagem aprovados; documentar alimentação,
   GND comum, níveis elétricos e carga. A permanência comandada de cinco segundos
   está definida; falta implementar/homologar sua execução, defasagem admissível
   dos comandos conjuntos, proteção contra obstrução,
   sustentação/torque e intervenção/parada segura, sem adotar ordem sequencial.
5. Especificar como o controlador verificará abertura, queda e retorno inicial
   em cada ciclo, inclusive ausência de evidência, e homologar a correlação por
   ciclo/ID. A observação humana relatada é evidência válida do teste de bancada,
   não uma entrada automática já disponível ao backend. Não foi afirmada
   existência de sensores; tempo ou escrita PWM não substituem essa verificação.
6. Integrar/homologar o provedor de evidências e o executor do plano antes de
   habilitar movimentos pelo backend; validar armazenamento, locks, falhas/restart
   e replay. Os testes reais já relatados não liberam automaticamente esse caminho.
   Preencher referências no JSON, sozinho, não satisfaz essas etapas.

## Validação deste registro de calibração/decisão — 10/11/2026

**77 testes focados existentes aprovados, zero falhas/skips, 16,98 s.** Foram
executados os mesmos quatro arquivos do comando abaixo, em container efêmero
da imagem de ferramentas já existente, sem rede/dispositivos, checkout readonly
e tmpfs temporário. As fixtures compilam os binários C usados nos testes.
Formatação do teste ajustado e `git diff --check` aprovados.

O teste existente do modelo agora verifica os seis valores aprovados e que
`open_order`/`close_order` continuam `null`. Os demais casos preservam a
concordância C/Python, bloqueio de despacho, IDs/snapshots, perfis históricos,
timeouts e estados indeterminados. Os casos sequenciais existentes continuam
passando porque esse contrato não foi alterado; não certificam a decisão de
movimento conjunto. Também permanece a recusa do valor não suportado
`simultaneous` pelos validadores atuais.

Nenhum executor/validador/runtime C/Python foi modificado. Além dos seis valores
do JSON, foram alteradas somente as expectativas do teste existente e a
documentação. Sem alteração de schema, journal operacional, ID, cabeamento,
frontend, IA, Supabase, Docker ou regras econômicas; sem commit, push ou deploy.

## Validação anterior do mapa sem hardware — 10/11/2026

**77 aprovados, zero falhas/skips, 32,67 s.** Foram executados somente os testes
focados abaixo, em container efêmero da imagem de ferramentas existente, sem
rede/dispositivos, com checkout readonly e tmpfs temporário. As fixtures C
compilam seus binários como parte dos testes; nenhum build/deploy operacional.

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_project_mapping.py tests/test_c_controller_doorless.py tests/test_c_controller_physical.py tests/test_c_controller_operational.py --tb=short
```

Verificam o mapa atual C/Python sem RX/TX/pulsos presumidos, bloqueio físico,
snapshot imutável mesmo após configuração divergente, idempotência, retenção,
perfis históricos e estados indeterminados. Não foi executado hardware nesta
correção; o teste real dos motores é o relato do responsável registrado acima.
Nenhum schema, journal operacional, ID ou cabeamento foi alterado.

## Validação anterior sem hardware — 09/11/2026

Testes compilam as variantes C e o teste unitário nativo do driver; verificam
convenção do modelo, ausência de pulsos/pinmux presumidos, concordância do plano,
diagnóstico, encaminhamento explícito do JSON, conflitos de snapshot e bloqueio
mesmo com plano declarado. Regressões focadas conservam a cobertura dos journals,
falhas e fluxo sem porta. Resultado final: **280 aprovados, zero falhas/skips,
22,67 s**, com as variantes C compiladas usando `-std=c11 -Wall -Wextra -Werror
-Wno-unused-function -lsqlite3`. Formatação Python e `git diff --check` aprovados.

Comando focado, da pasta backend, em container efêmero da imagem de ferramentas
existente, sem rede/dispositivos, com checkout readonly e tmpfs temporário:

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_project_mapping.py tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```

Sem alterações em frontend, IA, Supabase ou Docker; sem commit, push ou deploy.
