# 3C.3.1 — homologação opt-in Windows/Docker

TotemEdge FastAPI orquestra câmera e visão localmente. Supabase permanece a
autoridade de registro/recompensa, **não utilizada por este laboratório**.
Identidade e mecânica são sintéticas; a webcam e os provedores podem ser reais.
Não equivale a homologação física do Orange Pi nem a descarte econômico real.

## Pré-requisitos

O operador já relatou homologação do 3C.3.0: FFmpeg Windows/DirectShow,
Integrated Camera selecionada por identidade estável, bridge 127.0.0.1:8766,
Docker bingo-camera-lab saudável em 8016, JPEG real 20.744 bytes,
simulated=false, journal COMPLETED e replay CAPTURE_ALREADY_ATTEMPTED.
Essa é evidência fornecida pelo operador, não execução deste incremento.
O ensaio de reinício/reconexão real e Orange Pi físico continuam separados.

Não parar/reconstruir camera-lab nem o Docker DEV persistente. A nova composição
é standalone: projeto bingo-vision-lab, porta 8017 e volume vision-data próprios.
Não combinar os arquivos Compose deste laboratório com os do DEV.

## PowerShell, a partir da raiz do checkout

1. Conferir a seleção existente e iniciar o bridge, se ainda não estiver rodando:

```powershell
Set-Location -LiteralPath (git rev-parse --show-toplevel)
Push-Location Hardware/TotemEdge/backend
$cameraDirectory = Join-Path $env:LOCALAPPDATA 'BinGo/camera'
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory selection
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory status
# Somente se o serviço ainda não estiver em execução; terminal dedicado:
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory serve
Pop-Location
```

Não executar probe se a intenção for somente conferir disponibilidade: probe
fotografa. Nunca executar outro bridge concorrente na mesma porta/dispositivo.

2. Preparar um arquivo privado fora do repositório, sem valores em comandos/logs:

```powershell
$visionDirectory = Join-Path $env:LOCALAPPDATA 'BinGo/vision-lab'
New-Item -ItemType Directory -Force -Path $visionDirectory | Out-Null
icacls $visionDirectory /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F"
$visionFile = Join-Path $visionDirectory 'providers.json'
# Criar/editar pelo editor local, sem colar credenciais no terminal:
notepad $visionFile
```

Formato JSON UTF-8 sem BOM (substituir os valores vazios somente no arquivo privado):

```json
{
  "aws_key": "",
  "aws_secret": "",
  "aws_token": "",
  "region": "sa-east-1",
  "gemini_key": "",
  "model": "gemini-flash-lite-latest",
  "gemini_timeout": 10,
  "gemini_retries": 1
}
```

AWS exige permissão DetectLabels. Gemini é opcional: chave vazia desabilita
análise secundária e uma inconclusão primária permanece bloqueada. O alias de
modelo é o herdado, não uma versão imutável homologada. Credenciais são lidas
somente desse arquivo readonly; o laboratório recusa credenciais ambientais.
Não usar service_role ou chaves Supabase. Não imprimir o arquivo, environment,
`docker inspect` integral ou `compose config` sem --quiet em relatórios.

3. Criar somente o laboratório separado, com ação explícita do operador:

```powershell
$env:BINGO_CAMERA_TOKEN_FILE = Join-Path $env:LOCALAPPDATA 'BinGo/camera/camera.token'
$env:BINGO_VISION_CREDENTIALS_FILE = $visionFile
$env:BINGO_VISION_LAB_PORT = '8017'
docker compose -p bingo-vision-lab -f Hardware/TotemEdge/deploy/compose.vision-lab.yaml config --quiet
docker compose -p bingo-vision-lab -f Hardware/TotemEdge/deploy/compose.vision-lab.yaml up -d --build --wait
Start-Process 'http://127.0.0.1:8017'
```

Ao confirmar a retirada da mão, haverá **captura física e possível cobrança
dos provedores configurados**. Nada é disparado apenas ao abrir/atualizar a página.
O cliente central desse laboratório é exclusivamente em memória e não possui
capacidade de escrita hospedada. Seu PIN público de fixture é 0012; nunca é PIN
de aluno real. Os nomes/UUIDs fictícios não são comprovantes Supabase.

## Roteiro de verificação

- Selecionar a turma/aluno fictícios; PIN 0012; declarar triagem segura.
- PIN novo 0012 autoriza open simulado. Colocar somente um item diante da webcam.
- Coloquei um item → Retirei a mão. CLOSE deve alcançar COMPLETED/SUCCEEDED
  antes da captura. A interface conserva a tela de progresso já homologada.
- Aguardar REVIEW: o card existente mostra a sugestão real normalizada.
  Corrigir mostra somente candidatos permitidos e eletrônico não identificado
  quando o resultado reconhecido já estabeleceu domínio eletrônico.
- Confirmar correção registra a decisão; Confirmar descarte confirma a sugestão
  quando ainda não houver decisão. Só depois pode pedir PIN para hatch simulado.
- Conferir o snapshot, sem imagem nem segredo:

