# Base PWM física das duas escotilhas — 09/11/2026

## Atualização de integração Python/IPC — 10/11/2026

O backend preparou o lifecycle PHYSICAL do mesmo executor, mantendo a composição
operacional bloqueada até homologação supervisionada. O driver/plano/PWM/calibração
abaixo não foram reimplementados ou alterados neste incremento. IPC V1 e journal
C v4 permanecem; GET passou a recusar snapshot diferente do carregado com
CONFIGURATION_CONFLICT, evitando atribuir um resultado antigo a outra configuração.
O receptor sem configuração continua permitindo inspeção histórica bloqueada.

Python persiste snapshot/intenção antes de SUBMIT, utiliza budget de 30 s (10 s
de esperas + 20 s técnicos) e consulta pelo restante do prazo. Sucesso é somente
operacional; sessão, sensores/physical_confirmed e economia não são confirmados.
EOF/SIGTERM no lifecycle físico inibem novas escritas pelo C; o adaptador não usa
SIGKILL nem presume que motores pararam. Recuperação usa GET explícito do mesmo
ID, sem redisparo e sem promover UNKNOWN. C conserva locks e política de falha.

O harness existente foi estendido apenas para testes de IPC com peers/sinais reais
e espera controlada no syscall, sem PWM real nem opções de fault injection no
executável de produção. Validação: **430 testes focados aprovados, zero falhas/skips,
34,15 s**, com compilação C. Contratos, arquivos e ligação futura do fluxo de tela:
[OPERATIONAL_C_CONTROLLER.md](../backend/OPERATIONAL_C_CONTROLLER.md).

## Vigente: executor C conjunto e conclusão operacional — 10/11/2026

Esta seção substitui os bloqueios de execução integral descritos nas etapas
históricas abaixo. O responsável aprovou conclusão **operacional** pela execução
integral sem erro detectado; sensores, posição medida e queda independente não
foram declarados. O backend continua sem despacho PHYSICAL e sem crédito econômico.

O mesmo `physical.cycle`/plano `joint-v1` recebe uma extensão explícita:

```json
"completion_policy": "operational-sequence-v1",
"initial_condition": "closed_pwm_readback",
"close_settle_ms": 5000
```

Esses três campos são um grupo obrigatório; não são uma flag de habilitação.
`hold_open_ms=5000`, marco `after_both_open_commands` e relógio `monotonic`
continuam obrigatórios. Ambos os tempos são inteiros estritos de 5000 ms nesta
versão. Ordens sequenciais continuam proibidas. Sem a extensão, o joint-v1 anterior
continua terminando em AWAIT_INITIAL_EVIDENCE e não executa. Sem `mode`, preserva-se
o plano sequencial/ausente anterior. Snapshots antigos nunca recebem essa política.

Plano operacional C/Python: **REQUIRE_CLOSED_PWM → OPEN_BOTH → HOLD_OPEN →
CLOSE_BOTH → SETTLE_CLOSED**. O executor C reutiliza o driver/syscalls e os locks
existentes; não encadeia duas chamadas `pwm_pose`, cuja inibição por resultado
desconhecido é preservada. O IPC aceita somente CYCLE_LOWER_HATCH neste modo.

1. Depois de COMMIT durável de PHYSICAL/ACCEPTED no journal, adquire ambos os
   locks globais. Abre somente canais **já exportados**; exige `enable=1`, período,
   polaridade e duty de fechamento iguais ao snapshot. Não exporta, habilita,
   reconfigura ou faz homing. Essa leitura comprova o comando PWM, **não a pose**.
2. Escreve os dois duties de abertura consecutivamente, sem espera de motor.
   sysfs não garante bordas elétricas simultâneas. Somente depois das duas
   escritas bem-sucedidas começa HOLD_OPEN de 5000 ms com CLOCK_MONOTONIC.
3. Escreve ambos os duties de fechamento no mesmo estágio e aguarda mais
   5000 ms monotônicos após ambas as escritas bem-sucedidas. Sucesso significa
   que a sequência operacional acabou sem falha detectada; não physical_confirmed.

