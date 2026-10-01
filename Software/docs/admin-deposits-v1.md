# Admin Descartes V1

Atualizado em: `2026-10-01`.

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

## Validação local

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
