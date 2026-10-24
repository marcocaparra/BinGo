# BinGo Admin Lite

Aplicacao Angular do painel operacional do BinGo.

## Estado atual

- Angular 22 com bootstrap standalone e matriz de acesso tipada;
- Supabase Auth real para login, restauracao de sessao e logout;
- contexto proprio por `get_my_admin_context_v1()`, com role/escola/status do banco;
- ausencia de vinculo e INACTIVE bloqueiam o painel, sem fallback demo;
- layout e componentes preservados; alunos/turmas, trocas de turma e BinBazar operacional usam dados reais;
- perfis `ADMIN_A`, `ADMIN_B` e `ADMIN_C` alinhados ao contrato funcional V1;
- dashboard A/B/C somente leitura, composto de repositories reais, sem fallback demonstrativo;
- Totens somente leitura por `get_admin_machines_v1()`: A global, B/C escola, fotografia persistida sem heartbeat ou diagnostico calculado;
- formularios reais de escolas, identidades administrativas, alunos/turmas e produtos; missoes e demais regras economicas continuam demonstrativos;
- entrega e cancelamento reais de resgates com confirmacao, auditoria e estorno transacional;
- teto global real configurado por ADMIN_A; B/C criam produtos e editam preco conforme validacao server-side; teto inicial NULL bloqueia somente criacao/preco;
- loading/empty/error/submitting reais nas telas conectadas; seletor de demonstracao somente nos outros dominios;
- matriz de acesso centralizada em `src/app/admin-access.ts`;

## Estrutura Angular

