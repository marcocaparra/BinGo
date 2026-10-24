# Admin — auditoria dos dados demonstrativos restantes

Atualização documental: `2026-10-23`.

## Estado consolidado após a migration 031

A pendência de leitura administrativa de **Descartes foi resolvida** pelo
[contrato Admin Descartes V1](admin-deposits-v1.md) e pelas migrations equivalentes
`database/migrations/031_admin_deposits_v1.sql` e
`supabase/migrations/20261001160000_admin_deposits_v1.sql`. A tela consome a RPC
`get_admin_deposits_v1()` com escopo A global/B/C escolar e snapshots persistidos.
`AdminStore.deposits`, `discardStats` e os cards agregados fictícios foram removidos.
Não foi implementada uma leitura de estatísticas agregadas.

Missões, Economia ampliada e Ajuda continuam demonstrativas e pendentes dos
contratos descritos abaixo. O teto real do BinBazar permanece integrado.
Essas pendências não impedem a entrega delimitada de Descartes reais.

## Registro histórico anterior à implementação de Descartes

**Todo o registro abaixo, inclusive o inventário e a validação das seções 1–6,
descreve o preflight até a migration 030 em 01/10/2026.** A classificação de
Descartes como bloqueado, as referências aos seus mocks e a indicação de 030 como
última migration são históricas, superadas pela 031. Os resultados aprovados
abaixo não representam reexecução em 23/10/2026; a validação atual está registrada
em [Admin Descartes V1](admin-deposits-v1.md).

Data: 2026-10-01. Branch: `feature/admin-real-data-cleanup`.
Preflight documental, migrations até 030, catálogo do banco local e consumidores
Angular. Nenhuma consulta ou alteração remota.

## Resultado por domínio no preflight até 030

| Domínio                                   | Classificação                        | Motivo                                                                                                                                                              |
| ----------------------------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Descartes                                 | BLOQUEADO POR CONTRATO               | Não existe interface técnica de leitura administrativa aprovada. A policy da 010 é histórico próprio do aluno.                                                      |
| Missões                                   | BLOQUEADO POR CONTRATO               | Leitura existente resolve aluno; processamento/recovery são técnicos. Faltam leituras Admin e contratos de administração de definições/ciclos.                      |
| Economia — teto BinBazar                  | IMPLEMENTÁVEL AGORA, já implementado | Consulta/atualização da 027 e repository real permanecem intactos.                                                                                                  |
| Economia — demais controles               | BLOQUEADO POR CONTRATO               | Base/XP/meta semanal são escolares, bônus por categoria é global; não há contratos de leitura/mutation Admin desses controles. Há divergência de escopo a resolver. |
| Solicitações de ajuda                     | BLOQUEADO POR CONTRATO               | Não existe domínio backend oficial, tabela, interface ou ciclo de vida aprovado. Somente preflight.                                                                 |
| Limpeza de código/textos sem consumidores | IMPLEMENTÁVEL AGORA                  | Remoção de metadados fictícios mortos, helpers mortos e correção de textos que confundiam áreas reais e demo.                                                       |

As áreas reais permanecem: Auth/contexto, Overview, Escolas, Administradores,
Alunos/Turmas, Trocas/Pendências, Produtos/Resgates, teto global e Totens. Nenhuma
nova fonte real foi criada nesta auditoria. Nenhuma migration/RPC/grant/policy foi
criada ou alterada. A última migration continua 030, ainda somente local conforme
o registro vigente; esta auditoria não promoveu migrations ao `bingo-dev`.

## 1. Descartes

Evidências: [modelo](database-model.md), [Admin](admin-contract-v1.md),
[dashboard](admin-dashboard-v1.md), migrations 005/010/011/029.
`deposits` possui event_id único, school/machine/class, student opcional,
is_valid, detected_type, waste_category_id, category_source, created_at e
snapshots bonus_rate_applied/bonus_bincoins_awarded/points_awarded_student/
points_awarded_class. Não possui estado administrativo de revisão.

A 010 permite somente histórico do próprio aluno por Auth/RLS. Resumo Totem da
029 é server-only, autenticado tecnicamente por máquina; não é leitura Admin.
As leituras de saldo/alunos e o Extrato da 022 também não autorizam uma listagem
escolar de descartes. Não foram reutilizadas essas fronteiras.

Contrato mínimo a aprovar, sem nome de RPC inventado:

- operação versionada de leitura Admin, assinatura, campos e erros;
- autorização B/C ACTIVE na própria escola e decisão explícita sobre A global;
- identidade/escola server-side, sem parâmetros de autoridade e sem SELECT direto;
- identidade/instante/validade do evento, aluno opcional, turma histórica gravada
  em deposits.class_id, categoria/origem e snapshots econômicos existentes;
- nomes obtidos por join não devem ser apresentados como snapshots imutáveis;
- ordenação/paginação e filtros; se houver métricas total/hoje/semana, definir
  universo, período/timezone e agregação, sem derivar totais de uma página parcial.

Não recalcular BinCoins/XP pelo valor-base ou taxa atual. `AdminStore.deposits`
e `discardStats` continuam consumidos por DepositsComponent e explicitamente demo.

## 2. Missões

Evidências: [contrato Missões](missions-contract-v1.md), STATUS e migrations
012–018. Definições são globais; cada ciclo pertence a uma escola, com snapshot
de período/meta/recompensas. Completions e aplicações econômicas são histórico.
`get_active_missions_v1()` resolve **aluno ACTIVE**, sua escola/turma e progresso
individual/coletivo. Não é leitura de administrador, mesmo tendo EXECUTE para
authenticated. As operações de processamento/retry/recovery não são Admin CRUD.

O texto inicial do contrato ainda descreve runtime pendente e papel legado
BINGO_ADMIN. O STATUS posterior registra leitura/processamento/recovery
implementados. Para permissões administrativas canônicas prevalece o contrato
Admin A/B/C; não foi inferida conversão de papel legado nem ausência do runtime.

Faltam contratos separados para:

- leitura A de definições globais e ciclos; leitura B/C dos ciclos relacionados
  à própria escola, com retorno e visibilidade temporal definidos;
- criação/edição/inativação de definições por A, com regras que preservem ciclos;
- criação de ciclos por A, escola alvo explicitamente autorizada, períodos,
  recorrência, snapshot congelado, idempotência e auditoria;
- eventual consulta administrativa de completions/processamento, com escopo e
  dados necessários definidos, sem conceder ao browser execução técnica.

A leitura pode ser aprovada separadamente do CRUD. Não é necessário reimplementar
o motor. Geração automática de ciclos e métrica ENVIRONMENTAL_IMPACT continuam
sujeitas às decisões pendentes do domínio. `AdminStore.missions` e seus diálogos
continuam somente demonstração local, sem criar registros backend.

## 3. Economia

Evidências: [Admin](admin-contract-v1.md), [modelo](database-model.md),
[teto global](binbazar-global-price-cap-v1.md), [BinBazar Admin](admin-binbazar-v1.md)
e [BinBazar/Extrato](binbazar-statement-v1.md).

- `school_settings.deposit_bincoins_base`, `deposit_class_xp_base` e
  `class_weekly_xp_goal`: valores persistidos por escola.
- `waste_categories.bonus_rate`: taxa **por categoria** no catálogo global;
  leitura pública existente não é uma mutation administrativa autorizada.
- `global_economic_settings.binbazar_max_price`: única configuração global
  econômica integrada nesta etapa, com RPCs reais da 027.
- `Meta territorial = 8 descartes` do mock não equivale à meta semanal de XP,
  meta de Missão ou snapshot dos setores da Jornada.

Conflito: Admin descreve A administrando bases/metas do BinGo, enquanto o modelo
vigente mantém base/XP/meta semanal por escola. A 027 deliberadamente não
globalizou esses campos. É necessário decidir se A gerencia valores escolares,
defaults globais ou uma futura regra global, sua precedência e eventuais overrides.
Não foi escolhida nenhuma dessas alternativas nesta tarefa.

Depois dessa decisão, aprovar interfaces de leitura/mutation, campos/unidades,
validação, autorização, lock, no-op e auditoria. Bônus requer contrato específico
por categoria, não multiplicador único. Toda alteração deve preservar snapshots
de eventos anteriores. O teto real permanece integrado; os três cards de
`economySettings` e o diálogo genérico ficam explicitamente demonstrativos.

## 4. Ajuda — somente preflight

Não há tabela/RPC oficial de Ajuda nas migrations até 030 ou no catálogo local.
Pedidos AJ-*, lugares, prioridades, tipos/motivos, estados e tempos de
`helpRequests` são exclusivamente mock. HelpComponent usa filtros/ações em memória
e o shell mostra contador demo apenas fora do Overview, dentro da funcionalidade
demonstrativa existente. Nenhuma estrutura ou comportamento backend foi criado.

