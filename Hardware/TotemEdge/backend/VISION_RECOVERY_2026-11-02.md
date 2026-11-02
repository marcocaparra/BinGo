# Recuperação de imagem inadequada e falha de IA

## Causa observada no principal

Inspeção somente leitura da sessão `e14cb247-7ca1-46f6-99b2-e5e2e2e93aff`:

- state=RETURN_REQUIRED; failure_code=null;
- captura `5368beaa-533b-5e37-8892-a49e3aa66983`, phase=COMPLETED;
- JPEG DEVICE de 8.280 bytes, image_available=true;
- observation.status=rejected, confiança 0, candidatos vazios;
- origem AWS_REKOGNITION, sem passagem pelo Gemini; vision.error_code=null;
- allowed_actions=[cancel].

Não era falha de captura/provedor. A foto obstruída foi rejeitada normalmente,
conforme a política existente. O retry da mesma foto exigia falha temporária e
a recaptura exigia REVIEW/recognized. A UI mostrava mensagem genérica sem
distinguir essas situações e desabilitava a única ação de retry.

## Correção mínima

Reutilizados vision-recapture e vision-analyze, UUIDs, câmera e cascata existentes.
Recaptura autorizada em REVIEW/recognized, RETURN_REQUIRED/rejected ou
TECHNICAL_FAILURE/FAILED, somente antes de decisão final, com sessão ativa,
fechamento correlacionado seguro, identidade vinculada quando exigida e sem
qualquer tentativa de hatch/retorno ou evidência/outbox econômica.

UI mostra “Tirar outra foto” após rejeição/inconclusão/falha. Falha temporária
de IA com imagem em RAM oferece, separadamente, “Tentar análise novamente”.
As guardas de mecânica/economia também são aplicadas ao retry de análise.
Não se abre a porta, não se repete PIN e não se registra pontuação na visão.
Texto deixou de prometer devolução ou atribuir erro a um fornecedor.

Falha técnica da recaptura restaura a tentativa anterior no estado correto:
reconhecida → REVIEW; rejeitada → RETURN_REQUIRED; falha → TECHNICAL_FAILURE.
Não promove foto rejeitada/inconclusiva a classificação aceita. Históricos e
imagens recuperáveis seguem as regras existentes; nova foto recebe UUID próprio.
Replay idêntico só lê o resultado atual, sem câmera/análise novas. Intenção
divergente ou mecânica insegura continua recusada. Refresh não captura.

## Impedimento adicional encontrado nos testes

Depois de um retry de análise, trocar a captura falhava com FOREIGN KEY
constraint failed. vision_analysis_retries.capture_id referenciava a projeção
mutável vision_attempts, cujo capture_id é substituído pela refotografia.

Extensão local mínima: vision_capture_ids registra identidades imutáveis de
captura/evento. A FK do histórico passa a apontar para esse par histórico;
triggers registram cada captura corrente nova/restaurada. Startup faz backfill
e migra a tabela de retries transacionalmente, copiando todas as linhas com
mesmos UUIDs/payloads/UTC. Não usa ON UPDATE CASCADE, que alteraria indevidamente
o capture_id histórico. Não há migration ou mudança no Supabase.

Teste modela a FK antiga, migra, refotografa após retry e comprova igualdade
integral das linhas históricas, foreign_key_check vazio e migração idempotente.

## Validação

Regressão completa final: **764 testes aprovados**, zero falhas/skips.

36 testes focados iniciais aprovados; regressão de visão/migração final: 45 aprovados.
Contratos JavaScript: 28 aprovados. Browser dedicado: dois cenários, oito verificações
cada, zero erros. Exercita rejeição seguida
de nova foto e falha temporária seguida de análise da mesma foto e nova captura,
incluindo resposta perdida/replay/refresh, nova confirmação e zero recompensa.
São testes com dispositivos/provedores controlados, não homologação real desta
alteração no principal. A sessão real acima foi somente consultada.

Uma primeira execução combinada encontrou a FK descrita acima e foi corrigida.
A primeira regressão completa encontrou oito asserções antigas de ações que
excluíam recaptura após falha; foram adaptadas sem remover as verificações de
rejeição, ausência de candidatos/recibo ou bloqueio do hatch.

## Arquivos desta rodada

Backend: app/services/session_vision.py, app/vision_journal.py, app/storage.py.
Interface: frontend/script.js e frontend/operational.js.
Testes: backend/tests/test_vision_recapture.py, test_simulation_recovery.py,
test_session_vision.py, test_vision_photo_flow.py; frontend/validation/
recapture_smoke.cjs, approved_visual.cjs e vision_session_smoke.cjs.
Contratos: RECAPTURE_V1.md, VISION_SESSION_V1.md, LOCAL_API_V1.md,
frontend/INTEGRATION_V1.md, este relatório e Software/docs/STATUS_12-08.md.

Sem mudança de autenticação, recompensa, Supabase, providers ou dispositivo;
nenhum container/volume/serviço criado, reiniciado ou apagado. Sem commit/push/deploy.

## Atualização do serviço existente — não executada

Entre ciclos, preservando os arquivos privados e volumes. O restart perde pixels
em RAM; as intenções e metadados continuam persistidos. Nova fotografia segura
pode ser solicitada mesmo sem os pixels da tentativa anterior.

```powershell
Set-Location C:\Projetos\BinGo
$env:BINGO_DEV_POLICY_FILE='C:/BinGoDevSecrets/dev-policy-economic-main.json'
$env:BINGO_DEV_MACHINE_KEY_FILE='C:/BinGoDevSecrets/dev-machine-key'
$env:BINGO_CAMERA_TOKEN_FILE='C:/Users/Predeus/AppData/Local/BinGo/camera/camera.token'
$env:BINGO_VISION_CREDENTIALS_FILE='C:/Users/Predeus/AppData/Local/BinGo/vision-lab/providers.json'
docker compose -p bingo-totem-edge `
  -f Hardware/TotemEdge/deploy/compose.dev-integration.yaml `
  -f Hardware/TotemEdge/deploy/compose.vision-dev.yaml `
  up -d --build --no-deps --wait totem-edge-dev
```

Atualizar http://127.0.0.1:8000/ com Ctrl+F5. Não limpar sessões para testar.
