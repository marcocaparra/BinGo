STATUS técnico — BinGo

Atualizado em: `2026-10-23`

Este arquivo é a fonte rápida de verdade técnica do projeto. Ele consolida as decisões vigentes de `database-model.md`, `data-contracts-totem-app-backend.md`, `supabase-edge-functions-mvp.md`, `FLUXO_ECOSSISTEMA_DESCARTE_V1.md`, `operacao-offline.md`, `missions-contract-v1.md` e `class-journey-v1.md`, além dos relatórios recentes da fundação de autenticação técnica de máquinas e do inventário do FastAPI. Para descartes, permanecem vigentes as decisões revisadas a partir de `2026-08-12`; para missões, prevalece o contrato conceitual revisado em `2026-09-15`; para Jornada/BinGópolis, prevalece o contrato de `2026-09-22`. Código ou banco só devem prevalecer quando houver evidência de uma decisão posterior ainda não documentada.

## Decisões oficiais vigentes

O backend de nuvem do BinGo V1 tem como stack oficial **Supabase, PostgreSQL e Supabase Edge Functions em Deno/TypeScript**. O PostgreSQL concentra persistência, integridade, transações e regras que precisam de garantia atômica; as Edge Functions formam a camada HTTP server-side para autenticação técnica, validação do contrato, autorização e orquestração. O FastAPI não é o destino arquitetural: permanece temporariamente no repositório como legado e referência executável durante uma migração controlada, até que todas as suas responsabilidades tenham equivalência comprovada no Supabase.

Em `2026-09-13`, foi aprovada a redenominação oficial por fator `100`: a regra-alvo passa de **8 para 800 BinCoins** por descarte válido com aluno identificado, de **19 para 1900 XP** para a turma e de **100 para 10000 XP** na meta semanal configurável. Isso altera a unidade oficial compartilhada por domínio, banco, backend, APIs, Admin e Mobile; não é mera formatação do frontend nem aumento econômico real. A categoria ambiental continua acrescentando somente um bônus percentual de BinCoins, calculado server-side e preservado como fotografia histórica; `bonus_rate` não é multiplicado por `100`, e a categoria nunca altera o XP. Na unidade-alvo, por exemplo, base `800` com taxa `0,50` produz bônus `400` e total `1200`. Sem aluno identificado, um descarte válido concede `0` BinCoins e o XP-base da turma; um evento inválido concede `0` BinCoins e `0` XP. As categorias canônicas V1 continuam `BATTERY`, `MOBILE_DEVICE`, `CABLE_WIRE`, `PERIPHERAL`, `OTHER_EWASTE` e `UNKNOWN`. As taxas provisórias de `100%`, `50%` e `25%` presentes somente em seeds de desenvolvimento não constituem política aprovada de produção.

A redenominação está implementada e validada no repositório, no ambiente Supabase local e no projeto hospedado DEV `bingo-dev` pelas migrations incrementais `database/migrations/011_points_unit_redenomination.sql` e `supabase/migrations/20260913120000_points_unit_redenomination.sql`. Elas convertem por fator `100` configurações, saldos, snapshots de depósitos e custos de resgate existentes, preservam percentuais e `audit_logs.metadata` históricos, atualizam os defaults para `800/1900/10000` e registram um evento SYSTEM agregado por escola afetada. `register_deposit_v1` não precisou mudar: continua lendo `school_settings` e passou naturalmente a trabalhar na nova unidade nos ambientes migrados. A aplicação, o postflight e a validação manual do fluxo autenticado do Mobile no `bingo-dev` não comprovam aplicação ou comportamento em produção.

O contrato do descarte aceita `event_id`, `class_id`, `student_id`, `is_valid`, `detected_type`, `waste_category_code` e `category_source`. `size` e `quantity` estão fora do contrato, assim como `machine_id`, `school_id`, valores de pontuação, taxa e bônus. A identidade da máquina é derivada de `X-Machine-Id` e `X-Api-Key`, e campos extras devem ser rejeitados. `register_deposit_v1` é a operação PostgreSQL oficial, atômica e idempotente: deriva a escola da máquina, valida relações e categoria, calcula a recompensa, grava depósito, saldos e auditoria na mesma transação e usa `event_id` como barreira contra repetição e concorrência. Repetição idêntica devolve a fotografia persistida; reutilização divergente do identificador é conflito. Sua execução é reservada a `service_role`.

Novos descartes reais não podem começar offline ou quando serviços críticos estiverem indisponíveis. Se a conexão falhar antes da queda física do objeto, o ciclo deve ser interrompido com segurança; se falhar depois que o objeto já caiu no compartimento interno, o evento deve ser preservado com o mesmo `event_id` e reenviado quando a comunicação voltar, sem prometer pontos antes da confirmação server-side. Essa recuperação de um ciclo iniciado online não caracteriza operação offline. A orientação V1 é um item por ciclo, mas quantidade não é detectada nem enviada ao backend.

## Implementado e comprovado

A integração operacional do Totem Simulator com Supabase foi implementada na
branch `feature/totem-supabase-integration`, validada localmente e homologada
no ambiente hospedado `bingo-dev` em `2026-10-01`. O PR #41 foi mergeado em
`develop`. O browser deixou de depender de FastAPI,
JWT proprietário e chave técnica hardcoded: usa somente o serviço loopback
existente em :8765, agora gateway `/bingo/*` além de `/vision/analyze`.
Contexto/PIN/resumo/ranking usam as novas Functions `totem-context-v1`,
`totem-student-pin-v1`, `totem-student-summary-v1` e `totem-rankings-v1`, todas com
machine-auth e escola derivada da máquina. A migration incremental 029,
`database/migrations/029_totem_server_reads_v1.sql` e
`supabase/migrations/20261001140000_totem_server_reads_v1.sql`, acrescenta quatro
leituras SECURITY DEFINER server-only, sem schema/grants de tabela/policies
novas. PIN preserva PBKDF2 existente, exige aluno ACTIVE e mesma turma/escola,
sem usar is_activated ou status de máquina como novas barreiras.

Health e register existentes foram reutilizados, com readiness fail-closed e
pontuação exclusivamente retornada pelo backend. Um UUID por ciclo e payload
completo são persistidos antes do compromisso físico simulado; falhas de
resultado desconhecido bloqueiam novos ciclos e permitem retry idempotente,
inclusive após reload. IA indisponível não vira descarte inválido. A integração
original de visão de `d8fff0b`, providers, upload/drop, acervo e testes foram
preservados. Summary usa snapshots históricos; ranking mantém inclusão legada
de INACTIVE com ordenação determinística. A compatibilidade da chave server-side
`default` do CLI foi limitada ao gateway Docker local; hospedado ainda exige
`bingo_backend`.

Validação local: reset local completo com 029; pgTAP 609 verificações/22 arquivos;
backend 176 testes sem skips; Deno fmt/lint/check e 62 unitários + 6 integrações
sem ignores; Node 33 (16 visão originais + 17 recovery), Python 22 (15 visão
originais + 7 gateway), browser 8 incluindo Supabase/gateway/SQL reais com visão
controlada; node --check, py_compile, Prettier e git diff --check passaram.
Os smokes comprovaram descarte identificado/turma, snapshots, saldo/XP, linha
persistida e replay sem duplicação. A validação local usou visão controlada e
testes originais; na homologação hospedada, AWS Rekognition e Gemini foram
exercitados ao vivo. `apps/totem_ui` ficou integralmente inalterado.

