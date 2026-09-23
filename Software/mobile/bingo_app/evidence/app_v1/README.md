# App V1 - Estado dos dados

## Local

- Nome, perfil e PIN são salvos no aparelho.
- A Home usa o primeiro nome do perfil local.
- `Marco` permanece apenas como identidade do modo piloto.

## Simulado

- Saldo e movimentações de BinCoins.
- Histórico de descartes validados no Totem.
- Pontos da turma, ranking, missões, recompensas e impacto.
- As telas demonstrativas exibem o rótulo `Dados simulados`.

## Integração pendente

- Sincronização com backend/Supabase.
- Atualizações originadas pelo Totem físico.
- Descarte e validação permanecem exclusivos do Totem. O resgate exibido no app é uma simulação local, sem integração ou retirada válida; o Notion ainda prevê resgate no Totem.

## Evidências

- `splash-390.png`
- `access-390.png`
- `home-390.png`
- `profile-390.png`
- `profile-customization-390.png`
- `wallet-movements-390.png`
- `wallet-discards-390.png`
- `wallet-movements-430.png`
- `binbazar-390.png`
- `binbazar-reward-390.png`
- `binbazar-confirmation-390.png`
- `ranking-390.png`
- `scenario-390.png`
- `impact-390.png`
- `missions-390.png`
- `how-it-works-390.png`
- `mission-detail-390.png`
- `mission-scr4p-390.png`
- `mission-detail-lower-390.png`
- `totem-guidance-390.png`
- `totem-guidance-lower-390.png`
- `ranking-430.png`
- `missions-430.png`
- `how-it-works-430.png`
- `mission-detail-430.png`
- `totem-guidance-430.png`
- versões `text-2x` de Ranking, Missões, Como funciona, Detalhe da Missão
  e No Totem em 390 e 430 px.

Ranking, Cenário Atual, Impacto, Missões, Como funciona, Detalhe da Missão,
No Totem e Carteira também são cobertos por testes em fonte 2x. A auditoria
automática de overflow percorre as telas principais em `360x800`, `390x844` e
`430x932`, com fonte normal e 2x.

## Checklist de fechamento

- [x] Ranking usa uma única imagem da Praça.
- [x] Missão ativa recebe protagonismo e os demais estados têm hierarquia própria.
- [x] Missões usam cena temática sem repetir objetivo no hero.
- [x] Detalhes de missão são informativos e não iniciam ações no Totem.
- [x] A Home é o único ponto de entrada para o guia do Totem.
- [x] Como funciona separa ação física, resultado pessoal e impacto coletivo.
- [x] No Totem usa o equipamento físico como protagonista.
- [x] No Totem termina com resumo de consulta, sem CTA para Impacto.
- [x] O Totem valida; o app apenas recebe e exibe o resultado.
- [x] Uma única fala do B1N por tela.
- [x] Retratos contextuais do B1N sem halo branco.
- [x] CTAs verdes, azuis e amarelos usam texto navy com contraste AA.
- [x] BinBazar identifica ação, confirmação e código como simulação local.
- [x] Imagens compartilhadas possuem fallback visual e semântico.
- [x] Segurança consolidada em `Pode levar`, `Peça ajuda` e `Não toque`.
- [x] Dados locais, simulados e integrações pendentes estão identificados.
- [ ] Gravar vídeo final de navegação.
- [ ] Publicar PR e registrar o link.
