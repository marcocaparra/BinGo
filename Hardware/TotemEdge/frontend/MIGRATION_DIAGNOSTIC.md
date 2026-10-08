# Migração e diagnóstico do frontend oficial do Totem Edge

> Registro histórico da primeira etapa. A integração posterior autorizada está
> descrita em [INTEGRATION_V1.md](INTEGRATION_V1.md). As comparações e pendências
> abaixo descrevem a cópia antes dessa integração, não o runtime operacional atual.

Data da inspeção: **2026-10-08**. Etapa: cópia independente e diagnóstico,
sem integração frontend ↔ FastAPI e sem operação física ou remota.

Convenções usadas neste documento:

- **[Código]**: comportamento observado na versão atual dos arquivos inspecionados.
- **[Oficial]**: decisão do escopo desta tarefa ou contrato/documento do repositório.
- **[Recomendação]**: proposta para implementação posterior; não é contrato aprovado.

## 1. Resumo da migração e fontes

**[Código]** A origem oficial `Software/apps/totem_ui/` foi copiada para esta
pasta. Foram preservados o HTML, os estilos, o JavaScript, os 42 assets da
origem e seu README. O aplicativo é um **protótipo de interação**: não possui
comunicação de negócio, autenticação real, câmera real, visão, hardware nem
registro de descartes. A cópia não transforma a demonstração em modo operacional.

Foram copiados 46 arquivos da origem: 44 permanecem idênticos byte a byte;
`index.html` e `styles.css` diferem exclusivamente em cinco referências a caminhos.
Três dependências de `Software/mobile/bingo_app/assets/` foram incorporadas
localmente. O `script.js`, inclusive toda a representação de câmera, é idêntico.
Nenhum arquivo temporário, credencial, artefato de build ou código do Simulator
foi copiado. A `.gitignore` de origem, voltada a revisões visuais, não foi copiada;
a `.gitignore` já existente no destino passou a ignorar evidências locais.

**[Oficial]** Fontes consultadas antes das alterações:

| Fonte | Papel nesta análise |
| --- | --- |
| [STATUS atual](../../../Software/docs/STATUS_12-08.md) | Situação do backend central, unidade econômica e homologação DEV |
| [Totem Edge](../README.md) | Frontend → FastAPI → camera/controller/backend remoto |
| [Backend local](../backend/README.md) e `app/` | Rotas e implementação efetivamente disponíveis |
| [Operação offline](../../../Software/docs/operacao-offline.md) | Bloqueio operacional, readiness e interface indisponível |
| [Contratos Totem/App/backend](../../../Software/docs/data-contracts-totem-app-backend.md) | Autenticação técnica, evento, resposta e idempotência |
| [Integração Supabase V1](../../../Software/docs/totem-supabase-integration-v1.md) | Functions existentes e limites da referência técnica do Simulator |
| [Fluxo físico V1](../../../Software/docs/descarte/FLUXO_ECOSSISTEMA_DESCARTE_V1.md) | Sequência física, visão, correção, recusa e recuperação |

Também foram inspecionados integralmente os arquivos de texto da aplicação,
seus assets/referências e a estrutura atual do Totem Edge. `camera/`,
`controller/` e `deploy/` são estruturas reservadas; sua existência não comprova
integração funcional. O backend local já tem código e testes próprios.

### Alterações em relação à origem

| Arquivo | Referência original | Referência independente | Ocorrências |
| --- | --- | --- | --- |
| `index.html` | `../../mobile/bingo_app/assets/fonts/Sora[wght].ttf` | `./assets/fonts/Sora[wght].ttf` | 1, preload |
| `styles.css` | mesmo caminho de Sora | `./assets/fonts/Sora[wght].ttf` | 1, font-face |
| `styles.css` | `../../mobile/bingo_app/assets/fonts/Inter[opsz,wght].ttf` | `./assets/fonts/Inter[opsz,wght].ttf` | 1, font-face |
| `styles.css` | `../../mobile/bingo_app/assets/images/Praça Central - Limpa.png` | `./assets/backgrounds/Praça Central - Limpa.png` | 2, backgrounds |

As substituições preservaram os demais bytes dos arquivos, inclusive suas
quebras de linha. As três cópias adicionais são idênticas às dependências mobile.
O README copiado mantém o contexto e a instrução de execução **da origem**;
para executar esta cópia independente, utilize os comandos da seção 11 abaixo.

### Divergências documentais relevantes

| Divergência | Evidência e encaminhamento |
| --- | --- |
| A tarefa menciona uma implementação de câmera existente | `script.js:344–361` e README de origem explicitam câmera **simulada**. Não existe implementação de captura a preservar nesta versão. Preservada a tela/animação; localizar outra versão exige evidência e revisão posterior. |
| O fluxo físico menciona Arduino | Decisão atual: Orange Pi controla diretamente os equipamentos, sem Arduino. A exigência de confirmação mecânica permanece; o ator/protocolo antigo não deve ser adotado. |
| Operação offline/trechos finais do STATUS tratam serviço local como futuro | O FastAPI local já implementa `/health`, `/local/status` e cliente `health-v1`. O código e README local descrevem seu recorte seguro atual. Não foi alterada a documentação fora desta pasta. |
| STATUS rejeita FastAPI como destino central | Refere-se ao backend central legado. Não contradiz a orquestração local FastAPI decidida para o Totem Edge. |
| UI mostra `+8` BinCoins e `+19 pts` | Valores demonstrativos na unidade antiga, preservados. O contrato oficial tem base 800/1900 e snapshots server-side; futura UI deverá exibir a resposta efetiva, sem multiplicar valores localmente. |
| Documento offline usa inserção como marco; fluxo detalhado distingue queda irreversível | Inserção no compartimento de entrada não equivale à queda interna. A recuperação deve considerar posição física/confirmabilidade, preservando o evento depois do compromisso irreversível. |
| Simulator registra eventos inválidos; fluxo físico descreve recusa sem registro | O contrato central suporta inválidos, mas não define a política de registro de recusa física. Não importar automaticamente o comportamento do Simulator. |
| Origem oferece avanço visual offline | Protótipo sem efeitos reais; não representa permissão para descartar offline. A futura operação real deverá obedecer ao bloqueio local. |

