# Database do Diário de Bordo Coletivo

Esta pasta contém exclusivamente o schema e os dados iniciais do mini projeto
Diário de Bordo Coletivo. As tabelas usam o prefixo `diary_` para explicitar
esse limite e reduzir o risco de colisão com outros sistemas.

> Não aplique estes scripts no banco principal do BinGo. Prefira um projeto ou
> banco PostgreSQL/Supabase separado para o Diário de Bordo.

## Arquivos

### Migrations

- `migrations/001_create_diary_schema.sql`: cria a extensão de UUID, o enum de
  status, a função de auditoria, as tabelas, constraints, triggers e índices.

### Seeds

- `seeds/001_initial_diary_members.sql`: cadastra os seis integrantes iniciais
  sem duplicar nomes existentes. Nenhum relatório mockado é inserido.

## Ordem de execução

1. Execute `migrations/001_create_diary_schema.sql`.
2. Verifique a criação de `diary_members` e `diary_reports`.
3. Execute `seeds/001_initial_diary_members.sql`.
4. Confira os integrantes com uma consulta somente de leitura:

```sql
SELECT id, name, default_area, role, is_active
FROM diary_members
ORDER BY name;
```

## Aplicar pelo Supabase SQL Editor

No projeto Supabase exclusivo do Diário de Bordo:

1. abra o SQL Editor;
2. copie todo o conteúdo da migration e execute;
3. copie todo o conteúdo do seed e execute;
4. confirme o resultado da consulta de verificação acima.

## Aplicar com um cliente PostgreSQL

Com `psql` e uma URL de conexão fornecida apenas no ambiente local:

```bash
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f migrations/001_create_diary_schema.sql
psql "$POSTGRES_URL" -v ON_ERROR_STOP=1 -f seeds/001_initial_diary_members.sql
```

Execute os comandos a partir desta pasta. Não coloque a URL ou a senha real em
scripts, documentação, commits ou arquivos versionados.

## RLS e acesso

Row Level Security não está ativado nesta V1. A arquitetura prevê que somente
o backend Spring Boot acesse o PostgreSQL; o frontend não se conecta ao banco
diretamente.

Se uma versão futura permitir acesso direto do frontend ao Supabase, será
obrigatório ativar RLS e definir policies antes de expor as tabelas.

## Cuidados

- Nunca execute reset, drop ou limpeza de dados sem autorização explícita.
- Nunca versione credenciais reais.
- Aplique migrations na ordem numérica e apenas uma vez por ambiente.
- Faça backup antes de alterar um ambiente que já contenha dados reais.
