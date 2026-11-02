# Validação automatizada do TotemEdge — 3C.2.0

Refotografia (02/11): backend completo 760 aprovados, oito novos casos HTTP;
browser dedicado com oito verificações, zero erros, usando câmera/IA controladas.
Evidências/limites em [RECAPTURE_V1.md](../backend/RECAPTURE_V1.md). Nenhum deploy,
serviço/container ou dado hospedado alterado por esses testes.

## Confirmação única e retry da mesma fotografia — 02/11/2026

Validação desta correção: FAST 108 aprovados; INTEGRATION final 604 aprovados
(559 backend, 18 runtime, 27 contratos JS), zero falhos/ignorados e exit code 0.
Os nove casos de test_vision_retry.py também passaram isoladamente, sem somar essa
repetição. Antes da ampliação final, a seleção focada de sessão/foto/fluxo/recovery
teve 99 aprovados. A primeira execução apontou expectativas antigas de cancel como
única ação e fixtures que precisavam respeitar CHECK/identidade imutável do journal;
foram corrigidas sem relaxar as garantias do backend. Um PIN ausente é 401 pelo
contrato DEV existente, preservado. A versão final respeita essas condições.

Navegador (fallback/fone, failure/retry, camera-failure, recognized/correção,
rejected): 16 verificações funcionais e nove comparações visuais estritas aprovadas,
zero erros de página e temporary_removed=true nos cinco cenários. Ref B imutável,
sem novas máscaras, tolerâncias ou snapshots aceitos. O harness aplica somente os
novos rótulos solicitados aos controles de erro e remove do roteiro a segunda tela
que deixou de fazer parte do fluxo; recognized e correct-item continuam comparados.

Cobertura: decisão com fotografia -> PIN obrigatório (sem review redundante),
PIN ausente/incorreto sem hatch; retry com UUID estável, mesmo JPEG/event/capture,
resposta perdida, clique duplo, histórico de erros/observações, conflito de ID,
concorrência e recuperação de reserva interrompida; falta de foto ou journal
inseguro impede retry; cancel seguro permite outra sessão sem recaptura/movimento
na recuperação. STARTUP testado por reconciliação SQLite com perda deliberada da
RAM e testes existentes de subprocesso interrompido; não é homologação de restart
físico de webcam/Orange Pi. Nenhuma chamada real de câmera/AWS/Gemini/Supabase.

Evidências reproduzíveis (diretórios ignorados pelo Git):
- deploy/.validation/profiles-6df50bb3728f/report.json (FAST).
- deploy/.validation/profiles-4f2c79053e41/report.json (INTEGRATION final).
- frontend/.validation/vision-session-browser.json e relatórios por cenário.
Ambos os perfis registram temporary_sqlite_removed=true. Os smokes encerram e
removem apenas suas fixtures temporárias. FULL/Docker não executado nesta correção,
respeitando a restrição de não criar containers; nenhum recurso DEV foi alterado.
Comandos executados a partir da raiz:

```powershell
python -B Hardware/TotemEdge/deploy/validate.py fast
python -B Hardware/TotemEdge/deploy/validate.py integration
# A partir de Hardware/TotemEdge/frontend:
node validation/vision_session_smoke.cjs fallback failure camera-failure recognized rejected
```

Arquivos tocados nesta correção (outras alterações locais preexistentes preservadas):
- `Hardware/TotemEdge/frontend/operational.js`
- `Hardware/TotemEdge/frontend/local_api.js`
- `Hardware/TotemEdge/frontend/script.js`
- `Hardware/TotemEdge/backend/app/services/session_vision.py`
- `Hardware/TotemEdge/backend/app/services/simulation_flow.py`
- `Hardware/TotemEdge/backend/app/routes/simulation.py`
- `Hardware/TotemEdge/backend/app/storage.py`
- `Hardware/TotemEdge/backend/app/vision_journal.py`
- `Hardware/TotemEdge/backend/tests/test_vision_retry.py`
- `Hardware/TotemEdge/backend/tests/test_session_vision.py`
- `Hardware/TotemEdge/backend/tests/test_simulation_recovery.py`
- `Hardware/TotemEdge/frontend/validation/dev_api.test.cjs`
- `Hardware/TotemEdge/frontend/validation/vision_session_smoke.cjs`
- `Hardware/TotemEdge/frontend/validation/approved_visual.cjs`
- `Hardware/TotemEdge/deploy/validate.py`
- `Hardware/TotemEdge/backend/LOCAL_API_V1.md`
- `Hardware/TotemEdge/backend/VISION_SESSION_V1.md`
- `Hardware/TotemEdge/frontend/INTEGRATION_V1.md`
- `Hardware/TotemEdge/deploy/MAIN_DEV.md`
- `Hardware/TotemEdge/deploy/TESTING.md`
- `Software/docs/STATUS_12-08.md`


Revisão final: dez testes de recuperação/foto repetidos e aprovados, incluindo
uma primária inconclusiva seguida de VISION_TIMEOUT no secundário, preservação da
foto após cancelamento e expiração apenas na próxima captura válida. Não somar
repetições ao total abaixo.

Recuperação de simulações (02/11): 93 testes backend aprovados (recovery, sessão,
foto, fluxo simulado e laboratório), 20 contratos JS aprovados. Os seis testes de
recuperação foram repetidos após acrescentar a verificação de retenção limitada
da foto: seis aprovados, sem somar essa repetição ao total. Browser camera-failure,
failure e rejected: nove verificações funcionais e três comparações visuais
aprovadas; encerramento, início seguinte e clique duplo não causam outro movimento
ou captura. temporary_removed=true nos três cenários; sem serviço hospedado real.
Consolidado: frontend/.validation/simulation-recovery-focused.json. As expectativas
antigas de nenhuma ação em falha foram substituídas por cancel como única ação,
mantendo o bloqueio de hatch. Uma primeira fixture de movimento pendente precisou
incluir active_slot para respeitar o CHECK do journal; os controles não foram relaxados.
Diagnóstico somente leitura do principal: JPEG DEVICE/42030 bytes, observação
AWS needs-secondary e VISION_TIMEOUT; logs recentes sem traceback. Isso localiza
o timeout após o principal, mas não comprova causa de rede/provedor. Nenhum prazo
ou política de provider foi modificado; nenhum dado do principal foi alterado.


Correção de classes/apresentação (02/11): tipos específicos ficam separados dos
agrupamentos legados e da categoria canônica. Backend: 158 testes focados aprovados
(test_vision, test_session_vision, test_vision_photo_flow, test_vision_lab); JS:
20 contratos aprovados. Mais dez testes de test_capture.py passaram; quarenta
 testes de sessão/foto/laboratório foram repetidos após a compatibilidade de
 journals antigos, sem reescrever observações históricas. Não somar essa repetição.
 Navegador: fallback (fone de ouvido), recognized/correção, failure e rejected:
 onze verificações funcionais e oito comparações visuais estritas aprovadas,
 zero diferenças aceitas por tolerância, zero erros de página, limpeza confirmada.
 A referência imutável recebeu somente os novos textos aprovados e o JPEG sintético
 esperado no mesmo componente. As primeiras comparações apontaram subtítulos
 removidos em excesso e o novo rótulo oficial ainda ausente no harness; corrigidos
 preservando subtítulos úteis, sem máscaras ou alteração de limites.
 Relatórios por cenário e consolidado em frontend/.validation/vision-session-focused.json.
 O primeiro teste backend apontou apenas a inclusão de
metadado vazio na observação histórica; a serialização passou a omitir defaults
vazios, preservando os metadados específicos. Os ensaios são sintéticos, sem
AWS/Gemini/webcam/Supabase reais. Sem alteração de Docker, câmera ou economia.


Atualização principal 02/11: captura/análise automáticas e fotografia no componente
de confirmação. Testes focados de visão/sessão: 38 aprovados; visão/fluxo mecânico: 161 aprovados; contratos JS: 19
aprovados. Compose principal validado sem construir ou iniciar containers. O smoke de navegador recognized passou com quatro verificações funcionais, quatro
comparações visuais estritas e temporary_removed=true. A referência usa o mesmo
JPEG sintético no componente original; não há máscara ou relaxamento de tolerância.
A primeira tentativa ainda aguardava CAPTURING após iniciar a análise automática;
o teste foi alinhado à nova transição sem aumentar prazos. Os
relatórios abaixo pertencem a rodadas anteriores, não à homologação física atual.


## Ajuste funcional 3C.3.1 — 02/11/2026

INTEGRATION inclui agora `test_vision_photo_flow.py`: foto privada/GET puro,
análise explícita idempotente, perda da foto volátil na recuperação SQLite e
perfil de identidade pelo broker existente, sem fallback sintético. O smoke
`vision_session_smoke.cjs` cobre foto no canvas, AWS, fallback controlado, resultado
visível, confirmação/correção, perda de resposta, refresh, continuidade simulada,
rejeição e falha técnica. Os controles sem contrato mecânico seguro continuam
desabilitados. A referência B, assets, máscaras e tolerâncias permanecem intactos.
No comparador, somente o provider da **página de referência** é suspenso para
manter a tela original de análise; a aplicação testada usa HTTP/SQLite/provedores
sintéticos. A prontidão visual continua exigindo fontes, imagens decodificadas,
animações/estrutura/CSS e pixels, sem depender do heurístico networkidle.

O Compose vision-dev foi validado com caminhos/arquivos sintéticos, sem iniciar
containers ou ler segredos. Usa somente seu volume e porta, e a chave de máquina
permanece exclusivamente no broker. O roteiro hospedado é opt-in em VISION_LAB.md.
Nenhum teste desta correção chama webcam, AWS, Gemini ou Supabase reais.
FAST/INTEGRATION/FULL completos não foram reexecutados nesta correção pontual;
os números da seção seguinte são históricos, não evidência do novo código.

Verificações focadas efetivamente executadas:

- `uv run --locked --offline python -B -m pytest -q tests/test_vision_photo_flow.py tests/test_session_vision.py tests/test_vision_lab.py tests/test_vision.py --tb=short`:
  150 aprovados na primeira rodada (antes de acrescentar o terceiro teste de foto).
- `uv run --locked --offline python -B -m pytest -q tests/test_vision_photo_flow.py tests/test_dev_identity.py tests/test_dev_integration.py --tb=short`:
  158 aprovados; broker/contexto/PIN, recuperação e ausência de fallback.
