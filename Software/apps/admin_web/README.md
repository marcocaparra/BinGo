# BinGo Admin Lite

Aplicacao Angular do painel operacional do BinGo.

## Estado atual

- Angular 22 com bootstrap standalone e matriz de acesso tipada;
- interface, copy e estados demonstrativos preservados da versao aprovada;
- perfis `ADMIN_A`, `ADMIN_B` e `ADMIN_C` alinhados ao contrato funcional V1;
- navegacao, dashboards e acoes demonstrativas adaptados ao escopo de cada perfil;
- formularios demonstrativos para alunos, turmas, solicitacoes, produtos, administradores, escolas, missoes e economia;
- entrega e cancelamento demonstrativos de resgates, com confirmacao explicita;
- estados de carregamento, vazio e falha disponiveis pelo seletor de demonstracao;
- matriz de acesso centralizada em `src/app/admin-access.ts`;

## Estrutura Angular

```text
src/app/
  app.ts                         index e troca do perfil autenticado
  admin-access.ts                contrato de navegacao A/B/C
  core/admin-store.ts            estado demonstrativo compartilhado
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
npm install
npm start
```

## Build

```bash
npm run build
```

O seletor de perfil existe somente para demonstracao. Na integracao real, o papel e o escopo da escola devem vir da sessao autenticada.

## Fronteira com o backend

O front controla navegacao, formularios, validacao de campos, confirmacoes e feedback visual. O backend continua responsavel por:

- autenticacao, papel administrativo e escopo da escola;
- autorizacao de cada consulta e mutacao;
- persistencia, paginacao e concorrencia;
- auditoria das decisoes administrativas;
- atomicidade entre estoque, estorno e entrega de resgates;
- telemetria e ultima comunicacao dos Totens.

Enquanto a integracao nao existe, todas as alteracoes ficam apenas na memoria da pagina e sao identificadas como `Dados demonstrativos`.
