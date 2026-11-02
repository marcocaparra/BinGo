# Visão por sessão — 3C.3.1

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
