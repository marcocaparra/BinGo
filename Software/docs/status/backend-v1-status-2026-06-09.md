# Estado do Backend BinGo V1 - 2026-06-09

Este documento separa o backend V1 do legado e registra o que existe hoje no repositorio.

## Evidencia rapida

- Branch local atual: `develop`, limpa e alinhada com `origin/develop`.
- Remoto: https://github.com/marcocaparra/BinGo.git
- Branch atual no GitHub: https://github.com/marcocaparra/BinGo/tree/develop
- PR backend V1: https://github.com/marcocaparra/BinGo/pull/2 (`feature/backend-v1`)
- PR fluxo de descarte/Totem: https://github.com/marcocaparra/BinGo/pull/3 (`feature/deposit-flow-v0`)
- PR Supabase/Auth prep: https://github.com/marcocaparra/BinGo/pull/4 (`feature/database-supabase-auth`)
- Teste local executado em 2026-06-09: `cd backend && python -m pytest`
- Resultado: `19 passed`; avisos apenas de JWT secret curto em teste/dev e cache do pytest.

Observacao: os links de PR acima vem dos merge commits presentes em `develop`: `Merge pull request #2`, `#3` e `#4`.

## O que esta pronto

- Backend FastAPI V1 em `backend/`, versionado em `develop` via PR #2.
- Rotas V1 registradas sob `/v1`: auth, `/me`, rewards, redemptions, deposits, machines, admin e totem.
- Banco V1 modelado em SQL e nos models SQLAlchemy.
- Migrations Postgres locais em `database/migrations/`.
- Migrations equivalentes para Supabase local em `supabase/migrations/`.
- Seeds locais em `database/seeds/`, incluindo seed demo para o fluxo de descarte.
- Autenticacao por PIN do aluno para o fluxo atual de Totem/backend.
- Login admin por e-mail/senha no backend.
- Credencial tecnica de maquina por `X-Machine-Id` e `X-Api-Key`.
- Registro de descartes idempotente por `event_id`.
- Calculo e atualizacao de saldo do aluno e saldo da turma.
- Regra antifraude inicial para itens pequenos por limite diario.
- Resgate transacional com saldo, estoque, limite diario, limite de pendentes, codigo e expiracao.
- Entrega de resgate por admin.
- Auditoria para acoes sensiveis.
- Endpoints de Admin Lite no backend.
- Integracao real do simulador de Totem com a API local.
- Preparacao de Supabase Auth no schema via `students.auth_user_id`.

## O que esta em andamento

- Supabase esta preparado localmente, mas ainda nao aparece como ambiente remoto/produtivo configurado neste repositorio.
- Autenticacao do app via Supabase Auth esta documentada e preparada no banco, mas nao implementada no app mobile.
- Admin Lite tem endpoints de backend, mas nao ha interface web `admin_web` implementada em `apps/`.
- Integracao com App tem endpoints de consulta no backend (`/v1/me/*`), mas o app Flutter ainda e tela V0/placeholder.
- Integracao com Totem existe como simulador web local; o Totem fisico/Edge real ainda nao aparece implementado neste repo.

## O que esta pendente

- Implementar login real do app mobile com Supabase Auth.
- Vincular usuarios Supabase Auth a `students.auth_user_id` em fluxo real.
- Definir e aplicar RLS no Supabase.
- Popular `supabase/seed.sql`; hoje ele existe, mas esta vazio.
- Criar ou confirmar um projeto Supabase remoto/dev compartilhado para o time.
- Aplicar as migrations de `supabase/migrations/` no projeto Supabase remoto.
- Definir se `students.auth_user_id` tera FK real para `auth.users(id)` ou se o vinculo ficara logico na aplicacao.
- Criar o fluxo real de cadastro/login do aluno no Supabase Auth e gravar o `auth.users.id` no aluno correto.
- Definir politicas de RLS para leitura do proprio perfil, saldo, historico de descartes, historico de resgates e recompensas ativas.
- Criar UI Admin Lite ou conectar uma UI existente aos endpoints.
- Conectar app mobile aos endpoints `/v1/me/profile`, `/v1/me/deposits`, `/v1/me/redemptions` e `/v1/rewards`.
- Validar backend contra Postgres/Supabase real em ambiente compartilhado, alem dos testes SQLite locais.
- Formalizar secrets de producao: `BINGO_JWT_SECRET`, credenciais de maquina e credenciais admin.

## Pendencias especificas de Supabase

O Supabase ja esta preparado no schema local, mas ainda nao esta operacional como ambiente remoto com Auth, seguranca e dados compartilhados. As etapas pendentes sao:

- Ambiente remoto: criar ou confirmar o projeto Supabase de dev/staging que sera usado pelo time.
- Migrations remotas: aplicar `supabase/migrations/` no projeto Supabase remoto.
- Seeds: preencher `supabase/seed.sql` ou definir outra estrategia oficial de carga inicial/demo.
- Supabase Auth no app: implementar login por e-mail/senha no app mobile usando Supabase Auth.
- Vinculo Auth/dominio: gravar o ID de `auth.users` em `students.auth_user_id` durante o fluxo real de ativacao/cadastro.
- FK para Auth: decidir se havera foreign key real de `students.auth_user_id` para `auth.users(id)` no Supabase ou se o vinculo sera mantido apenas pela aplicacao.
- RLS: criar politicas para garantir que aluno leia apenas seus proprios dados e que escritas sensiveis continuem passando pelo backend/funcoes controladas.
- Validacao integrada: testar o backend contra Postgres/Supabase real, nao apenas SQLite local.
- Secrets: formalizar `BINGO_JWT_SECRET`, credenciais de maquina e credenciais admin fora do repositorio.

## Fora do V1

Conforme `docs/database-model.md`, ficam fora do V1:

- Armazenamento de imagens.
- Missoes avancadas.
- Marketplace.
- Multiplos tipos complexos de recompensa.
- Relatorios analiticos avancados.

## Separacao V1 vs legado

- O backend ativo neste repo e o FastAPI V1 em `backend/`.
- O historico registra remocao do backend legado.
- Nao ha pasta de backend legado presente na arvore atual.
- O mobile e o simulador sao V0/V1 de cliente, mas nao devem ser confundidos com backend antigo.
