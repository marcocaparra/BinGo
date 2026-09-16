# Contrato de domínio — Missões V1

Revisão: `2026-09-15`

Status: contrato conceitual aprovado; implementação ainda inexistente.

## Objetivo

Este documento consolida as decisões de produto, domínio, histórico, tempo, segurança e fronteiras de implementação para Missões V1. Ele orienta o desenho técnico da etapa seguinte, mas não define schema PostgreSQL, nomes definitivos de tabelas ou campos, endpoints, RPCs, Edge Functions ou repositories Flutter.

## Contexto e estado atual

As missões são metas globais do ecossistema BinGo acompanhadas por aluno ou turma. Suas definições são globais, mas cada execução concreta ocorre em um ciclo pertencente a uma escola. No primeiro slice, o progresso será derivado dos eventos persistidos em `deposits`, sem inscrição prévia, sem contador mantido pelo Mobile e sem alterar o fluxo físico de descarte. Ao atingir a meta, uma conclusão materializada deverá aplicar server-side os valores fixos configurados de BinCoins e XP.

O repositório já preserva em cada depósito os elementos históricos necessários para as métricas inicialmente aprovadas: `event_id`, `student_id`, `class_id`, `is_valid`, `points_awarded_class` e `created_at`. Também preserva os snapshots econômicos `bonus_rate_applied` e `bonus_bincoins_awarded`. Esses fatos não significam que o motor de missões exista.

O Mobile contém telas e dados locais de demonstração para missões, recompensas e BinGópolis. No fluxo autenticado, a tela informa que ainda não há fonte autorizada de missões. Esses mocks são referência visual e narrativa, não contrato de backend, catálogo oficial, regra econômica ou evidência de integração real.

Nesta etapa não foram criados artefatos de runtime: não há migration, tabela, função PostgreSQL, RLS, Edge Function, endpoint, repository Flutter, integração autenticada ou CRUD administrativo de missões.

## Decisões oficiais

- As missões e suas definições são globais, reutilizáveis e administradas centralmente pelo BinGo; não pertencem individualmente a uma escola.
- Cada ciclo pertence a exatamente uma escola e alcança automaticamente os participantes elegíveis daquela escola. A escola não cria nem controla a definição global.
- `BINGO_ADMIN` é a autoridade de produto prevista para a gestão futura do catálogo global. Administradores escolares não podem criar ou alterar regras globais de missão.
- O domínio separa definição/template, ciclo temporal e resultado do participante.
- Cada recorrência cria um novo ciclo lógico e histórico. Um registro de ciclo nunca deve ser simplesmente zerado para representar o período seguinte.
- As regras relevantes de um ciclo são historicamente estáveis. Alterações no template afetam somente ciclos futuros.
- O snapshot é congelado atomicamente quando o ciclo é criado.
- Não existe inscrição, adesão ou opt-in de aluno ou turma, nem cópia prévia de uma missão para cada participante.
- Os únicos escopos de participante aprovados no motor V1 são `STUDENT` e `CLASS`.
- Campanha/BinGópolis não é um terceiro escopo. É uma camada futura que poderá consumir conclusões de missões.
- As métricas aprovadas para o primeiro slice são quantidade de descartes válidos e XP conquistado pela turma durante o ciclo.
- `ENVIRONMENTAL_IMPACT` permanece planejada, mas sem unidade oficial e fora da primeira implementação.
- `deposits` é a fonte de verdade histórica do progresso inicial.
- A conclusão de um participante é materializada quando a meta é atingida e não encerra o ciclo para os demais.
- O timezone oficial de negócio é `America/Sao_Paulo`, com intervalos fechados no início e abertos no fim.
- Toda missão possui exatamente dois valores econômicos configuráveis no primeiro slice: BinCoins e XP. Cada valor pode ser zero, mas ambos não podem ser zero simultaneamente.
- Métrica e recompensa são conceitos independentes: o tipo da métrica não restringe qual dos dois valores de recompensa é positivo.
- Conclusões e aplicações de recompensas são efeitos server-side, materializados, idempotentes e auditáveis, com transação quando necessária.
- Para missão `STUDENT`, os BinCoins vão ao aluno e o XP vai à turma atual do aluno no instante da materialização.
- Para missão `CLASS`, o XP vai à própria turma e os BinCoins são concedidos integralmente a cada aluno vinculado à turma no instante da materialização.
- O relógio autoritativo das métricas é `deposits.created_at`; a conclusão pode ser materializada depois de `ends_at` quando a evidência que atingiu a meta estiver dentro do ciclo.

