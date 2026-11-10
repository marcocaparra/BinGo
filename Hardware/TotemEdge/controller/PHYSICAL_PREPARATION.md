# Preparação C/Python para Orange Pi — 07/11/2026

Registro da primeira etapa. Para o estado atual da comunicação operacional
(receptor C que só recusa, configuração e composição Python), consultar
[OPERATIONAL_C_CONTROLLER.md](../backend/OPERATIONAL_C_CONTROLLER.md).
O bloqueio de movimentos e as pendências físicas deste relatório permanecem.

Execução física **bloqueada**. Foi preparada a leitura de evidências C → Python,
sem movimento, sensores inventados, confirmação fictícia ou novo simulador.
O diagnóstico descreve o repositório; não identifica a placa conectada nem valida
sua montagem. Não foi feito commit, push, deploy ou acionamento físico.

## Código anterior encontrado

O código anterior está no histórico do mesmo arquivo
`Hardware/TotemEdge/controller/bingo_controller.c`:

- `c96ef8c`: primeira versão, descrita como controle de quatro servos via PWM
  de hardware do Orange Pi Zero 3. O comentário chama os pulsos de **defaults
  nominais**, dependentes da geometria real.
- `dafc9ab0453d6320734349ba47caaa3b1694693e`, 02/11/2026:
  `fix(controller): update validated Orange Pi PWM controller`. É a versão
  identificada no histórico como validada, compatível com o relato de movimento
  real fornecido pelo operador. Não há transcrição de terminal, oscilograma ou
  registro de pinmux nesse commit que prove a correspondência RX/TX atual.

Inspeção reproduzível, da raiz do repositório:

```sh
git show c96ef8c:Hardware/TotemEdge/controller/bingo_controller.c
git show dafc9ab:Hardware/TotemEdge/controller/bingo_controller.c
git show --stat dafc9ab
```

A busca no checkout e no histórico dos arquivos de hardware encontrou esse
controlador como implementação anterior. Não apareceu outro script com mapa
RX/TX → SoC → PWM sysfs. Não foi deduzido um mapa a partir do nome PWM3/PWM4.

### Configuração comprovada no código antigo

| Aspecto | Implementação `dafc9ab` | Limite da evidência |
| --- | --- | --- |
| Interface | Escrita em `/sys/class/pwm/pwmchip0/pwmN/*` | Não há UART/serial nem envio por `/dev/tty*` |
| Canais | Porta esquerda 1, porta direita 2; escotilha esquerda 3, direita 4 | São índices sysfs usados no código, não números físicos do conector |
| Período | 20.000.000 ns, equivalente a 50 Hz | Precisa ser conferido na placa/imagem atual |
| Pulsos | 500.000 / 1.500.000 / 2.500.000 ns para referências nominais 0°/90°/180° | Não calibra os ângulos atuais 70°/175°/113°/5° |
| Escotilha esquerda | Fechada 1.500.000 ns, aberta 500.000 ns | Geometria anterior |
| Escotilha direita | Fechada 1.500.000 ns, aberta 2.500.000 ns | Geometria anterior |
| Inicialização | Exigia root, exportava canais, aguardava até 40 × 50 ms | Depois atuava nos quatro servos automaticamente |
| Configuração por canal | Desabilitar se ativo → duty 0 → period 20 ms → duty 1,5 ms → enable 1 | Essa sequência pode movimentar a montagem atual; não reutilizada como startup |
| Queda | Referência de seis segundos em relógio monotônico | Não há sensor de queda ou confirmação de posição |

O modo terminal implementado é `--teste`: o `main` primeiro chamava
`bingo_inicializar`, depois `executar_teste_automatico`, que fabricava eventos
de toque, área segura, classificação e confirmação. Sem argumentos o programa
também inicializava fisicamente e entrava no loop. Portanto o modo chamado
“teste” **movia motores reais**, embora simulasse as entradas de negócio.

`sudo ./bingo_controller --teste` é a forma de invocação reconstruída da API
do código e da exigência de root; o repositório não comprova o nome/local do
executável nem a linha exata digitada pelo operador. Não executar o binário
histórico na montagem atual: ele energiza quatro canais e usa posições antigas.

## Diferenças para o controlador e adaptador atuais

