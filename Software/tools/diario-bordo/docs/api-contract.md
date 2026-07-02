# Contrato inicial da API

Documento de planejamento. Os endpoints serão implementados por etapas e
podem receber pequenos ajustes durante a definição dos DTOs.

## Convenções

- Base da API: `/` nesta fase.
- Corpo e resposta: `application/json`.
- Datas civis: formato ISO `YYYY-MM-DD`.
- Instantes: ISO 8601 com offset.
- A data corrente é calculada no backend em `America/Sao_Paulo`.
- Entidades JPA não fazem parte do contrato público.

Erros de validação e de regra de negócio terão uma estrutura JSON comum,
definida junto ao `GlobalExceptionHandler`.

## Endpoints da V1

| Método | Rota | Objetivo | Estado |
| --- | --- | --- | --- |
| `GET` | `/health` | verificar disponibilidade da API | planejado |
| `GET` | `/members` | listar integrantes | planejado |
| `POST` | `/members` | cadastrar integrante | planejado |
| `GET` | `/reports` | listar e filtrar relatórios | planejado |
| `POST` | `/reports/today` | registrar atividade de hoje | planejado |
| `PUT` | `/reports/{id}` | editar relatório existente | planejado |
| `GET` | `/reports/pending` | calcular relatórios pendentes | planejado |
| `POST` | `/reports/no-activity` | registrar ausência de atividade | planejado |

Filtros previstos em `GET /reports`: `memberId`, `area`, `date` e `status`.

### Campos essenciais de criação

Um relatório de atividade receberá, no mínimo:

- `memberId`;
- `area`;
- `title`;
- `description`.

O cliente não enviará a data para `/reports/today`; o backend preencherá a
data oficial. Problemas, solução, próximos passos e links de evidência serão
opcionais.

## Regras observáveis pela API

- membro inexistente resulta em erro de recurso não encontrado;
- campos inválidos resultam em erro de validação;
- segundo relatório para o mesmo integrante e data resulta em conflito;
- editar um relatório não cria uma nova linha;
- `NO_ACTIVITY` ocupa o registro diário do integrante e impede duplicidade.

## Endpoints futuros

| Método | Rota | Objetivo |
| --- | --- | --- |
| `POST` | `/auth/access` | validar a senha coletiva |
| `GET` | `/exports/xlsx` | exportar os registros para planilha |
