# TotemEdge principal — Windows DEV integrado

Laboratório C de 05/11/2026: o caminho sem porta foi adaptado somente no
subprocesso simulado, com perfil doorless-v1 e compatibilidade legacy-v1.
Não é atualização da imagem operacional nem instrução para conectar C ao DEV
econômico. Nenhuma factory, Compose ou volume operacional é alterado por essa
etapa. Ver [controller/README.md](../controller/README.md). A câmera Orange Pi
produziu JPEG 640×480 por FFmpeg segundo evidência do operador; isso não homologa
escotilhas, pinagem, sensores ou descarte físico.

Atualização de 05/11/2026: o perfil principal `vision-dev` usa compartimento sem
porta. Após segurança, `INSERTION_READY` permite posicionar o item; o botão
**Retirei a mão** registra `CONFIRM_HAND_REMOVED` e inicia a captura, sem movimento,
espera ou PIN adicional de porta. O PIN do alçapão continua exigido. As rotas
legadas open/close retornam 410 neste perfil; históricos antigos são preservados.
O journal SQLite é atualizado automaticamente para aceitar a declaração. O campo
legado `vision.close_command_id` passa a referenciar essa confirmação nos novos
ciclos. Nenhuma evidência física é inventada e os recibos antigos permanecem.
O laboratório legado continua disponível para testes de compatibilidade.

Atualização autorizada (02/11): principal em http://127.0.0.1:8000/ com economia
DEV habilitada. Apenas dev-central/totem-edge-dev recriados, volume e histórico
preservados. Para próximos comandos deste projeto usar
`BINGO_DEV_POLICY_FILE=C:/BinGoDevSecrets/dev-policy-economic-main.json`.
Demais arquivos privados inalterados. Aguardar teste do aluno com webcam/IA
reais para comprovar crédito/recibo/replay. Notas anteriores abaixo são históricas.

Decisão posterior: mecânica simulada com pontuação real é homologação econômica
DEV, mediante opt-in; não é modo demo. As afirmações antigas de ausência de
economia abaixo são históricas. Código preparado, containers não atualizados.
Ver [estado e ativação pendente](../../../Software/docs/totemedge-economic-dev.md).

## Recuperar teste parado em erro

A correção de recuperação reutiliza a rota cancel existente, sem alterar volumes
ou criar serviços. Atualizar somente totem-edge-dev com o comando da seção seguinte,
usando os mesmos arquivos privados. É possível aplicar esta atualização com a
sessão já parada em erro: o journal persistido é preservado. A foto antiga em RAM
não é recuperável após reinício e não será recapturada automaticamente.

Depois de atualizar http://127.0.0.1:8000, falhas simuladas de câmera/IA ou rejeição
com comandos encerrados sem risco oferecem **Cancelar tentativa**. Falha técnica
de IA com a foto ainda disponível oferece também **Tentar novamente**: nova análise
da mesma fotografia, mantendo aluno, sessão, captura e histórico anterior.
Cancelar encerra o evento pela API antes de voltar ao começo. Uma nova sessão usa
identificadores próprios. Sem foto em RAM não há retry nem recaptura automática.
Erro original, identidade, observações e comandos antigos continuam consultáveis.
Não reiniciar containers nem apagar SQLite entre os testes.

Se houver movimento pendente/indeterminado ou evidência física, os controles
continuam bloqueados. Chamar responsável: não existe devolução física implementada.
Novas fotos válidas substituem a última foto diagnóstica mantida somente em RAM.

## Atualização pontual de classe e textos do aluno

Com o ambiente principal já instalado e os mesmos quatro caminhos privados
BINGO_*_FILE configurados, atualizar somente o backend. Broker, proxy, seleção
da câmera e volumes permanecem os existentes. Não reiniciar o bridge por esta correção.
Atualizar entre ciclos: a foto permanece em RAM e não sobrevive à substituição do
backend. Não apagar o SQLite nem redisparar captura para contornar sessão pendente.

```powershell
$mainCompose = @('-p','bingo-totem-edge','-f','Hardware/TotemEdge/deploy/compose.dev-integration.yaml','-f','Hardware/TotemEdge/deploy/compose.vision-dev.yaml')
docker compose @mainCompose config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Configuração inválida' }
docker compose @mainCompose up -d --build --no-deps --wait totem-edge-dev
```

