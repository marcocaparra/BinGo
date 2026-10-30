# Contratos locais — fundação de sessão V1

Atualização 3C.1: as rotas operacionais deste documento são montadas somente na
fábrica operacional. As fábricas isolada e DEV não as montam (404), impedindo que
sessões simulated=1 sejam projetadas/mutadas por contratos sem procedência.
O [perfil de integração DEV](../deploy/DEV_INTEGRATION.md) acrescenta somente
GET /local/dev/health, GET /local/dev/context e POST /local/dev/student-pin,
além das rotas simuladas 3B existentes. Esses caminhos não existem nos outros
dois runtimes. PIN usa o contrato central existente class_id/student_id/pin.
A consulta stateless student-pin não autentica uma sessão mecânica. O 3C.1.1
acrescenta a associação durável descrita abaixo. Nenhuma rota DEV registra descarte.

Esta especificação precede as novas rotas desta entrega. `/health` e
`/local/status` mantêm seus contratos existentes. As demais operações abaixo
são contratos **locais novos desta implementação**, derivados do fluxo aprovado
nesta tarefa; não são contratos Supabase nem endpoints históricos oficiais.
Não dependem de nova regra econômica. Revisar antes da habilitação física.

O frontend é servido pelo FastAPI na mesma origem, em `/`. Demonstração
explícita em `/?runtime=demo` não chama a API de negócio. Não há CORS aberto.
Chamadas de escrita usam JSON e `X-Totem-Request: 1`; Origin, quando presente,
deve coincidir com a origem local. Hosts locais aceitos: localhost e loopback.
PIN nunca aparece em query, erro de validação, resposta, log ou SQLite.

| Método/caminho | Request | Response / validação |
| --- | --- | --- |
| GET `/local/context` | Sem body/query | Contexto público projetado de `totem-context-v1`. Exige disponibilidade operacional; retorna 503 enquanto hardware/visão não estão verificados. |
| GET `/local/sessions/active` | Sem body/query | `{session: null}` ou snapshot da única sessão ativa. Permite consultar recuperação mesmo offline. |
| POST `/local/sessions` | `{command_id: UUID, mode: student ou class_only, class_id: UUID}` | Snapshot com UUID event_id gerado pelo backend. Só inicia com prontidão completa. Valida turma no contexto oficial. Mesmo command_id e mesmos dados reapresentam a sessão; dados diferentes geram 409. |
| GET `/local/sessions/{event_id}` | UUID no path | Snapshot persistido, sem imagem/PIN/payload remoto bruto. |
| POST `/local/sessions/{event_id}/pin` | `{student_id: UUID, pin: quatro dígitos ASCII}` | Confirmação de identidade vinculada à sessão pela Function existente; avanço para SAFETY. Só em IDENTIFYING e com disponibilidade. PIN errado: 401; mantém identificação pendente. |
| POST `/local/sessions/{event_id}/safety` | `{has_risk: boolean}` | SAFETY → CANCELLED em risco ou PHYSICAL_BLOCKED em declaração segura. Nenhum movimento é emitido nesta etapa. Comando repetido/estado incorreto: 409. |
| POST `/local/sessions/{event_id}/hand-removed` | `{}` | Só aceita declaração em DOOR_OPEN; registra declaração, mas responde 503 PHYSICAL_INTEGRATION_REQUIRED sem solicitar movimento. Não implementa sensor de mão. |
| POST `/local/sessions/{event_id}/cancel` | `{}` | Cancelamento somente antes de qualquer etapa física. Repetir cancelamento terminal é idempotente. Não cancela pendência pós-queda ou estado indeterminado. |
| POST `/local/sessions/{event_id}/retry-registration` | `{}` | Só reenvia payload persistido com confirmação física já armazenada, em REGISTRATION_PENDING. Não recebe dados de evento do browser. Mesmo UUID e payload; confirmação local já persistida retorna o mesmo resultado sem nova chamada. |
| POST `/local/sessions/{event_id}/finish` | `{}` | Só encerra após REGISTERED; COMPLETED repetido retorna mesma sessão. Não apaga histórico/recibo e não credita pontos. |

Snapshot: `event_id`, `state`, `mode`, `class_id`, `student_id`, `class_name`,
`student_name`, `failure_code`, `hand_removed`, `receipt` (null até confirmação
central), `updated_at`. Recibo é a projeção tipada do contrato central, sem
economia calculada localmente. Não representa prontidão para próximo ciclo.

