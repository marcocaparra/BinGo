# Refotografia autorizada na sessão — 02/11/2026

Decisão do responsável: Corrigir mantém candidatos existentes e oferece
**Refotografar item**, sem novo PIN, abertura de porta ou reinício mecânico.
Continua a mesma sessão/event_id. O PIN do hatch posterior permanece inalterado.

## Contrato local

POST `/local/simulation/sessions/{event_id}/vision-recapture`

```json
{"capture_id":"UUID da foto corrente", "recapture_id":"UUID da intenção explícita"}
```

Body estrito; guardas de origem local/X-Totem-Request existentes. Resposta é o
SimulationSnapshot atual. `allowed_actions` acrescenta `vision-recapture` somente
quando a sessão simulada ativa está em REVIEW (reconhecido), RETURN_REQUIRED
(rejeitado) ou TECHNICAL_FAILURE (tentativa FAILED), sempre sem decisão final.
Rejeição não autoriza crédito: permite apenas uma nova fotografia explícita.
Requer identidade DEV vinculada quando aplicável, CLOSE da mesma
sessão COMPLETED/SUCCEEDED/SIMULATED, ausência de comando inseguro ou de qualquer
tentativa de hatch/retorno, ausência de confirmação física/payload/recibo e de
outbox econômica. Recusa por guarda: 409 VISION_RECAPTURE_NOT_ALLOWED;
captura-base divergente: CAPTURE_ID_CONFLICT; intenção reutilizada em vínculo
divergente: RECAPTURE_ID_CONFLICT. Sem visão integrada: 503 VISION_NOT_INTEGRATED.

O journal comprova fechamento conforme o contrato mecânico simulado existente;
não inventa sensor físico. Não altera controller, câmera, provedores ou economia.

## Reserva, captura e análise

Transação curta arquiva a tentativa corrente e reserva CAPTURING antes do I/O.
O capture_id novo é UUIDv5 de namespace/event_id/recapture_id, separado do ID da
captura inicial derivado do fechamento. A mesma intenção nunca volta a adquirir
pixels, mesmo após timeout/reinício ou depois de outra tentativa/conclusão.
Replay idêntico retorna o snapshot corrente; não autoriza nova fotografia.
Intenções diferentes concorrentes não substituem uma captura/análise pendente.

Tarefa independente do HTTP usa CaptureService.acquire, Camera Manager e
SessionVision._classify existentes. Nova fotografia é analisada automaticamente
pela política vigente (AWS, Gemini quando necessário), inclusive no perfil manual
histórico de testes. Nenhum GET/refresh inicia câmera ou provedor. A UI persiste
apenas UUID da intenção para replay de resposta desconhecida. Depois de tentativa
resolvida, novo clique explícito pode usar outra intenção.

Fluxo de recaptura: REVIEW → CAPTURING → CLASSIFYING → REVIEW/rejeição/falha.
Durante captura a UI informa “Fotografando seu eletrônico...”; análise e confirmação
usam componentes existentes. Resposta de foto atrasada só é aplicada se coincidir
com o capture_id corrente, evitando mostrar foto antiga como captura nova.

## Journal e recuperação

`vision_attempts` continua sendo a projeção corrente única por evento. A extensão
SQLite aditiva `vision_recaptures` conserva intenção global única, evento, ID
anterior, novo capture_id único, previous_attempt integral, result_attempt e UTC.
Snapshot.vision.capture_history expõe esses metadados. O histórico de retries de
análise existente continua preservado em sua tabela. Não há migration Supabase.

Nenhuma imagem é persistida. Durante uma recaptura pode haver temporariamente
duas imagens validadas em RAM: a anterior para recuperação e a nova corrente.
Ao terminar, só permanece a corrente (ou a anterior restaurada), até nova captura,
hatch ou reinício. O Camera Manager mantém seus próprios tombstones por UUID;
reenvio da intenção nunca depende de recuperar JPEG do journal da câmera.

Falha técnica da nova captura/análise é arquivada com seu código e proveniência.
A projeção anterior ainda não confirmada é restaurada no estado correspondente:
REVIEW se reconhecida, RETURN_REQUIRED se rejeitada, TECHNICAL_FAILURE se falhou.
Nunca converter rejeição/falha em REVIEW. Não há decisão automática;
snapshot.vision.recapture_error permite aviso explícito.
Se a foto anterior ainda está em RAM, ela volta a ser exibida. O usuário pode
conferir/corrigir ou refotografar novamente. Uma nova classificação rejeitada
continua rejeitada; não há fallback silencioso para aceitação anterior.

