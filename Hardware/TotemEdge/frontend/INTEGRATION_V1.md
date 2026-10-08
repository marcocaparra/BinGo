# Totem Edge V1 — integração local e limites atuais

Entrega de 2026-10-08, posterior ao [diagnóstico de migração](MIGRATION_DIAGNOSTIC.md).
O frontend oficial continua sendo derivado de `Software/apps/totem_ui/`.
As mudanças estão somente no frontend/backend do Totem Edge, na branch atual
`feature/totem-edge-backend-foundation`, sem commit, deploy ou alterações remotas.

## Resultado e execução

O FastAPI serve a interface e a API na mesma origem. O modo padrão consulta a
API local, apresenta indisponibilidade segura e consulta a sessão preservada.
O processo **não está operacional**: `/local/status` permanece OFFLINE/false,
inclusive com health-v1 saudável. Não há controller, simulação de controller,
GPIO ou câmera física nesta entrega. Não há descarte real habilitado.

Na pasta `Hardware/TotemEdge/backend/`:

```powershell
uv sync --locked
uv run --locked uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

Abrir `http://127.0.0.1:8000/`. Para o protótipo explicitamente isolado:
`http://127.0.0.1:8000/?runtime=demo`. A demonstração mantém a navegação,
ilustrações e câmera visual da origem, mostra aviso global e não chama APIs
de negócio. Parâmetros como `screen=success` são ignorados no modo padrão.
O long press do painel de cenários existe somente na demonstração.

Servidor estático isolado continua servindo demonstração, mas o modo padrão
precisa da API da mesma origem e falha fechado se ela estiver ausente.
Não foram criados CORS amplo, base URL pública ou configuração de secrets no JS.
O README copiado da origem e o diagnóstico descrevem a etapa anterior;
este documento e o README backend descrevem a integração atual.

## Decisões e divergências

**Oficial nesta tarefa:** FastAPI orquestra; Orange Pi direto sem Arduino;
Supabase continua autoridade de identidade e economia; não há sensor de mão;
câmera deve ser ativada na preparação da abertura e capturar somente após
fechamento confirmado, com estabilização inicial de 1,5s; sem driver escolhido.

**Restrição final prevalente:** não implementar ou simular o controller, nem
criar arquivos/documentação/testes desse componente. As capacidades físicas
são apenas pontos bloqueados na orquestração. Os testes desta entrega são de
serviços/estados SQLite; fixtures de linhas persistidas não simulam movimentos.
Por isso abertura, fechamento, iluminação, escotilha e devolução física **não
foram implementados ou testados como movimentos**.

**Observado no repositório:** a câmera da UI é um grid CSS/scan-line sem vídeo,
stream, fotografia ou getUserMedia. O gateway real de visão do Simulator usa
Rekognition/Gemini e saída `status/itemId/candidateIds/confidence/origin`; foi
inspecionado como referência e não copiado. `Hardware/BinGoVision/` não foi
alterado nem tratado como implementação vigente. O texto Arduino do fluxo
antigo e a pendência local do documento offline são históricos; não anulam as
decisões atuais. O documento offline deve ser lido junto do marco irreversível
da queda interna: recuperar o evento existente não permite novos ciclos offline.

**Pendentes:** contratos de preview, resultado canônico de visão, correção e
auditoria; `small` não define uma categoria oficial; não adotar automaticamente
o fallback por erro técnico do gateway como política física. Não implementar
registro de recusa inválida ou manejo de objetos de classes diferentes sem regra
aprovada. Esta entrega recusa a continuação e exige devolução/intervenção,
sem registrar evento válido. Não introduz regra econômica ou endpoint remoto.

## Arquitetura resultante

