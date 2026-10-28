# Controller mecânico interno — Incremento 1

Implementado em 2026-10-27 na branch `feature/orange-pi-integration`.
Contrato privado do backend; não é contrato HTTP, protocolo físico homologado
ou autorização de descarte. Nenhum sinal físico é emitido.

## Inspeção e decisões

A working tree estava limpa; HEAD `dc3a468`, merge do PR #49. Foram inspecionados
STATUS técnico, contrato Totem/App/backend, fluxo oficial em
`Software/docs/descarte/FLUXO_ECOSSISTEMA_DESCARTE_V1.md`, operação offline,
contratos locais/visão, `cycles.py`, `sessions.py`, `storage.py`, lifespan,
rotas, testes e Docker/Compose. Não havia implementação em `controller/`.

O STATUS geral ainda descreve partes do Orange Pi como futuras. As entregas
locais posteriores e o código do PR #49 já documentam FastAPI, SQLite, sessões
e visão interna. As proibições anteriores de simular controller nos documentos
da fundação descreviam aquela entrega; este incremento autoriza somente o
simulador privado. Não foi encontrada decisão física que permita assumir
pinagem, driver, sensores, Arduino obrigatório ou protocolo de transporte.

Reaproveitados `Protocol`, modelos Pydantic, `asyncio`, fábrica `create_app`,
`app.state`, lifespan e testes anyio existentes. Nenhuma dependência, serviço,
container, endpoint, máquina de estados ou mecanismo SQLite novo.

## Responsabilidades e arquivos

```text
FastAPI / lifespan
  app.state.controller: MechanicalController
    UnavailableController (padrão)
    SimulatedController (injeção explícita development/test)
    futuro adaptador físico (aguarda journal e homologação)
```

- `app/mechanical.py`: comandos/respostas imutáveis, validação e `Protocol`.
- `app/services/controller.py`: adaptadores indisponível/simulado e ciclo de
  vida em memória compartilhado entre eles.
- `app/main.py`: composição e encerramento; nenhuma sessão recebe o controller.
- `tests/test_controller.py`: relógio manual e verificações de isolamento.

O código fica em `backend/app`, incluído pelo `COPY backend/app ./app` e pela
allowlist de `.dockerignore`. Não é preciso mudar Docker, paths Python ou
empacotar o diretório irmão `controller/`. Esse diretório permanece reservado
para a futura integração específica de hardware, caso necessária.

O orquestrador continuará decidindo transições, revisões, persistência e quando
solicitar uma operação. O controller não calcula pontos, não chama Supabase,
não lê/escreve SQLite, não confirma queda real nem altera sessões.

## Contrato interno

`MechanicalController` define:

| Método | Semântica |
| --- | --- |
| `await submit(command)` | Retorna aceitação ou recusa; não aguarda movimento. |
| `get(mechanical_command_id)` | Snapshot imutável mais recente, sem executar. |
| `await wait(mechanical_command_id)` | Aguarda término da operação já aceita. Cancelar a consulta não cancela a operação. |
| `await cancel(mechanical_command_id)` | Encerra a tarefa lógica e aguarda sua saída; resultado desconhecido após aceitação. Não especifica parada física segura. |
| `await aclose()` | Recusa comandos novos, cancela e aguarda tarefas; idempotente. |

`MechanicalCommand` contém `mechanical_command_id` UUID (gerado por default,
mas pode ser fornecido para replay), `event_id` UUID, `operation`,
`state=REQUESTED` e `timeout_seconds` finito positivo (default técnico 10s).
Tipos são estritos e campos extras são rejeitados. O `command_id` de início
da sessão não participa deste contrato. Um ciclo pode ter vários comandos
mecânicos com IDs distintos; não se gera outro `event_id` a cada movimento.

| Operação | Intenção lógica |
| --- | --- |
| `OPEN_INSERTION_DOOR` | Abrir porta de inserção; também pode ser solicitada pelo orquestrador para devolução. |
| `CLOSE_INSERTION_DOOR` | Fechar porta de inserção. |
| `CYCLE_LOWER_HATCH` | Ciclo inferior completo previsto no fluxo: abertura, intervalo de queda, fechamento e retorno. Sem submovimentos físicos implementados. |
| `CONFIRM_INITIAL_STATE` | Confirmar estado inicial esperado dos mecanismos. Não implica homing, movimento corretivo ou conhecimento de posições/sensores. |

A geometria do estado inicial e as evidências para cada operação serão
definidas com a equipe mecânica. O tempo decorrido não prova posição ou queda.

