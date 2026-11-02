# Visão por sessão — 3C.3.1

## Retry de análise e confirmação única — decisão de 02/11/2026

A confirmação/correção em recognized/correct-item persiste vision.decision.
A UI segue diretamente ao componente PIN existente quando allowed_actions contém
hatch. Não exibe a segunda tela review com ilustração. PIN novo e todas as guardas
do alçapão permanecem obrigatórios; render/refresh não solicitam movimento.

POST /local/simulation/sessions/{event_id}/vision-analyze aceita, opcionalmente,
`analysis_attempt_id: UUID` junto de `capture_id: UUID`. O campo novo representa
uma intenção explícita de retry da IA, não de captura. Sem esse campo, permanece
inalterada a compatibilidade da análise inicial manual histórica.

Retry exige TECHNICAL_FAILURE, foto validada ainda em RAM, captura FAILED por
falha recuperável de provedor (indisponibilidade/timeout/resposta inválida), sessão
simulada ativa, CLOSE correlacionado COMPLETED/SUCCEEDED/SIMULATED e todos os
comandos seguros, sem evidência física ou econômica. Rejeição e inconclusão de
negócio não autorizam retry. A guarda expõe vision-analyze em allowed_actions;
qualquer POST que a viole retorna 409 VISION_RETRY_NOT_ALLOWED. Reinício perde o
JPEG: não se recaptura, mantém-se cancel seguro quando permitido ou responsável.

Uma transação SQLite insere vision_analysis_retries (analysis_id global único,
event_id, capture_id, previous_attempt, created_at), arquiva a tentativa anterior
integralmente e reserva CLASSIFYING antes da chamada externa. Snapshot.vision
expõe analysis_history com esse arquivo, enquanto provenance.analysis_id identifica
a tentativa atual. A câmera e o evento originais permanecem os mesmos. Replays do
mesmo UUID retornam o snapshot sem nova IA; UUID reutilizado em outro vínculo
retorna 409 ANALYSIS_ID_CONFLICT; intenção diferente durante processamento é
bloqueada. O frontend persiste somente UUIDs para repetir a intenção em caso de
resposta perdida; GET/refresh não executam análise. Nova tentativa explícita após
outra falha recebe outro UUID. Recuperação de processo registra falha técnica das
reservas pendentes; não reinicia provedores nem câmera. Uma chamada externa pode
ter concluído antes da queda local: não há garantia exactly-once no provedor,
mas o mesmo UUID consumido nunca é despachado novamente pelo TotemEdge.

Não há escrita econômica, alteração do fluxo da câmera, política de fallback,
credenciais ou recuperação física. A fotografia continua privada e apenas em RAM.


Recuperação DEV (02/11): POST /local/simulation/sessions/{event_id}/cancel também
encerra testes em TECHNICAL_FAILURE/RETURN_REQUIRED, somente com simulated=1,
controller/journal SIMULATED, todos os comandos COMPLETED/SUCCEEDED, nenhuma
análise pendente e nenhuma evidência/payload/recibo físico/econômico. A mesma guarda
expõe cancel em allowed_actions. Não altera os cancelamentos operacionais físicos.
O encerramento é CANCELLED, idempotente, libera apenas o slot ativo e acrescenta
SIMULATION_TEST_ENDED ao histórico, preservando erro original, identidade, comandos
e observações. Não significa devolução nem retorno físico à posição inicial.
A UI separa “Tentar novamente” (nova análise da mesma foto, quando autorizada)
de “Cancelar tentativa” (encerra pela API antes de voltar ao início). Nenhum desses
controles solicita devolução física. Uma sessão seguinte recebe IDs próprios.
Movimento pendente/indeterminado ou evidência física mantém bloqueio e orientação
para chamar responsável. A última foto validada fica só em RAM para diagnóstico
pela rota privada vision-image (inclusive após falha/encerramento), até a próxima
captura válida ou reinício. Não é salva em disco nem pode ser reconstruída por GET.


Correção localizada de 02/11 — classe específica e apresentação ao aluno:
`detected_types` preserva os tipos específicos observados pelos provedores, indexados
pelos IDs de adaptação legados. Esses IDs internos (inclusive small) não são classes
para exibição, tamanho ou novo catálogo canônico. Nenhuma regra econômica mudou.
AWS conserva a label específica; Gemini informa detected_type em português, separado
do agrupamento legado. A decisão local preserva detected_type e a observação original
continua em provenance.observations. Agrupamento small reconhecido sem tipo específico
projeta UNKNOWN/UNIDENTIFIED; inconclusão/rejeição/falha não ganham essa autorização.
A UI usa nomes compreensíveis, sem provedor/modelo/fallback/diagnósticos. A orientação
“Um item por ciclo” não representa contagem detectada. Captura, fotografia, mecânica,
broker e política de fallback permanecem preservados.