| Tema | Legado físico | Atual / decisão desta preparação |
| --- | --- | --- |
| Montagem | Quatro servos, com porta superior | Somente duas escotilhas; não reintroduzir porta |
| Lados | Sysfs 3/esquerda, 4/direita | Rótulos informados PWM3/direita, PWM4/esquerda; mapa Linux continua desconhecido |
| Posições | Referências nominais de 0°/90°/180° | Direita fechada 70°/aberta 175°; esquerda fechada 113°/aberta 5°; sem converter em pulsos |
| RX/TX | Não identificados no código antigo | Informação de cabeamento fornecida pelo operador, insuficiente para afirmar UART ou PWM/pinmux |
| Inicialização | Export/configuração e movimento automático | Inicialização, `--teste` e despacho físico permanecem recusados |
| Decisões | Loop C também simulava decisões de câmera e usuário | Backend conserva guardas de sessão, mão e revisão; C não decide negócio |
| Comunicação | Eventos por funções `bingo_evento_*` | IPC stdio V1 com correlação e journal, executável apenas com PWM simulado |
| Conclusão | Escrita PWM + tempo promoviam tela final | Isso não confirma movimento, posição, queda nem descarte físico |
| Reinício/replay | Sem retenção durável no legado | Journals C/Python, IDs imutáveis, sem redisparo e com bloqueio de incerteza mantidos |

## Alterações realizadas

- `bingo_physical.inc` centraliza os rótulos/ângulos conhecidos e emite
  `bingo-physical-preflight-v1`; canais e pulsos atuais são `null`. As referências
  de `dafc9ab` ficam em `legacy_evidence`, sem virar configuração ativa.
- `bingo_controller.c` reaproveita essas referências na sequência lógica já
  existente; o bloco PWM antigo é identificado como histórico incompatível com
  o cabeamento atual. Não se alteraram as sequências legadas ou seus resultados.
- `bingo_ipc.inc` aceita `--physical-preflight` sem journal, export, configuração,
  enable ou homing. O binário simulado recusa esse diagnóstico. Qualquer tentativa
  de despacho físico continua saindo 2 antes de abrir banco, agora com os códigos
  exatos de bloqueio. `--ipc-physical` não habilita um receptor.
- `CProcessController.physical_preflight` valida o JSON do C, limita resposta
  a 8 KiB e prazo padrão a dois segundos, limpa o processo ao falhar/cancelar e
  não cria um controller, reenviando zero comandos. Não aceita prontidão,
  confirmação ou origem física nesse relatório.
- `app.controller_cli` apresenta o diagnóstico; sai 2 mesmo se o relatório
  foi lido corretamente, pois a máquina permanece bloqueada. Não tem override.
- Testes focados e CMD da imagem exclusiva de testes incluem o novo caminho.

Reaproveitados: C existente, primitivas sysfs para referência técnica, IPC,
validação de respostas, coordenador e journals. Não foi habilitada a reutilização
dos índices/pulsos legados na montagem atual. O default `UnavailableController`
e a recusa de `source="PHYSICAL"` no `MechanicalService` permanecem; não há
mudança em frontend, economia, câmera, deploy ou schemas de journals.

## Compilar e ler o relatório sem hardware

Em Linux com compilador C e headers SQLite, da raiz do repositório:

```sh
cc -std=c11 -Wall -Wextra -Werror -Wno-unused-function Hardware/TotemEdge/controller/bingo_controller.c -lsqlite3 -o /tmp/bingo_controller_blocked
/tmp/bingo_controller_blocked --physical-preflight
cd Hardware/TotemEdge/backend
python -m app.controller_cli --executable /tmp/bingo_controller_blocked
```

O C retorna 0 apenas por ter emitido JSON com `ready=false`,
`physical_confirmed=false` e `source=UNAVAILABLE`. O CLI retorna 2 por bloqueio
físico. Nenhum comando acima exporta, configura ou energiza PWM. Esse relatório
continua bloqueado mesmo executado como root ou na placa correta.

## Verificações físicas pendentes no Orange Pi

1. **Identificação e pinmux (`PWM_MAPPING_UNVERIFIED`).** Confirmar modelo/revisão
   da placa, imagem/kernel e overlays em uso. Registrar qual RX e qual TX recebem
   o sinal de cada escotilha, incluindo conector e número físico. Relacionar cada
   fio ao pad/SoC, função alternativa e controlador/canal Linux comprovados.
   Conferir conflito com console serial/UART ou outro consumidor; não enviar
   bytes UART aos servos nem trocar pinmux por suposição.
2. **PWM e pulsos (`PULSE_CALIBRATION_UNVERIFIED`).** Recuperar a configuração
   efetivamente utilizada no terminal da placa e medir/conferir frequência,
   polaridade e pulsos. Registrar em nanossegundos cada uma das quatro posições
   informadas. Os três pulsos nominais antigos não autorizam interpolação. Não
   existe valor calibrado para preencher no código nesta entrega.