```powershell
$baseUrl = 'http://127.0.0.1:8017'
$active = Invoke-RestMethod "$baseUrl/local/simulation/sessions/active"
$eventId = $active.snapshot.session.event_id
if ($eventId) {
  $snapshot = Invoke-RestMethod "$baseUrl/local/simulation/sessions/$eventId"
  $snapshot | ConvertTo-Json -Depth 12
}
```

`vision.close_command_id` deve apontar para CLOSE da mesma sessão concluído;
`vision.phase=COMPLETED`, `provenance.camera=DEVICE`, `mechanical=SIMULATED`.
`inference=PROVIDER` exige pixels e provedores não simulados. Observations registra
a cascata normalizada; origin indica AWS_REKOGNITION ou GEMINI_FALLBACK.
Gemini só deve aparecer após inconclusão, nunca após falha operacional AWS.
`decision` distingue observação original, escolha, categoria e origem humana.
Não há bônus por tamanho nem cálculo de pontuação neste código.

Atualizar repetidamente durante e após a revisão deve conservar event_id,
capture_id, close_command_id e decisão, sem nova webcam/IA. O journal da câmera
pode ser consultado pela CLI capture-status usando vision.capture_id.
No SQLite próprio, `vision_attempts`, `transitions` e `mechanical_commands`
registram a correlação; `cycles.physical_confirmed=0`, payload/receipt=null.
Nenhuma fotografia é gravada. Não abrir/editar o SQLite DEV para essa inspeção.

Auditoria somente de leitura, dentro do container **deste laboratório**:

```powershell
$sqliteAuditScript = @'
import json, os, sqlite3, sys
from pathlib import Path
database = Path(os.environ['BINGO_SQLITE_PATH'])
with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as conn:
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA query_only=ON')
    event = sys.argv[1]
    cycle = conn.execute('SELECT event_id,state,physical_confirmed,payload IS NULL AS no_payload,receipt IS NULL AS no_receipt FROM cycles WHERE event_id=?', (event,)).fetchone()
    attempt = conn.execute('SELECT v.capture_id,v.phase,v.error_code,m.phase AS close_phase,m.result AS close_result,m.source AS close_source,v.event_id=m.event_id AS same_event FROM vision_attempts v JOIN mechanical_commands m ON m.mechanical_command_id=v.close_command_id WHERE v.event_id=?', (event,)).fetchone()
    print(json.dumps({'cycle': dict(cycle) if cycle else None, 'vision': dict(attempt) if attempt else None}))
'@
docker compose -p bingo-vision-lab -f Hardware/TotemEdge/deploy/compose.vision-lab.yaml exec -T totem-edge python -B -c $sqliteAuditScript $eventId
```

Depois de COMPLETED, GET pelo event_id continua recuperável, active retorna null
e não há recibo/recompensa. Guardar event_id antes do encerramento.

## Falhas e limites

Câmera ausente/corrompida, fornecedor indisponível ou inconclusão final não viram
UNKNOWN aceito. Falha deixa TECHNICAL_FAILURE; rejeição deixa RETURN_REQUIRED.
O protocolo de devolução física ainda falta: não reabrimos porta nem liberamos
alçapão para esses objetos. Chamar responsável/Entendi somente consulta/preserva.
Sem protocolo de recuperação segura, não há botão de tentar outra foto apagando
a tentativa. Não usar exclusão do SQLite para contornar uma sessão bloqueada.
Para homologar outro cenário após um bloqueio, preservar o volume/auditoria e
criar **outro laboratório**, por exemplo projeto bingo-vision-lab-rejeicao com
BINGO_VISION_LAB_PORT=8018, usando o mesmo arquivo standalone. Não reutilizar
o projeto DEV nem apagar o banco para produzir um resultado positivo.

Reiniciar o container **deste laboratório** durante captura/análise deve conservar
a tentativa como FAILED/PROCESS_INTERRUPTED, sem recaptura. Resultado/decisão
concluídos devem sobreviver. Se houve resposta externa antes de queda local,
ela pode ter sido consumida/cobrada sem resultado durável; não há exatamente uma
chamada garantida do lado do provedor. Não repetimos automaticamente.
Comando de reinício para esse ensaio opt-in, somente no laboratório:
`docker compose -p bingo-vision-lab -f Hardware/TotemEdge/deploy/compose.vision-lab.yaml restart totem-edge`.
Uma queda na lacuna CLOSE concluído → reserva de captura é registrada no startup
como TECHNICAL_FAILURE/CAPTURE_NOT_STARTED_AFTER_RESTART, sem abrir a câmera.
GET não fotografa. Retomada exige futuro protocolo explícito, não refresh.

Encerrar somente o laboratório (preserva seu volume para auditoria):

```powershell
docker compose -p bingo-vision-lab -f Hardware/TotemEdge/deploy/compose.vision-lab.yaml down
Remove-Item Env:BINGO_CAMERA_TOKEN_FILE, Env:BINGO_VISION_CREDENTIALS_FILE, Env:BINGO_VISION_LAB_PORT -ErrorAction SilentlyContinue
```

Não há instrução de down -v nem de remoção de volumes DEV. FAST/INTEGRATION/FULL
não executam este roteiro, não leem providers.json e usam câmeras/IA controladas.
