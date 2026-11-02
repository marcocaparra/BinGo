# Pontuação no TotemEdge principal — 02/11/2026

**Decisão posterior:** a restrição de crédito na mecânica simulada foi revista
para homologação DEV controlada. Ver [contrato vigente](totemedge-economic-dev.md).
O restante deste arquivo registra a entrega anterior e suas evidências históricas.

O caminho econômico central e a apresentação do recibo estão preparados e
testados localmente. A habilitação do ciclo físico real permanece pendente.
O Windows continua simulando mecânica, com `physical_confirmed=0`, `receipt=null`
e nenhuma concessão econômica. Não foi alterado o fluxo de PIN/autenticação.

## Inventário e estado verificado

- `register_deposit_v1` já era a autoridade atômica de cálculo, escola derivada
  da máquina, saldos, snapshots, auditoria, replay e concorrência. Não foi refeita.
- Migrations 005/006 materializam pontuação/recibo; 007 sustenta machine-auth;
  011 redenomina a unidade para 800 BinCoins/1900 XP por padrão. A RPC lê as
  configurações e taxas do banco. Seeds com bônus não definem política produtiva.
- A Function Deno/TypeScript `supabase/functions/register-deposit-v1` já existia,
  usando a fundação compartilhada de autenticação. Rejeita campos extras,
  recebe sete campos oficiais e retorna 201/200 ou conflito 409. Não foi refeita.
- TotemEdge já tinha `SupabaseEdgeClient`, payload persistido, retry, trava de
  escopo destino/máquina, recuperação de REGISTERING e projeção do recibo.
  A UI operacional já exigia recibo, mas desenhava outra composição de sucesso.
- Preflight de 02/11, **somente leitura**, confirmou o projeto vinculado
  `bingo-dev` (`ddxmohrjcxuibswmrtla`), `register-deposit-v1` ACTIVE v4 e
  `health-v1` ACTIVE v3. As 29 migrations até `20261001140000` estão alinhadas
  com o remoto, incluindo pontuação/redenominação. As locais `20261001150000`
  (Admin Machines) e `20261001160000` (Admin Deposits) não estão no remoto.
  Não são novas dependências desta integração. Não houve smoke econômico
  hospedado nesta rodada; presença/histórico não comprovam todo o funcionamento
  remoto e não declaram qualquer estado de produção.
- Supabase local existente: PostgreSQL com migrations até `20261001160000`.
  O worker Edge do CLI estava parado. O runner de teste executou o **handler
  oficial** em Deno no host, em loopback, contra esse banco/Data API locais.

## Mudanças desta rodada

`CycleStore.queue_registration` e `SessionService.register_completed` completam
a passagem interna de `HATCH_IN_PROGRESS` para a fila econômica. Só aceitam
payload válido já congelado e confirmação física **já persistida**, sessão não
simulada e escopo original. Resultados mecânicos indeterminados, conclusões
simuladas, ausência de evidência ou troca de destino continuam bloqueados.
Não há nova rota que aceite evidência física, categoria ou pontuação do browser.
Nenhum método novo escreve `physical_confirmed=1`.

A transação SQLite registra `ECONOMIC_REGISTRATION_QUEUED` antes do HTTP.
O envio reutiliza o cliente/Function/RPC existentes, com o mesmo `event_id` e
payload. Timeout, erro ou cancelamento da espera preservam REGISTRATION_PENDING
sem recibo. Reinício entre confirmação persistida e entrada na fila recupera
somente o registro; reinício durante HTTP conserva a recuperação já existente.
O slot ativo continua reservado até confirmação e encerramento explícito.

O cliente também recusa recibos contraditórios que concedam BinCoins/bônus sem
aluno ou pontos a eventos inválidos. Não calcula recompensa nem taxa localmente.

A tela operacional REGISTERED reutiliza o template prototipado de sucesso:
assets, classes, composição e CSS preservados. Substitui valores demonstrativos
em fragmento desconectado do DOM pelos totais do recibo, com “XP da turma”,
“Seus BinCoins” e “Registro confirmado”. Não soma o bônus novamente. Somente o
modo aluno mostra BinCoins. Pending/erro não mostram recompensa; Concluir chama
o backend e não há avanço automático por timer. O perfil DEV simulado permanece
sem recibo/tela de crédito. O protótipo separado continua explicitamente demo.

## Validação executada

