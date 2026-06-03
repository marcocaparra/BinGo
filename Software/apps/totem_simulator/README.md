# Relatorio Tecnico - BinGo Totem Simulator

Data da analise: 02/06/2026

## Sumario executivo

O projeto BinGo esta organizado como um MVP com backend FastAPI, banco Postgres/Supabase, app mobile Flutter inicial e um `totem_simulator` web em HTML/CSS/JS puro. O backend ja modela varias regras importantes do V1: autenticacao tecnica da maquina, deposito idempotente, pontuacao por aluno/turma, limite antifarm para itens pequenos, rankings, resgates, Admin Lite e status operacional de maquinas.

O ponto mais importante da analise e este: o `totem_simulator` nao deve ser tratado como uma tela administrativa de testes. Ele precisa simular o totem fisico real do projeto. Hoje ele cumpre bem o papel de testar a API de deposito, mas ainda nao reproduz o fluxo kiosk definido no produto: idle, escolha de acao, login por segmento/serie/turma/nome/PIN, pular login, depositar, processar, resultado, resgate, timeouts, falhas fisicas, modo offline e estados de manutencao.

Em outras palavras: o simulador esta tecnicamente util, mas conceitualmente incompleto como simulador do totem real.

## Mapa da arquitetura atual

```text
apps/totem_simulator
  index.html + style.css + app.js
  - roda como site estatico local
  - chama a API real em http://localhost:8000/v1
  - envia X-Machine-Id e X-Api-Key
  - registra depositos em POST /v1/deposits
  - consulta contexto, aluno e rankings em /v1/totem/*

backend FastAPI
  app/api/routes
    auth.py, deposits.py, totem.py, machines.py, rewards.py, redemptions.py, admin.py
  domain
    regras de negocio por area
  infra/db
    modelos SQLAlchemy
  Postgres/Supabase
    escolas, turmas, alunos, maquinas, depositos, recompensas, resgates, auditoria

mobile/bingo_app
  Flutter inicial
  foco esperado para V1: consulta, nao resgate
```

## O que o simulador faz bem hoje

- Usa a API real do backend, nao banco direto no navegador. Isso esta documentado em `apps/totem_simulator/README.md` e implementado em `apps/totem_simulator/app.js`.
- Autentica como maquina/edge usando `X-Machine-Id` e `X-Api-Key`, alinhado com `backend/src/app/api/dependencies.py` e `backend/src/domain/machines/service.py`.
- Registra depositos reais via `POST /v1/deposits`, usando `event_id` com `crypto.randomUUID()`, o que conversa com a idempotencia do backend.
- Atualiza contexto, rankings e resumo do aluno apos cada deposito, permitindo validar rapidamente se a regra de pontos esta funcionando.
- O backend tem boas bases para o totem real: `/v1/totem/context`, `/v1/totem/students/{student_id}/summary`, `/v1/totem/rankings`, `/v1/deposits`, `/v1/deposits/sync` e `/v1/machines/heartbeat`.
- A modelagem de maquina ja inclui `last_seen`, `bin_full`, `camera_ok`, `net_ok`, `status` e `api_key_hash`, que sao campos importantes para um totem fisico em producao.

## Lacuna central: simulador ainda nao representa o totem fisico

Pelo documento de produto, o Totem V1 precisa operar como kiosk autonomo em escola, com descarte completo em menos de 45s, fila offline, fluxo sem celular, login opcional, resgate somente no totem, feedback claro, timeouts agressivos e estados de falha.

Hoje, o `totem_simulator` representa apenas um formulario de deposito:

- escolhe aluno direto em um select;
- escolhe tamanho manualmente;
- escolhe validade manualmente;
- escolhe tipo detectado manualmente;
- envia o deposito;
- mostra resumo, historico e rankings.

Isso e bom para testar backend, mas nao simula o comportamento do aluno diante do totem fisico. O fluxo real deveria parecer com:

```text
Idle
  -> Descartar ou Resgatar ou Ajuda
  -> Entrar ou Pular login
  -> Segmento
  -> Serie
  -> Turma
  -> Nome + PIN, se logado
  -> Instrucoes de deposito
  -> Processando
  -> Resultado: aceito/devolvido + pontos
  -> Timeout e reset para Idle
```

## Problemas e riscos

### P1 - O simulador permite selecionar resultado de visao manualmente

No arquivo `apps/totem_simulator/index.html`, os campos `item-size`, `item-validity` e `detected-type` deixam o operador escolher o resultado final da classificacao. Isso e aceitavel como ferramenta de debug, mas nao como simulacao fiel do totem.

