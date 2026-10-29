# Controller mecânico interno — Incrementos 1, 2 e integração simulada 3B

Atualização 3B: máquina única de `cycles.py` conectada ao journal apenas para
sessões com procedência simulada persistida. Contratos em
[LOCAL_API_V1.md](LOCAL_API_V1.md), execução em [SIMULATION.md](../deploy/SIMULATION.md).
Não há integração do frontend, hardware ou economia.

Incremento 3C.1: o [perfil DEV](../deploy/DEV_INTEGRATION.md) reutiliza exatamente
este fluxo/journal com SQLite próprio. Consulta e PIN centrais passam por broker
de capacidades sem registro. Identidade central não modifica procedência mecânica,
physical_confirmed ou elegibilidade econômica. Rotas operacionais não são montadas
nas fábricas com simulador. Não houve mudança do schema v3, estados ou retenção.

Histórico 3A: [ambiente Docker isolado](../deploy/SIMULATION.md) e harness
executável reutilizam estes contratos, adaptadores e journal. A fábrica de
simulação bloqueia clientes centrais/saída HTTP, exige armazenamento marcado
próprio e mantém PHYSICAL_BLOCKED/OFFLINE/false. Não houve mudança da máquina
de estados, do schema v2 ou integração mecânica ao frontend nesta etapa.

## Integração da sessão ao journal — Incremento 3B

Inspeção inicial: branch feature/orange-pi-integration, working tree limpa,
HEAD f3e1277, baseline 415 testes revalidada. Não foi encontrada decisão física
que autorize sinais reais. A proibição anterior de endpoints referia-se às
entregas 1/2/3A; o 3B autoriza somente as rotas da fábrica isolada.

`SimulationFlow` valida escopo, cria snapshots e decide ações lógicas de teste;
não implementa outra máquina. As transições permanecem em cycles.py.
MECHANICAL_STEPS liga cada operação ao estado anterior, estado de movimento e
estado após conclusão, acrescentando arestas à tabela TRANSITIONS existente.
CycleStore.change recusa escrever diretamente essas arestas: precisam do journal.
Não foram criados novos nomes de estado.

SQLite v3 acrescenta cycles.simulated, default 0, com trigger de imutabilidade.
É necessário distinguir sessão simulada desde SAFETY, antes do primeiro comando,
sem reaproveitar mode, central_scope, command_id ou failure_code como identidade.
Migração aditiva/transacional de v1/v2 conserva o restante das tabelas e dados;
não há downgrade automático. Runtime operacional recusa linhas simulated=1.
Sessões legadas não são promovidas silenciosamente ao fluxo novo.

O journal chama guardas do store dentro da mesma transação:

- request: valida pré-condição, origem e slot; grava comando/histórico, declaração
  hand_removed quando aplicável e estado de movimento num commit antes do despacho;
- claim: CAS + rechecagem do estado vinculado, sem I/O dentro da transação;
- observe: valida comando inteiro, origem, fase e versão; grava resposta e estado
  final juntos, com rollback conjunto se qualquer gravação falhar;
- recover: intenção não despachada é abortada/restaurada; possível despacho sem
  conclusão durável bloqueia journal e sessão na mesma transação, sem redisparo.

Aceitação não cria transição redundante da sessão. A conclusão do alçapão conserva
HATCH_IN_PROGRESS e registra seu resultado no journal; allowed_actions libera
somente confirm-initial. Essa confirmação é uma verificação lógica adicional do
estado inicial, não um segundo ciclo de queda. Seu sucesso simulado encerra a
sessão como COMPLETED, receipt=null, physical_confirmed=0. Nenhum registro central.

REVIEW é alcançado somente por review-fixture explícito após DOOR_CLOSED. É um
checkpoint de teste auditado como SIMULATION_REVIEW_FIXTURE, sem classificação,
categoria ou evidência de validade eletrônica. Não aprova o contrato de visão/
revisão real. Os controles visuais e taxonomia continuam pendentes para 3C.