Nenhuma divergência foi resolvida com uma implementação presumida. Não foram
reabertas as decisões de origem oficial, Orange Pi sem Arduino, segredos no
backend ou Supabase como fonte de verdade. Um ou dois containers segue aberto.

## 2. Inventário dos arquivos

| Grupo | Quantidade | Finalidade / procedência |
| --- | --- | --- |
| `index.html` | 1 | Entrada, viewport, favicon, preload, montagem de `#kiosk` |
| `script.js` | 1 | 1.395 linhas: 29 telas, estado em memória, handlers, cenários e timers |
| `styles.css` | 1 | 3.971 linhas: 631 blocos, fontes, layouts, animações e overrides |
| `README.md` | 1 | README original, sem alteração |
| `assets/brand/` | 3 | Favicon e duas versões do logotipo, origem oficial |
| `assets/characters/` | 26 | B1N/personagens, variantes clean/corner e poses, origem oficial |
| `assets/items/` | 12 | Quatro objetos, três variantes cada, origem oficial |
| `assets/fonts/` | 3 | MaterialSymbols original; Sora e Inter provenientes do mobile |
| `assets/backgrounds/` | 1 | Praça Central proveniente do mobile |
| `.gitignore` | 1 | Existente, alterado para evidências, logs e bytecode locais |
| `MIGRATION_DIAGNOSTIC.md` | 1 | Este diagnóstico e plano pendente de revisão |
| `validation/verify_migration.py` | 1 | Comparação de bytes, referências, sintaxe e HTTP local |
| `validation/browser_smoke.cjs` | 1 | Comparação original/cópia e fluxos demonstrativos no navegador |

São **49 arquivos da aplicação**, incluindo README e 45 assets, mais quatro
arquivos de documentação/validação/controle: 53 no destino, sem contar evidências
ignoradas em `.validation/`. Algumas variantes de imagens não são referenciadas
atualmente, mas pertencem ao conjunto oficial e foram preservadas. Não houve
deduplicação, conversão ou otimização visual nesta etapa.

O inventário nominal completo dos assets consta no apêndice. A validação gera
`.validation/integrity.json` com caminho, tamanho e SHA-256 dos 49 arquivos da
aplicação; esse arquivo é evidência local reproduzível, não dependência de runtime.

## 3. Dependências e tecnologias

**[Código]** Aplicação estática com HTML5, CSS e JavaScript sem framework,
bundler, package.json, import de módulos ou compilação. Não há CDN, SDK Supabase,
API de terceiros, WebSocket ou dependência do Totem Simulator.

- Fontes locais: Sora variável, Inter variável e subconjunto Material Symbols
  Rounded com ligadura `back_hand`. Não há fonte remota.
- PNGs locais, SVGs inline gerados por funções de ícones e backgrounds CSS.
- Navegador moderno: template literals, optional chaining, nullish coalescing,
  URLSearchParams, Set, Pointer Events, Grid/Flex, CSS variables, `clamp()`,
  `100dvh` e safe-area. `requestIdleCallback` tem fallback para `setTimeout`.
- Delegação de eventos em `#kiosk`, updates parciais de busca/PIN, preload da
  próxima tela via `new Image()`, imagens com decode assíncrono e sem drag.
- Layout vertical; abaixo de 900px ocupa viewport completo, acima usa moldura
  de revisão com proporção 7/12. Reduced motion é respeitado. Há numerosos
  overrides históricos no CSS; limpeza não foi incluída na migração.

Depois das cinco correções, os recursos de runtime ficam dentro desta pasta,
sem caminho absoluto, `../../mobile/` ou recurso externo. As query strings de
versão em CSS/JS foram preservadas. Links documentais e o harness de comparação
referenciam o repositório, mas não são dependências da aplicação servida.

**[Recomendação]** Homologar no navegador/modelo/resolução reais do Orange Pi:
touch, fontes, GPU, memória, desempenho das imagens e layout físico de 7".
O smoke Windows não comprova desempenho ARM ou legibilidade em centímetros.
Instalação/systemd/container não foi configurada.

## 4. Fluxo atual do frontend

**[Código]** `screens` define as telas; `render()` substitui o conteúdo de
`#kiosk`; `handleKioskClick()` interpreta atributos `data-*`. Não há router,
sessão autenticada nem estado server-side.