Erros seguros: `{error: {code, message}}`. 422 para contrato local inválido;
404 para sessão inexistente; 409 para sequência/concorrência/conflito; 503 para
indisponibilidade ou integração ausente; 401 para PIN recusado; 502 para resposta
central inesperada. Todos os endpoints locais usam `Cache-Control: no-store`.
Detalhes de validação não incluem valores de entrada. Campos extras são recusados.
Não existem retries automáticos, polling, expiração de sessão ou sincronizador.

Apenas um slot SQLite ativo impede ciclos concorrentes. A persistência usa
transações e comparação do estado anterior para rejeitar comandos em corrida.
Cancelamentos são seguros só nos estados pré-físicos desta entrega. Perda de
resposta ao início recupera a mesma sessão por command_id ou consulta de ativa.
Após erro de PIN pode-se tentar novamente; repetição depois da confirmação não
reautentica nem avança o ciclo. Retry de registro não repete etapa física.

## Partes bloqueadas / propostas pendentes

Atualização de 2026-10-27: [visão interna e propostas](VISION_INTERNAL_V1.md)
documenta o serviço privado disponível no processo FastAPI. Não acrescenta rotas
nem aprova os contratos de classificação/correção/auditoria abaixo.

No runtime operacional continuam ausentes rotas de movimento, escotilha,
confirmação física, preview, captura, classificação, correção e reconciliação.
O Incremento 3B autoriza somente os contratos isolados de simulação abaixo.
O [Incremento 1 mecânico](MECHANICAL_INTERNAL_V1.md) acrescenta contrato e
simulador privados no backend, com controller indisponível por padrão. Substitui
a exclusão de simulador que valia na entrega da fundação; não liga operações
à sessão, aos estados físicos ou ao registro econômico.
Não há caminho no processo atual para produzir confirmação física ou ONLINE.

O Incremento 2 acrescenta journal mecânico durável e coordenação privada, sem
alterar as rotas acima. Cancelamento pré-físico só libera sessão se o journal
comprovar ausência de possível despacho; após claim/aceitação, mantém bloqueio.
Startup não cancela como preparação um ciclo com risco mecânico: recupera como
`INDETERMINATE`. Conclusão simulada persistida mantém `PHYSICAL_BLOCKED`.
O schema local migra de 1 para 2; registros centrais antigos já elegíveis
preservam a recuperação existente. Não existe reconciliação manual pública.

## Contratos locais de simulação — Incremento 3B

Montados **somente** por `app.simulation:create_simulation_app`, em SQLite marcado
exclusivo, com central bloqueada. Não existem em `app.main:app` operacional.
Mesmas verificações Host/Origin, JSON, `X-Totem-Request: 1`, ausência de query,
campos extras proibidos e Cache-Control no-store. Não há CORS amplo ou autenticação
central fictícia. O encaminhador TCP não altera Host/Origin.

Prefixo `S = /local/simulation/sessions`. UUIDs são validados e retornados na
forma canônica hifenizada, seguindo os modelos existentes.

| Método/caminho | Entrada | Resultado |
| --- | --- | --- |
| POST `S` | `{command_id: UUID}` | Cria sessão class_only com turma fixture local, em SAFETY, `simulated=1`. Mesmo command_id retorna a mesma sessão, inclusive terminal. Não autentica aluno nem consulta contexto real. |
| GET `S/active` | Sem body/query | `{snapshot: null}` ou snapshot da única sessão ativa de simulação. Sessão legada 3A ativa retorna 409, sem adoção/limpeza automática. |
| GET `S/{event_id}` | Sem body/query | Snapshot persistido, inclusive após encerramento/restart. |
| POST `S/{event_id}/safety` | `{has_risk: boolean estrito}` | Risco cancela; caso seguro vai a PHYSICAL_BLOCKED. Repetição idêntica consulta estado atual; decisão divergente retorna 409. |
| POST `S/{event_id}/open` | Comando mecânico abaixo | PHYSICAL_BLOCKED → OPENING → DOOR_OPEN. |
| POST `S/{event_id}/close` | Comando + `{hand_removed: true}` estrito | DOOR_OPEN → CLOSING → DOOR_CLOSED; declaração e intenção persistidas juntas. Não representa sensor de mão. |
| POST `S/{event_id}/review-fixture` | `{}` | DOOR_CLOSED → REVIEW, checkpoint explicitamente fictício e auditado. Não executa câmera/visão, não afirma validade eletrônica e não cria categoria/payload econômico. |
| POST `S/{event_id}/hatch` | Comando mecânico | REVIEW → HATCH_IN_PROGRESS; conclusão lógica persiste sem encerrar o ciclo, aguardando confirmação inicial. |
| POST `S/{event_id}/confirm-initial` | Comando mecânico | Exige alçapão concluído duravelmente. Confirmação simulada → COMPLETED sem recibo/pontuação, liberando o slot da sessão. |
| POST `S/{event_id}/cancel` | `{}` | Apenas SAFETY/PHYSICAL_BLOCKED, sem possível atuação. Repetição de cancelamento é idempotente. Não cancela porta aberta, movimento ou indeterminação. |
| GET `S/{event_id}/commands/{mechanical_command_id}` | Sem body/query | `{source: SIMULATED, command: JournalEntry, history: JournalEvent[]}`. Comando de outro ciclo retorna 404. |