Contrato mínimo: quem solicita e por qual fronteira (Totem/aluno/outro ator),
escopo da escola/máquina, dados necessários, identidade dos operadores, ciclo de
vida/transições, concorrência/idempotência, auditoria e política de histórico.
Prioridade, tipo e estados devem ser decididos, não copiados dos mocks.

## 5. Inventário e limpeza

| Fonte conservada                                   | Consumidores                                  | Por que permanece                |
| -------------------------------------------------- | --------------------------------------------- | -------------------------------- |
| deposits: quatro eventos fictícios                 | DepositsComponent                             | Sem substituição real autorizada |
| discardStats: total/hoje/semana                    | DepositsComponent                             | Sem contrato de agregação        |
| missions: duas missões                             | MissionsComponent, diálogo/submit demo        | Sem interface Admin              |
| economySettings: três controles                    | EconomyComponent, diálogo/submit demo         | Escopo e mutations pendentes     |
| helpRequests: três pedidos                         | HelpComponent, filtros, ações e contador demo | Sem domínio backend              |
| scenario/loading/empty/error, toast e diálogo demo | Domínios anteriores                           | Infraestrutura ainda utilizada   |

Removidos: scope/operatorName/operatorInitials fictícios sem consumidores em
admin-access; role redundante sem consumidores em AdminStore; chave de operação
e helpers key/clean/viewOnly mortos do diálogo demo após integrações anteriores.
Matriz de acesso e identidade derivada do contexto real não foram alteradas.

Corrigidos: escola fixa ENIAC na tela de acesso, aviso antigo de que todas as
outras telas eram demo e anúncio genérico de sistema operacional. A UI identifica
modo demo/sessão autenticada/somente leitura e explicita bloqueios de Descartes,
Missões e demais controles econômicos. Não houve alteração funcional em Ajuda.

O Overview continua sem consumir mocks. Diálogos demonstrativos, seus avisos e
seletor de cenário foram preservados porque têm consumidores legítimos.

## 6. Validação local histórica — 01/10/2026, antes da 031

| Verificação                           | Resultado final                                            |
| ------------------------------------- | ---------------------------------------------------------- |
| Supabase db reset --local             | Passou, migrations até 030 e seeds existentes              |
| pgTAP completo                        | 629 verificações / 23 arquivos, passou                     |
| backend pytest                        | 178 passaram, sem skips; 13 avisos JWT legados             |
| npm test                              | 104 passaram, sem skips; 10 testes novos de auditoria demo |
| npm run test:integration              | 8 passaram, Auth/RPC/Angular reais exclusivamente locais   |
| npm run build                         | Passou                                                     |
| npx tsc --noEmit -p tsconfig.app.json | Passou                                                     |
| Prettier nos arquivos alterados       | Passou                                                     |
| git diff --check                      | Passou                                                     |

O reset e pgTAP usaram o CLI Supabase instalado no repositório via Node.
Backend executado com `.venv/Scripts/python.exe -m pytest backend/tests -q -rs`,
`PYTHONPATH=backend/src` e bancos de RPC/migrations apontando para
`127.0.0.1:54322`. Integração opt-in com `BINGO_ADMIN_INTEGRATION=1`; browser
usa o dev server local em :8106. Nenhum teste hospedado foi executado.

Os novos testes verificam identidade real A/B/C, ausência de escola/operador
fictícios nas áreas reais, marcação demo e isolamento das chamadas em Descartes,
Missões, Economia e Ajuda. Preservam cenário/diálogo demo onde ainda necessário
e a leitura real do teto. Não testam interfaces backend inexistentes.

As primeiras execuções encontraram interferência entre pgTAP/backend executados
simultaneamente no banco compartilhado, comparação CRLF/LF no teste preexistente
de equivalência da 030 e texto exato do aviso de Economia alterado. As suítes de
banco foram repetidas em sequência; o teste compara o SQL completo normalizando
somente quebras de linha; o aviso mantém o texto existente e acrescenta a lacuna
separadamente. Nenhum assert foi removido ou substituído por verificação vazia.
As repetições finais passaram.

Não há integração nova para os quatro domínios bloqueados, pois isso exigiria
inventar contratos. A regressão cobre as oito fatias reais existentes.
Nenhum commit, push, PR, merge, deploy ou ação remota foi executado.