O preflight inicial encontrou o remoto em 028 e ausência de credencial conhecida
para smoke; essa pendência foi resolvida na homologação de `2026-10-01`. A
migration 029 (`20261001140000_totem_server_reads_v1.sql`) foi aplicada ao
`bingo-dev`, com histórico local/remoto alinhado, e as quatro Functions do Totem
foram deployadas. Uma máquina DEV específica do Totem Simulator foi provisionada
com credencial conhecida. `health-v1` retornou `AVAILABLE` e
`can_start_deposit=true`; contexto e PIN hospedados foram comprovados com dados
reais. Um aluno demo recebeu PIN exclusivamente para smoke DEV. O descarte
completo pelo simulador foi persistido por `register-deposit-v1`, atualizando
BinCoins do aluno e XP da turma conforme os snapshots do backend. Todos os testes
e o smoke end-to-end passaram. **A comprovação hospedada vale somente para
`bingo-dev`, sem homologação de produção.** Detalhes e resultados em
`totem-supabase-integration-v1.md`; startup sem FastAPI no README do simulador.

A leitura real de Totens no Admin está implementada e validada **somente localmente**
pelo contrato `admin-totems-v1.md` e pela migration 030 equivalente nos dois trilhos:
`database/migrations/030_admin_machines_v1.sql` e
`supabase/migrations/20261001150000_admin_machines_v1.sql`.
`get_admin_machines_v1()` não recebe parâmetros, deriva identidade por `auth.uid()`
e exige ADMIN ACTIVE: A consulta globalmente e B/C somente a própria escola.
Retorna identidade, escola por join, nome, status, firmware/last_seen nullable e
flags bin_full/camera_ok/net_ok. SECURITY DEFINER, search_path vazio e EXECUTE
somente authenticated; PUBLIC/anon/service_role não executam. Nenhum SELECT de
tabela ou policy foi aberto, nenhum hash é retornado e machine-auth foi preservado.
A tela Totens agora usa AdminMachinesRepository, com loading/empty/error/refetch
e invalidação de respostas atrasadas após troca/logout de sessão. Removidos o
mock AdminStore.machines, códigos BT, porta, depósitos do dia e diagnóstico fictício.
Os sinais são fotografia persistida: status é exibido sem inferência por last_seen,
sem heartbeat, polling, SLO ou disponibilidade operacional calculada.
Reset local completo, 23 arquivos/629 verificações pgTAP, 178 testes backend,
94 testes Admin e smoke real Auth/RPC/Angular A/B/C passaram sem falhas/skips finais.
Build, TypeScript, Prettier dos arquivos Angular alterados e diff-check passaram.
Os skips iniciais do backend foram resolvidos configurando os bancos de teste
PostgreSQL locais; permanecem 13 avisos JWT legados. A **030 não foi promovida
ao bingo-dev**; não houve ação remota nesta fatia.

A leitura real de Descartes no Admin está implementada e validada **somente
localmente** pelo contrato `admin-deposits-v1.md` e pela migration 031 equivalente
nos dois trilhos: `database/migrations/031_admin_deposits_v1.sql` e
`supabase/migrations/20261001160000_admin_deposits_v1.sql`.
`get_admin_deposits_v1()` não recebe parâmetros, deriva o admin exclusivamente de
`auth.uid()`, exige `ACTIVE` e autoriza A globalmente e B/C apenas na própria escola.
Retorna IDs para identidade técnica, nomes derivados por joins e os snapshots
históricos de validade, classificação, bônus, BinCoins e XP persistidos em
`deposits`, ordenados por `created_at DESC, deposit_id DESC`. Não recalcula valores,
não inventa status, tamanho, peso, impacto ou telemetria e preserva aluno,
categoria e origem nulos. A função é STABLE, SECURITY DEFINER, usa search_path
vazio e tem EXECUTE somente para authenticated; PUBLIC/anon/service_role foram
revogados e nenhum SELECT direto, policy ou acesso de máquina foi ampliado.

A tela usa `AdminDepositsRepository`, com loading/empty/error/retry/refetch e
descarte de respostas atrasadas após logout/troca de sessão. Admin A vê a escola;
B/C ficam no escopo server-side. Removidos `AdminStore.deposits`,
`AdminStore.discardStats`, os mocks 1284/32/184, cards agregados, filtros e estados
inventados. Não foi criada RPC de estatísticas e `register_deposit_v1` permanece
inalterada. Na validação histórica de `2026-10-01`, o reset local aplicou a 031;
pgTAP completo passou com 24 arquivos e 646
verificações; backend passou com 180 testes, sem skips; Admin passou com
107 testes; nove integrações locais Auth/RPC/Angular passaram, incluindo A/B/C para
Descartes. Build, TypeScript, Prettier e diff-check passaram. A **031 não foi
promovida ao bingo-dev** e não houve ação remota. Detalhes em
`admin-deposits-v1.md`.

A auditoria dos dados demonstrativos restantes do Admin foi concluída localmente
em `2026-10-01`, na branch `feature/admin-real-data-cleanup`. **Missões,
demais controles econômicos e Solicitações de ajuda estão BLOQUEADOS POR CONTRATO**,
cada um separadamente. Descartes deixou esse inventário depois da aprovação de uma
interface Admin própria e foi implementado separadamente pela 031 acima. Missões tem runtime real,
mas leitura Admin, gestão global de definições e criação de ciclos carecem de
contratos técnicos. Em Economia, base/XP/meta semanal persistidos por escola
precisam ser conciliados com o escopo global descrito pelo contrato Admin;
bônus por categoria não equivale ao multiplicador demo. Ajuda continua sem
domínio backend oficial; foi feito somente preflight.

O teto do BinBazar e as demais áreas reais permanecem intactos. Os mocks ainda
consumidos, diálogos e seletor de cenário foram preservados e explicitamente
identificados. Removidos apenas metadados fictícios de escola/operador e helpers
sem consumidores; corrigidos textos antigos que confundiam dados reais e demo.
Na fase de auditoria anterior à 031, nenhuma migration/RPC/grant/policy foi criada
ou alterada. A implementação posterior de Descartes criou a leitura 031 descrita
acima. Contratos mínimos e inventário histórico estão em
[Auditoria Admin](admin-real-data-audit-v1.md).

Validação histórica da auditoria em `2026-10-01`, antes de Descartes reais:
reset Supabase local até 030; pgTAP 629 verificações/23 arquivos;
backend 178 testes; Admin/browser 104 testes, incluindo 10 novos para isolamento
dos demos; 8 integrações reais locais Auth/RPC/Angular. Sem falhas/skips finais.
Build, TypeScript, Prettier dos arquivos alterados e diff-check passaram; seguem
13 avisos JWT legados. As suítes de banco foram repetidas sequencialmente após
interferência inicial; equivalência SQL da 030 agora tolera CRLF/LF sem mudar
migrations. Um aviso de UI foi ajustado preservando a verificação existente do
teto. Nenhuma ação remota; a 030 continua não promovida ao `bingo-dev`.

Em `2026-10-23`, a preparação do PR `feature/admin-real-data-cleanup` corrigiu
somente CI e documentação e reexecutou a validação local. Docker/CLI estavam
disponíveis; start e reset explicitamente locais aplicaram as 31 migrations.
pgTAP passou com 646 verificações/24 arquivos; backend com 180 testes, zero skips
e 13 avisos JWT legados; Admin com 107 testes e as nove integrações reais locais
Auth/RPC/Angular passaram, sem falhas/skips. Build, TypeScript, equivalência
030/031 nos dois trilhos, actionlint, Prettier e diff-check passaram.