Comando mecânico: `{mechanical_command_id: UUID, timeout_seconds?: número finito
positivo}`; timeout default técnico 10s, sem medição/homologação física. O tipo
da operação é fixado pela rota; não há endpoint genérico para chamar controller.
Campos como operation, simulated, physical_confirmed, GPIO, categoria e
pontuação são recusados. PIN também é recusado na simulação isolada e em
close/confirm-initial; a exceção DEV open/hatch está descrita abaixo.
Fechamento também exige hand_removed=true, sem coerção
de string/número e sem aceitar false.

Snapshot: `{source: "SIMULATED", session: Session, commands: JournalEntry[],
allowed_actions: string[]}`. `Session` mantém a projeção tipada existente;
COMPLETED simulado tem receipt=null. Commands contêm identidade, parâmetros,
fase, resultado, procedência, versão e instantes. Leitura de sessão e comandos
ocorre na mesma transação, sem combinações parciais. allowed_actions descreve
somente mutações possíveis; consultas permanecem disponíveis durante falhas.

POSTs de movimento retornam 202 após aceitação pendente, ou 200 para resultado
terminal/replay/recusa persistida. O snapshot pode já mostrar conclusão se a
operação terminou antes da leitura. **HTTP 200/202 não confirma movimento real**:
consultar phase/result/source. ACCEPTED/PENDING não equivale a COMPLETED/SUCCEEDED.
O `command.state=REQUESTED` aninhado conserva a intenção original; a fase atual
é `JournalEntry.phase`.

Erros seguem `{error:{code,message}}`, sem valores de entrada. 403: Host/Origin,
header ou content-type indevidos. 422: UUID/contrato/query inválidos. 404: sessão
não simulada/inexistente ou comando fora do ciclo. 409: sequência, slot ativo,
conflito de identidade/parâmetros, decisão de segurança divergente ou ação
incompatível. Códigos principais: COMMAND_OUT_OF_SEQUENCE,
MECHANICAL_COMMAND_ID_CONFLICT, MECHANICAL_OPERATION_IN_PROGRESS,
HATCH_COMPLETION_REQUIRED, CANCELLATION_NOT_SAFE, SAFETY_DECISION_CONFLICT,
SIMULATION_LEGACY_SESSION_ACTIVE. 503: coordenador fechado/capacidade indisponível
ou tentativa econômica. Recusa do adaptador é resultado REJECTED/UNAVAILABLE,
não autorização para continuar o fluxo.

## Identidade persistida no DEV — Incremento 3C.1.1

Extensão local nova deste incremento, somente na fábrica DEV. Não altera as
Functions/RPCs centrais nem as rotas operacionais. A fábrica isolada continua
criando fixtures class_only em SAFETY, sem depender de contexto/PIN.

No DEV, POST `/local/simulation/sessions` mantém `{command_id: UUID}` e passa a
criar uma sessão student em IDENTIFYING. class_id/class_name iniciais são somente
o placeholder existente de simulação, não uma turma escolhida/autorizada.
student_id e identity são null. allowed_actions é `["identify", "cancel"]`.
Após confirmação, os campos públicos de turma/aluno vêm da resposta central.
Repetir command_id recupera a mesma sessão, mesmo depois dessa atualização.

POST `/local/dev/sessions/{event_id}/identity` recebe exclusivamente:

```json
{
  "class_id": "33333333-3333-4333-8333-333333333333",
  "student_id": "44444444-4444-4444-8444-444444444444",
  "pin": "0000"
}
```

UUIDs e PIN acima são fictícios. PIN exige string de quatro dígitos ASCII.
Escola/máquina/confirmed/source não são aceitos como declarações do browser.
Valem as mesmas guardas Host/Origin/JSON/header/query e no-store.