Sem recuperação pública, limpeza ou TTL. A retenção futura precisa distinguir
terminais reconciliados de intenções pendentes, slots ativos e indeterminações,
preservando procedência, IDs, parâmetros imutáveis, FK, histórico e barreiras de
replay. Nenhum critério arbitrário de idade foi introduzido.

## Base do contrato interno — histórico dos Incrementos 1/2

Base implementada em 2026-10-27 na branch `feature/orange-pi-integration`;
integração simulada 3B atualizada em 2026-10-28, conforme seção anterior.
Contrato privado do backend; não é contrato HTTP, protocolo físico homologado
ou autorização de descarte. Nenhum sinal físico é emitido.

O Incremento 2 acrescenta o journal SQLite v2 e a coordenação privada descritos
ao final deste documento. O contrato dos adaptadores do Incremento 1 permanece
inalterado; suas tabelas em memória não substituem o journal.

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
`app.state`, lifespan e testes anyio existentes. O Incremento 1 não acrescentou
dependência, serviço, container, endpoint ou mecanismo SQLite. O Incremento 2
evolui somente o schema local e suas guardas de recuperação.

## Responsabilidades e arquivos

```text
FastAPI / lifespan
  app.state.mechanical: MechanicalService
    store.mechanical: MechanicalJournal (SQLite)
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
- `app/mechanical_journal.py`: identidade, histórico, CAS e recuperação duráveis.
- `app/services/mechanical.py`: persistência antes do despacho e acompanhamento
  assíncrono do resultado; caminho interno coordenado.
- `tests/test_mechanical_journal.py`: migração, falhas, concorrência e reinícios.

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

Nos adaptadores isolados, idempotência vale somente durante a vida da instância.
Reinício perde sua memória. No caminho coordenado do Incremento 2, o journal
preserva identidade e resultados entre instâncias. Isso ainda não garante
execução exatamente uma vez em hardware real.

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

# Dentro de contexto assíncrono com o lifespan ativo e um ciclo de teste
# já persistido em PHYSICAL_BLOCKED (não cria/libera sessão operacional):
# request = MechanicalCommand(event_id=event_id, operation="OPEN_INSERTION_DOOR")
# accepted = await application.state.mechanical.submit(request)
# final = await application.state.mechanical.wait(request.mechanical_command_id)
# assert accepted.phase == "ACCEPTED"
# assert final.source == "SIMULATED"
```

Para durações diferentes de zero sem esperar segundos reais, injetar
`sleep=clock.sleep`. `ManualClock` em `tests/test_controller.py` registra cada
espera e só libera sua Future quando `await clock.advance(seconds)` alcança
o prazo. Isso testa estado intermediário, limite exato, timeout e cancelamento
de forma determinística. O teste com duração zero exercita também o caminho
padrão `asyncio.sleep`. Sempre encerrar o adaptador com `await aclose()`;
o lifespan da aplicação assume essa responsabilidade para instâncias injetadas.

## Garantias e validação históricas do Incremento 1

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

## Diretrizes anteriores para o Incremento 2 (histórico)

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

## Incremento 2 — persistência e recuperação implementadas

Inspeção inicial: branch `feature/orange-pi-integration`, working tree limpa,
HEAD `387312a`, com o Incremento 1 já preservado. Revalidação anterior às
alterações: 310 testes aprovados. O modelo abaixo foi apresentado antes da
alteração do schema. Não foi encontrada divergência de decisão oficial que
exigisse mudar o fluxo físico ou econômico.

### Schema e compatibilidade

`CycleStore` cria banco novo em versão 2 e migra versão 1 de forma aditiva.
`cycles` e `transitions` conservam suas definições, identificadores, dados,
payloads e histórico. Não há migration Supabase ou dependência adicional.

DDL, validação estrutural/referencial e `PRAGMA user_version=2` executam na
mesma transação `BEGIN IMMEDIATE`. Não se usa `executescript`, que separaria
o commit da migração. Falha reverte DDL e versão; a recuperação só roda depois
da migração válida. Banco v2 incompleto, histórico divergente ou versão futura
são recusados, sem recriar silenciosamente tabelas que poderiam conter dados.
WAL, synchronous FULL, foreign_keys e a trava de instância continuam ativos.