```text
src/app/
  app.ts                         gate da sessao administrativa
  admin-access.ts                contrato de navegacao A/B/C
  core/admin-store.ts            estado demonstrativo dos dominios ainda nao integrados
  core/admin-auth.service.ts     sessao administrativa e Supabase Auth
  core/admin-dashboard.repository.ts composicao das fontes reais por papel, sem backend novo
  core/admin-structure.repository.ts escolas/identidades reais; sem provisionar Auth
  core/admin-binbazar.repository.ts produtos/resgates reais da propria escola
  core/binbazar-price-cap.repository.ts teto global real, leitura A/B/C e edicao A
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

`npm run build` executa primeiro `scripts/generate-supabase-config.cjs` via
`prebuild`. Quando as duas variáveis de ambiente existem, o script valida URL
http/https e chave pública e gera `public/supabase-config.json`, mantendo o
contrato de leitura atual do frontend. A chave deve ser `sb_publishable_*` ou
JWT com role `anon`; chaves `service_role`, `sb_secret_*`, JWT sem assinatura e
formatos inválidos são recusados sem imprimir a chave completa nos logs.
Configuração parcial ou vazia falha antes do build. Localmente, sem variáveis
de ambiente, um arquivo existente válido é preservado sem reescrita; sem arquivo
válido o build falha. O arquivo gerado permanece ignorado pelo Git.

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

## Preparação para deploy no Vercel

Esta configuração prepara o deploy; não comprova que o Admin foi deployado.
A aplicação continua sendo uma SPA Angular estática, conectada diretamente a
Supabase Auth e RPCs/RLS. Não existem API Routes, backend Node ou funções
serverless intermediárias nesta entrega.

Configure o projeto Vercel com:

| Campo            | Valor                                    |
| ---------------- | ---------------------------------------- |
| Root Directory   | `Software/apps/admin_web`                |
| Install Command  | `npm ci`                                 |
| Build Command    | `npm run build`                          |
| Output Directory | `dist/admin_web/browser`                 |
| Node.js          | `24.x` (validado localmente com 24.19.0) |

O diretório de saída foi confirmado pelo build Angular 22 real: os arquivos
estáticos publicáveis, incluindo `index.html` e `supabase-config.json`, ficam em
`dist/admin_web/browser`, dentro do diretório base anunciado pelo CLI.

Defina no ambiente de build Vercel:

- `SUPABASE_URL`: URL http/https do projeto Supabase hospedado escolhido;
- `SUPABASE_PUBLISHABLE_KEY`: chave pública publishable ou JWT `anon` desse projeto.

Com `VERCEL=1`, o gerador exige as duas variáveis e falha fechado se estiverem
ausentes, mesmo que um arquivo local válido já exista. Não versione uma
configuração real nem coloque **service_role, secret key ou outra credencial
privilegiada** nessas variáveis ou no frontend. Publishable/anon é pública e
aparece no asset servido ao browser; não concede acesso administrativo por si.
A autorização real continua em Supabase Auth, contexto administrativo, RLS e
validação server-side de cada RPC. A validação do gerador verifica tipo/formato
da chave; a autenticação e verificação de tokens permanecem no Supabase.

`vercel.json` fixa o output e usa rewrite de SPA para `index.html`, permitindo
refresh direto de uma rota sem 404 de hospedagem. Arquivos existentes são
servidos antes do rewrite, preservando bundles, CSS, imagens e configuração
pública, conforme a [documentação Vercel](https://vercel.com/docs/project-configuration/vercel-json#rewrites).
O roteamento funcional Angular permanece inalterado.

Preview e Production poderão apontar para projetos Supabase diferentes, definindo
essas variáveis por ambiente Vercel. Cada build deve usar URL e chave do mesmo
projeto; a seleção de ambiente não altera roles ou escopo de escola.

Os testes do gerador integram `npm test` e também podem rodar isoladamente com
`node --test supabase_config.test.cjs`, sem chamadas ao Supabase.

## Fronteira com o backend

O front controla navegacao, formularios, validacao de campos, confirmacoes e feedback visual. O backend continua responsavel por:

- autenticacao, papel administrativo e escopo da escola;
- autorizacao de cada consulta e mutacao;
- persistencia, paginacao e concorrencia;
- auditoria das decisoes administrativas;
- atomicidade entre estoque, estorno e entrega de resgates;
- persistencia dos sinais e ultima comunicacao dos Totens; a leitura nao garante telemetria atualizada.

Autenticacao, escolas/identidades administrativas, alunos/turmas, trocas de turma, BinBazar operacional e teto global estao integrados.
Overview, Totens e Descartes usam somente fontes reais; Ajuda, Missoes e outras regras economicas continuam demonstrativos. Totens exibe status/flags persistidos, com firmware e ultima comunicacao explicitamente ausentes quando NULL. Descartes exibe eventos e snapshots economicos persistidos, sem recalculo ou estatisticas agregadas; as migrations 030 e 031 ainda nao foram promovidas ao bingo-dev. Confira [Totens leitura V1](../../docs/admin-totems-v1.md), [Descartes V1](../../docs/admin-deposits-v1.md) e [Dashboard real V1](../../docs/admin-dashboard-v1.md). Criar identidade administrativa nao cria usuario Auth, senha ou convite; confira [Estrutura Admin V1](../../docs/admin-structure-management-v1.md). Contratos, limites
de preco, concorrencia e reproducao local em [Admin BinBazar V1](../../docs/admin-binbazar-v1.md) e [Teto global V1](../../docs/binbazar-global-price-cap-v1.md).

## Domínios ainda demonstrativos

A [auditoria dos dados demonstrativos](../../docs/admin-real-data-audit-v1.md)
classifica Missões, Ajuda e os demais controles econômicos como
**BLOQUEADO POR CONTRATO**. Descartes deixou essa lista após a aprovação do
contrato e passou a usar a RPC específica da migration 031. Em Economia,
o escopo global do contrato Admin também precisa ser conciliado com os valores
persistidos por escola; bônus por categoria não equivale ao multiplicador demo.

Os dados, diálogos e seletor de cenário dos domínios ainda bloqueados continuam explicitamente
demonstrativos e operam somente em memória. Não são fallback das áreas reais,
não modificam o backend e não aparecem no Overview. O teto do BinBazar permanece
real. A auditoria removeu apenas metadados fictícios e helpers sem consumidores,
sem criar migration, RPC, policy ou regra de negócio.