O backend verifica health e contexto atuais e usa verify_pin pelo broker existente.
Máquina/escola são conferidas com a política; turma/aluno ACTIVE precisam pertencer
ao contexto e a Function revalida sua relação. Só confirmed=true com IDs
correspondentes autoriza o commit local. Não há transação SQLite durante HTTP.

Resposta 200: SimulationSnapshot existente, acrescido de `identity` (null antes
da associação), com event_id, project_ref, machine_id, school_id, class_id,
student_id, validated_at UTC e source=`SUPABASE_DEV_PIN_V1`. A procedência do
envelope e dos comandos continua SIMULATED. A identidade nunca confirma atuação.
O commit grava vínculo, atualiza turma/aluno e audita
IDENTIFYING → AUTHENTICATING → SAFETY atomicamente; AUTHENTICATING registra a
confirmação local e não fica persistido como estado pendente durante a chamada.

| Situação | HTTP / efeito |
| --- | --- |
| Primeira confirmação consistente | 200, vínculo único e SAFETY; libera safety/cancel. |
| Mesmo event_id/turma/aluno já vinculados | Revalida health/contexto/PIN no Supabase. 200 somente após confirmação atual; retorna snapshot sem novo vínculo, histórico, transição ou alteração de validated_at, inclusive em sessão terminal. |
| Outra turma/aluno em sessão vinculada | 409 DEV_IDENTITY_CONFLICT antes de qualquer chamada remota. |
| Sem vínculo em sessão cancelada/encerrada, legada class_only ou após movimento | 409 COMMAND_OUT_OF_SEQUENCE; não adota identidade retroativamente. |
| PIN errado recusado pela Function | 401 STUDENT_PIN_INVALID, inclusive após associação/restart. Preserva o estado anterior e eventual vínculo existente. |
| IDs fora do contexto permitido | 403 DEV_TEST_SCOPE_MISMATCH; sem associação. |
| Resposta inesperada, credencial inválida, timeout ou falha central | Falha segura 503 pela normalização existente do broker/cliente; 401 para health com autenticação negada e 502 para resposta inconsistente detectada diretamente no cliente local. Sem associação. |
| Contrato/UUID inválido ou campos extras | 422 INVALID_LOCAL_CONTRACT sem expor entrada. |
| Sessão inexistente ou operacional | 404; nenhuma associação. |

Correção de segurança do 3C.1.1: o retorno antecipado anterior confundia replay
de estado com autenticação. Todo POST identity agora revalida o PIN na Function;
PIN de formato válido mas incorreto nunca é aceito como nova autenticação.
Indisponibilidade central retorna erro, preservando o vínculo. validated_at
permanece o instante da associação original, não a última tentativa de autenticação.
Idempotência significa não duplicar a associação; não dispensa a validação do
segredo em outra requisição. GET é o contrato de recuperação sem PIN e sem rede.
Para autenticar outra pessoa é preciso cancelar com segurança e criar outro ciclo.

GET da sessão e GET active restauram o vínculo diretamente do SQLite, sem dados
de identidade reenviados pelo navegador. No DEV, POST open/hatch exige também
`pin` no JSON, string de quatro dígitos ASCII, validada na Function para os IDs
do vínculo persistido. Não recebe outro aluno/turma nem aproveita autenticação
de um POST anterior. Vale para novo comando e replay de comando existente.
Ausência/null de PIN: 401 DEV_ACTION_PIN_REQUIRED; PIN incorreto: 401
STUDENT_PIN_INVALID; formato inválido: 422. PIN nunca integra MechanicalCommand,
journal, snapshot ou banco. Nas outras operações/perfil isolado, o campo é recusado.
Exige health/contexto disponíveis e permanência do aluno ACTIVE na turma autorizada.
allowed_actions informa os estágios persistidos; não promete disponibilidade da
rede no instante de uma chamada seguinte. GET de comandos consulta o journal
sem rede/redisparo; POST open/hatch exige nova autenticação mesmo em replay.
Após autenticação, o mesmo ID/parâmetros continua retornando o comando durável
sem redisparo. Fechamento e confirm-initial válidos continuam disponíveis
sem consulta central para preservar recuperação segura. Estado indeterminado
continua bloqueando movimentos novos/cancelamento; PIN não o desbloqueia.

