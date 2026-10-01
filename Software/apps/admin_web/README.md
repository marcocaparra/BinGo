# BinGo Admin Lite

Aplicacao Angular do painel operacional do BinGo.

## Estado atual

- Angular 22 com bootstrap standalone e matriz de acesso tipada;
- Supabase Auth real para login, restauracao de sessao e logout;
- contexto proprio por `get_my_admin_context_v1()`, com role/escola/status do banco;
- ausencia de vinculo e INACTIVE bloqueiam o painel, sem fallback demo;
- layout e componentes preservados; alunos/turmas, trocas de turma e BinBazar operacional usam dados reais;
- perfis `ADMIN_A`, `ADMIN_B` e `ADMIN_C` alinhados ao contrato funcional V1;
- navegacao, dashboards e acoes demonstrativas adaptados ao escopo de cada perfil;
- formularios reais escolares e de estoque; administradores, escolas, missoes e economia continuam demonstrativos;
- entrega e cancelamento reais de resgates com confirmacao, auditoria e estorno transacional;
- criacao de produtos e edicao de preco bloqueadas ate existir teto global persistido;
- loading/empty/error/submitting reais nas telas conectadas; seletor de demonstracao somente nos outros dominios;
- matriz de acesso centralizada em `src/app/admin-access.ts`;

## Estrutura Angular

```text
src/app/
  app.ts                         gate da sessao administrativa
  admin-access.ts                contrato de navegacao A/B/C
  core/admin-store.ts            estado demonstrativo compartilhado
  core/admin-auth.service.ts     sessao administrativa e Supabase Auth
  core/admin-binbazar.repository.ts produtos/resgates reais da propria escola
  core/admin-context.ts          validacao do contexto retornado pela RPC
  core/supabase-client.ts        SDK e configuracao publica por ambiente
  layout/admin-shell.component.ts
  roles/admin-role-components.ts componentes Admin A, B e C
  features/                      componentes de cada dominio
  shared/                        cards, linhas, estados e dialogos
```

O shell, a navegacao e os estilos sao compartilhados. Cada componente de papel
monta somente os componentes permitidos pelo contrato. Nao existe mais um
renderer monolitico dentro do codigo Angular ativo.

As regras do front organizam a experiencia, mas nao substituem a autorizacao do backend. Toda consulta e operacao futura deve ser validada novamente pelo servidor, incluindo o vinculo de escola dos perfis `ADMIN_B` e `ADMIN_C`.

## Rodar localmente

```bash
npm ci
npm start
```

## Build

```bash
npm run build
```

Antes de iniciar, configure `public/supabase-config.json` (ignorado pelo Git) com
`SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY`; o exemplo tem chave vazia. Use somente
publishable/anon, nunca service_role ou credencial tecnica. O seletor de perfil
foi removido do login e do shell. Role/escola/status vêm somente da RPC propria.

Provisionamento local de usuarios Auth, migrations, comandos e testes estão em
[`docs/admin-supabase-auth-session.md`](../../docs/admin-supabase-auth-session.md).

```powershell
npm test
$env:BINGO_ADMIN_INTEGRATION = '1'
npm run test:integration
```

Os testes de browser exigem o dev server (porta 8106, ou `BINGO_ADMIN_URL`) e Edge
no Windows (`BINGO_BROWSER_PATH` pode indicar outro Chromium). A integracao real
e opt-in, somente local, e cria/remove fixtures pelo Auth local.

## Fronteira com o backend

O front controla navegacao, formularios, validacao de campos, confirmacoes e feedback visual. O backend continua responsavel por:

- autenticacao, papel administrativo e escopo da escola;
- autorizacao de cada consulta e mutacao;
- persistencia, paginacao e concorrencia;
- auditoria das decisoes administrativas;
- atomicidade entre estoque, estorno e entrega de resgates;
- telemetria e ultima comunicacao dos Totens.

Autenticacao, alunos/turmas, trocas de turma e BinBazar operacional estao integrados.
Overview e os outros dominios ainda usam `Dados demonstrativos`. Contratos, limites
de preco, concorrencia e reproducao local em [Admin BinBazar V1](../../docs/admin-binbazar-v1.md).
