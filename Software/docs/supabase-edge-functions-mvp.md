# Supabase Edge Functions do MVP

Data de consolidação: `2026-08-10`  
Branch de referência: `feature/supabase-edge-functions-mvp`  
Status: referência arquitetural para implementação futura; nenhuma Edge Function é entregue por este documento.

## Como ler este documento

- **Decisão oficial:** direção já definida pelo projeto ou por esta feature.
- **Estado comprovado:** fato verificado no `HEAD` da branch indicada.
- **Decisão histórica:** registro válido para explicar o histórico, mas que não comprova entrega no baseline atual.
- **Hipótese:** interpretação que ainda exige validação.
- **Sugestão:** recomendação não vinculante.
- **Pendência:** decisão ou implementação ainda necessária.
- **Conflito:** fontes vigentes divergem e não devem ser reconciliadas sem decisão explícita.

O FastAPI atual é referência de comportamento já implementado e testado. Ele não transforma automaticamente seus endpoints, respostas ou códigos HTTP em contrato definitivo das Edge Functions. Novas regras críticas desta feature não devem ser implementadas apenas no FastAPI.

Uma Edge Function só pode ser considerada entregue quando existir código correspondente versionado em `supabase/functions/` no baseline em avaliação. Menções históricas a Functions não localizadas devem permanecer como histórico, nunca como evidência de entrega atual.

## Baseline técnico comprovado

| Item | Estado em 2026-08-10 | Evidência no baseline |
|---|---|---|
| Branch | Correta | `feature/supabase-edge-functions-mvp` |
| `supabase/functions/` | Não existe | Árvore de arquivos do `HEAD` |
| Edge Functions versionadas | Não existem | Nenhum arquivo de Function no `HEAD` ou no histórico consultado de `supabase/functions/` |
| `process_deposit` | Não localizado | Busca no baseline e no histórico Git consultado não encontrou implementação ou documentação com esse nome |
| Runtime local de Edge Functions | Habilitado | `[edge_runtime] enabled = true` em `supabase/config.toml` |
| Migrations Supabase | Quatro arquivos; um deles vazio | `20260527120000_initial_schema.sql`, `20260527121000_add_indexes.sql`, `20260527122000_backend_v1_support.sql` e `20260527123000_prepare_supabase_auth.sql` |
| `20260802120000_mobile_profile_rls.sql` | Ausente do baseline | Não está em `supabase/migrations/` no `HEAD` |
| RLS/policies versionadas | Não comprovadas | As migrations atuais não habilitam RLS nem criam policies |
| `deposits.event_id` único | Comprovado no schema | `event_id uuid not null unique` na migration inicial; modelo SQLAlchemy também usa `unique=True` |
| `machines.api_key_hash` | Comprovado no schema de suporte | Adicionado por `20260527122000_backend_v1_support.sql` e presente no modelo SQLAlchemy |
| Supabase Auth no Mobile | Cliente implementado no baseline | Uso de `supabase_flutter`, login por e-mail/senha e perfil remoto em `mobile/bingo_app` |
| Vínculo Auth/domínio | Preparado, não operacionalmente comprovado | `students.auth_user_id` é nullable e unique; não há FK para `auth.users` |
| FastAPI | Implementado e usado como referência | `backend/`; `21 passed` em `python -m pytest` em 2026-08-10 |
| Projeto Supabase remoto | Não comprovado | Não há evidência suficiente no repositório para afirmar configuração, migrations aplicadas ou policies remotas |
| Supabase CLI nesta estação | Não disponível no `PATH` | A execução de `supabase --version` falhou; `supabase/.temp/cli-latest` registra `v2.111.0`, mas os comandos de Functions não foram executados nesta revisão |

**Decisão histórica:** o commit `56f950a` da branch `feature/mobile-pin-refresh` contém uma versão de `20260802120000_mobile_profile_rls.sql` e um teste SQL de RLS. Esses arquivos não pertencem ao `HEAD` desta branch e não provam entrega ou aplicação remota.

## Arquitetura híbrida oficial

