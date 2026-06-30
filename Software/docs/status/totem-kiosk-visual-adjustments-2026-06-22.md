# Totem Kiosk - Ajustes visuais e assets de descarte

## Objetivo desta rodada

Aplicar o feedback visual do fluxo do totem:

- B1N grande apenas em momentos de conversa, acolhimento, espera, análise, aviso e recompensa.
- B1N pequeno no canto superior direito quando há uma ação objetiva do aluno.
- Remover títulos soltos das telas principais; a instrução deve parecer fala do B1N.
- Reduzir textos longos e melhorar distribuição visual.
- Trocar siglas de item por assets reais.

## Alterações feitas

- `script.js` reescrito em UTF-8 para corrigir acentuação quebrada.
- `styles.css` refeito de forma mais enxuta, removendo estilos antigos que competiam entre si.
- Tela idle mantém B1N dormindo em fundo branco controlado e usa `ZZZ` agrupado.
- Tela inicial passa a ter B1N grande falando diretamente com o aluno.
- Telas de ação (`turma`, `aluno`, `PIN`, `item`, `segurança`) usam B1N pequeno no canto com balão curto.
- Telas de estado/conversa (`inserir`, `análise`, `resultado`, `professor`) usam B1N grande.
- Cards de item agora usam assets reais: celular, mouse/item pequeno, pilha/bateria e cabo.

## Assets adicionados

Origem documental:

`C:\Users\gugad\OneDrive\Documentos\BinGo\Software\Frontend, UI e UX\UX e Design\Itens de Descarte`

Arquivos principais:

- `web/descarte_celular_smartphone_web.png`
- `web/descarte_mouse_item_pequeno_web.png`
- `web/descarte_pilha_bateria_web.png`
- `web/descarte_cabo_usb_web.png`
- `review/itens_descarte_review_sheet.png`
- `item_assets_manifest.json`
- `ASSET_INDEX.md`

Versões copiadas para o wireframe:

`Software/apps/totem_kiosk_wireframe/assets/items/`

## Decisão visual importante

As imagens dos itens foram mantidas em PNG com fundo branco controlado. Não foi aplicada transparência automática porque os objetos têm grandes áreas brancas e a remoção de fundo poderia cortar bordas, corpo e brilho dos assets.

## Pendências

- Validar visualmente no viewport real da tela 7 polegadas vertical.
- Ajustar copy final quando as regras de pontuação e professor forem fechadas.
- Criar estados de hardware reais: porta liberada, porta aberta, item detectado, item rejeitado e professor autorizado.
- Gerar assets específicos de item quebrado/estufado/vazando para a tela de segurança.

## Rodada de feedback tela a tela

Aplicado após revisão do fluxo no totem:

- Logo do totem trocada por versão local sem slogan (`assets/brand/logo_bingo_sem_slogan.png`).
- CTA inicial alterado para deixar claro o uso do totem: `Trouxe eletrônico? Toca aqui`.
- Removido footer de slogan/notas nas telas principais para não competir com a fala do B1N.
- Balão de fala reforçado com borda mais visível e maior contraste.
- Texto de identificação reescrito para fazer sentido com as opções: `Como você quer registrar esse descarte?`.
- Botões de identificação ajustados para `Ganhar BinCoins` e `Só ajudar minha turma`.
- Lista de turmas expandida até `3ª Série A`.
- Removido botão `Pular aluno`.
- Fala da tela de aluno ficou mais carismática e menos seca.
- Segurança agora é contextual: pilha/bateria e celular recebem alerta mais forte; cabo/item pequeno recebem checagem mais simples.
- Asset da pilha reprocessado e compensado visualmente para não parecer deslocado.
- Tela de inserção refeita: seta aponta para a esquerda, sem item flutuando no meio da tela.
- Nova tela adicionada: confirmação de que a mão está fora da abertura antes da portinha fechar.
- Resultado mudou frase para `Seu descarte move o futuro` como fala do B1N.
- Recompensas mudaram de roxo para gradiente azul-verde, alinhado à BinCoin.