A CI de backend agora instala o CLI pelo lockfile, inicia e verifica Supabase
local, aplica migrations/seeds locais, executa pgTAP e pytest em sequência e
rejeita coleta vazia/skips pelo JUnit. Os scripts de readiness e JUnit foram
exercitados localmente, inclusive rejeição de relatórios vazios/com skip. O job
Linux/GitHub Actions ainda não foi executado nesta tarefa; seus checks deverão
ser confirmados após publicação. O registro da auditoria até 030 foi identificado
como histórico, anterior à resolução de Descartes pela 031. Missões, Economia
ampliada e Ajuda continuam demonstrativas. Nenhuma migration ou regra aprovada
foi alterada; nenhuma ação de banco hospedado, commit, push, merge, deploy ou PR
foi realizada. Merge de código e promoção de banco são etapas separadas; a
liberação hospedada da tela depende da promoção e do postflight das migrations
pendentes. Resultados e procedimento em [Admin Descartes V1](admin-deposits-v1.md).

A fundação de autenticação administrativa do Admin Web V1 está implementada e
comprovada localmente pelas migrations incrementais equivalentes
`database/migrations/023_admin_auth_foundation.sql` e
`supabase/migrations/20260930120000_admin_auth_foundation.sql`. `admins.auth_user_id`
é um vínculo UUID opcional e único com Supabase Auth; o banco aceita somente
`ADMIN_A/B/C`, exige A global com escola nula e B/C com escola obrigatória, e
mantém `status` explícito ACTIVE/INACTIVE (default ACTIVE). A RPC sem parâmetros
`get_my_admin_context_v1()` resolve somente o próprio contexto por `auth.uid()`,
sem hashes, com SECURITY DEFINER, search_path vazio e EXECUTE exclusivo de
authenticated. `admins` permanece RLS fail-closed, sem leitura/escrita direta
aberta ao cliente. O Angular usa Supabase Auth para login, restauração e logout,
consulta novamente o contexto no refresh e bloqueia ausência de vínculo,
inatividade e falhas sem fallback de autenticação demonstrativa. Alunos, turmas,
trocas de turma, BinBazar operacional, teto global, estrutura de escolas/contas
e Overview usam as fatias reais descritas abaixo; Totens usa a leitura 030 descrita acima. Os outros domínios e demais controles econômicos continuam demonstrativos
explícitos no AdminStore. `password_hash` permanece
legado FastAPI, sem sincronização com Auth. A migration recusa papéis históricos
ambíguos e exige classificação manual antes de futura promoção em bancos que
os contenham, preservando IDs e histórico. Não houve promoção desta migration
ao `bingo-dev` nem aplicação remota. Procedimento local e limites em
`admin-supabase-auth-session.md`.

A gestão escolar de alunos e turmas está implementada e comprovada localmente
na branch `feature/admin-school-management-foundation`, pelas migrations
equivalentes `database/migrations/024_admin_school_management_foundation.sql` e
`supabase/migrations/20260930130000_admin_school_management_foundation.sql`.
`students.registration` e `students.email` são text nullable: os históricos
permanecem nulos, sem matrícula inventada ou vínculo Auth automático. Matrícula
é única por escola quando informada, preserva zeros à esquerda, distingue caixa
e não admite branco ou whitespace nas extremidades; novas mutations exigem RA.
As RPCs `get_admin_students_v1`, `get_admin_classes_v1`,
`create_admin_student_v1`, `update_admin_student_v1`, `create_admin_class_v1` e
`update_admin_class_v1` derivam o administrador e a escola por `auth.uid()`,
validam ACTIVE a cada operação e mantêm SECURITY DEFINER com search_path vazio.
B lê e administra somente sua escola; C lê alunos/saldos/XP e lookup de turmas,
mas é rejeitado server-side nas quatro escritas. As mutations registram ator
derivado em `audit_logs` na mesma transação, incluindo old/new de turma e status.
Saldo/PIN/Auth/ativação/XP não são editáveis, e a troca direta por B não reescreve
depósitos, Missões ou outros históricos. Não foram abertas policies escolares
amplas nem escrita direta: as cinco policies e grants Mobile continuam intactos.
O Angular usa repository escolar, IDs reais, loading/empty/error, formulários
restritos e recarga autoritativa após salvar, sem fallback aos mocks. Turmas
mostram segmento/série/nome/quantidade/XP, sem status ou participação inventados.
Solicitações de troca e BinBazar operacional passaram aos fluxos reais descritos
abaixo; os outros domínios permanecem demonstrativos.
A assistência escolar por ADMIN_A ainda não está integrada nesta fatia; isso
não é uma proibição permanente do contrato. As migrations 023 e 024 permanecem
somente locais, sem promoção ao `bingo-dev`. Reset com 24 migrations, 467 testes
pgTAP, 78 testes backend e smoke real local B/C Auth/RPC/Angular passaram.
Contratos, reprodução e limites em `admin-school-management-foundation.md`.

O fluxo real de solicitação de troca de turma C → decisão B está implementado e
comprovado localmente pelas migrations equivalentes
`database/migrations/025_class_change_requests_v1.sql` e
`supabase/migrations/20260930140000_class_change_requests_v1.sql`.
`class_change_requests` preserva escola/aluno/origem/destino/solicitante,
PENDING/APPROVED/REJECTED/CANCELED, resolvedor e timestamps, com FKs RESTRICT,
constraints de resolução e RLS fail-closed sem acesso direto do browser.
As RPCs `get_class_change_requests_v1`, `create_class_change_request_v1`,
`approve_class_change_request_v1`, `reject_class_change_request_v1` e
`cancel_class_change_request_v1` exigem ACTIVE e derivam escola/ator via Auth.
C cria/lista próprias/cancela próprias pendentes; B lista sua escola e decide;
A não participa. Criação captura origem sob lock, usa UUID do cliente para replay
idempotente e conflita em payload divergente. Decisões bloqueiam request/aluno;
approve valida a origem contra turma atual, sem sobrescrever mudança mais recente.
`is_stale` é derivado na leitura, sem status STALE persistido. Mutation e auditoria
são transacionais; retry não duplica logs nem reaplica troca já aprovada. Somente
students.class_id muda, preservando depósitos/XP histórico/Missões/Jornada/resgates.
Angular usa solicitações reais, alunos/turmas UUID, loading/empty/error/submitting,
conflito explícito, aprovação bloqueada em stale e recarga autoritativa. Pendências
agora combina trocas e resgates reais, pela integração BinBazar da 026 abaixo.
Reset com 25 migrations, 547 testes pgTAP, 87 backend, 38 browser e três integrações
locais passaram, incluindo os smokes de aprovação, stale e cancelamento. Nenhum
skip; somente avisos JWT legados preexistentes. A migration 025, assim como 023/024,
não foi promovida ao bingo-dev. Regras funcionais e decisões técnicas separadas em
`class-change-requests-v1.md`.