### A. Direct Supabase + RLS

Usar para operações simples de leitura que possam ser limitadas corretamente por identidade, vínculo e escola. Cada leitura direta depende de policy RLS específica, grants mínimos e teste de isolamento. A ausência de RLS comprovado bloqueia a liberação dessa leitura.

Não deve existir uma Edge Function para toda leitura simples. Criar uma Function sem regra privilegiada ou necessidade de segredo adicionaria complexidade sem melhorar o limite de segurança.

### B. Supabase Edge Functions

Usar para operações que envolvam privilégio, segredo, credencial técnica, alteração de saldo, alteração de estoque, antifraude, idempotência, auditoria, transação, integração externa, IA remota, administração privilegiada ou health de dependências.

Uma Function é a fronteira de entrada e autorização; ela não elimina a necessidade de uma operação atômica server-side no banco. O mecanismo definitivo de atomicidade — PostgreSQL function, RPC, transação SQL ou outro mecanismo server-side — ainda é uma **pendência**.

### C. Totem / Orange Pi local

Usar para hardware, câmera, visão local, Arduino, Serial, sensores, ciclo físico, confirmação física, modo demonstração e estado local de segurança. Credenciais técnicas devem ficar em serviço local protegido no Orange Pi, não no JavaScript público da interface.

Resumo oficial:

```text
consulta simples
→ Supabase + RLS

regra crítica / privilégio / transação / segredo
→ Edge Function

hardware / sensores / câmera / Arduino / ciclo físico
→ Orange Pi / Totem local
```

## Matriz de responsabilidades

As classificações abaixo não criam nomes de Functions nem endpoints.

| Operação conhecida | Classificação | Base e condição |
|---|---|---|
| Autenticação do App | Direct Supabase + RLS | Supabase Auth é a decisão oficial; RLS protege os dados lidos após autenticação. |
| Leitura do próprio perfil | Direct Supabase + RLS | Permitida arquiteturalmente somente após policy e teste de isolamento. |
| Leitura do próprio saldo | Direct Supabase + RLS | O saldo é campo de leitura; alteração continua privilegiada. |
| Histórico próprio de descartes | Direct Supabase + RLS | Requer policy por aluno e escola e teste contra vazamento entre usuários. |
| Histórico próprio de resgates | Direct Supabase + RLS | Requer policy por aluno e escola e teste de isolamento. |
| Catálogo de recompensas | Direct Supabase + RLS | Leitura simples por escola/visibilidade; policy ainda não existe no baseline. |
| Ranking | A definir | A leitura cruza alunos ou turmas; escopo, privacidade e policy ainda não estão fechados. |
| PIN do aluno no Totem | Edge Function | Credencial operacional do domínio, com validação server-side e sem exposição de `pin_hash`. |
| Autenticação técnica da máquina | Edge Function | Usa identificador e segredo técnico; referência FastAPI: `X-Machine-Id` e `X-Api-Key`. |
| Registro de descarte | Edge Function | Escrita crítica com idempotência, validações, saldos e auditoria. |
| Cálculo de pontos | Edge Function | Fonte final server-side; o cliente não calcula o valor definitivo. |
| Antifraude | Edge Function | Regra server-side; a referência atual limita pontos do aluno para itens pequenos por dia. |
| Alteração de saldo do aluno e da turma | Edge Function | Escrita privilegiada e parte da operação atômica de descarte. |
| Auditoria | Edge Function | Deve acompanhar a operação crítica na mesma unidade de consistência quando aplicável. |
| Captura de imagem | Local Totem | Responsabilidade da câmera e do serviço local. Armazenamento de imagens está fora do V1 documentado. |
| Visão computacional principal/local | Local Totem | O fluxo físico documenta captura e classificação ligadas ao Totem; o contrato de integração ainda precisa ser fechado. |
| Segunda análise por IA externa, quando aplicável | Edge Function | Integração externa com segredo; o fluxo histórico cita Gemini para resultados incertos. |
| Arduino e Serial | Local Totem | Controle de hardware e ciclo mecânico. |
| Sensores | Local Totem | Estado físico e segurança do equipamento. |
| Confirmação de queda e fechamento do ciclo | Local Totem | Deve produzir evidência física antes da persistência/pontuação; contrato preciso está pendente. |
| Criação de resgate | Edge Function | Escrita crítica; o V1 documentado usa canal Totem e o Mobile é consulta. |
| Débito de saldo no resgate | Edge Function | Parte da operação atômica de resgate. |
| Atualização de estoque | Edge Function | Parte da operação atômica de resgate quando `stock_qty` é controlado. |
| Entrega de recompensa | Edge Function | Operação administrativa privilegiada e auditada. |
| Heartbeat da máquina | Edge Function | Usa credencial técnica e altera status/telemetria com auditoria na referência FastAPI. |
| Health de dependências | Edge Function | Deve orientar se o Totem pode iniciar operação real, sem executar negócio. |
| Modo demonstração | Local Totem | Estado separado, com dados simulados e sem writes reais. |
| Comportamento offline e recuperação local | Local Totem | Estado de segurança e eventual fila dependem de decisão pendente descrita abaixo. |
| Missões, marketplace e relatórios avançados | Fora do MVP | Marcados fora do V1 ou sem entidade/contrato backend atual. |