Observação: a tela de revisão lateral continua sendo ferramenta de desenvolvimento. O modo kiosk final ainda deve ser separado, sem chips de tela e sem botões `Anterior/Próxima`.

## Correção de estado ativo versus descanso

Feedback aplicado: B1N não deve aparecer dormindo como tela ativa de início. O sono é estado de inatividade.

- Adicionada tela `Descanso`, com B1N dormindo e fundo mais escuro/inativo.
- A tela `Início` agora mostra B1N acordado, com fala ativa: `Trouxe um eletrônico? Eu te ajudo a descartar com segurança.`
- O botão da tela ativa virou `Começar descarte`.
- Ao finalizar resultado ou aviso de professor, o fluxo volta para `Descanso`, simulando o totem parado após uso.
- A tela de descanso acorda o fluxo e leva para `Início`.

Pendência: no produto real, a entrada em `Descanso` deve acontecer por temporizador de inatividade do kiosk, não apenas por botão de finalizar.

## Rodada de refinamento após review no celular

Feedback aplicado:

- Removido o modo visual de wireframe do HTML principal: sem painel lateral `Totem 7" vertical`, sem chips de tela e sem botões externos `Anterior/Próxima`.
- `script.js` agora tolera ausência de `screenList`, `prevBtn` e `nextBtn`, mantendo apenas navegação interna do totem.
- Tela `Descanso` mantida como estado de hibernação/inatividade, com fundo branco escurecido sutilmente em vez de card cinza.
- Tela `Início` ganhou mais presença do B1N acordado e menos vazio vertical.
- B1N de canto nas telas de ação foi aumentado levemente.
- Tela de inserção simplificada: removida camada retangular externa, mantendo abertura centralizada + seta para a esquerda.
- Indicador `MAO` na tela de segurança foi transformado em selo circular, menos parecido com quadrado solto.
- Asset da pilha recebeu ajuste visual específico em cards pequenos e no alerta de segurança.
- Tela de análise ganhou B1N maior para reduzir sensação de espaço vazio.

Pendências visuais:

- Criar asset oficial de mão fora da abertura para substituir o selo textual `MAO`.
- Revisar por screenshot real no viewport 7" vertical, porque alguns ajustes foram validados por código e servidor, não por pixel.
- Avaliar se o asset de B1N dormindo precisa de recorte manual ou versão com branco perfeitamente igual ao fundo do modo descanso.

## Rodada de refinamento - hibernação e disponibilidade

Feedback aplicado:

- Modo `Descanso` ajustado para fundo branco real, sem conceito cinza de card atrás do B1N dormindo.
- B1N dormindo ficou com baixa opacidade e sombra mais leve para simular estado de hibernação sem parecer tela ativa.
- Imagens do totem receberam bloqueio de seleção/arraste no desktop (`draggable=false`, `user-select: none` e prevenção de `dragstart`).
- Barra de análise ganhou espaçamento inferior para não ficar colada no botão `Ver resultado`.
- B1N de canto foi ampliado nas telas de ação para não parecer micro no PIN, turma, aluno e item.
- Botões/listas de aluno e teclado de PIN ganharam área de toque maior para ocupar melhor a tela vertical.
- Tela de análise passou a usar classe específica (`analysis-talk`) em vez de seletor CSS dependente de `:has()`, reduzindo risco no navegador kiosk.

Pendência visual:

- Validar no hardware real se o asset de B1N dormindo precisa de uma versão PNG ainda mais limpa. No estado atual, a tela branca disfarça melhor o fundo, mas o recorte perfeito depende do asset final.

## Rodada de alinhamento estético - sistema visual

Feedback aplicado:

- Tamanhos de B1N foram organizados por papel visual: `B1N grande`, `B1N de canto` e `B1N dormindo`.
- Criadas variáveis CSS para tamanhos de botões, listas, teclado e personagens, reduzindo divergências entre telas.
- B1N grande agora usa o balão de fala acima do personagem, com seta para baixo, reforçando a sensação de conversa.
- Botões principais, secundários e perigosos usam a mesma altura base.
- Botões de lista e teclado foram normalizados por categoria, evitando variações aleatórias de altura.
- Telas com B1N de canto mantêm personagem em tamanho fixo para não parecer que ele muda de escala a cada etapa.

Avaliação crítica desta rodada:

- A direção do balão acima do B1N grande é melhor para carisma e leitura infantil.
- O B1N de canto ainda pode variar visualmente por causa do recorte interno de cada PNG, mesmo com caixa CSS fixa. Se isso incomodar no hardware real, o ideal é gerar versões com canvas padronizado.
- A tela de turma é a única que precisa de lista mais compacta porque há muitas séries; isso é uma exceção funcional, não uma inconsistência estética.

## Padronização de assets

Decisão:

- Cada asset deve ter uma versão canônica com canvas fixo por categoria.
- Personagens devem ter categorias separadas: `character_corner`, `character_full`, `character_sleep`.
- Itens de descarte devem usar canvas quadrado padronizado e ocupar proporção visual semelhante.
- Ajustes finos de escala/posição devem ficar em variáveis CSS nomeadas, não espalhados por contexto.

Correção aplicada:

- O asset de pilha/bateria era o mesmo arquivo nas telas de seleção e cuidado, mas recebia transformações diferentes.
- Criada a variável `--asset-battery-fit`.
- Seleção e cuidado agora usam o mesmo ajuste visual da pilha para reduzir divergência entre telas.

## Rodada tela a tela - consistência e retorno

Feedback aplicado:

- Botões de início (`Tocar para começar` e `Começar descarte`) foram desafogados do rodapé com espaçamento flexível menor.
- Botão `Continuar`, `Coloquei o item`, `Minha mão está fora` e `Finalizar` também foram puxados levemente para cima.
- Adicionado botão de voltar no topo das telas do fluxo, evitando caminho sem retorno em seleção de registro, turma, aluno, PIN, item e etapas seguintes.
- A navegação usa histórico interno (`historyStack`), então saltos como `Só ajudar minha turma` voltam para a tela correta.
- O botão de voltar não aparece em `Descanso` e `Início`, mantendo essas telas limpas.
- B1N grande foi padronizado com a mesma caixa visual nas telas de início, registro, abertura, mão fora, análise, resultado e professor.
- Removidas exceções visuais que faziam `welcome`, `insert`, `hand` e `analysis` parecerem tamanhos diferentes.
- B1N de PIN recebeu mais presença visual sem abrir os olhos: removido efeito apagado/cinza e aplicado brilho sutil.
- Espaço entre B1N e barra de análise foi reduzido.
- Abertura foi subida levemente para melhorar a distribuição vertical.
- Pilha/bateria centralizada de forma consistente nas telas de seleção e cuidado usando `--asset-battery-fit`.

Regra documentada:

- Diferença de tamanho só pode acontecer quando muda o papel do elemento: `sleep`, `corner`, `big`, `list`, `key`, `primary action`.
- Não criar ajuste visual solto por tela sem variável nomeada.
- Se um asset parecer mudar de tamanho mesmo com CSS fixo, o problema provavelmente é canvas/recorte do PNG, não layout.

## Correção específica - teclado do PIN

Feedback corrigido:

- A divergência citada era no teclado numérico do PIN.
- O teclado foi separado conceitualmente dos botões gerais do fluxo.
- As teclas agora usam `grid-auto-rows: var(--tap-key)` e altura fixa, garantindo a mesma caixa para números, `Apagar` e `OK`.
- `Apagar` e `OK` usam classe `key-action`: continuam diferentes na função, mas pertencem visualmente ao mesmo keypad.
- Removida a classe antiga `key-secondary`, que fazia `Apagar` parecer um botão de outra família.