Impacto: a experiencia nao testa estados de captura, analise, fallback offline, devolucao fisica, nem mapeamento tipo -> tamanho. O time pode achar que o fluxo do totem esta validado quando, na pratica, apenas o endpoint de deposito foi exercitado.

Recomendacao: separar modo "debug" de modo "kiosk". No modo kiosk, a tela deve simular camera/IA/edge como etapas do fluxo, mesmo que internamente ainda use dados mockados.

### P1 - Falta fluxo de login real do totem

O produto definiu login por Segmento -> Serie -> Turma -> Nome -> PIN, com possibilidade de pular login para pontuar somente a turma. Hoje o simulador escolhe o aluno diretamente em uma lista.

Impacto: nao valida a principal interacao do aluno no totem. Tambem nao testa PIN, ativacao, busca por nome, scroll, teclado numerico, pular login ou expiracao de sessao.

Recomendacao: transformar o simulador em uma maquina de estados de tela, usando o fluxo real. O select direto de aluno pode continuar apenas como atalho de desenvolvedor.

### P1 - Nao ha simulacao offline-first

O backend tem `/v1/deposits/sync` e idempotencia por `event_id`, que sao bons sinais para fila offline. Mas o simulador depende de `fetch` direto para `localhost:8000` e, quando a API cai, so mostra erro.

Impacto: nao valida uma regra essencial do V1: o totem nao pode parar se a internet cair. O contexto diz explicitamente que offline significa evento pendente e sincronizacao posterior.

Recomendacao: adicionar uma fila local no simulador, usando `localStorage` ou `IndexedDB`, com estados `pending`, `synced` e `failed`. O simulador deve permitir alternar "online/offline" e sincronizar quando a API voltar.

### P1 - Nao ha estados fisicos do totem

O backend modela heartbeat, camera_ok, net_ok, bin_full e status de maquina, mas o simulador nao expoe isso como experiencia.

Impacto: nao testa "Fora de Servico", cesto cheio, camera indisponivel, falha de rede, manutencao nem travamento da entrada. Esses estados sao essenciais para o totem fisico.

Recomendacao: criar um painel discreto de simulacao de hardware para desenvolvedor e estados visuais de kiosk para o usuario final. Exemplo: camera falhou -> tela "Fora de servico"; internet offline -> aviso discreto e fila ativa.

### P2 - Chave tecnica exposta no frontend

`apps/totem_simulator/app.js` contem `MACHINE_API_KEY = "edge-demo-key"`. O README deixa claro que isso e apenas para desenvolvimento e que no totem real a chave deve ficar protegida no Edge/Orange Pi.

Impacto: baixo no simulador local, alto se esse padrao vazar para uma versao real. Uma credencial de maquina em frontend publico permite forjar depositos.

Recomendacao: manter essa exposicao apenas no simulador local. Para o totem fisico, a UI kiosk deve conversar com um servico local do Edge, e esse servico local deve assinar/chamar a API remota.

### P2 - O simulator mistura tela do aluno com painel de consulta

As abas "Aluno" e "Rankings" sao uteis para desenvolvedor, mas nao correspondem necessariamente ao fluxo principal do totem. O totem real precisa priorizar rapidez, fila, botoes grandes, cancelar/voltar e reset automatico.

Impacto: o simulador pode induzir decisoes de UX erradas, parecendo um dashboard em vez de uma experiencia de corredor escolar.

Recomendacao: manter visualizacao de aluno/ranking em modo debug ou em telas reais do produto quando fizer sentido, mas a primeira tela do simulador deve ser o Idle/Home do totem.

### P2 - Divergencia de stack e direcao tecnica

O `STATUS.md` diz que o backend-alvo atual e Supabase/Postgres + Edge Functions Deno/TypeScript, e que o FastAPI precisa migrar. O repositorio, por outro lado, contem um backend FastAPI bem estruturado e testado.

Impacto: risco de retrabalho. Se o time continuar evoluindo regras em FastAPI enquanto a decisao travada e migrar para Supabase Edge Functions, a distancia entre implementacao e stack-alvo aumenta.

Recomendacao: decidir explicitamente se o FastAPI e prototipo descartavel, backend temporario de bancada ou base real do V1. Se for temporario, o relatorio de migracao deve mapear endpoints, regras e testes para Edge Functions.

## Pontos fortes do backend para reaproveitar