| Etapa / IDs de telas | Comportamento observado | Natureza |
| --- | --- | --- |
| `sleep`, `idle` | Botão acorda interface; Iniciar descarte avança, exceto cenário unavailable | Interação real da UI; disponibilidade simulada |
| `identity` | Participar com perfil ou contribuir só com turma | Escolha real; vínculo ainda demonstrativo |
| `segment`, `year`, `class` | Três segmentos, anos/séries fixos e letras A–D; turma apenas segue para safety | Dados estáticos, sem UUID ou escola real |
| `student` | Vinte nomes fixos; busca por teclado touch com normalização de acentos e ordenação pt | Filtro real sobre dados simulados; mesma lista para qualquer turma |
| `pin` | Conta quatro teclas, permite Apagar e OK; não armazena nem valida os dígitos | Autenticação simulada: qualquer sequência de quatro teclas passa |
| `safety` | Declaração sem risco abre; risco chama responsável (`teacher`) | Declaração real de interface; não é sensor nem certificação de segurança |
| `opening`, `insert` | 2,2s altera `doorStatus` para open; aluno declara que inseriu um item | Abertura e inserção não confirmadas fisicamente |
| `hand-confirm`, `door-progress` | Declara retirada da mão; 3,2s altera porta para closed | Declaração de usuário; fechamento simulado |
| `camera` | Grid CSS, scan-line, texto AO VIVO e badge Câmera simulada; 2,8s avança | Sem preview/captura real |
| `classification` | 2,4s resolve cabo padrão, recusa ou incerteza segundo cenário | Visão simulada, sem imagem ou request |
| `secondary-analysis` | 2,6s sempre resolve como eletrônico/cabo | Gemini simulado; sem negativa, inconclusivo persistente ou erro técnico |
| `recognized`, `correct-item`, `review` | Confirma ou escolhe candidato/unknown; edição em rascunho, revisão final | Interação real sobre inferência e categorias estáticas |
| `computing` | 4,5s marca mecanismo e registro completos | Queda e registro simulados; não há resposta de backend |
| `post-drop-recovery` | Pending só em RAM; botão Restabelecer conexão marca complete e success imediatamente | Recuperação visual sem persistência/retry |
| `success` | Exibe +19/+8 fixos e Registro simulado; 6s ou Concluir reinicializa | Recompensas e confirmação simuladas |
| `unavailable` | Entendi retorna ao descanso; sem consulta de disponibilidade | Cenário demonstrativo, não check de rede |
| `rejected`, `return-progress`, `return-confirm` | Solicita devolução; 2,2s exibe compartimento aberto; Retirei reinicializa | Nenhum atuador/sensor; não registra evento |
| `connection-interrupted` | Falha antes do ciclo final; orienta recuperação do objeto | Conexão simulada |
| `mechanical-error`, `teacher` | Orienta chamar responsável e permite reset pela interface | Falha/intervenção simuladas; não comprovam equipamento seguro |

`jump()` contém guardas em memória para abertura, fechamento, classificação,
revisão e sucesso. `next()`, `back()`, navegação de revisão e parâmetros de URL
não constituem uma máquina de estados autoritativa. O histórico guarda índices
de telas, não snapshots físicos ou transações.

Categorias locais: battery, cable, phone, small e unknown. Candidatos primários:
cable/small/phone; secundários: cable/battery/small. A opção unknown fica disponível
somente para `recognitionOutcome=electronic`. A origem usa VISION_PRIMARY ou
VISION_SECONDARY até correção, que usa USER_CORRECTED/UNIDENTIFIED. Esses valores
de visão não são `category_source=AI_CONFIRMED` do contrato remoto; falta adaptação
explícita. O rótulo genérico small não estabelece um código canônico oficial.

Query params `screen`, `scenario`, `demo`, `mode`, `segment`, `year`, `class`,
`student`, `search`, `searchActive` e `pin` controlam a revisão. `?screen=success`
pré-configura conclusão sem executar ciclo. Pressionar o logo por 2s abre painel
de cenários. O cenário risk do painel não aciona automaticamente a triagem;
o botão de risco da tela safety é que conduz a teacher. São facilidades do
protótipo, não um modo real autorizado ou um controle de acesso.

## 5. Diagnóstico da câmera

**[Código]** A análise exata da tela `camera` (`script.js:344`) e dos blocos
`.camera-preview`/`.camera-frame` no CSS confirma:

| Responsabilidade | Implementação atual |
| --- | --- |
| Inicialização | Não existe: sem `getUserMedia`, enumerateDevices, SDK ou cliente local |
| Preview | `div` com backgrounds CSS, scan-line e textos; não há `<video>` nem stream |
| Captura de fotografia | Não existe canvas, drawImage, toBlob, takePhoto ou botão de captura |
| Armazenamento temporário | Não existe fotografia em RAM, Blob, data URL, arquivo ou storage |
| Envio/processamento | Não existe upload/FormData/HTTP; classifiers apenas alteram variáveis por timer |
| Desativação | Não existe dispositivo/MediaStreamTrack ativo para encerrar; mudar tela remove o DOM e `render()` limpa o timer de avanço |
| Permissões atuais | Nenhuma permissão de câmera/microfone é solicitada; somente leitura de recursos estáticos |

Fotos de objetos em `assets/items/` ilustram resultados pré-definidos; não são
fotos capturadas do compartimento. O texto AO VIVO não comprova acesso a câmera.
Toda essa implementação foi preservada sem modificação.

**[Oficial]** `camera/` deverá concentrar inicialização, preview, captura e acesso
às imagens; FastAPI orquestra e intermedeia o frontend. A UI poderá manter
apresentação, instruções, enquadramento visual e estados de carregamento/erro.
Não há código de captura do navegador a transferir neste checkout.

