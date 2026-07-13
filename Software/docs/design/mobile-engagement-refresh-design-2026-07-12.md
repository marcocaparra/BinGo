# Mobile Engagement Refresh - Design

## Objetivo

Fazer o app BinGo ser acolhedor, responsivo e prazeroso de abrir sem copiar a aparencia do Duolingo. A referencia do Duolingo sera usada nos principios: proxima acao clara, feedback imediato, personagem com funcao, progresso visivel e baixa friccao.

## Decisoes aprovadas

- Perfil local existente abre o app diretamente no Inicio; onboarding e criacao do PIN aparecem apenas no primeiro uso.
- O Perfil concentra redefinicao de PIN, dados escolares e troca de conta.
- A hotbar mantem posicoes fixas para preservar memoria muscular. Um indicador inspirado na energia da BinCoin desliza ate a aba selecionada, e o icone ativo sobe e ganha enfase.
- O botao principal perde o brilho estatico. Uma faixa suave de energia atravessa o fundo e retorna; a sombra fica mais curta e moderna.
- A sequencia numerica do onboarding vira `Rota do descarte`, com icones de preparar, ir ao Totem, validar e gerar impacto.
- B1N aparece como orientador em momentos de decisao e conquista. Ele nao sera repetido em todos os cards.
- Pontos pessoais, pontos da turma e BinCoins permanecem recursos diferentes e visualmente distinguiveis.
- A futura demonstracao animada do descarte sera feita em Rive com estados de seguranca, insercao, validacao e comemoracao. Nao entra nesta rodada.

## Perfil

O Perfil tera um cabecalho unico com avatar temporario de iniciais, nome, turma, nivel atual e progresso ate o proximo nivel. Abaixo, um resumo visual separa pontos pessoais, pontos da turma e BinCoins. A trilha de niveis 1 a 5 substitui a lista longa de explicacoes. Uma unica fala contextual do B1N orienta a proxima acao.

As configuracoes ficam agrupadas em uma superficie compacta: personalizacao futura, dados escolares, redefinir PIN e trocar conta. A troca de conta limpa o perfil local somente apos confirmacao e retorna ao onboarding.

## Auditoria de jornada

Cada tela deve satisfazer tres perguntas: onde estou, o que posso fazer agora e como volto ou saio. A revisao inclui rotas sem saida, CTAs duplicadas, botoes que apenas repetem outra acao, labels inconsistentes, overflow, contraste, estados desabilitados e navegacao de retorno.

## Assets

Esta rodada reutiliza poses oficiais ja documentadas. O avatar do aluno usa iniciais, sem fingir que existe selecao de foto pronta. Novos assets so serao solicitados quando uma tela exigir uma pose que nao exista na biblioteca.
