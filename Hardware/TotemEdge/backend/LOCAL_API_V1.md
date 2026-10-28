# Contratos locais — fundação de sessão V1

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
Campos como operation, simulated, physical_confirmed, GPIO, PIN, categoria e
pontuação são recusados. Fechamento também exige hand_removed=true, sem coerção
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

## Atomicidade, recuperação e retenção da simulação integrada

SQLite v3 acrescenta somente cycles.simulated (default 0) e sua imutabilidade.
Bancos v1/v2 migram transacionalmente, sem reclassificar sessões antigas. A
procedência é devolvida no envelope simulado, preservando o contrato operacional
de Session. Runtime operacional recusa banco com sessões simulated=1.

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
