# Base PWM física das duas escotilhas — 09/11/2026

Atualização física de 10/11: [PROJECT_MAPPING.md](PROJECT_MAPPING.md) registra,
olhando pela frente, direita/pwmchip0/canal 3 e esquerda/pwmchip0/canal 4,
conforme testes reais relatados no Orange Pi Zero 3. RX/TX ficam desconhecidos.
O plano das duas escotilhas e a comparação explícita do JSON C/Python permanecem.
O driver e os bloqueios físicos descritos abaixo são reutilizados.

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
2. Frequência/período/polaridade e quatro pulsos da geometria atual não medidos.
3. Critério/provedor de evidência de movimento e retorno inicial não definidos.
   Não foi presumido sensor nem adotado tempo de queda como prova.
4. Política segura de parada/torque/obstrução/recuperação ainda não homologada.
5. Política de ciclo autorizado e sua integração com evidências/journal ainda
   precisam ser implementadas após essas definições. Os permits internos são
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
