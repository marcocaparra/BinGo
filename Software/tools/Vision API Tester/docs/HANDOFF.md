# Vision API Tester - Relatorio tecnico de transicao

Data da auditoria: 2026-07-15
Workspace auditado: `C:\Users\Predeus\Documents\Vision API Tester`

Este documento resume o estado real do projeto para que outro desenvolvedor possa assumir o trabalho sem depender do historico de conversas anteriores.

## Resumo executivo

O projeto possui duas partes principais:

- `frontend/`: SPA em Vite + React + TypeScript, com CSS global simples e dados mockados.
- `backend/`: API Java Spring Boot com PostgreSQL, Flyway, JPA e upload local de imagens.

O frontend esta funcional como prototipo mockado. Ele nao consome o backend ainda.

O backend compila e tem testes unitarios passando, mas a inicializacao real da aplicacao contra PostgreSQL nao ficou funcional no ambiente auditado por conflito na porta local `5432`. O container Docker do PostgreSQL sobe, e as credenciais funcionam dentro do container, mas o Spring Boot falha ao conectar via `localhost:5432` porque existe tambem um PostgreSQL local ouvindo na mesma porta.

Nao ha integracao real com AWS Rekognition, Google Cloud Vision ou qualquer API externa.

## Estado do repositorio

### Git

Problema encontrado:

```text
git status --short
fatal: not a git repository (or any of the parent directories): .git
```

Existe uma entrada `.git/` na raiz, mas ela esta vazia. Portanto, o workspace atual nao esta operando como um repositorio Git valido.

Impacto:

- Nao ha historico de commits verificavel.
- Nao ha baseline confiavel para diff.
- Nao ha protecao contra arquivos gerados como `frontend/node_modules`, `frontend/dist` ou `backend/target`, exceto `.gitignore` local do backend.

Recomendacao imediata:

1. Recriar ou restaurar o repositorio Git.
2. Adicionar `.gitignore` na raiz.
3. Garantir que `node_modules/`, `dist/`, `target/`, arquivos locais de storage e caches nao sejam versionados.

## Estrutura atual

```text
Vision API Tester/
  backend/
    compose.yaml
    pom.xml
    README.md
    src/main/java/com/visiontester/backend/
      api/
      api/dto/
      config/
      domain/
      repository/
      service/
    src/main/resources/
      application.yaml
      db/migration/V1__init_schema.sql
    src/test/java/...
  frontend/
    package.json
    vite.config.ts
    index.html
    src/
      App.tsx
      main.tsx
      styles.css
      components/
      data/mockData.ts
      pages/
  docs/
    HANDOFF.md
  database/
  scripts/
  storage/
```

`database/`, `scripts/` e `storage/` existem, mas nao contem logica relevante versionada no momento da auditoria.

## Frontend

### Stack

Confirmado em `frontend/package.json`:

- Vite
- React 19
- React DOM 19
- TypeScript
- CSS global unico em `src/styles.css`

Scripts:

```json
{
  "dev": "vite --host 0.0.0.0",
  "build": "tsc -b && vite build",
  "preview": "vite preview --host 0.0.0.0"
}
```

### Organizacao

Rotas internas implementadas em `frontend/src/App.tsx`:

- `/` redireciona via `history.replaceState` para `/dashboard`
- `/dashboard`
- `/new-test`
- `/history`

Nao ha `react-router`. A navegacao e manual, controlada por estado React e History API.

Componentes principais:

- `Navbar`
- `MetricCard`
- `DashboardSection`
- `ProviderResultCard`
- `ImageUploadPreview`
- `EvaluationForm`
- `HistoryTable`

Paginas:

- `DashboardPage`
- `NewTestPage`
- `HistoryPage`

Dados mockados:

- `frontend/src/data/mockData.ts`
- Inclui providers, metricas, historico, classes esperadas, resultados de avaliacao, labels e `rawResponse` JSON mockado por provider.

