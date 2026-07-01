# Organização do GitHub — BinGo

## Objetivo

Este documento define o padrão oficial de organização do repositório do BinGo.

Seu objetivo é manter o desenvolvimento organizado, facilitar revisões de código, evitar conflitos entre integrantes e permitir que qualquer pessoa compreenda rapidamente como o projeto está estruturado.

Este documento descreve:

- organização das branches;
- fluxo de desenvolvimento;
- padrão de commits;
- Pull Requests;
- estrutura do repositório;
- boas práticas.

## Estrutura de branches

O projeto utiliza uma estratégia simples baseada em uma branch principal de desenvolvimento.

```text
main
│
└── develop
    │
    ├── feature/backend-v1
    ├── feature/mobile-v0
    ├── feature/admin-auth
    ├── feature/database-seeds
    ├── fix/login-pin
    ├── docs/backend-status
```

Cada branch possui um objetivo específico.

### `main`

Representa a versão estável do projeto.

Características:

- somente código aprovado;
- nunca desenvolver diretamente nela;
- utilizada para releases;
- histórico limpo.

### `develop`

É a branch principal de desenvolvimento.

Todo novo trabalho deve partir dela.

Fluxo:

```text
develop
   ↓
feature
   ↓
Pull Request
   ↓
develop
```

## Tipos de branch

### `feature/`

Utilizada para novas funcionalidades.

Exemplos:

- `feature/backend-v1`
- `feature/mobile-dashboard`
- `feature/admin-lite`
- `feature/database-v2`

### `fix/`

Utilizada para correções.

Exemplos:

- `fix/login-pin`
- `fix/deposit-validation`
- `fix/student-search`

### `docs/`

Utilizada exclusivamente para alterações em documentação.

Exemplos:

- `docs/backend-status`
- `docs/github-workflow`
- `docs/database-contract`

### `hotfix/`

Utilizada para correções urgentes em produção.

Exemplos:

- `hotfix/api-crash`
- `hotfix/auth-error`

## Fluxo de desenvolvimento

Todo desenvolvimento segue o fluxo abaixo:

```text
develop
   ↓
criar nova branch
   ↓
desenvolver
   ↓
commits
   ↓
push
   ↓
Pull Request
   ↓
revisão
   ↓
merge em develop
```

> **Importante:** nunca desenvolver diretamente na branch `develop`.

## Commits

Os commits devem ser pequenos e representar uma única alteração lógica.

Exemplos:

```text
feat: implement student PIN authentication
feat: add reward redemption endpoint
fix: correct login validation
fix: prevent duplicate deposits
docs: update backend status
refactor: simplify deposit service
test: add deposit integration tests
```

Evitar commits como:

```text
update
alterações
teste
aaaa
corrigindo
```

## Pull Requests

Todo código deve entrar através de Pull Request.

O PR deve conter:

- objetivo;
- alterações realizadas;
- testes executados;
- observações.

Modelo:

```markdown
## Objetivo

Implementar autenticação por PIN.

## Alterações

- Login por PIN
- Busca de aluno
- Validação
- Testes

## Testado

- [x] API
- [x] Banco
- [x] Integração Totem
```

## Organização do repositório

Estrutura principal:

```text
Software/
├── apps/
├── backend/
├── database/
├── mobile/
├── infra/
└── docs/
```

Cada diretório possui responsabilidade própria.

### `apps/`

Contém as interfaces do sistema:

- `admin_web`;
- `totem_ui`.

### `backend/`

Contém a API do sistema.

É responsável por:

- regras de negócio;
- autenticação;
- integração com banco;
- endpoints.

### `database/`

Contém os recursos relacionados ao banco de dados:

- migrations;
- seeds;
- documentação do modelo.

### `mobile/`

Contém a aplicação Flutter, responsável pela experiência do aluno.

### `infra/`

Contém os recursos de infraestrutura, como:

- Docker;
- Compose;
- scripts.

### `docs/`

Contém a documentação técnica.

Exemplos:

- `database-model.md`;
- `backend-status.md`;
- `github-workflow.md`;
- `contracts.md`.

## Boas práticas

Sempre:

- criar uma branch para cada tarefa;
- realizar commits frequentes;
- escrever mensagens claras;
- revisar antes do merge;
- manter a documentação atualizada;
- excluir branches concluídas após o merge.

Evitar:

- commits gigantes;
- múltiplas funcionalidades na mesma branch;
- alterar código diretamente na `main`;
- abrir Pull Requests sem testes;
- misturar documentação e implementação na mesma branch sem necessidade.

## Fluxo resumido

```text
develop
   ↓
feature/minha-feature
   ↓
commits
   ↓
push
   ↓
Pull Request
   ↓
review
   ↓
merge
   ↓
deletar branch
```