**[Recomendação]** Definir o contrato de preview e captura com o componente
camera antes de adaptar a tela. Formato de stream/imagem, ciclo de vida,
retenção, privacidade e cancelamento exigem aprovação; não foram criados paths
ou protocolos. A classificação remota deve receber imagem pelo backend local,
sem credenciais de visão no browser. WebSocket/SSE/JPEG/WebRTC não foi escolhido.
Se houver proposta futura de captura por navegador, ela depende de revisão
explícita da responsabilidade já definida e de secure context/permissão de
câmera; **esta migração não adotou essa alternativa**.

## 6. Inventário das comunicações externas

**[Código]** Não existe chamada HTTP de negócio, fetch, XMLHttpRequest,
WebSocket, EventSource, SDK de serviço, bridge nativa ou acesso a GPIO. Nenhum
Supabase, FastAPI, classificador ou gateway é chamado. As únicas requisições
são de recursos estáticos para o servidor que hospeda a interface:

| Arquivo / função | Método e destino | Enviado / recebido e finalidade | Falhas atuais | Integração futura |
| --- | --- | --- | --- | --- |
| `index.html`, carregador do browser | GET `./styles.css?v=…`, `./script.js?v=…` | Nenhum payload de negócio; CSS/JS | Erro de browser, sem fallback de aplicação | Manter recursos locais; origem de hospedagem a definir |
| `index.html`, links favicon/preload | GET favicon/logo/Sora local | PNG/TTF para marca e preload | Sem handler de erro | Nenhuma adaptação de negócio |
| `styles.css`, font-face/background | GET três TTF e background local | Fonte/imagem; antes dependia da árvore mobile | Fallback CSS de fonte; sem alerta operacional | Caminhos já corrigidos nesta etapa |
| `script.js`, assets/itemMedia/talk/render | GET PNGs locais em `<img>` | Ilustrações de marca, personagem e item, não fotografias capturadas | Sem onerror/placeholder de erro; decode async | Manter assets, tratar imagens reais separadamente no futuro |
| `script.js`, preloadNextScreenAssets/scheduleAdjacentPreload | GET assets da próxima tela via `new Image()` | Preload oportunista com cache Set; sem dados de aluno | Sem retry/status de falha; fallback de agendamento | Continua recurso visual; não antecipa comandos físicos |
| `script.js`, applyReviewParams | Leitura de `window.location.search`, sem request próprio | Parâmetros locais alteram UI e estado demonstrativo | Valores parcialmente não validados | Isolar ferramentas de revisão antes de operação real |

Não existem headers técnicos, tokens, secrets, base URL remota, tabela ou campo
de payload de descarte na aplicação. Não foram adicionados mocks de serviço.
O servidor estático usado na validação não é uma integração backend de negócio.

## 7. Funcionalidades reais, simuladas e ausentes

**[Código]** Funcionam realmente como interface: navegação, opções aluno/turma,
busca sobre lista fixa, teclado touch, contador PIN, declaração de segurança,
confirmação da mão, correção em rascunho, revisão, ilustrações, animações,
pré-carregamento e reset. Isso não valida a semântica operacional dos botões.

São simulados: identidade/contexto, PIN, disponibilidade, estados de porta,
câmera, visão/Gemini, conclusão mecânica, registro, conectividade, recuperação
e pontos. Algumas telas identificam explicitamente a simulação, mas não há um
banner global com a mensagem completa exigida pelo documento offline.

Não implementados: sessão de backend, IDs reais/contexto escolar, catálogo
autoritativo, validação de PIN, fotografia, auditoria original/correção,
comandos e feedback físicos, liveness/readiness local, eventos idempotentes,
recuperação durável, saldo/histórico/ranking/resgate e expiração de sessão.
Saldo/histórico/ranking/resgate não possuem telas nesta aplicação; Functions de
leitura disponíveis não justificam criar novas funcionalidades nesta etapa.

## 8. Estados, segurança e riscos técnicos

**[Código]** O estado é exclusivamente variável JavaScript: `currentIndex`,
`historyStack`, `flowMode`, seleção de aluno/turma, busca/PIN, `safetyConfirmed`,
`handConfirmed`, `doorStatus`, estados de classificação/revisão/mecanismo/registro
e candidatos. Não há localStorage, sessionStorage, IndexedDB, cookie de sessão,
event_id, UUID ou vínculo com evento persistido.