### Funcionalidade implementada

Dashboard:

- Cards de metricas mockadas.
- Secoes de resumo, desempenho por provider, desempenho por classe, erros comuns e ultimos testes.
- Nao consome API real.

Novo Teste:

- Upload local apenas para preview via `URL.createObjectURL`.
- Selecao de providers via checkboxes.
- Botao `Executar teste` renderiza resultados mockados.
- Cada provider exibe:
  - labels resumidas;
  - confianca;
  - tempo de resposta mockado;
  - JSON completo mockado da resposta.
- Formulario de avaliacao humana por provider.
- `Salvar avaliacao` apenas altera estado visual temporariamente; nao persiste.

Historico:

- Renderiza tabela com dados mockados.
- Filtros visuais por provider, resultado e classe.
- Filtros ainda nao aplicam logica.

### Verificacoes feitas

Comando executado:

```powershell
cd frontend
npm run build
```

Resultado:

```text
BUILD SUCCESS / vite build concluido
40 modules transformed
```

Tambem foi verificado:

```powershell
Invoke-WebRequest -UseBasicParsing http://localhost:5173/dashboard
```

Resultado:

```text
StatusCode: 200
```

Porta `5173` estava ocupada por processo Node:

```text
TCP 0.0.0.0:5173 LISTENING PID 7848
PID 7848: node.exe
```

### Problemas e lacunas do frontend

- Nao ha integracao com backend.
- Nao ha camada de API client.
- Upload nao envia arquivo ao backend.
- Resultados mockados nao sao persistidos.
- Avaliacoes humanas nao sao persistidas.
- Dashboard nao consome metricas reais.
- Historico nao consome dados reais.
- Filtros do Historico sao apenas visuais.
- Nao ha testes automatizados de frontend.
- Nao ha lint configurado.
- Nao ha tratamento de estados de erro/loading de API.
- Nao ha selecao/criacao real de projeto no frontend.
- Deploy/producao: NAO VERIFICADO.

## Backend

### Stack

Confirmado em `backend/pom.xml`:

- Java configurado: 21
- Spring Boot: 4.1.0
- Spring WebMVC
- Spring Data JPA
- Spring Validation
- Spring Actuator
- Flyway
- PostgreSQL driver
- Jackson Databind

Observacao: nos logs de execucao, o Maven/Spring rodou com Java `24.0.2`, apesar do `pom.xml` declarar `java.version=21`. Isso nao quebrou a compilacao, mas deve ser padronizado.

### Configuracao

Arquivo: `backend/src/main/resources/application.yaml`

Valores padrao:

```yaml
DB_URL: jdbc:postgresql://localhost:5432/vision_api_tester
DB_USERNAME: vision_api_tester
DB_PASSWORD: vision_api_tester
SERVER_PORT: 8080
STORAGE_ROOT: ../storage/uploads
CORS_ALLOWED_ORIGINS: http://localhost:5173,http://127.0.0.1:5173
```

JPA:

- `ddl-auto: validate`
- `open-in-view: false`

Flyway:

- habilitado
- migration inicial em `V1__init_schema.sql`

Multipart:

- max file size: `20MB`
- max request size: `25MB`

### Docker Compose

Arquivo: `backend/compose.yaml`

Servico:

- `postgres:16-alpine`
- container: `vision-api-tester-postgres`
- database: `vision_api_tester`
- user: `vision_api_tester`
- password: `vision_api_tester`
- porta publicada: `5432:5432`
- volume nomeado: `vision-api-tester-postgres-data`

Verificacao:

```powershell
docker compose config
```

Resultado: sucesso.

```powershell
docker compose up -d
```

Resultado: container ficou `Running`.

Consulta dentro do container:

```powershell
docker exec -e PGPASSWORD=vision_api_tester vision-api-tester-postgres psql -U vision_api_tester -d vision_api_tester -c "select current_user, current_database();"
```

Resultado:

```text
current_user: vision_api_tester
current_database: vision_api_tester
```

### Banco de dados

Migration inicial cria:

- `projects`
- `images`
- `provider_runs`
- `provider_labels`
- `human_evaluations`

Relacionamentos:

- `images.project_id -> projects.id`
- `provider_runs.image_id -> images.id`
- `provider_labels.provider_run_id -> provider_runs.id`
- `human_evaluations.provider_run_id -> provider_runs.id`, unico

`provider_runs.raw_response` e `JSONB`.

### Dominio backend

Pacote `domain/`:

- `Project`
- `ImageAsset`
- `ProviderRun`
- `ProviderLabel`
- `HumanEvaluation`
- `ExpectedClass`
- `EvaluationResult`
- `ProviderRunStatus`

### Repositorios

Pacote `repository/`:

- `ProjectRepository`
- `ImageAssetRepository`
- `ProviderRunRepository`
- `HumanEvaluationRepository`

Inclui consultas para:

- historico por imagem/projeto;
- contagens de imagens e execucoes;
- media de tempo de resposta;
- sumarizacao por provider;
- sumarizacao por classe esperada.

### Servicos

Pacote `service/`:

- `ProjectService`: cria/lista projetos.
- `ImageStorageService`: valida imagem, salva arquivo local, calcula SHA-256, extrai dimensoes com `ImageIO`, persiste metadados.
- `ProviderResultService`: salva resposta mockada/manualizada de provider, labels e `rawResponse`.
- `EvaluationService`: cria/atualiza avaliacao humana por `providerRun`.
- `HistoryService`: monta historico com provider results e avaliacao.
- `DashboardService`: monta metricas agregadas.
- `DtoMapper`: converte entidades para DTOs.

### Controllers / endpoints

Confirmado por anotacoes em `backend/src/main/java/com/visiontester/backend/api`:

```text
GET  /api/health
GET  /api/projects
POST /api/projects
POST /api/images
POST /api/provider-results
GET  /api/provider-results?imageId={uuid}
PUT  /api/provider-results/{providerRunId}/evaluation
GET  /api/history
GET  /api/dashboard
```

### Upload local

Endpoint:

```text
POST /api/images
Content-Type: multipart/form-data
fields:
  projectId: UUID
  file: imagem
```

Storage:

```text
../storage/uploads/{year}/{month}/{uuid}.{ext}
```

Metadados persistidos:

- nome original;
- nome armazenado;
- caminho;
- content type;
- tamanho;
- SHA-256;
- largura;
- altura;
- data de criacao.

### Verificacoes feitas no backend

Comandos:

```powershell
cd backend
.\mvnw.cmd test
```

Resultado:

```text
Tests run: 1, Failures: 0, Errors: 0, Skipped: 0
BUILD SUCCESS
```

Comando:

```powershell
.\mvnw.cmd -DskipTests package
```

Resultado:

```text
BUILD SUCCESS
target/backend-0.0.1-SNAPSHOT.jar gerado
```

Importante: o teste atual e muito raso. Ele apenas instancia `BackendApplication`; nao sobe contexto Spring, nao valida Flyway, nao valida JPA, nao valida controllers.

### Erro real de inicializacao encontrado

Comando:

```powershell
.\mvnw.cmd spring-boot:run
```

Resultado: falha no boot.

Erro principal:

```text
Unable to obtain connection from database:
FATAL: autenticacao do tipo senha falhou para o usuario "vision_api_tester"
```

Investigacao:

Container Docker esta rodando e aceita as credenciais internamente.

Porem, no host ha conflito na porta `5432`:

```text
PID 9512: com.docker.backend.exe
PID 7096: postgres
ambos ouvindo em 0.0.0.0:5432 / [::]:5432
```

Ou seja:

- o container publica `5432`;
- ha tambem um PostgreSQL local do host ouvindo em `5432`;
- o backend, ao conectar em `localhost:5432`, aparenta atingir o PostgreSQL local ou uma rota ambigua, nao o container esperado.