## Conceitos do domínio

### Definição ou template

Representa uma regra reutilizável do catálogo global: identidade e apresentação da missão, escopo, métrica, recorrência, meta e os valores configurados de `reward_bincoins` e `reward_xp`. A definição não pertence a uma escola, não representa um período já executado nem o progresso de um participante.

### Ciclo de missão

Representa uma execução temporal específica de uma definição para exatamente uma escola, por exemplo `Juntos pela Praça — Setembro/2026 — Escola A`. A mesma definição pode originar ciclos distintos e independentes para Escola A e Escola B no mesmo período.

O snapshot é congelado atomicamente quando o ciclo é criado. Deve preservar, no mínimo, escola, escopo, métrica, meta, período, timezone, recorrência ou revisão necessária à interpretação histórica, `reward_bincoins` e `reward_xp`. Não se fixam aqui os nomes ou a representação física dessas propriedades. O requisito é que uma mudança posterior no template não altere a interpretação nem a economia de ciclos passados ou em andamento. Se setembro nasceu com meta de `500 XP` e o template depois passou a `700 XP`, setembro continua com `500 XP`; um ciclo futuro poderá nascer com `700 XP`.

### Resultado do participante

Representa o progresso derivado e a conclusão materializada de um aluno ou de uma turma em um ciclo. O estado do resultado é independente do estado temporal do ciclo: um aluno pode concluir uma missão mensal no dia 12, receber os efeitos aprovados e o ciclo continuar vigente até o primeiro dia do mês seguinte para os demais participantes.

A conclusão preserva tanto o instante histórico em que a meta foi atingida quanto o instante em que foi materializada. As aplicações econômicas persistidas identificam os destinatários reais e tornam-se o histórico autoritativo do efeito, sem recalcular ou redistribuir recompensas depois.

Os nomes exatos de tabelas, campos e enums desses conceitos serão definidos no desenho do schema posterior.

```text
BINGO_ADMIN
    ↓
MISSION DEFINITION (conceitual)
    ↓
MISSION CYCLE DA ESCOLA (conceitual)
    ↓
STUDENT / CLASS ELEGÍVEIS, SEM INSCRIÇÃO
    ↓
DEPOSITS
    ↓
PROGRESS
    ↓
COMPLETION
    ↓
REWARD APPLICATION
    ↓
BALANCE / XP / AUDIT
    ↓
FUTURE CAMPAIGN / BINGÓPOLIS
```

## Escopos de participante

| Escopo | Participante | Regra histórica |
| --- | --- | --- |
| `STUDENT` | aluno identificado | o progresso acompanha `student_id` e não depende da turma atual do aluno; o destino do eventual XP é resolvido separadamente na materialização |
| `CLASS` | turma | cada contribuição pertence à `class_id` gravada no depósito |

`CAMPAIGN` não é um escopo de missão. Ranking, campanha, progressão de mapa, trilhas e restauração de cenário também não ampliam a lista de escopos do motor V1.

## Elegibilidade sem inscrição

Não existe botão obrigatório de participação, opt-in, tabela de inscrição de alunos, tabela de inscrição de turmas nem cópia prévia de missão por participante. Um ciclo `STUDENT` vale automaticamente para os alunos elegíveis da escola do ciclo; um ciclo `CLASS` vale automaticamente para as turmas elegíveis dessa escola.

Onboarding, primeiro login, PIN, confirmação de e-mail e criação de conta não fazem parte desta feature. O primeiro slice trabalha sobre alunos e turmas já existentes. O modelo atual possui atributos como `students.status` e `students.is_activated`, mas a regra normativa que distingue, para Missões, uma entidade meramente existente de uma entidade elegível ainda não está definida de forma inequívoca. Essa pendência operacional não autoriza criar uma tabela de participação.

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

Para Missões V1, `evento` significa exclusivamente `deposits.created_at`. Não será criado `occurred_at`, `discarded_at` ou timestamp equivalente, e `deposits` e `register_deposit_v1` não serão alterados para esse fim. Se um descarte físico ocorrer antes do fim do ciclo, mas só for persistido com `created_at >= ends_at`, ele não pertence ao ciclo anterior. Esse trade-off é aceito conscientemente no primeiro slice.