| Risco observado | Efeito numa futura operação real | Encaminhamento recomendado |
| --- | --- | --- |
| Timers assumem abertura, fechamento, queda, registro e sucesso | Avançar com porta travada, objeto não recebido ou registro sem confirmação | Transições comandadas por confirmações do backend/controller; timer apenas de UX/timeout |
| PIN é contador e aluno é nome de lista fixa | Autenticação fictícia, identidade/turma erradas | Contexto/UUID e confirmação oficial pelo backend; não persistir/logar PIN |
| Não há event_id nem payload durável | Replay pode duplicar registro/pontos; reload perde ciclo irreversível | Backend deve preservar um único ID e payload por ciclo e reusar até resolução |
| Reload/reset apaga pending; botão de recuperação assume sucesso | Texto Registro preservado não corresponde a persistência; descarte pode ser perdido logicamente | Recuperação durável server-side e resultado confirmado; UI reanexa ao ciclo existente |
| Cliques dependem só de estado/DOM; não há trava de operação/idempotência | Ações repetidas, requisições tardias e reentrância podem acionar movimento duas vezes | Serialização e validação backend, bloquear ações enquanto pendentes; UI sozinha não garante unicidade |
| `back()` repõe índice, sem desfazer flags/estado físico | Navegação pode mostrar etapa incompatível com equipamento | Navegação permitida pelo estado autoritativo; retorno físico precisa de confirmação |
| Falha mecânica/teacher permitem reset; devolução não confirma fechamento | Liberar novo ciclo com posição física desconhecida | Bloqueio até recuperação automática comprovada ou intervenção autorizada |
| Query params configuram estados completos e aceitam valores livres | Atalho para sucesso/etapas proibidas; valores interpolados em innerHTML trazem risco de injeção DOM | Isolar revisão em modo explícito; validar dados e renderizar conteúdo externo como texto |
| +8/+19 fixos; small e VISION_PRIMARY/SECONDARY não são contrato canônico | Recompensa/categoria/origem divergentes | Consumir snapshots oficiais e aprovar mapeamento; sem regras econômicas no cliente |
| Secondary sempre aceita; cenário offline não mede disponibilidade | Aceitar objeto em erro de IA ou liberar operação sem readiness | Distinguir falha técnica, incerteza, recusa e eletrônico; leitura segura do status local |
| Demo conserva cenário após reset, com painel por long press | Misturar revisão e operação real ou manter erro demonstrativo inesperado | Definir isolamento de demonstração, sem caminho de escrita real |
| Interface não trata resource/network failure operacional | Falhas de carregamento/serviço não conduzem a estado seguro medido | Erros explícitos na futura integração, sem fallback para sucesso demonstrativo |

`render()` limpa o timer principal de avanço; reset limpa seleção/histórico e
fechamento do teclado, mas não oferece recuperação transacional nem cancelamento
de trabalho externo. Cancelar na UI hoje apenas zera variáveis. O estado da
devolução pode permanecer doorStatus=opening enquanto a tela diz aberto; reset
atribui closed sem feedback físico. Nenhuma dessas flags é evidência mecânica.

**[Oficial]** Depois da queda interna irreversível, o descarte físico não pode
ser descartado logicamente. Timeout, reload ou encerramento da UI **não podem
criar outro event_id, mudar o payload, apagar a pendência ou repetir o comando
físico**. Retry do registro deve usar o mesmo ID/payload; criação 201 e replay
200 precisam de corpo válido. 409 requer diagnóstico, não um UUID substituto.
Falhas 401/404/422 e respostas perdidas não autorizam a UI a fingir confirmação.
Novos ciclos continuam bloqueados se há indisponibilidade crítica ou recuperação.

**[Recomendação]** Persistir intenção/estado antes de autorizar o ciclo
irreversível e definir reconciliação no reinício, inclusive falha entre movimento
e confirmação de software. Tecnologia, schema local, estados e protocolo de
retomada ainda exigem aprovação; persistência no navegador não resolve sozinha
o estado do equipamento. Nenhum armazenamento ou endpoint foi implementado aqui.

## 9. Proposta de integração com FastAPI

### Contratos locais já existentes

**[Código]** O backend foi inspecionado sem alteração:

- `GET /health` → HTTP 200 `{"status":"ok"}`: saúde do processo local,
  sem consulta remota; nunca usar para liberar descarte.
- `GET /local/status` → HTTP 200, `Cache-Control: no-store`, status OFFLINE,
  can_start_deposit false e mensagem documentada. Faz uma consulta central
  quando configurado, mas permanece bloqueado mesmo se ela for saudável.
- `LocalStatusService.check_status()` separa `StatusSnapshot.central_backend`
  da resposta local. Resultado central não é exposto como autorização operacional.
- Cliente HTTP autenticado `GET /functions/v1/health-v1`, headers técnicos
  exclusivamente server-side. Timeouts, erro de conexão/autenticação, HTTP ou
  resposta inesperada mantêm indisponibilidade segura. Não há polling/cache de
  readiness nem endpoints locais de contexto/PIN/sessão/câmera/controller/descarte.

Exemplo da resposta local atual:

```json
{
  "status": "OFFLINE",
  "can_start_deposit": false,
  "message": "Totem temporariamente indisponível. Estamos sem conexão no momento."
}
```

**[Oficial]** Não retornar ONLINE nem liberar descartes sem verificações reais
de câmera, visão e controller. Health central é apenas uma parcela da prontidão.
HTTP 200 local não equivale a operação permitida. O frontend deverá falhar
fechado se o serviço local estiver inacessível ou o corpo for inválido. Nesta
etapa, nenhuma dessas chamadas foi adicionada ao frontend.

### Ações, dados, dependências e pendências

Tudo que aparece como integração futura abaixo é **[Recomendação]** apoiada
nas responsabilidades oficiais. Contratos locais adicionais são pendentes de
aprovação; seus caminhos, métodos, payloads e mecanismos de atualização não
foram definidos ou implementados.