O BinBazar operacional Admin está implementado e comprovado somente localmente
pelas migrations equivalentes `database/migrations/026_admin_binbazar_v1.sql` e
`supabase/migrations/20260930150000_admin_binbazar_v1.sql`. B/C ACTIVE, derivados
por Auth/admins, leem produtos e resgates da própria escola e atualizam
nome/descrição/estoque/ativo sem escolher escola/ator. A não participa da operação.
As RPCs `get_admin_binbazar_products_v1`, `update_admin_binbazar_product_v1`,
`get_admin_redemptions_v1`, `deliver_admin_redemption_v1` e
`cancel_admin_redemption_v1` mantêm SECURITY DEFINER/search_path vazio, EXECUTE
somente authenticated e RLS fail-closed sem acesso direto nem policies Mobile novas.
Entrega/cancelamento bloqueiam primeiro o pedido e são idempotentes: somente uma
transição terminal vence, inclusive Mobile cancel × Admin deliver. Entrega não
cobra novamente nem muda estoque. Cancelamento reutiliza núcleo econômico interno
compartilhado com a 022: refund exato do snapshot, restauração somente de reserva
finita ainda com estoque finito; NULL ilimitado é preservado. Mutation e auditoria
ADMIN são transacionais; retry não duplica efeitos/logs. A assinatura, autorização,
resultado, idempotência e metadata original do cancelamento Mobile foram mantidos;
nenhum arquivo histórico da 022 foi editado. Snapshots, Extrato, depósitos, XP,
Missões e Jornada permanecem preservados, sem expiração automática.
Angular usa repository real para produtos, fila e bloco de resgates em Pendências,
IDs UUID, snapshots, busca pelo identificador interno BGO, estados reais e refetch,
sem fallback mock. Na entrega 026, o Overview e outros domínios ainda eram
demonstrativos; o Overview foi integrado na fatia descrita abaixo. Na entrega 026 ainda não existia teto global persistido:
criação e edição de preço estavam bloqueadas. A 027 abaixo conclui esses caminhos
com configuração autoritativa, sem usar o 300 demo. DELETE continua fora do V1.
Reset final com 26 migrations, 561 verificações pgTAP, 121 testes backend,
47 browser e quatro integrações Auth/RPC/Angular locais passaram, sem skips;
build, TypeScript, Prettier e diff-check passaram. Restam somente 13 avisos JWT
legados preexistentes. A 026, como 023/024/025, não foi promovida ao bingo-dev.
Contratos, limites, concorrência, reprodução e relatório em `admin-binbazar-v1.md`.

O teto global real do BinBazar está implementado e comprovado somente localmente
pelas migrations incrementais equivalentes
`database/migrations/027_binbazar_global_price_cap_v1.sql` e
`supabase/migrations/20261001120000_binbazar_global_price_cap_v1.sql`, sem editar
022–026. `global_economic_settings` é singleton com teto integer positivo quando
informado, timestamps e valor inicial NULL (ainda não configurado), sem valor
inventado nem globalização de 800 BinCoins, 1900 XP, 10000 XP ou bônus ambientais.
`get_binbazar_price_cap_v1()` permite consulta por A/B/C ACTIVE;
`update_binbazar_price_cap_v1(p_max_price)` permite somente A ACTIVE, com lock,
auditoria transacional e no-op para o mesmo valor. `audit_logs.school_id` agora
aceita NULL como escopo global, preservando FK RESTRICT e todas as auditorias
escolares; A não recebe escola artificial.
B/C ACTIVE criam produtos da própria escola por
`create_admin_binbazar_product_v1` com UUID do cliente e editam preço/categoria
pela assinatura completa de `update_admin_binbazar_product_v1`. A assinatura
não-preço da 026 continua compatível. Escola/ator são derivados via Auth, nome
não vazio, preço positivo, estoque NULL/zero/finito e teto configurado são
validados server-side. Recibo privado em rewards (`created_by_admin_id` e
`admin_creation_payload`) preserva a intenção original sem backfill histórico:
replay idêntico não duplica produto/auditoria mesmo após edição/consumo/redução;
UUID divergente conflita. Update idêntico também é no-op. SECURITY DEFINER,
search_path vazio, EXECUTE somente authenticated e RLS fail-closed permanecem;
nenhuma policy Mobile ou escrita direta do browser foi aberta.
Reduzir o teto não modifica preços/estoque/ativo existentes nem snapshots,
resgates, saldo ou Extrato. Edição que mantém preço histórico acima do teto
continua permitida; novo produto ou preço alterado deve respeitar o limite atual.
FOR SHARE na configuração precede lock do produto e conflita com FOR UPDATE de
A, mantendo validação até commit. Corridas reais create/update × redução
comprovaram ambos os ordenamentos serializados, sem validação contra teto vencido.
Angular Economia agora mostra teto real/NULL e permite A definir/editar sem
confirmação otimista; B/C veem teto vigente, criam/editam produtos UUID e refazem
leitura autoritativa. Ausência/erro de teto bloqueia somente criação/preço, sem
fallback mock; outras edições continuam disponíveis. Demais controles da Economia
e outros domínios ainda demonstrativos estão explicitamente identificados.
Reset completo com 27 migrations, 20 arquivos/576 verificações pgTAP, 151 backend,
55 browser e cinco integrações Auth/RPC/Angular locais passaram, sem skips.
Build, TypeScript, Prettier e git diff-check passaram. As 13 advertências JWT
legadas preexistentes permanecem. Regressão 022/026 confirmou solicitação e
cancelamento Mobile, entrega/cancelamento Admin, concorrência e snapshots intactos.
Fixtures/Auth foram removidos e a configuração original restaurada. A 027,
como 023–026, não foi promovida ao bingo-dev; nenhum commit/push/PR/deploy/ação
remota foi executado. Contratos técnicos, concorrência, auditoria global,
reprodução e limites em `binbazar-global-price-cap-v1.md`.

A estrutura real de Escolas e Administradores está implementada e comprovada
somente localmente pelas migrations equivalentes
`database/migrations/028_admin_structure_management_v1.sql` e
`supabase/migrations/20261001130000_admin_structure_management_v1.sql`.
As migrations 023–027 foram preservadas integralmente. Escolas mantêm somente
UUID/nome/timestamps, sem cidade/endereço/status/implantação nem unicidade global
de nome inventados. `get_admin_schools_v1` e `create_admin_school_v1` permitem
somente A ACTIVE listar globalmente e criar por UUID idempotente; contagens de
alunos/turmas/admins/máquinas são derivadas dos dados reais.
`get_managed_admins_v1`, `create_managed_admin_v1` e `update_managed_admin_v1`
permitem A gerir contas globalmente e B somente C da própria escola; C é recusado.
Criação define role/escopo corretos; atualização aceita somente nome/email/status,
sem alteração retrospectiva de role/escola, IDs, Auth ou password_hash. Nova
identidade mantém auth_user_id/password_hash NULL: não cria usuário Auth, senha,
convite ou acesso automático. UI retorna vínculo boolean, sem UUID Auth/hash;
email administrativo não altera credenciais da conta Auth vinculada.
Recibos técnicos privados em `admin_structure_creation_receipts` guardam intenção
original por tipo/UUID/ator/payload, com RLS fail-closed. Replay idêntico não
reinserta nem duplica auditoria, inclusive após edição; UUID divergente conflita.
Email respeita unicidade existente; update idêntico não muda timestamp/auditoria.
Mutations de contas serializam pelo mesmo advisory transaction lock, revalidam
ACTIVE após a espera e bloqueiam ator/alvo. Auto-inativação e remoção do último A
ACTIVE são recusadas no banco. Corridas entre dois A nos dois ordenamentos e em
READ COMMITTED/REPEATABLE READ preservaram um A ACTIVE; o perdedor foi recusado
ou abortou por snapshot antigo. Reativação autorizada permanece disponível.
Auditoria é transacional e registra ator derivado e old/new seguros: criação de
escola/A usa escopo global NULL; criação/edição de B/C usa a escola da entidade.
Não há DELETE, leitura ampla de admins, escrita direta, novos grants/policies
Mobile ou alterações em históricos de outros domínios. SECURITY DEFINER,
search_path vazio e EXECUTE somente authenticated seguem o baseline.
Angular usa repository/telas reais, IDs UUID, estados loading/empty/error/
submitting/conflict e refetch. Os formulários demo de escola/admin foram removidos;
na entrega 028, o dashboard ainda era demonstrativo; a fatia abaixo substitui
essa fotografia por fontes reais.
Reset isolado final com 28 migrations, 21 arquivos/590 verificações pgTAP,
176 backend, 66 browser e seis smokes reais Auth/RPC/Angular locais passaram,
sem skips. Build, TypeScript, Prettier e diff-check passaram. Restam 13 avisos JWT
legados preexistentes. Foram corrigidos problemas iniciais de ambiente/seletor/
espera de render e refeita isoladamente uma execução de reset local sobreposta.
As fixtures e usuários Auth efêmeros foram removidos. A 028, como 023–027,
continua sem promoção ao bingo-dev, sem commit/push/PR/deploy/ação remota.
Regras oficiais, decisões técnicas, provisionamento separado, reprodução e
resultados em `admin-structure-management-v1.md`.

