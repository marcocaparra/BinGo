# Contrato de domínio — Missões V1

Revisão: `2026-09-13`

Status: contrato conceitual aprovado; implementação ainda inexistente.

## Objetivo

Este documento consolida as decisões de produto, domínio, histórico, tempo, segurança e fronteiras de implementação para Missões V1. Ele orienta o desenho técnico da etapa seguinte, mas não define schema PostgreSQL, nomes definitivos de tabelas ou campos, endpoints, RPCs, Edge Functions ou repositories Flutter.

## Contexto e estado atual

As missões são metas globais do ecossistema BinGo acompanhadas por aluno ou turma. No primeiro slice, seu progresso será derivado dos eventos persistidos em `deposits`, sem contador mantido pelo Mobile e sem alterar o fluxo físico de descarte.

O repositório já preserva em cada depósito os elementos históricos necessários para as métricas inicialmente aprovadas: `event_id`, `student_id`, `class_id`, `is_valid`, `points_awarded_class` e `created_at`. Também preserva os snapshots econômicos `bonus_rate_applied` e `bonus_bincoins_awarded`. Esses fatos não significam que o motor de missões exista.

O Mobile contém telas e dados locais de demonstração para missões, recompensas e BinGópolis. No fluxo autenticado, a tela informa que ainda não há fonte autorizada de missões. Esses mocks são referência visual e narrativa, não contrato de backend, catálogo oficial, regra econômica ou evidência de integração real.

Nesta etapa não foram criados artefatos de runtime: não há migration, tabela, função PostgreSQL, RLS, Edge Function, endpoint, repository Flutter, integração autenticada ou CRUD administrativo de missões.

## Decisões oficiais

- As missões e suas definições são globais, reutilizáveis e administradas centralmente pelo BinGo; não pertencem individualmente a uma escola.
- `BINGO_ADMIN` é a autoridade de produto prevista para a gestão futura do catálogo global. Administradores escolares não podem criar ou alterar regras globais de missão.
- O domínio separa definição/template, ciclo temporal e resultado do participante.
- Cada recorrência cria um novo ciclo lógico e histórico. Um registro de ciclo nunca deve ser simplesmente zerado para representar o período seguinte.
- As regras relevantes de um ciclo são historicamente estáveis. Alterações no template afetam somente ciclos futuros.
- Os únicos escopos de participante aprovados no motor V1 são `STUDENT` e `CLASS`.
- Campanha/BinGópolis não é um terceiro escopo. É uma camada futura que poderá consumir conclusões de missões.
- As métricas aprovadas para o primeiro slice são quantidade de descartes válidos e XP conquistado pela turma durante o ciclo.
- `ENVIRONMENTAL_IMPACT` permanece planejada, mas sem unidade oficial e fora da primeira implementação.
- `deposits` é a fonte de verdade histórica do progresso inicial.
- A conclusão de um participante não encerra o ciclo para os demais.
- O timezone oficial de negócio é `America/Sao_Paulo`, com intervalos fechados no início e abertos no fim.
- Recompensa econômica por conclusão não faz parte do primeiro slice.

## Conceitos do domínio

### Definição ou template

Representa uma regra reutilizável do catálogo global: identidade e apresentação da missão, escopo, métrica, recorrência e meta configurada. A definição não representa um período já executado nem o progresso de um participante.

### Ciclo de missão

Representa uma execução temporal específica de uma definição, por exemplo `Juntos pela Praça — Setembro/2026`. Cada ciclo possui seu próprio período lógico e deve preservar snapshot suficiente das regras que determinaram seus resultados.

Não se fixa nesta documentação quais colunas guardarão esse snapshot. O requisito é que uma mudança posterior no template não altere a interpretação de ciclos passados ou em andamento. Se setembro nasceu com meta de `500 XP` e o template depois passou a `700 XP`, setembro continua com `500 XP`; um ciclo futuro poderá nascer com `700 XP`.

### Resultado do participante

Representa o progresso e a eventual conclusão de um aluno ou de uma turma em um ciclo. O estado do resultado é independente do estado temporal do ciclo: um aluno pode concluir uma missão mensal no dia 12, enquanto o ciclo continua vigente até o primeiro dia do mês seguinte para os demais participantes.

Os nomes exatos de tabelas, campos e enums desses conceitos serão definidos no desenho do schema posterior.

```text
BINGO_ADMIN
    ↓
MISSION DEFINITION (conceitual)
    ↓
MISSION CYCLE (conceitual)
    ↓
STUDENT / CLASS
    ↓
DEPOSITS
    ↓
PROGRESS
    ↓
COMPLETION
    ↓
FUTURE CAMPAIGN / BINGÓPOLIS
```

## Escopos de participante