Evidência informada pelo responsável em 10/11/2026: script presencial
`/tmp/bingo_teste_duas_escotilhas.sh`, Orange Pi Zero 3 montado, 3000 ms inicialmente
fechado, 5000 ms aberto, 5000 ms após fechamento conjunto. Alinhamento, abertura,
queda de objeto e retorno aprovados visualmente. Os **5000 ms após fechamento**
foram aprovados como duração operacional; não constituem tempo mínimo físico.
Os 3000 ms iniciais documentam o teste e não são uma espera implícita do executor.
O script foi relatado pelo responsável; não está sendo recuperado nem executado aqui.

### Admissão, journal e falhas

Configuração numérica válida, política completa e referências de mapa,
calibração, conclusão operacional e homologação do ciclo são exigidas. RX/TX,
pin/pad continuam desconhecidos e não são usados para derivar chip/canal.
`safety_recovery_reference=null` não autoriza desligamento ou recuperação.
O JSON exemplo registra as aprovações recebidas, sem instalar nada na placa.

O diagnóstico somente leitura mantém os campos antigos e acrescenta
`c_executor_configured`; esse campo não consulta hardware nem garante prontidão.
O handshake configurado é `V1 READY PHYSICAL DOORLESS_V1 OPERATIONAL_SEQUENCE_V1`;
sem a política/referências exigidas continua UNAVAILABLE/PHYSICAL_BLOCKED.
SUBMIT/GET e os campos V1 não mudaram. O timeout de comando precisa ser **maior
que 10 s** (as duas esperas mais I/O); 30 s é um orçamento para teste supervisionado,
não um tempo de movimento. O timeout é monotônico e abrange a sequência inteira.

Journal físico **v4**, mesma application_id e mesmas dez colunas: migração
transacional de v2/v3 preserva rowids, IDs, resultados, origem e snapshots exatos.
v4 permite COMPLETED/SUCCEEDED/PHYSICAL somente para CYCLE_LOWER_HATCH com
`completion_policy=operational-sequence-v1` no snapshot. Nunca promove registros
antigos; ACCEPTED após reinício vira FAILED/UNKNOWN antes de qualquer I/O.
Journal Python e journal/perfis de laboratório não migram neste incremento.

Falha de qualquer canal, escrita curta, erro de close, condição inicial divergente,
SIGINT/SIGTERM, timeout, erro de relógio ou desconexão detectada durante o ciclo
gera FAILED/UNKNOWN/EXECUTION_ERROR, inibe novas escritas e bloqueia novos IDs.
O laço verifica interrupção/prazo/perda de peer entre escritas e em esperas de até
20 ms. Syscalls sysfs dependem do kernel; isso não é garantia de parada em tempo real.
Não há fechamento corretivo nem desenergização automática: **o último PWM pode
continuar aplicado**. Interrupção não significa que o motor foi fisicamente parado.
Processo morto antes da atualização final deixa intenção ACCEPTED durável para
recuperação UNKNOWN. IDs repetidos retornam DUPLICATE; mudar o snapshot retorna
ID_CONFLICT; um novo ID para evento já executado também não repete o ciclo.
GET só lê. Perda da resposta pode deixar o chamador indeterminado, mesmo com um
resultado já durável no C: consultar o mesmo ID, jamais reenviar automaticamente.

### Primeiro ciclo supervisionado no Orange Pi

1. Compilar o C existente com SQLite/JSON disponível, sem BINGO_PWM_SIMULATED;
   conferir paths de executável/JSON/journal, permissões sysfs e locks globais.
   Manter banco e arquivo de configuração persistentes e separados do Python.
2. Conferir presencialmente direita=pwmchip0/pwm3, esquerda=pwmchip0/pwm4,
   período 20000000 ns, normal e os quatro pulsos aprovados. Preservar cabeamento;
   não usar RX/TX como prova elétrica. Verificar alinhamento/área livre e um meio
   presencial seguro de interromper a alimentação, pois não há recuperação automática.
3. Preparar pelas rotinas presenciais já aprovadas ambas fechadas e com PWM
   **habilitado**. Ler enable/period/polarity/duty_cycle dos dois canais; se não
   coincidirem, não tentar usar o executor para homing ou corrigir a montagem.
   Validar essa condição inicial de comando durante a homologação do executor.
