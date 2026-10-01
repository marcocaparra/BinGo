# Admin Totens V1 — leitura

Contrato técnico aprovado nesta fatia, a partir das permissões funcionais de
`admin-contract-v1.md`. Implementação validada somente no ambiente local.

## Fronteira e autorização

`get_admin_machines_v1()` não recebe parâmetros. Resolve o administrador por
`auth.uid() → admins.auth_user_id` e exige `ACTIVE`. ADMIN_A consulta todas as
máquinas; ADMIN_B/C consultam somente a própria escola. Ausência de vínculo,
ausência de sessão e administrador inativo são recusados com SQLSTATE `42501`
e `ADMIN_MACHINES_ACCESS_DENIED`.

Retorna `machine_id`, `school_id`, `school_name`, `name`, `status`,
`firmware_version`, `last_seen`, `bin_full`, `camera_ok` e `net_ok`.
`school_name` vem do join por `machines.school_id = schools.id`. A ordenação é
nome da escola, nome da máquina e UUID da máquina. Firmware e última comunicação
preservam NULL. Não retorna hash ou credencial.

A migration 030 existe nos dois trilhos:

- `database/migrations/030_admin_machines_v1.sql`;
- `supabase/migrations/20261001150000_admin_machines_v1.sql`.

A RPC é STABLE, SECURITY DEFINER e tem `search_path = ''`. EXECUTE é concedido
somente a `authenticated`, revogado de PUBLIC/anon/service_role. Não há novos
grants de tabela nem policies: `machines` continua RLS fail-closed. A leitura
técnica mínima usada por machine-auth e as RPCs server-only da 029 permanecem
inalteradas. A 030 **não foi promovida ao `bingo-dev`**.

## Fotografia persistida

Os quatro status são exibidos como armazenados: ONLINE, OFFLINE, MAINTENANCE e
OUT_OF_SERVICE. `last_seen` não produz status calculado. Câmera/rede representam
flags persistidas, e `bin_full` representa o compartimento registrado. Não há
garantia de atualização desses sinais, heartbeat, polling, timeout, SLO ou
diagnóstico operacional criado nesta fatia.

## Angular

`AdminMachinesRepository` concentra a leitura e os estados loading/loaded/error.
Cada entrada na tela e atualização manual busca uma nova fotografia. Uma lista
vazia tem estado explícito; erros nunca usam mocks. Mudança de contexto remove
os dados anteriores e invalida respostas atrasadas, inclusive após logout/login.

Totens usa UUID como chave interna, mostra escola, status e os campos permitidos,
com estados explícitos para NULL. Foram removidos `AdminStore.machines`, códigos
BT, porta, depósitos do dia e o diálogo de diagnóstico fictício. Outros domínios
conscientemente demonstrativos, inclusive Ajuda, permanecem fora desta fatia.

## Validação local

pgTAP cobre escopo A/B/C, recusas, retorno exato, NULL, os quatro status, RLS,
grants e preservação da autenticação técnica. Testes browser cobrem os campos,
estados, refetch, responsividade e resposta atrasada após troca de sessão.
O smoke com Supabase Auth/RPC/Angular local usa identidades efêmeras e confirma
leitura global/escolar, ausência de hash e bloqueio de inativo/sem vínculo.