Reinício não despacha intenção consumida. A recuperação existente marca tentativas
pendentes FAILED/PROCESS_INTERRUPTED; SessionVision arquiva o resultado e restaura
a classificação anterior quando seguro, sem recuperar pixels inexistentes.
Conclusão de IA já persistida antes do reinício é conservada e arquivada, sem
chamar novamente o provedor. A refotografia explícita pode obter pixels novos.
Não há garantia exactly-once do fornecedor se ele concluiu antes de queda local;
há garantia de não redispatch da intenção pelo TotemEdge.

## Economia e homologação

Conforme relato do responsável, o fluxo anterior de mecânica simulada com crédito
real no bingo-dev e saldo no app foi homologado. Este incremento não altera essa
integração. Nenhuma tentativa de visão chama o registro econômico. Apenas a
decisão final corrente permite o hatch e sua conclusão pelo fluxo existente.
O event_id original continua sendo a barreira econômica de idempotência.

## Validação desta entrega

- Backend completo: **760 aprovados**, zero falhas/skips, incluindo oito novos
  testes HTTP com Camera Manager/cascata controlados e SQLite temporário.
- Regressão focada final: 38 aprovados; contratos JavaScript: 28 aprovados.
- Novos casos: captura/resultado diferentes; evento/identidade/comandos iguais;
  falhas de câmera e provedor com restauração; nova tentativa após falha;
  replay/conflito/concorrência; reinício sem I/O e histórico preservado;
  bloqueio após decisão/conclusão, intenção de hatch, porta aberta, evidência
  física ou econômica. Não usam hardware ou créditos hospedados.
- Browser `frontend/validation/recapture_smoke.cjs`: oito verificações aprovadas,
  zero erros JS; resposta perdida, refresh/replay, feedback, nova foto, retorno à
  confirmação, candidatos preservados e ausência de recompensa. Capturas em
  `frontend/.validation/recapture-{correction,confirmation}.png` inspecionadas.
- A referência visual de correção recebe somente o botão explicitamente solicitado;
  arquivos de baseline, máscaras, CSS e tolerâncias não foram alterados.
- A primeira tentativa de reutilizar o smoke visual longo expirou durante o hold
  inicial do provedor; foi encerrada com limpeza do temporário. O smoke dedicado
  não segura o provedor durante comparações visuais. Na primeira execução dedicada,
  a asserção esperava texto de captura mesmo com aviso de timeout: foi ajustada
  para observar o estado durável e o texto após reload; a execução final passou.

Não houve deploy, uso de webcam real, alteração de containers/volumes de operação,
Supabase hospedado, autenticação ou pontuação. Sem commit/push.

## Arquivos desta alteração

Backend: app/routes/simulation.py; app/services/session_vision.py;
app/services/simulation_flow.py; app/storage.py; app/vision_journal.py.
Frontend: local_api.js; operational.js; script.js.
Testes: backend/tests/test_vision_recapture.py; backend/tests/test_session_vision.py;
frontend/validation/dev_api.test.cjs; frontend/validation/recapture_smoke.cjs;
frontend/validation/approved_visual.cjs; frontend/validation/vision_session_smoke.cjs;
deploy/validate.py. Contratos/notas: este arquivo, CAMERA_V1.md, LOCAL_API_V1.md,
MECHANICAL_INTERNAL_V1.md, VISION_SESSION_V1.md, frontend/INTEGRATION_V1.md,
deploy/TESTING.md e Software/docs/STATUS_12-08.md.

## Atualizar somente o backend existente (não executado)

Executar entre ciclos, pois reinício perde imagens em RAM. Não remover SQLite,
volumes, sessões bloqueadas ou journals. Preservar a política econômica principal.

```powershell
Set-Location C:\Projetos\BinGo
$env:BINGO_DEV_POLICY_FILE='C:/BinGoDevSecrets/dev-policy-economic-main.json'
$env:BINGO_DEV_MACHINE_KEY_FILE='C:/BinGoDevSecrets/dev-machine-key'
$env:BINGO_CAMERA_TOKEN_FILE='C:/Users/Predeus/AppData/Local/BinGo/camera/camera.token'
$env:BINGO_VISION_CREDENTIALS_FILE='C:/Users/Predeus/AppData/Local/BinGo/vision-lab/providers.json'
$mainCompose=@('-p','bingo-totem-edge','-f','Hardware/TotemEdge/deploy/compose.dev-integration.yaml','-f','Hardware/TotemEdge/deploy/compose.vision-dev.yaml')
docker compose @mainCompose up -d --build --no-deps --wait totem-edge-dev
```

Depois: Ctrl+F5 em http://127.0.0.1:8000/. Fazer captura/IA reais, Corrigir →
Refotografar item, conferir nova foto/classificação, confirmar decisão e concluir
o descarte. Só o backend deverá confirmar a recompensa uma vez.
