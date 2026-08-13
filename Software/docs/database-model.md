# Modelo de dados — descarte e bônus ambiental V1

Revisão: `2026-08-13`

O modelo V1 separa três conceitos. BinCoins são o saldo individual e gastável do aluno; XP mede o progresso coletivo da turma; e a categoria ambiental descreve o lixo eletrônico confirmado no Totem. Todo descarte válido parte da mesma recompensa-base. A categoria pode acrescentar BinCoins, mas nunca altera o XP.

## Pontuação

`school_settings.deposit_bincoins_base` guarda a base individual, inicialmente `8`. `school_settings.deposit_class_xp_base` guarda o XP por descarte válido, inicialmente `19`. `school_settings.class_weekly_xp_goal`, inicialmente `100`, é a meta usada por consultas de progresso; o saldo acumulado da turma não é zerado semanalmente.

O cálculo server-side é:

```text
bônus = round(deposit_bincoins_base × waste_categories.bonus_rate)
BinCoins do evento = deposit_bincoins_base + bônus
XP do evento = deposit_class_xp_base
```

Sem aluno identificado, o evento válido concede `0` BinCoins, bônus efetivo `0` e o XP normal à turma. Evento inválido concede `0/0` e não recebe categoria canônica. O tamanho físico e todas as configurações `SMALL`, `MEDIUM` e `LARGE` foram removidos pela migration V1.

## Catálogo canônico

`waste_categories` é um catálogo global com UUID interno, código público estável, nome para exibição, `bonus_rate`, estado ativo e timestamps. Os códigos V1 são `BATTERY`, `MOBILE_DEVICE`, `CABLE_WIRE`, `PERIPHERAL`, `OTHER_EWASTE` e `UNKNOWN`.

A migration cria o catálogo com todas as taxas em zero. Somente as seeds de desenvolvimento aplicam a matriz provisória: `BATTERY = 1.0000`, `MOBILE_DEVICE = 0.5000`, `CABLE_WIRE = 0.2500` e as demais categorias em zero. Produção não deve ativar esses valores antes da aprovação formal. Categorias deixam de ser utilizadas por `is_active = false`; registros referenciados não são excluídos.

## Evento de descarte

`deposits` representa um evento lógico e mantém `event_id` único, escola, máquina, turma, aluno opcional, validade, `detected_type`, categoria canônica, origem da categoria, recompensa concedida e instante do evento. `detected_type` preserva a classificação observada; `waste_category_id` aponta para a decisão canônica confirmada ou corrigida.

`category_source` aceita `AI_CONFIRMED`, `USER_CORRECTED` ou `UNIDENTIFIED`. `UNKNOWN` deve ser combinado com `UNIDENTIFIED`; categorias conhecidas devem ser confirmadas pela IA ou corrigidas pelo aluno.

`bonus_rate_applied` e `bonus_bincoins_awarded` são fotografias históricas. `points_awarded_student` guarda o total de BinCoins do evento e `points_awarded_class` guarda o XP. Alterar uma taxa ou a base no futuro não recalcula descartes anteriores.

## Atomicidade e acesso

`register_deposit_v1` é uma função PostgreSQL `security definer` com `search_path` vazio. Ela deriva a escola da máquina, valida as relações, resolve uma categoria ativa, calcula a recompensa, insere o evento, atualiza os saldos e grava a auditoria na mesma transação.

O primeiro insert usa `event_id` como barreira de concorrência. Retry com os mesmos dados retorna a fotografia existente; reutilização com máquina, turma, aluno, validade, classificação ou categoria diferente é rejeitada. Assim não existe evento sem recompensa correspondente, recompensa sem evento, saldo duplicado ou auditoria duplicada.

A execução da RPC foi revogada de `public`, `anon` e `authenticated` e concedida somente a `service_role`. Para autenticar a máquina, esse papel recebe apenas `SELECT (id, school_id, api_key_hash)` em `machines`; não recebe leitura ampla nem escrita, e os papéis `anon` e `authenticated` continuam sem acesso ao hash. Os papéis públicos também não podem inserir, atualizar ou excluir descartes, saldos, configurações, auditoria ou categorias. A Edge Function `register-deposit-v1` autentica a máquina e chama a RPC com o papel técnico.

## Migration e compatibilidade

Os arquivos de migration `005` materializam a pontuação e a RPC original. A migration `006` acrescenta `category_source` à fotografia retornada preservando o núcleo atômico já versionado, e a migration `007` concede a leitura mínima de `machines` necessária à autenticação. Antes de remover `size`, descartes válidos preexistentes são associados a `UNKNOWN` com bônus zero; depois a coluna e as configurações por tamanho são eliminadas.

O repositório é a fonte adotada nesta etapa. A existência dos arquivos não comprova aplicação no projeto Supabase hospedado. Antes de qualquer deploy, verificar o histórico remoto e exportar valores históricos de `size` caso tenham valor operacional fora deste baseline.
