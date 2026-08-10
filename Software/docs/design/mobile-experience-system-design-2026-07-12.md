# BinGo Mobile Experience System

## Objetivo

Renovar as telas internas do app para que sejam acolhedoras, vivas e claramente pertencentes ao universo BinGo, preservando o onboarding e a estrutura do Perfil ja aprovados. A experiencia deve comunicar descarte seguro, progresso coletivo e recompensa sem saturar o B1N nem criar acoes repetidas.

## Principios aprovados

### Hotbar em carrossel completo

- A aba ativa ocupa sempre a posicao central.
- As cinco abas continuam visiveis.
- Os destinos deslizam de forma continua; nunca mudam de posicao instantaneamente.
- Icone, rotulo e area de toque se movem como uma unidade.
- Movimento reduzido troca a animacao por uma transicao curta sem deslocamento elastico.

### B1N contextual

- B1N aparece para orientar, alertar, celebrar ou explicar.
- Ha no maximo uma presenca principal do personagem por viewport.
- O personagem nao repete informacao que o titulo ou botao ja comunica.
- Cenários mostram impacto; B1N oferece significado e proximidade.
- B3N permanece exclusivo do BinBazar.

### Hierarquia de recursos

- Pontos pessoais representam evolucao individual.
- Pontos da turma representam o ciclo coletivo e o ranking.
- BinCoins sao a moeda de troca.
- Cada recurso usa rotulo, cor e iconografia propria. BinCoins usam o asset oficial da moeda, nunca um raio generico.

## Telas principais

### Inicio

- Manter o cenario atual como principal sinal visual.
- Integrar a missao ativa e a distancia do proximo setor em uma leitura continua.
- Usar B1N em uma fala contextual curta, sem criar um segundo card de missao.
- Substituir o icone isolado de `Como funciona` por uma acao textual integrada e acessivel.
- Manter uma unica CTA dominante para seguir ao Totem.
- Pontos, BinCoins e impacto devem levar a destinos distintos e previsiveis.

### Carteira

- Saldo usa a BinCoin oficial em escala suficiente para reconhecimento.
- Separar saldo atual, capacidade de resgate e movimentacoes recentes.
- O BinBazar e a unica CTA dominante.
- Historico usa sinais claros de ganho e gasto, sem depender apenas de `+` e `-`.

### Missoes

- Missao ativa recebe prioridade e progresso claro.
- Missoes futuras, concluidas e eventos SCR4P possuem estados visuais diferentes.
- Cada card comunica objetivo, progresso e recompensa sem precisar abrir a subtela.
- B1N aparece apenas para orientar a proxima acao ou celebrar uma conclusao.

### Ranking

- Posicao da turma e distancia do podio aparecem antes do ranking completo.
- Podio usa cores mais vivas e identidade escolar, mantendo legibilidade.
- Premios do ciclo ficam condensados e escaneaveis.
- Cenarios continuam como subtela contextual do ranking, nao como navegacao principal.

### Perfil

- Preservar estrutura, trilha de niveis e painel de conta aprovados.
- Reduzir o vazio vertical entre icone, valor e rotulo nos tres recursos.
- Substituir o raio de BinCoins pelo asset oficial.
- Nao alterar as demais secoes nesta rodada.

## Subtelas

### Detalhe da missao

- Responder rapidamente: o que fazer, onde fazer, qual cuidado e qual recompensa.
- Usar uma CTA final para ir ao Totem.
- Evitar repetir o mesmo passo em card, texto e botao.

### Acompanhamento no Totem

- Manter separado do projeto visual do kiosk.
- Explicar apenas a relacao app-Totem e os cuidados de seguranca.
- Preservar retorno para a missao e acesso ao Impacto sem apagar o historico.
- A futura animacao do B1N descartando corretamente entra como componente substituivel nesta tela.

### SCR4P

- `Quem e SCR4P?` explica o personagem e leva ao evento ativo.
- `Alerta SCR4P` apresenta progresso, regras e recompensa do evento.
- Roxo permanece semantico; recompensas usam roxo no contexto do evento.
- Evitar duas CTAs que levem ao mesmo detalhe.

### Impacto e cenario atual

- Antes/depois precisa mostrar o cenario, nao apenas recortes decorativos.
- Progresso usa superficie clara, barra legivel e texto de proxima meta.
- `Cenario atual` explica setores e ciclo sem competir com o ranking.
- Nenhuma grande superficie navy ou verde escuro.

### BinBazar

- B3N apresenta o saldo e acolhe o aluno apenas na entrada do bazar.
- Cada item mostra imagem, nome, custo com BinCoin e disponibilidade.
- Reservar e item indisponivel possuem estados distintos.
- Nao repetir saldo em todos os cards.

### Como funciona

- Fluxo curto: `Prepare -> Va ao Totem -> Valide -> Gere impacto`.
- B1N contextual introduz a explicacao uma unica vez.
- Conteudo de seguranca deve ser direto e separado de explicacoes sobre pontos.
- Entrada pela tela inicial e retorno claro para a origem.

### Dados da escola e redefinicao de PIN

- Manter como acoes de conta no Perfil.
- Dados da escola permanecem em painel curto.
- Redefinicao usa o teclado numerico existente e confirma o novo PIN.
- Modo piloto nao exibe acoes de conta indisponiveis.

## Componentes compartilhados

- `BingoCarouselNavigationBar`: calcula a ordem visual a partir da aba ativa e anima o deslocamento completo.
- `B1nContextMessage`: fala curta com tamanhos previsiveis e variantes orientacao, alerta e celebracao.
- `ResourceTile`: altura estavel, espacamento compacto e suporte a imagem oficial.
- `ProgressMissionCard`: objetivo, progresso, estado e recompensa.
- `BinCoinAmount`: moeda oficial, valor e rotulo acessivel.
- `InlineHelpAction`: substitui icones de ajuda isolados quando o texto reduz ambiguidade.
- `ImpactComparison`: antes/depois responsivo com enquadramento consistente.

## Movimento e acessibilidade

- Animacoes entre 180 e 320 ms, exceto brilhos ambientais lentos.
- Hotbar usa deslocamento continuo e curva suave; toque permanece disponivel durante a transicao.
- Respeitar `MediaQuery.disableAnimations`.
- Alvos de toque com pelo menos 48 px.
- Texto e estado nunca dependem somente de cor.
- Validar em 390x844, 430x932 e largura web de 1024 px.

## Navegacao e coerencia

- Cada CTA possui um destino exclusivo ou uma consequencia clara.
- Toda subtela aberta por `push` preserva retorno para a origem.
- Nao usar `pushAndRemoveUntil` dentro de missao, ranking, carteira ou impacto.
- A hotbar aparece apenas nas cinco telas principais.
- Subtelas usam seta de retorno consistente e nao duplicam a hotbar.

## Validacao

- Testes de widget para ordem e animacao da hotbar.
- Testes de responsividade das cinco telas principais.
- Testes de entrada e retorno das subtelas.
- Auditoria de CTAs repetidas, rotas sem saida e textos redundantes.
- `flutter analyze`, `flutter test` e `flutter build web`.
- Inspecao visual mobile de todas as telas e subtelas, incluindo console e overflows.

## Fora desta rodada

- Alteracoes no kiosk/Totem web.
- Backend real, sincronizacao ou autenticacao de producao.
- Criacao improvisada da animacao de descarte sem asset aprovado.
- Mudancas estruturais no onboarding ou no fluxo de PIN ja aprovados.