| Estrutura | Conteúdo e finalidade |
| --- | --- |
| `mechanical_commands` | PK `mechanical_command_id`; FK `event_id`; operação, timeout e origem imutáveis; fase, resultado, erro, versão, instantes e reserva única `active_slot`. |
| `mechanical_history` | PK composta `(mechanical_command_id, version)`; fase, resultado, erro e instante de cada transição. Escrita somente por append. |
| `mechanical_by_event` | Índice para correlação e guardas por ciclo. |

Operação e timeout são a identidade paramétrica completa do contrato atual.
Não há cópia JSON do comando/resposta, hash duplicado ou novo identificador de
ciclo. A origem é definida por comando e não muda conforme a resposta recebida.
Assim, o histórico herda a origem pela FK, sem repeti-la em cada linha.
O estado atual no cabeçalho permite CAS, reserva única e consulta eficiente;
o histórico preserva os estados anteriores para auditoria. Não são dois eventos
lógicos independentes. Triggers impedem alterar identidade e editar/apagar o
histórico. Não existe rotina de expurgo nesta etapa.

Um runtime antigo que só conhece schema 1 recusará um banco migrado para 2.
Não há downgrade automático. Backup e reversão de implantação precisam levar
em conta a versão do volume; nenhum banco operacional foi migrado nesta tarefa.

### Ciclo de vida e coordenação

`app.state.mechanical` compõe `MechanicalService`, usando o mesmo `CycleStore`
e o adaptador do Incremento 1. `app.state.controller` permanece disponível para
compatibilidade e testes unitários do adaptador, mas não oferece durabilidade.
O caminho coordenado é obrigatório para a futura orquestração. Nenhum adaptador
físico existe ou foi autorizado: a coordenação recusa `source="PHYSICAL"`.
O schema suporta essa procedência para representar/auditar o domínio futuro;
os testes de recuperação usam somente respostas controladas, sem equipamento.

| Fase persistida | Semântica |
| --- | --- |
| `INTENT / PENDING` | Identidade, intenção e reserva gravadas; despacho ainda não reivindicado. |
| `DISPATCHING / PENDING` | Commit realizado antes de chamar o adaptador; atuação pode ter começado. |
| `ACCEPTED / PENDING` | Aceitação validada e persistida, separada da conclusão. |
| `COMPLETED / SUCCEEDED` | Conclusão declarada pelo adaptador; origem preservada. Não confirma queda real. |
| `REJECTED / UNAVAILABLE` | Recusa explícita antes de aceitação; reserva mecânica liberada. |
| `FAILED / FAILURE ou UNKNOWN` | Falha após despacho; reserva e bloqueio mantidos. |
| `TIMED_OUT / UNKNOWN` | Prazo esgotado sem evidência conclusiva; sem retry. |
| `CANCELLED / UNKNOWN` | Cancelamento lógico após aceitação; não prova ausência de movimento. |
| `INDETERMINATE / UNKNOWN` | Falha de despacho, inconsistência ou recuperação sem conclusão durável. |
| `ABORTED / UNAVAILABLE` | Intenção encerrada antes da reivindicação de despacho; nenhuma execução solicitada por esse caminho. |

`submit` grava intenção e reserva em transação curta, verificando que o ciclo
está ativo em `PHYSICAL_BLOCKED` e sem confirmação física. Em outra transação,
CAS reivindica `DISPATCHING`. Só depois do commit chama `controller.submit`.
Uma aceitação válida é persistida antes de retornar. Uma tarefa interna aguarda
`controller.wait` e persiste o resultado final, mesmo sem observador de UI.
Nunca há transação SQLite aberta durante `await`, temporização ou chamada ao
adaptador. Os métodos privados não fazem transições positivas do fluxo físico.

`get`, `wait` e `cancel` consultam/acompanham comandos existentes. Cancelar
somente a consulta `wait` não cancela a operação nem perde o acompanhamento.
`aclose` encerra o adaptador e aguarda/cancela despachos e observadores internos
antes do fechamento do store. Operação interrompida fica desconhecida; uma
conclusão que não foi persistida não é promovida a sucesso no encerramento.
Falha de SQLite é propagada, sem retorno fictício de sucesso: permanece a
última fase durável e sua reserva, a ser tratada pela recuperação.

