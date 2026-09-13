# Modelo de dados — descarte e bônus ambiental V1

Revisão: `2026-09-13`

O modelo V1 separa três conceitos. BinCoins são o saldo individual e gastável do aluno; XP mede o progresso coletivo da turma; e a categoria ambiental descreve o lixo eletrônico confirmado no Totem. Todo descarte válido parte da mesma recompensa-base. A categoria pode acrescentar BinCoins, mas nunca altera o XP.

## Pontuação

Na regra-alvo aprovada, `school_settings.deposit_bincoins_base` guarda `800` BinCoins, `school_settings.deposit_class_xp_base` guarda `1900` XP por descarte válido e `school_settings.class_weekly_xp_goal` guarda `10000` XP. Esses valores correspondem à redenominação por fator `100` das antigas unidades `8`, `19` e `100`; a relação econômica permanece equivalente. A nova escala é unidade oficial de domínio e persistência, não multiplicação visual aplicada pelo frontend. O saldo acumulado da turma continua sem ser zerado semanalmente.

O cálculo server-side é:

```text
bônus = round(deposit_bincoins_base × waste_categories.bonus_rate)
BinCoins do evento = deposit_bincoins_base + bônus
XP do evento = deposit_class_xp_base
```

O percentual não é redenominado. Exemplo: na unidade antiga, base `8` com `bonus_rate = 0.50` produzia bônus `4` e total `12`; na unidade nova, base `800` com a mesma taxa produz bônus `400` e total `1200`.

Sem aluno identificado, o evento válido concede `0` BinCoins, bônus efetivo `0` e o XP normal à turma. Evento inválido concede `0/0` e não recebe categoria canônica. O tamanho físico e todas as configurações `SMALL`, `MEDIUM` e `LARGE` foram removidos pela migration V1.

## Catálogo canônico

`waste_categories` é um catálogo global com UUID interno, código público estável, nome para exibição, `bonus_rate`, estado ativo e timestamps. Os códigos V1 são `BATTERY`, `MOBILE_DEVICE`, `CABLE_WIRE`, `PERIPHERAL`, `OTHER_EWASTE` e `UNKNOWN`.

A migration cria o catálogo com todas as taxas em zero. Somente as seeds de desenvolvimento aplicam a matriz provisória: `BATTERY = 1.0000`, `MOBILE_DEVICE = 0.5000`, `CABLE_WIRE = 0.2500` e as demais categorias em zero. Produção não deve ativar esses valores antes da aprovação formal. Categorias deixam de ser utilizadas por `is_active = false`; registros referenciados não são excluídos.

## Evento de descarte

`deposits` representa um evento lógico e mantém `event_id` único, escola, máquina, turma, aluno opcional, validade, `detected_type`, categoria canônica, origem da categoria, recompensa concedida e instante do evento. `detected_type` preserva a classificação observada; `waste_category_id` aponta para a decisão canônica confirmada ou corrigida.

`category_source` aceita `AI_CONFIRMED`, `USER_CORRECTED` ou `UNIDENTIFIED`. `UNKNOWN` deve ser combinado com `UNIDENTIFIED`; categorias conhecidas devem ser confirmadas pela IA ou corrigidas pelo aluno.

`bonus_rate_applied` e `bonus_bincoins_awarded` são fotografias históricas. `points_awarded_student` guarda o total de BinCoins do evento e `points_awarded_class` guarda o XP. Alterar uma taxa ou a base no futuro não recalcula descartes anteriores.

## Redenominação e normalização pendentes

A regra-alvo `800/1900/10000` ainda não está materializada nas migrations ou no runtime. Até uma implementação coordenada, `register_deposit_v1`, os dados locais e os dados hospedados podem continuar usando `8/19/100`; este documento não declara conversão do `bingo-dev` nem de produção.

A futura implementação deverá manter uma única unidade coerente e analisar, no mínimo, `school_settings.deposit_bincoins_base`, `school_settings.deposit_class_xp_base`, `school_settings.class_weekly_xp_goal`, `students.points_student_balance`, `classes.points_class_balance`, `deposits.points_awarded_student`, `deposits.points_awarded_class`, `deposits.bonus_bincoins_awarded`, `rewards.cost_points` e as metas e recompensas de missões. Novos lançamentos na escala nova não podem coexistir operacionalmente com saldos ou snapshots ainda interpretados na escala antiga. Custos de resgate também deverão ser normalizados para preservar equivalência econômica.