| Verificação | Resultado |
| --- | --- |
| Backend TotemEdge completo, SQLite temporário e rede externa bloqueada | 750 aprovados, zero skips/falhas |
| Novos testes do handoff, incluindo simulação com evidência forjada | 9 aprovados; fazem parte dos 750 |
| TotemEdge → HTTP Deno oficial → Supabase local | 2 testes integrados aprovados |
| pgTAP `deposit_v1_scoring.sql` | 40 verificações aprovadas, transação revertida |
| Contratos JS LocalApi / DevApi | 7 + 20 aprovados |
| Smoke de navegador operacional | 7 verificações, zero erros; Edge headless |
| Ruff nos arquivos novos e serviços econômicos alterados | aprovado |
| Sintaxe JS e `git diff --check` | aprovados |

A prova local HTTP cobre válido com aluno, válido sem aluno, inválido, replay
idêntico, duas chamadas concorrentes e reutilização divergente do identificador.
Compara deltas de saldo/XP com recibo e linha histórica, categoria/bônus,
máquina/escola derivada e auditoria MACHINE. Cada evento tem um depósito e uma
auditoria, inclusive após replay/conflito.

A recuperação utiliza commit real no PostgreSQL **local** seguido de perda
controlada da resposta. SQLite fica pendente sem recibo; após reabertura, o mesmo
evento/payload recupera o recibo, sem novo saldo/auditoria. As fixtures de
confirmação física existem somente nos testes, não representam hardware real.

O browser foi testado com contratos controlados: Pending sem valores, REGISTERED
sem recibo rejeitado, valores variáveis 1377/2345 reproduzidos sem fórmula,
modo turma sem BinCoins, layout original e Concluir explícito. Capturas em
`Hardware/TotemEdge/frontend/.validation/economic-confirmed-{student,class}.png`
foram inspecionadas. Não são evidência de crédito de aluno real.

O primeiro pgTAP encontrou uma asserção antiga que contava todas as auditorias
do banco e pressupunha banco vazio. Foi corrigida para o `event_id` da fixture;
o banco não foi limpo. A primeira repetição do browser excedeu a janela de
startup de oito segundos durante a regressão concorrente; a espera limitada
foi ampliada para trinta segundos e o smoke final passou.

## Reproduzir a prova local

Com o Supabase **local existente** iniciado e a seed DEV conhecida (máquina
`40000000-0000-4000-8000-000000000001`, chave fictícia `edge-demo-key`), executar:

```powershell
& C:\Projetos\BinGo\Hardware\TotemEdge\backend\.venv\Scripts\python.exe C:\Projetos\BinGo\Hardware\TotemEdge\deploy\check_economy_local.py
```

O runner exige `API_URL=http://127.0.0.1:54321`, obtém a chave administrativa
somente do `supabase status` local e mantém essa chave em memória no processo
Deno. O handler tem rede limitada a loopback. O cliente Totem usa apenas a chave
técnica fictícia. Não inicia/resetta Supabase nem cria projeto Docker. Encerra
o servidor temporário ao terminar. Requer Deno (ou npx para executar Deno), Docker
CLI e a venv de desenvolvimento existente. Não deve ser apontado ao hospedado.

Os cinco eventos por execução integrada permanecem no banco **local**, marcados
por `detected_type=CONTROLLED_LOCAL_ECONOMY_TEST`, para inspeção. As duas rodadas
executadas deixaram dez eventos de teste; cada rodada altera somente saldos DEV
locais da seed. A suíte pgTAP reverte suas próprias fixtures. Nenhum saldo
hospedado/produção foi alterado.

## Falta para homologação operacional

1. Homologar o adaptador mecânico real e seu contrato de evidência durável de
   queda/conclusão autorizada. O runtime atual não produz esse sinal; o journal
   mantém o bloqueio conservador de conclusões PHYSICAL. Conectar a conclusão
   ao handoff econômico depende dessa entrega, sem usar confirmação SIMULATED.
2. Ligar a decisão canônica autorizada ao `prepare_payload` antes do compromisso
   físico. Não foi criado mapeamento para classes específicas novas da IA.
   O mapeamento legado documentado em VISION_SESSION_V1 continua intacto;
   o agrupamento `small` não autoriza inferir categoria por tamanho. Novos tipos
   fora das regras aprovadas exigem decisão de domínio. UNKNOWN/UNIDENTIFIED
   serve apenas a e-lixo aceito e não identificado, nunca a falha técnica.
3. Executar ciclo completo com hardware homologado em DEV: readiness antes do
   compromisso, decisão persistida, queda confirmada, perda de rede/reinício,
   registro/replay e inspeção dos saldos/histórico/auditoria e da tela real.
4. Confirmar configuração econômica/taxas aprovadas do ambiente de destino e
   fazer smoke controlado no DEV hospedado antes de qualquer promoção.

Não houve alteração de câmera, provedores IA, mecânica ou autenticação nesta
rodada. Alterações preexistentes do working tree foram preservadas. Não houve
commit, push, deploy, migration aplicada ou novo projeto Docker.
