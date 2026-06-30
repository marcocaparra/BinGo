# Totem Kiosk Wireframe - Status 2026-06-22

## Estado atual

Wireframe navegavel do Totem BinGo criado em `Software/apps/totem_kiosk_wireframe/`, pensado para tela touch vertical de 7 polegadas no Orange Pi com Ubuntu.

## Decisoes de UX/UI

- B1N passa a ser a voz principal do fluxo: instrucoes operacionais aparecem como fala dele.
- Estado parado do kiosk usa B1N aguardando/dormindo, sem fala, para parecer uma tela em repouso.
- Ao tocar na tela parada, o fluxo acorda e inicia a identificacao.
- Tela de PIN reforca privacidade com B1N em postura discreta.
- Tela de inserir item usa B1N apontando para a esquerda, alinhado ao compartimento fisico previsto.
- Textos usam "BinCoins" por extenso, sem abreviacao "BC" e sem "Bitcoin".
- O visual segue a linguagem clara e colorida do mobile, evitando verde escuro/navy como area dominante.
- Depois da revisao critica com agentes, as falas do B1N foram encurtadas e o texto visivel foi ajustado para PT-BR com acentuacao.
- O caminho "Só minha turma" agora pula aluno/PIN e vai direto para tipo de item.
- Celular foi tratado como item assistido: a selecao envia para tela de professor.
- A tela de analise nao usa mais o texto de prototipo "Simular aprovado".

## Fluxo atual

1. Idle do totem
2. Identificacao
3. Escolha da turma
4. Escolha do aluno
5. PIN
6. Tipo do item
7. Checagem de seguranca
8. Insercao no compartimento
9. Analise
10. Sucesso ou chamar professor

## Assets em uso

Os personagens usados no wireframe ficam em `Software/apps/totem_kiosk_wireframe/assets/characters/` e sao copias reduzidas da biblioteca oficial de personagens.

Os cutouts de privacidade e apontando para a esquerda foram aprovados apenas para superficies claras. Em fundo escuro, ainda existe halo claro nas bordas.

A pose `b1n_dormindo_kiosk_idle` foi reprovada como cutout transparente porque a remocao de fundo deformou cabeca, travesseiro, braco e perna. No wireframe, o idle usa `b1n_dormindo_kiosk_idle_uncropped_white_web.png`, sem crop, preservando o personagem inteiro em uma area branca controlada.

## Assets recomendados para proxima rodada

- Recorte profissional de `b1n_dormindo_kiosk_idle`, sem deformar travesseiro/corpo.
- `b1n_alerta_seguro`: pose atenta para pilhas, baterias e celulares.

## Validacao feita

- `node --check` do `script.js`: OK.
- Servidor local em `http://127.0.0.1:8091/apps/totem_kiosk_wireframe/`: respondeu 200.
- Assets principais do B1N no totem: responderam 200.
- PNGs de personagens do totem: `RGBA`, com alpha real.
- Revisao critica por subagentes: crianca/adolescente, UX visual, feira/professor e QA frontend.

## Pendencias

- Validacao visual final no dispositivo real ou viewport equivalente da tela 7".
- Criar/obter recorte profissional da pose dormindo apenas se o totem precisar usar essa pose fora de fundo branco.
- Criar pictogramas reais para pilha/bateria, cabo, celular e eletronico pequeno; siglas atuais ainda sao placeholder visual.
- Projetar estados de hardware mais completos: porta abrindo, item detectado, porta aberta, item incompativel e professor autorizado.
- Integrar com backend/edge local apenas depois de aprovar o fluxo visual.

## Atualizacao para continuidade em develop

- O prototipo navegavel fica em `Software/apps/totem_kiosk_wireframe/`.
- Para abrir localmente, sirva a pasta `Software` e acesse `/apps/totem_kiosk_wireframe/`.
- Comando recomendado: `python -m http.server 8092 --bind 127.0.0.1`.
- URL recomendada: `http://127.0.0.1:8092/apps/totem_kiosk_wireframe/`.
- O idle do totem agora usa `b1n_dormindo_kiosk_idle_clean_web.png`, criado para reduzir o fundo quadrado visivel do asset dormindo.
- As pastas `_visual_check*`, screenshots `_review_*.png` e logs locais foram marcados para nao serem versionados no app.
