<div align="center">
  <img src="assets/b1n-logo.png" alt="B1N, mascote do BinGo" width="220" />

  # BinGo

  **Totem inteligente + gamificação + educação ambiental para escolas.**

  <p>
    <img alt="Branch" src="https://img.shields.io/badge/branch-develop-2563eb?style=for-the-badge" />
    <img alt="Status" src="https://img.shields.io/badge/status-MVP%20em%20desenvolvimento-f59e0b?style=for-the-badge" />
    <img alt="Totem" src="https://img.shields.io/badge/totem-HTML%2FCSS%2FJS-22c55e?style=for-the-badge" />
    <img alt="Mobile" src="https://img.shields.io/badge/mobile-Flutter-38bdf8?style=for-the-badge" />
    <img alt="Backend alvo" src="https://img.shields.io/badge/backend%20alvo-Supabase%20Edge%20Functions-3ecf8e?style=for-the-badge" />
  </p>
</div>

> Você está lendo o README da branch `develop`, a branch mais atual do MVP. A branch `main` ainda representa uma referência histórica/estável do projeto legado.

## 🌱 O Que É

O BinGo transforma o descarte de resíduo eletrônico em uma experiência gamificada para escolas. O aluno descarta um item no totem físico, ganha **Bins**, acompanha seu progresso no app e pode trocar pontos por recompensas reais definidas pela escola.

O objetivo do MVP é provar o ciclo completo:

```text
Aluno -> Totem físico -> Backend/Banco -> Pontos -> Ranking/App -> Recompensa
```

## 🚦 Estado Atual

| Frente | Estado | Onde olhar |
|---|---:|---|
| Totem kiosk visual | Em revisão visual | `Software/apps/totem_kiosk_wireframe` |
| Totem simulator técnico | Funcional para testar backend | `Software/apps/totem_simulator` |
| App mobile | Protótipo Flutter visual | `Software/mobile/bingo_app` |
| Backend atual | FastAPI temporário | `Software/backend` |
| Backend alvo | Supabase Edge Functions | `Software/supabase` |
| Banco | Supabase/PostgreSQL local | `Software/database` e `Software/supabase` |
| Visão computacional | Protótipo inicial | `Hardware/BinGoVision` |

### ⚠️ Atenção Técnica

O backend em `Software/backend` está em **FastAPI/Python**. Ele modela regras importantes do V1, mas **não é a stack final acordada**. A direção técnica travada para produção é:

```text
Supabase PostgreSQL + Edge Functions em Deno/TypeScript
```

Então o FastAPI deve ser tratado como base temporária de regras, testes e contratos até a migração.

## 🧭 Arquitetura Do MVP

```text
┌──────────────────────┐
│ Aluno                │
└──────────┬───────────┘
           │ toque / PIN / descarte
┌──────────▼───────────┐
│ Totem web/kiosk      │  HTML + CSS + JS
│ Orange Pi            │
└──────────┬───────────┘
           │ serial / sensores
┌──────────▼───────────┐
│ Arduino + mecanismo  │
└──────────┬───────────┘
           │ evento validado
┌──────────▼───────────┐
│ Backend temporário   │  FastAPI hoje
│ Backend alvo         │  Supabase Edge Functions
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│ Supabase/PostgreSQL  │
└──────────┬───────────┘
           │ consulta
┌──────────▼───────────┐
│ App Flutter V1       │  consulta de pontos
└──────────────────────┘
```

## 🗂️ Estrutura Do Repositório

```text
BinGo/
├── assets/
│   └── b1n-logo.png
├── Hardware/
│   └── BinGoVision/                 # Protótipo de visão computacional
├── Software/
│   ├── apps/
│   │   ├── totem_kiosk_wireframe/    # Protótipo visual do totem kiosk
│   │   └── totem_simulator/          # Simulador técnico integrado ao backend
│   ├── backend/                      # Backend FastAPI temporário
│   │   ├── src/app/api/routes/       # Rotas HTTP
│   │   ├── src/domain/               # Regras de negócio
│   │   ├── src/infra/                # Banco, auth e repositories
│   │   └── tests/                    # Testes automatizados
│   ├── database/
│   │   ├── migrations/               # Estrutura SQL
│   │   └── seeds/                    # Dados demo
│   ├── docs/                         # Documentos técnicos
│   ├── mobile/
│   │   └── bingo_app/                # App Flutter
│   ├── supabase/                     # Configuração Supabase local
│   └── docker-compose.yml            # Serviço backend-dev
└── README.md
```

## 🚀 Guia Rápido

### Pré-requisitos

- Git
- Docker Desktop
- Supabase CLI
- Python 3.12+
- Flutter SDK, apenas para o app mobile

### 1. Subir Supabase Local

A partir de `Software/`:

```powershell
cd Software
supabase start
```

Serviços esperados:

```text
Supabase API:    http://localhost:54321
Supabase Studio: http://localhost:54323
Postgres:        127.0.0.1:54322
```

### 2. Subir Backend FastAPI Temporário

