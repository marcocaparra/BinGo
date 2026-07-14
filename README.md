<div align="center">
  <img src="assets/b1n-logo.png" alt="B1N, mascote do BinGo" width="220" />

  # BinGo

  **Descarte eletrônico gamificado para escolas.**

  <p>
    <img alt="Branch" src="https://img.shields.io/badge/branch-main-111827?style=for-the-badge" />
    <img alt="Estado" src="https://img.shields.io/badge/estado-legado%20est%C3%A1vel-64748b?style=for-the-badge" />
    <img alt="Backend legado" src="https://img.shields.io/badge/backend-FastAPI-009688?style=for-the-badge" />
    <img alt="Banco legado" src="https://img.shields.io/badge/banco-MySQL-4479a1?style=for-the-badge" />
    <img alt="Frontend legado" src="https://img.shields.io/badge/frontend-HTML%2FCSS%2FJS-f59e0b?style=for-the-badge" />
  </p>
</div>

> Você está lendo o README da branch `main`. Esta branch preserva a versão legada/estável do projeto. Para o MVP atual, use a branch `develop`.

## 🌱 O Que É

O BinGo é um projeto de descarte de resíduo eletrônico gamificado para escolas. A proposta é transformar o descarte correto em uma experiência com pontos, missões, recompensas e acompanhamento de impacto.

Esta branch mostra uma fase anterior do projeto, com:

- backend em FastAPI;
- banco MySQL via Docker Compose;
- frontend web vanilla;
- primeiros fluxos de usuário, missões, conquistas, ranking, recompensas e descarte;
- protótipo de visão computacional em `Hardware/BinGoVision`.

## 🚦 Estado Da Branch

| Frente | Estado | Onde olhar |
|---|---|---|
| Backend | FastAPI legado | `Software/backend` |
| Banco | MySQL legado | `docker-compose.yml` e `Software/backend/models` |
| Frontend | HTML/CSS/JS vanilla | `Software/frontend` |
| Hardware/visão | Protótipo Python/OpenCV/YOLO | `Hardware/BinGoVision` |
| MVP atual | Não está nesta branch | branch `develop` |

### ⚠️ Atenção Técnica

| Branch | Uso |
|---|---|
| `main` | Preserva a versão legada/estável do projeto |
| `develop` | Integra o MVP atual: Supabase local, totem kiosk, app Flutter e backend reestruturado |

Se você quer entender o BinGo atual, troque para a branch:

```text
develop
```

## 🧭 Arquitetura Do MVP

A arquitetura atual do MVP, documentada na branch `develop`, mudou para:

```text
Totem web/kiosk -> Orange Pi + Arduino -> Supabase/PostgreSQL -> App Flutter
```

Decisões atuais importantes:

- Totem V1 é HTML/CSS/JS em modo kiosk, não Flutter.
- App Flutter V1 é apenas consulta.
- Backend final deve ser Supabase Edge Functions em Deno/TypeScript.
- O backend FastAPI desta branch não deve ser tratado como arquitetura final.

## 🗂️ Estrutura Do Repositório

```text
BinGo/
├── assets/
│   └── b1n-logo.png
├── Hardware/
│   └── BinGoVision/              # Protótipo de visão computacional
├── Software/
│   ├── backend/                   # FastAPI legado
│   │   ├── main.py                # Entrada da API
│   │   ├── routers/               # Rotas HTTP
│   │   ├── models/                # Modelos SQLAlchemy
│   │   ├── schemas/               # Schemas Pydantic
│   │   ├── services/              # Regras auxiliares
│   │   └── migrations/            # Alembic
│   └── frontend/                  # Frontend web legado
│       ├── index.html
│       ├── public/                # Páginas HTML
│       ├── css/
│       ├── js/
│       └── landing/
├── docker-compose.yml             # MySQL + backend legado
├── requirements.txt               # Dependências Python
└── README.md
```

## 🚀 Guia Rápido

### Pré-requisitos

- Docker Desktop
- Python 3.12+ se for rodar sem Docker
- Navegador moderno

### 1. Subir Docker Compose Legado

Na raiz do repositório:

```powershell
docker compose --profile dev up -d
```

Isso sobe:

- MySQL em `localhost:3306`;
- backend FastAPI em `localhost:8000`.

Teste a API:

```powershell
Invoke-RestMethod -Uri http://localhost:8000/
```

Resposta esperada:

```json
{"message":"Bem-vindo à API do BinGo!"}
```

### 2. Subir Backend Manual

Na raiz do repositório:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
cd Software/backend
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### 3. Abrir Frontend Legado

Abra diretamente:

```text
Software/frontend/index.html
```

Ou sirva a pasta:

```powershell
cd Software/frontend
python -m http.server 8080
```

Abra:

```text
http://localhost:8080
```

## 👥 Responsáveis

| Frente | Pessoa | Responsabilidade |
|---|---|---|
| Produto e integração | Marco Caparra | Coordenação geral, decisões e validação |
| Backend e banco | João Predeus | Backend, banco e contratos de API |
| Frontend/UX | Gustavo Alencar | Totem, app, identidade visual e BinGópolis |
| Hardware/CAD | Gustavo Bretas | Eletrônica, Orange Pi/Arduino e componentes |
| Mecânica | Gustavo Borrego | Estrutura física e montagem |
| Apoio pontual | Guilherme Albano | Apoio não operacional |

## 🌿 Branches, Commits E Pull Requests

> Fonte oficial: [Organização do GitHub — BinGo](https://github.com/marcocaparra/BinGo/blob/develop/Software/docs/github-workflow.md).

### Fluxo Desta Branch

A `main` representa a versão estável. Não desenvolva funcionalidades diretamente nela.

```text
develop -> Pull Request de promoção -> main
```

- Trabalho comum parte da `develop` em uma branch própria e retorna para a `develop` por Pull Request.
- A `main` recebe apenas alterações aprovadas e prontas para uma versão estável.
- Correções urgentes usam `hotfix/*`; mudanças exclusivas de documentação usam `docs/*`.
- Não use force push nem reescreva o histórico compartilhado.

### Nomes De Branch

| Prefixo | Quando usar | Exemplo |
|---|---|---|
| `feature/` | nova funcionalidade | `feature/admin-lite` |
| `fix/` | correção pontual | `fix/login-pin` |
| `docs/` | somente documentação | `docs/readme-workflow` |
| `hotfix/` | correção urgente da versão estável | `hotfix/api-crash` |

### Padrão De Commit

```text
tipo(escopo): descrição curta
```

Use commits pequenos, com uma única alteração lógica. O histórico atual usa descrições curtas em inglês, minúsculas e sem ponto final.

```text
docs(readme): document release contribution workflow
fix(api): correct production authentication regression
test(api): cover stable release behavior
```

Tipos usuais: `feat`, `fix`, `docs`, `refactor`, `test`, `chore` e `seed`.

Evite mensagens vagas como `update`, `alterações`, `teste` ou `corrigindo`.

### Padrão De Pull Request

O PR para a `main` deve explicar a promoção ou correção estável e conter:

```markdown
## Objetivo

Explique o resultado esperado.

## Alterações

- Liste as mudanças relevantes.

## Testes

- [x] Informe os testes realmente executados.

## Observações

Registre riscos, migrações ou pontos de atenção.
```

Antes do merge, confirme que o PR está atualizado, revisado e com os testes aplicáveis aprovados. Depois do merge, exclua a branch concluída.

## 🧩 Onde Mexer

| Se você vai mexer em... | Comece por |
|---|---|
| API legada | `Software/backend/main.py` e `Software/backend/routers` |
| Modelos do banco legado | `Software/backend/models` |
| Schemas Pydantic legados | `Software/backend/schemas` |
| Serviços/regras auxiliares | `Software/backend/services` |
| Frontend web legado | `Software/frontend/public`, `Software/frontend/js` e `Software/frontend/css` |
| Landing antiga | `Software/frontend/landing` |
| Visão computacional antiga | `Hardware/BinGoVision` |
| Ambiente Docker legado | `docker-compose.yml` |

## 📄 Licença

Veja `LICENSE`.