4. Executar `--physical-config /caminho/absoluto/controller.json` (não move).
   Iniciar o mesmo binário numa sessão interativa mantendo stdin/stdout abertos:

   ```text
   binario --ipc-physical /caminho/absoluto/controller.sqlite3 --profile doorless-v1 --config /caminho/absoluto/controller.json
   V1 SUBMIT <uuid-comando> <uuid-evento> CYCLE_LOWER_HATCH 30
   V1 GET <uuid-comando>
   ```

   Usar UUIDs válidos minúsculos e o mesmo journal. Não usar pipe que feche stdin
   depois de SUBMIT. A aceitação é emitida antes do movimento; GET é atendido
   após a tentativa. Observar juntas a abertura, a permanência e o fechamento;
   conferir o resultado e o snapshot no journal. O ensaio físico do **executor C**
   ainda não foi realizado, embora o ciclo no script já tenha sido aprovado.
5. Se houver UNKNOWN ou perda de resposta, consultar/inspecionar o mesmo ID e
   parar o ensaio. Não criar outro ID, limpar banco ou reiniciar para contornar
   risco. Reconciliação, parada mecânica e recuperação continuam pendentes de
   política presencial homologada, sem mecanismo de desbloqueio automático.

Testes sem hardware: `test_c_joint_executor.py` usa o harness nativo existente,
com injeção de falhas e relógio nos syscalls de link. Confere intenção commitada
por um leitor SQLite independente antes de cada escrita. Não há outro driver,
simulador, raiz sysfs configurável ou opção de fault injection no binário real.

