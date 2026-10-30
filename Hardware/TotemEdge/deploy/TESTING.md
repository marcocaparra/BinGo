# Validação automatizada do TotemEdge — 3C.2.0

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

| Perfil | Grupos executados | Recursos adicionais |
| --- | --- | --- |
| FAST | contratos JS, runtime/infraestrutura, sintaxe JS, formato Python, testes backend de isolamento/rotas/contratos centrais | Nenhum serviço |
| INTEGRATION | FAST e testes existentes de identidade DEV, broker, journal, fluxo simulado, sessões e transporte HTTP loopback | SQLite descartável e mocks/servidor loopback no processo de teste |
| FULL | backend completo (inclui INTEGRATION, sem repetir sua seleção), runtime, JS, formato, os dois smokes Docker sintéticos e os dois smokes browser existentes | Docker Linux/Compose com !override (validado em 2.40.3), imagens/dependências de build, Playwright e navegador |
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
Grupos de smoke, telas e fluxos não são somados como se fossem testes unitários.
Os relatórios nativos dos smokes Docker registram os projetos exclusivos, checks
e o resultado da limpeza. Artefatos ficam ignorados pelo Git.

Código de saída `0`: grupos executáveis passaram; `1`: falha ou interrupção;
`2`: recurso indisponível, execução ainda em curso ou teste ignorado. Consulte `status`, `reason`, `tests`
e o log do grupo. Teste ignorado não equivale a aprovado. `frontend-3c2-e2e` aparece
como `pending`, sem contagem de aprovação: a integração ainda não existe. Essa
pendência planejada não impede validar a infraestrutura do 3C.2.0.

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
deploy/tests. Os contratos Node atuais ficam em local_api.test.cjs; se surgirem
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

A execução atual de `browser_smoke.cjs`, após corrigir a instalação do relógio
para preceder o alvo de pauseAt, revelou divergência preexistente na tela student:
o protótipo Software/apps/totem_ui contém Primeiro acesso/student-button-label,
enquanto a cópia oficial TotemEdge conserva o DOM anterior. A asserção de igualdade
foi preservada e reprova o grupo/FULL. Essa comparação entre versões não é um E2E
DEV aprovado. Resolver a referência histórica ou a decisão de produto exige
revisão própria; não copiar funcionalidade para fazer o gate passar.
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

## Evidência local — 30/10/2026

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
migração histórico e GitHub Actions. A aprovação integral do incremento continua
pendente da revisão do comparativo visual e do resíduo temporário descrito acima.