## Correção estrutural - consistência tela a tela

Problema encontrado:

- O fluxo estava sendo ajustado por exceções visuais (`welcome-talk`, `insert-talk`, `analysis-talk`, `spacer--soft`, `spacer--analysis`).
- Isso criava saltos perceptíveis ao avançar telas: B1N mudava de tamanho, logo mudava alguns pixels, botões caíam em zonas diferentes e telas pareciam de produtos diferentes.

Regra nova:

- Toda tela do totem usa slots fixos:
  - `topbar`: topo fixo com logo centralizada e etapa.
  - `content-zone`: área principal.
  - `action-zone`: área de ação inferior.
- Telas de conversa usam `screen--big` + `content-zone--big`.
- Telas de ação usam `screen--corner` + `content-zone--corner`.
- Tela de descanso usa `screen--sleep` + `content-zone--sleep`.
- Telas com dois botões usam `action-zone--stack` e uma linha de grid maior.

Métricas validadas no navegador interno em viewport vertical:

- Topbar das telas ativas: `y=60`, `h=40`.
- Logo das telas ativas: `x=571`, `y=61`, `w=104`, `h=38`.
- Content zone normal: `y=112`, `h=504`.
- Action zone normal: `y=628`, `h=76`.
- CTA normal: `y=640`, `h=64`.
- B1N grande normal: `x=477`, `y=202`, `w=292`, `h=246`.
- Balão grande normal: `x=449`, `y=112`, `w=348`, `h=78`.
- B1N de canto normal: `x=682`, `y=107`, `w=118`, `h=126`.

Exceções permitidas:

- `Descanso`: não tem topbar; usa B1N dormindo maior e branco/hibernação.
- Telas com dois botões (`Registro`, `Cuidado`) têm `action-zone--stack` e CTA principal mais alto na tela.
- Telas de lista sem CTA (`Turma`, `Aluno`, `PIN`) ocupam todo o espaço abaixo da topbar.

Critério de aprovação visual:

- Logo, topbar, B1N grande, B1N de canto, balão e CTA não podem mudar de coordenada entre telas do mesmo tipo.
- Qualquer novo ajuste de layout deve ser feito por variável ou classe de slot, nunca por margem solta em uma tela específica.

## Rodada crítica com avaliadores - correções aplicadas

Achados reais corrigidos:

- Removida dependência de CSS `:has()` no layout principal.
- Adicionadas classes explícitas:
  - `screen--no-action`
  - `screen--stack-action`
- Botão de voltar aumentado para `48x48px`, melhor para toque infantil.
- `OK` do PIN agora usa `disabled` real quando o PIN tem menos de 4 dígitos.
- Tela de segurança foi compactada: checks, card e asset de alerta menores para reduzir poluição visual.
- Telas `Inserir` e `Mão fora` foram revalidadas contra overflow.
- `Mão fora` recebeu card mais compacto para caber no slot sem corte.

Medições pós-correção:

- `insert-visual` termina 18px antes do fim da `content-zone`.
- `hand-warning` termina 20px antes do fim da `content-zone`.
- Topbar/logo permanecem fixos nas telas ativas.
- B1N grande permanece em `x=477`, `y=202`, `w=292`, `h=246` nas telas grandes padrão.
- B1N de canto permanece em `x=682`, `y=107`, `w=118`, `h=126` nas telas de ação.

Falsos positivos/observações:

- O suposto mojibake em `script.js`/`styles.css` foi falso positivo de visualização. Validação Node UTF-8 retornou `bad: false`.
- O path `Praça Central - Limpa.png` existe e o CSS contém `Praça`, sem versão corrompida do nome.
- `overflow: hidden` permanece no container do kiosk para simular tela fixa, mas telas críticas foram medidas. Se o hardware tiver viewport menor que o protótipo, será necessário novo teste real.

Notas dos avaliadores nesta rodada:

