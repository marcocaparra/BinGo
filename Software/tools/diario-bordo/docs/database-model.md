# Modelo de dados

Este documento descreve o modelo inicial. Os nomes e tipos definitivos serão
formalizados pela primeira migration SQL.

## `members`

Representa um integrante do grupo.

| Coluna | Tipo sugerido | Regra |
| --- | --- | --- |
| `id` | `BIGINT` | chave primária gerada |
| `name` | `VARCHAR(120)` | obrigatório |
| `area` | `VARCHAR(80)` | obrigatório |
| `is_active` | `BOOLEAN` | obrigatório, padrão `TRUE` |

## `daily_reports`

Representa o registro de um integrante em uma data.

| Coluna | Tipo sugerido | Regra |
| --- | --- | --- |
| `id` | `BIGINT` | chave primária gerada |
| `member_id` | `BIGINT` | FK obrigatória para `members.id` |
| `report_date` | `DATE` | obrigatório |
| `area` | `VARCHAR(80)` | obrigatório |
| `title` | `VARCHAR(160)` | obrigatório |
| `description` | `TEXT` | obrigatório |
| `problems` | `TEXT` | opcional |
| `solution` | `TEXT` | opcional |
| `next_steps` | `TEXT` | opcional |
| `evidence_links` | a definir na migration | lista opcional de URLs |
| `status` | `VARCHAR(30)` | obrigatório |
| `submitted_at` | `TIMESTAMPTZ` | obrigatório |
| `created_at` | `TIMESTAMPTZ` | obrigatório |
| `updated_at` | `TIMESTAMPTZ` | obrigatório |

Status aceitos inicialmente:

- `SUBMITTED`: enviado na data do relatório;
- `SUBMITTED_LATE`: enviado depois da data do relatório;
- `NO_ACTIVITY`: integrante declarou não ter realizado atividade.

## Integridade

A restrição central do modelo é:

```sql
UNIQUE (member_id, report_date)
```

Ela garante, inclusive sob requisições concorrentes, no máximo um relatório
por integrante e data. A aplicação também validará a duplicidade para retornar
uma mensagem clara, mas o banco continua sendo a garantia final.

Pendências não serão armazenadas como linhas: serão calculadas pela ausência
de relatório de um integrante ativo na data consultada.
