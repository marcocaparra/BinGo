# BinGo

BinGo é uma plataforma gamificada de descarte de resíduos eletrônicos para escolas. O aluno usa um totem físico para registrar descartes, acumula Bins e consulta seu progresso pelo app. A escola acompanha engajamento, impacto e recompensas por meio de uma operação simples para piloto e MVP.

> Status: projeto em desenvolvimento. A branch `develop` contém o estado mais atual do MVP. A branch `main` funciona como referência estável/histórica até que `develop` seja promovida.

## Visão rápida

- Produto: descarte de resíduo eletrônico gamificado para escolas.
- MVP V1: totem físico + backend + app mobile de consulta + Admin Lite.
- Totem V1: web/kiosk em HTML, CSS e JavaScript, rodando em Orange Pi.
- App V1: Flutter, somente consulta de pontos e progresso.
- Backend definido: Supabase PostgreSQL + Edge Functions em Deno/TypeScript.
- Backend existente no repositório: FastAPI em Python, usado como implementação temporária/protótipo técnico até a migração para Edge Functions.
- Hardware definido: Orange Pi + Arduino via comunicação Serial.

## Estado atual do repositório

O README antigo descrevia uma arquitetura legada com frontend web geral, MySQL e ESP32/ESP8266. Isso não representa mais o projeto atual.

Hoje, a branch `develop` concentra:

- Backend FastAPI V1 em `Software/Backend`, com regras de autenticação, depósitos, resgates, máquinas, recompensas e auditoria.
- Banco Supabase/PostgreSQL versionado em `Software/database` e `Software/supabase`.
- Simulador técnico do totem em `Software/apps/totem_simulator`.
- Protótipo visual kiosk do totem em `Software/apps/totem_kiosk_wireframe`.
- App Flutter em `Software/mobile/bingo_app`.
- Documentos técnicos em `Software/docs`.
- Protótipo de visão computacional em `Hardware/BinGoVision`.

A migração crítica ainda é transformar as regras atuais do backend FastAPI em Supabase Edge Functions, sem manter servidor separado para produção.

## Estrutura de pastas

```text
BinGo/
├── Hardware/
│   └── BinGoVision/                 # Protótipo de visão computacional
├── Software/
│   ├── Backend/                      # Backend FastAPI temporário do V1
│   │   ├── src/app/api/routes/       # Rotas HTTP
│   │   ├── src/app/api/schemas/      # Schemas de entrada/saída
│   │   ├── src/domain/               # Regras de negócio
│   │   ├── src/infra/                # Banco, auth, repositories
│   │   └── tests/                    # Testes do backend
│   ├── apps/
│   │   ├── totem_simulator/          # Simulador técnico integrado ao backend
│   │   └── totem_kiosk_wireframe/    # Protótipo visual do kiosk/totem
│   ├── database/
│   │   ├── migrations/               # SQL de estrutura do banco
│   │   └── seeds/                    # Dados demo e seeds de desenvolvimento
│   ├── docs/                         # Documentação técnica e status
│   ├── mobile/
│   │   └── bingo_app/                # App Flutter
│   ├── supabase/                     # Configuração local do Supabase
│   └── docker-compose.yml            # Serviço local do backend-dev
├── Gestão e Operacional/             # Status e contexto operacional do projeto
├── README.md                         # Este guia de entrada
└── LICENSE
```

## Componentes principais

### Backend

- Local atual: `Software/Backend`
- Stack atual no repo: Python 3.12, FastAPI, SQLAlchemy, PostgreSQL/Supabase, PyJWT.
- Responsável: João Predeus.
- Observação técnica: esta implementação existe, mas não é a stack final acordada. A stack final do V1 é Supabase Edge Functions em Deno/TypeScript.

Principais responsabilidades atuais:

- Login de aluno/admin.
- Registro de depósitos.
- Idempotência por evento de depósito.
- Regras de pontuação e antifraude.
- Resgates e entrega por admin.
- Status operacional de máquinas.
- Auditoria de ações sensíveis.

### Banco de dados

- Local: `Software/database` e `Software/supabase`
- Stack: Supabase local com PostgreSQL.
- Tabelas do domínio: `schools`, `classes`, `students`, `admins`, `machines`, `rewards`, `deposits`, `redemptions`, `audit_logs`, `school_configs`/configurações equivalentes.

### Totem

Existem dois artefatos diferentes:

- `Software/apps/totem_simulator`: ferramenta técnica para testar backend, seeds, depósitos, rankings e comportamento de API.
- `Software/apps/totem_kiosk_wireframe`: protótipo visual do fluxo kiosk, usado para revisão de UI/UX do totem físico.

O produto final do Totem V1 deve ser web/kiosk em HTML, CSS e JavaScript no Orange Pi. Não é Flutter.

### App mobile

- Local: `Software/mobile/bingo_app`
- Stack: Flutter.
- Responsável: Gustavo Alencar.
- Escopo V1: consulta de pontos, progresso e narrativa visual. Resgate não acontece no app no V1; resgate é pelo totem físico.

### Hardware e visão

