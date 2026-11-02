# CAMERA_CAPTURE_FAILED — diagnóstico dirigido no principal

## Causa e controle real

A webcam estava sendo utilizada por outro site. O responsável confirmou esse
uso e fechou o site. Com a câmera ocupada, o dispositivo continuava enumerado e
o CameraManager informava present=true/busy=false: busy cobre operações do próprio
gerenciador, não exclusividade global do Windows.

Evidências anteriores à liberação:

- Sessão `67fb1158-3449-4520-80fc-6c6498e432a5`, captura
  `2d5cb7d4-9196-5759-9074-34df40cb5dad`, FAILED/CAMERA_CAPTURE_FAILED no
  journal do bridge, além de outras falhas conservadas. Falha em aproximadamente
  um segundo, não timeout.
- Container → host.docker.internal:8766 com token montado: HTTP 200 para status,
  dispositivo selecionado presente. Os IDs da sessão chegaram ao journal do host.
  Portanto não era bloqueio de rede/autenticação nem recaptura de UUID consumido.
- Execução diagnóstica com o driver/worker reais: zero bytes, DirectShow
  `Error during demuxing: I/O error`. FFmpeg também reportou erro de inicialização
  MJPEG/YUV ao encerrar sem frames. Teste independente de getUserMedia pelo Edge
  retornou `NotReadableError: Device in use`.
- Testar formato JPEG explícito removeu o erro do encoder, mas continuou dando
  zero frames. Essa hipótese não resolveu o bloqueio e o ajuste foi retirado.
- Depois de fechar o site, **o comando original**, sem alteração de formato,
  produziu JPEG válido de 30.065 bytes, exit 0 e stderr vazio. Controle com formato
  explícito também passou; não há motivo para alterar o formato do fluxo.
- `git diff c87eacd HEAD -- app/services/camera.py` não mostrou alterações do
  gerenciador entre a implementação inicial e o código anterior a este diagnóstico.
  Não foi encontrada regressão do driver causada pela refotografia.

## Prova pelo principal existente

Execução controlada dentro de `bingo-totem-edge-totem-edge-dev-1` usou
configured_camera/RemoteCamera, URL/token existentes, bridge, CameraManager,
process guard, FFmpeg e Integrated Camera reais. Sem novos serviços/containers.

Captura `313027cc-8bfb-4b88-97b7-ebfb75643dd6`: 29.879 bytes,
image/jpeg, 640×480, simulated=false, validada por validate_frame e Pillow no
backend. Mesmo UUID reenviado: CAPTURE_ALREADY_ATTEMPTED, sem nova captura.
Status posterior: present=true/busy=false. Nenhuma imagem salva e nenhum registro
econômico gerado por essa sondagem.

Validação concluída com o operador: sessão
`211d2883-3b4b-4b97-a82f-0392d045ff9d`, captura inicial
`6f4741fe-1781-56a5-8e92-146eaab37db3`, chegou a REVIEW/COMPLETED com
image_available=true, reconhecimento real de fone de ouvido via GEMINI_FALLBACK.
O responsável confirmou a classificação e forneceu screenshot da interface.

Refotografia real autorizada na mesma sessão: nova captura
`ebbff224-287f-5ca3-89dc-7eaf5c723add`, JPEG de 29.551 bytes recebido pela rota
privada vision-image, nova análise real GEMINI_FALLBACK e retorno a REVIEW.
Mesma intenção enviada duas vezes; um único novo capture_id/registro no bridge.
capture_history=1, identidade/evento preservados, dois comandos mecânicos (somente
abertura/fechamento), receipt=null, sem decisão/hatch/conclusão econômica.
Não foi preciso atualizar container ou corrigir o pipeline para conseguir isso.

## Alteração mínima de diagnóstico (não implantada)

`app/services/camera.py`: FFmpeg com exit 0 e saída vazia passa a ser reconhecido
como falha de captura no driver. CameraError pode carregar diagnóstico interno;
CameraManager persiste na tabela aditiva privada `capture_diagnostics`, por UUID,
etapa, exit code, bytes, SHA-256 do stderr e marcadores conhecidos de I/O/encoder.
Exceções inesperadas conservam apenas classe/etapa, sem repr/segredos.

Nada disso entra em capture_status ou na resposta pública: o aluno continua
recebendo mensagens sanitizadas. Não há imagem, token, stderr bruto, novo serviço,
alteração de autenticação, seleção, timeout, pontuação ou idempotência. Teste
adicionado em `tests/test_camera.py` comprova diagnóstico privado/saída vazia,
liberação do gerenciador e rejeição de replay.

Testes focados de diagnóstico/driver/refotografia: 10 aprovados. Na rodada mais
ampla, 31 passaram e o teste Windows de cancelamento de processo falhou duas
vezes em WaitForSingleObject(handle,0), retornando 258; o código de process guard
não foi alterado. Essa falha é registrada, não contada como aprovação da suíte.
O diagnóstico ambiental foi comprovado por capturas reais, independentemente
dos doubles. Não foi feita auditoria geral nem reset de driver/dispositivo.

## Atualização

A correção operacional foi liberar a câmera no outro site; **não requer rebuild
nem deploy do TotemEdge**. Evitar uso simultâneo por outras abas/aplicativos.
Para ativar o journal de diagnóstico adicional, entre ciclos encerrar somente o
bridge existente com Ctrl+C no seu terminal e iniciar o mesmo comando:

```powershell
Set-Location C:\Projetos\BinGo\Hardware\TotemEdge\backend
& .venv\Scripts\python.exe -B -m app.camera_cli --directory "$env:LOCALAPPDATA/BinGo/camera" serve
```

Não executar init, trocar a seleção ou apagar banco/token/journal. O bridge
existente não foi reiniciado pelo Codex nesta rodada. Containers, volumes e
sessões existentes preservados; nenhum commit/push/deploy ou crédito realizado.