## Autenticação e autorização

### App Mobile

**Decisão oficial:** usar Supabase Auth para e-mail/senha, sessão, refresh token e JWT do App. `students` permanece como entidade de domínio e `students.auth_user_id` prepara o vínculo com `auth.users`.

O App usa somente chave pública apropriada ao cliente. Chave privilegiada, `service_role` ou equivalente nunca deve ser exposta no Mobile.

### Aluno no Totem

**Decisão oficial:** o PIN é uma credencial operacional associada ao aluno, escola e turma no domínio. PIN não é a senha do App. A referência FastAPI guarda apenas `students.pin_hash`, valida contexto e não retorna o hash ao Totem.

O PIN identifica/autoriza o aluno dentro do fluxo presencial; ele não substitui a autenticação técnica da máquina.

### Máquina

**Estado comprovado no FastAPI:** a autenticação técnica usa:

```http
X-Machine-Id
X-Api-Key
```

O identificador localiza `machines`; a chave apresentada é verificada contra `machines.api_key_hash`. A credencial da máquina representa o equipamento, não o aluno.

**Requisitos de segurança:**

- secrets não são versionados;
- a chave em claro não é persistida no banco;
- chave privilegiada, `service_role` ou equivalente não vai para o Mobile;
- chave privilegiada nem credencial real da máquina vai para frontend JavaScript público do Totem;
- a UI do Totem conversa com serviço local protegido quando precisar usar a credencial técnica;
- logs, respostas e health não expõem credenciais, hashes ou tokens.

## RLS e acesso direto

**Estado comprovado:** não há migration RLS no baseline. A afirmação anterior de que `20260802120000_mobile_profile_rls.sql` estava presente foi corrigida em `docs/supabase-preparation.md`.

Nenhuma leitura direta deve ser liberada antes de existir, para o conjunto exato de tabelas/colunas:

1. RLS habilitado;
2. grants mínimos;
3. policy correspondente;
4. teste de isolamento positivo e negativo;
5. evidência de que a migration foi aplicada no ambiente alvo.

Uma policy de perfil não autoriza implicitamente histórico, catálogo ou ranking. Cada recorte precisa de análise própria. Ranking permanece **a definir** por cruzar dados de múltiplos alunos/turmas.

## Contrato atual de descarte

Este é o contrato comprovado entre Totem e FastAPI e deve ser preservado como referência de migração, sem definir antecipadamente o endpoint ou nome da futura Function.

```json
{
  "event_id": "uuid",
  "class_id": "uuid",
  "student_id": "uuid-ou-null",
  "is_valid": true,
  "detected_type": "mouse",
  "size": "SMALL"
}
```

Headers técnicos atuais:

```http
X-Machine-Id
X-Api-Key
```