Atualização de 02/11/2026 — decisão posterior: no perfil integrado DEV, CLOSE
confirmado no journal dispara uma única captura e análise automaticamente. Não há
tela manual nem botão Analisar item. O reconhecimento reutiliza o componente
original com a fotografia real em lugar da ilustração. A imagem permanece somente
em RAM durante análise/revisão e é liberada ao iniciar hatch. Reinício perde essa
foto; resultados/decisões persistidos continuam recuperáveis, sem recaptura.
A implantação Windows utiliza o projeto principal bingo-totem-edge com os overlays
DEV existentes; ver deploy/MAIN_DEV.md. As descrições manuais abaixo são históricas.


## Ajuste funcional — foto confirmada e identidade DEV

Decisão posterior do operador: foto única, sem vídeo. Após fechamento confirmado,
o backend captura e libera a câmera; a foto permanece somente em RAM, no máximo
5 MiB. O canvas original mostra essa mesma imagem. Analisar item solicita a IA
explicitamente; GET/refresh nunca capturam ou classificam. O modo automático
anterior permanece somente como compatibilidade interna de testes.

Extensões locais necessárias para ligar os controles existentes:
- GET S/{event_id}/vision-image/{capture_id}: JPEG privado em memória, sem cache;
  exige X-Totem-Request: 1 e as guardas locais de origem. Não abre câmera.
- POST S/{event_id}/vision-analyze: {capture_id: UUID}; reserva CLASSIFYING antes
  de despachar. Replay recupera o resultado/intenção, sem outra IA ou foto.
S é /local/simulation/sessions. CAPTURING com provenance.capture_ready=true
permite vision-analyze em allowed_actions; não cria outro estado mecânico.
Reinício sem a foto em RAM permanece falha técnica segura, sem recaptura.

O perfil separado vision-dev reutiliza DevPolicy, FunctionTransport e
DevCentralClient do 3C.2.1, com somente health/context/student-pin pelo broker
existente. Não possui fallback para alunos sintéticos. A simulação mecânica,
physical_confirmed=0, receipt=null e a proibição de registro econômico continuam.
As credenciais IA continuam em arquivo privado; a chave Supabase só fica no broker.

Os templates camera/recognized/classification/secondary-analysis são restaurados
da referência da equipe. A foto capturada usa o canvas existente, nunca vídeo ao
vivo. Confirmar reconhecimento/correção persiste a decisão e libera revisão final.
Refazer captura, ajustar/tentar novamente e devolver item ficam desabilitados:
faltam contratos seguros de nova intenção e devolução. Não se reutilizam esses
controles para apagar sessão, reabrir porta ou executar alçapão.
Pontos/recibo continuam pendentes da integração econômica, sem tela de recompensa.

As seções seguintes registram a entrega anterior; esta seção atualiza a ligação UX.

Extensão local do contrato VISION_INTERNAL_V1, sem contrato econômico novo.
Somente a fábrica opt-in `app.vision_lab:create_vision_lab_app` compõe câmera,
InternalVision e controlador SIMULATED. O runtime operacional e o DEV hospedado
continuam com seus bloqueios. Supabase permanece autoridade econômica.

## Intenção e autoridade

O POST close explícito com hand_removed=true solicita também a análise subsequente.
O backend aguarda o journal CLOSE_INSERTION_DOOR COMPLETED/SUCCEEDED da mesma
sessão e usa UUIDv5 derivado desse comando para a intenção de captura.
GET, polling, renderização e startup nunca iniciam captura ou classificação.
Uma única tentativa por evento; IDs consumidos não são reutilizados para fotografia.
Captura e classificação correm em tarefa local, não no tempo de vida da conexão HTTP.
DOOR_CLOSED → CAPTURING → CLASSIFYING → REVIEW/RETURN_REQUIRED/TECHNICAL_FAILURE.

Extensão do snapshot: `vision` nulo ou journal técnico, com capture_id, event_id,
close_command_id, phase, error_code, observation, decision e provenance. Nenhuma
fotografia/base64/resposta bruta de fornecedor é exposta ou persistida. O journal
contém somente saída normalizada, provedor/modelo/política e tempos UTC.
Os pixels DEVICE e a mecânica SIMULATED são procedências independentes;
nenhuma delas altera physical_confirmed=0, payload=null ou receipt=null.

POST `/local/simulation/sessions/{event_id}/vision-review`:
`{capture_id: UUID, item_id: ID visual, action: confirm|correct}`.
Confirm exige a sugestão original; correct exige candidato oferecido. Repetição
idêntica recupera a decisão imutável, divergência gera 409. Rejeição/inconclusão
não admite revisão nem hatch. Decisão posterior do desenvolvedor neste incremento:
reutilizar o mapeamento vigente do Simulator, sem recompensa por tamanho.
battery→BATTERY, cable→CABLE_WIRE, phone→MOBILE_DEVICE, small→PERIPHERAL;
esse último é um ID legado de agrupamento, não regra de bônus. A categoria fica
somente na decisão local; não cria payload nem registro econômico.
UNKNOWN/UNIDENTIFIED pode ser escolhido somente após resultado `recognized`
do pipeline existente (domínio eletrônico aceito), nunca após rejeição ou
inconclusão. Os demais candidatos devem ter sido oferecidos pelo provedor.
Uma observação genérica `needs-secondary` não comprova domínio e continua bloqueada.