- `uv run --locked --offline python -B -m pytest -q tests/test_vision_photo_flow.py tests/test_simulation_flow.py --tb=short`:
  50 aprovados, incluindo o teste de marcador exclusivo após a última alteração.
- `uv run --locked --offline python -B -m pytest -q ../deploy/tests/test_validation_profiles.py ../deploy/tests/test_runtime.py --tb=short`:
  18 aprovados e 16 subtestes aprovados.
- `node --test validation/dev_api.test.cjs`: 19 aprovados. Sintaxe de seis arquivos
  JavaScript e formato dos onze arquivos Python alterados: aprovados.

As suítes backend acima se sobrepõem; os números não são somados como testes
distintos. Zero falhas/ignorados nessas rodadas. Todas usam recursos descartáveis.
O smoke browser aceita nomes de cenários opcionais (`recognized`, `rejected`,
`failure`, `fallback`) para execução focada; sem argumentos executa todos.
Relatórios por cenário ficam em frontend/.validation/vision-session-browser-*.json.
Tentativas iniciais pararam na prontidão da fixture (`ECONNREFUSED`, prazo existente
de 80 sondagens) e uma navegação da referência excedeu o heurístico networkidle.
Não foram classificadas como falha de PIN/IA nem ocultadas. Nenhum prazo foi elevado;
o comparador usa load seguido das verificações estritas de prontidão visual.

Rodadas finais de navegador, ambas exit code 0:
`node validation/vision_session_smoke.cjs failure fallback` e
`node validation/vision_session_smoke.cjs recognized rejected`.
Quatro cenários, onze verificações funcionais e **nove comparações visuais**:
estrutura/CSS/geometria/assets iguais, imagens binariamente iguais, zero pixels
ou canais diferentes, zero máscaras e tolerância zero. Rejeição/falha não emitem
hatch; os dois percursos aceitos chegam a COMPLETED com quatro comandos
SIMULATED/COMPLETED/SUCCEEDED, receipt=null e refresh sem novo POST/câmera/IA.
Todos os quatro relatórios comprovam temporary_removed=true e errors=[].
Consolidado auditável das duas rodadas em
frontend/.validation/vision-session-focused.json; capturas approved-vision-*.
Após a última alteração transacional de RAM/SQLite, test_vision_photo_flow.py
foi reexecutado separadamente: três aprovados. A formatação final foi aplicada.

3C.3.1: INTEGRATION reutiliza test_vision.py e inclui test_session_vision.py e
test_vision_lab.py; FULL inclui
vision_session_smoke.cjs, usando o mesmo harness/browser/comparador da referência B.
Câmera e IA determinísticas; JPEG entregue efetivamente ao InternalVision.
Testes incluem morte real de subprocesso durante CAPTURING/CLASSIFYING, journal,
concorrência, revisão, rejeição, falha técnica e nenhuma capacidade econômica.
Um encerramento forçado durante fallback comprova preservação da saída primária
antes de Gemini; uma falha de auditoria impede a chamada secundária.
Novo laboratório real é separado e opt-in: [VISION_LAB.md](VISION_LAB.md).
O marcador physical-return-protocol permanece pendente: não há devolução física
implementada, e objetos recusados continuam bloqueados. Não equivale a skip de
teste implementado nem a aprovação física. Não altera o comparativo histórico.

## Resultados 3C.3.1 — 01/11/2026

Rodada final sequencial, com exit code 0 em todos os perfis:

| Perfil | Aprovados | Falhos | Ignorados | Relatório local |
| --- | ---: | ---: | ---: | --- |
| FAST | 105 | 0 | 0 | .validation/profiles-7627b46440b3/report.json |
| INTEGRATION | 574 | 0 | 0 | .validation/profiles-210955d1517f/report.json |
| FULL | 756 | 0 | 0 | .validation/profiles-af0f1bb77375/report.json |

FULL: 714 backend, 18 runtime e 24 contratos JS; formato e sintaxe aprovados.
35 testes backend novos e um contrato JS novo; INTEGRATION também reutiliza
os 111 testes preexistentes de visão. Nenhuma chamada real a câmera/AWS/Gemini.
Docker: os sete grupos DEV sintéticos e oito grupos isolados foram executados
e passaram. Histórico: 29 telas, três screenshots iguais, dez fluxos; operacional:
seis verificações. DEV: 30 verificações/21 comparações; visão: sete verificações/
nove comparações. As 30 comparações B têm igualdade binária e de design, zero
pixels/canais diferentes, zero máscaras e tolerância zero. Referência a9310a6 intacta.

Teste adicional da imagem final vision_lab: build/startup e seis verificações
em container readonly, UID 10001, sem rede, sem webcam/IA reais; container removido.
Compose standalone validado com arquivos descartáveis sintéticos. Evidências
em .validation/vision-3c31-audit/lab-container-final.json e compose-check.json.

Os três perfis removeram seu SQLite temporário. Dez projetos Docker exclusivos
das duas execuções FULL tiveram containers, redes e volumes removidos.
Os 15 containers persistentes mantiveram IDs/montagens; os BinGo também mantiveram
StartedAt. SQLite/WAL dos ambientes operacional, DEV integrado e camera-lab
permaneceram byte a byte iguais. Não houve acesso hospedado, atualização do DEV
ou GPIO. Auditoria em .validation/vision-3c31-audit/isolation-final.json,
scope-check.json, visual-final.json e native-cleanup-final.json.
Nenhum processo de fixture ficou ativo. O resíduo anterior
%TEMP%/bingo-dev-ui-euhfQ5, criado/alterado em 31/10 às 01:18, foi inspecionado
somente por metadados e preservado; não foi criado nem reutilizado neste incremento.

Tentativas anteriores foram preservadas, sem aprovação retroativa:
profiles-dcb5ae75ae47 detectou leitura de UUID vazio no handshake preexistente;
profiles-50986b5ac8bc e profiles-556624cdbdd5 registraram prazos de inicialização
de subprocessos não atendidos. A primeira FULL, profiles-d2e36a894c53, teve
752 testes e os 15 grupos Docker aprovados, mas falhou na inicialização de duas
fixtures browser; não comprovou os cenários restantes nem foi declarada aprovada.
Foi medida CPU do host em 100%, sem atribuir causa única. Corrigidos publicação
atômica e imports de fixtures/test runners desnecessários em subprocessos;
dados sintéticos foram compartilhados em dev_data.py. Não aumentamos timeouts,
alteramos asserções de garantia, aceitamos snapshots ou reduzimos cobertura.

CI: workflow totem-ci.yml inspecionado, preservado e abrangendo os novos testes
pelo INTEGRATION. Sem secrets/deploy/hardware; GitHub Actions não foi executado
nesta sessão. Homologação real 3C.3.1 continua opt-in e pendente; a captura real
3C.3.0 fornecida pelo operador está registrada no STATUS e CAMERA_V1.md.

## Base histórica 3C.2.0 / 3C.3.0

Atualização 3C.3.0: testes de gerenciamento de câmera usam exclusivamente
dispositivos fictícios. FAST inclui test_camera.py; INTEGRATION acrescenta
test_camera_api.py/test_camera_capture.py/test_camera_process.py; FULL coleta todos. FFmpeg e webcam
nunca são necessários aos perfis comuns. Procedimento opt-in real e contrato
em ../backend/CAMERA_V1.md. A visão/E2E do aluno permanece pendente de integração.

Infraestrutura de regressão, sem integração funcional nova do frontend. Os runners
continuam sendo pytest, unittest e node:test. Playwright já é usado pelos dois
smokes do frontend oficial; não há outro frontend, banco ou máquina de estados.

## Preparação e comandos PowerShell

A partir da raiz do checkout (a pasta que contém Hardware e Software), com
Python >=3.12, uv 0.12.19 e Node >=22 no PATH:

```powershell
Push-Location Hardware/TotemEdge/backend
uv sync --locked
# Prepara o formatter fixado; esta preparação pode precisar de internet.
uv format --version 0.15.22 --check -- app tests ../deploy
Pop-Location

python -B Hardware/TotemEdge/deploy/validate.py fast
python -B Hardware/TotemEdge/deploy/validate.py integration
python -B Hardware/TotemEdge/deploy/validate.py full
```

Os comandos também funcionam no Linux. O script resolve diretórios pelo próprio
arquivo, independentemente do cwd; não usa caminhos pessoais. Após a preparação,
FAST e INTEGRATION usam uv offline e não precisam de Docker, internet, hardware
ou credenciais. Não há configuração TypeScript nem lint próprios no frontend;
node --check e o formatter Python são as verificações existentes aplicáveis.
O comparativo do FULL também exige Git e o commit de referência disponível no
histórico local. Não faz fetch automático; um checkout raso precisa disponibilizar
esse histórico antes do teste (em uma futura CI FULL, usar fetch-depth: 0).

| Perfil | Grupos executados | Recursos adicionais |
| --- | --- | --- |
| FAST | contratos JS, runtime/infraestrutura, sintaxe JS, formato Python, testes backend de isolamento/rotas/contratos centrais | Nenhum serviço |
| INTEGRATION | FAST e testes existentes de identidade DEV, broker, journal, fluxo simulado, sessões e transporte HTTP loopback | SQLite descartável e mocks/servidor loopback no processo de teste |
| FULL | backend completo, runtime, JS, formato, dois smokes Docker sintéticos e três smokes browser (histórico, operacional e identificação DEV) | Docker Linux/Compose com !override, imagens/dependências de build, Playwright, navegador e histórico Git |
| HOSTED DEV | somente duas leituras via ingresso local DEV já configurado: health e contexto | Opt-in explícito, broker DEV autorizado e internet; nunca CI |

FULL constrói os targets de teste; um build frio pode baixar imagens e wheels.
Isso não é tráfego de negócio: os smokes usam Functions sintéticas e rede interna.
O smoke `dev_integration_smoke` **não** é teste hospedado, apesar do nome.
O smoke operacional antigo `container_smoke.py` continua disponível conforme
VALIDATION.md, mas não é acrescentado ao FULL: os dois smokes atuais já exercitam
Compose, restart/recreate, persistência e guardas, sem criar outra bateria redundante.

Para navegador, reutiliza-se a instalação de Playwright já utilizada pelos smokes
em `Software/apps/admin_web/node_modules/playwright`, ou uma instalação de teste
explicitamente indicada:

```powershell
$env:PLAYWRIGHT_MODULE = (Resolve-Path Software/apps/admin_web/node_modules/playwright).Path
# Opcional: caminho de um navegador compatível já instalado.
$env:BROWSER_EXECUTABLE = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
python -B Hardware/TotemEdge/deploy/validate.py full
```

No Windows, os smokes detectam esse Edge se instalado. Nos demais ambientes usam
o Chromium instalado pelo Playwright. FULL não instala módulos/navegadores por
conta própria: ausência de tooling resulta em `unavailable`, sem aprovação falsa.
Os smokes individuais e seus comandos anteriores continuam disponíveis.

## Resultados, falhas e auditoria

Cada execução gera `deploy/.validation/profiles-<UUID>/report.json`, logs por grupo,
JUnit do pytest e referências/cópias das evidências dos smokes. O JSON registra
contagens de testes, estados dos grupos e remoção do diretório SQLite temporário.
Cada log é aberto antes do subprocesso; stdout/stderr são gravados diretamente
no arquivo, na ordem de chegada, com Python sem buffering. O terminal informa o
caminho e o timeout. Em outro terminal, use Get-Content -LiteralPath CAMINHO_DO_LOG
-Tail 20 -Wait para acompanhar esse arquivo, substituindo CAMINHO_DO_LOG pelo
caminho exibido, entre aspas. Não é necessário interromper o perfil para ler o log.
O relatório registra log_file, timeout_seconds e, quando aplicável, termination.
KeyboardInterrupt mantém o perfil interrompido e não é convertido em falha de
asserção. Contagens recuperadas do JUnit nesses casos ou em timeout recebem
partial_results=true: são somente os casos registrados, não aprovação da suíte.
XML parcial inválido é indicado por junit_error, sem mascarar a interrupção.
Grupos de smoke, telas e fluxos não são somados como se fossem testes unitários.
Os relatórios nativos dos smokes Docker registram os projetos exclusivos, checks
e o resultado da limpeza. Artefatos ficam ignorados pelo Git.

Código de saída `0`: grupos executáveis passaram; `1`: falha ou interrupção;
`2`: recurso indisponível, execução ainda em curso ou teste ignorado. Consulte `status`, `reason`, `tests`
e o log do grupo. Teste ignorado não equivale a aprovado. O antigo marcador
`frontend-3c2-mechanical-e2e` fica registrado nas evidências históricas abaixo;
o ciclo mecânico simulado agora é
exercitado no smoke DEV existente até COMPLETED, com retorno inicial coordenado
pelo backend. O marcador futuro frontend-3c23-vision-e2e identifica câmera/IA ainda
fora do escopo, sem contagem de aprovação. Essa pendência planejada não impede
validar a infraestrutura do 3C.2.0.

Uma falha de asserção requer comparação com a baseline; não é classificada
automaticamente como regressão. Dependência/cache ausente no uv offline exige
repetir a preparação. Docker ausente e navegador ausente são indisponibilidade.
Interrupção/timeout torna o grupo malsucedido; o relatório é salvo entre grupos.
O script continua os grupos independentes para oferecer resultado agregado.

Não use `|| true`, `continue-on-error` ou pipelines que descartem o exit code.
No PowerShell, consulte `$LASTEXITCODE` imediatamente após o comando desejado.

## Isolamento e interrupções

- O orquestrador remove configurações BINGO/Supabase/AWS/Gemini, proxies,
  opções pytest/uv/Compose herdadas e não carrega `.env`. Caminhos de ferramentas
  Playwright/navegador são as únicas opções de browser reaproveitadas.
- O pytest recebe basetemp e SQLite de coleta em TemporaryDirectory exclusivo.
  Cada teste continua usando seu tmp_path. A fixture remove credenciais e recusa
  DNS/conexões fora de loopback; transports mockados continuam funcionando.
- Os smokes Docker conservam SimulatedController, redes internas, ausência de
  devices/privilégios, broker sintético e a sentinela econômica existente.
  Projetos/volumes UUID e portas loopback efêmeras coexistem com o DEV persistente.
- O único `down --volumes` dos smokes é aplicado a seus projetos UUID registrados.
  A limpeza verifica containers, redes e volumes pelo label exato do projeto;
  falha de limpeza reprova o smoke. Não há prune ou comando contra o projeto DEV.
- A política, chave técnica sintética e chave TLS do smoke DEV são temporárias
  e removidas no finally. Nenhum arquivo de credenciais do operador é utilizado.
- O browser operacional inicia Uvicorn sem configurações centrais, usa SQLite
  temporário e só o remove depois de encerrar o processo. A UI controlada histórica
  usa rotas interceptadas; isso não comprova integração DEV mecânica no navegador.

Falha normal e Ctrl+C dão oportunidade ao finally de limpar. Encerramento forçado
do processo/host e timeout de um subprocesso podem deixar recursos próprios.
Nunca execute limpeza global: consulte o projeto UUID e os arquivos Compose de
override do relatório nativo, confira seu label e repita somente o teardown desse
projeto. Não remova volumes padrão DEV/operacionais, nem evidências antigas do
usuário. A integridade do journal/slot e o bloqueio offline continuam sendo
responsabilidade dos serviços existentes, não do runner.

## HOSTED DEV: somente por decisão explícita

Não é dependência nem etapa automática de FAST, INTEGRATION, FULL ou PR. Reutiliza
o broker restrito e a política externa de [DEV_INTEGRATION.md](DEV_INTEGRATION.md),
com máquina/escola de teste autorizadas. O runner não inicia containers, lê arquivos
secretos, recebe PIN, cria sessão ou solicita movimento. Ele apenas verifica os
dois GETs pelo ingresso local; redirects e proxies ficam bloqueados. Não imprime
corpos, identidades, credenciais ou exceções remotas. O broker existente continua
limitado às três Functions autorizadas; service_role não é distribuída ao Totem.

```powershell
# Somente com o DEV hospedado previamente autorizado e em execução:
python -B Hardware/TotemEdge/deploy/validate.py hosted-dev --allow-hosted-dev --url http://127.0.0.1:8002
```

Sem opt-in ou com CI/GITHUB_ACTIONS definido, recusa antes de qualquer conexão.
A URL aceita somente ingresso loopback, sem usuário/senha, query ou outro path.
O comando não comprova PIN hospedado ou ciclo hospedado completo; a homologação
manual anterior permanece histórica. Nenhum teste aqui homologa hardware físico.

## Cobertura e próximos incrementos

| Risco | Testes existentes reaproveitados |
| --- | --- |
| IDENTIFYING, PIN certo/errado/inválido, vínculo único, conflitos, autenticação em replay e validated_at imutável | backend/tests/test_dev_identity.py e test_dev_integration.py |
| GET sem PIN/consulta central; restart antes/depois do commit; rollback e concorrência | test_dev_identity.py, test_sessions.py e test_mechanical_journal.py |
| PIN obrigatório em open/hatch, hand_removed estrito, confirmação condicionada ao journal, COMPLETED sem recibo | test_dev_identity.py e test_simulation_flow.py |
| Idempotência, intenção/claim antes de despacho, pending/UNKNOWN, falha parcial sem redisparo | test_mechanical_journal.py, test_simulation_flow.py e smokes Docker |
| SIMULATED não vira confirmação física; nenhuma recompensa/registro real | test_controller.py, test_simulation.py, test_dev_integration.py, test_simulation_flow.py e sentinelas dos smokes |
| Offline/HTTP/erros e recibo central obrigatório | test_routes.py, test_central_business.py, test_sessions.py, local_api.test.cjs e operational_smoke.cjs |

Para 3C.2.1/2/3, acrescente testes ao cliente JS existente e, quando houver fluxo
real na UI oficial, estenda os smokes Playwright ou adote @playwright/test se as
fixtures/retries/relatórios justificarem a dependência. Não é necessário introduzir
um segundo runner agora. O backend/broker sintéticos e as políticas das fixtures
existentes são a referência; o navegador deve usar APIs locais e snapshots, jamais
abrir SQLite ou definir estado/autenticação/pontuação.

FULL coleta automaticamente novos arquivos `backend/tests/test_*.py`. Para incluí-los
também no ciclo cotidiano ou na CI, acrescente o arquivo à seleção FAST ou
INTEGRATION de validate.py. unittest descobre automaticamente novos test_*.py em
deploy/tests. Os contratos Node atuais ficam em local_api.test.cjs e dev_api.test.cjs; se surgirem
outros arquivos, inclua-os explicitamente no comando desse grupo. Ao transformar
um cenário E2E pendente em executável, substitua sua indicação de pendência pelo
grupo real e registre a evidência; não contabilize placeholders como aprovação.

E2E pendentes: seleção/associação por PIN na UI DEV; reload por GET active/event_id;
replay com IDs preservados e autenticação atual; renderização de allowed_actions;
movimentos/hand_removed pelo snapshot durável; 401/403/409/503; bloqueio em UNKNOWN;
ciclo completo com aviso SIMULATED e conclusão sem recibo/recompensa. Não registrar
esses cenários como aprovados enquanto dependerem de intercepção que fabrique a
integração. As fixtures futuras devem usar portas efêmeras, SQLite próprio,
central sintética e teardown verificável como os testes atuais.

Limitações conhecidas: o verificador histórico `verify_migration.py` compara com
uma origem que evoluiu e procura camera_controller.js ausente na cópia; não é gate
destes perfis e não foi corrigido para ocultar a divergência. O `.env.example`
operacional com início `g#` também permanece fora dos perfis. Não foram alterados
contratos de produto, schema, frontend funcional, drivers ou políticas econômicas.
Não há teste físico, desempenho ARM, manutenção/expurgo de SQLite ou E2E 3C.2.

### Referência do comparativo de migração

O frontend oficial **executado pelo TotemEdge** é Hardware/TotemEdge/frontend:
app/main.py serve essa pasta, e o Dockerfile copia seus arquivos. A origem visual
da migração é Software/apps/totem_ui na revisão efetivamente copiada, conforme
[MIGRATION_DIAGNOSTIC.md](../frontend/MIGRATION_DIAGNOSTIC.md) e
[INTEGRATION_V1.md](../frontend/INTEGRATION_V1.md), ambos de 08/10.

