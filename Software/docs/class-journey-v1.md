# Contrato de domínio — Jornada da Turma / BinGópolis V1

Atualizado em: `2026-09-22`

## Escopo e independência

A Jornada da Turma é um domínio próprio. Ela não é uma Mission, não participa do cálculo de conclusão de Missões e não altera recompensas, BinCoins ou XP. O domínio consome fatos históricos já aprovados — descartes e `mission_completions` — para calcular a restauração coletiva de BinGópolis.

Home, Ranking e mapa autenticados consomem o mesmo snapshot de Jornada. O Flutter controla somente assets e apresentação; campanha, pesos, progresso e estados são autoridade do backend. O modo piloto conserva sua simulação isolada.

## Campanha H2/2026

A primeira campanha usa `America/Sao_Paulo` e o intervalo semiaberto:

- início: `2026-07-01 00:00 America/Sao_Paulo`;
- fim exclusivo: `2027-01-01 00:00 America/Sao_Paulo`.

O modelo aceita campanhas semestrais sucessivas H1 (`01/01` a `01/07`) e H2 (`01/07` a `01/01` do ano seguinte). A V1 não possui scheduler de provisionamento.

Cada campanha fotografa seus pesos históricos:

- descarte válido: `1` unidade;
- conclusão `STUDENT`: `3` unidades;
- conclusão `CLASS`: `5` unidades.

Os pesos não dependem de constantes Flutter.

## Fontes e atribuição histórica

### Descartes

Cada linha de `deposits` contribui para a `class_id` histórica gravada nela quando:

```text
deposits.class_id = turma
deposits.is_valid = true
campaign.starts_at <= deposits.created_at
deposits.created_at < campaign.ends_at
```

O descarte pode ser identificado ou anônimo. Não existe ledger que copie descartes; sua contribuição permanece derivada da tabela autoritativa.

### Completion STUDENT

Uma conclusão `STUDENT / VALID_DEPOSIT_COUNT` contribui para a turma do depósito que efetivamente atingiu a meta. Para o `cycle_id` e `student_id` da completion, o backend:

1. seleciona somente descartes válidos do aluno com `cycle.starts_at <= created_at < cycle.ends_at`;
2. ordena deterministicamente por `deposits.created_at, deposits.id`;
3. escolhe o depósito cuja posição é `mission_cycles.target`;
4. exige que o `created_at` reconstruído seja igual a `mission_completions.achieved_at`;
5. fotografa a `class_id` daquele depósito no ledger da Jornada.

Não se usa a turma atual do aluno, proximidade temporal ou outra heurística. Falha de reconstrução é inconsistência de integridade e aborta a materialização/backfill correspondente.

Essa regra é intencionalmente diferente da economia de Missões:

**Missões STUDENT — destino econômico de XP**
→ turma atual do aluno na materialização.

**Jornada — contribuição de conclusão STUDENT**
→ turma histórica do depósito que atingiu a meta.

A Jornada atribui restauração à turma que realizou a ação conclusiva; a economia de Missões preserva seu contrato próprio.

### Completion CLASS

Uma conclusão `CLASS` contribui para a `class_id` persistida na própria `mission_completion`.

Para ambos os escopos, o pertencimento temporal à campanha usa `mission_completions.achieved_at`, nunca `materialized_at`.

## Modelo persistido

`journey_campaigns` preserva escola, intervalo, timezone, pesos e timestamp técnico. Campanhas da mesma escola não podem se sobrepor.

`journey_stages` preserva código, ordem e target por campanha. A campanha V1 possui exatamente:

1. `CENTRAL_SQUARE`, target `20`;
2. `SPRING_PARK`, target `25`;
3. `CREATIVE_SCHOOL`, target `30`.

`journey_mission_contributions` é o ledger imutável das completions. Ele preserva campanha, turma histórica destinatária, completion, escopo, unidades, instante histórico e, para `STUDENT`, o depósito de atingimento. A unicidade `(campaign_id, mission_completion_id)` e `ON CONFLICT` formam a barreira adicional de idempotência.

As três tabelas possuem RLS estrutural fechada e não concedem acesso direto a `anon`, `authenticated` ou `service_role`.

Não são persistidos percentual, total derivado ou estágio atual.

## Cálculo de progresso

```text
total_units =
  valid_deposit_count * campaign.discard_units
  + SUM(journey_mission_contributions.units_applied)
```

Os targets são consumidos sequencialmente, com carry-over integral. Estados permitidos:

- `ACTIVE`: estágio atual, inclusive com progresso zero após o anterior ser concluído;
- `LOCKED`: target anterior ainda não foi consumido;
- `COMPLETED`: target integralmente consumido.

Exemplo com total `27`:

- Praça Central: `20/20`, `COMPLETED`;
- Parque das Nascentes: `7/25`, `ACTIVE`;
- Escola Criativa: `0/30`, `LOCKED`.

Com total maior ou igual a `75`, os três estágios permanecem `COMPLETED`; não surge um quarto estágio.

## Captura e backfill

O trigger `mission_completions_capture_journey_v1` roda após a criação da completion. Ele localiza a campanha da escola que contém `achieved_at`, reconstrói o depósito `STUDENT` quando necessário e chama a gravação idempotente. Se não houver campanha correspondente, não cria contribuição.

`process_mission_event_v1` e o motor econômico não foram alterados. A operação interna `backfill_journey_campaign_v1(campaign_id)` reaplica a mesma validação e é idempotente; ela não possui grant para papéis expostos.

O seed DEV `database/seeds/011_bingo_dev_journey_h2_2026.sql` provisiona de forma idempotente a campanha H2/2026 e seus três estágios para a escola demo. Dados específicos do `bingo-dev` não fazem parte da migration estrutural.

## Leitura autenticada

`public.get_class_journey_v1()` não recebe parâmetros. Ela deriva exclusivamente:

```text
auth.uid() -> students.auth_user_id -> students.school_id/class_id
```

A função é `STABLE`, `SECURITY DEFINER`, usa `SET search_path = ''`, qualifica relações explicitamente e concede `EXECUTE` somente a `authenticated`. Conta sem aluno vinculado ou sem campanha vigente recebe zero linhas.

Cada uma das três linhas retorna campanha, intervalo, estágio, target, progresso, razão, estado, total, contagem de descartes, contagens de completions `STUDENT`/`CLASS` e unidades restantes do estágio.

## Mobile e impacto ambiental

O repository autenticado valida as três linhas como um único snapshot, a sequência, os targets V1, o carry-over e os estados. Os códigos são mapeados somente para os visuais existentes:

- `CENTRAL_SQUARE` → `central-square`;
- `SPRING_PARK` → `spring-park`;
- `CREATIVE_SCHOOL` → `creative-school`.

Home, Ranking e mapa reutilizam os mesmos componentes e assets. No modo autenticado não existe avanço local. O card da Home abre o mesmo mapa usado pelo Ranking.

Peso recuperado, quantidade simulada de alunos e demais métricas de `ScenarioImpactSnapshot` não possuem fonte autenticada aprovada. `ImpactScreen` permanece indisponível nesse modo e dados demo nunca são apresentados como remotos.

## Estado de promoção

A migration estrutural local é `database/migrations/021_class_journey_v1.sql`, espelhada por `supabase/migrations/20260922120000_class_journey_v1.sql`. Ela foi validada somente no Supabase local. A migration `021` e o seed DEV não foram aplicados ao `bingo-dev` nem a produção nesta etapa.
