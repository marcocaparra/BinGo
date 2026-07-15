# Database do Diário de Bordo Coletivo

Esta pasta contém exclusivamente o schema e os dados iniciais do mini projeto
Diário de Bordo Coletivo. As tabelas usam o prefixo `diary_` para explicitar
esse limite e reduzir o risco de colisão com outros sistemas.

> Não aplique estes scripts no banco principal do BinGo. Prefira um projeto ou
> banco PostgreSQL/Supabase separado para o Diário de Bordo.

## Arquivos

### Migrations

- `V1` cria a estrutura inicial;
- `V2` a `V5` evoluem relatórios e anexos;
- `V6` cadastra os integrantes iniciais sem inserir relatórios fictícios.

## Ordem de execução

O Spring Boot aplica automaticamente as migrations `V1` a `V6` com Flyway ao
iniciar. Em um banco vazio, não execute esses arquivos manualmente. Depois do
primeiro início, confira os integrantes com uma consulta somente de leitura:

```sql
SELECT id, name, default_area, role, is_active
FROM diary_members
ORDER BY name;
```

O histórico fica na tabela `flyway_schema_history`. Não coloque URL ou senha
real em scripts, documentação, commits ou arquivos versionados.

## RLS e acesso

Row Level Security não está ativado nesta V1. A arquitetura prevê que somente
o backend Spring Boot acesse o PostgreSQL; o frontend não se conecta ao banco
diretamente.

Se uma versão futura permitir acesso direto do frontend ao Supabase, será
obrigatório ativar RLS e definir policies antes de expor as tabelas.

## Cuidados

- Nunca execute reset, drop ou limpeza de dados sem autorização explícita.
- Nunca versione credenciais reais.
- Nunca edite uma migration já aplicada; crie a próxima versão `Vn__descricao.sql`.
- Faça backup antes de alterar um ambiente que já contenha dados reais.