O schema FastAPI ainda aceita `school_id` e `machine_id` opcionais no corpo por compatibilidade, porém a rota sobrescreve ambos com `machine.school_id` e `machine.id` obtidos da máquina autenticada. Logo, esses valores enviados pelo cliente não são fonte confiável e não devem ser aceitos cegamente na implementação futura.

`student_id` pode ser nulo; nesse caso, a implementação atual pode pontuar apenas a turma. `detected_type` também é nullable no schema atual. Os valores de `size` comprovados são `SMALL`, `MEDIUM` e `LARGE`.

### Invariantes obrigatórios do descarte

- `event_id` identifica um evento lógico único;
- repetir o mesmo `event_id` não cria outro descarte;
- repetir o mesmo `event_id` não pontua novamente;
- duas chamadas concorrentes com o mesmo `event_id` não podem gerar dupla pontuação;
- retry após timeout deve ser seguro e produzir resultado coerente;
- a máquina precisa ser autenticada;
- a turma deve pertencer à escola derivada da máquina;
- o aluno, quando informado, deve pertencer à mesma escola e turma;
- pontuação é calculada server-side;
- antifraude é server-side;
- item inválido não gera pontos na referência atual;
- operação crítica mantém consistência entre evento, saldos e auditoria;
- auditoria acompanha a operação quando aplicável;
- falha parcial não deixa saldo e evento divergentes.

`UNIQUE(event_id)` é barreira de integridade necessária, mas não substitui tratamento idempotente e de concorrência na camada de aplicação/transação.

**Estado comprovado no FastAPI:** há busca prévia por `event_id`, retorno do registro existente, constraint única, teste de duplicação sequencial, cálculo de pontos por tamanho, regra diária para pontos do aluno em itens pequenos, atualização de saldo do aluno e da turma e auditoria na mesma chamada a `commit`.

**Pendência:** a implementação FastAPI não contém teste de duplicação concorrente, retry após timeout ou falha injetada no meio da transação. A corrida entre a busca prévia e o insert não é convertida explicitamente em resposta idempotente. Essas garantias precisam ser desenhadas e testadas na implementação Supabase.

## Atomicidade

### Descarte

Logicamente pertencem à mesma operação:

- criação ou recuperação idempotente de `deposits`;
- atualização do saldo do aluno, quando aplicável;
- atualização do saldo da turma;
- criação da auditoria aplicável.

Nenhum consumidor pode observar saldo pontuado sem evento correspondente, evento válido sem os saldos esperados ou repetição que gere novo crédito.

### Resgate

Logicamente pertencem à mesma operação de criação:

- criação de `redemptions`;
- débito do saldo do aluno;
- atualização de estoque, quando controlado;
- criação da auditoria.

A entrega também precisa atualizar estado, admin responsável, data e auditoria de forma consistente.

**Estado comprovado no FastAPI:** criação de resgate, débito, estoque e auditoria são gravados em um único `commit`, com `rollback` em exceção. A entrega e sua auditoria também compartilham um `commit` próprio.

**Pendência de arquitetura:** ainda não há decisão oficial entre PostgreSQL function, RPC, transação SQL ou outro mecanismo server-side para garantir atomicidade sob Edge Functions. Não escolher arbitrariamente. Também faltam testes de concorrência para saldo, estoque, limites e entrega.

## Regras de resgate de referência

O FastAPI comprova as seguintes validações e efeitos para criação/entrega:

- aluno e recompensa pertencem à escola do principal autenticado;
- recompensa precisa existir, estar ativa e com status disponível;
- estoque, quando controlado, precisa ser maior que zero;
- saldo precisa ser suficiente;
- há limite diário configurável;
- há limite configurável de resgates pendentes;
- código é gerado server-side e possui unicidade no schema;
- expiração usa configuração da escola;
- saldo é debitado na criação;
- estoque é decrementado na criação quando controlado;
- criação é auditada;
- apenas admin autorizado da mesma escola entrega;
- apenas resgate pendente e não expirado pode ser entregue;
- entrega é auditada;
- tentativa sequencial de segunda entrega é rejeitada.

