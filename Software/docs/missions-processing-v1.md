# Contrato de processamento — Missões V1

Revisão: `2026-09-17`

Status: decisões de domínio e processamento aprovadas; implementação server-side ainda pendente.

## Objetivo

Este documento define como o backend deve detectar, materializar e recompensar conclusões de Missões V1.

Ele complementa `missions-contract-v1.md`.

A leitura de progresso permanece independente deste fluxo. O Mobile pode consultar progresso, meta, `is_achieved` e `is_completed`, mas não possui autoridade para declarar uma missão concluída nem para solicitar valores de recompensa como verdade.

O backend é a única autoridade sobre:

- progresso;
- atingimento da meta;
- conclusão;
- destinatários;
- BinCoins;
- XP;
- aplicações econômicas;
- auditoria.

---

## Princípio central

A conclusão de uma missão não depende do Mobile.

O Mobile não envia:

- progresso;
- `is_achieved`;
- `is_completed`;
- `student_id`;
- `class_id`;
- `school_id`;
- valores de recompensa;
- `achieved_at`.

O backend deriva essas informações exclusivamente das fontes autoritativas persistidas.

Uma missão deve poder ser concluída e recompensada mesmo que o aluno nunca abra o aplicativo após atingir a meta.

---

## Relação com o fluxo de descarte

O registro do descarte e o processamento de Missões são operações server-side separadas.

O descarte é a operação prioritária.

O sucesso do descarte não pode depender do sucesso do motor de Missões.

Fluxo conceitual:

```text
descarte
↓
register_deposit_v1
↓
depósito + efeitos normais do descarte
+ pendência durável de Missões
↓
COMMIT
↓
processamento de Missões

Uma falha posterior no motor de Missões não desfaz nem invalida um descarte já confirmado.
Pendência durável de processamento
Todo descarte persistido com sucesso deve deixar, atomicamente com o descarte, evidência persistida de que aquele evento precisa passar pelo processamento de Missões.
Essa pendência é baseada no evento de descarte e deve permitir retry seguro.
A pendência não deve duplicar informações autoritativas já disponíveis em deposits, como:
- student_id;
- class_id;
- progresso;
- meta;
- recompensa.
O processador deve recuperar essas informações novamente das fontes autoritativas.
A representação física da pendência será definida durante a implementação, sem introduzir estado desnecessário.
Processamento imediato e recuperação
Após o commit do descarte, o backend pode tentar processar suas Missões imediatamente.
Essa tentativa rápida existe para que a recompensa normalmente apareça logo após o descarte.
Ela não é a garantia de processamento.
A garantia é a pendência persistida.
Se a tentativa imediata falhar, um mecanismo de recuperação periódico deve localizar pendências ainda não concluídas e tentar novamente.
Os dois caminhos devem utilizar a mesma lógica autoritativa de processamento.
CAMINHO RÁPIDO
descarte
↓
tentativa imediata

CAMINHO DE RECUPERAÇÃO
pendência persistida
↓
retry posterior

AMBOS
↓
mesma operação idempotente

Seleção das Missões afetadas
O processamento parte de um descarte persistido identificado por seu event_id.
Os ciclos afetados são determinados pelo instante histórico do depósito:
cycle.starts_at <= deposit.created_at
AND deposit.created_at < cycle.ends_at

Não deve ser usado o horário atual do worker para decidir a qual ciclo o evento pertence.
Isso permite processar corretamente, inclusive depois do encerramento do ciclo, um descarte historicamente pertencente ao período.
Descarte válido com aluno identificado
Pode afetar:
- Missões STUDENT;
- Missões CLASS.
Descarte válido anônimo
Pode afetar:
- Missões CLASS.
Não pode afetar Missões STUDENT.
Descarte inválido
Não afeta nenhuma métrica atualmente aprovada de Missões V1.
Pode ser encerrado pelo processador sem cálculo de conclusão.
Progresso autoritativo
O evento que dispara o processamento serve para identificar quais Missões precisam ser reavaliadas.
Ele não deve ser usado simplesmente como incremento de contador.
O backend recalcula o progresso autoritativo a partir de deposits, conforme missions-contract-v1.md.
Para STUDENT / VALID_DEPOSIT_COUNT:
- contar depósitos válidos do aluno;
- respeitar o período do ciclo.
Para CLASS / CLASS_XP_EARNED:
- somar points_awarded_class;
- respeitar a turma histórica gravada no depósito;
- respeitar o período do ciclo.
O Mobile não participa desses cálculos.
Progresso após conclusão
O progresso continua sendo derivado normalmente depois que a missão foi concluída.
Portanto, pode ultrapassar a meta.
Exemplo:
target = 10
progress = 17
is_achieved = true
is_completed = true

Na V1, progresso excedente:
- não cria uma nova conclusão;
- não altera achieved_at;
- não gera recompensa adicional;
- não gera bônus extra.
A recompensa permanece única por conclusão.
Materialização
Quando o progresso autoritativo comprova que a meta foi atingida, o backend pode materializar a conclusão.
A materialização compreende, quando aplicável:
- mission_completions;
- alterações de saldo;
- mission_reward_applications;
- auditoria.
A existência de progresso suficiente não autoriza o cliente a solicitar ou informar a recompensa.
A decisão e os valores vêm sempre do ciclo persistido.
Atomicidade por evento
Todas as consequências de Missões processadas para um mesmo event_id são atômicas.
Se um único descarte fizer com que várias Missões sejam concluídas, todas elas devem ser preparadas e materializadas dentro da mesma transação econômica.
Exemplo:
event_id ABC
↓
Missão A concluída
Missão B concluída
Missão C concluída

Resultado permitido:
A + B + C + recompensas + ledger + auditoria
↓
COMMIT

Ou:
qualquer falha
↓
ROLLBACK de tudo

Não é permitido deixar apenas parte das consequências daquele evento aplicada.
Uma pendência só pode ser considerada processada depois do sucesso integral dessa transação.
Preparação antes das escritas
Antes de materializar efeitos econômicos, o backend deve determinar e validar:
- ciclos afetados;
- participantes;
- progresso;
- metas atingidas;
- conclusões já existentes;
- destinatários;
- recompensas;
- limites dos saldos;
- relacionamentos necessários.
A execução física das escritas continua dentro de uma única transação.
O COMMIT é a confirmação conjunta dos efeitos.
Recompensas STUDENT
Para missão STUDENT:
reward_bincoins
→ aluno que concluiu

reward_xp
→ turma cadastrada em students.class_id
   no instante do processamento/materialização

O progresso histórico da missão continua pertencendo ao aluno independentemente de trocas de turma.
O destino do XP é resolvido separadamente no processamento.
Depois que a recompensa foi materializada, uma futura troca de turma não redistribui nem recalcula esse XP.
Não existe divisão proporcional entre turmas históricas.
Recompensas CLASS
Para missão CLASS:
reward_xp
→ própria turma participante

reward_bincoins
→ cada aluno ACTIVE atualmente vinculado à turma

Cada aluno elegível recebe o valor integral configurado.
Não existe divisão de um pool entre os alunos.
students.is_activated não participa da seleção.
A lista real de destinatários fica congelada pelas aplicações de recompensa persistidas.
Alunos que entrarem na turma posteriormente não recebem retroativamente aquela conclusão.
Alunos que saírem depois não perdem a recompensa já recebida.
Recompensa zero
Se um tipo de recompensa tiver valor 0, nenhum efeito econômico daquele tipo é aplicado.
Também não deve ser criada aplicação de recompensa de valor zero.
Exemplo:
reward_bincoins = 500
reward_xp = 0

Resultado:
+500 BinCoins
nenhuma aplicação XP

Ledger econômico
mission_reward_applications é o histórico autoritativo dos efeitos econômicos realmente aplicados.
Para cada efeito positivo deve existir uma aplicação correspondente ao destinatário real.
Exemplo de missão CLASS com BinCoins para 30 alunos elegíveis:
30 destinatários
→ 30 aplicações BINCOINS

Isso preserva quem efetivamente recebeu a recompensa no instante da materialização.
Uma mudança posterior de turma ou vínculo não altera aplicações históricas.
Idempotência
O processamento deve poder ser repetido sem duplicar efeitos.
As garantias mínimas são:
- no máximo uma conclusão por ciclo + participante;
- no máximo uma aplicação equivalente por conclusão + tipo + destinatário;
- retries do mesmo evento não duplicam saldo;
- execução concorrente não duplica recompensa;
- auditoria não é usada como mecanismo primário de idempotência.
Uma conclusão já existente significa que aquela recompensa não deve ser concedida novamente.
O progresso, entretanto, continua acumulando normalmente até o fim do ciclo.
Concorrência
Cada pendência de event_id deve ser processada de forma segura mesmo com vários workers.
A estratégia aprovada é utilizar locking do PostgreSQL, incluindo mecanismo equivalente a:
FOR UPDATE SKIP LOCKED

para evitar que dois workers processem simultaneamente a mesma pendência.
O estado transitório de processamento não precisa ser persistido como status apenas para representar um lock.
Se o worker morrer, a transação é desfeita e o PostgreSQL libera o lock.
Concorrência entre eventos diferentes
Eventos diferentes podem tentar concluir a mesma missão ou alterar os mesmos saldos simultaneamente.
O backend deve utilizar ordem determinística de locks para reduzir risco de deadlock.
A ordem conceitual aprovada é:
turma(s)
↓
aluno(s) em ordem determinística de UUID
↓
conclusões
↓
efeitos econômicos

Depois de aguardar os locks necessários, os relacionamentos relevantes devem ser revalidados antes da materialização.
Constraints e índices únicos do banco permanecem como última barreira contra duplicidade.
Processamento em lote
O recuperador pode localizar várias pendências em uma execução.
Entretanto, cada event_id deve possuir sua própria transação econômica.
Exemplo:
ABC → transação própria
DEF → transação própria
GHI → transação própria

Uma pendência problemática não deve causar rollback de eventos independentes encontrados no mesmo lote.
Overflow e integridade econômica
Antes de gravar saldos, os cálculos devem ser realizados em tipo suficientemente amplo, usando bigint quando necessário.
O backend deve validar antecipadamente que:
saldo atual + recompensa

pode ser representado pelo tipo persistido da coluna.
Se qualquer destinatário não puder receber o valor com segurança:
ROLLBACK de todo o processamento daquele event_id

Em missão CLASS, se um único aluno entre vários destinatários causar falha econômica, nenhum dos demais recebe parcialmente naquela tentativa.
Auditoria
A auditoria complementa o ledger, mas não substitui:
- mission_completions;
- mission_reward_applications;
- constraints de idempotência.
A intenção para V1 é registrar auditoria da materialização de forma agregada, evitando criar um audit_log apenas para repetir cada linha individual do ledger.
Os nomes e metadados físicos devem seguir o padrão real de audit_logs existente no projeto e serão definidos durante a implementação após inspeção do schema atual.
Não devem ser inventados campos de auditoria que não existam no modelo real.
Falha e rollback
Se qualquer etapa econômica falhar:
ROLLBACK integral

Isso inclui:
- completions;
- saldos;
- reward applications;
- auditoria;
- marcação final da pendência.
O descarte original já persistido permanece válido.
A pendência continua disponível para processamento posterior.
Registro operacional de falha
Informações operacionais de uma tentativa que falhou não devem depender da mesma transação econômica que sofreu rollback.
Após o rollback, uma transação operacional separada pode registrar informações equivalentes a:
- número de tentativas;
- último erro sanitizado;
- instante permitido para próxima tentativa.
A representação física exata será definida durante a implementação.
Erros armazenados não devem expor segredos, credenciais ou dados internos sensíveis.
Retry e backoff
Retries não devem ocorrer continuamente sem intervalo.
A V1 utilizará backoff progressivo conceitualmente equivalente a:
tentativa imediata
↓ falhou

retry ~1 minuto
retry ~5 minutos
retry ~15 minutos
retry ~1 hora
demais retries → aproximadamente uma vez por hora

Os valores físicos podem ser ajustados durante a implementação sem mudar o princípio do contrato.
Uma pendência não é abandonada automaticamente por ter falhado muitas vezes.
Não existe estado permanente equivalente a:
FAILED_FOREVER

Falhas repetidas podem ser sinalizadas futuramente para intervenção operacional, sem eliminar a possibilidade de processamento posterior.
Segurança
Nenhuma operação cliente deve permitir:
"completei a missão"
"me dê esta recompensa"
"meu progresso é X"
"minha turma é Y"

como informação autoritativa.
O Mobile permanece consumidor de leitura.
A materialização deve estar disponível somente através de caminhos server-side autorizados.
Conhecer um cycle_id, event_id ou outros identificadores não deve permitir que um usuário autenticado conceda recompensas a si próprio.
Relação com a RPC de leitura
get_active_missions_v1() continua sendo somente leitura.
Ela pode apresentar:
- progress;
- target;
- is_achieved;
- achieved_at;
- is_completed;
- materialized_at.
Ela não materializa:
- completion;
- recompensa;
- saldo;
- auditoria;
- pendência.
É permitido existir temporariamente:
is_achieved = true
is_completed = false

Isso representa uma meta historicamente atingida cuja materialização ainda não terminou.
Após processamento bem-sucedido:
is_achieved = true
is_completed = true

Princípios finais
Missões V1 seguem estas garantias:
1. o descarte não depende do sucesso do motor de Missões;
2. todo descarte persistido deixa uma pendência durável de processamento;
3. conclusão e recompensa são exclusivamente server-side;
4. o Mobile nunca é autoridade sobre progresso ou economia;
5. deposits permanece a fonte histórica de progresso;
6. retries são seguros;
7. concorrência não pode duplicar recompensa;
8. um event_id é economicamente atômico;
9. falha parcial provoca rollback integral;
10. pendências nunca são descartadas automaticamente;
11. progresso pode continuar crescendo após conclusão;
12. recompensa é aplicada uma única vez;
13. ledger preserva os destinatários históricos reais;
14. qualquer efeito econômico deve ser auditável;
15. nenhuma falha em Missões invalida um descarte já confirmado.
Fora do escopo deste contrato
Continuam fora deste slice:
- interface Mobile de celebração;
- animações de recompensa;
- notificações;
- histórico visual de Missões encerradas;
- bônus por ultrapassar a meta;
- ranking;
- cálculo ou leitura da Jornada/BinGópolis dentro do motor de Missões;
- ENVIRONMENTAL_IMPACT;
- boosts;
- CRUD de BINGO_ADMIN;
- definição final do mecanismo de agendamento periódico;
- política de monitoramento/alerta operacional;
- aplicação no bingo-dev;
- produção.

## Integração separada com a Jornada

A Jornada da Turma, definida em `class-journey-v1.md`, observa novas linhas de `mission_completions` por trigger server-side idempotente. Ela não altera `process_mission_event_v1`, recompensas, saldos, auditoria econômica ou retry de Missões.

Para uma completion `STUDENT`, o destino econômico de XP continua sendo a turma atual do aluno na materialização. A contribuição da Jornada usa outra semântica: reconstrói deterministicamente o depósito válido na posição `mission_cycles.target`, ordenado por `deposits.created_at, deposits.id`, exige igualdade entre o `created_at` reconstruído e `achieved_at` e fotografa a `class_id` daquele depósito. Para `CLASS`, a Jornada usa a `class_id` persistida na completion. Essa diferença é intencional e testada.
