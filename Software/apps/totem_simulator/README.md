# Totem Simulator

Interface web de desenvolvimento para demonstrar o fluxo de descarte do BinGo, incluindo a análise de uma imagem antes do registro no backend.

O simulador usa a API real do backend para carregar alunos, turmas e rankings e para registrar depósitos. O navegador não acessa diretamente o banco, o Supabase ou os provedores de IA.

## Fluxo demonstrado

```text
Imagem PNG/JPG
  -> serviço local de visão
  -> AWS Rekognition
  -> Gemini Flash Lite somente quando a primeira leitura é inconclusiva
  -> decisão normalizada
  -> POST /v1/deposits
```

A imagem permanece em memória durante a análise e não é incluída no payload do depósito.

## Como abrir localmente

Para iniciar o Supabase local, o backend e a seed de demonstração, consulte `../../docs/iniciar-supabase-local.md`.

O backend deve estar disponível em `http://localhost:8000`. Aplique as migrations e a seed `Software/database/seeds/008_seed_totem_simulator_rich_demo.sql` usando o procedimento do backend. Esse arquivo é SQL, não um comando PowerShell.

Instale a dependência do serviço local de visão:

```powershell
cd Software/apps/totem_simulator
python -m pip install -r vision/requirements.txt
Copy-Item vision/edge.env.example .env
```

O comando acima parte da raiz do repositório. Preencha `.env` com as credenciais da equipe recebidas por canal privado: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION=sa-east-1` e `GEMINI_API_KEY`. O modelo usado no teste real desta entrega foi `gemini-flash-lite-latest`. O `.env` é ignorado pelo Git; o arquivo de exemplo contém somente campos vazios e parâmetros públicos.

Nesse mesmo terminal, inicie o serviço e mantenha-o aberto:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_vision.ps1
```

Sirva o frontend estático:

```powershell
cd Software/apps/totem_simulator
python -m http.server 8110 --bind 127.0.0.1
```

Abra `http://127.0.0.1:8110`. Consulte `http://127.0.0.1:8765/health` para confirmar que o serviço de IA está ligado. São três serviços distintos: frontend em 8110, visão em 8765 e backend em 8000. Abrir somente a página não liga a IA nem o backend.

Se o Python tiver outro nome ou caminho, use `start_vision.ps1 -Python CAMINHO_DO_PYTHON`. Em Linux/macOS, exporte as variáveis de ambiente e execute `python vision/edge_vision_service.py` diretamente.

Não existe etapa de build para o frontend. Por padrão, ele consulta `http://127.0.0.1:8765/vision/analyze`. Para usar outro Edge compatível, abra o simulador com `?visionUrl=URL`.

## Áreas disponíveis

- **Simulador de descarte**: escolhe turma ou aluno, recebe uma imagem, acompanha a análise e envia o resultado para `POST /v1/deposits`.
- **Informações do aluno**: consulta `GET /v1/totem/students/{student_id}/summary` e mostra saldo, turma, estatísticas e histórico recente.
- **Rankings**: consulta `GET /v1/totem/rankings` e exibe alunos e turmas.

## Acervo local de imagens

A etapa de imagem inclui 15 amostras em `assets/samples`, selecionadas por clique ou arrastadas para a área de upload/prévia. O acervo funciona sem downloads externos e não dispara análise automaticamente. Os filtros de dificuldade são estimativas para organizar testes, não resultados medidos da IA.

Há fotos de eletrônicos e controles de recusa, além de ilustrações identificadas no título. Placa eletrônica, cabo com fios expostos e duas pilhas são casos de limite: reconhecer o objeto não confirma segurança, autorização ou quantidade. O acervo não substitui avaliação com capturas reais do equipamento.

As fotos foram copiadas do acervo já existente em `tools/Vision API Tester/storage/uploads/2026/07`; as ilustrações vêm dos assets existentes de Totem e mobile. São cópias locais para teste, sem mudança nas fontes. A origem/licença das fotos externas não foi verificada para redistribuição pública.

## Resultado normalizado

O frontend recebe somente um resultado normalizado:

- `recognized`: eletrônico autorizado identificado;
- `needs-secondary`: primeira leitura inconclusiva, acionando o fallback;
- `rejected`: item não confirmado ou não autorizado;
- `itemId`: `battery`, `cable`, `phone` ou `small`;
- `confidence`: confiança entre zero e um;
- `origin`: `AWS_REKOGNITION` ou `GEMINI_FALLBACK`.

O mapeamento para `waste_category_code`, `detected_type` e `category_source` acontece no simulador. A imagem nunca é enviada ao endpoint de depósito.

## Dados de desenvolvimento

O simulador espera a escola criada pela seed `008_seed_totem_simulator_rich_demo.sql`:

- Escola Demo BinGo;
- turmas e alunos demonstrativos com PIN de quatro dígitos;
- máquina `Totem Demo 01`;
- chave técnica local `edge-demo-key`.

A chave técnica aparece no frontend somente porque este é um simulador local. No equipamento real, ela deve permanecer protegida no serviço Edge do Orange Pi.

## Testes

```powershell
node --test vision/tests/vision_provider.test.cjs
python -m unittest vision/tests/edge_vision_service_test.py
node --check app.js
```

## Fronteira com o backend

O simulador encerra sua responsabilidade ao produzir a decisão normalizada e montar o payload do depósito. Persistência, idempotência, pontuação e vínculo definitivo entre análise e descarte continuam sob responsabilidade do backend.

## Entrega e validação

Branch: `feature/totem-simulator-vision-upload`. As mudanças ficam exclusivamente em `Software/apps/totem_simulator`; o Totem aprovado em `Software/apps/totem_ui` não foi modificado.

Foram validados 16 testes do provider, 15 testes do serviço e quatro testes de navegador locais, cobrindo upload, acervo, fallback, montagem do payload e layout estreito. Os testes de fluxo do navegador usaram respostas controladas de API. Separadamente, houve chamada real via navegador usando a foto de duas pilhas: AWS pediu confirmação e Gemini retornou `battery` com confiança declarada de 0,99. Isso não mede a acurácia geral nem comprova segurança ou quantidade de itens. Registro real no banco e cálculo de pontos ainda precisam ser validados pelo responsável do backend.

### Diagnóstico rápido

- Página abre, mas não analisa: confira o terminal da visão e `/health`; mantenha o processo ligado.
- Erro de provedor: confira credenciais, permissões de Rekognition, acesso ao Gemini, rede e cotas no terminal da visão.
- Erro ao carregar turmas/alunos ou registrar resultado: confira backend em 8000, migrations, seed e credenciais técnicas da máquina.
- Porta 8765 ocupada: use o serviço compatível já ativo ou configure outra porta e informe `?visionUrl=http://127.0.0.1:PORTA/vision/analyze` na página.