| Componente | Responsabilidade implementada |
| --- | --- |
| `app/main.py` | Lifespan, cliente HTTP compartilhado, SQLite, composição, origem local, erros sanitizados e arquivos estáticos selecionados |
| `app/config.py`, `clients/supabase.py` | Configuração server-side, health, contexto, PIN e registro por Functions existentes |
| `app/central_contracts.py` | Payload de sete campos e projeções tipadas das respostas centrais, sem calcular pontos |
| `app/routes/sessions.py` | Contratos HTTP locais documentados antes de sua implementação |
| `app/services/sessions.py` | Disponibilidade, sessão, autenticação, triagem, declaração da mão, cancelamento seguro, retry e conclusão |
| `app/cycles.py` | Estados/snapshot e transições lógicas permitidas |
| `app/storage.py` | SQLite transacional, slot único, payload imutável, journal e recuperação no startup |
| `app/services/capture.py` | Interface interna de câmera/visão sem implementação concreta ou rota; falhas/simulações bloqueadas |
| `frontend/local_api.js` | Somente HTTP local, timeout, validação de status/snapshot/recibo, sem secrets/storage de eventos |
| `frontend/operational.js` | Interface dirigida por estado backend, identificação por UUID, PIN efêmero, avisos/pendência/sucesso confirmado |
| `frontend/script.js` | Protótipo original preservado, inicializado apenas em demonstração explícita |

Não há framework novo, SDK Supabase, ORM, polling ou sincronizador. Usados
SQLite da biblioteca padrão, HTTPX já existente e componentes pequenos.
O backend serve apenas entrada, JS/CSS selecionados e assets; não expõe README,
SQLite, arquivos de configuração ou seleção arbitrária de arquivos por query.

## Estados e confirmações

| Estado | Semântica e liberação |
| --- | --- |
| IDENTIFYING / AUTHENTICATING | Sessão lógica/aluno pendente; PIN encaminhado à Function, nunca gravado |
| SAFETY | Identidade central confirmada ou modo turma scoped; declaração de risco pendente |
| PHYSICAL_BLOCKED | Declaração segura recebida; nenhuma abertura, LED ou ativação física foi solicitada |
| OPENING / DOOR_OPEN / CLOSING / DOOR_CLOSED | Reservas de estados para integração futura; não produzidos pelo runtime atual |
| CAPTURING / CLASSIFYING | Guardas internas de captura/visão, testadas sem rota pública; exigem estado fechado |
| REVIEW | Resultado interno de visão aceito; contrato de correção/mapeamento local ainda pendente |
| RETURN_REQUIRED | Recusa exige devolução física futura; bloqueia registro e novo ciclo |
| HATCH_IN_PROGRESS | Reserva crítica: se encontrada em reinício, fica INDETERMINATE, nunca presume queda |
| REGISTRATION_PENDING | Confirmação física persistida e payload completo; retry manual do mesmo evento |
| REGISTERING | Requisição central em curso, claim transacional impede duplicação concorrente |
| REGISTERED | Recibo central validado e persistido; só aqui a UI exibe sucesso e snapshots |
| INDETERMINATE / TECHNICAL_FAILURE | Sem conclusão física confiável ou falha crítica; bloqueia cancelamento e novos ciclos |
| CANCELLED | Preparação encerrada antes da etapa física, sem pontuação |
| COMPLETED | Usuário encerrou registro confirmado; recibo e histórico preservados |

O botão Retirei a mão só declara a retirada em DOOR_OPEN. Sua operação local
registra a declaração e responde 503 enquanto falta integração física;
não fecha porta nem muda para fechado. Repetição é recusada. Não há sensor
ou análise de mão. Apenas avisos e timers visuais existem no modo operacional;
nenhum timer altera movimento, classificação, registro ou sucesso.

## SQLite e recuperação

`BINGO_SQLITE_PATH` é configurável; default absoluto em `backend/.data/totem.sqlite3`.
O exemplo `.env` usa `.data/totem.sqlite3` relativo ao diretório de execução do
backend. Pode futuramente apontar a volume persistente; Docker não foi preparado.

- UUID criado pelo backend uma vez por ciclo; command_id permite replay do início.
- Tabelas locais `cycles` e `transitions`, schema local versão 1. Não são tabelas
  Supabase e não modificam nenhum schema central.
- Slot ativo único, transações BEGIN IMMEDIATE, WAL, synchronous FULL, CAS de
  estado/versão e trava do SO para uma instância por arquivo.
- Um único processo/worker por arquivo. Outra instância falha ao abrir a trava,
  evitando que seu startup reconcilie o trabalho do primeiro processo.
