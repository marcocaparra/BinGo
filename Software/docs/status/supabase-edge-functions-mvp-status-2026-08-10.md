# Status técnico — Supabase Edge Functions MVP

Data: `2026-08-10`  
Branch de trabalho: `feature/supabase-edge-functions-mvp`  
Escopo desta etapa: documentação preparatória; nenhuma Edge Function, migration, alteração de schema ou deploy.

Documento arquitetural principal: [`../supabase-edge-functions-mvp.md`](../supabase-edge-functions-mvp.md)

## Legenda de status

- **Decisão oficial:** direção aprovada e vigente.
- **Estado comprovado:** fato verificado no `HEAD` desta branch.
- **Decisão histórica:** registro de outra etapa ou linha de desenvolvimento; não comprova entrega atual.
- **Hipótese/Sugestão:** possibilidade ainda não aprovada.
- **Pendência:** trabalho ou decisão ainda necessário.
- **Conflito:** fontes divergem e exigem decisão explícita.
- **Bloqueio:** ausência de contrato impede implementação segura.

## Baseline técnico atual

- **Estado comprovado:** a branch conferida antes das edições é `feature/supabase-edge-functions-mvp`.
- **Estado comprovado:** não existe `STATUS.md` na raiz deste baseline. O status técnico anterior consultado foi `docs/status/backend-v1-status-2026-06-09.md`; o `STATUS.md` encontrado no commit histórico `56f950a` não pertence ao `HEAD` atual.
- **Estado comprovado:** `supabase/config.toml` habilita Auth, migrations, seed e o runtime local de Edge Functions.
- **Estado comprovado:** `supabase/functions/` não existe.
- **Estado comprovado:** não há Edge Functions versionadas.
- **Estado comprovado:** nenhuma implementação ou documentação chamada `process_deposit` foi localizada no baseline ou no histórico Git consultado.
- **Estado comprovado:** as migrations atuais são `20260527120000_initial_schema.sql`, `20260527121000_add_indexes.sql` (vazia), `20260527122000_backend_v1_support.sql` e `20260527123000_prepare_supabase_auth.sql`.
- **Estado comprovado:** `20260802120000_mobile_profile_rls.sql` não está no baseline atual e nenhuma migration vigente cria policies RLS.
- **Estado comprovado:** não há evidência no repositório suficiente para afirmar que um projeto Supabase remoto esteja configurado ou migrado.
- **Estado comprovado:** `supabase/.temp/cli-latest` registra `v2.111.0`, mas o executável `supabase` não estava disponível no `PATH` desta estação; os comandos de Functions documentados não foram executados nesta revisão.
- **Estado comprovado:** o FastAPI atual passou em `21` testes (`python -m pytest`) em 2026-08-10, com avisos de chave JWT curta restritos ao ambiente de teste.

## O que já existe

### Banco e autenticação

- `deposits.event_id` possui unicidade no schema Supabase e no modelo SQLAlchemy.
- `machines.api_key_hash` existe na migration de suporte e no modelo SQLAlchemy.
- `students.auth_user_id` existe, é nullable e unique, sem FK comprovada para `auth.users`.
- o Mobile contém integração com Supabase Auth por e-mail/senha e leitura de perfil, mas o RLS de suporte não está no baseline.
- o PIN do Totem permanece separado da senha do App e é armazenado como `students.pin_hash`.

### FastAPI como referência de negócio

- autenticação técnica por `X-Machine-Id` e `X-Api-Key`, com chave comparada a `machines.api_key_hash`;
- autenticação do aluno no Totem por PIN e contexto de escola/turma;
- contrato de descarte com `event_id`, `class_id`, `student_id`, `is_valid`, `detected_type` e `size`;
- `school_id` e `machine_id` do descarte derivados da máquina autenticada, mesmo quando o schema aceita esses campos opcionais no corpo;
- idempotência sequencial por consulta prévia de `event_id` e unicidade no banco;
- cálculo de pontos server-side por tamanho e configurações da escola;
- antifraude inicial: limite diário de pontos individuais para itens pequenos, mantendo pontos da turma na implementação atual;
- atualização de saldo do aluno e da turma;
- auditoria de descarte, PIN, heartbeat, criação e entrega de resgate;
- criação de resgate com validação de escola, recompensa, disponibilidade, estoque, saldo, limite diário e limite de pendentes;
- código, expiração, débito, decremento de estoque e auditoria na criação;
- entrega por admin da mesma escola, somente para resgate pendente e não expirado;
- `/health` estático com `{"status":"ok"}`.

## O que ainda não existe ou não está comprovado

- scaffold ou código de Edge Functions;
- nomes e contratos finais de Functions;
- `_shared` para Functions;
- RLS versionado no baseline;
- testes de isolamento RLS disponíveis no baseline;
- autenticação de máquina portada para Edge Functions;
- descarte, resgate, heartbeat ou health implementados em Edge Functions;
- mecanismo server-side escolhido para atomicidade sob Functions;
- tratamento comprovado de duplicação concorrente e retry após timeout;
- testes de falha parcial/transação e concorrência no PostgreSQL;
- health Supabase com verificação seletiva de dependências;
- contrato preciso de confirmação física/queda;
- política oficial completa de recuperação após falha de conexão;
- exemplos de chamada de Functions;
- evidência de configuração ou deploy remoto.

## Decisões vigentes