A partir de `Software/`:

```powershell
docker compose up -d backend-dev
```

Verificar:

```powershell
Invoke-RestMethod -Uri http://localhost:8000/health
```

Resposta esperada:

```json
{"status":"ok"}
```

Alternativa sem Docker:

```powershell
cd Software/backend
pip install -e .[dev]
$env:BINGO_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
$env:BINGO_JWT_SECRET="dev-secret-change-me"
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Rodar testes:

```powershell
cd Software/backend
pytest
```

### 3. Abrir Totem Simulator Técnico

Use quando quiser testar backend, seed, depósitos, alunos e rankings.

```powershell
cd Software/apps/totem_simulator
python -m http.server 8001
```

Abra:

```text
http://localhost:8001
```

### 4. Abrir Totem Kiosk Visual

Use quando quiser revisar a experiência visual do totem físico.

```powershell
cd Software
python -m http.server 8092 --bind 127.0.0.1
```

Abra:

```text
http://127.0.0.1:8092/apps/totem_kiosk_wireframe/
```

### 5. Rodar App Flutter

```powershell
cd Software/mobile/bingo_app
flutter pub get
flutter analyze
flutter test
flutter run
```

Build web:

```powershell
flutter build web
```

## 🧪 Seeds E Dados Demo

A seed principal do simulador é:

```text
Software/database/seeds/008_seed_totem_simulator_rich_demo.sql
```

Ela cria a Escola Demo BinGo, 7 turmas, 70 alunos, PINs de demonstração, máquina demo e recompensas.

Para recarregar a seed com o Supabase local ligado, rode a partir de `Software/`:

```powershell
Get-Content database\seeds\008_seed_totem_simulator_rich_demo.sql | docker exec -i supabase_db_Software psql -v ON_ERROR_STOP=1 -U postgres -d postgres
```

## 🎮 Fluxos Do Produto

### Login Do Aluno

```text
Segmento -> Série -> Turma -> Nome -> PIN de 4 dígitos -> JWT
```

### Descarte

```text
Totem acorda -> aluno escolhe identificar-se ou ajudar a turma -> item é inserido
-> visão/sensores validam -> backend registra evento -> pontos entram no saldo
```

### Resgate

No V1, resgate é feito pelo **totem físico**. O app mobile é apenas consulta.

## 👥 Responsáveis

| Frente | Pessoa | Responsabilidade |
|---|---|---|
| Produto e integração | Marco Caparra | Coordenação geral, decisões e validação |
| Backend e banco | João Predeus | Supabase, Edge Functions e contratos de API |
| Frontend/UX | Gustavo Alencar | Totem kiosk, app Flutter e identidade BinGópolis |
| Hardware/CAD | Gustavo Bretas | Orange Pi, Arduino, circuito e componentes |
| Mecânica | Gustavo Borrego | MDF, montagem e estrutura física |
| Apoio pontual | Guilherme Albano | Apoio não operacional |

## 🌿 Branches E Commits

| Branch | Uso |
|---|---|
| `main` | referência estável/histórica |
| `develop` | integração atual do MVP |
| `feature/*` | novas frentes a partir de `develop` |
| `fix/*` | correções pontuais |

Padrão de commit:

```text
tipo(escopo): descrição curta
```

Exemplos reais:

```text
feat(totem): add kiosk wireframe prototype
docs(status): map mobile UI v2 snapshot
feat(mobile): add current Flutter UI snapshot
seed(database): add updated demo school dataset
fix(api, cors): finalize CORS configuration for Codespaces with regex
```

## 🔗 Links Úteis

| Recurso | Link |
|---|---|
| GitHub | https://github.com/marcocaparra/BinGo |
| Branch develop | https://github.com/marcocaparra/BinGo/tree/develop |
| Notion - tarefas | https://www.notion.so/2f7229b439f88122a3d8c01247448309 |
| Notion - projetos | https://www.notion.so/2f7229b439f8817cba32cc9521b3809b |
| Documento BinGo 2026 | https://docs.google.com/document/d/1OD3hdFm2UbYNE3HBNEI6vms9kNsu5Rd5fo-KymgfRvY/edit |
| Componentes e BOM | https://docs.google.com/spreadsheets/d/1N7zrweYtqQFoFymsH3EZ1djiAX-3tFzBTZ71HSuSdk0/edit |
| Cronograma | https://docs.google.com/spreadsheets/d/1St1Xw-g0P6QZDXfAjKSIkHHS6w-jj98bh7YkkGKBzqY/edit |

## 🔒 Regras Que Não Devem Ser Reabertas Sem Decisão Formal

- Totem V1 é web/kiosk, não Flutter.
- App Flutter V1 é consulta, não resgate.
- Backend final é Supabase Edge Functions, não servidor FastAPI separado.
- Resgate acontece no totem físico.
- Offline significa fila pendente e sincronização posterior.
- Credencial técnica de máquina não deve ficar exposta em frontend real.

## 📄 Licença

Veja `LICENSE`.