- Payload oficial imutável persistido em REVIEW antes de uma futura etapa
  irreversível. Nenhuma rota aceita esse payload ou confirmação física do browser.
- Confirmação física tem campo reservado e permanece false em sessões produzidas
  hoje. Não há setter/rota/runtime que a fabrique. A retomada só aceita registro
  já persistido com confirmação, payload consistente e escopo central correspondente.
- Fingerprint não secreto de destino/máquina bloqueia replay em outro ambiente ou
  máquina; não usa a API key e permite sua rotação. Secrets/PIN/imagem não entram no SQLite.
- Saída de visão tipada pode ser preservada internamente; imagem fica em memória.
  Auditoria da correção depende do contrato/mapeamento pendente.
- Reinício pré-físico cancela a preparação preservando o UUID. Estados físicos
  críticos sem evidência viram indeterminados e mantêm o slot bloqueado.
- REGISTERING interrompido com confirmação física conhecida volta a pending;
  retry usa mesmos sete campos/event_id. Falha central conserva pending/erro seguro.
- Registro confirmado sobrevive ao reinício; novo retry devolve o recibo local,
  sem chamada adicional. Finish libera o slot, preservando UUID, recibo e journal.
- Corrupção/versão incompatível/trava indisponível não recriam silenciosamente
  o banco. É necessária recuperação autorizada; não há rota manual de reconciliação.

Não há fila de novos descartes offline, apagamento de pendência pelo browser,
substituição de event_id em erro, nem auto-retry periódico. O replay do registro
não executa outra etapa física. No runtime atual não são produzidos eventos
fisicamente confirmados; os testes exercitam recuperação de registros controlados.

## Integrações efetivamente funcionais e bloqueadas

**Funcionando:** servir UI/assets pelo FastAPI, consulta de status seguro, consulta
de sessão persistida, erro/reconsulta, isolamento da demonstração, clientes reais
de health/contexto/PIN/register com contratos tipados, estados lógicos e retry
de registro previamente confirmado. Testes usam transporte central controlado.

**Preparado, mas bloqueado no runtime normal:** seleção de contexto/turma/aluno,
PIN e triagem, pois o status atual não comprova disponibilidade completa. Seus
contratos são exercitados em testes isolados de identificação/triagem; o gate
controlado dos testes não é opção de configuração da aplicação e não habilita
ONLINE. Nenhum Supabase hospedado foi consultado nesta tarefa.

**Câmera/visão:** Protocols internos activate/capture/deactivate e classify,
Frame/Observation com simulated=true por default. Ausência, erro, bytes vazios,
resultado simulado ou inconclusivo não viram descarte válido. Não há driver,
stream, serviço HTTP de visão escolhido ou implementação migrada do Simulator.
Não há caminho público de classificação ou cadastro a partir de imagem simulada.

**Físico:** não implementado, simulado ou homologado. Não há confirmação de
abertura/fechamento/escotilha produzida. O ciclo completo permanece bloqueado.

Resumo/rankings centrais foram inspecionados e não receberam novos clientes/
telas locais nesta etapa, pois não participam das ações atuais da UI oficial.

## Contratos locais e pendências de aprovação

Ver [LOCAL_API_V1.md](../backend/LOCAL_API_V1.md) para métodos, paths, requests,
responses, validação, erros e idempotência das novas operações estritamente
lógicas. `/health` e `/local/status` preservam o contrato anterior.
São novos contratos desta implementação, não novos contratos remotos.

Aguardam aprovação antes de implementar: preview/captura públicos, visão/candidatos
canônicos/correção e auditoria, confirmações físicas/reconciliação/intervenção,
política de validade dos checks e habilitação operacional. Não há paths oficiais
presumidos para essas partes. Cadência de polling, containers, driver e modelo
de câmera não foram definidos. Não reabre a decisão definitiva sobre mão/câmera.

## Testes e limites da comprovação

Backend, em sua pasta:

```powershell
uv run --locked pytest -q
uv format --check -- app tests
```

Frontend, em sua pasta:

```powershell
python -B validation/verify_migration.py
node --test validation/local_api.test.cjs
node validation/browser_smoke.cjs
node validation/operational_smoke.cjs
git diff --check
```