Writes críticos de resgate não devem ser feitos diretamente pelo frontend. O contrato de produto vigente no modelo de dados diz que resgate V1 ocorre no Totem e que o Mobile é consulta; `docs/data-contracts-totem-app-backend.md` também registra que o canal do App precisa ser confirmado antes de liberar UI de criação.

## Operação offline e recuperação

**Conflito:** `docs/operacao-offline.md` e o fluxo oficial de descarte bloqueiam novos descartes reais quando serviços críticos estão indisponíveis. Já `backend/README.md` usa a expressão “offline-first”, e `apps/totem_simulator/README.md` interpreta offline como evento pendente com sincronização posterior e afirma que o Totem não pode parar. O fluxo oficial ainda admite recuperação de um evento cujo descarte físico terminou após uma queda de comunicação, mas distingue isso de iniciar uma operação offline.

Até decisão oficial, o comportamento seguro é:

- não prometer pontuação offline;
- não alterar saldo local como fonte final;
- não iniciar descarte real quando dependências obrigatórias já estão indisponíveis, conforme a documentação operacional vigente;
- manter modo demonstração separado, identificado e sem writes reais;
- manter `event_id` como requisito para qualquer futura sincronização/recuperação;
- determinar quais eventos, se algum, podem ser enfileirados;
- determinar em qual estado físico o descarte se torna elegível para sincronização;
- não chamar mecanismo de recuperação pós-queda de “pontuação offline” sem decisão de produto.

## Confirmação física e fechamento do ciclo

O Totem/Orange Pi controla porta, escotilha, câmera, Arduino, Serial e sensores. A nuvem não deve pontuar apenas porque recebeu intenção de descarte.

**Estado documental:** `docs/descarte/FLUXO_ECOSSISTEMA_DESCARTE_V1.md` diz que, após aceitação, a escotilha abre para a queda. Se não houver sensor, o ciclo é considerado fisicamente concluído quando o hardware confirma abertura, tempo de queda, fechamento e retorno ao estado inicial. O evento é enviado ao backend após essa conclusão.

**Bloqueio de contrato:** ainda não há contrato preciso e versionado que determine:

- qual sensor ou evento confirma a queda quando houver sensor;
- qual confirmação do Arduino representa cada etapa;
- qual sinal único comprova fechamento seguro do ciclo;
- em que instante a nuvem pode persistir e pontuar;
- qual estado local fica gravado se a conexão falhar entre inserção física e persistência;
- como um operador reconcilia estado físico indefinido sem dupla pontuação.

Não criar campo, endpoint ou nome de Function para resolver esse bloqueio nesta etapa.

## Health

**Referência histórica:** o FastAPI expõe `/health` com `{"status":"ok"}`, sem verificar banco ou outra dependência.

O health da arquitetura Supabase deve permitir que o Totem determine se pode iniciar operação real. Deve verificar apenas dependências relevantes para o fluxo que será iniciado e distinguir indisponibilidade sem revelar detalhes sensíveis.

O health não deve:

- expor secrets, tokens, hashes ou credenciais;
- executar descarte, pontuação, resgate, heartbeat ou qualquer operação real de negócio;
- depender de serviços que não sejam necessários para a decisão operacional consultada;
- usar o nome do endpoint FastAPI como nome final automático da Function.

**Pendência:** definir o conjunto mínimo de dependências, timeout, semântica de degradação e contrato de resposta antes da implementação.

## Categorias conceituais de erro

O contrato futuro precisa distinguir, sem fixar agora códigos HTTP finais:

| Categoria | Exemplos conceituais |
|---|---|
| Autenticação | token, PIN ou credencial técnica ausente/inválida |
| Autorização | identidade válida sem acesso à escola, aluno ou operação |
| Validação | payload malformado, campo obrigatório ausente ou valor fora do domínio conhecido |
| Recurso inválido | máquina, turma, aluno, recompensa ou resgate não localizado no contexto autorizado |
| Regra de negócio | saldo, estoque, limites, estado ou expiração impedem a operação |
| Idempotência/conflito | repetição, concorrência ou estado já processado |
| Dependência externa | banco, IA ou integração necessária indisponível |
| Erro interno | falha inesperada sem detalhe sensível para o cliente |