- Técnico layout/kiosk: 64/100 antes das correções; principais críticas eram `:has`, overflow e PIN disabled falso.
- UX infantil/touch: 78/100; principais críticas eram segurança densa e botão voltar pequeno.
- Consistência visual: 74/100 antes das correções; principal crítica era corte em `insert`/`hand`.

Estado após correções:

- A régua visual está muito mais estável.
- Ainda há uma decisão de produto aberta: a tela `Descanso` foge propositalmente do padrão por ser hibernação. Se quiser consistência absoluta de marca, adicionar logo discreta também no descanso.

## Rodada de polimento final - consistência visual rígida

Correções aplicadas nesta rodada:

- `topbar` subiu para `48px` de altura para comportar o botão de voltar `48x48px` sem estourar a linha.
- `screen-gap` caiu para `4px`, mantendo o começo do conteúdo em posição fixa depois da topbar.
- A logo das telas ativas foi centralizada verticalmente dentro da topbar.
- A tela de descanso recebeu `sleep-logo` discreta, sem usar a topbar completa.
- O botão do descanso voltou a usar a mesma régua visual do CTA primário.
- O cursor de clique foi removido da tela inicial ativa; a ação fica no botão.
- O marcador de etapa foi ocultado na interface final do totem, porque brigava visualmente com a logo central.
- O botão `Ver resultado` voltou para `primary-action`, mantendo a mesma família visual dos CTAs principais.

Métricas finais validadas no navegador com Edge instalado:

- Logo ativa: `x=538`, `y=81`, `w=104`, `h=38`.
- Etapa ativa: oculta visualmente; a topbar mantém apenas voltar + logo.
- Botão voltar: `x=416`, `y=76`, `w=48`, `h=48`.
- CTA principal normal: `x=416`, `y=656`, `w=348`, `h=64`.
- CTA principal em tela com dois botões: `x=416`, `y=580`, `w=348`, `h=64`.
- B1N grande: `x=444`, `y=218`, `w=292`, `h=246`.
- B1N de canto: `x=649`, `y=123`, `w=118`, `h=126`.
- Balão grande: `x=416`, `y=128`, `w=348`, `h=78`.
- Balão de canto: `x=416`, `y=128`, `w=222`, `h=68` ou `h=87` quando o texto tem duas linhas.
- `OK` do PIN fica `disabled=true` antes de 4 dígitos e `disabled=false` depois.
- Overflow visual medido: `0` nas telas `sleep`, `idle`, `identity`, `class`, `student`, `pin`, `item`, `safety`, `insert`, `hand`, `analysis` e `success`.

Critério obrigatório daqui para frente:

- Não ajustar uma tela individual com margem solta se o ajuste afetar logo, topbar, B1N, balão ou CTA.
- Qualquer alteração deve preservar a régua dos slots (`topbar`, `content-zone`, `action-zone`) e as variáveis de tamanho.
- Se uma tela precisar fugir da régua, documentar como exceção de produto antes de aplicar.

## Rodada de régua visual - B1N, balões e ações

Motivo:

- As duas primeiras telas após hibernação precisavam parecer da mesma família visual.
- O botão único da tela inicial estava muito baixo em comparação com a tela de dois botões.
- Alguns balões em telas grandes corriam risco de parecer cortados por causa do `overflow` do slot principal.
- B1N de canto parecia mudar de tamanho por causa do recorte interno diferente entre os PNGs.

Correções aplicadas:

- `idle` agora usa a mesma altura de área de ação das telas com dois botões (`screen--stack-action`).
- O botão único da tela inicial usa `action-zone--single`, ficando centralizado dentro da mesma área visual dos dois botões da tela seguinte.
- O B1N grande foi aumentado de forma moderada para `306x258`, sem voltar ao aumento exagerado da rodada revertida.
- O slot grande (`content-zone--big`) permite overflow visual controlado para evitar que o balão/rabicho pareça cortado.
- As poses pequenas receberam compensação leve por classe:
  - `character-joinha`
  - `character-doubt`
  - `character-idea`
  - `character-privacy`
