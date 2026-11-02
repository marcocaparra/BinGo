# Gerenciamento operacional de câmeras — 3C.3.0

Contrato local definido antes dos endpoints. Não altera o UX do aluno, visão,
economia, GPIO ou prontidão física. CameraManager implementa o protocolo Camera
do CaptureService; abrir/capturar/liberar não decide estados mecânicos.

## Transporte e autoridade

Windows usa processo Python no host e FFmpeg/DirectShow. Linux usa o mesmo
gerenciador com FFmpeg/V4L2, nativo ou com dispositivos explicitamente expostos
ao container. Não há descoberta por índice numérico, streaming ou fallback de
dispositivo. DirectShow usa o alternative name; Linux prefere /dev/v4l/by-id,
depois by-path. Identidade por porta não distingue duas unidades idênticas sem
serial; a troca física dessas unidades requer conferência do operador.

O bridge Windows é loopback por padrão, sem CORS, rejeita Origin e exige Bearer
token de arquivo protegido (mínimo 32 caracteres aleatórios). O token nunca é
retornado. Docker Desktop usa host.docker.internal; não se presume webcam na VM.
Se a instalação exigir bind diferente de loopback, limitar pelo firewall à
interface/rede do Docker. Nenhum bind público ou regra de firewall é criado.
O cliente aceita somente HTTP para localhost/loopback/host.docker.internal,
sem redirects, proxy, query ou credenciais em URL. Não reutiliza chaves Supabase.

O bridge expõe /camera/v1. O TotemEdge configurado explicitamente expõe as mesmas
operações técnicas em /local/camera (mais a operação de sessão abaixo). Sem
configuração, não há acesso a câmera. Toda operação exige token, inclusive GET.
GET não abre câmera. JSON de escrita é estrito. Erros são códigos sanitizados,
sem stderr do driver, imagem ou token. Respostas usam Cache-Control: no-store.
O transporte HTTP da câmera é independente do transporte central; não altera a
allowlist, a chave de máquina ou o isolamento de rede do broker DEV. As redes
internas do DEV persistente continuam sem acesso ao host. A homologação Docker
Windows usa o projeto camera-lab separado; habilitar esse acesso no DEV persistente
exige configuração de rede explícita revisada, não é consequência de ligar câmera.

| Método/sufixo | Contrato |
| --- | --- |
| GET /devices | Dispositivos com device_id opaco, nome, locator e identity_kind. Enumera, não captura. |
| GET /selection | Seleção persistida ou null. |
| PUT /selection | {device_id}; exige identidade estável descoberta. Não abre câmera. |
| GET /status | Seleção, presença e estado ocupado do gerenciador. Presença não comprova permissão/exclusividade. |
| GET /captures/{capture_id} | Metadados do journal da captura (fase, código sanitizado, dispositivo e instantes); nunca imagem e nunca recaptura. |
| POST /captures | {capture_id: UUID}; somente bridge privado, usado pelo backend. Uma captura JPEG em memória, application/octet-stream não é aceita. |
| POST /probe | {capture_id: UUID, allow_real_camera: true}; ensaio técnico explícito fora do fluxo do aluno. Captura e retorna somente metadados, sem salvar imagem. |

/local/camera não expõe /captures irrestrito. POST
/local/camera/sessions/{event_id}/capture recebe {capture_id: UUID} e reutiliza
CaptureService.capture_only. Antes de abrir câmera exige DOOR_CLOSED e comando
CLOSE_INSERTION_DOOR COMPLETED/SUCCEEDED no journal da mesma sessão, com origem
compatível. Reserva CAPTURING atomicamente antes do acesso ao dispositivo. O
resultado da captura não avança para classificação, REVIEW ou conclusão. A sessão
permanece CAPTURING, bloqueada para movimentos posteriores neste incremento.
Reinício nessa fase segue a recuperação conservadora existente, sem recaptura.
Fechamento SIMULATED permite somente ensaio de sessão simulada; não comprova
porta física, e o Frame continua marcado simulated. Não habilita modo operacional.

## Persistência e limites

Seleção e intenções usam SQLite próprio do gerenciador, independente do SQLite
DEV. Um lease de processo impede múltiplos workers no mesmo arquivo. A intenção
é persistida antes do driver. Mesmo UUID nunca recaptura, inclusive após falha,
timeout, queda ou reinício. Resultado binário não é persistido nem reapresentado:
replay retorna 409 CAPTURE_ALREADY_ATTEMPTED. Não há retry automático. Uma nova
sondagem técnica exige UUID novo; uma sessão não recebe nova captura por esse
meio. Capturas concorrentes e seleção durante captura recebem 409 CAMERA_BUSY.
Startup marca intenções incompletas INDETERMINATE; não abre dispositivo.