`MechanicalResponse` referencia o comando inteiro, preservando correlação e
parâmetros; inclui `state`, `result`, `source` e `error_code` normalizados:

| Estado da resposta | Resultado | Código |
| --- | --- | --- |
| `ACCEPTED` | `PENDING` | null |
| `COMPLETED` | `SUCCEEDED` | null |
| `REJECTED` | `UNAVAILABLE` | `CONTROLLER_UNAVAILABLE` ou `CONTROLLER_BUSY` |
| `FAILED` | `FAILURE` | `OPERATION_FAILED` |
| `FAILED` | `UNKNOWN` | `INCONSISTENT_RESPONSE` ou `EXECUTION_ERROR` |
| `TIMED_OUT` | `UNKNOWN` | `EXECUTION_TIMEOUT` |
| `CANCELLED` | `UNKNOWN` | `EXECUTION_CANCELLED` |

`REQUESTED` é a intenção no comando; `ACCEPTED` é aceitação pelo adaptador;
`COMPLETED` é seu resultado final. Nenhuma dessas palavras isoladamente é uma
confirmação física para registro econômico. `FAILURE` informa falha declarada,
sem afirmar ausência de movimento ou posição segura.

`source` é `UNAVAILABLE`, `SIMULATED` ou, futuramente, `PHYSICAL`.
Default conservador: `SIMULATED`. O adaptador indisponível só produz
`REJECTED/UNAVAILABLE`, nunca aceita nem conclui. O simulador produz
exclusivamente `SIMULATED`, inclusive em erros. Não existe campo/setter de
`physical_confirmed` nesse contrato. Uma marca `PHYSICAL` sozinha também não
substituirá evidências homologadas e persistidas pelo futuro orquestrador.

O modelo rejeita pares estado/resultado/código inconsistentes.
`checked_response` revalida a resposta terminal, inclusive instâncias criadas
sem validação, e confere comando inteiro e origem esperada. Resposta ausente,
divergente ou ainda pendente no lugar da conclusão vira
`FAILED/UNKNOWN/INCONSISTENT_RESPONSE`, preservando o comando solicitado.
O simulador usa essa verificação antes de publicar sua conclusão.

`ControllerError` representa recusa local antes de novo despacho ou erro de
consulta, com mensagem segura e códigos: `MECHANICAL_COMMAND_ID_CONFLICT`,
`MECHANICAL_COMMAND_NOT_FOUND`, `CONTROLLER_CLOSED`,
`COMMAND_CAPACITY_REACHED`. Não há tradução HTTP, pois não há rota mecânica.
Erros de construção de modelos/configuração usam `ValidationError/ValueError`.
Exceções brutas de execução não são expostas na resposta nem logadas.

## Temporização, idempotência e concorrência

O simulador exige `context="development"` ou `context="test"` na construção.
Não existe variável de ambiente, parâmetro HTTP, modo do frontend ou opção
Compose para selecioná-lo. A instância operacional exportada em `app.main:app`
continua usando `UnavailableController`. A fábrica opcional é código interno
confiável, não uma fronteira de segurança contra alteração do próprio Python.

`submit` retorna `ACCEPTED/PENDING` antes da espera. Uma tarefa `asyncio`
executa a duração configurada por operação com `asyncio.sleep`, liberando o
event loop. Não existe temporizador mecânico no JavaScript.

Defaults meramente ilustrativos: abrir 3s, fechar 3s, alçapão 4s, confirmar
estado inicial 1s. Nenhum é medição, especificação física ou prazo homologado.
`SimulationPlan` permite duração finita não negativa e resultado `SUCCEEDED`,
`FAILURE`, `UNAVAILABLE` ou `TIMEOUT` por tipo de operação.

- `UNAVAILABLE`: recusa imediata, sem tarefa ou aceitação.
- `FAILURE`: aceita, aguarda duração e informa falha controlada.
- `TIMEOUT`: aceita, aguarda `timeout_seconds` e informa resultado desconhecido.
- Duração maior ou igual ao timeout: resultado desconhecido no timeout. Em
  empate, prevalece a interpretação conservadora de timeout.
- Cancelamento: `CANCELLED/UNKNOWN`, mesmo imediatamente após aceitação.
- Shutdown: aguarda cancelamento, sem tarefas lógicas penduradas.

O timeout é simulado pela mesma espera injetável, limitada ao menor prazo
aplicável; não há tarefa concorrente de timer. A espera injetada deve respeitar
cancelamento e o tempo do relógio escolhido. O caminho padrão usa somente
`asyncio.sleep`; hooks arbitrários de teste não são drivers de hardware.