O Overview A/B/C está integralmente baseado nas leituras reais existentes e
comprovado localmente. Esta fatia é somente composição/consulta: não criou
migration, RPC, policy, grant nem alteração de backend. A última migration
permanece 028; as migrations anteriores foram preservadas.
AdminDashboardRepository compõe AdminStructureRepository, AdminSchoolRepository,
ClassChangeRequestsRepository, AdminBinbazarRepository e BinbazarPriceCapRepository.
A consulta escolas/admins/teto: total de escolas, soma de alunos/máquinas
cadastradas, contas total/ACTIVE/INACTIVE/sem vínculo Auth e teto real/NULL;
listas exibem escolas e contas reais, sem cidade/status/implantação/saúde inventados.
Máquinas cadastradas representam somente contagem estrutural, sem estado online.
B consulta alunos/turmas, contas C locais, trocas PENDING, resgates PENDING,
produtos ativos/esgotados e teto. C consulta alunos/turmas, próprias solicitações,
resgates/produtos da escola e teto, sem RPC de gestão de contas. Os resgates usam
snapshots; estoque zero considera produto ativo, e NULL continua ilimitado.
Pendências são reais, ordenadas por created_at; stale aparece sem aprovação no
Overview. Turmas mostram alunos/XP, sem status ou participação fictícios.
Entrada/retorno/refresh/Atualizar consultam uma fotografia autoritativa; não há
polling. O coordenador não duplica a leitura de alunos/turmas já feita pelas
solicitações, nem mantém outro cache. Loading mostra …, erro mostra Indisponível,
e zero/Não configurado somente após leitura confirmada. Erro parcial conserva
fontes saudáveis; logout/troca de contexto invalidam os repositories e descartam
respostas antigas, sem fallback. Atalhos navegam somente às telas autorizadas.
Removidos demoSchools/demoClasses/demoPendingRedemptions e todos os eventos e
números fictícios do Overview. `helpRequests` permanece apenas na tela demo de
Ajuda; na entrega do Overview, Máquinas e Descartes ainda eram demo, substituídos
depois pelas leituras 030 e 031 acima. Missões e demais configurações
econômicas continuam demonstrativas. O Overview não consome essas fontes e não
mostra seletor demo, nome de escola fixo ou sinal de saúde fictício do shell.
Reset local com 28 migrations e seeds existentes, 21 arquivos/590 verificações
pgTAP, 176 backend, 79 browser e sete smokes reais Auth/RPC/Angular passaram,
sem falhas/skips finais. Foram acrescentados 13 testes browser e um smoke real
A/B/C de dashboard, incluindo isolamento, refresh após decisões e restauração.
Build Angular, TypeScript, Prettier e diff-check passaram. Permanecem 13 avisos
JWT legados. Uma fixture de troca de sessão com escola sem UUID foi corretamente
recusada; a correção para UUID válido passou sem alterar o parser/segurança.
Flutter e Edge Functions não rodaram porque não foram alterados.
Fixtures/usuários efêmeros removidos; teto/timestamps originais restaurados.
Não houve commit/push/PR/deploy/ação remota ou promoção ao bingo-dev nesta fatia.
Fontes, métricas, limites e reprodução em `admin-dashboard-v1.md`.

O modelo V1, o contrato de dados, as migrations correspondentes e a RPC `register_deposit_v1` estão implementados no repositório. A implementação documentada cobre snapshots de recompensa, catálogo de categorias, restrição de execução da RPC, idempotência sequencial e concorrente, atualização de saldos e auditoria transacional. A redenominação acrescentou a décima primeira migration Supabase e a migration `011` do trilho PostgreSQL; reset completo, testes específicos de conversão/rollback, pgTAP e testes de integração locais comprovaram o comportamento na nova unidade. Em `2026-09-14`, a migration `20260913120000_points_unit_redenomination.sql` foi aplicada de forma controlada no `bingo-dev`, e o postflight confirmou onze migrations locais/remotas alinhadas, defaults `800/1900/10000`, saldo smoke de `16` para `1600`, XP smoke de `19` para `1900` e o snapshot histórico do depósito convertido para bônus `800`, BinCoins `1600` e XP `1900`, sem alterar seu identificador, taxa ou instante. O `audit_logs.metadata` histórico preservou o mesmo SHA-256, e foi criado exatamente um evento SYSTEM `POINTS_UNIT_REDENOMINATED_V1` para a escola afetada. Essa comprovação é exclusiva do ambiente DEV e não declara aplicação em produção.

Em `2026-09-15`, o usuário validou manualmente no celular o aplicativo que já estava instalado, sem reinstalação e sem novo `flutter run`. Ao abrir a conta autenticada, a carteira apresentou os valores na escala `×100`, comprovando que o fluxo autenticado do Mobile consumiu do `bingo-dev` os saldos já redenominados sem depender de uma nova instalação do aplicativo. Essa evidência se limita ao ambiente DEV e não constitui validação de produção.

A fundação compartilhada das Edge Functions está implementada em `supabase/functions/_shared`. Ela fornece `authenticateMachine(request)` e `withMachineAuthentication(handler)`, usa `X-Machine-Id` e `X-Api-Key`, consulta server-side somente a identidade necessária da máquina e entrega ao handler uma identidade imutável `{ id, schoolId }`, sem expor hash, `service_role` ou detalhes do PostgREST. O formato atual de credencial foi preservado com PBKDF2-HMAC-SHA256, e falhas de autenticação são uniformizadas sem revelar se a máquina existe. A permissão técnica correspondente concede a `service_role` somente `SELECT (id, school_id, api_key_hash)` em `machines`; testes comprovam ausência de leitura das demais colunas, ausência de escrita e ausência de acesso ao hash por `anon` e `authenticated`.