- **Decisão oficial:** arquitetura híbrida: leitura simples por Direct Supabase + RLS; regra crítica, privilégio, transação ou segredo por Edge Function; hardware e ciclo físico no Orange Pi/Totem local.
- **Decisão oficial:** não criar Function para toda leitura simples.
- **Decisão oficial:** nenhuma leitura direta é liberada sem policy RLS correspondente e teste de isolamento.
- **Decisão oficial:** Supabase Auth, PIN do Totem e credencial da máquina são mecanismos distintos.
- **Decisão oficial:** chave privilegiada não vai para Mobile nem frontend JavaScript público do Totem; secrets não são versionados.
- **Decisão oficial:** o FastAPI existente é referência das regras de negócio já implementadas.
- **Decisão oficial:** novas regras críticas desta feature não devem ser implementadas apenas no FastAPI.
- **Decisão oficial:** Edge Functions só são entregues quando o código está versionado em `supabase/functions/` no baseline atual.
- **Decisão oficial:** registros históricos de Functions ou migrations não localizadas permanecem como histórico, não como evidência de entrega.
- **Decisão oficial:** writes críticos de descarte e resgate não são responsabilidade direta dos frontends.

## Decisões históricas preservadas

- O commit `56f950a`, na branch `feature/mobile-pin-refresh`, registrou Supabase PostgreSQL/Auth/Edge Functions como backend alvo do Mobile e adicionou `20260802120000_mobile_profile_rls.sql` e `supabase/tests/mobile_profile_rls.sql`.
- Esses arquivos e o `STATUS.md` daquela etapa não estão no `HEAD` atual. O conteúdo histórico pode servir de insumo para recuperação/revisão, mas não é entrega vigente.
- O FastAPI foi documentado em 2026-06-09 como backend V1 pronto; nesta feature ele permanece no repositório e serve de referência, sem ser alterado.

## Conflitos encontrados

1. **RLS documentado versus baseline:** `docs/supabase-preparation.md` e `docs/mobile-supabase-auth-profile.md` afirmavam que a migration de perfil era aplicada pelo reset local. A migration e o teste SQL estão ausentes desta branch. Os documentos foram corrigidos para distinguir histórico de estado comprovado.
2. **Offline-first versus modo seguro:** `backend/README.md` e `apps/totem_simulator/README.md` mencionam offline-first/fila pendente; `docs/operacao-offline.md` bloqueia descarte real sem serviços críticos. O fluxo oficial permite apenas recuperação de ciclo iniciado online e fisicamente concluído. A política completa segue pendente.
3. **Pontos fixos versus pontos por tamanho:** `docs/descarte/FLUXO_ECOSSISTEMA_DESCARTE_V1.md` diz que todos os descartes válidos têm o mesmo valor; `docs/data-contracts-totem-app-backend.md`, `school_settings`, FastAPI e testes usam `SMALL`, `MEDIUM`, `LARGE` com valores distintos.
4. **Canal de resgate:** `docs/database-model.md` define resgate V1 no Totem e Mobile apenas para consulta; o contrato de dados registra criação tecnicamente disponível ao principal aluno e exige validação de produto antes de liberar no App.
5. **Mobile sem camada RLS correspondente no baseline:** o cliente autenticado e o repositório de perfil estão presentes, mas os artefatos de RLS e seus testes não estão.

## Bloqueios

- **RLS:** recuperar ou recriar migrations/policies e testes em tarefa própria antes de leitura direta.
- **Confirmação física:** definir sinal de queda/ciclo concluído, instante elegível para persistência e recuperação quando a conexão falhar após inserção física.
- **Atomicidade:** decidir o mecanismo PostgreSQL/RPC/transação server-side sem assumir uma solução não aprovada.
- **Concorrência:** especificar e testar comportamento de `event_id`, saldos, estoque, limites e entrega sob chamadas simultâneas.
- **Produto:** resolver pontos fixos versus pontos por tamanho, ranking e canal de criação de resgate.
- **Health:** definir dependências relevantes e semântica de degradação.

## Hipóteses e sugestões

- **Hipótese:** a migration RLS histórica pode ser recuperada como ponto de partida após revisão contra o schema atual; ela não deve ser reaplicada cegamente.
- **Sugestão:** testar idempotência e transações contra Postgres/Supabase, porque os testes FastAPI atuais usam SQLite.
- **Sugestão:** criar `_shared` somente após surgir duplicação real entre Functions.
- **Sugestão:** portar primeiro a autenticação técnica e o descarte após resolver os bloqueios de RLS e ciclo físico.

## Próximas etapas

1. resolver RLS e testes de isolamento;
2. resolver contrato físico/queda e recuperação;
3. fechar a matriz de responsabilidades e conflitos de produto;
4. criar scaffold versionado de Functions;
5. portar autenticação técnica da máquina;
6. implementar descarte com atomicidade e idempotência concorrente;
7. testar retries, falhas parciais e concorrência;
8. portar resgates e demais operações sensíveis necessárias;
9. implementar health de dependências relevantes;
10. integrar clientes, documentar contratos/exemplos e registrar evidências rastreáveis.

## Critério de saída desta etapa documental

- referência arquitetural principal criada;
- baseline e ausências registrados sem tratar histórico como entrega;
- responsabilidades classificadas;
- autenticação, RLS, descarte, atomicidade, resgate, offline, confirmação física, health, erros, testes, roadmap e critérios de pronto documentados;
- nenhum código, migration, schema ou cliente alterado.