Uma instância aceita somente uma operação por vez, inclusive entre ciclos.
Não há fila. Concorrência retorna recusa estável `CONTROLLER_BUSY`. Mesmo ID e
mesmo comando retornam o snapshot atual, sem nova tarefa. Mesmo ID com ciclo,
operação ou timeout divergente é conflito. Uma recusa também é terminal para
aquele ID. Tentar outra operação exige decisão explícita do chamador; timeout
nunca provoca retry ou novo ID automático.

Registro em memória limitado a 1024 comandos por instância, configurável por
código; não há eviction que permita reutilizar IDs silenciosamente. Ao atingir
capacidade, comandos novos falham antes de despacho; replay permanece disponível.
Os métodos são destinados ao mesmo event loop do FastAPI, sem chamadas diretas
de outras threads. Para testes com `TestClient`, usar seu portal assíncrono.

Idempotência vale somente durante a vida da instância. Reinício perde comandos
simulados. Não há journal durável, recuperação mecânica ou promessa de execução
exatamente uma vez. Essa limitação impede usar esta base em hardware real.

## Uso interno e testes

```python
from app.main import create_app
from app.mechanical import MechanicalCommand
from app.services.controller import SimulatedController, SimulationPlan

# Fábrica executada no lifespan; nunca selecionada por browser/config de produção.
application = create_app(
    controller_factory=lambda: SimulatedController(
        context="test",
        plans={"OPEN_INSERTION_DOOR": SimulationPlan(duration_seconds=0.0)},
    )
)

# Dentro de contexto assíncrono com o lifespan ativo:
# request = MechanicalCommand(event_id=event_id, operation="OPEN_INSERTION_DOOR")
# accepted = await application.state.controller.submit(request)
# final = await application.state.controller.wait(request.mechanical_command_id)
# assert accepted.state == "ACCEPTED"
# assert final.source == "SIMULATED"
```

Para durações diferentes de zero sem esperar segundos reais, injetar
`sleep=clock.sleep`. `ManualClock` em `tests/test_controller.py` registra cada
espera e só libera sua Future quando `await clock.advance(seconds)` alcança
o prazo. Isso testa estado intermediário, limite exato, timeout e cancelamento
de forma determinística. O teste com duração zero exercita também o caminho
padrão `asyncio.sleep`. Sempre encerrar o adaptador com `await aclose()`;
o lifespan da aplicação assume essa responsabilidade para instâncias injetadas.

## Garantias preservadas e validação

Não mudaram SQLite/schema versão 1, estados/transições, slot único, UUID por
ciclo, `command_id` de sessão, contratos de visão, frontend, modo demonstração,
payload central ou clientes Supabase. Nenhum endpoint mecânico foi criado.
`PHYSICAL_BLOCKED`, `OFFLINE` e `can_start_deposit=false` permanecem ativos,
inclusive com central saudável e simulador injetado. Sucesso simulado não
produz confirmação física, payload, recibo ou pontos. A recuperação de
eventos existente permanece independente desta memória temporária.

Verificações executadas nesta implementação, sem usar resultados históricos
do PR #49 como substitutos:

| Verificação | Resultado |
| --- | --- |
| `uv run --locked pytest -q` | 310 aprovados, zero falhas/skips: 248 existentes + 62 novos. |
| Runtime/deploy: `python -B -m unittest discover -s tests -p test_runtime.py -v` | 6 aprovados, zero skips. |
| Frontend: `node --test Hardware/TotemEdge/frontend/validation/local_api.test.cjs` | 7 aprovados, zero skips. |
| `uv format --check -- app tests` | 30 arquivos formatados. |
| `git diff --check` | Aprovado. |
| `docker buildx build --check -f deploy/Dockerfile .` | Aprovado, sem avisos. |
| Build local `linux/amd64`, imagem `bingo-totem-edge:mechanical-increment-1` | Aprovado; mesmas dependências locked, sem mudança de Dockerfile. |
| Smoke na imagem, `--network none`, rootfs readonly, tmpfs temporário, UID 10001, sem capabilities | Aprovado: import dos novos módulos, lifespan, default indisponível, quatro operações simuladas, ausência de rota, OFFLINE/false, schema 1 e nenhum ciclo registrado. |
| Compose com `.env.example` original | Falhou: primeira linha preexistente começa com `g#`, inválido como nome de variável. Confirmado também em `git show HEAD:Hardware/TotemEdge/deploy/.env.example`. Arquivo preservado. |
| Compose com arquivo temporário vazio via `--env-file`, `config --quiet` | Aprovado; valida estrutura sem usar o exemplo inválido ou imprimir configuração/segredos. |
| `frontend/validation/verify_migration.py` histórico | Falhou ao procurar `frontend/camera_controller.js`, ausente também no HEAD. O script compara o protótipo atual, que tem arquivos adicionais, com a migração anterior. Frontend e verificador preservados. |

