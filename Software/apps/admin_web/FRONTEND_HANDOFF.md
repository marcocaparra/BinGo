# Admin Lite - Handoff do frontend

## Estado atual

O Admin Lite e uma aplicacao Angular demonstrativa baseada no contrato
`Software/docs/admin-contract-v1.md`.

O front representa tres perfis:

- `ADMIN_A`: visao global de escolas, administradores, Totens, missoes e
  economia;
- `ADMIN_B`: gestao da escola, alunos, turmas, equipe, pendencias e BinBazar;
- `ADMIN_C`: operacao escolar, consultas, solicitacoes, estoque, resgates e
  estado dos Totens.

A matriz de navegacao fica centralizada em `src/app/admin-access.ts`.

## O que funciona no prototipo

- acesso demonstrativo por perfil;
- dashboards diferentes por escopo;
- estados de carregamento, vazio e falha;
- formularios e confirmacoes de alunos, turmas, solicitacoes, produtos,
  administradores, escolas, missoes e economia;
- entrega e cancelamento demonstrativos de resgates;
- diagnostico visual dos Totens com ultima comunicacao;
- alteracoes em memoria durante a sessao;
- layout responsivo para tablet e larguras estreitas.

Todas as operacoes sao identificadas como `Dados demonstrativos`. Recarregar a
pagina restaura o estado inicial.

## Fronteira com o backend

O frontend controla apresentacao, validacao de campos, confirmacoes, feedback e
restricao visual de navegacao. O backend deve continuar responsavel por:

- autenticacao e sessao;
- autorizacao de cada leitura e mutacao;
- isolamento por escola;
- persistencia e paginacao;
- auditoria;
- concorrencia de estoque e resgates;
- estorno e entrega atomicos;
- telemetria e ultima comunicacao dos Totens.

Ocultar uma acao no front nao e autorizacao. Toda permissao deve ser validada
novamente pelo servidor.

## Validacao

```bash
npm install
npm run build
npm test
```

Na ultima validacao, o build Angular e seis testes Playwright passaram. A suite
cobre acesso, navegacao, estados, responsividade, permissoes por perfil e fluxos
demonstrativos de gestao escolar e global.

## Proxima etapa

Quando os endpoints e payloads estiverem definidos, substitua o estado local por
um adapter de dados sem transferir regras de autorizacao para o navegador. A
componentizacao por dominio pode evoluir junto dessa integracao, preservando a
matriz de acesso e os testes de comportamento atuais.