event_id é público e não é credencial: conhecer o ID/vínculo já não autoriza
abrir porta ou executar alçapão. Safety/review-fixture apenas avançam checkpoints;
cancel/close/confirm-initial preservam recuperação local sem autenticação central,
com as pré-condições/journal existentes. Um processo local capaz de satisfazer
as guardas HTTP ainda pode consultar dados sintéticos, interferir em checkpoints,
cancelar preparação segura ou pedir esses movimentos de recuperação simulados.
Host/Origin/header são proteção de origem, não identidade de usuário/processo.
Este DEV exige computador confiável; não fornece isolamento entre usuários locais
nem autorização homologada para hardware. Antes de atuação física, será necessário
um contrato aprovado de autorização do dispositivo/operador e recuperação segura.
Não foram criados tokens locais, cookies de sessão ou cache de PIN.

Uma sessão DEV 3B/3C.1 sem vínculo conserva o histórico: SAFETY/PHYSICAL_BLOCKED
podem ser cancelados se seguros para criar outra sessão identificada. Não se
retrocede o fluxo nem se presume que o PIN stateless anterior foi validado para
ela. Se já houve movimento, não se adota a identidade; somente fechamento/retorno
seguros já previstos podem continuar. Não há reconciliação pública nova.

## Atomicidade, recuperação e retenção da simulação integrada

SQLite v3 acrescentou cycles.simulated (default 0) e sua imutabilidade.
Bancos v1/v2 migram transacionalmente, sem reclassificar sessões antigas. A
procedência é devolvida no envelope simulado, preservando o contrato operacional
de Session. Runtime operacional recusa banco com sessões simulated=1.

SQLite v4 adiciona simulation_identities, PK/FK event_id e vínculo imutável por
ciclo. Migra v1/v2/v3 na mesma transação de schema, sem apagar/recriar ciclos ou
journal. IDs, instante UTC e origem da confirmação são a evidência local mínima;
nomes continuam somente na projeção Session. Triggers recusam UPDATE/DELETE do
vínculo e alteração dos IDs associados na sessão. O histórico reutiliza transitions.
Startup valida schema, FK, vínculo/sessão/histórico e escopo da instalação.

Após a chamada remota, BEGIN IMMEDIATE e a versão esperada serializam o commit:
mesmos IDs concorrentes retornam o vencedor; IDs diferentes conflitam; cancelamento
concorrente impede associação tardia. Antes do commit não existe vínculo e um
retry precisa validar novamente; depois dele, o vínculo é durável mesmo se a
resposta HTTP se perder. Falha de INSERT/transição reverte tudo. Não existe
transação distribuída ou promessa de validação remota exatamente uma vez.
IDENTIFYING sem vínculo e SAFETY com vínculo são restaurados, sem reautenticação
ou movimento automático. PIN/hash/chave/corpo remoto não são persistidos.

Intenção + estado de movimento + declaração de mão são um commit antes de
despacho; aceitação fica no journal separada; conclusão + estado final são outro
commit atômico com CAS. Nenhuma transação atravessa espera/I/O. Mesmo ID e
parâmetros retornam o estado durável sem redisparo, ainda que o ciclo já tenha
avançado. IDs novos não contornam pré-condições/reserva única. Respostas atrasadas
ou divergentes não avançam sessão.

Startup antes do claim aborta intenção e restaura o estágio conhecido sem enviar
comando; isso exige nova ação explícita/novo ID para tentar a operação. Após
possível despacho, ou após conclusão recebida mas não persistida, journal/sessão
ficam INDETERMINATE/UNKNOWN com slot mantido. Conclusões simuladas persistidas
preservam DOOR_OPEN/DOOR_CLOSED/REVIEW/HATCH_IN_PROGRESS/COMPLETED compatíveis,
sem repetir movimentos. Falha/timeout/cancelamento após aceitação mantêm bloqueio.
Sessões antigas sem procedência nova conservam recuperação anterior.

Não há TTL, expurgo ou reconciliação pública. A manutenção futura deverá preservar
IDs e parâmetros como barreiras de replay, FK por event_id, procedência imutável,
histórico/versionamento e referências de comandos. Registros pendentes, ativos
ou indeterminados não podem ser tratados como concluídos/reconciliados por idade.
Critérios de arquivo/compactação e reconciliação física continuam pendentes.

Contratos de preview/classificação precisam definir transporte, resultado
canônico, auditoria e mapeamento das opções visuais (especialmente `small`).
O gateway de visão do Simulator fornece uma referência de saída, não uma rota
remota oficial a copiar. Esses contratos e a reconciliação de movimento
indeterminado aguardam aprovação; não adicionar campos ao register-deposit-v1.

Resumo/rankings centrais existem, mas a UI oficial não tem essas telas. Não
criar operações locais sem demanda. PIN/contexto podem ser testados com
respostas centrais controladas; a interface real fica indisponível enquanto
`/local/status` retorna false, inclusive se somente health-v1 estiver saudável.
