# Comunicação operacional Python ↔ C bloqueada — 07/11/2026

Mapeamento atualizado em 10/11, após os testes reais relatados no Orange Pi Zero 3:
[PROJECT_MAPPING.md](../controller/PROJECT_MAPPING.md). Olhando pela frente, o
JSON define direita em pwmchip0/canal 3 e esquerda em pwmchip0/canal 4. RX/TX
ficam desconhecidos (`null`), sem alteração do cabeamento. Python encaminha o JSON
explicitamente ao C e verifica o mapa/plano retornados. A dependência anterior
da variável herdada pelo filho não se aplica mais. Atuação permanece bloqueada.

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
conservam seus significados originais, sem preencher calibração ausente.

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
2. Confirmar período/polaridade e os quatro pulsos reais para as posições
   fornecidas. Não interpolar os pulsos nominais do legado.
3. Confirmar alimentação externa/GND comum e comportamento sob carga; homologar
   proteção, queda, parada, obstrução, falha parcial e recuperação após perda de
   energia/sinal ou posição desconhecida.
4. Definir e comprovar a evidência de conclusão do ciclo e retorno inicial.
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
