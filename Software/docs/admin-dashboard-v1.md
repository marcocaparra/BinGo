# Dashboard administrativo real V1

Atualizado em: `2026-10-01`.

O Overview é somente leitura. Regras de papel/escopo vêm de [admin-contract-v1.md](admin-contract-v1.md); esta implementação compõe exclusivamente as leituras reais existentes, sem migration, RPC, policy, grant ou alteração de backend.

## Fontes e métricas

| Perfil | Leituras existentes                                                                                                                                                                                 | Apresentação                                                                                                                                                    |
| ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A      | `get_admin_schools_v1`, `get_managed_admins_v1`, `get_binbazar_price_cap_v1`                                                                                                                        | Escolas; alunos somados por escola; contas total/ACTIVE/INACTIVE/sem vínculo; máquinas cadastradas somadas; teto ou Não configurado; escolas e resumo de contas |
| B      | `get_admin_students_v1`, `get_admin_classes_v1`, `get_managed_admins_v1`, `get_class_change_requests_v1`, `get_admin_binbazar_products_v1`, `get_admin_redemptions_v1`, `get_binbazar_price_cap_v1` | Alunos ACTIVE/INACTIVE; turmas; C total/ACTIVE/INACTIVE; trocas PENDING; resgates PENDING; produtos ativos/esgotados; teto; turmas/quantidade/XP                |
| C      | Mesmas leituras escolares de B, exceto `get_managed_admins_v1`                                                                                                                                      | Solicitações próprias PENDING; resgates da escola; produtos ativos/esgotados; alunos ACTIVE/INACTIVE; turmas/quantidade/XP; teto                                |

Autorização continua server-side: A global; B/C própria escola; C recebe somente solicitações próprias pela RPC vigente. O coordenador não envia parâmetros de identidade/escola nem faz mutations.

Máquinas cadastradas são contagem estrutural. Não representam Totem online ou operacional. Turmas não recebem status/participação inventados. Estoque esgotado considera apenas `is_active = true AND stock_qty = 0`; NULL significa ilimitado. Resgates usam nome/preço snapshots, nunca o catálogo atual. Pedidos e trocas são filtrados por PENDING; listas exibem os três mais recentes, ordenados por created_at decrescente com UUID como desempate. Solicitação stale continua PENDING e indica que aprovação está bloqueada, sem decisão no Overview.

## Composição e estados

`AdminDashboardRepository` é fornecido pelo componente Overview, coordena os cinco repositories reais e deriva métricas por signals/computed. Não mantém uma segunda fotografia/cache. A entrada, refresh do navegador ou botão Atualizar fazem novas leituras autoritativas. Não há polling. A consulta de solicitações já carrega alunos/turmas; o coordenador não repete essas chamadas. A faz três leituras; B sete; C seis, além do contexto de autenticação.

Cada fonte conserva seu estado: loading mostra `…`; erro mostra `Indisponível`; zero aparece somente após consulta bem-sucedida. Falhas parciais preservam fontes saudáveis. Teto NULL só vira Não configurado após confirmação da RPC. Um alerta indica erro de fonte, com atualização disponível após conclusão das leituras. Não existe fallback demo. Como as fontes são RPCs separadas, a fotografia não é um snapshot transacional único entre domínios.

A invalidação por contexto e descarte de respostas antigas permanecem nos repositories existentes; restauração/logoff removem o shell pelo gate Auth. Voltar à view consulta novamente. Atalhos navegam às telas reais autorizadas e não alteram dados. O shell deixa de anunciar saúde operacional ou escola demonstrativa no Overview e não exibe contagem demo de ajuda nessa view.

## Limpeza e limites

Removidos `demoSchools`, `demoClasses`, `demoPendingRedemptions` e toda atividade/métrica fictícia do Overview. `deposits`, `discardStats` e `helpRequests` permanecem porque são usados pelas telas conscientemente demonstrativas de Descartes/Ajuda; máquinas, Missões e outras regras econômicas também continuam demo. Essas fontes não são consumidas pelo dashboard. O seletor de cenário demonstrativo não aparece no Overview.

Provisionamento Auth, novas leituras de descartes, ajuda, hardware, Missões e demais regras econômicas continuam fora de escopo. Nenhuma migration foi criada; a última permanece 028. Nenhuma promoção remota ao bingo-dev foi executada.

## Reprodução local

```powershell
# Cwd: Software; executar as suites de banco em sequência.
node node_modules/supabase/dist/supabase.js db reset --local
node node_modules/supabase/dist/supabase.js test db
$env:PYTHONPATH = 'backend/src'
$env:BINGO_RPC_TEST_DATABASE_URL = 'postgresql://postgres:postgres@127.0.0.1:54322/postgres'
$env:BINGO_MIGRATION_TEST_DATABASE_URL = $env:BINGO_RPC_TEST_DATABASE_URL
.venv/Scripts/python.exe -m pytest backend/tests -q

# Cwd: Software/apps/admin_web; dev server local na porta 8106.
npm test
$env:BINGO_ADMIN_INTEGRATION = '1'
npm run test:integration
npm run build
node node_modules/typescript/bin/tsc --noEmit -p tsconfig.app.json
```

Testes novos de browser cobrem A/B/C, somas/escopo, snapshots, NULL/zero, ausência de mocks, erro parcial/total, loading/empty, renovação por role/escola, logout com leituras atrasadas, refetch, atalhos e responsividade. O smoke real local cria fixtures Auth A/B/C/aluno, duas escolas, alunos/turmas/produtos/máquina estrutural; cria solicitação por C e resgate pelo aluno, confere cards contra RPCs reais, aprova/entrega por B, atualiza dashboard e valida restauração C. Remove fixtures/usuários e restaura teto/timestamps originais. A chave técnica existe apenas no provisionador de teste local; o browser recebe anon.

## Validação local — 2026-10-01

| Suíte/comando                                      | Resultado                                                   |
| -------------------------------------------------- | ----------------------------------------------------------- |
| Supabase db reset --local                          | 28 migrations/seeds existentes; passou                      |
| Supabase test db                                   | 21 arquivos, 590 verificações; passou                       |
| pytest backend/tests -q                            | 176 passaram, sem skips; 13 avisos JWT legados              |
| npm test                                           | 79 passaram; 13 novos de dashboard, sem skips               |
| BINGO_ADMIN_INTEGRATION=1 npm run test:integration | Sete smokes reais passaram, um novo de dashboard; sem skips |
| npm run build / tsc --noEmit                       | Passaram                                                    |
| Prettier --check / git diff --check                | Passaram                                                    |

Os testes antigos continuam cobrindo os domínios reais e demo preservados. As contagens Auth foram delimitadas à RPC de contexto, porque o Overview passou a executar outras leituras; credenciais inválidas continuam exigindo zero RPCs. Asserts de responsividade e composição foram preservados. Uma fixture nova usou escola sem UUID e o gate recusou corretamente o contexto; corrigida para UUID válido e aprovada, sem mudar o parser. Um comando de ajuste foi iniciado fora do cwd esperado e foi corrigido antes da reexecução. Nenhuma falha ou skip nas execuções finais. Flutter/Edge Functions não foram alterados nem executados. Não houve commit, push, PR, deploy ou ação remota.
