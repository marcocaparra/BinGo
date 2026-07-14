# Diário de Bordo Coletivo do BinGo

Ferramenta interna para registrar, consultar e acompanhar as atividades diárias dos integrantes do BinGo. Esta frente é isolada do produto principal: não compartilha código, banco ou configuração com o backend do totem.

## Estado Atual

Esta branch já possui a base funcional do V0:

| Frente | Estado | Onde olhar |
|---|---:|---|
| Backend | Spring Boot com controllers, service, repository, DTOs e tratamento de erro | `backend/src/main/java/com/bingo/diario` |
| Autenticação | PIN coletivo/admin por variáveis de ambiente | `AuthController`, `AuthService`, `.env.example` |
| Banco | Migrations e seeds próprias do Diário | `database/migrations` e `database/seeds` |
| Frontend | React/Vite com login, relatório do dia, histórico e exportação | `frontend/src` |
| Documentação técnica | Arquitetura, contrato, modelo e fluxo | `docs/` |

## Escopo Da V0

- acesso por PIN coletivo e PIN admin;
- seleção de integrante ativo;
- criação/atualização do relatório do dia;
- registro de atividade, ausência de atividade, pendências e evidências por link;
- consulta de histórico e relatórios;
- base para exportação dos registros.

Upload de arquivos e integração com o produto principal continuam fora desta etapa.

## Tecnologias

- Java 21;
- Spring Boot e Maven Wrapper;
- Spring Web MVC;
- Spring Data JPA;
- Bean Validation;
- PostgreSQL;
- React + Vite + TypeScript.

## Estrutura

```text
diario-bordo/
|-- backend/   # API Spring Boot
|-- database/  # migrations SQL e seeds
|-- docs/      # arquitetura e contratos
|-- frontend/  # app React/Vite
`-- README.md
```

## Documentação

- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/database-model.md)
- [Contrato da API](docs/api-contract.md)
- [Fluxo do frontend](docs/frontend-flow.md)

## Configuração

Use `.env.example` como referência. As credenciais reais não devem ser versionadas.

Variáveis principais:

```text
DATABASE_URL=jdbc:postgresql://host:5432/database
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=change_me
DIARY_TEAM_PIN=2610
DIARY_ADMIN_PIN=6262
CORS_ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173,http://[::1]:5173
```

## Executar Backend

A partir de `backend/`:

```powershell
.\mvnw.cmd spring-boot:run
```

Rodar testes:

```powershell
.\mvnw.cmd test
```

## Executar Frontend

A partir de `frontend/`:

```powershell
npm install
npm run dev
```

Build:

```powershell
npm run build
```

## Onde Mexer

| Se você vai mexer em... | Comece por |
|---|---|
| Rotas HTTP | `backend/src/main/java/com/bingo/diario/controller` |
| Regras de relatório | `backend/src/main/java/com/bingo/diario/service/DailyReportService.java` |
| Autenticação | `backend/src/main/java/com/bingo/diario/service/AuthService.java` |
| Modelo e persistência | `backend/src/main/java/com/bingo/diario/model` e `repository` |
| Contratos frontend/backend | `frontend/src/types` e `frontend/src/api` |
| Telas | `frontend/src/pages` |
| Banco | `database/migrations` e `database/seeds` |