A primeira fronteira HTTP está implementada como a Edge Function implantável `register-deposit-v1`, disponível localmente em `POST /functions/v1/register-deposit-v1`. Ela valida o método antes da autenticação, rejeita campos extras, usa exclusivamente a identidade server-side da máquina, chama uma única vez `register_deposit_v1` e devolve a fotografia persistida. Criação responde `201`; replay idêntico responde `200`; conflito semântico responde `409`. A integração local comprovou autenticação, criação, replay, conflito, concorrência, descarte anônimo, descarte inválido, exatamente um depósito, uma auditoria e uma aplicação de saldo por evento. Não foi adicionado CORS no código da Function nem credencial técnica ao Totem Web.

O readiness central está implementado como a Edge Function `health-v1`, disponível localmente em `GET /functions/v1/health-v1` e equivalente ao contrato conceitual `GET /health`. Ela reutiliza a autenticação técnica e chama a RPC somente leitura `check_backend_readiness_v1`, restrita a `service_role`, para verificar PostgreSQL fora de recovery e com `default_transaction_read_only` permitindo escrita. Somente `200 + AVAILABLE + can_start_deposit=true` comprova saúde; `503/UNAVAILABLE` é retornado apenas quando o handler obtém um resultado negativo comprovado. Credencial inválida permanece `401`, e timeout, ausência de resposta, `500` ou outra falha de infraestrutura também são condições fail-closed sem promessa de `503`.

No mesmo preflight remoto de `2026-09-04`, as Edge Functions `register-deposit-v1` e `health-v1` foram observadas ativas no `bingo-dev`. Essa verificação comprova presença e estado ativo, sem substituir testes funcionais dos contratos HTTP.

O baseline backend de Supabase Auth e RLS está implementado e comprovado localmente. A identidade segue `auth.uid() → students.auth_user_id → school_id/class_id`; usuários autenticados leem somente seu perfil, sua turma e sua escola, enquanto identidades sem vínculo não recebem contexto. As onze tabelas preexistentes permanecem protegidas pelo baseline; com as cinco tabelas de Missões e as três tabelas da Jornada, o baseline totalizava dezenove tabelas com RLS. A migration 025 acrescenta class_change_requests e eleva somente o ambiente local a vinte tabelas com RLS; não foi promovida ao bingo-dev. `anon` não acessa dados privados e não há escrita direta para `authenticated`. O catálogo `waste_categories` permanece integralmente legível por `anon` e `authenticated`, inclusive categorias inativas, por policy explícita. As policies relacionadas exigem `SELECT(auth_user_id)` para `authenticated`; teste real comprovou `42501` sem o grant, e a RLS limita sua exposição ao vínculo próprio.

O primeiro fluxo vertical real do Mobile está implementado: login por e-mail/senha no Supabase Auth, restauração pela sessão persistida do SDK, leitura do próprio `students` por `auth_user_id`, leitura da turma e escola vinculadas sob RLS e logout. O perfil autenticado reutiliza o frontend final somente para nome, escola, turma, saldo individual de BinCoins (`students.points_student_balance`) e XP da turma (`classes.points_class_balance`); informações sem fonte real permanecem ocultas. O modo piloto continua explícito e isolado, com seus mocks locais, e a identificação por PIN no Totem permanece separada.

O Ranking V1 está implementado no repositório e aplicado no `bingo-dev` como uma leitura autenticada e somente leitura do saldo atual de XP das turmas. A RPC `get_class_ranking_v1()` não recebe `school_id`: deriva `auth.uid() → students.auth_user_id → school_id`, valida o vínculo entre aluno, turma e escola e retorna somente `class_id`, `class_name` e `points_class_balance` das turmas da mesma escola. A ordenação autoritativa é `points_class_balance DESC, class_id ASC`; o UUID funciona somente como desempate técnico determinístico temporário, sem instituir regra competitiva de empate. O Mobile consome a mesma lista para posição da própria turma e top 3, reutiliza a composição visual canônica e não recorre aos mocks do piloto em ausência ou falha. O preflight somente leitura de `2026-09-21` confirmou `20260919120000_get_class_ranking_v1.sql` no histórico remoto; isso não comprova produção.

O histórico próprio de descartes também está implementado no repositório: a migration `010_mobile_deposit_history_rls.sql` autoriza `authenticated` a ler apenas depósitos ligados ao próprio `student_id`, preservando a identidade histórica mesmo após troca de turma, e o Mobile possui repository/adapter para apresentar esse histórico na carteira autenticada. A branch contém testes de banco, integração e Flutter para esse recorte. Posteriormente à verificação de `2026-09-04`, a migration Supabase correspondente, `20260905120000_mobile_deposit_history_rls.sql`, foi aplicada no `bingo-dev`; `supabase migration list` confirmou dez migrations locais e remotas alinhadas. Depois da aplicação, o Mobile autenticado voltou a consultar `deposits` sem o erro `42501`, e o histórico pessoal foi validado manualmente nesse ambiente hospedado. Essa comprovação é exclusiva do ambiente DEV e não demonstra aplicação ou comportamento em produção.

A Trilha do Restaurador V1 é derivada exclusivamente da quantidade histórica de descartes válidos identificados do aluno. Não existe contador ou nível persistido no aluno. Missões, BinCoins e XP da turma não participam do cálculo. A identidade histórica é `deposits.student_id`, inclusive após mudança de turma, e somente linhas com `is_valid = true` contam. Os thresholds V1 são: nível 0 `NONE` com zero descartes; nível 1 `APPRENTICE` de 1 a 4; nível 2 `EXPLORER` de 5 a 9; nível 3 `RESTORER` de 10 a 19; nível 4 `GUARDIAN` de 20 a 49; e nível 5 `HERO` a partir de 50. A RPC `get_student_profile_progress_v1()` deriva o aluno exclusivamente de `auth.uid()`, e as migrations equivalentes `020_get_student_profile_progress_v1.sql` e `20260921120000_get_student_profile_progress_v1.sql` estão implementadas e validadas localmente. Em `2026-09-21`, a migration Supabase foi aplicada de forma controlada no `bingo-dev`; o postflight confirmou 20 migrations alinhadas, função sem parâmetros, `STABLE`, `SECURITY DEFINER`, `search_path` vazio e execução somente para `authenticated`. Ela não foi aplicada em produção.

O perfil autenticado do Mobile consome essa RPC sem enviar `student_id`, valida o vínculo e apresenta contagem, nível e progresso nos componentes visuais já existentes. Avatar e tema permanecem preferências exclusivamente cosméticas e locais, persistidas por aparelho em chaves namespaced por `AuthenticatedStudentProfile.id`; nenhum dado de personalização é enviado ao Supabase. O desbloqueio reutiliza os `requiredLevel` existentes e usa o nível real da Trilha. O modo piloto preserva suas chaves e comportamento anteriores.

O smoke hospedado da Trilha em `2026-09-21` usou o gateway e o repository reais do Mobile contra o `bingo-dev`. A conta vinculada retornou exatamente uma linha para o próprio aluno, com 2 descartes válidos, nível 1 `APPRENTICE`, 3 descartes restantes e progresso `0.4`; os saldos observados permaneceram em 3300 BinCoins e 3800 XP da turma. Uma identidade Auth temporária sem aluno retornou zero linhas e foi removida ao final, enquanto `anon` não conseguiu executar a RPC. A recriação do armazenamento local preservou avatar e tema para o mesmo `student_id` e manteve defaults para a segunda identidade, sem escrita de personalização no Supabase. A suíte de widgets relacionada passou sem atualização de golden ou alteração estrutural do frontend.