Tentativa alternativa:

```powershell
DB_URL=jdbc:postgresql://172.18.0.2:5432/vision_api_tester
```

Resultado:

```text
SQL State 08001
Connect timed out
```

Conclusao: o backend nao foi validado em runtime com Flyway/API no ambiente atual. O bloqueio e ambiental/rede/porta, nao de compilacao.

## O que esta funcionando

Confirmado:

- Frontend compila com `npm run build`.
- Frontend responde `200` em `http://localhost:5173/dashboard` quando servidor Vite esta ativo.
- Frontend renderiza SPA com rotas internas e dados mockados.
- Backend compila.
- Backend empacota jar.
- Teste unitario atual passa.
- `docker compose config` e valido.
- Container PostgreSQL sobe.
- Banco dentro do container aceita `vision_api_tester/vision_api_tester`.
- Migration Flyway existe e define o schema inicial.

## O que esta incompleto

- Integracao frontend-backend.
- Fluxo real de upload no frontend chamando `POST /api/images`.
- Criacao/selecao de projeto no frontend.
- Envio de resultados mockados do frontend para `POST /api/provider-results`.
- Persistencia real da avaliacao humana pelo frontend.
- Dashboard real consumindo `GET /api/dashboard`.
- Historico real consumindo `GET /api/history`.
- Filtros reais no frontend e/ou backend.
- Servir/download/preview de imagens armazenadas pelo backend.
- Testes de integracao com banco.
- Testes de controllers.
- Testes de frontend.
- Documentacao OpenAPI/Swagger.
- Pipeline de CI.
- Dockerfile da aplicacao backend.
- Compose incluindo backend + frontend.
- Controle de autenticacao/usuarios.
- Integracao real com AWS Rekognition ou Google Cloud Vision.

## Decisoes tecnicas ja tomadas

- Frontend mantido simples, sem `react-router`, usando History API manual.
- Frontend usa mock centralizado em `src/data/mockData.ts`.
- CSS global unico em vez de CSS Modules/Tailwind/component library.
- Backend usa Spring Boot 4.1.0 e Java 21 configurado.
- Banco modelado em PostgreSQL com Flyway como fonte da verdade.
- JPA configurado com `ddl-auto: validate`; schema nao deve ser criado por Hibernate.
- Upload salva arquivo no filesystem local e metadados no banco.
- `raw_response` do provider e persistido como `JSONB`.
- O backend aceita resultados mockados/manualizados; nao chama APIs externas.
- CORS liberado para Vite local (`localhost:5173` e `127.0.0.1:5173`).
- Docker Compose atual sobe apenas PostgreSQL.

## Problemas conhecidos

1. Repositorio Git invalido

`git status` falha porque `.git/` esta vazio.

2. Backend nao inicializa no ambiente auditado

Causa observada: conflito entre PostgreSQL local e Docker na porta `5432`.

3. Teste backend nao cobre contexto real

`mvn test` passa, mas nao garante que:

- Flyway aplica migrations;
- entidades batem com schema;
- controllers respondem;
- upload funciona;
- metricas funcionam.

4. Dependencias geradas existem no workspace

Foram observados:

- `frontend/node_modules`
- `frontend/dist`
- `backend/target`

Sem `.gitignore` na raiz, isso pode virar sujeira de versionamento quando Git for restaurado.

5. Runtime Java diferente da configuracao

O projeto declara Java 21, mas os logs indicaram Java 24.0.2 durante `spring-boot:run`.

6. Backend runtime contra banco correto

NÃO VERIFICADO por causa do conflito de porta/conexao descrito.

7. Upload real via HTTP

NÃO VERIFICADO. O codigo existe, mas o backend nao iniciou no ambiente atual.

8. Flyway aplicando migration no banco

NÃO VERIFICADO. O backend falhou antes de aplicar/confirmar migration.