- Semana oficial: segunda-feira às `00:00` até a segunda-feira seguinte às `00:00`, em `America/Sao_Paulo`.
- Mês oficial: primeiro dia do mês às `00:00` até o primeiro dia do mês seguinte às `00:00`, em `America/Sao_Paulo`.

Missões poderão ser recorrentes, agendadas/eventuais e, futuramente, iniciadas manualmente por `BINGO_ADMIN`. A criação dos ciclos recorrentes deve ser idempotente: pode existir no máximo um ciclo da mesma definição, para a mesma escola e o mesmo período lógico. Escolas diferentes podem possuir ciclos independentes da mesma definição e período.

O mecanismo de geração automática não foi decidido. Esta documentação não escolhe entre cron, Edge Function agendada, geração sob demanda ou outra solução.

### Conclusão tardia e instante de atingimento

A conclusão pode ser materializada depois de `ends_at`. O que determina se a missão foi cumprida é a evidência histórica dos depósitos cujo `created_at` pertence ao período do ciclo; um depósito com `created_at >= ends_at` nunca completa o ciclo anterior. Não se usa `now()` para decidir se uma meta histórica foi válida.

O domínio deve preservar dois momentos distintos, com nomes físicos ainda a definir:

- instante em que a meta foi atingida, conceitualmente `achieved_at`;
- instante em que a conclusão foi materializada e persistida.

Em `VALID_DEPOSIT_COUNT`, `achieved_at` é o `created_at` do depósito válido que completa a quantidade-alvo em ordenação determinística. Em `CLASS_XP_EARNED`, é o primeiro `created_at` em que a soma acumulada determinística de `points_awarded_class` atinge ou ultrapassa a meta. O processamento posterior ao fim do ciclo não invalida esse resultado.

## Progresso derivado e idempotência

No primeiro slice, o progresso deve ser derivável de `deposits`. O Mobile não mantém nem incrementa um contador autoritativo. A unicidade já existente de `deposits.event_id` faz com que um retry idêntico do mesmo descarte seja naturalmente contado uma única vez pelas consultas de progresso.

O fluxo crítico `register_deposit_v1` não deve ser acoplado ao novo motor apenas para manter progresso de missão. O registro físico do descarte não pode falhar porque um subsistema de gamificação falhou.

Quando `progress >= target`, a conclusão deverá ser materializada para suportar a aplicação persistente das recompensas. Mesmo ciclo mais mesmo participante admite no máximo uma conclusão. Cada efeito econômico real admite no máximo uma aplicação para a combinação de conclusão, tipo de recompensa e destinatário. Aberturas repetidas do App, retries server-side, concorrência ou reavaliações de progresso não podem duplicar conclusão, BinCoins, XP ou audit logs relacionados.

Conclusão, aplicações econômicas e auditoria deverão ocorrer server-side na mesma operação transacional. A aplicação persistida funciona como ledger histórico e barreira de idempotência; `audit_logs` não substitui esse ledger. Em missão `CLASS` com BinCoins, podem existir várias aplicações individuais, uma para cada aluno destinatário. O Mobile pode solicitar ou consultar o processamento, mas nunca credita recompensa por conta própria. O desenho de schema e a fronteira de execução serão definidos em etapa posterior.

## Transferência de turma

Missões individuais acompanham a identidade histórica do aluno por `student_id`. Missões coletivas atribuem cada contribuição à `class_id` gravada no depósito.

Se um aluno mudar de turma durante o ciclo, depósitos anteriores continuam contribuindo para a turma histórica e depósitos novos contribuem para a nova turma. O histórico não é reescrito para refletir o vínculo atual do aluno.

Para efeitos econômicos, os vínculos são resolvidos no instante em que a conclusão é materializada:

- em missão `STUDENT`, os BinCoins pertencem ao aluno e o XP pertence integralmente à turma atual desse aluno;
- em missão `CLASS`, o XP pertence à própria turma e os BinCoins configurados pertencem integralmente a cada aluno atualmente vinculado a ela.

Não se congela a turma inicial de uma missão individual, não se divide XP entre turmas históricas, não se calcula proporção por depósito e não se pré-materializa a lista de membros de uma turma. Depois da aplicação, o ledger preserva a turma e os alunos que realmente receberam os efeitos. Uma mudança posterior de turma não recalcula nem remove recompensa; aluno que entrar na turma depois da conclusão não recebe retroativamente.

## Administração, segurança e autorização

