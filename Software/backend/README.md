# BinGo Backend V1

Backend FastAPI responsável pelas regras críticas do BinGo V1: autenticação por contexto, depósitos idempotentes, antifraude, resgates transacionais, entrega por admin, auditoria e status operacional de máquinas.

## O que está sendo modelado

O backend é a camada central de escrita crítica entre:

- Totem Touch
- Edge local offline-first
- Admin Lite Web
- App mobile de consulta
- Postgres/Supabase

Escritas sensíveis sempre passam por esta API. Leituras simples podem ser expostas via outra camada no futuro.

## Impacto no banco

Além das tabelas já existentes, esta implementação assume uma migration de suporte para:

- `school_settings`: limites e políticas operacionais por escola
- `admins.password_hash`: autenticação segura de admin
- `machines.api_key_hash`: credencial técnica por máquina/edge
- `rewards.status`: disponibilidade administrativa explícita

Esses ajustes evitam deixar antifraude, auth e disponibilidade “soltos” no client.

## Estratégia de autenticação

- `student`: autenticação customizada com `school_id + class_id + student_id + pin`, retornando JWT curta
- `admin_school` / `bingo_admin`: login por `email + password`, também retornando JWT
- `edge_service`: `X-Machine-Id + X-Api-Key`, validados contra hash persistido na máquina

## Estrutura

```text
backend/
  src/
    app/
      api/
        routes/
        schemas/
      config/
    domain/
      auth/
      students/
      deposits/
      rewards/
      redemptions/
      machines/
      audit/
    infra/
      auth/
      crypto/
      db/
      repositories/
    shared/
      constants/
      errors/
      utils/
  tests/
  Dockerfile
```

## Rodando localmente

```bash
cd backend
pip install -e .[dev]

$env:BINGO_DATABASE_URL="postgresql+psycopg://bingo:bingo123@localhost:5432/bingo_dev"
$env:BINGO_JWT_SECRET="dev-secret-change-me"

uvicorn app.main:app --host 0.0.0.0 --port 8000
pytest
```

## Variáveis de ambiente

```env
BINGO_DATABASE_URL=postgresql+psycopg://bingo:bingo123@localhost:5432/bingo_dev
BINGO_JWT_SECRET=change-me
BINGO_API_PREFIX=/v1
BINGO_TOKEN_TTL_MINUTES=30
```
