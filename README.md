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

## 🌱 O Que É O BinGo

O BinGo é um projeto de descarte de resíduo eletrônico gamificado para escolas. A proposta é transformar o descarte correto em uma experiência com pontos, missões, recompensas e acompanhamento de impacto.

Esta branch mostra uma fase anterior do projeto, com:

- backend em FastAPI;
- banco MySQL via Docker Compose;
- frontend web vanilla;
- primeiros fluxos de usuário, missões, conquistas, ranking, recompensas e descarte;
- protótipo de visão computacional em `Hardware/BinGoVision`.

## 🚦 Estado Desta Branch

| Área | Estado na `main` | Observação |
|---|---|---|
| Backend | FastAPI legado | Funciona como referência histórica |
| Banco | MySQL | Diferente do Supabase usado no MVP atual |
| Frontend | HTML/CSS/JS vanilla | Fluxos web antigos |
| Hardware/visão | Protótipo Python/OpenCV/YOLO | Ainda não representa a arquitetura Orange Pi + Arduino final |
| MVP atual | Não está nesta branch | Use `develop` |

## ⚠️ Diferença Entre `main` E `develop`

| Branch | Para que serve |
|---|---|
| `main` | Preserva a versão legada/estável do projeto |
| `develop` | Integra o MVP atual: Supabase local, totem kiosk, app Flutter e backend reestruturado |

Se você quer entender o BinGo atual, troque para a branch:

```text
develop
```

## 🗂️ Estrutura Desta Branch

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

## 🚀 Como Rodar A Versão Legada

### Pré-requisitos

- Docker Desktop
- Python 3.12+ se for rodar sem Docker
- Navegador moderno

### Opção 1: Docker Compose

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

### Opção 2: Backend Manual

Na raiz do repositório:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
cd Software/backend
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Frontend Legado

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

## 🧭 Para Onde O Projeto Evoluiu

A arquitetura atual do MVP, documentada na branch `develop`, mudou para:

```text
Totem web/kiosk -> Orange Pi + Arduino -> Supabase/PostgreSQL -> App Flutter
```

Decisões atuais importantes:

- Totem V1 é HTML/CSS/JS em modo kiosk, não Flutter.
- App Flutter V1 é apenas consulta.
- Backend final deve ser Supabase Edge Functions em Deno/TypeScript.
- O backend FastAPI desta branch não deve ser tratado como arquitetura final.

## 🌿 Padrão De Branch E Commit

Fluxo recomendado:

```text
develop -> feature/* -> Pull Request -> develop -> promoção planejada para main
```

Padrão de commit usado no projeto:

```text
tipo(escopo): descrição curta
```

Exemplos:

```text
feat(totem): add kiosk wireframe prototype
docs(status): map mobile UI v2 snapshot
fix(api, cors): finalize CORS configuration for Codespaces with regex
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

## 🧩 Mapa Interno Da Branch

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