### Concorrência e idempotência

- Mesmo ID e mesmo comando retornam o estado durável atual, sem novo despacho,
  inclusive após restart, mudança de adaptador ou recusa anterior.
- Mesmo ID com outro ciclo, operação ou timeout é conflito. A origem original
  permanece na consulta/replay, mesmo se o adaptador atual for indisponível.
- Reserva mecânica única no SQLite impede duas operações incompatíveis, mesmo
  por coordenadores concorrentes. Sem fila, expiração ou liberação por timeout.
- CAS usa versão e fase anteriores; cabeçalho e evento de histórico são gravados
  na mesma transação. Resultado idêntico duplicado não incrementa versão.
- Correlacionam-se ID, ciclo, operação, timeout e origem. Aceitação atrasada,
  conclusão anterior à aceitação e respostas de outro comando são recusadas.
  Divergência recebida pelo coordenador vira indeterminação; não vira sucesso.
- Replay de `INTENT` não reivindica despacho, mesmo no mesmo processo. Não há
  retomada automática de intenções. Identidades novas exigem decisão explícita.
- Cancelamento de sessão antes do claim aborta a intenção e libera suas reservas
  na mesma transação. Depois do claim, a guarda impede cancelar/liberar o ciclo.
  Essa corrida é serializada por `BEGIN IMMEDIATE` e rechecagem do estado.

A identidade durável impede duplicação local pelo mesmo ID. Um ID novo não é
deduplicado só por ter a mesma operação: reabrir a porta, por exemplo, pode ser
outra intenção legítima. O futuro protocolo físico também precisará tratar
idempotência e consultas por ID; SQLite não comprova execução única no hardware.

### Recuperação e bloqueios

Startup reconcilia journal e sessão na mesma transação, sem chamar controller,
Supabase ou temporizadores:

| Janela de falha | Resultado no startup |
| --- | --- |
| Intenção persistida, antes do claim | `ABORTED/UNAVAILABLE`; segue cancelamento pré-físico legado se não houver outra evidência de atuação. |
| Claim persistido, antes/durante envio | `INDETERMINATE/UNKNOWN`; sessão indeterminada e slot mantido. Mesmo sem aceitação, não se presume ausência de atuação. |
| Aceitação persistida ou falha durante movimento | `INDETERMINATE/UNKNOWN`; nenhum redisparo. |
| Conclusão recebida somente em memória | Mesma indeterminação; a evidência em memória foi perdida. |
| Timeout, falha ou cancelamento já persistidos | Preserva resultado/histórico; mantém bloqueio. |
| Conclusão simulada persistida | Preserva comando concluído e origem simulada; sessão continua `PHYSICAL_BLOCKED`, sem confirmação física ou registro. |
| Declaração física persistida | Preserva declaração, mas sessão permanece indeterminada: ainda não há contrato homologado de evidências físicas. |
| Recusa persistida sem aceitação | Preserva recusa; permite recuperação pré-física existente. |

Repetir startup não duplica eventos de recuperação. Estados indeterminados não
têm reconciliação manual pública, comando de manutenção ou retry mecânico.
Será necessário um contrato futuro de consulta/evidências e intervenção segura.

Sessões antigas sem journal mantêm sua recuperação anterior: preparação
pré-física é cancelada; registros centrais já elegíveis continuam recuperáveis
com o mesmo UUID/payload. Nenhum campo `physical_confirmed` é escrito pelo
journal. A guarda de registro recusa risco mecânico ou conclusão simulada,
mesmo diante de payload válido e flag física incorretamente preenchida por
código externo de teste. Os testes econômicos usam transportes controlados.

Não houve ligação com frontend, câmera, visão, estados físicos positivos ou
registro de descarte. `OFFLINE`, `can_start_deposit=false` e o controller
indisponível por padrão permanecem. O simulador não comprova funcionamento real.

### Verificação do Incremento 2

