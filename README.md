<div align="center">
  <img src="assets/b1n-logo.png" alt="B1N, mascote do BinGo" width="220" />

  # BinGo

  **Totem inteligente + gamificação + educação ambiental para escolas.**

  <p>
    <img alt="Branch" src="https://img.shields.io/badge/branch-feature%2Ftotem--v1-2563eb?style=for-the-badge" />
    <img alt="Status" src="https://img.shields.io/badge/status-totem%20V1%20em%20revis%C3%A3o-f59e0b?style=for-the-badge" />
    <img alt="Totem" src="https://img.shields.io/badge/totem-kiosk%20HTML%2FCSS%2FJS-22c55e?style=for-the-badge" />
    <img alt="Mobile" src="https://img.shields.io/badge/mobile-Flutter-38bdf8?style=for-the-badge" />
    <img alt="Backend alvo" src="https://img.shields.io/badge/backend%20alvo-Supabase%20Edge%20Functions-3ecf8e?style=for-the-badge" />
  </p>
</div>

> Você está lendo o README da branch `feature/totem-v1`. Esta branch nasce da `develop` e concentra a evolução visual/navegável do totem V1 em `Software/apps/totem_kiosk_wireframe/`.

## 🌱 O Que É

O BinGo transforma o descarte de resíduo eletrônico em uma experiência gamificada para escolas. O aluno descarta um item no totem físico, ganha **Bins**, acompanha seu progresso no app e pode trocar pontos por recompensas reais definidas pela escola.

O objetivo do MVP é provar o ciclo completo:

```text
Aluno -> Totem físico -> Backend/Banco -> Pontos -> Ranking/App -> Recompensa
```

## 🚦 Estado Da Branch

| Frente | Estado | Onde olhar |
|---|---:|---|
| Totem kiosk visual | Foco desta branch; protótipo V1 em refinamento | `Software/apps/totem_kiosk_wireframe` |
| Favicon/guia do navegador | Ajustado para `BinGo \| Totem` | `Software/apps/totem_kiosk_wireframe/assets/brand` |
| Totem simulator técnico | Herdado da `develop` | `Software/apps/totem_simulator` |
| App mobile | Herdado da `develop` | `Software/mobile/bingo_app` |
| Backend atual | Herdado da `develop`; FastAPI temporário | `Software/backend` |
| Backend alvo | Herdado da `develop`; Supabase Edge Functions | `Software/supabase` |
| Banco | Herdado da `develop`; Supabase/PostgreSQL local | `Software/database` e `Software/supabase` |

### Escopo Desta Branch

Esta branch existe para o Alencar e o Marco continuarem o desenho navegável do totem físico sem travar a `develop`.

O que pode ser alterado aqui:

- fluxo visual do kiosk em HTML/CSS/JS;
- hierarquia, espaçamento, legibilidade e estados das telas do totem;
- textos curtos com voz do B1N;
- assets específicos do protótipo visual do totem.

O que deve evitar nesta branch:

- backend real, banco e regras de pontuação definitivas;
- mudanças no app Flutter;
- refatorações gerais fora de `Software/apps/totem_kiosk_wireframe/`.

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
| `feature/totem-v1` | protótipo visual/navegável do totem V1 |
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

## 🧩 Onde Mexer

| Se você vai mexer em... | Comece por |
|---|---|
| Fluxo visual do totem nesta branch | `Software/apps/totem_kiosk_wireframe` |
| Favicon, logo e assets do kiosk | `Software/apps/totem_kiosk_wireframe/assets` |
| Teste técnico de depósito/ranking | `Software/apps/totem_simulator` |
| Regras temporárias do backend | `Software/backend/src/domain` |
| Rotas da API temporária | `Software/backend/src/app/api/routes` |
| Contratos/schemas da API | `Software/backend/src/app/api/schemas` |
| Banco local e seeds | `Software/database` e `Software/supabase` |
| App mobile Flutter | `Software/mobile/bingo_app` |
| Visão computacional | `Hardware/BinGoVision` |

## 🔒 Regras Que Não Devem Ser Reabertas Sem Decisão Formal

- Totem V1 é web/kiosk, não Flutter.
- App Flutter V1 é consulta, não resgate.
- Backend final é Supabase Edge Functions, não servidor FastAPI separado.
- Resgate acontece no totem físico.
- Offline significa fila pendente e sincronização posterior.
- Credencial técnica de máquina não deve ficar exposta em frontend real.

## 📄 Licença

Veja `LICENSE`.