O papel já existente `BINGO_ADMIN` é a autoridade central futura sobre definições globais. Administradores escolares permanecem limitados ao seu contexto e não podem definir nem modificar essas regras globais.

A existência do papel no legado não comprova autenticação administrativa equivalente na arquitetura oficial Supabase. Por isso, esta feature não implementa CRUD Admin de missões. Quando a implementação começar, templates oficiais poderão ser provisionados de forma controlada pelo backend, migrations ou seeds até que o fluxo administrativo seja desenhado e comprovado.

A leitura no Mobile deverá ser autenticada e autorizada server-side. A identidade autoritativa segue `auth.uid() → student → school_id → class_id`; o Mobile não envia `student_id`, `class_id` ou `school_id` como autoridade para selecionar participante. Para cada ciclo da escola, o progresso `STUDENT` é calculado para o próprio aluno e o progresso `CLASS` para sua turma atual. O próximo desenho técnico deve definir grants, RLS e/ou fronteira server-side que exponham somente ciclos e resultados permitidos, sem ampliar RLS de `deposits` para revelar eventos privados de outros alunos da turma. Nenhum cliente deve receber `service_role`, escrever progresso autoritativo ou alterar definições e ciclos diretamente.

## Templates recorrentes iniciais

| Template oficial planejado | Escopo | Métrica | Recorrência | Meta | Recompensa |
| --- | --- | --- | --- | --- | --- |
| Consistência Sustentável | `STUDENT` | `VALID_DEPOSIT_COUNT` | `MONTHLY` | valor numérico configurável e ainda pendente | `reward_bincoins` e `reward_xp` configuráveis; valores pendentes e não ambos zero |
| Juntos pela Praça | `CLASS` | `CLASS_XP_EARNED` | `MONTHLY` | valor numérico configurável, na nova unidade de XP, ainda pendente | `reward_bincoins` e `reward_xp` configuráveis; valores pendentes e não ambos zero |
| Salve o Planeta | pendente | impacto ambiental | mensal pretendida | fora do primeiro slice; unidade, escopo final e meta pendentes | a definir quando entrar no escopo; também deverá possuir ao menos uma recompensa |

`Juntos pela Praça` soma o XP histórico ganho durante o ciclo e nunca lê o saldo acumulado `classes.points_class_balance` como progresso mensal.

Sua meta não deve reutilizar automaticamente `school_settings.class_weekly_xp_goal`, pois se trata de missão mensal com regra própria. Nenhum valor numérico de meta ou recompensa está aprovado por exemplos ou mocks.

`Salve o Planeta` não deve ser implementada enquanto a unidade de impacto ambiental e seu escopo não forem aprovados. `bonus_bincoins_awarded` não é sua unidade por padrão.

## Bônus ambiental existente

O domínio de missões não altera a regra vigente de recompensa por descarte:

- descarte válido com aluno identificado recebe BinCoins-base;
- a categoria ambiental pode acrescentar bônus individual de BinCoins;
- o XP da turma não recebe multiplicador por categoria;
- `bonus_rate_applied` e `bonus_bincoins_awarded` são snapshots históricos;
- taxas usadas somente em seeds de desenvolvimento não constituem política de produção.

A unidade oficial aprovada foi redenominada por fator `100`: `8` BinCoins antigos correspondem a `800` BinCoins novos e `19` XP antigos correspondem a `1900` XP novos. Isso não multiplica `bonus_rate` nem representa aumento econômico real. A conversão está versionada e validada localmente e foi aplicada e aprovada no postflight do `bingo-dev`, sem implementação de schema ou recompensa de missões. Metas e recompensas futuras de Missões devem nascer diretamente na unidade nova. Essa evidência é exclusiva do DEV e não permite inferir o estado de produção.

## Recompensas de missão

Toda missão possui exatamente dois valores econômicos configuráveis no primeiro slice: `reward_bincoins` e `reward_xp`. Ambos são não negativos e pelo menos um deve ser maior que zero. Essa regra permite somente BinCoins, somente XP ou ambos, sem uma lista arbitrária de tipos de recompensa. Esses valores pertencem à definição para ciclos futuros e são congelados no snapshot de cada ciclo.

Métrica e recompensa não são acopladas: uma missão de `VALID_DEPOSIT_COUNT` pode conceder BinCoins e/ou XP, assim como uma missão de `CLASS_XP_EARNED`. A tabela existente `rewards` não deve ser reutilizada, pois representa catálogo físico resgatável, estoque e custo no BinBazar.

