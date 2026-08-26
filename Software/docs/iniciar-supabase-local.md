# Como iniciar o banco Supabase local

Este guia e para quando voce voltar outro dia e quiser testar o BinGo usando o banco local do Supabase.

O banco correto do projeto e o Postgres do Supabase local, exposto em:

```text
127.0.0.1:54322
```

O backend em Docker usa esse mesmo banco por:

```text
host.docker.internal:54322
```

## Inicio rapido

Na raiz do projeto:

```powershell
cd C:\Users\Predeus\Documents\BinGo\Software
supabase start
docker compose up -d backend-dev
```

Depois, abra ou mantenha o Totem Simulator em:

```powershell
cd C:\Users\Predeus\Documents\BinGo\Software\apps\totem_simulator
python -m http.server 8001
```

URLs principais:

```text
Backend:          http://localhost:8000
Backend health:   http://localhost:8000/health
Totem Simulator:  http://localhost:8001
Supabase Studio:  http://localhost:54323
Supabase API:     http://localhost:54321
```

## Conferir se o banco esta ligado

Na raiz do projeto:

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Procure pelo container:

```text
supabase_db_Software
```

Ele deve aparecer como `Up` e expor a porta:

```text
54322->5432
```

## Conferir se a seed 008 esta carregada

Use:

```powershell
docker exec supabase_db_Software psql -U postgres -d postgres -c "select count(*) as classes from public.classes where school_id='10000000-0000-4000-8000-000000000001'; select count(*) as students from public.students where school_id='10000000-0000-4000-8000-000000000001';"
```

O esperado para a seed rica do Totem Simulator e:

```text
classes: 7
students: 70
```

## Recarregar a seed 008

Use isto quando o banco estiver ligado, mas os dados do simulador nao estiverem corretos.

Na raiz do projeto:

```powershell
Get-Content database\seeds\008_seed_totem_simulator_rich_demo.sql | docker exec -i supabase_db_Software psql -v ON_ERROR_STOP=1 -U postgres -d postgres
```

Essa seed limpa e recria apenas os dados demo da escola do simulador:

```text
Escola Demo BinGo
```

Ela recria:

- 7 turmas
- 70 alunos
- PIN individual para cada aluno
- maquina demo do totem
- recompensas demo

## Reset completo do Supabase local

Use apenas quando quiser reconstruir o banco local do zero.

Na raiz do projeto:

```powershell
supabase db reset
```

O `supabase/config.toml` ja esta configurado para carregar automaticamente:

```text
../database/seeds/008_seed_totem_simulator_rich_demo.sql
```

Atencao: `supabase db reset` apaga os dados locais e reaplica as migrations e a seed.

## Subir o backend depois do banco

Com o Supabase ja ligado:

```powershell
docker compose up -d backend-dev
```

Verifique:

```powershell
Invoke-RestMethod -Uri http://localhost:8000/health
```

O esperado e:

```json
{"status":"ok"}
```

## Edge Functions

**Estado comprovado localmente em 2026-08-15:** `register-deposit-v1` e `health-v1` estão versionadas em `supabase/functions/`, e ambas reutilizam a autenticação técnica compartilhada.

Depois de iniciar a stack local:

```powershell
supabase start
supabase functions serve
```

Também é possível servir uma Function isoladamente:

```powershell
supabase functions serve health-v1
```

O readiness central fica em `GET http://127.0.0.1:54321/functions/v1/health-v1` e exige `X-Machine-Id` e `X-Api-Key`. Somente HTTP `200` com `AVAILABLE` e `can_start_deposit=true` representa saúde comprovada. O `/health` do FastAPI mostrado na seção anterior pertence ao backend legado e não substitui esse contrato Supabase.

Para secrets locais de desenvolvimento:

```powershell
supabase functions serve --env-file supabase/.env.local
```

O arquivo `supabase/.env.local` já está coberto por `supabase/.gitignore` e deve permanecer ignorado pelo Git. Não versionar chaves privilegiadas, credenciais de máquina, tokens ou secrets de integrações. Até existir código em `supabase/functions/`, não há chamada de Function para validar neste guia.

## Testar se o backend esta lendo o Supabase

```powershell
$headers = @{
  'X-Machine-Id' = '40000000-0000-4000-8000-000000000001'
  'X-Api-Key' = 'edge-demo-key'
}

$context = Invoke-RestMethod -Uri http://localhost:8000/v1/totem/context -Headers $headers
[pscustomobject]@{
  school = $context.school.name
  classes = $context.classes.Count
  students = $context.students.Count
}
```

O esperado e:

```text
school: Escola Demo BinGo
classes: 7
students: 70
```

## Testar login por PIN no Totem

Exemplo com a aluna Ana Castanheira:

```powershell
$headers = @{
  'X-Machine-Id' = '40000000-0000-4000-8000-000000000001'
  'X-Api-Key' = 'edge-demo-key'
}

$context = Invoke-RestMethod -Uri http://localhost:8000/v1/totem/context -Headers $headers
$student = $context.students | Where-Object { $_.name -eq 'Ana Castanheira' } | Select-Object -First 1

$payload = @{
  class_id = $student.class_id
  student_id = $student.id
  pin = '4827'
} | ConvertTo-Json

Invoke-RestMethod -Uri http://localhost:8000/v1/totem/students/login -Method Post -Headers $headers -ContentType 'application/json' -Body $payload
```

Se funcionar, a resposta tera:

```text
token_type: bearer
student.name: Ana Castanheira
```

## Parar os servicos

Para parar apenas o backend:

```powershell
docker compose down
```

Para parar o Supabase local:

```powershell
supabase stop
```

## Resumo do ritual diario

Quando quiser testar o projeto de novo:

```powershell
cd C:\Users\Predeus\Documents\BinGo\Software
supabase start
docker compose up -d backend-dev
cd apps\totem_simulator
python -m http.server 8001
```

Depois abra:

```text
http://localhost:8001
```