| Funcionalidade | Implementação atual | Integração futura | Dependências | Pendências |
| --- | --- | --- | --- | --- |
| Saúde do processo | Não consultada | Consumir `/health` somente para diagnóstico/liveness | FastAPI existente | Política de uso em operação |
| Disponibilidade inicial/reverificar | Cenário unavailable e botão Entendi | Consultar `/local/status`; apresentar message e bloquear por can_start_deposit=false | Rota existente e futuras verificações locais reais | Aprovar momento/validade dos checks; sem fixar polling |
| Iniciar/retomar/encerrar sessão | Variáveis em RAM/reset | Pedir estado autoritativo ao FastAPI, incluindo ciclo pendente antes de permitir novo início | Orquestração/persistência local | Contrato local e timeout/cancelamento de sessão |
| Contexto/turmas/alunos | schoolTree, letras e nomes estáticos | FastAPI consulta `totem-context-v1` e entrega dados públicos scoped, com IDs oficiais | Máquina provisionada e Function existente | Contrato local, loading/empty/error e seleção por UUID |
| Identificação/PIN | Contador de teclas | Solicitar confirmação por `totem-student-pin-v1` via FastAPI; receber confirmação e identidade pública | Contexto válido, PIN real, backend central | Contrato local; coleta efêmera, limites e limpeza; sem JWT legado |
| Triagem/retirada da mão | Botões e flags | Enviar declaração do usuário à sessão; backend decide próxima transição | Projeto mecânico e controller | Contrato de ação; nenhum detector de mão/quantidade previsto na V1 |
| Abrir/fechar/devolver | Timers e flags | Solicitar ação; exibir resultado real, falha ou recuperação | Controller no Orange Pi, sem Arduino | Contratos locais/controller e feedbacks reais |
| Preview/fotografia | Grid e scan-line | Exibir preview fornecido pela camada camera; captura orquestrada após fechamento confirmado | Camera + controller + FastAPI | Transporte/formato, privacidade, ciclo de vida e contrato local |
| Classificação/secundária | Cabo e cenários por timer | Backend envia imagem à visão; retornar decisão/candidatos de exibição | Camera, provedor primário, Gemini quando incerto | Contrato local de visão, falha técnica/inconclusivo e readiness real |
| Confirmar/corrigir categoria | Lista estática e draft | Comunicar escolha; backend mantém saída original e valida categoria/origem | Visão, catálogo oficial e sessão | Mapeamento canônico e auditoria sem inventar campos no registro remoto |
| Confirmação final/queda | Timer computing | Solicitar autorização ao backend; registrar intenção durável, conferir serviços e acompanhar confirmação mecânica | Controller, recuperação local, backend central | Contrato local e marco irreversível/retomada aprovados |
| Registro/retry | registrationStatus em memória | Somente backend chama `register-deposit-v1`, com mesmo ID/payload após falha | Function existente, persistência local e ciclo confirmado | Contrato local de resultado/pendência; sem repetir queda |
| Resultado/sucesso | +8/+19 e timer | Receber confirmação e snapshots oficiais; só então exibir sucesso e limpar UI | Registro 201/200 validado | Formato local de apresentação e tratamento de erro; sem cálculo econômico |
| Recuperação após queda | Botão marca complete | UI consulta/retoma ciclo preservado; backend reenvia mesmo evento, bloqueando novo ciclo | Estado durável/reconciliação no reinício | Confirmação/remediação de conflitos e intervenção autorizada |
| Resumo/ranking | Sem telas/chamadas | Se solicitado em etapa própria, FastAPI pode usar `totem-student-summary-v1`/`totem-rankings-v1` | Functions oficiais existentes | Fora do fluxo atual; não criar nova funcionalidade automaticamente |

Informações necessárias à futura UI: contexto público e identidade confirmada,
estado autoritativo da sessão/etapa, ações permitidas, porta/ciclo confirmados,
preview quando disponível, decisão de visão/candidatos, resultado de registro e
pendência/erro seguro. Isso descreve necessidades, **não define campos de um
novo contrato local**. PIN, secrets, logs internos e respostas brutas de provedor
não devem ser enviados como estado público.

Exclusivo do backend local: credenciais da máquina/provedores, autenticação
técnica remota, sessão/idempotência, persistência e reconciliação, comando de
controller, ciclo de vida da câmera, envio à visão, validação das transições,
chamadas de Functions e tratamento de falhas. Exclusivo do backend central:
regras econômicas, validação central e persistência definitiva de eventos/saldos.

### Reuso dos contratos centrais, sem novos contratos remotos

**[Oficial]** A integração V1 documenta Functions existentes; os caminhos
`/bingo/*` pertencem ao gateway do Simulator e **não** são rotas do FastAPI local.
`POST /v1/deposits` é conceitual: usar a Function nativa existente na futura
implementação, sem presumir alias. Não copiar arquitetura/browser client do Simulator.

| Contrato central existente | Dados relevantes / reuso |
| --- | --- |
| GET `health-v1` | Já usado pelo backend: AVAILABLE, can_start_deposit, scope=CENTRAL_BACKEND, checked_at; não cobre IA/hardware |
| GET `totem-context-v1` | Máquina/escola públicas, turmas e alunos ACTIVE scoped; sem PIN/hash/email/Auth UUID |
| POST `totem-student-pin-v1` | class_id, student_id, pin de quatro dígitos ASCII; confirmed e identidade pública, sem studentToken |
| POST `register-deposit-v1` | Os sete campos oficiais: event_id, class_id, student_id nullable, is_valid, detected_type, waste_category_code, category_source |
| POST `totem-student-summary-v1` | student_id scoped; leitura de saldos/histórico/snapshots, caso uma futura funcionalidade seja aprovada |
| GET `totem-rankings-v1` | Rankings scoped à escola, caso uma futura funcionalidade seja aprovada |