- A logo permanece centralizada e sem marcador de etapa visível.

Métricas finais validadas na viewport de teste:

- `idle` e `identity`: B1N grande em `318x268`, balão em `348x78`.
- `idle`: CTA único em `y=664`, centralizado dentro da área equivalente ao grupo de dois botões.
- `identity`: botões em `y=630` e `y=706`.
- B1N de canto ficou em faixa visual próxima:
  - turma: `123x131`
  - aluno/item: `120x129`
  - PIN: `118x126`
  - segurança: `119x127`

## Ajuste fino - B1N pequeno em turma, aluno e PIN

Motivo:

- Mesmo com a caixa CSS parecida, as poses de canto ainda pareciam mudar de tamanho entre `Turma`, `Aluno` e `PIN`.
- A causa é o crop interno dos PNGs: o B1N do PIN ocupa mais área útil no arquivo, enquanto o B1N da turma tem mais respiro transparente.

Correção aplicada:

- Mantida a mesma família de layout de canto.
- Ajustadas apenas as escalas das poses pequenas:
  - `character-joinha`: escala moderada para não ficar micro na tela de turma.
  - `character-doubt`: escala quase neutra para aluno/item.
  - `character-privacy`: escala reduzida levemente para não parecer maior no PIN.

Métricas após ajuste:

- Turma: `127x136`.
- Aluno: `120x129`.
- PIN: `116x123`.

Leitura visual:

- As três poses continuam diferentes, mas agora parecem variações do mesmo personagem no mesmo slot, em vez de personagens com tamanhos diferentes.

## Correção de percepção - slot fixo para B1N pequeno

Motivo:

- A regulagem por escala ainda deixava a percepção de tamanho diferente em `Turma`, `Aluno` e `PIN`.
- O problema não era só tamanho numérico; o balão e o crop interno das poses faziam o personagem parecer mudar de escala.

Correção aplicada:

- O `talk()` passou a renderizar o personagem dentro de um wrapper fixo (`b1n-avatar`).
- Em telas de canto, `b1n-avatar` mantém sempre `118x126`.
- As poses agora são centralizadas dentro desse mesmo slot, em vez de cada imagem deslocar a própria caixa.
- A tela `Mão fora` ganhou classe específica (`screen--hand`) para não usar a mesma centralização das telas grandes simples.
- O card de mão foi levemente compactado para criar mais respiro entre card e botão.

Métricas após ajuste:

- Turma: wrapper `118x126`, imagem `123x131`.
- Aluno: wrapper `118x126`, imagem `120x129`.
- PIN: wrapper `118x126`, imagem `120x129`.
- Mão fora: card em `y=553`, botão em `y=706`, mantendo respiro visual entre os elementos.

Restrição:

- Não houve alteração em assets ou cards de item.

Restrição mantida:

- Nenhum asset de item foi renomeado, recortado ou trocado nesta rodada.
- Nenhum card de item foi unido ou redesenhado.

## Correcao critica - regua fixa de personagens e regressao de sobreposicao

Motivo:

- A rodada anterior deixou B1N grande invadindo areas de acao em telas como `Registro`, `Mao fora` e `Resultado`.
- As poses pequenas de canto continuavam parecendo mudar de tamanho entre `Turma`, `Aluno`, `PIN`, `Item` e `Seguranca`.
- A tela `Coloquei o item` estava visualmente comprimida pelo conjunto personagem + slot + CTA.

Correcoes aplicadas:

- `b1n-avatar` virou a caixa oficial de escala do personagem.
- B1N pequeno de canto ficou travado em `118x126`.
- B1N grande ficou travado com imagem em `246px` de altura, sem escalas manuais por tela.
- Foram removidas/neutralizadas regras antigas que miravam `welcome-talk img`, `insert-talk img`, `hand-talk img` e `analysis-talk img`, porque elas faziam o PNG escapar da caixa.
- O slot da tela `Inserir` foi reduzido de `156x116` para `140x98`, e a seta interna de `92x70` para `78x58`, para nao competir com o CTA.
- A tela `Mao fora` passou a usar `b1n_joinha_confirmacao_web.png`, porque o asset `b1n_ideia_instrucao_web.png` carregava mas desaparecia visualmente no fundo branco nesta composicao.