- Hardware definido: Orange Pi + Arduino via Serial.
- Local de protótipo de visão: `Hardware/BinGoVision`.
- Direção do produto: Orange Pi executa a camada local do totem/edge; Arduino controla partes físicas; visão computacional classifica itens em SMALL, MEDIUM ou LARGE com fallback operacional.

## Como rodar localmente

As instruções abaixo são para desenvolvimento. Não representam deploy de produção.

### 1. Supabase local

A partir de `Software/`:

```powershell
supabase start
```

A configuração local fica em `Software/supabase/config.toml`. Para um passo a passo mais completo, veja `Software/docs/iniciar-supabase-local.md`.

### 2. Backend FastAPI atual

A partir de `Software/Backend/`:

```powershell
pip install -e .[dev]
$env:BINGO_DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
$env:BINGO_JWT_SECRET="dev-secret-change-me"
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Testes:

```powershell
pytest
```

Alternativa com Docker Compose, a partir de `Software/`:

```powershell
supabase start
docker compose up -d backend-dev
```

### 3. Totem Simulator

Com o backend em `http://localhost:8000`, a partir de `Software/apps/totem_simulator/`:

```powershell
python -m http.server 8001
```

Abra:

```text
http://localhost:8001
```

### 4. Totem Kiosk Wireframe

A partir de `Software/apps/totem_kiosk_wireframe/`:

```powershell
python -m http.server 8002
```

Abra:

```text
http://localhost:8002
```

Esse protótipo é visual e de fluxo; ele não substitui a integração real com Orange Pi, Arduino, backend e visão computacional.

### 5. App Flutter

A partir de `Software/mobile/bingo_app/`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Para build web:

```powershell
flutter build web
```

## Branches

- `main`: branch padrão do GitHub. Deve receber apenas estados estáveis ou promovidos.
- `develop`: branch de integração atual do MVP. É onde backend, mobile, totem e documentação estão avançando.
- Branches de feature: criar a partir de `develop`, usando nomes descritivos como `feature/totem-ux-v0`, `feature/database-supabase-auth` ou `fix/auth-pin-validation`.

Fluxo recomendado:

```text
develop -> feature/* -> Pull Request -> develop -> promoção planejada para main
```

## Padrão de commits

O repositório usa Conventional Commits. Exemplos reais do histórico:

```text
feat(totem): add kiosk wireframe prototype
docs(status): map mobile UI v2 snapshot
feat(mobile): add current Flutter UI snapshot
seed(database): add updated demo school dataset
fix(api, cors): finalize CORS configuration for Codespaces with regex
```

Use o formato:

```text
tipo(escopo): descrição curta no imperativo
```

Tipos comuns:

- `feat`: nova funcionalidade.
- `fix`: correção de bug.
- `docs`: documentação.
- `chore`: configuração/manutenção.
- `refactor`: mudança interna sem alterar comportamento.
- `test`: testes.
- `seed`: dados de desenvolvimento.

## Responsáveis por frente

| Frente | Responsável principal | Observação |
|---|---|---|
| Integração geral, produto e operação | Marco Caparra | Coordena decisões, valida prioridades e integra frentes |
| Backend e banco | João Predeus | Supabase Edge Functions e PostgreSQL; FastAPI atual precisa migrar |
| Frontend, UI e UX | Gustavo Alencar | Totem kiosk, app Flutter, identidade visual e BinGópolis |
| Hardware, CAD e eletrônica | Gustavo Bretas | Orange Pi, Arduino, circuito e componentes |
| Mecânica e estrutura | Gustavo Borrego | Corte, MDF e montagem física do totem |
| Apoio pontual | Guilherme Albano | Apoio não operacional |

## Links úteis

- Repositório GitHub: https://github.com/marcocaparra/BinGo
- Branch principal de desenvolvimento: https://github.com/marcocaparra/BinGo/tree/develop
- Notion - tarefas: https://www.notion.so/2f7229b439f88122a3d8c01247448309
- Notion - projetos: https://www.notion.so/2f7229b439f8817cba32cc9521b3809b
- Notion - Gestão e Operações: https://www.notion.so/2f7229b439f8800eb1acfc3dc500f5b8
- Documento BinGo 2026: https://docs.google.com/document/d/1OD3hdFm2UbYNE3HBNEI6vms9kNsu5Rd5fo-KymgfRvY/edit
- Componentes e BOM: https://docs.google.com/spreadsheets/d/1N7zrweYtqQFoFymsH3EZ1djiAX-3tFzBTZ71HSuSdk0/edit
- Cronograma de Projetos: https://docs.google.com/spreadsheets/d/1St1Xw-g0P6QZDXfAjKSIkHHS6w-jj98bh7YkkGKBzqY/edit

## Avisos importantes

- Não tratar o backend FastAPI como decisão final de produção. Ele é base técnica atual, mas a arquitetura acordada é Supabase Edge Functions.
- Não mover o totem para Flutter no V1. O totem é web/kiosk.
- Não implementar resgate no app mobile V1. Resgate é no totem físico.
- Não expor chave técnica de máquina em frontend real. No simulador local isso existe apenas para desenvolvimento.
- Antes de alterar fluxos principais, conferir `Gestão e Operacional/STATUS.md` e a tarefa correspondente no Notion.

## Licença

Veja `LICENSE`.