3. **Alimentação e segurança (`SAFETY_RECOVERY_UNVERIFIED`).** A fonte externa
   e GND comum são dados da montagem fornecidos pelo operador, não medidos aqui.
   Conferir fonte, tensões/níveis dos sinais e comportamento sob carga. Definir
   proteção contra mão/obstrução, ordem de abertura/fechamento, tempo de queda,
   parada/intervenção e reação a falha parcial, perda de sinal/energia, restart
   e posição desconhecida. Matar o processo C não é parada física segura.
4. **Conclusão (`MOTION_CONFIRMATION_UNDEFINED`).** Definir e homologar a
   evidência que permitirá confirmar ciclo e retorno inicial. Não foi afirmada
   existência de sensores. Escrita sysfs, `enable=1`, seis segundos ou declaração
   “Retirei a mão” não comprovam movimento/posição/queda; `CONFIRM_INITIAL_STATE`
   não deve virar um sucesso físico por ausência de erro.
5. **Integração (`PHYSICAL_DISPATCH_DISABLED`).** Depois das evidências acima,
   implementar/homologar o despacho físico e sua resposta terminal sob o
   `MechanicalService`, antes de alterar sua recusa PHYSICAL. Preservar aceite
   durável anterior a qualquer efeito, identidade contendo mapa/calibração
   versionados, exclusão mútua do dispositivo (inclusive entre journals distintos),
   consulta somente leitura, prazos, UNKNOWN/INDETERMINATE e ausência de replay
   após crash/timeout. Conferir fsync/armazenamento real. Não usar o sucesso
   simulado ou apagar journals para liberar movimento/crédito econômico.

Coleta inicial **somente leitura** na placa, sem presumir índices:

```sh
tr -d '\000' < /proc/device-tree/model
uname -a
cat /etc/os-release
ls -l /sys/class/pwm
for chip in /sys/class/pwm/pwmchip*; do
  [ -d "$chip" ] || continue
  echo "$chip"
  readlink -f "$chip/device"
  readlink -f "$chip/device/of_node"
  cat "$chip/npwm"
  for channel in "$chip"/pwm*; do
    [ -d "$channel" ] || continue
    echo "$channel"
    cat "$channel/period" "$channel/duty_cycle" "$channel/enable" "$channel/polarity"
  done
done
```

Esses dados não provam qual conector está ligado a cada motor. Complementar com
documentação/esquema da placa identificada, overlays e pinmux efetivos (se
disponível, leitura de `pinmux-pins` em debugfs), histórico de comandos local e
verificação elétrica dos fios RX/TX. Não executar export, unexport, escrita de
period/duty/enable, troca de overlays, `--teste` ou homing durante essa coleta.

## Validação executada sem hardware

Container efêmero da imagem de ferramentas existente `bingo-mechanical-ipc:test`,
checkout montado somente leitura, rede desativada, sem dispositivos/volumes
operacionais, capacidades removidas e tmpfs temporário executável:

```powershell
docker run --rm --network none --read-only --tmpfs /tmp:rw,exec,nosuid,nodev --cap-drop ALL --security-opt no-new-privileges --mount 'type=bind,source=C:\Projetos\BinGo,target=/repo,readonly' -w /repo/Hardware/TotemEdge/backend -e PYTHONDONTWRITEBYTECODE=1 bingo-mechanical-ipc:test python -m pytest -q -p no:cacheprovider tests/test_c_controller.py tests/test_c_controller_doorless.py tests/test_c_controller_physical.py tests/test_mechanical_journal.py tests/test_mechanical_boundary.py tests/test_controller.py tests/test_doorless_flow.py --tb=short
```

**199 aprovados, zero falhas/skips, 19,30 s.** As fixtures compilam as variantes
simulada e física bloqueada com `-Wall -Wextra -Werror` (somente funções legadas
não utilizadas são dispensadas). Inclui diagnóstico e CLI, ausência de alteração
em journal existente, recusa de prontidão/origem indevida e de despacho físico,
idempotência/conflitos, falhas parciais, timeout/perda de resposta/restart,
migração/retenção de IDs e os bloqueios do serviço/journal Python já existentes.
`uv format --check` nos três arquivos Python alterados/adicionados e
`git diff --check` também passaram.

Não foram testados Orange Pi/ARM64, pinmux, sinais elétricos, PWM real, carga
mecânica, sensores, durabilidade sob queda de energia nem integração econômica
real. O relatório de preparação não representa homologação física.
