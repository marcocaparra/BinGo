# Admin Descartes V1

Atualizado em: `2026-10-23`.

Esta fatia substitui a demonstração local da tela Descartes por uma leitura administrativa real. A implementação está validada somente no Supabase local e não foi promovida ao `bingo-dev` ou a produção.

## Contrato aprovado

`get_admin_deposits_v1()` não recebe parâmetros. A RPC deriva a identidade administrativa exclusivamente de `auth.uid()`, exige um registro `admins` `ACTIVE` e aplica o seguinte escopo:

- `ADMIN_A`: descartes de todas as escolas;
- `ADMIN_B`: somente a escola vinculada;
- `ADMIN_C`: somente a escola vinculada;
- admin ausente, sem escola quando B/C ou `INACTIVE`: acesso recusado.

O cliente não envia `admin_id`, role ou `school_id`. O resultado é ordenado por `created_at DESC, deposit_id DESC` e contém:

| Campo                        | Tipo          | Origem                                               |
| ---------------------------- | ------------- | ---------------------------------------------------- |
| `deposit_id`                 | `uuid`        | `deposits.id`                                        |
| `event_id`                   | `uuid`        | `deposits.event_id`                                  |
| `school_id`, `school_name`   | `uuid`, text  | depósito e join com `schools`                        |
| `machine_id`, `machine_name` | `uuid`, text  | depósito e join seguro com `machines`                |
| `class_id`, `class_name`     | `uuid`, text  | depósito e join seguro com `classes`                 |
| `student_id`, `student_name` | `uuid`, text  | depósito e left join seguro com `students`; nullable |
| `is_valid`, `detected_type`  | boolean, text | fotografia do evento em `deposits`                   |
| `waste_category_code`        | text          | join com o catálogo canônico; nullable               |
| `category_source`            | text          | fotografia persistida; nullable                      |
| `bonus_rate_applied`         | numeric       | fotografia econômica persistida                      |
| `bonus_bincoins_awarded`     | integer       | fotografia econômica persistida                      |
| `points_awarded_student`     | integer       | fotografia econômica persistida                      |
| `points_awarded_class`       | integer       | fotografia econômica persistida                      |
| `created_at`                 | timestamptz   | instante autoritativo do depósito                    |

Os nomes são derivados das tabelas existentes; nenhuma coluna duplicada foi adicionada ao domínio. A RPC não recalcula BinCoins, bônus ou XP usando configuração atual. Descarte anônimo permanece com aluno nulo. Evento inválido preserva seus nulos e valores `0/0`. Não são inferidos tamanho, quantidade, peso, impacto ambiental, status de revisão, estado operacional do Totem ou outro horário.

## Banco e segurança

As migrations equivalentes são:

- `database/migrations/031_admin_deposits_v1.sql`;
- `supabase/migrations/20261001160000_admin_deposits_v1.sql`.

A função é `STABLE`, `SECURITY DEFINER`, usa `search_path = ''` e nomes qualificados. `EXECUTE` é revogado de `PUBLIC`, `anon`, `authenticated` e `service_role`, sendo concedido novamente somente a `authenticated`. A RLS e os grants diretos existentes de `deposits` foram preservados; não existe nova leitura direta ampla. A interface não expõe credenciais técnicas de máquina. `register_deposit_v1` não foi alterada.

## Admin Angular

`AdminDepositsRepository` chama somente `get_admin_deposits_v1()` e invalida a fotografia quando muda o contexto Auth. Tickets de leitura impedem que uma resposta atrasada repovoe a tela após logout ou troca de sessão.

A tela oferece loading, vazio, erro, retry e refetch. Admin A vê a coluna de escola; B/C recebem apenas o escopo retornado pelo banco. A interface mostra data/hora, aluno ou “Sem identificação”, turma, Totem, tipo detectado, categoria, origem, validade e snapshots de BinCoins, bônus e XP. IDs internos não são apresentados. Foram removidos `AdminStore.deposits`, `AdminStore.discardStats`, os valores fictícios `1284`, `32` e `184`, filtros/status inventados e os cards agregados. Esta fatia não cria RPC de estatísticas.

## Validação local histórica — 01/10/2026

Executado em `2026-10-01`:

| Validação                                   | Resultado                                      |
| ------------------------------------------- | ---------------------------------------------- |
| `supabase db reset`                         | passou; migration 031 aplicada localmente      |
| `supabase test db`                          | 24 arquivos, 646 verificações, passou          |
| `pytest tests/test_admin_deposits_v1.py -q` | 2 passaram                                     |
| `pytest -q` backend                         | 180 passaram, sem skips; 13 avisos JWT legados |
| teste browser específico de Descartes       | 5 passaram                                     |
| `npm test` Admin                            | 107 passaram                                   |
| integração local Auth/RPC/Angular           | 9 passaram, incluindo Descartes A/B/C          |
| `npm run build`                             | passou                                         |

Os testes cobrem escopo A/B/C, ausência de vazamento entre escolas, admin ausente/inativo, anon, ausência de `EXECUTE` para `service_role`, grants/RLS preservados, aluno nulo, evento válido identificado e anônimo, evento inválido, categoria/origem nulas, snapshots econômicos, ordenação determinística, estados da UI, retry/refetch, remoção dos mocks e descarte de resposta atrasada. TypeScript, Prettier e `git diff --check` também fazem parte da validação final da fatia.