Para o `bingo-dev`, permanece pendente escolher entre converter os poucos dados existentes ou recriar/resetar somente dados DEV comprovadamente descartáveis. Nenhuma dessas opções está aprovada por este documento. A estratégia também deverá preservar a auditabilidade: `audit_logs.metadata` pode conter snapshots na unidade antiga e não deve ser reescrito silenciosamente. Antes da implementação, deverá ser decidido se a redenominação será registrada por documentação/evento de migração, conversão controlada ou recriação autorizada de dados DEV descartáveis.

## Atomicidade e acesso

`register_deposit_v1` é uma função PostgreSQL `security definer` com `search_path` vazio. Ela deriva a escola da máquina, valida as relações, resolve uma categoria ativa, calcula a recompensa, insere o evento, atualiza os saldos e grava a auditoria na mesma transação.

O primeiro insert usa `event_id` como barreira de concorrência. Retry com os mesmos dados retorna a fotografia existente; reutilização com máquina, turma, aluno, validade, classificação ou categoria diferente é rejeitada. Assim não existe evento sem recompensa correspondente, recompensa sem evento, saldo duplicado ou auditoria duplicada.

A execução da RPC foi revogada de `public`, `anon` e `authenticated` e concedida somente a `service_role`. Para autenticar a máquina, esse papel recebe apenas `SELECT (id, school_id, api_key_hash)` em `machines`; não recebe leitura ampla nem escrita, e os papéis `anon` e `authenticated` continuam sem acesso ao hash. Os papéis públicos também não podem inserir, atualizar ou excluir descartes, saldos, configurações, auditoria ou categorias. A Edge Function `register-deposit-v1` autentica a máquina e chama a RPC com o papel técnico.

`check_backend_readiness_v1()` é a RPC mínima e somente leitura usada por `health-v1`. Ela não consulta tabelas nem regras de domínio; verifica apenas se o PostgreSQL não está em recovery e se `default_transaction_read_only` permite escrita. A função é `STABLE`, `SECURITY INVOKER`, possui `search_path` vazio e pode ser executada somente por `service_role`; `PUBLIC`, `anon` e `authenticated` estão explicitamente revogados.

## Supabase Auth e RLS

O baseline V1 liga a sessão por `auth.uid() → students.auth_user_id → school_id/class_id`. `auth_user_id` continua opcional para permitir alunos ainda não vinculados ao Auth, mas possui unicidade e índice; uma identidade Auth sem aluno associado não obtém contexto de domínio. RLS está habilitado em todas as onze tabelas de domínio: `schools`, `classes`, `students`, `admins`, `machines`, `rewards`, `deposits`, `redemptions`, `audit_logs`, `school_settings` e `waste_categories`.

As três policies privadas mínimas permitem a `authenticated` ler somente seu registro em `students`, sua turma em `classes` e sua escola em `schools`. Todas usam explicitamente `TO authenticated` e comparam a identidade por `(select auth.uid())`; as policies de escola e turma também conferem `school_id` para preservar o isolamento. Os grants expõem somente as colunas necessárias. O grant de `students.auth_user_id` é necessário porque as policies relacionadas consultam essa coluna sob o papel autenticado; o teste com usuários Auth reais comprovou que sua ausência produz `42501`. A própria RLS restringe essa coluna ao vínculo do usuário atual.

O catálogo global `waste_categories` possui policy explícita de leitura para `anon` e `authenticated` com `USING (true)`. A leitura inclui categorias ativas e inativas; nenhuma filtragem por `is_active` foi introduzida. Não existem policies de escrita direta para clientes, e os defaults de `postgres` foram corrigidos para que novas tabelas, sequences e funções não voltem a conceder privilégios implícitos aos papéis expostos.

## Migration e compatibilidade

Os arquivos de migration `005` materializam a pontuação e a RPC original. A migration `006` acrescenta `category_source` à fotografia retornada preservando o núcleo atômico já versionado, a migration `007` concede a leitura mínima de `machines` necessária à autenticação, a migration `008` estabelece grants mínimos, defaults seguros e o baseline de RLS/Auth e a migration `009` acrescenta a RPC restrita de readiness. Antes de remover `size`, descartes válidos preexistentes são associados a `UNKNOWN` com bônus zero; depois a coluna e as configurações por tamanho são eliminadas.

O repositório é a fonte adotada nesta etapa. A existência dos arquivos não comprova aplicação no projeto Supabase hospedado. Antes de qualquer deploy, verificar o histórico remoto e exportar valores históricos de `size` caso tenham valor operacional fora deste baseline. Uma migration futura ainda deverá materializar a redenominação e sua normalização; não há neste documento SQL de conversão nem afirmação de que qualquer ambiente remoto já foi alterado.
