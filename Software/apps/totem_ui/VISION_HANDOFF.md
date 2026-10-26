# Vision do Totem - Guia de continuidade

## Escopo atual

A camada de Vision conecta a camera do navegador ao fluxo visual do Totem sem
incorporar o backend geral do BinGo. A imagem fica em memoria durante a analise
e nao e persistida pelo front nem pelo servico Edge.

Fluxo atual:

1. `camera_controller.js` abre a camera, captura um frame e controla os estados
   visuais de captura e nova tentativa.
2. `vision_provider.js` envia a imagem ao servico Edge local e normaliza a
   resposta consumida pelo Totem.
3. `edge_vision_service.py` consulta AWS Rekognition primeiro.
4. Quando a resposta principal e inconclusiva, Gemini Flash Lite e usado como
   fallback seletivo.
5. `script.js` recebe item, confianca, provedor e decisao, e segue o fluxograma
   visual existente.

O servico nao substitui contratos de deposito, autenticacao, pontuacao ou
persistencia. Essas integracoes continuam sob responsabilidade do backend.

## Execucao local

Instale as dependencias do Edge:

```bash
python -m pip install -r edge-requirements.txt
```

Configure as variaveis descritas em `edge.env.example` somente no ambiente.
Nunca grave chaves AWS ou Gemini no repositorio.

Inicie o servico:

```bash
python edge_vision_service.py
```

Por padrao, o front consulta `http://127.0.0.1:8765`. Sirva a pasta `Software`
por HTTP e abra:

```text
/apps/totem_ui/?screen=camera&vision=remote
```

## Contrato entregue ao front

A resposta normalizada informa:

- item reconhecido;
- confianca;
- provedor usado;
- decisao de aceitar, recusar ou pedir nova tentativa;
- mensagem segura para o aluno;
- indicacao de fallback quando aplicavel.

O front nao deve depender dos nomes brutos retornados por AWS ou Gemini. Toda
traducao de labels externas deve permanecer concentrada no provider/Edge.

## Estrategia dos provedores

- AWS Rekognition e o provedor principal por velocidade.
- Gemini Flash Lite e fallback, nao uma segunda chamada obrigatoria.
- Itens apresentados na mao com resultado inconclusivo podem seguir ao Gemini.
- Contextos fortes de item nao eletronico devem ser recusados antes do fallback.
- O fallback usa timeout curto e apenas uma nova tentativa para proteger o
  desempenho no Orange Pi.
- A heuristica de pilha vertical apenas sugere o fallback; ela nunca aprova o
  item sem uma classificacao valida.

## Resultados observados

- Camera do notebook integrada ao fluxo real do Totem.
- Item, confianca e provedor chegaram corretamente ao front.
- Pilha vertical passou a ser reconhecida com maior consistencia pelo fallback.
- Gemini Flash Lite respondeu em aproximadamente 1 a 3 segundos nos testes
  repetidos de pilha vertical, enquanto o modelo anterior apresentou respostas
  muito mais lentas e erros temporarios.
- Garrafas e outros contextos claramente nao eletronicos continuam recusados.

Resultados variam com luz, enquadramento, rede e disponibilidade dos provedores.
Eles nao devem ser tratados como garantia de producao.

## Testes

```bash
node --test tests/vision_provider.test.cjs
node --test tests/camera_controller.test.cjs tests/camera_flow.test.cjs
python -m unittest tests/edge_vision_service_test.py
```

Na ultima validacao local passaram:

- 16 testes do provider JavaScript;
- 5 testes do fluxo de camera;
- 15 testes Python do servico Edge.

Tambem existem testes do primeiro acesso, fluxo geral e integracao remota em
`tests/`.

## Proximas integracoes

- Executar perfil de desempenho no Orange Pi com camera e rede reais.
- Definir com o backend como a decisao de Vision sera associada ao deposito.
- Adicionar identificador idempotente quando o contrato geral estiver pronto.
- Conectar telemetria sem enviar imagens ou credenciais ao navegador.
- Configurar chaves de producao fora do repositorio e com privilegio minimo.