## Como executar localmente

### Frontend

```powershell
cd frontend
npm install
npm run dev
```

Abrir:

```text
http://localhost:5173/dashboard
```

Build:

```powershell
npm run build
```

### Backend

Pre-requisitos:

- Java 21 recomendado.
- Docker Desktop aberto, se for usar o PostgreSQL do compose.
- Porta `5432` livre, ou ajustar porta/DB_URL.

Subir banco:

```powershell
cd backend
docker compose up -d
```

Rodar backend:

```powershell
.\mvnw.cmd spring-boot:run
```

Se houver PostgreSQL local em `5432`, ha duas opcoes:

1. Parar o PostgreSQL local antes de usar o compose.
2. Alterar `compose.yaml` para publicar outra porta, por exemplo `55432:5432`, e rodar:

```powershell
$env:DB_URL="jdbc:postgresql://localhost:55432/vision_api_tester"
.\mvnw.cmd spring-boot:run
```

Esta segunda opcao ainda precisa ser aplicada e verificada.

## Sequencia recomendada para o proximo desenvolvedor

1. Restaurar Git

- Corrigir `.git`.
- Criar `.gitignore` na raiz.
- Commitar estado atual limpo.

2. Resolver conflito de PostgreSQL

- Decidir se o projeto usara PostgreSQL local ou Docker.
- Se Docker, mudar publish para porta livre (`55432:5432`) ou parar PostgreSQL local.
- Validar `.\mvnw.cmd spring-boot:run`.
- Confirmar `GET /api/health`.
- Confirmar se Flyway criou tabelas.

3. Criar testes backend reais

- Teste de contexto com banco de teste.
- Teste de migration.
- Teste de upload multipart.
- Teste de salvar provider result.
- Teste de salvar evaluation.
- Teste de dashboard/history.

4. Criar cliente API no frontend

- `src/api/client.ts` ou equivalente.
- Configurar `VITE_API_BASE_URL`.
- Mapear DTOs backend em TypeScript.

5. Conectar fluxo Novo Teste

- Criar/selecionar projeto.
- Enviar imagem real para `/api/images`.
- Enviar resultados mockados para `/api/provider-results`.
- Enviar avaliacao para `/api/provider-results/{id}/evaluation`.

6. Conectar Dashboard e Historico

- Substituir mocks por chamadas reais.
- Manter fallback/loading/error states.
- Implementar filtros reais.

7. Melhorar contrato da API

- Adicionar OpenAPI/Swagger.
- Padronizar erros.
- Documentar exemplos completos.

8. Preparar infraestrutura

- Dockerfile backend.
- Compose completo para backend + postgres, e possivelmente frontend.
- CI para `npm run build` e `mvn test`.

## Comandos executados nesta auditoria

```powershell
rg --files -g '!frontend/node_modules/**' -g '!frontend/dist/**' -g '!backend/target/**'
git status --short
npm run build
.\mvnw.cmd test
.\mvnw.cmd -DskipTests package
docker compose config
docker compose up -d
docker compose ps
docker exec -e PGPASSWORD=vision_api_tester vision-api-tester-postgres psql -U vision_api_tester -d vision_api_tester -c "select current_user, current_database();"
.\mvnw.cmd spring-boot:run
Invoke-WebRequest -UseBasicParsing http://localhost:5173/dashboard
Invoke-WebRequest -UseBasicParsing http://localhost:8080/api/health
netstat -ano | findstr :5432
netstat -ano | findstr :5173
```

## Status final

- Frontend: funcional como prototipo mockado e buildado com sucesso.
- Backend: implementado e compilando, mas runtime com PostgreSQL ainda bloqueado por conflito local de porta/conexao.
- Banco Docker: container sobe e credenciais funcionam internamente.
- Integracao frontend-backend: ainda nao existe.
- Proxima prioridade: resolver porta/DB_URL do PostgreSQL e validar o backend com Flyway + health endpoint.