| Escopo | Participante | Regra histórica |
| --- | --- | --- |
| `STUDENT` | aluno identificado | acompanha `student_id` e não depende da turma atual do aluno |
| `CLASS` | turma | cada contribuição pertence à `class_id` gravada no depósito |

`CAMPAIGN` não é um escopo de missão. Ranking, campanha, progressão de mapa, trilhas e restauração de cenário também não ampliam a lista de escopos do motor V1.

## Métricas e filtros de progresso

Os identificadores abaixo são representações conceituais sugeridas, não nomes obrigatórios de enum ou schema.

### Quantidade de descartes válidos (`VALID_DEPOSIT_COUNT`)

Para uma missão individual, o progresso é a contagem dos depósitos que atendam simultaneamente a:

- `student_id` correspondente ao participante;
- `is_valid = true`;
- `created_at` dentro do período do ciclo.

### XP conquistado pela turma (`CLASS_XP_EARNED`)

Para uma missão coletiva, o progresso é a soma de `points_awarded_class` dos depósitos que atendam simultaneamente a:

- `class_id` correspondente ao participante histórico;
- `is_valid = true`;
- `created_at` dentro do período do ciclo.

Deve ser usado o XP histórico armazenado em cada depósito. É proibido recalcular o progresso como quantidade de descartes multiplicada pelo XP configurado no presente. Também não deve ser usado `classes.points_class_balance`, pois esse saldo é acumulado e não é reiniciado a cada mês.

### Impacto ambiental (`ENVIRONMENTAL_IMPACT`)

Esta métrica é apenas planejada. Sua unidade oficial ainda não foi definida e ela não deve ser implementada no banco até nova decisão. Em particular, `bonus_bincoins_awarded` não pode ser adotado automaticamente como unidade permanente de impacto: o bônus econômico e a categoria ambiental têm relação de produto, mas poderão exigir calibrações independentes.

## Tempo, recorrência e fronteiras

O timezone oficial para formar períodos lógicos é `America/Sao_Paulo`. A persistência futura deverá representar instantes adequadamente, preferencialmente com `timestamptz`, sem perder a regra de calendário baseada nesse timezone.

Todos os períodos usam a fronteira:

```text
starts_at <= evento < ends_at
```

- Semana oficial: segunda-feira às `00:00` até a segunda-feira seguinte às `00:00`, em `America/Sao_Paulo`.
- Mês oficial: primeiro dia do mês às `00:00` até o primeiro dia do mês seguinte às `00:00`, em `America/Sao_Paulo`.

Missões poderão ser recorrentes, agendadas/eventuais e, futuramente, iniciadas manualmente por `BINGO_ADMIN`. A criação dos ciclos recorrentes deve ser idempotente: pode existir no máximo um ciclo da mesma definição para o mesmo período lógico.

O mecanismo de geração automática não foi decidido. Esta documentação não escolhe entre cron, Edge Function agendada, geração sob demanda ou outra solução.

## Progresso derivado e idempotência

No primeiro slice, o progresso deve ser derivável de `deposits`. O Mobile não mantém nem incrementa um contador autoritativo. A unicidade já existente de `deposits.event_id` faz com que um retry idêntico do mesmo descarte seja naturalmente contado uma única vez pelas consultas de progresso.

O fluxo crítico `register_deposit_v1` não deve ser acoplado ao novo motor apenas para manter progresso de missão. O registro físico do descarte não pode falhar porque um subsistema de gamificação falhou.

Se uma conclusão futuramente produzir recompensa, desbloqueio ou outro efeito persistente, a conclusão e o efeito deverão possuir idempotência e auditoria próprias, além de atomicidade quando necessária.

## Transferência de turma

Missões individuais acompanham a identidade histórica do aluno por `student_id`. Missões coletivas atribuem cada contribuição à `class_id` gravada no depósito.

Se um aluno mudar de turma durante o ciclo, depósitos anteriores continuam contribuindo para a turma histórica e depósitos novos contribuem para a nova turma. O histórico não é reescrito para refletir o vínculo atual do aluno.

## Administração, segurança e autorização

O papel já existente `BINGO_ADMIN` é a autoridade central futura sobre definições globais. Administradores escolares permanecem limitados ao seu contexto e não podem definir nem modificar essas regras globais.

A existência do papel no legado não comprova autenticação administrativa equivalente na arquitetura oficial Supabase. Por isso, esta feature não implementa CRUD Admin de missões. Quando a implementação começar, templates oficiais poderão ser provisionados de forma controlada pelo backend, migrations ou seeds até que o fluxo administrativo seja desenhado e comprovado.