browser_smoke.cjs prova a preservação dessa migração, com 29 comparações de DOM,
texto/imagens/fontes, três pares de screenshots e dez fluxos demonstrativos.
Não é um teste de paridade com todas as funcionalidades futuras do protótipo.
A referência agora é o commit completo
`b4ebdc14427649d7257e1345abbf015b384e1817` (08/10/2026), que introduziu a migração
e o próprio comparativo. Os bytes são lidos diretamente do Git local e servidos
em memória: não há nova interface, snapshot gerado do frontend atual ou aceitação
automática. O relatório browser.json registra propósito, revisão e caminho.

A falha anterior tinha uma referência móvel: o teste lia a origem do checkout
atual. O commit dfe8fe5, escrito em 23/09 em outra branch e incorporado pelo merge
9f385ab em 26/10, acrescentou Primeiro acesso/student-button-label e câmera/visão.
Ele não é ancestral de b4ebdc1. Já index.html, styles.css, script.js, local_api.js
e operational.js do TotemEdge não mudaram entre b4ebdc1 e a retomada em a9310a6.
O JavaScript anterior ao bootstrap continua idêntico à origem histórica.

Diferenças autorizadas da migração: caminhos locais dos três assets incorporados,
bootstrap/API operacional e aviso de demonstração. O teste conserva a remoção
apenas desse aviso para comparar imagens e preserva todas as asserções anteriores.
Primeiro acesso, webcam e visão novos existem no protótipo atual, mas estão
ausentes do TotemEdge: isso é evolução não portada, não regressão da cópia de 08/10.
Portá-los ou exigir paridade funcional atual requer outro escopo aprovado. Alterar
DOM, texto, imagens ou estilos da cópia nos cenários comparados continua causando
falha; a referência só pode mudar mediante revisão explícita e documentada.

