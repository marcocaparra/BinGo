# Modelo de dados do Diário de Bordo

## Objetivo e isolamento

Este banco armazena integrantes e relatórios diários da ferramenta interna do
grupo BinGo. Ele não é o banco do produto principal do BinGo e suas migrations
não devem ser aplicadas nesse banco.

As tabelas recebem o prefixo `diary_` para deixar o domínio explícito e evitar
colisões. Ainda assim, a recomendação operacional é usar um projeto ou banco
PostgreSQL/Supabase exclusivo para o Diário de Bordo.

## Enum `diary_report_status`

Valores persistidos:

- `SUBMITTED`: relatório enviado na data correspondente;
- `SUBMITTED_LATE`: relatório enviado depois da data correspondente;
- `NO_ACTIVITY`: integrante declarou não ter realizado atividade.

`PENDING` não é salvo. Uma pendência é calculada quando um integrante ativo
não possui registro em `diary_reports` para a data consultada. Isso evita criar
linhas artificiais e mantém o histórico como registro de fatos ocorridos.

## Tabela `diary_members`

Representa os integrantes que podem preencher o diário.

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | `UUID` | PK, gerado com `gen_random_uuid()` |
| `name` | `VARCHAR(120)` | obrigatório, não vazio e único sem diferenciar maiúsculas |
| `default_area` | `VARCHAR(80)` | opcional; área sugerida no preenchimento |
| `role` | `VARCHAR(80)` | opcional; função principal no grupo |
| `is_active` | `BOOLEAN` | obrigatório, padrão `TRUE` |
| `created_at` | `TIMESTAMPTZ` | criação da linha |
| `updated_at` | `TIMESTAMPTZ` | atualizado automaticamente por trigger |

O índice único `ux_diary_members_name_lower` aplica a unicidade sobre
`LOWER(name)`, impedindo variações duplicadas apenas por capitalização.

## Tabela `diary_reports`

Representa um relatório ou uma declaração de ausência de atividade.

| Coluna | Tipo | Regra |
| --- | --- | --- |
| `id` | `UUID` | PK, gerado com `gen_random_uuid()` |
| `member_id` | `UUID` | FK obrigatória para `diary_members.id` |
| `report_date` | `DATE` | data civil do relatório |
| `area` | `VARCHAR(80)` | obrigatório e não vazio |
| `title` | `VARCHAR(160)` | obrigatório e não vazio |
| `description` | `TEXT` | obrigatório e não vazio |
| `problems` | `TEXT` | opcional |
| `solution` | `TEXT` | opcional |
| `next_steps` | `TEXT` | opcional |
| `evidence_links` | `TEXT` | URLs opcionais, uma por linha na V1 |
| `time_spent_minutes` | `INTEGER` | opcional e nunca negativo |
| `status` | `diary_report_status` | obrigatório |
| `submitted_at` | `TIMESTAMPTZ` | instante do envio |
| `created_at` | `TIMESTAMPTZ` | criação da linha |
| `updated_at` | `TIMESTAMPTZ` | atualizado automaticamente por trigger |

### Relacionamento e exclusão

`member_id` usa `ON DELETE RESTRICT`. Relatórios são históricos e não devem
ser apagados automaticamente quando um integrante for desativado ou quando
alguém tentar removê-lo. Na operação normal, integrantes devem ser desativados
com `is_active = FALSE`, não excluídos.

### Relatório único por integrante e data

A constraint central é:

```sql
CONSTRAINT uq_diary_reports_member_report_date
    UNIQUE (member_id, report_date)
```

Ela garante no próprio PostgreSQL que cada integrante tenha no máximo um
registro por dia, inclusive diante de requisições concorrentes. Um registro
`NO_ACTIVITY` também ocupa essa combinação e não pode coexistir com outro
relatório para o mesmo integrante e data.

## Evidências na V1

Evidências são links armazenados em `evidence_links`, com uma URL por linha.
Arquivos e imagens não são salvos no banco. A opção por `TEXT` mantém a V1
simples; uma estrutura normalizada poderá ser criada futuramente se surgirem
requisitos de busca ou metadados por evidência.

## Índices

Existem índices para as consultas previstas por:

- data do relatório;
- integrante e data;
- status;
- área.

## RLS

Row Level Security não está ativo na V1 porque o acesso será intermediado pelo
backend Spring Boot. Se o frontend passar a consultar o Supabase diretamente,
RLS e policies adequadas deverão ser implementados antes dessa mudança.