Validação final deste incremento: **376 testes aprovados, zero falhas/skips,
44,48 s**, compilando C11 com -Wall -Wextra -Werror. Inclui configuração inválida,
concordância C/Python, durações, condições iniciais divergentes, falha de apenas
um canal na abertura/fechamento, escrita curta/erro de close, interrupção em
HOLD_OPEN/SETTLE_CLOSED, timeout, erro de relógio, perda de peer, crash após intenção,
reinício, replay/ID_CONFLICT, evento repetido e migração histórica v2/v3.
Uma rodada anterior teve 375 aprovados e timeout no subprocesso da CLI Python
(10 s); esse caso passou isolado e na repetição integral, sem aumentar limites.
A imagem de testes já existente foi utilizada, sem alterar Docker ou acessar hardware.

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_joint_executor.py tests/test_c_joint_cycle.py tests/test_c_project_mapping.py tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```

Arquivos deste incremento, além das alterações anteriores já presentes na branch:

- C/configuração: `controller/bingo_pwm.inc`, `bingo_ipc.inc`,
  `operational.example.json` e `tests/pwm_driver_test.c`.
- Python: `backend/app/services/controller_config.py` e `c_controller.py`.
- Testes backend: `test_c_joint_executor.py`, `test_c_joint_cycle.py`,
  `test_c_project_mapping.py` e `test_c_pwm_driver.py`.
- Contratos: este documento, `controller/PROJECT_MAPPING.md`, `README.md`,
  `backend/OPERATIONAL_C_CONTROLLER.md`, `MECHANICAL_INTERNAL_V1.md` e
  `Software/docs/STATUS_12-08.md`.

## Histórico: preparação do plano e das primitivas

Plano conjunto implementado em 10/11: `joint-v1` usa estágios OPEN_BOTH e
CLOSE_BOTH, com HOLD_OPEN de 5.000 ms monotônicos após os dois comandos de
abertura. C e Python concordam em etapas e parâmetros temporais; o modo ausente
preserva o plano antigo. Apenas contrato/plano/diagnóstico evoluíram: as primitivas
PWM, locks, journal físico v3 e bloqueios de execução foram preservados. O
driver não executa o novo plano até haver confirmação/parada/recuperação homologadas.
Detalhes: [PROJECT_MAPPING.md](PROJECT_MAPPING.md).

Atualização física de 10/11: [PROJECT_MAPPING.md](PROJECT_MAPPING.md) registra,
olhando pela frente, direita/pwmchip0/canal 3 e esquerda/pwmchip0/canal 4,
conforme testes reais relatados no Orange Pi Zero 3. RX/TX ficam desconhecidos.
O plano das duas escotilhas e a comparação explícita do JSON C/Python permanecem.
O driver e os bloqueios físicos descritos abaixo são reutilizados.

Registro adicional de 10/11: calibração física aprovada (direita fechada/aberta
1.750.000/600.000 ns; esquerda 1.350.000/2.300.000 ns; período 20.000.000 ns,
polaridade normal). Foram relatados fechamento alinhado, abertura adequada,
ciclo conjunto e queda de objeto. A decisão final é abrir e fechar ambas
praticamente simultaneamente. O plano novo representa essa decisão; as primitivas
por lado ainda não constituem um executor de par. Ordens sequenciais ficam `null`
no modo conjunto e conservam somente o significado histórico no modo ausente.
Evidência e inventário preciso das evoluções C/Python pendentes estão em
[PROJECT_MAPPING.md](PROJECT_MAPPING.md). Não foi liberada atuação.

O STATUS técnico vigente e os contratos mecânicos mantêm atuação e confirmação
físicas bloqueadas. Esta etapa implementa a base C de I/O, comandos internos por
lado/posição e contenção de resultados desconhecidos. **Não implementa uma
homologação, sensor ou política de ciclo ainda inexistentes.** O receptor V1 de
produção continua recusando todos os movimentos; não há flag para habilitá-los.

## Implementação

`bingo_pwm.inc` é incluído no controlador existente, somente no build físico.
Reaproveita a sequência sysfs e a disciplina de escrita de `dafc9ab`; não chama
suas funções de quatro motores nem recupera porta superior. Os únicos lados
do driver são RIGHT/LEFT, com poses OPEN/CLOSED. Não há conversão de graus,
pulso neutro, canal Linux, período ou polaridade predefinidos.

### Configuração no C

É o mesmo JSON `bingo-c-controller-v1` de
[operational.example.json](operational.example.json), inclusive campos
`physical.right/left.pwm_chip`, `pwm_channel`, `closed_pulse_ns`, `open_pulse_ns`,
`period_ns`, `polarity`, conector/pad e referências de evidência.

O C lê o caminho de `BINGO_C_CONTROLLER_CONFIG`, já utilizado no lifespan Python,
ou recebe explicitamente `--config /caminho/absoluto/controller.json` no receptor:

```text
binario --ipc-physical /caminho/absoluto/controller.sqlite3 --profile doorless-v1 --config /caminho/absoluto/controller.json
```

O argumento é opcional para manter a comunicação bloqueada anterior. Se estiver
presente, JSON inválido ou `journal` diferente do argumento é recusado **antes**
da criação do banco/lock. O JSON é carregado uma vez; não há reload durante uma
ordem. A chamada programática Python `open_operational` não foi modificada:
fora do lifespan, usar a variável existente para que o filho também leia o JSON.

Validação C: arquivo regular absoluto até 16 KiB; schema e perfil exatos;
caminhos absolutos de executável/journal; campos conhecidos sem duplicação;
tipos estritos; chip/canal inteiros não negativos dentro do intervalo suportado;
período positivo; pulsos positivos e menores que o período; polaridade
`normal`/`inversed`; saídas Linux distintas. Booleanos como números, floats
para parâmetros inteiros, arrays, strings vazias/de controle/NUL, flags extras
de habilitação e configuração ambígua são recusados. Campos físicos ausentes ou
`null` deixam configuração incompleta, sem defaults. JSON usa funções do SQLite
já vinculado ao controlador; ausência desse suporte na placa falha fechada.

Diagnóstico C **somente leitura**, sem journal/PWM:

```sh
/caminho/binario --physical-config /caminho/absoluto/controller.json
```

Informa `INCOMPLETE` ou `DECLARED` e sempre `execution_ready=false`,
`completion_provider=false`, `stop_policy=false`. DECLARED significa apenas
dados preenchidos. Referências em texto não concedem um permit de atuação.
O `--physical-preflight` anterior continua com seu contrato original.

### Primitivas físicas e erros

- Lock global por par chip/canal em `/run/lock/bingo-pwmchipN-pwmM.lock`, em
  ordem estável, antes de qualquer acesso ao PWM. Protege canais coincidentes
  entre processos com journals distintos, quando todos usam o driver. Não
  impede outro usuário de escrever diretamente em sysfs.
- Abre o chip sob o caminho fixo `/sys/class/pwm/pwmchipN`, verifica `npwm` e
  exporta somente o canal configurado se necessário. A espera limitada pela
  criação do diretório é prontidão de sysfs, não confirmação de movimento.
- Recusa canal já habilitado: não toma uma saída ativa de outro processo nem
  remove seu torque automaticamente. Não muda pinmux, overlays ou UART.
- Com saída verificada como desabilitada, escreve duty 0 → período → polaridade
  → pulso da pose selecionada → enable 1. Não passa por 90°/1,5 ms. Arquivos
  dentro do chip/canal são abertos sem seguir symlinks arbitrários.
- Falhas de abertura, leitura, escrita curta, escrita negativa e fechamento
  interrompem a sequência. Escrita incerta não é repetida e não ocorre
  fechamento corretivo. A incerteza é marcada antes da primeira escrita de saída.
- Até uma sequência integralmente escrita retorna `PWM_UNKNOWN`; inibe novas
  poses. Não existe ramo de sucesso por sleep, relógio, PWM ou ausência de erro.

`pwm_pose` é uma primitiva interna por lado/pose. `ipc_pwm_pose` acrescenta a
barreira do journal: exige intenção PHYSICAL/ACCEPTED de CYCLE_LOWER_HATCH já
commitada, mesmo ID/perfil/snapshot de configuração e nenhuma transação aberta.
Ao terminar a tentativa, tenta a contenção autorizada e persiste
FAILED/UNKNOWN/EXECUTION_ERROR, sem caminho para COMPLETED. Não existe caller
de produção para esse bloco enquanto a política física não for homologada.
Não foram acrescentados opcodes ao Python nem CLI manual que contorne o journal.

### Parada e sinais

SIGINT/SIGTERM apenas marcam um flag no handler; não fazem SQLite/sysfs dentro
do sinal. O loop deixa de receber ordens, as primitivas verificam interrupção
entre escritas e o encerramento aplica contenção quando pertinente.

`pwm_stop` sempre inibe novas poses. Desabilitar PWM só é tentado se a política
de desenergização tiver sido homologada no contexto interno; essa autorização
é **falsa em produção**. Sem ela, mantém o estado indeterminado e não solta
torque por suposição. Quando autorizada, a rotina tenta disable em **todas** as
saídas tocadas, mesmo se uma falhar. Sucesso de disable não confirma posição,
queda ou parada mecânica segura. Não há homing, fechamento corretivo ou unexport.
Fechar descritores/matar processo não desliga automaticamente PWM no kernel;
SIGKILL/perda de energia não são resolvidos por um handler de software.

### Journal físico v3 e compatibilidade

O banco físico mantém `application_id=1112098640`. Migração transacional v2→v3
preserva rowids, IDs, evento, operação, timeout, perfil e recusas; acrescenta
`source` e snapshot JSON imutáveis. Recusas anteriores recebem UNAVAILABLE e
snapshot vazio. O banco simulado e sua migração histórica permanecem separados.

O schema físico permite recusas e intenções/UNKNOWN PHYSICAL, mas **não permite
COMPLETED/SUCCEEDED**. Aceite pendente encontrado no restart vira
FAILED/UNKNOWN/EXECUTION_ERROR sem atuar. Esse risco retido faz novos IDs serem
recusados com CONTROLLER_BUSY; GET não desbloqueia nem redispara. Não se apagam
IDs para recuperar posição. Alterar os bytes da configuração no replay do mesmo
ID é conflito: não se reinterpretam ordens com outro mapa/calibração.

O handshake continua UNAVAILABLE/PHYSICAL_BLOCKED. Uma consulta de histórico
PHYSICAL/UNKNOWN não pode ser tratada pelo Python como resposta UNAVAILABLE ou
elegibilidade física: o adaptador existente falha fechado e seu journal conserva
a incerteza. Nada foi alterado na composição Python, frontend, IA ou economia.

## O que impede a ativação

1. Chip/canais dos dois motores já foram comprovados nos testes relatados:
   chip 0, direita/3 e esquerda/4 pela frente. Falta identificação elétrica
   específica de RX/TX, conector/pad/pinmux; não alterar o cabeamento.
2. Período, polaridade e quatro pulsos já foram aprovados na montagem real e
   registrados no JSON. Isso não homologa o executor conjunto, permanência
   aberta ou critérios automáticos de conclusão; referências formais do modelo
   permanecem sem preenchimento neste incremento.
3. Critério/provedor de evidência de movimento e retorno inicial não definidos.
   Não foi presumido sensor nem adotado tempo de queda como prova.
4. Política segura de parada/torque/obstrução/recuperação ainda não homologada.
5. O ciclo final aprovado é conjunto e seu plano já representa cinco segundos
   de permanência comandada. Faltam executor e integração com evidências/journal,
   implementação da contagem e política de parada/recuperação. Os permits internos são
   falsos, não preenchíveis pelo JSON, e não há caller físico de produção.

Portanto não há comando de produção capaz de testar motores energizados nesta
versão. Isso é um bloqueio explícito, não uma promessa de ativação pelo JSON.

## Roteiro mínimo de bancada, por motor

1. **Agora, sem energizar motores:** identificar placa/imagem/kernel; conferir
   RX/TX de cada lado, pinmux/console serial e correspondência sysfs. Recuperar
   valores efetivamente usados e preencher somente dados medidos. Preservar
   arquivos/journals existentes. Compilar o C e executar `--physical-config` e
   `--physical-preflight`; ambos devem continuar indicando bloqueio.
2. **Antes de habilitar qualquer teste:** definir como serão comprovadas poses,
   proteção de pessoas/obstrução, sustentação da escotilha, corte/intervenção
   externa e política de torque ao parar. Homologar esses critérios e instalar
   a política/provedor correspondente no executor C e contrato de prontidão.
   Não editar permits, criar um bypass de CLI ou enviar writes avulsos a sysfs
   para contornar o bloqueio atual.
3. **Direita isolada, somente após a etapa 2:** deixar a esquerda sem alimentação
   e mecanicamente sustentada; conferir fonte externa/GND comum, pinagem e sinal
   com instrumentação antes de ligar o servo. Executar uma única pose autorizada
   com ID próprio e journal durável; conferir pulso/pose fisicamente para as
   referências fechada 70° e aberta 175°, uma tentativa por vez. Não usar valores
   nominais legados como calibração. Validar a parada autorizada e reter UNKNOWN
   quando a evidência não chegar.
4. **Esquerda isolada:** repetir o procedimento com a direita sem alimentação,
   usando somente o mapa/pulsos medidos para fechada 113° e aberta 5°.
5. **Ambas, depois dos testes individuais:** homologar ordem/coordenação e
   critério de queda/retorno, falha parcial, obstrução, timeout, perda de
   comunicação/energia e exclusão entre processos/journals. Repetir o mesmo ID
   deve consultar o resultado, sem repetir movimento. Ensaios de falha exigem
   sustentação e intervenção externa; não reiniciar para supor posição inicial.

As etapas energizadas são condicionais à homologação e ao executor de evidência
ainda pendentes; não foram executadas nesta entrega.

## Validação sem hardware

Testes nativos `controller/tests/pwm_driver_test.c` usam substituição de syscalls
na linkedição para verificar caminhos, ordem e falhas. Não há árvore sysfs falsa,
modelo de servo, novo simulador ou raiz de I/O configurável em produção. Permits
são ajustados somente no processo unitário para cobrir primitivas inacessíveis
no entrypoint de produção. Os demais testes usam o binário C real e SQLite
temporário para configuração, migração, retenção, restart, sinais e IPC bloqueado.

Compilação com `-std=c11 -Wall -Wextra -Werror -Wno-unused-function -lsqlite3`.
A imagem de ferramentas existente foi usada em container efêmero sem rede,
dispositivos ou volumes operacionais, checkout readonly e tmpfs temporário.
Sem alteração de Docker, commit, push ou deploy. Resultado final: **270 aprovados,
zero falhas/skips, 18,75 s**. Formatação Python e `git diff --check` aprovados.
Não há evidência de Orange Pi/ARM64, sysfs real, servos ou segurança mecânica por
estes testes.

Suíte focada executada da pasta backend, na imagem de ferramentas já existente:

```sh
python -m pytest -q -p no:cacheprovider tests/test_c_pwm_driver.py tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_operational.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```