A primeira execução completa passou com 306 testes; a última acrescentou
cobertura das quatro operações no adaptador indisponível e de múltiplas
consultas concorrentes durante cancelamento, totalizando 310. Não houve falha
nos testes novos. O relógio manual não depende de esperas reais de 3–4s.

Não foram executados nesta tarefa pytest dentro da imagem, build ARM64, smoke
de navegador ou homologação no Orange Pi. O smoke da imagem é uma verificação
isolada de empacotamento/composição; não equivale à suíte completa no Linux.
O smoke Compose histórico não foi usado com seu exemplo de ambiente inválido.
Não houve acesso a hardware, inferência externa, Supabase real, migration,
commit, push, merge ou deploy. Os containers utilizados foram efêmeros de teste.

## Recomendação técnica para o Incremento 2

1. **Definir invariantes antes da migration local.** Journal mecânico separado
   de `cycles.command_id`, chave única `mechanical_command_id`, vínculo ao mesmo
   `event_id`, operação e parâmetros imutáveis, origem, estado, instantes,
   versão e resultado normalizado. Diferenciar intenção persistida, despacho
   possivelmente iniciado, aceitação e conclusão. Projetar retenção e consultas
   sem apagar evidência de pendências. Não migrar banco central para isso.
2. **Persistir intenção antes do possível efeito.** Na mesma transação curta
   que valida/CAS o ciclo e reserva sua operação, gravar comando completo e
   estado esperado. Commit antes de I/O; nunca manter transação SQLite aberta
   durante movimento ou espera. Só então permitir despacho pelo orquestrador.
   Persistir aceitação e conclusão em transações próprias com CAS e correlação.
3. **Tratar a janela entre commit e despacho explicitamente.** Crash durante
   envio ou antes de persistir resposta não prova que o movimento não ocorreu.
   Não redisparar pendências cegamente. Fazer reconciliação somente com consulta
   e evidências homologadas; sem evidência, manter resultado desconhecido,
   ciclo `INDETERMINATE` e slot bloqueado. Um journal local não garante sozinho
   execução única no dispositivo. Idempotência física dependerá do protocolo
   e da retenção de IDs pelo controlador homologado.
4. **Integrar transições de forma condicionada.** Aceitação pode representar
   movimento em andamento; somente conclusão física homologada e evidência
   persistida permitem estados finais. Nunca usar tempo decorrido ou origem
   declarada como evidência isolada. Simulações devem permanecer excluídas do
   caminho que define confirmação física e libera registro. Congelar payload
   antes da etapa irreversível conforme a infraestrutura existente.
5. **Formalizar confirmações com a mecânica.** Para cada operação, definir
   estado inicial/final, observações exigidas, significado de falha, timeouts,
   consulta por ID, cancelamento versus parada segura, perda de energia e
   intervenção autorizada. O ciclo inferior precisa evidenciar abertura,
   intervalo necessário, fechamento e retorno; não presumir sensor de queda,
   mão, GPIO, Arduino ou protocolo ainda não escolhido.
6. **Manter a autoridade econômica.** Após conclusão física persistida, usar
   o mesmo evento e payload imutável no fluxo de registro existente. Falha de
   rede pós-queda preserva pendência; retry econômico não repete movimento e
   não promete pontos antes do recibo central. Não liberar ONLINE até prontidão
   completa e homologação independente de mecânica, visão e segurança.
7. **Testar janelas de falha e reinício.** Cobrir crash antes/depois de cada
   commit/despacho/aceitação/conclusão, duas requisições concorrentes, resposta
   atrasada/duplicada/divergente, timeout, reinício com posição desconhecida,
   mudança de configuração/instância, corrupção de registro e operação já
   concluída sem resposta. Verificar preservação de IDs, payload, slot único e
   ausência de segundo despacho/segundo crédito. Começar com este simulador
   e SQLite temporário; hardware real vem depois do journal validado.

O adaptador físico futuro implementará o mesmo `MechanicalController`, recebendo
os mesmos comandos e devolvendo respostas normalizadas. A fábrica o comporá
internamente; frontend e contratos Supabase não precisam conhecer o driver.
Ele não deverá herdar `_MemoryController`: a durabilidade e a reconciliação
precisam existir antes de qualquer envio real. Novas evidências específicas
serão definidas no contrato do journal/hardware, sem inferi-las deste simulador.
