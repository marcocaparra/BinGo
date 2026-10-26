# Totem BinGo

Interface local do Totem BinGo para tela touch vertical de 7 polegadas.

## Objetivo

Este protótipo usa a lógica das telas antigas de `UX e Design/UI e Telas`, mas segue a linguagem visual do app mobile atual. Ele existe para revisão rápida de fluxo e interface antes da implementação real do kiosk no Orange Pi com Ubuntu.

## Como abrir

Sirva a pasta `Software` como raiz estatica:

```bash
cd Software
python -m http.server 8092 --bind 127.0.0.1
```

Abra:

```text
http://127.0.0.1:8092/apps/totem_ui/
```

Se a porta `8092` ja estiver ocupada, use outra porta e mantenha o mesmo caminho `/apps/totem_ui/`.

## Escopo

- Fluxo vertical para tela de 7 polegadas.
- B1N como fonte principal das instruções: as frases operacionais aparecem como fala dele.
- Estado idle de kiosk com B1N aguardando/dormindo, sem balão de fala.
- Tela de PIN com B1N em postura de privacidade.
- Login por aluno/turma/PIN como wireframe.
- Opção de pontuar apenas para turma.
- Escolha de categoria do item.
- Checagem de segurança para pilhas, baterias e celulares.
- Estados de inserir, analisar, sucesso e chamar professor.

## Fora do escopo

- Backend real.
- Integração final da visão e do serviço Edge no Orange Pi. No PC, webcam e Rekognition já funcionam juntos.
- Persistência de dados.
- Integração com Supabase ou FastAPI.

## Teste de webcam no PC

- O modo padrão usa webcam real, somente na etapa Câmera e após a porta simulada ser fechada.
- Clique em `Ativar câmera` e permita o acesso no navegador. O microfone não é solicitado.
- Confira o preview, clique em `Capturar imagem` e use `Refazer captura` se necessário.
- `Continuar com IA simulada` preserva a demonstração existente: a foto não é enviada nem usada pelo classificador simulado.
- A captura fica só em memória até encerrar/resetar a sessão. Não há armazenamento persistente nem upload.
- A webcam é desligada ao capturar, sair da etapa, ocultar a aba ou fechar a página.
- Permissão negada, câmera ocupada/ausente, desconexão e timeout impedem a captura e permitem tentar novamente ou usar a devolução existente.
- Use localhost/127.0.0.1 ou HTTPS. No Orange Pi ainda é necessário validar dispositivo, navegador, iluminação e confirmação real da porta.
- Para manter a demonstração sem acesso a hardware, use `?camera=simulated`.
- Para abrir diretamente a etapa em revisão com porta **simulada** fechada, use `?screen=camera`.
- Para usar o Rekognition real, inicie o serviço Edge e abra `?screen=camera&vision=remote`.

Testes locais (sem acesso à webcam):

```bash
node --check camera_controller.js
node --check vision_provider.js
node --check script.js
node --test tests/camera_controller.test.cjs
node --test tests/vision_provider.test.cjs
python -m unittest tests/edge_vision_service_test.py
```

O teste de navegador `tests/camera_flow.test.cjs` requer Playwright no ambiente Node e um servidor ativo. Usa dispositivo **sintético**, não acessa a webcam humana. Execute `node --test tests/camera_flow.test.cjs`; `BINGO_TOTEM_URL` troca a URL padrão (porta 8105), e `BINGO_BROWSER_PATH` troca o executável padrão do Edge no Windows. Os prints vão para `_visual_check_local`, fora do versionamento. A matriz inclui 420x720, 480x800 e 600x1024, com texto normal e ampliado 2x.

A integração não confirma mão retirada por visão computacional nem estado real da porta. Não usar este front sozinho para comandar hardware. Evidências de câmera real, Orange Pi, IA e vídeo permanecem pendentes até execução reproduzível.

## Preparação da IA