## Durabilidade e falhas

A reserva, correlação do fechamento e CAPTURING são atômicos. CLASSIFYING é
persistido antes da chamada externa; resultado e estado final são atômicos.
Reinício com tentativa em andamento registra TECHNICAL_FAILURE/PROCESS_INTERRUPTED,
sem reabrir câmera ou repetir IA. Sem imagem durável, essa tentativa é irrecuperável.
Uma resposta externa concluída antes de queda local não pode ser provada: não
prometemos exactly-once no fornecedor, nem repetimos automaticamente sua chamada.
Resultado e decisão já persistidos sobrevivem. Não há retry automático de captura.
Startup na lacuna CLOSE concluído sem reserva grava FAILED e
CAPTURE_NOT_STARTED_AFTER_RESTART, sem I/O de câmera/provedor. Não deixa a UI
aguardando indefinidamente uma captura que não será iniciada por GET.
Erros técnicos usam códigos controlados; mensagens externas/segredos não são gravados.
Saídas normalizadas dos provedores são preservadas, inclusive a primária quando
o fallback falha. Um observador fornecido pelo orquestrador grava a resposta
primária antes da rede secundária, sem acoplar o serviço de visão ao SQLite.
Falha dessa auditoria impede a chamada secundária. Queda durante Gemini conserva
a evidência primária já persistida. O journal também registra MIME/tamanho da
captura validada, sem os bytes JPEG. Modelo Gemini é o configurado nos resultados;
AWS informa a operação DetectLabels,
sem alegar uma versão imutável que o adaptador atual não fornece.

O SQLite v4 recebe a tabela aditiva vision_attempts, com FK para sessão/comando;
não há migration PostgreSQL, mudança de payload econômico ou fotografia em disco.
A lease de processo existente impede dois workers no mesmo arquivo. Reserva,
projeção e decisão usam transações curtas e o CAS da sessão.

## Associação visual

Sem modificar HTML, CSS ou textos: CAPTURING/CLASSIFYING conservam door-progress,
REVIEW usa review com a sugestão real, Corrigir usa correct-item com candidatos.
Confirmar descarte persiste a sugestão antes de solicitar o PIN de hatch;
Confirmar correção persiste a escolha e volta a review. Uma decisão persistida é
imutável, inclusive após refresh. O botão Corrigir passa a indisponível.
Não são ativados os templates antigos camera/recognized: divergem da referência
B em preview/badge, e não é necessário substituí-los para integrar este fluxo.
O comparador usa a mesma revisão B, zero máscaras e zero tolerância; somente
recebe os candidatos/dados sintéticos correspondentes para montar a referência.

Retorno físico após recusa não está implementado no contrato mecânico atual.
RETURN_REQUIRED mantém bloqueio e orientação existente; nenhum OPEN/hatch é emitido.
Novas tentativas após falha exigem futuro protocolo explícito de recuperação segura;
não apagamos a sessão para contornar o bloqueio.

## Preservação

Reutilizados validate_frame, CameraManager/RemoteCamera, InternalVision,
RekognitionProvider/GeminiProvider e política 0,75. Falha operacional principal
não chama Gemini. Inconclusão final é falha bloqueante, nunca UNKNOWN aceito.
Sem mudanças em taxonomia, recompensa, templates, textos, CSS ou referências visuais.

## Arquivos deste incremento

- Novos: app/services/session_vision.py, app/vision_journal.py, app/vision_lab.py,
  tests/test_session_vision.py, tests/test_vision_lab.py, tests/dev_data.py e este contrato.
- Composição/persistência: app/main.py, app/storage.py, app/simulation.py,
  app/services/capture.py, app/services/vision.py, app/services/simulation_flow.py,
  app/routes/simulation.py.
- Frontend: somente adaptadores funcionais script.js, operational.js e local_api.js;
  validation/dev_api.test.cjs, validation/approved_visual.cjs (dados de candidatos,
  nenhuma tolerância/referência alterada), novo validation/vision_session_smoke.cjs.
- Harness reutilizado: tests/dev_frontend_fixture.py; dados públicos compartilhados
  extraídos de tests/test_dev_integration.py, sem duplicação e sem carregar pytest
  no servidor de navegador. Handshakes/imports reduzidos em tests/test_auto_initial.py
  e tests/test_camera.py; novas verificações em tests/test_vision.py. Nenhum timeout
  ou asserção de garantia foi afrouxado.
- Deploy: novo start_vision_lab.py, compose.vision-lab.yaml, VISION_LAB.md;
  Dockerfile, validate.py e TESTING.md atualizados.
- Documentos relacionados: CAMERA_V1.md, VISION_INTERNAL_V1.md, LOCAL_API_V1.md,
  ../frontend/INTEGRATION_V1.md e Software/docs/STATUS_12-08.md.

As alterações de Camera Manager do 3C.3.0 já estavam na working tree e foram
preservadas; seu driver/bridge não foi reimplementado aqui. .vscode não foi alterado.