O destino é determinado pelo escopo e pelo vínculo vigente na materialização:

| Escopo | BinCoins | XP |
| --- | --- | --- |
| `STUDENT` | integralmente ao aluno que concluiu | integralmente à turma atual do aluno |
| `CLASS` | valor integral para cada aluno atualmente vinculado à turma | integralmente à própria turma |

Valores iguais a zero não geram efeito econômico. Cada efeito positivo efetivamente aplicado deve ser persistido com seu destinatário real. Em `CLASS`, `reward_bincoins = 1000` significa `1000` para cada aluno destinatário, nunca divisão de `1000` entre a turma.

Os valores numéricos ainda dependem de aprovação explícita e deverão usar a nova unidade oficial. Textos e números presentes nos mocks do Mobile continuam sem força normativa. Estoque, recompensa física e resgate permanecem fora do primeiro slice.

### Boosts e efeitos temporários

Boosts como percentual adicional de BinCoins por sete dias ou percentual adicional de XP durante determinado período são uma evolução futura, fora do primeiro slice. Não se define schema nem fórmula para eles neste contrato.

Se um boost vier a afetar um descarte, deverá ser processado server-side, ter período de validade, garantia de idempotência e snapshot do efeito efetivamente aplicado ao evento. Essa evolução exige revisão explícita do cálculo transacional de `register_deposit_v1`; a operação não é alterada nesta etapa.

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
- conclusão materializada e idempotente quando a meta for atingida;
- valores fixos `reward_bincoins` e `reward_xp`, com pelo menos um maior que zero;
- aplicação server-side, idempotente, auditável e transacional das recompensas;
- leitura autenticada autorizada;
- integração com a tela autenticada de Missões no Mobile.

## Fora de escopo

- Salve o Planeta enquanto a métrica ambiental não estiver fechada;
- campanha/BinGópolis e progressão de mapa;
- ranking e trilhas;
- boosts e outros efeitos temporários;
- estoque, recompensa física e resgate de recompensa de missão;
- notificações;
- CRUD real pelo Admin;
- nova autenticação administrativa;
- alterações no fluxo físico de descarte;
- mudanças em `register_deposit_v1`;
- contadores autoritativos mantidos pelo Mobile;
- inscrição, adesão ou cópias prévias de missão por aluno ou turma;

## Decisões pendentes

- desenho do schema e nomes definitivos de tabelas, campos, constraints e enums;
- representação física do snapshot imutável, já definido como congelado atomicamente na criação do ciclo;
- metas numéricas e valores concretos de `reward_bincoins` e `reward_xp` de Consistência Sustentável e Juntos pela Praça;
- unidade, escopo e meta de Salve o Planeta/`ENVIRONMENTAL_IMPACT`;
- mecanismo automático de criação de ciclos recorrentes;
- estados exatos do ciclo e do resultado do participante;
- regra operacional que distingue aluno/turma existente de participante elegível, inclusive o papel de `students.status` e `students.is_activated`, sem criar inscrição;
- contrato de leitura autenticada, paginação e ordenação para o Mobile;
- policies RLS, grants e eventual fronteira server-side de leitura;
- autenticação/autorização Supabase de `BINGO_ADMIN` e futuro CRUD global;
- comportamento e autorização do início manual futuro;
- desenho físico da conclusão materializada, do ledger idempotente de aplicações e dos audit logs correspondentes;
- garantia de que metas, recompensas, saldos e snapshots futuros de Missões nasçam diretamente na nova unidade oficial, sem misturar escalas;
- eventual modelo futuro de boosts, incluindo validade, snapshot do efeito e fórmula, sem mudança atual em `register_deposit_v1`.

## Próximos passos de implementação

1. Fechar o desenho técnico do schema incremental de Missões V1 sem alterar `register_deposit_v1`, incluindo ciclo por escola, snapshot histórico, conclusão materializada e ledger idempotente dos efeitos econômicos.
2. Definir o contrato de leitura autenticada e sua matriz de autorização para `STUDENT` e `CLASS`.
3. Criar migrations e testes de banco em tarefa própria, incluindo fronteiras temporais, idempotência de ciclo/conclusão/recompensa, transferência de turma e isolamento por autorização.
4. Provisionar somente os dois templates aprovados para o primeiro slice, com metas e recompensas configuradas após decisão explícita.
5. Implementar a leitura no Mobile autenticado somente depois que a fonte real e as políticas correspondentes estiverem comprovadas.