A leitura no Mobile deverá ser autenticada e autorizada server-side. O próximo desenho técnico deve definir grants, RLS e/ou fronteira server-side que exponham somente ciclos e resultados permitidos ao aluno autenticado, com testes de isolamento. Nenhum cliente deve receber `service_role`, escrever progresso autoritativo ou alterar definições e ciclos diretamente.

## Templates recorrentes iniciais

| Template oficial planejado | Escopo | Métrica | Recorrência | Situação da meta |
| --- | --- | --- | --- | --- |
| Consistência Sustentável | `STUDENT` | quantidade de descartes válidos | mensal | valor numérico configurável e ainda pendente |
| Juntos pela Praça | `CLASS` | XP conquistado pela turma no ciclo | mensal | valor numérico configurável e ainda pendente |
| Salve o Planeta | pendente | impacto ambiental | mensal pretendida | fora do primeiro slice; unidade, escopo final e meta pendentes |

`Juntos pela Praça` soma o XP histórico ganho durante o ciclo e nunca lê o saldo acumulado `classes.points_class_balance` como progresso mensal.

`Salve o Planeta` não deve ser implementada enquanto a unidade de impacto ambiental e seu escopo não forem aprovados. `bonus_bincoins_awarded` não é sua unidade por padrão.

## Bônus ambiental existente

O domínio de missões não altera a regra vigente de recompensa por descarte:

- descarte válido com aluno identificado recebe BinCoins-base;
- a categoria ambiental pode acrescentar bônus individual de BinCoins;
- o XP da turma não recebe multiplicador por categoria;
- `bonus_rate_applied` e `bonus_bincoins_awarded` são snapshots históricos;
- taxas usadas somente em seeds de desenvolvimento não constituem política de produção.

## Recompensas de missão

O primeiro slice não concede crédito extra de BinCoins, XP extra, estoque, recompensa física, resgate ou ledger de recompensa por conclusão. Textos de recompensa presentes nos mocks do Mobile não aprovam esses efeitos econômicos.

Uma missão poderá gerar efeitos adicionais no futuro. Qualquer efeito econômico deverá ser executado server-side, ser idempotente, auditável e transacional quando necessário.

## Relação futura com campanha

Campanha/BinGópolis é uma camada posterior que poderá consumir resultados e conclusões de missões:

```text
deposits
  → progresso de missões
  → conclusões
  → campanha
  → restauração de cenário
  → desbloqueio do próximo setor
```

O primeiro slice não implementa campanha, progressão de mapa nem desbloqueio de setores.

## Primeiro vertical slice planejado

O primeiro slice futuro fica limitado a:

- catálogo/definições globais de missão;
- ciclos mensais;
- Consistência Sustentável;
- Juntos pela Praça;
- progresso derivado de `deposits`;
- leitura autenticada autorizada;
- integração com a tela autenticada de Missões no Mobile.

## Fora de escopo

- Salve o Planeta enquanto a métrica ambiental não estiver fechada;
- campanha/BinGópolis e progressão de mapa;
- ranking e trilhas;
- recompensas econômicas de missões;
- notificações;
- CRUD real pelo Admin;
- nova autenticação administrativa;
- alterações no fluxo físico de descarte;
- mudanças em `register_deposit_v1`;
- contadores autoritativos mantidos pelo Mobile.

## Decisões pendentes

- desenho do schema e nomes definitivos de tabelas, campos, constraints e enums;
- representação exata do snapshot imutável das regras de cada ciclo;
- metas numéricas de Consistência Sustentável e Juntos pela Praça;
- unidade, escopo e meta de Salve o Planeta/`ENVIRONMENTAL_IMPACT`;
- mecanismo automático de criação de ciclos recorrentes;
- estados exatos do ciclo e do resultado do participante;
- contrato de leitura autenticada, paginação e ordenação para o Mobile;
- policies RLS, grants e eventual fronteira server-side de leitura;
- autenticação/autorização Supabase de `BINGO_ADMIN` e futuro CRUD global;
- comportamento e autorização do início manual futuro;
- modelo idempotente, auditável e transacional para eventuais efeitos de conclusão.

## Próximos passos de implementação

1. Desenhar o schema incremental sem alterar `register_deposit_v1`, incluindo as garantias de unicidade do ciclo e snapshot histórico.
2. Definir o contrato de leitura autenticada e sua matriz de autorização para `STUDENT` e `CLASS`.
3. Criar migrations e testes de banco em tarefa própria, incluindo fronteiras temporais, idempotência de ciclo, transferência de turma e isolamento por autorização.
4. Provisionar somente os dois templates aprovados para o primeiro slice, com metas configuradas após decisão explícita.
5. Implementar a leitura no Mobile autenticado somente depois que a fonte real e as políticas correspondentes estiverem comprovadas.