O smoke hospedado em `bingo-dev`, executado em `2026-08-27` pelo gateway e repository reais do Mobile, comprovou login, sessão válida, uma linha própria em `students`, sua `classes`, sua `schools`, ausência de acesso a outro aluno, restauração após recriação do cliente e logout. A fotografia observada foi de `16` BinCoins e `19` XP na unidade antiga então implementada; esses valores comprovam a leitura do estado da conta de teste, não a unidade-alvo agora aprovada.

Em `2026-09-04`, a seed `database/seeds/010_bingo_dev_demo_dataset.sql` foi aplicada uma única vez no `bingo-dev`, após preflight remoto sem conflitos. O postflight confirmou sete turmas e setenta alunos do conjunto determinístico, dez alunos demo por turma e totais globais de sete turmas e setenta alunos. Na unidade antiga então implementada, o aluno smoke permaneceu vinculado ao Supabase Auth com `16` BinCoins, a turma smoke preservou `19` XP, e o depósito e o audit log preexistentes permaneceram únicos. A seed não criou depósitos, resgates, recompensas ou logs adicionais e não alterou usuários Auth, RLS, policies, migrations ou Edge Functions. O hosted smoke do Mobile executado após a aplicação foi aprovado: comprovou login e sessão válida, uma linha própria em `students`, sua turma e escola, invisibilidade dos outros 69 alunos sob RLS, preservação daqueles saldos históricos, restauração da sessão e logout.

O inventário estático do FastAPI identificou **21 operações sob `/v1`, além de `/health`**: cinco públicas, quatro de aluno com JWT próprio, cinco administrativas com JWT próprio e sete protegidas pela chave técnica da máquina. Ele também confirmou que o FastAPI ainda implementa regras e acessos que não foram integralmente migrados, não chama `register_deposit_v1` no fluxo de descarte e usa JWT próprio em vez de Supabase Auth. Esse inventário é a referência de paridade para a migração, não uma aprovação do FastAPI como arquitetura futura.

## Missões V1 — migrations `012–018` aplicadas no DEV

O contrato final de `missions-contract-v1.md` mantém definições/templates globais controlados centralmente pelo BinGo, mas associa cada ciclo histórico a exatamente uma escola. `STUDENT` e `CLASS` são os únicos escopos do primeiro slice. Não existe inscrição, adesão, tabela de participação nem cópia antecipada da missão por aluno ou turma. Para Missões, o aluno elegível pertence à escola do ciclo e possui `students.status = 'ACTIVE'`; `is_activated` não participa da elegibilidade. Turmas não possuem status próprio aprovado.

O progresso continua exclusivamente derivado de `deposits`: `STUDENT` conta descartes válidos do aluno e `CLASS` soma o `points_awarded_class` histórico da turma. O relógio V1 é `deposits.created_at`, sempre sob `starts_at <= created_at < ends_at`; não existe `occurred_at` ou contador autoritativo de progresso. `classes.points_class_balance` e a configuração atual de XP não são usados para reconstruir progresso. Uma conclusão pode ser materializada depois de `ends_at` quando os depósitos persistidos dentro do ciclo comprovarem historicamente que a meta foi atingida.

Cada definição e seu snapshot de ciclo possuem exatamente dois valores fixos: `reward_bincoins` e `reward_xp`, ambos não negativos e pelo menos um positivo, sem valores oficiais ainda definidos. Em missão `STUDENT`, BinCoins pertencem ao aluno e XP à turma atual dele no instante da materialização. Em missão `CLASS`, XP pertence à própria turma e o valor integral de BinCoins é destinado a cada aluno `ACTIVE` atualmente vinculado a ela. Os destinatários efetivos deverão ser persistidos no ledger e não serão recalculados após mudanças de turma.

A fundação estrutural está versionada localmente pelas migrations equivalentes `database/migrations/012_missions_v1_schema.sql` e `supabase/migrations/20260915120000_missions_v1_schema.sql`. Ela cria somente `mission_definitions`, `mission_cycles`, `mission_completions` e `mission_reward_applications`, além do índice parcial aprovado para progresso coletivo em `deposits`; não cria tabela de progresso ou participação. As quatro tabelas possuem constraints, FKs, unicidades de ciclo/conclusão/aplicação e RLS habilitada sem policies ou grants diretos para `anon`, `authenticated` ou `service_role`.

As migrations de Missões `012–018`, incluindo leitura autenticada, fila durável, processamento, retry e recuperação, estão versionadas nos dois trilhos e aplicadas no `bingo-dev`. O preflight somente leitura de `2026-09-21` confirmou as migrations Supabase de `20260915120000` a `20260918130000`, além das tabelas e índices correspondentes no banco hospedado. Não há evidência equivalente de produção. Criação automática de ciclos, CRUD Admin e valores reais provisionados continuam sujeitos aos limites dos contratos vigentes; esta atualização registra somente o estado técnico comprovado e não reabre decisões de produto.

## Jornada da Turma / BinGópolis V1 — implementada localmente

A Jornada é um domínio separado de Missões e está versionada localmente pelas migrations equivalentes `database/migrations/021_class_journey_v1.sql` e `supabase/migrations/20260922120000_class_journey_v1.sql`. Ela cria `journey_campaigns`, `journey_stages` e o ledger idempotente `journey_mission_contributions`, todos com RLS estrutural fechada. Percentual, total e estágio atual permanecem derivados.

A campanha H2/2026 usa `America/Sao_Paulo`, de `2026-07-01 00:00` até `2027-01-01 00:00` exclusivo. Os pesos fotografados são `1` por descarte válido, `3` por completion `STUDENT` e `5` por completion `CLASS`. Os targets sequenciais são Praça Central `20`, Parque das Nascentes `25` e Escola Criativa `30`, com carry-over integral.

Para a Jornada, uma completion `STUDENT` pertence à turma histórica do depósito válido que ocupa a posição `target` sob `ORDER BY deposits.created_at, deposits.id`; o `created_at` reconstruído deve coincidir com `mission_completions.achieved_at`. Essa regra não altera a economia: XP de Missão `STUDENT` continua destinado à turma atual do aluno na materialização. Completion `CLASS` usa sua `class_id` persistida. O trigger pós-insert captura novas completions sem modificar `process_mission_event_v1`, e o backfill interno reutiliza a mesma validação e idempotência.

A RPC `get_class_journey_v1()` não recebe identidade do cliente, deriva escola/turma por `auth.uid()`, é `STABLE`, `SECURITY DEFINER`, usa `search_path` vazio e concede execução somente a `authenticated`. O Mobile possui repository próprio e usa um único snapshot para Home, Ranking e mapa, sem fallback demo no modo autenticado. O mapa autenticado não simula avanço e o Impacto permanece indisponível porque não existe fonte aprovada para peso ou demais métricas ambientais.

O preflight remoto inicial permaneceu somente leitura e confirmou 20 migrations alinhadas no `bingo-dev`. A única completion histórica observada, `97f580c2-907d-489a-b276-6d99ab036c68`, foi reconstruída deterministicamente no target `1`: depósito `31125c80-819c-4e68-abed-61c311065abd`, evento `d234e61a-1cad-4905-af79-bed63b85e6c2`, turma `20000000-0000-4000-8000-000000000001`, `created_at = achieved_at = 2026-09-18 21:51:56.301564+00`. A promoção posterior aplicou a migration `021`, provisionou a campanha H2/2026 e materializou deterministicamente a contribuição `+3`; o preflight de BinBazar em `2026-09-22` confirmou 21 migrations remotas alinhadas e essa contribuição preservada.