| Verificação executada nesta implementação | Resultado |
| --- | --- |
| Baseline antes das alterações: `uv run --locked pytest -q` | 310 aprovados, zero falhas/skips. |
| Suíte completa após implementação: `uv run --locked pytest -q` | 369 aprovados, zero falhas/skips; preserva 310 anteriores e acrescenta 59. |
| Runtime/deploy: `python -B -m unittest discover -s tests -p test_runtime.py -v` | 6 aprovados, zero skips. |
| API local JS: `node --test Hardware/TotemEdge/frontend/validation/local_api.test.cjs` | 7 aprovados, zero skips. |
| `uv format --check -- app tests` | 33 arquivos formatados. |
| `git diff --check` | Aprovado. |
| Build Docker local `linux/amd64`, tag `bingo-totem-edge:mechanical-increment-2` | Aprovado; sem alteração de Dockerfile ou lock. |
| Smoke na imagem sem rede, rootfs readonly, tmpfs de teste, UID 10001, capabilities removidas | Aprovado: import, migração 1→2, resultado simulado durável, replay com adaptador vazio sem despacho, restart indeterminado, OFFLINE/false e ausência de confirmação/registro econômico. |

Os testes novos verificam cada janela de restart, conflito de parâmetros,
respostas duplicadas/atrasadas/cruzadas, origem divergente, CAS, concorrência
entre threads/coordenadores, corrida de cancelamento versus claim, rollback
de cabeçalho/histórico/bloqueio, falha de commit após receber conclusão,
shutdown durante despacho/movimento e preservação de sessão central elegível.
Utilizam SQLite temporário, relógio manual e adaptadores/transportes controlados.
As execuções inicial e completa não tiveram falhas nos testes novos.

Não foram executados ARM64, pytest dentro da imagem, smoke de navegador ou
homologação no equipamento. Não houve rede externa em simulações, Supabase
real, mudança de frontend/câmera/visão/contratos centrais, commit, push, merge
ou deploy. Containers utilizados foram efêmeros de teste, sem volumes reais.
Os problemas preexistentes do verificador histórico e de `.env.example`, listados
na validação do Incremento 1, não foram corrigidos nem reexecutados nesta etapa.

Persistem limites de homologação: nenhum protocolo físico para reconciliar
posição/queda, ausência de garantia de execução única no dispositivo, dependência
da durabilidade real do meio de armazenamento e crescimento do histórico sem
política de expurgo. Operações desconhecidas exigem contrato futuro de evidências;
não existe caminho público para desbloqueá-las. Não se infere segurança física
a partir dos resultados do simulador ou de uma origem declarada como PHYSICAL.

### Recomendação específica para o Incremento 3

Criar uma composição de simulação explicitamente isolada do runtime operacional,
com sessões e SQLite de teste próprios e sem credenciais/transporte econômico
real. O frontend deve solicitar intenções ao orquestrador e renderizar snapshots
do backend; duração e conclusão continuam exclusivamente no backend. Nenhum
temporizador JavaScript deve fabricar `DOOR_OPEN`, `DOOR_CLOSED` ou sucesso.

Antes de criar rotas, definir o contrato local da simulação, identidade das ações
do usuário e transições permitidas. Associar cada avanço simulado ao comando
durável: aceitação representa movimento em andamento; conclusão simulada permite
somente o próximo estado no ambiente isolado. Reutilizar journal, IDs e CAS para
cliques repetidos e consultas após reload, sem reenviar movimentos pendentes.

Reservar o próximo comando e validar/CAS o estado do ciclo na mesma transação;
na conclusão, persistir resultado e avanço simulado atomicamente. Não afrouxar
as guardas operacionais deste incremento para facilitar a UI. Indeterminação
deve manter bloqueio e mostrar necessidade de recuperação sem botão que repita
o movimento. Recibo/pontuação demonstrativos exigem fonte isolada explícita.

Testar ponta a ponta abertura, inserção/declarar mão retirada, fechamento e
alçapão com relógio controlado; reload durante cada etapa; cliques concorrentes;
timeout/falha/cancelamento; restart; resposta atrasada; e ausência de qualquer
chamada a registro real. Integração com visão/revisão continua dependente dos
contratos próprios. Homologação física e liberação ONLINE serão etapas futuras.