- `vision_provider.js` define o contrato interno entre a interface e a cascata real de visão.
- `edge_vision_service.py` recebe a captura em memória, chama Rekognition e, quando necessário, Gemini; devolve somente o resultado normalizado e nunca salva a imagem.
- A cascata definida para produção usa AWS Rekognition como análise primária e solicita Gemini quando o resultado é genérico, conflitante, sensível a erro ou fica abaixo do limiar de confiança configurado. A confiança isolada não é suficiente: controles e calculadoras podem receber rótulos incorretos com confiança alta.
- A etapa complementar já preserva a mesma captura em memória e identifica a origem final como `AWS_REKOGNITION` ou `GEMINI_FALLBACK`.
- O modo padrão continua simulado. O modo `vision=remote` usa o serviço local em `http://127.0.0.1:8765/vision/analyze`.
- A captura real é entregue somente em memória ao provedor. O mock não lê, copia, envia ou persiste a imagem.
- Ao trocar de tela, a análise pendente é cancelada. Depois do resultado, a referência da captura é liberada.
- As credenciais e o SDK permanecem fora do navegador. O bridge usa somente `boto3` e não depende de PostgreSQL.
- O `Vision API Tester` de `develop` serviu como referência do cliente AWS. Quando Gemini não está configurado ou indisponível, o fluxo segue para revisão manual em vez de inventar uma classificação.
- `tests/live_remote_front.test.cjs` valida, de forma opt-in, que uma imagem percorre câmera sintética, Edge, Rekognition e a tela final do Totem. Informe os casos em `BINGO_LIVE_VISION_CASES`; o teste fica ignorado na suíte comum para não consumir a API por acidente.

### Rodar a visão local

Instale a dependência do bridge:

```powershell
python -m pip install -r edge-requirements.txt
```

Defina as credenciais AWS e `GEMINI_API_KEY` somente no ambiente do processo, usando `edge.env.example` como referência, e execute:

```powershell
python edge_vision_service.py
```

Health check: `http://127.0.0.1:8765/health`. A resposta informa os provedores ativos e o modelo Gemini, sem expor credenciais.

O serviço aceita apenas JPEG ou PNG de até 5 MB, fica restrito ao loopback por padrão e nunca registra o conteúdo da imagem. Não coloque credenciais AWS ou Gemini no HTML, JavaScript ou URL do Totem.

## Primeiro acesso e PIN

- A conta demonstrativa `Ana Clara M.` representa um aluno ainda não ativado e aparece identificada como `Primeiro acesso`.
- O fluxo permite criar e confirmar um PIN de quatro números, voltar, corrigir divergência e tentar novamente após uma falha simulada.
- Contas já ativadas preservam a tela normal de login por PIN.
- A ativação atual é somente visual e efêmera: o PIN não é persistido, enviado ou registrado no navegador.
- Nenhum e-mail ou telefone é solicitado, conforme a regra de minimização de dados da demonstração pública.
- O cenário oculto `Falha no primeiro acesso` permite validar erro e retry pelo painel de demonstração.
- O Predeus ainda deve conectar detecção de `is_activated`, ativação segura e reset controlado das contas de teste ao backend.

## Perfil de desempenho

- O kiosk usa delegação de eventos e evita recriar listeners a cada tela.
- Busca e PIN atualizam apenas seus componentes durante a digitação.
- Assets da próxima etapa são pré-carregados quando o navegador fica ocioso.
- Animações contínuas têm ciclos limitados e respeitam `prefers-reduced-motion`.
- Em telas pequenas, a interface ocupa o viewport inteiro sem a moldura de revisão.

## Diretriz visual do B1N

- Evitar textos longos soltos na tela; quando for instrução, deve parecer fala do B1N.
- No estado parado, o totem deve parecer aguardando toque, nao vendendo uma mensagem.
- Na etapa de PIN, o B1N deve reforçar privacidade visualmente. O asset ideal futuro é uma pose com olhos fechados ou virado discretamente para o lado.
- Em etapas em que o B1N já aparece grande, ele pode ocupar mais área visual e a fala deve ficar curta para não poluir a tela de 7 polegadas.
