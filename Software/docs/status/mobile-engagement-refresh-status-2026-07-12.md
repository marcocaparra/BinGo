# Mobile Engagement Refresh Status - 2026-07-12

## Estado

Implementado na branch isolada `feature/mobile-pin-refresh`. Ainda nao foi mesclado em `develop`.

## Entrega

- Perfil local salvo abre diretamente o app nas visitas seguintes; onboarding e PIN nao se repetem.
- Botao principal ganhou energia em movimento, profundidade mais leve e suporte a movimento reduzido.
- A rota numerica do onboarding foi substituida por etapas proprias do BinGo: preparar, ir ao Totem, validar e gerar impacto.
- Hotbar mantem as cinco posicoes fixas e move somente o indicador da aba ativa.
- Perfil reorganizado em pontos pessoais, pontos da turma e BinCoins, com trilha de niveis de 1 a 5.
- Redefinicao de PIN foi movida para o Perfil e reutiliza o `ProfileRepository`.
- Modo piloto nao oferece redefinicao de PIN nem troca de uma conta inexistente.
- O caminho `No Totem -> Impacto` preserva o historico e permite voltar sem encerrar o fluxo.
- A tela antiga de Perfil foi removida para evitar duas fontes de verdade.

## Auditoria de experiencia

Problemas corrigidos nesta rodada:

- caminho sem volta ao abrir o impacto;
- acao de PIN impossivel no modo piloto;
- estouro de layout nos recursos do Perfil em largura estreita;
- selo e progresso do nivel competindo pela mesma linha;
- itens de conta sem superficie Material para toque e feedback;
- tela legada morta que poderia receber manutencao por engano;
- teste antigo preso aos textos e conceitos do Perfil anterior.

Pontos deliberadamente adiados:

- animacao guiada do B1N descartando corretamente no Totem;
- revisao profunda de Inicio, Carteira/BinBazar, Missoes e Ranking;
- autenticacao real e sincronizacao com backend.

## Validacao executada

```powershell
flutter analyze
flutter test
flutter build web --no-pub
```

Resultado: analisador sem problemas, 24 testes passando e inspecao visual em viewport `390x844` sem erros no console.

## Visualizacao

Build web local desta rodada: `http://127.0.0.1:8096/`.

