<div align="center">
  <img src="assets/b1n-logo.png" alt="B1N, mascote do BinGo" width="220" />

  # BinGo

  **Totem inteligente + gamificação + educação ambiental para escolas.**

  <p>
    <img alt="Branch" src="https://img.shields.io/badge/branch-feature%2Fdiario--bordo--v0-2563eb?style=for-the-badge" />
    <img alt="Status" src="https://img.shields.io/badge/status-di%C3%A1rio%20de%20bordo%20V0-f59e0b?style=for-the-badge" />
    <img alt="Diário" src="https://img.shields.io/badge/di%C3%A1rio-Spring%20Boot%20%2B%20React-22c55e?style=for-the-badge" />
    <img alt="Mobile" src="https://img.shields.io/badge/mobile-Flutter-38bdf8?style=for-the-badge" />
    <img alt="Backend alvo" src="https://img.shields.io/badge/backend%20alvo-Supabase%20Edge%20Functions-3ecf8e?style=for-the-badge" />
  </p>
</div>

> Você está lendo o README da branch `feature/diario-bordo-v0`. Esta branch nasce da `develop` e concentra a primeira versão do Diário de Bordo coletivo em `Software/tools/diario-bordo/`.

## 🌱 O Que É

O BinGo transforma o descarte de resíduo eletrônico em uma experiência gamificada para escolas. O aluno descarta um item no totem físico, ganha **Bins**, acompanha seu progresso no app e pode trocar pontos por recompensas reais definidas pela escola.

O objetivo do MVP é provar o ciclo completo:

```text
Aluno -> Totem físico -> Backend/Banco -> Pontos -> Ranking/App -> Recompensa
```

## 🚦 Estado Da Branch

| Frente | Estado | Onde olhar |
|---|---:|---|
| Diário de Bordo V0 | Foco desta branch; API, frontend e banco em integração | `Software/tools/diario-bordo` |
| Backend do diário | Spring Boot + PostgreSQL | `Software/tools/diario-bordo/backend` |
| Frontend do diário | React + Vite | `Software/tools/diario-bordo/frontend` |
| Banco do diário | Migrations e seeds próprias | `Software/tools/diario-bordo/database` |
| Totem kiosk visual | Herdado da `develop` | `Software/apps/totem_kiosk_wireframe` |
| App mobile | Herdado da `develop` | `Software/mobile/bingo_app` |
| Backend principal do BinGo | Herdado da `develop`; FastAPI temporário/Supabase alvo | `Software/backend` e `Software/supabase` |

### Escopo Desta Branch

Esta branch existe para desenvolver o Diário de Bordo coletivo sem misturar essa ferramenta operacional com o fluxo principal do totem.

O que pode ser alterado aqui:

- API Spring Boot do Diário de Bordo;
- frontend React/Vite do Diário;
- migrations, seeds e documentação do Diário;
- autenticação simples por PIN coletivo/admin e fluxo de relatório diário.

O que deve evitar nesta branch:

- alterações no fluxo visual do totem V1;
- regras centrais de pontuação/descarte do BinGo;
- mudanças no app Flutter sem relação direta com o Diário.

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
│   ├── tools/
│   │   └── diario-bordo/              # Ferramenta interna desta branch
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

## 🌿 Branches, Commits E Pull Requests

> Fonte oficial: [Organização do GitHub — BinGo](Software/docs/github-workflow.md).

### Fluxo Desta Branch

A `feature/diario-bordo-v0` concentra somente a primeira versão do Diário de Bordo coletivo.

```text
develop -> feature/diario-bordo-v0 -> commits -> push -> Pull Request -> develop
```

- Antes de trabalhar, atualize sua cópia desta branch para preservar os commits do restante do time.
- Mantenha aqui apenas frontend, backend, banco, documentação e testes do Diário de Bordo.
- Mudanças sem relação devem partir da `develop` em outra `feature/*`, `fix/*` ou `docs/*`.
- Não versione `.env`, credenciais, bancos locais, builds ou arquivos enviados como evidência.
- Não use force push nem reescreva o histórico compartilhado.
- Quando a ferramenta estiver pronta para integração, abra o PR de `feature/diario-bordo-v0` para `develop`.

### Nomes De Branch

| Prefixo | Quando usar | Exemplo |
|---|---|---|
| `feature/` | nova funcionalidade | `feature/diario-bordo-v0` |
| `fix/` | correção pontual | `fix/diario-attachment-download` |
| `docs/` | somente documentação | `docs/diario-api-contract` |
| `hotfix/` | correção urgente da versão estável | `hotfix/diario-auth` |

### Padrão De Commit

```text
tipo(escopo): descrição curta
```

Use commits pequenos, com uma única alteração lógica. O histórico atual usa descrições curtas em inglês, minúsculas e sem ponto final.

```text
feat(diario-bordo): add evidence upload flow
fix(diario-bordo): prevent future report dates
docs(diario-bordo): clarify local setup
test(diario-bordo): cover attachment download
```

Tipos usuais nesta branch: `feat`, `fix`, `docs`, `refactor`, `test`, `chore` e `seed`. Use o escopo `diario-bordo` para mudanças completas; use `frontend`, `backend` ou `database` quando a alteração estiver restrita a uma camada.

Evite mensagens vagas como `update`, `alterações`, `teste` ou `corrigindo`.

### Padrão De Pull Request

O PR para a `develop` deve usar um título direto e conter:

```markdown
## Objetivo

Explique qual resultado do Diário de Bordo foi concluído.

## Alterações

- Liste mudanças de frontend, backend, banco ou documentação.

## Testes

- [x] Informe testes automatizados, lint, build e fluxos manuais executados.

## Observações

Registre migrations, variáveis de ambiente, limites de upload ou riscos conhecidos.
```

Antes do merge, confirme que frontend e backend foram validados, que migrations necessárias estão documentadas e que o PR recebeu revisão. Depois do merge, exclua a branch concluída.

## 🧩 Onde Mexer

| Se você vai mexer em... | Comece por |
|---|---|
| Diário de Bordo coletivo | `Software/tools/diario-bordo` |
| API do Diário | `Software/tools/diario-bordo/backend/src/main/java/com/bingo/diario` |
| Frontend do Diário | `Software/tools/diario-bordo/frontend/src` |
| Banco do Diário | `Software/tools/diario-bordo/database` |
| Fluxo visual do totem | `Software/apps/totem_kiosk_wireframe` |
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