Metricas validadas na viewport `420x720`:

- B1N pequeno em `Turma`, `Aluno`, `PIN`, `Item` e `Seguranca`: wrapper e imagem `118x126`.
- B1N grande em `Inicio`, `Registro`, `Inserir`, `Mao fora`, `Analise` e `Resultado`: altura visual `246px`.
- Zero sobreposicao detectada entre B1N e botao principal.
- Zero sobreposicao detectada entre B1N e card de recompensa.
- Zero sobreposicao detectada entre balao e topbar.
- Tela `Mao fora`: pixels reais do personagem confirmados no screenshot final (`hand_dark=7729`, `hand_blue=1126`).

Arquivos afetados:

- `Software/apps/totem_kiosk_wireframe/styles.css`
- `Software/apps/totem_kiosk_wireframe/script.js`

Artefatos de verificacao:

- Screenshots finais em `Software/apps/totem_kiosk_wireframe/_visual_check/`.
- Prancha final em `Software/apps/totem_kiosk_wireframe/_visual_check/_contact_sheet.png`.

Restricao mantida:

- Nenhum asset/card de item foi alterado nesta rodada.

## Microajuste - B1N maior em telas de entrada e confirmacao de mao

Motivo:

- As telas `Inicio`, `Registro` e `Mao fora` tinham distribuicao correta, mas o B1N ainda podia ocupar um pouco mais da area livre sem afetar os demais elementos.

Correcao aplicada:

- A pose grande `character-joinha` recebeu escala visual `1.08`.
- A caixa de layout permaneceu igual; apenas o personagem cresceu visualmente.
- Nenhum botao, card, balao, asset de item ou fluxo foi alterado.

Metricas validadas:

- `Inicio`: B1N visual em aproximadamente `212.5x265.7`, sem sobreposicao com CTA.
- `Registro`: B1N visual em aproximadamente `212.5x265.7`, sem sobreposicao com os dois botoes.
- `Mao fora`: B1N visual em aproximadamente `212.5x265.7`, sem sobreposicao com card de seguranca ou CTA.

## Revisao tela a tela - descanso, seta, cards e recompensa

Motivo:

- Na tela de descanso ainda aparecia um retangulo claro do asset do B1N dormindo.
- O `ZZZ` precisava ficar mais proximo do personagem e subir como animacao de desenho.
- A seta de voltar ainda parecia texto (`<`) em vez de icone.
- Os cards de selecao de eletronico estavam com icones e textos desalinhados.
- Na recompensa, o numero precisava ter mais enfase que a unidade (`pts` / `BinCoins`).

Correcoes aplicadas:

- Criado o asset `b1n_dormindo_kiosk_idle_clean_web.png`, removendo o fundo conectado as bordas e preservando o original.
- A tela de descanso agora usa o asset limpo, sem depender de blend/mask para esconder o quadrado.
- `ZZZ` recebeu animacao individual `zzzRise`, com delays diferentes para criar leitura de subida.
- O botao de voltar agora usa `back-icon` desenhado em CSS, sem texto `&lt;`.
- Os cards de item passaram a usar grade interna fixa: midia, titulo e subtitulo alinhados ao centro.
- A recompensa separa `reward-number` e `reward-unit`: numero com peso `950`, unidade com peso `700`.

Validacao:

- Fluxo completo navegado do descanso ate recompensa na viewport `420x720`.
- Tela de recompensa confirmou pesos `950` para os numeros e `700` para as unidades.
- Capturas finais em `Software/apps/totem_kiosk_wireframe/_visual_check_feedback/`.