Abrir http://127.0.0.1:8000 e atualizar a página. Homologar foto de fone/mouse/cabo,
nome específico na confirmação, ausência de nomes de provedores, correção e
recuperação. Tipos inconclusivos não são aceitos como UNKNOWN; essa opção exige
domínio eletrônico reconhecido. Não há pontuação nem registro econômico.
Esses comandos não foram executados pelo Codex nesta correção.

Decisão de 02/11/2026: um único projeto principal `bingo-totem-edge`. Reutilizar
`compose.dev-integration.yaml` + `compose.vision-dev.yaml`, sem novos laboratórios.
`dev-http` publica 8000, `totem-edge-dev` executa a aplicação FastAPI existente e
`dev-central` mantém exclusivamente a chave da máquina e health/contexto/PIN.
O backend recebe apenas credenciais IA e token da câmera, em arquivos readonly.

## Impacto antes de substituir o container antigo

O serviço antigo `totem-edge` ocupa 8000. Deve ser parado explicitamente antes
da ativação integrada. Seu container e volume `bingo-totem-edge_sqlite-data`
permanecem preservados: não há remoção nem migração/adopção de sessões físicas.
O perfil integrado usa `bingo-totem-edge_vision-dev-data`, um armazenamento de
sessões simuladas separado dentro do mesmo projeto. Não compartilha o banco do
DEV antigo em 8002 nem os bancos dos laboratórios. Não usar --remove-orphans,
down, down -v ou prune. Nenhuma troca de container foi executada nesta entrega.

## Homologação pelo operador, PowerShell na raiz do checkout

Primeiro, iniciar o bridge existente somente se 8766 ainda não estiver ocupado,
em terminal dedicado (não executar init nem trocar a seleção automaticamente):

```powershell
Push-Location Hardware/TotemEdge/backend
$cameraDir = Join-Path $env:LOCALAPPDATA 'BinGo/camera'
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDir serve
Pop-Location
```

Em outro terminal: informar caminhos de arquivos autorizados, nunca valores secretos.
O formato de providers.json e a configuração da webcam continuam em VISION_LAB.md
e CAMERA_V1.md. Os comandos seguintes são para homologação autorizada futura;
não foram executados automaticamente.

```powershell
Push-Location Hardware/TotemEdge/backend
$cameraDir = Join-Path $env:LOCALAPPDATA 'BinGo/camera'
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDir selection
uv run --locked --offline python -B -m app.camera_cli --directory $cameraDir status
Pop-Location
$env:BINGO_DEV_POLICY_FILE = Read-Host 'Caminho da política DEV existente'
$env:BINGO_DEV_MACHINE_KEY_FILE = Read-Host 'Caminho do arquivo da chave da máquina'
$env:BINGO_CAMERA_TOKEN_FILE = Join-Path $env:LOCALAPPDATA 'BinGo/camera/camera.token'
$env:BINGO_VISION_CREDENTIALS_FILE = Read-Host 'Caminho do providers.json privado'
$env:BINGO_VISION_DEV_PORT = '8000'
$mainCompose = @('-p','bingo-totem-edge','-f','Hardware/TotemEdge/deploy/compose.dev-integration.yaml','-f','Hardware/TotemEdge/deploy/compose.vision-dev.yaml')
docker compose @mainCompose config --quiet
if ($LASTEXITCODE -ne 0) { throw 'Configuração inválida' }
docker compose -p bingo-totem-edge -f Hardware/TotemEdge/deploy/compose.yaml stop totem-edge
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível liberar a porta principal' }
docker compose @mainCompose up -d --build --wait
if ($LASTEXITCODE -ne 0) { throw 'Integração não ficou saudável; preservar dados para diagnóstico' }
Start-Process 'http://127.0.0.1:8000'
```

Identidade/PIN do contexto DEV → segurança → PIN/abertura simulada → um item →
retirada da mão → fechamento concluído no journal → captura/análise automáticas →
**foto da webcam na confirmação** → Sim, está certo ou Corrigir → revisão final →
PIN/hatch e retorno simulados. COMPLETED continua sem recibo, BinCoins ou XP.
Não há vídeo nem comandos mecânicos acionados por refresh/animação. GET nunca
recaptura. Falha/rejeição bloqueiam o descarte; devolução/recaptura continuam sem
contrato. Foto não é gravada em disco: um reinício pode recuperar a decisão da IA,
mas não a foto. A UI não deve substituí-la por ilustração após reinício.

O caminho Linux/V4L2 existente continua preparado, mas Orange Pi e GPIO reais não
foram homologados. Testes comuns usam webcam, central e IA controladas e não
constituem prova de funcionamento físico ou de credenciais hospedadas.