Não houve `db push`, seed remoto, commit, push, PR, merge, deploy ou outra ação remota.

## Revalidação executada em 23/10/2026

Esta seção registra execuções novas, distintas das evidências históricas de
01/10/2026. A indisponibilidade de Docker/PostgreSQL observada na revisão anterior
foi superada: Docker Engine 29.0.1 e CLI 2.116.0 responderam nesta execução. Foi
usado o `Software/supabase/config.toml` existente, sem alterações. O reset
explicitamente local reaplicou as 31 migrations e os seeds configurados.

| Verificação                                                 | Resultado desta execução                                                                    |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `supabase start` e `db reset --local`                       | Aprovados; histórico local com 31 migrations                                                |
| `supabase test db --local`                                  | 646 verificações / 24 arquivos aprovados                                                    |
| `pytest backend/tests -q -rs --junitxml=...`                | 180 aprovados, zero skips; 13 avisos JWT legados                                            |
| `npm test` Admin                                            | 107 aprovados, zero falhas/skips                                                            |
| `BINGO_ADMIN_INTEGRATION=1 npm run test:integration`        | 9 aprovados, zero falhas/skips; Auth/RPC/Angular locais                                     |
| `npm run build` e TypeScript `--noEmit`                     | Aprovados                                                                                   |
| Equivalência 030 e 031 entre database/Supabase              | Aprovada, normalizando somente CRLF/LF; SQL inalterado                                      |
| `actionlint` 1.7.7 no workflow alterado                     | Aprovado                                                                                    |
| Scripts Python de readiness e JUnit da CI                   | Aprovados contra banco/JUnit reais; relatórios simulados vazios e com skip foram rejeitados |
| Prettier nos quatro arquivos alterados e `git diff --check` | Aprovados                                                                                   |

pgTAP, pytest e integrações reais foram executados em sequência no banco local.
O JUnit confirmou 180 testes coletados sem skips. O backend foi executado com o
Python 3.14 local; a CI mantém Python 3.12 e Node 22. Nenhum teste terminou com
falha nesta rodada. A execução do workflow no runner Linux/GitHub Actions não foi
realizada, pois esta tarefa não publica commits nem dispara workflows remotos.
O workflow foi validado estaticamente e seus comandos de banco/pytest e scripts
de verificação foram exercitados localmente; isso não equivale a uma execução do
job hospedado.

Não restam bloqueios locais de implementação, documentação ou validação para
abrir o PR. Os checks hospedados deverão ser confirmados após a publicação.
Missões, Economia ampliada e Ajuda permanecem fora desta entrega. As migrations
030/031 não foram alteradas ou promovidas por esta tarefa; não houve ação de
banco remoto, commit, push, merge, deploy ou abertura de PR.

## CI e reprodução local

O workflow `.github/workflows/backend-ci.yml` instala o CLI pelo
`Software/package-lock.json`, inicia o Supabase com o `supabase/config.toml`
existente e executa reset explicitamente local. A conexão PostgreSQL e a presença
das RPCs 030/031 são verificadas antes das suítes. pgTAP e pytest executam em
sequência para não disputar fixtures no banco compartilhado.

As três variáveis `BINGO_TEST_DATABASE_URL`, `BINGO_RPC_TEST_DATABASE_URL` e
`BINGO_MIGRATION_TEST_DATABASE_URL` apontam para
`postgresql://postgres:postgres@127.0.0.1:54322/postgres`, exclusivamente local.
O pytest gera JUnit e a CI rejeita coleta vazia ou qualquer teste ignorado,
incluindo skips por indisponibilidade de infraestrutura. Falhas exibem diagnóstico
dos containers; o ambiente efêmero é encerrado ao final. Não são necessários
tokens de conta ou credenciais de Supabase hospedado.

Alterações em backend/testes, `database/**`, `supabase/**`, manifests do CLI e no
próprio workflow acionam a CI. As etapas seguem o
[fluxo local documentado pelo Supabase](https://supabase.com/docs/guides/local-development/cli/getting-started).

Para reproduzir, em `Software`, execute `supabase start`,
`supabase db reset --local` e `supabase test db --local` usando o CLI instalado
(`node node_modules/supabase/dist/supabase.js`). Configure as três URLs acima e
`PYTHONPATH=backend/src`; execute `.venv/Scripts/python.exe -m pytest backend/tests -q -rs`.
Em `apps/admin_web`, com Angular local em :8106, execute `npm test` e, em seguida,
`BINGO_ADMIN_INTEGRATION=1 npm run test:integration` (no PowerShell, atribua o valor
via `$env:BINGO_ADMIN_INTEGRATION = '1'`). Os smokes reais só aceitam endpoints locais.

## Merge e promoção de banco

O merge em `develop` versiona código, migrations e testes; não exige nem executa
promoção imediata ao Supabase hospedado. Esta entrega não executa `db push`,
seeds remotos ou deploy. A leitura depende da 031: disponibilizar o Admin em um
ambiente sem essa RPC produz erro explícito de leitura, sem fallback demo.

A promoção futura é uma operação separada: consultar o histórico do ambiente,
validar dependências e dados legados das migrations pendentes, aplicar os trilhos
Supabase em ordem (incluindo 030/031 quando ainda ausentes), conferir grants/RLS
e executar smoke Auth/RPC/Angular A/B/C antes de liberar a versão nesse ambiente.
A aprovação local não comprova homologação no `bingo-dev` ou em produção.