Os campos do registro não incluem imagem, quantidade, size, machine_id,
school_id ou pontuação. Evidência original da visão/correção é requisito do fluxo,
mas seu mecanismo de auditoria deve ser definido sem acrescentar campos não
contratados à Function. Escola/máquina são derivadas da autenticação técnica.
Recompensas vêm dos snapshots retornados, não de valores da interface.

Transições que exigirão confirmação real: liberação inicial, identificação,
porta aberta, porta fechada, imagem disponível, classificação válida, decisão
final aceita, ciclo mecânico concluído, registro confirmado e equipamento apto
para nova sessão. Declaração da mão continua declaração do usuário, não sensor.
Animações e temporizações podem permanecer como apresentação/timeout, jamais
como comprovação das etapas físicas ou do registro.

## 10. Sequência recomendada de implementação

**[Recomendação]**, após revisão/aprovação desta entrega:

1. Resolver as divergências de versão/câmera e formalizar contratos locais de
   sessão/ações/consulta de estado, captura/preview, controller e recuperação.
   Definir quais confirmações físicas existem e o marco irreversível.
2. Aprovar origem da UI, proteção de Host/origem/CORS e modo de demonstração.
   Mesmo processo/origem ou servidor separado depende da decisão futura de
   deploy. Não há configuração de CORS/static serving no FastAPI atual.
3. Integrar primeiro somente status local seguro e estados de falha, mantendo
   descarte bloqueado com o backend atual; definir a atualização dos checks sem
   instituir cadência/polling não aprovado.
4. Implementar sessão/contexto/PIN atrás do FastAPI, removendo dados/atalhos demo
   do caminho real sem expor credenciais e mantendo identidade pública por UUID.
5. Implementar controller e camera no equipamento, integrar visão e feedbacks
   reais. Homologar falhas e segurança mecânica antes de qualquer descarte real.
6. Implementar persistência/reconciliação local e testar reinícios, resposta
   perdida, duplo comando e falha no marco irreversível antes de habilitar queda.
7. Integrar registro oficial idempotente e snapshots, recuperação e encerramento.
   Só habilitar ONLINE após prontidão completa e homologação no Orange Pi.

Essa sequência não autoriza nenhuma etapa adicional neste trabalho.

## 11. Testes executados e reprodução

Para executar apenas a interface copiada, dentro de `Hardware/TotemEdge/frontend/`:

```powershell
python -B -m http.server 8092 --bind 127.0.0.1
```

Abrir `http://127.0.0.1:8092/`. Se necessário, trocar somente a porta. Não usar
`file://` como validação de carregamento. Não são necessários backend local,
Supabase, credenciais ou acesso à câmera para este protótipo.

Validação reproduzível, na mesma pasta:

```powershell
python -B validation/verify_migration.py
node --check script.js
node --check validation/browser_smoke.cjs
node validation/browser_smoke.cjs
git diff --check
```

O verificador usa Python padrão e Node para sintaxe. O smoke usa Playwright
**já instalado** em `Software/apps/admin_web/node_modules/playwright` e Edge
headless disponível no Windows, sem instalar dependências ou usar código do
Simulator. Em outro ambiente, fornecer caminhos de ferramentas equivalentes:

```powershell
$env:PLAYWRIGHT_MODULE = 'caminho/para/playwright'
$env:BROWSER_EXECUTABLE = 'caminho/para/chromium-ou-edge'
node validation/browser_smoke.cjs
```

As ferramentas não são dependências do produto. Os testes abrem servidores
HTTP efêmeros em loopback, bloqueiam requests de browser para outras origens,
encerram servidores/browser e guardam relatórios/capturas/perfil temporário
apenas em `.validation/` (ignorado). O smoke usa relógio virtual para verificar
as temporizações originais sem esperar todo o ciclo real de demonstração.
Não consulta FastAPI, Supabase, IA ou hardware.

| Verificação | Resultado |
| --- | --- |
| Comparação dos 46 arquivos de origem | 44 idênticos; 2 com somente as cinco substituições autorizadas |
| Três dependências mobile | Byte a byte idênticas às fontes |
| Referências estáticas | 39 ocorrências verificadas, sem referência de runtime fora da pasta |
| HTTP com frontend como raiz independente | 49/49 arquivos, HTTP 200 e corpo idêntico ao disco |
| Sintaxe JS da aplicação | `node --check`: aprovado |
| Sintaxe do harness | `node --check`: aprovado |
| Comparação no navegador | 29/29 telas com DOM idêntico; imagens carregadas e fontes sem erro |
| Comparação visual | Sleep, camera e success: três pares de PNGs idênticos em 600×1024 |
| Fluxos demonstrativos | 10/10 aprovados: ciclo aluno/PIN/sucesso/reset, indisponibilidade, análise secundária/correção unknown, recusa/devolução, falha antes da queda, perda de pending no reload, recuperação visual sem resposta, falha mecânica, triagem de risco e modo só turma |
| Erros de carregamento/console e destinos externos | Zero erros em 730 requisições locais; nenhuma requisição a serviço externo |
| Preservação dos diretórios protegidos | Hashes agregados antes/depois idênticos para UI original, Simulator, backend local e BinGoVision; alterações preexistentes do backend preservadas |
| `git diff --check` | Aprovado; nenhuma alteração nova fora do frontend no status Git |