Essa prova histórica e os smokes operacionais não aprovam E2E DEV 3C.2.
O ajuste do relógio segue o [padrão oficial do Playwright](https://playwright.dev/docs/clock#consistent-time-and-timers).

No Windows, o smoke operacional aguarda o fechamento do processo e streams antes
de remover seu SQLite e usa retries limitados para EPERM transitório. A primeira
tentativa deixou somente um arquivo de lock em `.validation/tmp/bingo-browser-EKzfC1`;
a revisão automática bloqueou sua remoção manual. Esse resíduo não contém SQLite
DEV nem processo ativo. A execução corrigida passou nas seis verificações e
removeu seu próprio diretório; não confundir esse resultado com o comparativo acima.

## CI

O workflow Totem CI existente mantém a checagem do protótipo e acrescenta um job
Linux com o perfil INTEGRATION para mudanças em Hardware/TotemEdge. Usa Python
3.12, Node 22, uv e formatter fixados, lock existente e nenhuma secret. Não usa
pull_request_target, deploy, hosted-dev, Docker ou hardware. A execução GitHub
Actions só pode ser confirmada após publicação pelo desenvolvedor; validação
local não é evidência de execução no GitHub.

## Evidência local anterior à correção da referência — 30/10/2026

Windows/PowerShell, backend Python 3.12, runtime Python 3.14, Node 24.19.0,
uv 0.12.19, Docker 29.0.1/Compose 2.40.3 e Edge headless 156.0.4314.50.
A baseline anterior às alterações foi reexecutada: 617 backend aprovados.

| Execução final | Resultado |
| --- | --- |
| FAST | 41 backend + 14 runtime/infraestrutura + 7 JS = 62 aprovados, zero falhas/skips; sintaxe/formato aprovados |
| INTEGRATION | 327 backend + 14 runtime/infraestrutura + 7 JS = 348 aprovados, zero falhas/skips |
| FULL — testes | 620 backend + 14 runtime/infraestrutura + 7 JS = 641 aprovados, zero falhas/skips |
| FULL — Docker | 7 grupos DEV sintéticos e 8 isolados aprovados; cinco projetos UUID limpos e verificados |
| FULL — browser operacional | 6 verificações aprovadas, zero erros; processo e SQLite temporário limpos |
| FULL — comparativo visual | 1 grupo falhou pela divergência preexistente student/Primeiro acesso; FULL retornou 1 |
| Consistência | 58 arquivos Python formatados; sintaxe JS, parse YAML e git diff --check aprovados |

Os perfis se sobrepõem: não somar as contagens como testes distintos. Os dez testes
novos verificam somente a infraestrutura: três casos de bloqueio de rede e sete
testes de ambiente, opt-in, agregação/JUnit e segurança da limpeza. Os cenários de
negócio continuam nos testes existentes.

Relatórios locais ignorados pelo Git:

- FAST: `.validation/profiles-1d572de443d1/report.json`.
- INTEGRATION: `.validation/profiles-08e09d363e7e/report.json`.
- FULL final: `.validation/profiles-725c845aae0e/report.json` e logs por grupo.
- Docker DEV: `.validation/bingo-dev-integration-test-9567f97c5a23/report.json`.
- Docker isolado: `.validation/bingo-simulation-test-4758ff1f3fbc/report.json`.
- Auditoria DEV: `.validation/3c2-isolation/`, com consultas SQLite somente leitura,
  identidades dos containers e confirmação da diferença frontend já presente em HEAD.

O hash lógico do SQLite DEV foi idêntico antes/depois:
`e418067ec3ccbf8c46613e748057cd0180d94eff7ae586b9f7881da0fd7870cf`.
Conservados schema 4, um ciclo, um vínculo e quatro comandos; os três containers
DEV mantiveram IDs, instantes de início e mounts. A sentinela econômica sintética
dos smokes permaneceu inalterada. Nenhum teste hospedado ou físico foi executado.

As falhas iniciais de cache do formatter e da limpeza Windows introduzida no
harness foram corrigidas e revalidadas. A fragilidade preexistente de pauseAt foi
corrigida sem mudar UI; a divergência de conteúdo seguinte foi preservada como
falha. O gate hosted-dev sem opt-in foi exercitado e recusou antes da rede.
Não executados: hosted-dev autorizado, hardware/ARM, E2E 3C.2, verificador de
migração histórico e GitHub Actions. Naquela execução, a aprovação integral do
incremento ficou pendente da revisão do comparativo e do resíduo descrito acima.

## Retomada de encerramento — 30/10/2026

Branch feature/orange-pi-integration, HEAD inicial a9310a6 e Git inicialmente limpo.
Não foi encontrado AGENTS.md aplicável; consultados STATUS técnico atualizado em
23/10, contratos locais/centrais/offline, diagnóstico e relatório da migração.
Somente browser_smoke.cjs e este documento foram alterados. A correção fixa a
origem histórica comprovada no Git, mantendo todas as comparações e fluxos; não
porta Primeiro acesso, câmera ou visão para o TotemEdge e não antecipa 3C.2.1.

| Perfil/cenário reexecutado | Resultado atual |
| --- | --- |
| FAST | 62 testes aprovados, zero falhas/skips, saída 0 |
| INTEGRATION | 348 testes aprovados, zero falhas/skips, saída 0 |
| FULL — testes | 641 testes aprovados, zero falhas/skips; formato/sintaxe aprovados |
| FULL — comparativo | 29 telas, três pares de screenshots idênticos, dez fluxos, zero erros |
| FULL — browser operacional | Seis verificações aprovadas, zero erros |
| FULL — Docker | Dois grupos unavailable: engine Linux indisponível desde o início; não reexecutados os 15 grupos Docker históricos |
| FULL — agregado | Saída 2 por indisponibilidade; nenhuma falha de teste |
| Prova negativa do comparativo | Mutação somente em memória no bodyText de student: comparação recusada nessa tela, saída 1 esperada; arquivos da UI intactos |

Relatórios: `.validation/profiles-df521de927bb/report.json` (FAST),
`.validation/profiles-4a858ff4937c/report.json` (INTEGRATION) e
`.validation/profiles-8048582a0b14/report.json` (FULL). A auditoria adicional fica
em `.validation/3c2-closure/`: proveniência Git, prova negativa e hashes antes/depois.
Os hashes de index.html, styles.css, script.js, local_api.js, operational.js e
do workflow de CI ficaram idênticos. YAML e git diff --check passaram; o workflow
permaneceu sem alterações, secrets, deploy ou execução GitHub Actions nesta tarefa.

Todos os diretórios SQLite temporários dos três perfis foram removidos. A referência
histórica é servida em memória e não cria cópia temporária em disco. O browser
operacional removeu seu diretório; restou somente bingo-browser-EKzfC1 da tentativa
anterior. Ele foi inspecionado, sem apagar: um único lock de um byte nulo, sem
symlink, acessível por abertura exclusiva de leitura, sem indício de uso ativo.

Docker não foi iniciado nem houve comandos mutantes contra containers/volumes.
Não foram acessados Supabase hospedado, credenciais ou bancos DEV persistentes.
Com o engine desligado, a comparação atual do conteúdo SQLite dos volumes e a
revalidação Docker não puderam ser executadas; não usar hashes/resultados históricos
como se fossem desta retomada.

A divergência visual está resolvida no escopo de preservação da migração, sem
decisão de produto pendente. O encerramento integral do 3C.2.0 ainda exige
disponibilizar o Docker Linux e repetir `python -B Hardware/TotemEdge/deploy/validate.py full`.
Os E2E 3C.2 continuam planejados; não houve commit, push, merge ou deploy.

## Diagnóstico da interrupção do FULL — 30/10/2026

Execução original preservada: `.validation/profiles-4e4e4ee987e9/`.
O perfil iniciou em 30/10 às 21:24:45 no horário de São Paulo. O grupo backend
registrou interrupted após 95,56s; esse status só era atribuído no except
KeyboardInterrupt de validate.py. O timeout do grupo era 900s, tratado por
TimeoutExpired em outro ramo. Não há evidência de timeout interno ou de falha
de asserção nessa execução.

pytest.xml contém 143 casos registrados, com zero failures/errors/skips e tempo
de suíte de 79,674s. O XML foi gravado antes do report.json final. Isso comprova
progresso parcial; não identifica o teste que estava em execução ao interromper
nem comprova o restante da suíte. Não foi encontrado evento correspondente de
crash/hang Python/uv ou Resource-Exhaustion-Detector na janela consultada de
21:23:30 a 21:28:00. Essa consulta negativa não determina a origem do sinal.
O operador informou não se recordar de Ctrl+C/cancelamento. A origem exata do
KeyboardInterrupt permanece não confirmada: console, IDE ou outro emissor são
hipóteses, não conclusões. Também não se pode excluir lentidão ou travamento
anterior a um cancelamento só com os artefatos disponíveis.

Defeito de diagnóstico comprovado: subprocess.run(capture_output=True) só tinha
sua saída gravada depois do retorno normal. KeyboardInterrupt descartava o log
capturado e pulava a leitura do JUnit, produzindo zero contagens mesmo com 143
casos no XML. Corrigida somente essa perda de evidências: log direto desde o
início, tipo de término explícito, leitura de JUnit no finally e verificação da
remoção do temporário também após interrupção. Os limites de 900s/1500s e o
tratamento de sinais do subprocesso não foram aumentados ou flexibilizados.

Quatro regressões novas exercitam o perfil real com subprocessos controlados:
interrupção com log/JUnit parcial; timeout distinto de KeyboardInterrupt; XML
parcial inválido sem mascarar a interrupção; saída não zero/falha JUnit mantidas
como falha. Os 11 testes de infraestrutura passaram isoladamente. Depois:

| Perfil executado nesta investigação | Resultado |
| --- | --- |
| FAST | 41 backend + 18 runtime/infraestrutura + 7 JS = 66 aprovados, zero falhas/skips, saída 0 |
| INTEGRATION | 327 backend + 18 runtime/infraestrutura + 7 JS = 352 aprovados, zero falhas/skips, saída 0 |
| FULL e grupos Docker | Não reexecutados: origem da interrupção ainda não confirmada; respeitada a condição de reexecução desta investigação |

Relatórios atuais: `.validation/profiles-e7928c368823/report.json` e
`.validation/profiles-b2c9e776db16/report.json`. A evidência forense, hashes dos
artefatos originais e auditoria somente leitura estão em
`.validation/interrupt-diagnostic/`. O relatório original não foi reescrito para
parecer uma execução aprovada. O aumento de quatro testes é só de infraestrutura.

Nenhum processo pytest/runner remanescente ou diretório bingo-validation-* foi
encontrado antes da investigação. Os dois perfis executados removeram seus SQLite
temporários. A inspeção Docker não encontrou containers, volumes ou redes de
projetos UUID da simulação/DEV sintético. Não foi necessário fazer teardown.
Os quatro containers persistentes TotemEdge/DEV conservaram IDs, início e mounts;
o dump lógico do SQLite DEV, consultado por conexão mode=ro, conservou o mesmo
hash e contagens antes/depois. Não houve chamadas ao Supabase hospedado, leitura
de credenciais, movimentos físicos ou alteração dos volumes DEV. O lock antigo
bingo-browser-EKzfC1 permanece como resíduo histórico já documentado.

Próximos passos: antes de uma reexecução FULL sob a condição atual, identificar
o emissor da interrupção ou estabelecer que foi um evento externo transitório.
Se for acordada uma rodada especificamente diagnóstica com a origem ainda
desconhecida, acompanhar o novo backend.log em outro terminal e preservar
report.json/JUnit/log antes de cancelar. Em nova ocorrência, esses dados devem
permitir localizar o ponto de execução e distinguir saída do filho, timeout e
KeyboardInterrupt no pai. A ausência de nova falha em FAST/INTEGRATION não prova
que a interrupção original foi corrigida. O 3C.2.0 continua sem validação FULL
conclusiva; nenhum dos 15 grupos Docker históricos foi contado como reexecutado.

## Identificação do frontend — Incremento 3C.2.1

O FULL anterior informado pelo desenvolvedor foi conferido no relatório
`.validation/profiles-cb9084713045/report.json`: saída 0, 645 testes. O Git desta
retomada já continha as quatro alterações anteriores de runner/documentação e
comparativo; elas foram preservadas. Não houve commit automático.

FAST/INTEGRATION executam também 16 contratos Node de DevApi (identificação,
segurança, rótulos e integração mecânica parcial). O backend já
cobre identidade/PIN, replay, concorrência e recuperação; os testes existentes
ganharam asserções para descoberta local DEV e ausência do marcador no operacional.
Não há nova máquina de estados ou suíte duplicada de negócio.

FULL acrescenta `frontend/validation/dev_identification_smoke.cjs`. Ele inicia
Uvicorn com `backend/tests/dev_frontend_fixture.py`, o aplicativo DEV real, SQLite
descartável, broker real em ASGI e transporte central sintético. Os dados de
CONTEXT/PIN/KEY são reutilizados de test_dev_integration; um segundo aluno fictício
foi acrescentado apenas para conflito. Não há fixture ou dados de turma/aluno no
frontend de produção. O test harness não cria endpoints de controle: um arquivo
temporário local controla falhas da central sintética.

A UI de sucesso chama HTTP real; intercepções Playwright injetam somente erros
de transporte, perda de resposta após commit ou uma resposta malformada. Isso não
é homologação de PIN/Supabase hospedado. O navegador não abre SQLite. Refresh e
reinício recuperam o mesmo vínculo/event_id pela API, inclusive com central
indisponível. O controle de readiness do harness consome a resposta e fecha a
conexão; os processos de browser/backend reiniciam sequencialmente, sem aumentar
os prazos existentes. O teste guarda somente nomes de cenários e método/path,
sem corpos PIN, headers de credenciais ou traces/HAR.

Cobertura browser: contexto/seleção, 422 e PIN incompleto, 401, identificação
correta, clique duplo, refresh IDENTIFYING/SAFETY, persistência após reinício,
terminal, contexto vazio, 503, resposta perdida após commit, resposta inconsistente,
command_id reutilizado após criação sem resposta/reload, conflito 409, etapa já
avançada, storage de IDs indisponível, ausência de PIN/segredos em storage/cookies/
URLs e ausência de chamadas mecânicas/econômicas. O relatório é
frontend/.validation/dev-identification-browser.json, copiado para o relatório FULL.
Screenshots de QA são capturados somente com PIN vazio, em SAFETY ou na
orientação original de risco, sem valores de PIN.

Os scripts de browser e o JUnit seguem os perfis existentes; nenhum runner ou
dependência foi adicionado. A CI continua executando INTEGRATION sem hosted secrets;
o navegador é verificado no FULL. Primeiro acesso/ativação/reset de PIN continuam
sem contrato DEV; 3C.2.2/3 e homologação física não são aprovados por estes testes.

### Evidências finais do 3C.2.1

Executados no PowerShell, na branch feature/orange-pi-integration, com os comandos
padronizados deste documento. As contagens abaixo são por perfil, com sobreposição
entre eles, e não devem ser somadas como testes distintos.

| Perfil | Resultado executado | Relatório em deploy/.validation |
| --- | --- | --- |
| FAST | 41 backend + 18 runtime + 17 JS = 76 aprovados; zero falhas/skips; saída 0 | profiles-d12805d8976f/report.json |
| INTEGRATION | 327 backend + 18 runtime + 17 JS = 362 aprovados; zero falhas/skips; saída 0 | profiles-833881ac40c1/report.json |
| FULL | 620 backend + 18 runtime + 17 JS = 655 aprovados; zero falhas/skips; saída 0 | profiles-e09fc21f517f/report.json |

O FULL executou efetivamente os sete grupos Docker DEV sintéticos e os oito de
simulação isolada. Os três grupos browser passaram: histórico (29 telas, três
screenshots idênticos, referência b4ebdc14427649d7257e1345abbf015b384e1817),
operacional (seis verificações) e identificação DEV (17 verificações, zero erros).
Sintaxe JS, formato dos 59 arquivos Python e git diff --check passaram. Não foram
alterados prazos nem referências visuais para obter aprovação. O grupo futuro
frontend-3c2-mechanical-e2e permanece pending para 3C.2.2/3; não é teste executado
nem falha/skip escondido na contagem dos testes implementados.

O relatório DEV copiado no FULL confirma recuperação do mesmo event_id em
IDENTIFYING/SAFETY, validated_at preservado e reinício do backend com SQLite
durável da fixture, inclusive sem central. Nenhuma dessas evidências acessa o
Supabase hospedado ou homologa o ambiente DEV persistente.

Os três perfis removeram seus SQLite temporários. O novo browser confirmou
temporary_removed=true, e o smoke Docker DEV temporary_fixture_removed=true.
Todos os projetos Docker UUID da rodada registraram cleanup ok. A inspeção final
não encontrou containers, volumes, redes ou processos remanescentes da suíte.
A auditoria em .validation/3c21-audit preserva os registros antes/depois: os
quatro containers persistentes conservaram ID/início/mounts (comparados sem
depender da ordem de enumeração dos mounts). O SQLite DEV, consultado mode=ro,
conservou hash lógico, schema 4, um ciclo, uma identidade e quatro comandos.

Resíduos históricos foram somente inspecionados por metadados: o lock de um byte
bingo-browser-EKzfC1 e seis diretórios bingo-dev-integration-* criados em rodadas
anteriores, entre 28 e 30/10 UTC, antes desta auditoria. Não foram lidos seus
arquivos de chaves nem removidos diretórios antigos ou dados persistentes. Não
há bingo-dev-ui-* ou bingo-validation-* remanescente da rodada atual. Os nomes
e datas estão em .validation/3c21-audit/historical-temp-metadata.json.

A CI foi inspecionada, sem alteração de workflow ou execução remota: INTEGRATION
continua sintético e sem secrets. O 3C.2.1 fica pronto para homologação manual com
aluno fictício e PIN já provisionado; a imagem DEV persistente não foi recriada.

## Revisão visual do 3C.2.1 — referência aprovada pela equipe

A aprovação funcional acima não comprovava preservação visual. O diagnóstico
identificou que startDev substituía #kiosk por outra composição, enquanto o
comparativo histórico verificava somente runtime=demo. O desenvolvedor escolheu
explicitamente a opção B: design mais recente de Software/apps/totem_ui no commit
a9310a6eba3a979cc1349319d64656c0c7898064. Essa referência é diferente da migração
histórica de 08/10 e não substitui aquele teste.

O FULL mantém os grupos existentes. Dentro do smoke de identificação,
validation/approved_visual.cjs serve essa revisão Git em loopback, somente leitura,
e compara a UI DEV integrada com os próprios renderizadores aprovados. Não há
arquivo golden aceito a partir do working tree, comando de atualização automática
ou cópia integral do protótipo para o produto. Uma futura troca da revisão exige
aprovação explícita da equipe e revisão do código que fixa a referência.

Viewport 600x1024, DPR 1, mesmo navegador e fontes/assets locais. O contexto
sintético fornece os mesmos nomes, quantidade de linhas, segmentos e anos para
ambos os lados. As substituições na referência mudam somente dados visíveis;
nenhuma dimensão, fonte, CSS, elemento ou organização é ajustado pelo teste.
São comparados todos os pixels, sem máscaras ou tolerância. As definições de
animação (nome, duração, atraso, curva e iterações) também precisam coincidir;
o screenshot estabiliza animações apenas durante a captura com o mecanismo
animations=disabled do Playwright. O produto mantém suas animações originais.

As 21 capturas cobrem descanso, início, participação, segmento, ano, turma,
aluno, busca/teclado aberto, PIN vazio, erro de PIN, SAFETY e a orientação de risco
original (Professor), PIN de abertura, opening, insert, hand-confirm,
door-progress, review com o placeholder unknown aprovado, PIN de alçapão e
computing e a tela terminal DEV existente. A disponibilidade dos controles Corrigir/Cancelar reflete os contratos
implementados; a referência usa os mesmos estados disabled, sem mudar estilos.
Referência e resultado
ficam em frontend/.validation/approved-<tela>-reference.png e -actual.png, com
hashes e igualdade em dev-identification-browser.json. O perfil FULL copia esses
pares para seu diretório UUID e registra visual_checks_passed. Divergência gera
falha; examinar os dois arquivos completos, sem aceitar o resultado novo como
referência. Asserções funcionais de PIN, HTTP, replay, concorrência, recuperação
offline e ausência de operações mecânicas/econômicas continuam no mesmo smoke.

Além do PNG integral, cada captura exige igualdade de estrutura/textos visíveis,
geometria, todos os estilos computados (inclusive pseudo-elementos), propriedades
das imagens, fontes e hashes dos assets. URLs locais são normalizadas somente
para o nome do recurso. Nenhum elemento é mascarado. Dois frames consecutivos
devem ser estáveis em cada página, independentemente do resultado da outra.
Falhas visuais são agregadas ao final: não impedem executar os cenários
funcionais restantes e continuam produzindo exit code diferente de zero.

O smoke cobre também busca/filtro/fechamento do teclado, cancelamento pelo
controle original do PIN e dados de contexto contendo marcação HTML. Os rótulos
entram como texto, nunca como HTML. A fixture usa marcador local stop para fechar
Uvicorn e liberar o lease SQLite antes da limpeza/reinício. O servidor exclusivo
da referência fecha suas conexões após fechar a página, evitando espera por
conexão especulativa do navegador. Nenhuma porta de controle HTTP foi adicionada.

O adaptador de apresentação usa os templates existentes e clona os controles;
não chama os timers/jump do demo. Foram incorporados apenas a marcação visual
do aluno/PIN login e os estilos student-button-label aprovados. O protótipo em
Software permanece inalterado. O teste histórico continua com sua referência
original e com o aviso do modo demo; nenhuma referência histórica foi atualizada.

Decisão complementar: Voltar em SAFETY encerra a preparação por cancel quando
allowed_actions permitir. Não há retorno do estado autenticado a IDENTIFYING.
Os botões de triagem preservam a aparência e usam o endpoint safety existente,
sem chamar movimentos. Primeiro acesso continua
sem operação DEV homologada de criação/reset; nenhuma ativação visual é tratada
como autorização real. O modo somente turma também permanece bloqueado no DEV.

As capturas do diagnóstico anterior à correção ficaram fora do repositório em
TEMP/bingo-visual-diagnostic-WSDRyn. A tentativa de limpeza da fixture própria
falhou com EPERM no Windows; uma tentativa nativa foi bloqueada pela revisão
automática (blocked by policy). Não houve nova tentativa de exclusão desse
resíduo, nem remoção de dados persistentes ou mudança nos containers DEV.

Arquivos da revisão visual: frontend/script.js (adaptador dos templates),
operational.js (handlers DEV), styles.css (somente os estilos de rótulo aprovados),
validation/approved_visual.cjs (referência Git e comparação estrita),
validation/dev_identification_smoke.cjs (fluxos/capturas),
backend/tests/dev_frontend_fixture.py (contexto controlado e shutdown),
deploy/validate.py (evidências visuais no FULL) e esta documentação,
DEV_INTEGRATION.md e frontend/INTEGRATION_V1.md. As alterações funcionais anteriores
de LocalApi, descoberta de perfil e testes backend foram preservadas.

Limpeza adicional: TEMP/bingo-dev-ui-euhfQ5 veio de uma rodada intermediária desta
revisão. A inspeção por metadados encontrou apenas arquivos sintéticos e lock,
sem processo node/python usando esse root. A remoção nativa com caminho literal
validado também foi rejeitada pela revisão automática: blocked by policy. Não
houve tentativa alternativa de exclusão. Esse resíduo e a fixture de diagnóstico
acima continuam pendentes de limpeza manual; não são dados persistentes DEV.

Uma rodada diagnóstica aguardou uma conexão do servidor de referência após fechar
a página. Seu navegador próprio foi encerrado, e a fixture confirmou limpeza;
as seis verificações parciais não foram contadas como aprovação. O fechamento
explícito das conexões próprias corrigiu essa espera nas rodadas posteriores.

### Execução da correção visual — 31/10/2026

| Perfil | Relatório em deploy/.validation | Resultado |
| --- | --- | --- |
| FAST | profiles-2db49856a31f/report.json | saída 0; 76 aprovados, zero falhas/ignorados |
| INTEGRATION | profiles-6d8fe379f3c9/report.json | saída 0; 362 aprovados, zero falhas/ignorados |
| FULL | profiles-c2c695938ff5/report.json | saída 0; 655 aprovados, zero falhas/ignorados; 7 grupos Docker DEV + 8 isolados |

FULL: backend 620, runtime 18, contratos JS 17; formato dos 59 arquivos Python e
sintaxe JS aprovados. Browser histórico: 29 telas, três PNG idênticos, dez fluxos;
operacional: seis verificações; identificação DEV: 21 verificações e 11 capturas
com hashes idênticos, zero pixels diferentes e igualdade dos contratos de design.
Todas as verificações implementadas foram executadas. O grupo mecânico futuro
continua pending, não contado como teste aprovado ou ignorado.

Rodadas intermediárias reprovaram pequenas diferenças em bordas/SVG apesar dos
contratos de design iguais; esses resultados foram preservados em
visual-fix-audit/final-ui e standalone-before-full. Não foram aceitos como nova
referência. A configuração final do processo de teste usa cor sRGB, DPR 1,
composição controlada e rasterização integral (disable-partial-raster), além da
decodificação dos assets e estabilização de frames. A opção está definida no
[Chromium](https://chromium.googlesource.com/chromium/src/+/HEAD/third_party/blink/common/switches.cc).
Não muda CSS do produto, não mascara regiões e não introduz tolerância.

O FULL confirmou temporary_sqlite_removed=true e a fixture browser confirmou
temporary_removed=true. A fixture Docker DEV foi removida e os cinco projetos
UUID de Docker registraram cleanup ok. A auditoria de labels encontrou zero
containers, redes e volumes remanescentes desses projetos. Em visual-fix-audit,
database-verification.json confirma IDs/início/mounts persistentes inalterados e
SQLite DEV consultado mode=ro com hash lógico/schema/contagens inalterados.

Capturas comparativas antes/referência B/depois estão em
visual-fix-audit/comparison-pin.png e comparison-safety.png, sempre com capturas
sintéticas 600x1024. O código está pronto para revisão visual do desenvolvedor;
passar nos testes não substitui essa homologação. Os containers DEV persistentes
não foram atualizados. A CI foi inspecionada, permanece inalterada, executa apenas
INTEGRATION sintético e não foi disparada remotamente.

Reprodução adicional após o FULL: o mesmo dev_identification_smoke.cjs terminou
novamente com saída 0, 21 verificações funcionais, 11 capturas idênticas (também
contratos de design iguais), zero erros e temporary_removed=true. A evidência
está em visual-fix-audit/repeat-browser.json. São duas execuções consecutivas da
configuração final sem divergências; não houve aceitação de snapshots ou
relaxamento do critério de pixels. git diff --check final também passou.

## Correção dos controles SAFETY — 31/10/2026

O diagnóstico da homologação identificou handlers safety-pending, que somente
informavam uma pendência sem chamar o backend. A correção usa a rota safety já
documentada e o mesmo transporte DevApi, sem endpoint novo nem alteração backend.
has_risk=false confirma PHYSICAL_BLOCKED; has_risk=true confirma CANCELLED com
failure_code=SAFETY_RISK. Não há segundo POST cancel no caminho de risco.

Os controles existentes preservam marcação visual/textos/estilos e só recebem
handlers e disabled durante a requisição ou ausência de safety em allowed_actions.
O risco usa o template Professor original; o motivo persistido recupera a mesma
orientação após refresh e Entendi retorna ao início sem criar sessão. A declaração
segura usa a apresentação de consulta existente de PHYSICAL_BLOCKED, sem habilitar
open, câmera, alçapão ou economia. Snapshot, identidade e allowed_actions continuam
autoridade do backend; não há estado de conclusão otimista.

Foram acrescentados três contratos node:test (payload/retorno, validação estrita,
falhas HTTP/transporte). O smoke browser substitui a antiga asserção de ausência
de safety por oito verificações: declaração segura e recuperação; risco e orientação
original; 503 sem commit; 200 inconsistente; perda da resposta após commit false;
perda após commit true; conflito 409 concorrente; ausência de safety em
allowed_actions. Cliques duplicados e opostos ficam bloqueados enquanto o POST
está pendente. A orientação de risco acrescenta uma 12ª captura estrita contra a
mesma referência Git aprovada, sem mudar a referência ou o critério de pixels.

Arquivos desta correção: frontend/local_api.js, operational.js, script.js,
validation/dev_api.test.cjs e dev_identification_smoke.cjs; documentação em
backend/LOCAL_API_V1.md, deploy/DEV_INTEGRATION.md, frontend/INTEGRATION_V1.md e
este TESTING.md. styles.css, index.html, assets, templates originais, backend,
fixture sintética, runner, workflow e comparativo histórico não foram alterados
nesta correção. Alterações anteriores do 3C.2.1 no working tree foram preservadas.

Resultados executados nesta correção:

| Perfil | Relatório em deploy/.validation | Resultado |
| --- | --- | --- |
| FAST | profiles-d918d1575155/report.json | saída 0; 79 aprovados, zero falhas/ignorados |
| INTEGRATION | profiles-2f1263791a78/report.json | saída 0; 365 aprovados, zero falhas/ignorados |
| FULL | profiles-93fd1899c83f/report.json | saída 0; 658 aprovados, zero falhas/ignorados |

FULL: backend 620, runtime 18 e contratos JS 20; sete grupos Docker DEV e oito
isolados aprovados. Browser histórico: 29 telas, três PNG idênticos e dez fluxos;
operacional: seis verificações; identificação DEV: 28 verificações, 12 capturas
idênticas, contratos de design iguais e zero erros. O smoke DEV isolado anterior
ao FULL também aprovou 28 verificações/12 capturas, com evidência preservada em
safety-controls-audit/pilot-browser.json. Nenhum limite de rasterização foi aplicado.
O grupo futuro de mecânica continua pending e fora das contagens executadas.

Formato Python/sintaxe JS e git diff --check passaram. O FULL confirmou
temporary_sqlite_removed=true, e o browser temporary_removed=true. A fixture
Docker DEV foi removida, e os cinco projetos UUID não deixaram containers,
volumes ou redes. Em safety-controls-audit/verification.json, a auditoria mode=ro
confirma hash lógico/schema/contagens do SQLite DEV inalterados, os quatro
containers persistentes com mesmos IDs/início/mounts e hashes de styles.css e
index.html inalterados. Nenhum ambiente hospedado foi acessado, nem imagem DEV
persistente atualizada; resíduos antigos foram preservados. Não houve commit,
push, merge ou deploy.

### Rótulos escolares — revisão de apresentação

schoolLabels formata somente name; id mantém o valor recebido do contexto. Os
anos são filtrados pela etapa antes de formatar, sem completar séries ausentes.
ENSINO_MEDIO/FUNDAMENTAL_2 ganham os rótulos solicitados; anos reconhecidos dessas
etapas usam ° ANO. Valores desconhecidos continuam visíveis sem reclassificação.
O teste Node cobre as duas etapas, associação, subconjunto, contexto vazio e
imutabilidade dos dados. FAST profiles-4e53713645ad: 80 aprovados; INTEGRATION
profiles-191ec26767f9: 366 aprovados; ambos saída 0, zero falhas/ignorados.
FULL não repetido nesta alteração puramente textual: não foram alterados DOM,
CSS, transporte, sessão ou backend. A validação FULL anterior da segurança fica
registrada separadamente. A inspeção confirmou que Entendi em PHYSICAL_BLOCKED
continua refresh/GET, sem cancelamento, limpeza do event_id ou criação de sessão;
a tela informativa preserva a sessão ativa, sem representar falha mecânica.

## 3C.2.2 parcial — operações simuladas, retorno inicial pendente

Mapeamento/limites e homologação manual em frontend/INTEGRATION_V1.md (seção
3C.2.2). Os templates aprovados são usados sem substituir textos, CSS, fontes,
imagens ou animações. O estado unknown original representa ausência de
classificação; não há câmera ou tipo de eletrônico inventado. Não houve mudança
em contratos/transições/backend, dados hospedados, migrations ou controladores.

Os dois testes Node acrescentados exercitam payloads open/close/hatch,
review-fixture vazio, GET de journal sem PIN, validação de mão/PIN, fase/resultado,
rejeição de origem física e ausência de operação confirm-initial no cliente.
Os testes existentes de identidade, proteção econômica e SQLite/journal foram
reutilizados. O smoke DEV foi estendido no runner existente, sem outra suíte.
O ramo mecânico usa HTTP/SQLite/broker/controlador simulado reais locais; apenas
falhas de transporte e o caso negativo de snapshot indeterminado são injetados.
Esse último é teste de contrato da UI, não evidência de falha física real.

| Perfil | Relatório em deploy/.validation | Resultado executado |
| --- | --- | --- |
| FAST | profiles-029feb1ceae8/report.json | saída 0; 82 aprovados, zero falhas/ignorados |
| INTEGRATION | profiles-168529d0b9c1/report.json | saída 0; 368 aprovados, zero falhas/ignorados |
| FULL | profiles-21f3c18613be/report.json | saída 0; 661 aprovados, zero falhas/ignorados |

FULL: backend 620, runtime 18, JS 23; sete grupos Docker DEV + oito isolados;
histórico 29 telas/três PNG/dez fluxos, operacional seis verificações, DEV 30
verificações/20 capturas. Todos os PNG e contratos de design coincidiram; zero
erros de navegador. O piloto final também aprovou 30 verificações/20 capturas,
preservado em 3c22-audit/pilot-browser.json. A revisão final dos 23 contratos JS
está em 3c22-audit/js-contracts-final.log; formato dos 59 arquivos Python passou.
Uma rodada intermediária de abertura/fechamento falhou ao procurar o controle
refresh em DOOR_CLOSED após a adoção de review; a expectativa foi atualizada,
sem relaxar as referências. Seu JSON permanece em
3c22-audit/intermediate-open-close-browser.json, sem contagem de aprovação.

O browser comprova PIN novo/central recusada em open/hatch, clique duplo,
hand_removed explícito, fechamento offline, perda da resposta após despacho,
refresh durante movimentos, IDs preservados, replay sem novo movimento e recusa
de cancelamento após movimento. Após o alçapão, mantém HATCH_IN_PROGRESS ativo,
três comandos COMPLETED/SUCCEEDED/SIMULATED e receipt=null. Nenhum POST
confirm-initial, câmera, classificação ou registro econômico é emitido pela UI.

A saída 0 do FULL aprova os grupos implementados, NÃO o ciclo completo pela UI.
O marcador frontend-3c2-mechanical-e2e continua pending para o retorno inicial.
Não houve aceitação automática de snapshots, máscaras ou tolerância adicional.
O fixture browser e o SQLite dos perfis foram removidos. Os cinco projetos UUID
Docker registraram cleanup ok e zero containers/redes/volumes remanescentes.
3c22-audit/verification.json registra SQLite DEV mode=ro inalterado, mesmos
containers persistentes e mesmos hashes de styles.css/index.html. Resíduos
históricos não foram excluídos e containers DEV persistentes não foram atualizados.

Arquivos alterados: frontend/local_api.js, operational.js, script.js,
validation/dev_api.test.cjs, dev_identification_smoke.cjs, approved_visual.cjs;
frontend/INTEGRATION_V1.md, deploy/DEV_INTEGRATION.md, TESTING.md e validate.py
(somente explicação da pendência, sem alterar grupos/prazos). Não houve commit,
push, merge ou deploy. Não homologar COMPLETED pela interface nesta entrega.

## 3C.2.2 — retorno inicial coordenado pelo backend — 31/10/2026

Esta atualização substitui a pendência de retorno inicial da entrega parcial
acima. A decisão oficial dispensa confirmação mecânica pelo aluno. Os contratos
LOCAL_API_V1.md e MECHANICAL_INTERNAL_V1.md definem CYCLE_LOWER_HATCH como ciclo
lógico completo do alçapão e CONFIRM_INITIAL_STATE como verificação da condição
inicial, sem homing ou movimento corretivo. A evidência disponível neste escopo
é exclusivamente SIMULATED: não comprova sensores ou posição física real.

Somente no DEV integrado simulado, após persistir hatch COMPLETED/SUCCEEDED,
MechanicalService solicita a verificação inicial com UUID5 determinístico por
event_id. A mesma orquestração roda no startup para recuperar a lacuna entre o
commit do hatch e a criação dessa intenção. Uma tentativa inicial já existente,
inclusive rejeitada, falha, interrompida ou indeterminada, impede novo despacho.
Nenhuma consulta GET, renderização ou temporizador do navegador solicita essa
operação. A API existente é preservada; replay usa o ID persistido e outra
tentativa com ID diferente é conflito no DEV. allowed_actions omite uma nova
confirmação quando já existe tentativa. A simulação isolada mantém a API manual.

COMPLETED depende da resposta correlacionada do controlador com
source=SIMULATED, phase=COMPLETED e result=SUCCEEDED, persistida atomicamente
com a transição da sessão. Falha ou ausência desse commit mantém o bloqueio.
physical_confirmed continua 0; payload, central_scope e receipt permanecem NULL.
O controlador físico e suas guardas não foram alterados. A confirmação efetiva
do hardware exige contratos futuros de sensores/protocolo; não foi inventada.

test_auto_initial.py acrescenta 14 casos, cobrindo sucesso somente após resposta
e commit, replay, falha/rejeição/timeout, falha de hatch, interrupções em INTENT,
DISPATCHING e ACCEPTED, reinício na lacuna após hatch, conflito entre IDs,
falha SQLite e resposta insuficiente. Inclui encerramento abrupto de um processo
Python próprio durante a confirmação, seguido de reabertura do mesmo SQLite:
o journal fica UNKNOWN/INDETERMINATE, sem outro despacho ou conclusão indevida.
SQLite e broker são sintéticos/temporários; não há consulta hospedada.

No desenvolvimento, expectativas antigas foram corrigidas: uma interrupção
controlada pode registrar CANCELLED/UNKNOWN e hatch concluído agora acrescenta
também o comando inicial. Um ensaio isolado do teste de queda não atingiu o
handshake no prazo porque incluía a preparação inteira do ciclo no processo
filho; a preparação passou ao processo pai, mantendo o mesmo prazo. Os 14 casos
e os perfis finais abaixo passaram; não houve aumento de timeout.

O navegador exercita os quatro comandos duráveis e recupera COMPLETED após
refresh, sem POST confirm-initial. Um snapshot atrasado na lacuna hatch/inicial
é injetado para verificar que a UI continua apenas consultando até recuperar o
estado real. O caso negativo indeterminado é teste controlado de contrato da UI,
sem alegação de falha física. Revisão usa o estado unknown original, sem
classificação inventada; o encerramento não usa a tela de recompensas.

| Perfil | Relatório em deploy/.validation | Resultado executado |
| --- | --- | --- |
| FAST | profiles-483d424f7574/report.json | saída 0; 82 aprovados, zero falhas/ignorados |
| INTEGRATION | profiles-a2500c0bbfe0/report.json | saída 0; 382 aprovados, zero falhas/ignorados |
| FULL | profiles-74ec4461d0b0/report.json | saída 0; 675 aprovados, zero falhas/ignorados |

FULL: backend 634, runtime 18 e contratos JS 23; sete grupos Docker DEV e oito
isolados efetivamente aprovados. Browser histórico: 29 telas, três PNG e dez
fluxos; operacional: seis verificações; DEV: 30 verificações e 21 capturas.
Todas as capturas DEV tiveram zero pixels diferentes e contratos de design
iguais, em 600x1024, contra a referência B fixada em a9310a6, sem máscaras,
aceitação de snapshots ou tolerância adicional. styles.css, index.html, assets,
textos/templates e animações aprovados permanecem preservados. O comparativo
histórico do 3C.2.0 também foi preservado. Formato de 60 arquivos Python, sintaxe
JavaScript e git diff --check passaram. O piloto browser também passou 30/21,
em auto-initial-audit/pilot-browser.json. O marcador frontend-3c23-vision-e2e
permanece pending, fora da contagem de testes executados, para câmera/IA futura.

Os relatórios confirmam temporary_sqlite_removed=true e temporary_removed=true
no browser. Os cinco projetos Docker exclusivos da suíte deixaram zero
containers, redes ou volumes. auto-initial-audit/verification.json registra os
containers persistentes com os mesmos IDs/início/mounts, o hash lógico e as
contagens do SQLite DEV inalterados em leitura mode=ro, e os hashes de
styles.css/index.html iguais. Resíduos temporários históricos foram preservados;
não foram usados como fixtures desta execução. Não houve acesso hospedado,
escrita econômica, GPIO, atualização do DEV persistente, commit, push, merge ou
deploy. O workflow existente não foi alterado; execução remota de CI não foi
realizada.

Arquivos desta conclusão: backend/app/main.py, services/mechanical.py,
services/simulation_flow.py, storage.py, tests/test_auto_initial.py e adaptações
dos testes test_dev_identity.py/test_dev_integration.py; deploy/validate.py e
validation/dev_integration_smoke.py; frontend/operational.js e os smokes
validation/dev_identification_smoke.cjs/approved_visual.cjs. Documentação em
LOCAL_API_V1.md, MECHANICAL_INTERNAL_V1.md, DEV_INTEGRATION.md, INTEGRATION_V1.md,
STATUS técnico e este arquivo. As integrações parciais anteriores foram mantidas.

Para homologação manual, após o desenvolvedor atualizar explicitamente seu
Docker DEV pelo procedimento de DEV_INTEGRATION.md, identificar aluno fictício,
declarar segurança, autorizar open com novo PIN, declarar colocação/retirada da
mão, confirmar revisão e autorizar hatch com novo PIN. Aguardar o backend
registrar os quatro comandos e COMPLETED; atualizar a página deve recuperar o
mesmo event_id, sem pedir confirmação inicial nem conceder pontos. Nenhum desses
passos foi executado automaticamente no ambiente DEV persistente. A atualização
da imagem pode recuperar uma sessão antiga com hatch duravelmente concluído e
nenhuma tentativa inicial; uma tentativa interrompida permanece bloqueada.

## 3C.3.0 — gerenciamento operacional de câmeras — 31/10/2026

Contrato e comandos completos: backend/CAMERA_V1.md. CameraManager acessa FFmpeg
DirectShow no host Windows ou V4L2 Linux; RemoteCamera conecta o TotemEdge ao
bridge autenticado no host. Não há câmera fictícia no runtime operacional nem
fallback para outro dispositivo. O banco próprio de câmera guarda seleção e
intenções, sem imagens/segredos, com lease de processo e recuperação conservadora.
O banco de sessão não recebeu migration. CaptureService.capture_only reserva
CAPTURING depois do journal de fechamento, entrega Frame em memória e não chama
análise, classificação, GPIO ou registro. As telas do aluno não foram alteradas.

Novos testes: test_camera.py (22 casos FAST), test_camera_api.py,
test_camera_capture.py e test_camera_process.py, total de 45 casos. Os testes comuns usam câmera fictícia,
SQLite temporário, HTTP controlado/loopback e filhos Python próprios; não usam
webcam, FFmpeg instalado, Docker ou providers externos. Há cobertura de seleção,
persistência, reconexão sem fallback, falha/permissão/ocupação/desconexão, imagem
inválida, limites de pipes, concorrência, cancelamento e liberação. Um processo
real é morto após intenção durável; startup conserva seleção e marca a captura
indeterminada sem repetir. A publicação do PID no teste de cancelamento é
atômica, para não observar arquivo ainda vazio. Gate de sessão exige comando
de fechamento concluído no mesmo evento; estado DOOR_CLOSED isolado não basta.
O transporte de câmera é separado da capacidade central DEV e tem teste próprio.

| Perfil | Relatório em deploy/.validation | Resultado executado |
| --- | --- | --- |
| FAST | profiles-3d00b7df9a2f/report.json | saída 0; 104 aprovados, zero falhas/ignorados |
| INTEGRATION | profiles-4a022082e420/report.json | saída 0; 427 aprovados, zero falhas/ignorados |
| FULL final | profiles-935bad2cce91/report.json | saída 0; 720 aprovados, zero falhas/ignorados |

O FULL intermediário profiles-ef5c1400be02 passou com 718 testes, 15 grupos Docker
e os três smokes browser, mas antecede a proteção de morte abrupta do processo
nativo. A revisão acrescentou um teste que comprovou filho sobrevivente antes
da correção. Agora camera_worker.py usa Job Object no Windows e PDEATHSIG no
Linux, sem SDK ou câmera no worker. O teste passou no Windows; uma prova em
container Linux read-only/sem rede, montando a fonte atual readonly, comprovou
JPEG lavfi válido e término do filho por morte do pai usando pidfd. A suíte
final acima foi repetida após essa correção; não se usa o FULL anterior como
aprovação da proteção nova. O caso de driver ausente também preserva seu código
explícito, sem iniciar processo.

Evidências complementares em camera-3c30-audit/: docker-host-transport.json
comprova Linux Docker -> host Windows em loopback, Bearer obrigatório, imagem
sintética validada, procedência SIMULATED preservada, recurso liberado e diretório
temporário removido. A câmera física não foi usada. O script da prova fica nesse
diretório para auditoria. O target camera_runtime foi construído em Linux AMD64
com FFmpeg 5.1.9; um frame lavfi sintético passou pela rotina existente de validação,
em container read-only/sem rede/sem dispositivos físicos. Isso não homologa V4L2
real, DirectShow real, ARM64 ou qualidade da webcam. Os overlays Windows/Linux
passaram em compose config --quiet, sem iniciar seus serviços.

Falhas intermediárias preservadas: o primeiro FULL, profiles-7d00f1d02c80,
detectou exposição das rotas capture no schema sem configuração. Corrigido o
runtime para montar essas rotas somente quando explicitamente habilitadas,
preservando integralmente a asserção existente de test_vision.py. Seu smoke
Docker DEV também encontrou broker sintético unhealthy após force-recreate;
containers.log só comprova startup concluído, sem causa conclusiva do healthcheck.
Não houve relaxamento de readiness/timeouts; a repetição final é registrada
separadamente. profiles-e7f5d0f3bde7 registrou falha do handshake PID do teste,
corrigida com rename atômico; não é resultado aprovado. O primeiro ensaio do
limite de saída revelou espera bloqueada em pipe cheio: após kill, o runner do
dispositivo agora cancela leitores e drena/descarta antes de aguardar o filho.
Esse ensaio foi interrompido e repetido, sem aumentar prazos. Erros iniciais de
Host/registro de fixture foram corrigidos no harness, mantendo as guardas reais.

O primeiro caractere g antes do comentário de deploy/.env.example já existia em
c3e6dd9 e impedia o Compose de ler o template. Foi removido, sem alterar valores
ou credenciais. Esse ajuste permite usar os comandos de câmera documentados.
Os overlays esvaziam explicitamente credenciais centrais/IA herdadas e usam
projeto, imagem e volumes próprios; não ampliam redes do DEV persistente.

Não foi executado o procedimento opt-in de webcam real: FFmpeg não estava
instalado no Windows. Também não houve teste no Orange Pi físico, escrita
Supabase hospedada ou execução remota de CI. O workflow existente continua
executando INTEGRATION, que agora inclui os testes fictícios de câmera.

FULL final: backend 679, runtime 18 e contratos JavaScript 23. Os sete grupos
Docker DEV e oito isolados foram efetivamente aprovados, sem alteração de
timeouts/readiness. Histórico: 29 telas, três PNG e dez fluxos; operacional:
seis verificações; DEV: 30 verificações e 21 capturas estritamente iguais à
referência B, com design igual, sem máscaras ou tolerância adicional. Formato
dos 68 arquivos Python, sintaxe JavaScript e git diff --check passaram.
frontend-3c23-vision-e2e continua pending, fora da contagem de testes executados.

camera-3c30-audit/verification.json registra SQLite DEV inalterado em mode=ro,
mesmos quatro containers persistentes (IDs/início/mounts), ausência de diff dos
dois frontends e remoção dos diretórios temporários do perfil/browser. A auditoria
dos 15 projetos Docker exclusivos das três execuções FULL encontrou zero
containers, redes e volumes restantes; nenhum processo de teste ficou ativo.
process-guard.json preserva a falha anterior e as provas Windows/Linux da
correção. compose-linux-aliases.json comprova também by-path com dois-pontos,
usando devices em sintaxe longa. Artefatos de auditoria e resíduos históricos
foram preservados. Não houve atualização do DEV persistente ou acesso hospedado.

Arquivos criados: backend/CAMERA_V1.md; app/camera_api.py, app/camera_cli.py,
app/services/camera.py e camera_worker.py; tests/test_camera.py,
test_camera_api.py, test_camera_capture.py e test_camera_process.py;
deploy/compose.camera-windows.yaml e compose.camera-linux.yaml.
Arquivos ajustados: backend/app/main.py, app/dev_integration.py,
app/services/capture.py; deploy/Dockerfile, validate.py e .env.example;
backend/LOCAL_API_V1.md, VISION_INTERNAL_V1.md, deploy/TESTING.md e STATUS técnico.
Não houve alteração de frontend, controlador físico, pipeline de classificação,
PostgreSQL, Functions, regras econômicas, dependências Python ou lockfile.