O FastAPI usa atualmente `detail` e classes que mapeiam para respostas HTTP. Isso é referência de comportamento, não contrato automático das Edge Functions.

## Estratégia mínima de testes futuros

“Atual” significa coberto pelos testes FastAPI executados no baseline; não significa coberto por Edge Functions.

| Área | Cenário | FastAPI atual | Edge Functions futura |
|---|---|---|---|
| Máquina | credenciais válidas | Coberto para contexto do Totem | Obrigatório |
| Máquina | headers ausentes | Coberto | Obrigatório |
| Máquina | máquina inexistente | Não identificado teste específico | Obrigatório |
| Máquina | chave inválida | Coberto | Obrigatório |
| Descarte | happy path | Coberto | Obrigatório |
| Descarte | payload inválido | Validação existe; teste específico não identificado | Obrigatório |
| Descarte | aluno válido | Coberto | Obrigatório |
| Descarte | aluno incorreto | Não identificado | Obrigatório |
| Descarte | turma incorreta | Não identificado | Obrigatório |
| Descarte | escola incorreta/tentativa de forjar contexto | Corpo é sobrescrito; cenário adversarial não identificado | Obrigatório |
| Descarte | item inválido | Coberto para pontos zero | Obrigatório |
| Descarte | antifraude | Coberto para limite de item pequeno | Obrigatório |
| Descarte | `event_id` duplicado sequencial | Coberto | Obrigatório |
| Descarte | `event_id` duplicado concorrente | Não coberto | Obrigatório |
| Descarte | retry após timeout | Não coberto | Obrigatório |
| Descarte | falha no meio da transação | Não coberto por falha injetada | Obrigatório |
| Descarte | saldo não duplicado | Coberto no retry sequencial | Obrigatório, inclusive concorrente |
| Descarte | auditoria correta | Auditoria existe; asserção específica do evento não identificada | Obrigatório |
| Auth/RLS | usuário lê próprio dado | Sem teste RLS no baseline | Obrigatório |
| Auth/RLS | usuário não lê outro aluno | Sem teste RLS no baseline | Obrigatório |
| Auth/RLS | anônimo não acessa dado privado | Sem teste RLS no baseline | Obrigatório |
| Auth/RLS | autenticado sem vínculo não acessa dado indevido | Sem teste RLS no baseline | Obrigatório |
| Resgate | saldo suficiente | Coberto | Obrigatório quando entrar no escopo |
| Resgate | saldo insuficiente | Coberto | Obrigatório quando entrar no escopo |
| Resgate | estoque disponível | Exercitado indiretamente | Obrigatório quando entrar no escopo |
| Resgate | estoque esgotado | Não identificado | Obrigatório quando entrar no escopo |
| Resgate | limite diário | Regra existe; teste específico não identificado | Obrigatório quando entrar no escopo |
| Resgate | limite de pendentes | Coberto | Obrigatório quando entrar no escopo |
| Resgate | expiração | Coberto na entrega | Obrigatório quando entrar no escopo |
| Resgate | admin correto | Coberto | Obrigatório quando entrar no escopo |
| Resgate | admin de outra escola | Regra existe; teste específico não identificado | Obrigatório quando entrar no escopo |
| Resgate | tentativa duplicada de entrega | Coberto sequencialmente | Obrigatório quando entrar no escopo |
| Health | saudável | Endpoint existe; teste específico não identificado | Obrigatório |
| Health | dependência indisponível | Health atual não verifica dependências | Obrigatório |
| Health | resposta sem informação sensível | Resposta atual é mínima; teste específico não identificado | Obrigatório |

Além dos casos acima, os testes Supabase devem rodar contra Postgres/Supabase compatível com produção. Os testes FastAPI atuais usam SQLite e não provam semântica concorrente do PostgreSQL, RLS ou execução Deno.

