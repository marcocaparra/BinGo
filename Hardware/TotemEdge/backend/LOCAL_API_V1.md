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

Não criar rotas de movimento, escotilha, confirmação física, preview, captura,
classificação, correção ou reconciliação manual nesta etapa.
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

Contratos de preview/classificação precisam definir transporte, resultado
canônico, auditoria e mapeamento das opções visuais (especialmente `small`).
O gateway de visão do Simulator fornece uma referência de saída, não uma rota
remota oficial a copiar. Esses contratos e a reconciliação de movimento
indeterminado aguardam aprovação; não adicionar campos ao register-deposit-v1.

Resumo/rankings centrais existem, mas a UI oficial não tem essas telas. Não
criar operações locais sem demanda. PIN/contexto podem ser testados com
respostas centrais controladas; a interface real fica indisponível enquanto
`/local/status` retorna false, inclusive se somente health-v1 estiver saudável.