Evidências locais: `.validation/integrity.json`, `.validation/browser.json` e
seis screenshots original/cópia. Browser: Edge Chromium 154.0.4258.62 headless,
viewport 600×1024. As execuções iniciais encontraram uma regex de inventário e
um seletor de teste ambíguo, corrigidos no harness; a aplicação não foi alterada
para acomodar os testes. A execução final passou sem pendências de teste.

Limitações explícitas: smoke em Windows/navegador desktop, uma resolução vertical;
não homologou câmera física (inexistente na UI), GPIO, segurança mecânica, IA,
Supabase real, contrato frontend/FastAPI, modo kiosk do SO, containers ou execução
ARM. Abrir corretamente não comprova essas integrações. As falhas/recompensas
dos fluxos exercitados são exclusivamente demonstrativas.

## 12. Pendências e decisões que exigem aprovação

- Revisar este diagnóstico antes de autorizar comunicação frontend ↔ FastAPI.
- Confirmar eventual versão diferente de câmera, se esperada: o checkout oficial
  analisado só contém a representação simulada. Não substituir por Simulator
  ou protótipo antigo de visão sem evidência/aprovação.
- Aprovar contratos **locais** adicionais e modo de entrega de estado/preview;
  não há novos endpoints criados ou caminhos propostos como oficiais.
- Definir feedback mecânico e intervenção segura, com Orange Pi direto, e
  recuperação durável antes de habilitar descarte irreversível.
- Aprovar política de recusa física/registro inválido, situações com classes
  diferentes e auditoria da saída original/correção; não presumir regra do Simulator.
- Definir mapeamento entre opções visuais e catálogo canônico; consumir unidade
  e snapshots oficiais, sem economia no frontend.
- Aprovar validade/atualização de readiness e isolamento de demonstração/revisão;
  nenhum intervalo de polling foi oficializado.
- Definir hospedagem/origem/proteção local e depois estratégia de um/dois
  containers, modelo/OS do Orange Pi e homologação touch/ARM.

Esta entrega encerra a primeira etapa. Não houve integração, deploy, Docker,
commit, merge, push ou alteração fora de `Hardware/TotemEdge/frontend/`.

## Apêndice — caminhos de assets preservados

<!-- Lista nominal gerada dos arquivos copiados; não é código de runtime. -->

- `assets/backgrounds/Praça Central - Limpa.png`
- `assets/brand/favicon-bingo-totem.png`
- `assets/brand/logo_bingo_sem_slogan.png`
- `assets/brand/logo_bingo_sem_slogan_clean.png`
- `assets/characters/b1n_apontando_esquerda_compartimento_web.png`
- `assets/characters/b1n_apontando_esquerda_compartimento_web_clean.png`
- `assets/characters/b1n_b3n_dupla_binbazar_web.png`
- `assets/characters/b1n_celebrando_punhos_web.png`
- `assets/characters/b1n_comemorando_bracos_abertos_web.png`
- `assets/characters/b1n_dormindo_kiosk_idle_clean_web.png`
- `assets/characters/b1n_dormindo_kiosk_idle_recorte.png`
- `assets/characters/b1n_dormindo_kiosk_idle_uncropped_white_web.png`
- `assets/characters/b1n_duvida_pergunta_corner_norm_web.png`
- `assets/characters/b1n_duvida_pergunta_corner_norm_web_clean.png`
- `assets/characters/b1n_duvida_pergunta_web.png`
- `assets/characters/b1n_ideia_instrucao_corner_norm_web.png`
- `assets/characters/b1n_ideia_instrucao_corner_norm_web_clean.png`
- `assets/characters/b1n_ideia_instrucao_web.png`
- `assets/characters/b1n_ideia_instrucao_web_clean.png`
- `assets/characters/b1n_joinha_confirmacao_corner_norm_web.png`
- `assets/characters/b1n_joinha_confirmacao_corner_norm_web_clean.png`
- `assets/characters/b1n_joinha_confirmacao_web.png`
- `assets/characters/b1n_joinha_confirmacao_web_clean.png`
- `assets/characters/b1n_lupa_analise_web.png`
- `assets/characters/b1n_lupa_analise_web_clean.png`
- `assets/characters/b1n_privacidade_pin_olhos_fechados_corner_norm_web.png`
- `assets/characters/b1n_privacidade_pin_olhos_fechados_corner_norm_web_clean.png`
- `assets/characters/b1n_privacidade_pin_olhos_fechados_web.png`
- `assets/characters/b1n_segurando_bincoin_recompensa_web.png`
- `assets/characters/b1n_segurando_bincoin_recompensa_web_clean.png`
- `assets/fonts/Inter[opsz,wght].ttf`
- `assets/fonts/MaterialSymbolsRounded-back-hand.ttf`
- `assets/fonts/Sora[wght].ttf`
- `assets/items/descarte_cabo_usb_cutout.png`
- `assets/items/descarte_cabo_usb_cutout_clean.png`
- `assets/items/descarte_cabo_usb_web.png`
- `assets/items/descarte_celular_smartphone_cutout.png`
- `assets/items/descarte_celular_smartphone_cutout_clean.png`
- `assets/items/descarte_celular_smartphone_web.png`
- `assets/items/descarte_mouse_item_pequeno_cutout.png`
- `assets/items/descarte_mouse_item_pequeno_cutout_clean.png`
- `assets/items/descarte_mouse_item_pequeno_web.png`
- `assets/items/descarte_pilha_bateria_cutout.png`
- `assets/items/descarte_pilha_bateria_cutout_clean.png`
- `assets/items/descarte_pilha_bateria_web.png`