Os testes de navegador reutilizam ferramentas Playwright/Edge disponíveis.
`PLAYWRIGHT_MODULE`, `BROWSER_EXECUTABLE` e `BINGO_TEST_PYTHON` podem indicar
instalações equivalentes; ferramentas de teste não são dependências do produto.
Relatórios, SQLite e screenshots de smoke ficam em `.validation/`, ignorados.
O smoke operacional inicia/encerra Uvicorn com credenciais centrais removidas.

| Verificação | Resultado |
| --- | --- |
| Backend Python 3.12 / 3.14 | 137/137 testes aprovados em cada versão; 84 testes anteriores preservados |
| Cliente JS local | 7 testes: contratos, rede, validação, recibo vinculado e request local |
| Integridade | 43 arquivos da origem idênticos; JS do protótipo preservado até bootstrap; estilos base preservados; 3 assets adicionais idênticos |
| HTTP estático | 51 arquivos, corpo íntegro; 41 referências locais verificadas; sintaxe de três JS aprovada |
| Demonstração | 29 telas/DOM comparados, 3 pares visuais idênticos com aviso verificado e removido apenas na captura comparativa; 10 fluxos; 811 requisições locais, zero erros |
| UI operacional | 6 verificações: FastAPI/SQLite reais indisponíveis; revisão URL ignorada/reconsulta; identificação/PIN/triagem por contratos controlados; sem promoção por timer; pending/reload/retry sem sucesso falso; recibo obrigatório; demo sem API |

Os testes de captura/visão usam imagens e respostas controladas somente em
serviços internos. Os testes de recuperação usam fixtures SQLite, **não controller
simulado**; o transporte central é mockado e não pontua banco real. A simulação
visual antiga só existe em runtime=demo, sem qualquer caminho de escrita.

Da lista obrigatória, abertura/fechamento/escotilha/devolução como movimentos
não foram exercitados porque a restrição adicional os exclui. Foram verificados
o bloqueio sem integração, duplicação de comando lógico, declaração de mão,
captura fora de sequência, retorno requerido e recuperação de estado crítico
indeterminado. Isso não equivale a validar confirmações físicas reais.

Não comprovados: GPIO, câmera física, segurança mecânica, visão ao vivo,
Supabase hospedado, desempenho ARM, SO kiosk, um/dois containers ou Docker.
Os smokes controlados não autorizam declarar o Totem operacional.

## Próxima etapa, após revisão

Revisar os contratos lógicos e aprovar as partes pendentes de visão/reconciliação.
O integrante de mecatrônica implementará as integrações físicas em trabalho
próprio. Integrar evidências confiáveis à orquestração, ciclo de vida da câmera,
auditoria da decisão e prontidão completa antes de habilitar qualquer movimento
ou descarte real. GPIO, câmera real e Docker aguardam revisão do usuário.

## Arquivos desta entrega

| Situação | Arquivos |
| --- | --- |
| Backend criados | `LOCAL_API_V1.md`, `app/central_contracts.py`, `app/cycles.py`, `app/storage.py`, `app/routes/sessions.py`, `app/services/sessions.py`, `app/services/capture.py`, `tests/test_sessions.py`, `tests/test_capture.py`, `tests/test_central_business.py` |
| Backend alterados | `README.md`, `.env.example`, `.gitignore`, `app/main.py`, `app/clients/supabase.py`, `tests/conftest.py` |
| Frontend criados | `local_api.js`, `operational.js`, `INTEGRATION_V1.md`, `validation/local_api.test.cjs`, `validation/operational_smoke.cjs` |
| Frontend alterados | `index.html`, `script.js`, `styles.css`, `MIGRATION_DIAGNOSTIC.md`, `validation/verify_migration.py`, `validation/browser_smoke.cjs` |

Assets, README original copiado, pyproject/lock e as alterações de fundação
preexistentes foram preservados. Evidências ficam ignoradas em `.validation/`.
`git diff --check` e formatação Python aprovados; não houve commit, merge,
push, deploy ou Docker. Hashes agregados confirmam preservação da UI original,
Simulator, BinGoVision, controller, docs centrais, Supabase e migrations.