- Depositos idempotentes por `event_id`, evitando pontuacao duplicada em retry.
- Pontuacao separada de aluno e turma.
- Regra de item pequeno com limite diario por aluno.
- Deposito sem aluno permitindo pontuar turma, alinhado ao "pular login".
- Rotas especificas para contexto do totem e rankings.
- Autenticacao tecnica de maquina por headers.
- Auditoria para acoes sensiveis.
- Entidades de resgate e entrega por admin ja existem.
- Testes cobrindo CORS, deposito, idempotencia, antifarm, contexto do totem, rankings e resumo de aluno.

## Prioridades recomendadas para o Totem Simulator

1. Renomear mentalmente o objetivo: de "formulario de teste de deposito" para "simulador do totem fisico".
2. Criar modo kiosk como fluxo principal, deixando modo debug separado.
3. Implementar maquina de estados de telas: Idle, Escolha de acao, Login/Pular, Deposito, Processando, Resultado, Resgate, Ajuda, Fora de Servico.
4. Simular login real: segmento, serie, turma, nome, PIN.
5. Implementar timeouts e reset de sessao.
6. Simular offline com fila local e sincronizacao em `/v1/deposits/sync`.
7. Simular hardware: camera, rede, cesto cheio, manutencao e heartbeat.
8. Adicionar fluxo de resgate no totem, usando as rotas de recompensas/resgates ja existentes.
9. Trocar selecao manual de tamanho/validade por uma etapa de "classificacao simulada", com modo debug para forcar casos.
10. Documentar no README a diferenca entre "modo kiosk" e "modo debug".

## Conclusao

O projeto esta mais avancado no backend do que na simulacao do totem. A camada FastAPI ja concentra varias regras corretas para o V1, mas o `totem_simulator` ainda valida principalmente a API, nao a experiencia fisica. Para o produto BinGo, isso e uma diferenca grande: o totem e a interface principal do aluno, nao um detalhe auxiliar.

Minha recomendacao e evoluir o `totem_simulator` como prototipo operacional do totem fisico real. Ele deve continuar usando a API real, mas precisa passar a representar o comportamento de kiosk, o fluxo do aluno, as falhas de hardware, o offline-first e o resgate. Assim ele vira uma ferramenta de produto e engenharia: serve para testar backend, validar UX com o time e ensaiar o comportamento do Orange Pi/Arduino antes do hardware estar completo.


# Totem Simulator

O Totem Simulator é uma interface web simples para simular o fluxo inicial de descarte do totem BinGo.

Esta versão usa a API real do backend BinGo para carregar alunos, turmas, rankings e registrar depósitos. Ela continua sem frameworks no frontend e não acessa banco de dados ou Supabase diretamente pelo navegador.

## Como abrir localmente

Para o passo a passo completo de iniciar o Supabase local, subir o backend e conferir a seed 008, veja `../../docs/iniciar-supabase-local.md`.

Antes de abrir o simulador, deixe o backend rodando em `http://localhost:8000` e aplique as migrations mais a seed:

```powershell
database/seeds/008_seed_totem_simulator_rich_demo.sql
```

Depois sirva os arquivos estáticos:

```powershell
cd apps/totem_simulator
python -m http.server 8001
```

Abra no navegador:

```text
http://localhost:8001
```

Não existe etapa de build ou instalação de dependências para o frontend.

## Páginas disponíveis

- **Simulador de descarte**: permite escolher um aluno vindo da API, tamanho do item, validade e tipo detectado. O descarte é enviado para `POST /v1/deposits`.
- **Informações do aluno**: consulta `GET /v1/totem/students/{student_id}/summary` e mostra saldo, turma, estatísticas e histórico recente.
- **Rankings**: consulta `GET /v1/totem/rankings` e exibe alunos e turmas do maior para o menor saldo.

## Dados de desenvolvimento

O simulador espera a escola criada pela seed `008_seed_totem_simulator_rich_demo.sql`:

- Escola Demo BinGo
- Turmas: 6º Ano A, 7º Ano A, 8º Ano A, 9º Ano A, 1ª Série A, 2ª Série A e 3ª Série A
- Alunos demo: 70 alunos com PIN individual de 4 digitos
- Máquina demo: Totem Demo 01
- API key demo: `edge-demo-key`

No `app.js`, a configuração padrão é:

```js
const API_BASE_URL = "http://localhost:8000/v1";
const MACHINE_ID = "40000000-0000-4000-8000-000000000001";
const MACHINE_API_KEY = "edge-demo-key";
```

A chave fica no frontend apenas porque este é um simulador de desenvolvimento. No totem real, ela deve ficar protegida no serviço local do Edge/Orange Pi.

## Próximo passo futuro

Evoluir o simulador para representar melhor o fluxo físico do totem, mantendo a integração com o backend real para registrar depósitos e atualizar saldos reais.