FFmpeg é executável externo configurável, sem shell. Cada captura cria um
processo, limita saída/tempo e mata/aguarda o filho em erro/cancelamento; o driver
libera o dispositivo ao sair. Uma imagem JPEG, até 5 MiB/16 milhões de pixels,
é validada pela rotina já existente da visão, sem chamar provider. Não há arquivo
de imagem nem fila de frames. Ausência, acesso negado, dispositivo ocupado,
desconexão, timeout e conteúdo inválido mantêm falha; erros ambíguos do driver
ficam CAMERA_CAPTURE_FAILED, sem diagnóstico de hardware inventado.

O worker é somente stdlib e não decide captura. No Windows, ingressa em um Job
Object com KILL_ON_JOB_CLOSE antes de iniciar FFmpeg, sem conservar handle do job:
somente o serviço é proprietário. Morte abrupta do serviço encerra worker e
descendentes. No Linux, configura PR_SET_PDEATHSIG/SIGKILL, confere o PID do pai
para cobrir a corrida de startup e faz exec do executável no mesmo processo.
Falha da proteção impede executar o driver; não há fallback sem proteção.
O worker não recebe token/credenciais em argumentos e o ambiente do driver
remove credenciais BINGO/Supabase/AWS/Gemini. A intenção permanece indeterminada
após interrupção mesmo que o SO tenha liberado o dispositivo.
Usar o binário FFmpeg confiável da distribuição/build escolhido; no Linux, sem
wrappers que criem outro processo, setuid/setgid ou capabilities adicionais.
Referências: [Job Objects](https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects)
e [PR_SET_PDEATHSIG](https://man7.org/linux/man-pages/man2/PR_SET_PDEATHSIG.2const.html).

Iluminação tem protocolo próprio on/off. O adaptador padrão é sem GPIO. Não se
infere que iluminação ou câmera confirmem fechamento, mão retirada ou queda.

Referências: [FFmpeg DirectShow/V4L2](https://ffmpeg.org/ffmpeg-devices.html),
[Docker Desktop host networking](https://docs.docker.com/desktop/features/networking/networking-how-tos/),
LOCAL_API_V1.md, MECHANICAL_INTERNAL_V1.md e VISION_INTERNAL_V1.md.

## Homologação opt-in no Windows/PowerShell

Na inspeção de 31/10, FFmpeg ainda não estava instalado. Em 01/11 o operador
relatou homologação Windows/Docker com Integrated Camera/DirectShow, seleção
persistida, JPEG real de 20.744 bytes e journal COMPLETED; repetição do UUID
retornou CAPTURE_ALREADY_ATTEMPTED. Não é execução do Codex nem homologação Orange Pi.
Ensaio separado de câmera + IA em [VISION_LAB.md](../deploy/VISION_LAB.md).
Para outra máquina ainda sem a ferramenta, instalar um build
Windows com DirectShow, conforme https://ffmpeg.org/download.html, e conferir
`ffmpeg -version`. Pode-se apontar BINGO_CAMERA_FFMPEG para o executável absoluto.
Não há download ou acesso à webcam automático na instalação Python ou nos testes.
O Python usado é o mesmo ambiente locked do backend (Python >=3.12).

A partir da raiz do checkout, em um terminal:

```powershell
Push-Location Hardware/TotemEdge/backend
uv sync --locked
$cameraDirectory = Join-Path $env:LOCALAPPDATA 'BinGo/camera'
# Uma vez; init recusa sobrescrever o token existente.
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory init
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory serve
```

Em outro terminal, no mesmo diretório backend:

```powershell
$cameraDirectory = Join-Path $env:LOCALAPPDATA 'BinGo/camera'
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory devices
# Copiar o device_id da câmera desejada; nunca usar seu índice na lista.
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory select COLE_O_DEVICE_ID
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory status
$captureIntent = [guid]::NewGuid().ToString()
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory probe --allow-real-camera --capture-id $captureIntent
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDirectory capture-status $captureIntent
```

Resultado esperado: fase COMPLETED, JPEG validado e bytes >0; nenhum arquivo de
imagem, transmissão contínua ou chamada IA. Repetir o mesmo UUID deve falhar com
CAPTURE_ALREADY_ATTEMPTED, sem nova abertura. Reiniciar o serviço preserva a
seleção. Desconectar a câmera deve dar present=false ou CAMERA_DISCONNECTED;
reconectar a mesma identidade permite nova sondagem explícita com outro UUID.
Fechar Teams/browser/outro consumidor antes de testar exclusividade; habilitar
acesso de aplicativos desktop à câmera nas configurações de privacidade Windows.
Uma mensagem ambígua do driver é falha de captura, não prova de câmera ocupada.
Ctrl+C encerra o serviço e seus filhos; não apaga configuração ou journal.

### Backend no Docker Desktop

O overlay Windows usa rede normal do runtime operacional, host.docker.internal
e token montado readonly. Não altera o broker DEV, suas redes internas ou chave
de máquina. Criar projeto separado; não aplicar este overlay ao projeto DEV
persistente nem reconstruir seus containers automaticamente.

Na raiz do checkout, após iniciar o serviço Windows:

```powershell
$env:BINGO_CAMERA_TOKEN_FILE = Join-Path $env:LOCALAPPDATA 'BinGo/camera/camera.token'
$env:BINGO_HTTP_PORT = '8016'
# A configuração abaixo não contém credenciais de Supabase/AWS/Gemini.
docker compose --env-file Hardware/TotemEdge/deploy/.env.example -p bingo-camera-lab -f Hardware/TotemEdge/deploy/compose.yaml -f Hardware/TotemEdge/deploy/compose.camera-windows.yaml config --quiet
docker compose --env-file Hardware/TotemEdge/deploy/.env.example -p bingo-camera-lab -f Hardware/TotemEdge/deploy/compose.yaml -f Hardware/TotemEdge/deploy/compose.camera-windows.yaml up -d --build
```

Não imprimir compose config sem --quiet. O .env.example deixa credenciais
centrais vazias; não herdar BINGO_SUPABASE_*, BINGO_MACHINE_*, AWS_* ou GEMINI_*
de outro terminal. O projeto camera-lab tem seu próprio SQLite. Consultar usando
a mesma CLI, acrescentando antes do subcomando:
`--url http://127.0.0.1:8016/local/camera`. devices/status/select/probe funcionam
através do backend Linux; /local/status continua OFFLINE/false. Não há endpoint
de captura livre no backend. capture-session exige evento com journal de porta
fechada; não fabricar esse evento no DEV persistente para testar câmera.

Docker Desktop possui configurações de rede que podem impedir alcançar o
loopback Windows. Se ocorrer CAMERA_BRIDGE_UNAVAILABLE, verificar resolução de
host.docker.internal e firewall, sem alterar regras automaticamente. Se necessário,
serve aceita --bind com endereço da interface local adequada; restringir firewall
ao Docker e preservar autenticação. Não expor 8766 indiscriminadamente à LAN.
O smoke sintético de transporte não comprova acesso a webcam ou USB passthrough.

Para parar somente esse laboratório, repetir os mesmos argumentos de projeto e
arquivos com `down` (sem -v). Nenhum comando de remoção do DEV é necessário.

### Orange Pi/Linux

Nativamente, instalar FFmpeg com V4L2 pelo gerenciador da distribuição e usar a
mesma CLI com diretório protegido e permissão do usuário sobre o dispositivo.
Descoberta prefere /dev/v4l/by-id e informa quando a identidade é somente por
porta. Não aceitar descoberta exclusivamente /dev/videoN: criar regra udev de
identidade estável aprovada pelo operador ou usar câmera que forneça serial.

Em Docker Linux, o target opcional camera_runtime instala FFmpeg; o runtime
default mantém suas dependências e bloqueios. compose.camera-linux.yaml exige
BINGO_CAMERA_DEVICE (link estável absoluto), BINGO_CAMERA_VIDEO_GID (grupo numérico
do device no host) e BINGO_CAMERA_TOKEN_FILE. Usar com compose.yaml e projeto
separado. Somente aquele char device é exposto, sem privileged, sem GPIO e sem
montagem de /dev inteiro. O destino preserva o nome estável; a descoberta também
aceita char device montado nesse caminho. A configuração/journal usam camera-data,
separados do volume de sessão. Para o Linux local no processo TotemEdge, configurar
BINGO_CAMERA_MODE=local, BINGO_CAMERA_DB absoluto e o arquivo de token.

O adaptador cobre câmeras V4L2 disponíveis ao FFmpeg. CSI/libcamera e dispositivos
que dependem de driver específico não são presumidos compatíveis. Medir captura,
memória, permissões, reconexão e qualidade no Orange Pi real antes de homologar.
Não há homing, confirmação física nova ou liberação de prontidão neste incremento.
Hotplug V4L2 nativo redescobre o link estável. Em Docker, mudança do major/minor
após reconexão pode exigir recriação controlada do container para atualizar a
exposição do char device, preservando camera-data e a mesma seleção. Não trocar
para outro índice para contornar esse caso. A imagem opcional usa FFmpeg da
distribuição; registrar sua versão na homologação do equipamento.
O overlay usa sintaxe longa de devices para aceitar os dois-pontos dos nomes
by-path (validada com Compose 2.40.3). Validar config --quiet antes da execução
em outra versão de Compose; o procedimento nativo não depende de Compose.