O reset local, a suíte pgTAP completa e os testes Flutter validam schema, RPC, boundaries `19/20/21/44/45/74/75`, descarte anônimo, idempotência, backfill e as duas trocas de turma exigidas. A migration, campanha e backfill da Jornada estão comprovados no `bingo-dev`; nada disso declara aplicação em produção.

## Pendências e limites de comprovação

O BinBazar + Extrato V1 foi incorporado ao `develop` pelo PR #33, conforme `binbazar-statement-v1.md`. O preflight original confirmou `21` migrations alinhadas no repositório de partida, no banco local e no `bingo-dev`, além de `0 rewards`, `0 redemptions` e reconciliação exata do saldo smoke `3300 = 1600 + 1600 + 100`. A migration `022_binbazar_statement_v1.sql`, equivalente a `20260923120000_binbazar_statement_v1.sql`, adiciona snapshots, idempotência, cancelamento, catálogo, pedidos próprios e Extrato consolidado; as evidências disponíveis ainda não comprovam sua promoção ao DEV ou à produção. O cancelamento preserva `stock_qty = NULL` quando um produto reservado originalmente como finito se torna ilimitado e audita separadamente reserva histórica e incremento efetivo.

Em `2026-09-23`, o requisito foi corrigido: `redemptions.code` permanece `NOT NULL/UNIQUE`, e `request_redemption_v1` continua gerando e retornando o identificador interno `BGO-*` para preservação e futura integração Admin. Ele não é PIN, QR, código de retirada ou autenticação e não aparece em nenhuma interface Mobile, inclusive no piloto. Não houve mudança de schema ou RPC, a `022` permaneceu intacta e a proposta `023` foi descartada antes de promoção remota. “Seus pedidos” mostra somente `PENDING`; `DELIVERED` e `CANCELED` permanecem no backend e no Extrato. Reset com `22` migrations, `348` testes pgTAP, `2` provas PostgreSQL, `250` testes Flutter e análise estática passaram localmente na branch `fix/binbazar-pickup-flow`.

O contrato público conceitual continua sendo `POST /v1/deposits`, enquanto o roteamento nativo atualmente comprovado é `POST /functions/v1/register-deposit-v1`. Um alias no gateway poderá materializar o caminho conceitual no futuro, mas ainda não foi criado. Vinte e uma migrations estão comprovadas e alinhadas no `bingo-dev`, de `20260527120000_initial_schema.sql` a `20260922120000_class_journey_v1.sql`; a nova migration local de BinBazar/Extrato permanece pendente de promoção controlada e postflight no DEV. `register-deposit-v1` e `health-v1` foram observadas ativas no projeto, e a leitura autenticada da carteira na escala `×100` foi validada manualmente no Mobile já instalado; não houve nesta validação novo descarte ou resgate. Essas evidências do ambiente DEV não comprovam, isoladamente, todos os comportamentos dos contratos HTTP hospedados nem qualquer estado de produção.

O baseline abre as leituras de perfil, turma, escola, catálogo ambiental e histórico próprio de descartes implementadas no repositório. O Mobile consome perfil, turma, escola e histórico próprio; a leitura de Ranking V1 possui uma RPC dedicada aplicada no `bingo-dev` que não amplia a policy global de `classes`. Catálogo de produtos, resgates e Extrato agora possuem RPCs próprias no repositório, mas permanecem indisponíveis no DEV até a promoção controlada da migration `022`. A leitura do histórico de descartes possui validação manual hospedada somente no `bingo-dev`; não há comprovação equivalente de produção. O health central está implementado, mas sua política de consumo — polling, contadores, transições `ONLINE/OFFLINE` e endpoint `/local/status` — pertence ao futuro serviço local e não foi definida nem simulada nesta entrega. Não há SLO de 2 s/3 s nem cadência oficial fixada.

A integração com o Orange Pi está pendente porque o hardware e seu serviço local ainda não existem em condição de integração; atualmente há somente o Totem Web. Na versão física, a API key deverá ficar no serviço local controlado e jamais no frontend kiosk. A chave de demonstração serve apenas ao ambiente de desenvolvimento. Também permanecem pendentes regras futuras de ciclo de vida da credencial, como rotação mais elaborada, expiração e auditoria de tentativas, sem que isso invalide a revogação MVP por substituição ou remoção de `machines.api_key_hash`.

Em `2026-09-04`, estavam comprovadas no `bingo-dev` as nove migrations então existentes, de `20260527120000` a `20260815120000`. Posteriormente, `20260905120000_mobile_deposit_history_rls.sql` foi aplicada e validada no mesmo projeto; a listagem de migrations confirmou o estado local e remoto alinhado em dez migrations. Em `2026-09-14`, `20260913120000_points_unit_redenomination.sql` foi aplicada após preflight read-only compatível e quiescência sem queries longas, bloqueios ou locks concorrentes; a listagem final confirmou onze migrations alinhadas e o postflight econômico/auditorial foi aprovado. Em `2026-09-21`, novo preflight somente leitura comprovou que as migrations de Missões `20260915120000–20260918130000` e o Ranking `20260919120000` também estavam aplicados, alinhando local e remoto em dezenove migrations. Na mesma data, `20260921120000_get_student_profile_progress_v1.sql` foi promovida somente no DEV e o postflight alinhou a vigésima migration. Em `2026-09-22`, a Jornada foi promovida e o preflight posterior confirmou a vigésima primeira migration. As Edge Functions versionadas não foram alteradas nem reimplantadas. Todas essas evidências remotas se limitam ao projeto DEV `bingo-dev` e não constituem declaração sobre produção.

## Divergências históricas

Referências antigas a `size`, `SMALL/MEDIUM/LARGE`, `quantity`, novos descartes offline ou a uma Edge Function chamada `process_deposit` estão superadas. A posição atual é: tamanho e quantidade não fazem parte do contrato; novos ciclos offline são bloqueados; recuperação existe somente após conclusão física irreversível de um ciclo iniciado online; e a Function física se chama `register-deposit-v1`. Também há divergências transitórias entre FastAPI e a fundação Edge, como o uso de `strip()` pelo FastAPI e a possibilidade de `404` para máquina inexistente, enquanto a autenticação compartilhada Edge não aplica `trim()` deliberadamente e uniformiza credenciais inválidas em `401`. Essas diferenças devem ser tratadas como legado documentado, não copiadas automaticamente.

## Próximos passos

Para BinBazar/Extrato, o próximo passo eventual é um novo preflight somente leitura e a promoção controlada de `20260923120000_binbazar_statement_v1.sql` ao `bingo-dev`, seguida de postflight de grants, RPCs, geração e persistência do `code` interno `BGO-*`, catálogo, resgate, cancelamento, Extrato e saldo smoke; isso não faz parte desta entrega local. A futura integração Admin poderá consumir esse identificador, mas nenhuma interface Mobile deve exibi-lo. Para Missões, continuam pendentes criação automática de ciclos, CRUD de `BINGO_ADMIN` e valores reais adicionais. Em paralelo, permanecem a decisão sobre o alias público `POST /v1/deposits`, a integração do health ao futuro serviço local do Orange Pi e a migração controlada das 21 operações FastAPI. O FastAPI só poderá ser aposentado depois que a paridade funcional, de segurança e de testes estiver comprovada e nenhum cliente depender de suas rotas.