## Roadmap documental para implementação

1. resolver RLS;
2. resolver contrato físico/queda;
3. fechar matriz Direct Supabase × Edge Function × Local Totem;
4. criar scaffold de Functions;
5. criar `_shared` mínimo apenas quando necessário;
6. portar autenticação técnica de máquina;
7. implementar primeiro fluxo crítico de descarte;
8. testar idempotência, concorrência e retries;
9. implementar resgates/operações sensíveis necessárias;
10. implementar health;
11. integrar clientes;
12. completar documentação e evidências.

## Critério de pronto da feature

A feature só estará pronta quando houver:

- estrutura `supabase/functions/` versionada;
- contratos de entrada, saída e erros aprovados;
- autenticação de usuário quando aplicável;
- credencial técnica de máquina protegida;
- secrets protegidos e não versionados;
- RLS e testes de isolamento para todos os acessos diretos;
- descarte idempotente, inclusive sob concorrência e retries;
- atomicidade nas operações críticas;
- antifraude server-side;
- health sem efeito de negócio nem exposição sensível;
- testes automatizados das Functions e integrações relevantes;
- exemplos de chamada sem credenciais reais;
- instruções locais reproduzíveis;
- documentação da arquitetura atualizada;
- commits rastreáveis contendo código e evidências.

No baseline de 2026-08-10, esses critérios ainda não foram atendidos porque não há `supabase/functions/`, RLS comprovado nem testes de Edge Functions.

## Decisões, conflitos e pendências consolidados

### Decisões oficiais

- arquitetura híbrida em três zonas: Direct Supabase + RLS, Edge Functions e Totem local;
- Supabase Auth para o App, PIN separado para o aluno no Totem e credencial técnica separada para a máquina;
- leituras simples não exigem Function quando RLS e isolamento forem suficientes;
- writes críticos, segredos, privilégios, saldos, estoque, antifraude, auditoria e transações passam por Edge Functions;
- hardware e confirmação física permanecem locais;
- FastAPI é referência de regras existentes, não destino para novas regras críticas desta feature;
- uma Function só está entregue quando seu código está versionado no baseline.

### Conflitos

- documentação afirmava RLS entregue, mas a migration e o teste correspondentes não estão no baseline atual;
- “offline-first/fila pendente” diverge do modo seguro que bloqueia descarte real offline; recuperação após queda durante ciclo iniciado online não resolve toda a divergência;
- o fluxo oficial de descarte diz que todos os itens válidos têm pontuação fixa, enquanto contrato, schema e FastAPI calculam pontos por `size`;
- o modelo de dados limita resgate V1 ao Totem/Mobile consulta, enquanto o contrato de dados registra uma rota tecnicamente acessível pelo fluxo de aluno e pede validação antes de liberar App;
- o cliente Mobile autenticado está presente, mas o RLS e a fixture/teste citados por sua documentação não estão no baseline.

### Pendências

- recuperar ou recriar RLS e testes sem criar migration nesta tarefa;
- decidir o mecanismo de atomicidade no PostgreSQL;
- fechar garantias concorrentes de idempotência, saldo, estoque e limites;
- definir contrato de confirmação física e recuperação;
- resolver a regra oficial de pontos fixos versus pontos por tamanho;
- definir escopo seguro de ranking;
- definir canal de criação de resgate no MVP;
- definir dependências e semântica do health;
- definir contratos finais de Functions e erros sem herdar endpoints FastAPI automaticamente.

### Hipóteses e sugestões

- **Hipótese:** a migration RLS histórica pode servir como insumo de revisão, mas não deve ser copiada sem validar schema, grants, políticas e testes atuais.
- **Sugestão:** implementar primeiro o menor fluxo crítico de descarte após fechar RLS e confirmação física.
- **Sugestão:** manter `_shared` pequeno e introduzi-lo somente quando autenticação, erro ou acesso a banco realmente forem compartilhados.
- **Sugestão:** testar concorrência contra Postgres/Supabase realista, não apenas com doubles ou SQLite.
