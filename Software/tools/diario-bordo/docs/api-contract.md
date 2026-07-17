# Contrato da API

## Convenções

- Base pública definida por `VITE_API_BASE_URL` no frontend.
- Corpo e resposta: `application/json`, exceto exportação Markdown.
- Datas civis: `YYYY-MM-DD`; a data oficial usa `America/Sao_Paulo`.
- Rotas protegidas recebem `Authorization: Bearer <token>`.
- O token expira em oito horas e não contém o PIN.
- Erros usam o formato JSON padronizado pelo `GlobalExceptionHandler`.

## Autenticação

`POST /auth/access` recebe `{ "role": "TEAM|ADMIN", "pin": "000000" }` e
devolve `{ "role", "token", "expiresAt" }`. Depois de dez falhas no mesmo IP,
novas tentativas ficam bloqueadas por quinze minutos.

## Endpoints

| Método | Rota | Acesso | Objetivo |
| --- | --- | --- | --- |
| `GET` | `/health` | Público | Verificar disponibilidade da API |
| `POST` | `/auth/access` | Público | Abrir uma sessão temporária |
| `GET` | `/members` | Equipe ou coordenação | Listar integrantes ativos |
| `GET` | `/reports` | Equipe ou coordenação | Listar e filtrar registros |
| `POST` | `/reports/today` | Equipe ou coordenação | Registrar o diário do dia |
| `GET` | `/reports/exists` | Equipe ou coordenação | Verificar registro por integrante e data |
| `PUT` | `/reports/{id}` | Coordenação | Editar um registro |
| `DELETE` | `/reports/{id}` | Coordenação | Excluir um registro para permitir novo preenchimento |
| `POST` | `/reports/no-activity` | Equipe ou coordenação | Registrar ausência de atividade |
| `GET` | `/reports/pending` | Coordenação | Listar pendências do dia |
| `GET` | `/reports/export` | Coordenação | Baixar o relatório em Markdown |

Uploads e downloads de anexos permanecem no contrato para uma futura etapa com
armazenamento externo, mas retornam erro quando `ATTACHMENTS_ENABLED=false`.
No lançamento gratuito, evidências devem ser informadas como texto e links.

## Regras observáveis

- integrante inexistente resulta em `404`;
- campos inválidos resultam em `400`;
- segundo registro para integrante e data resulta em `409`;
- data futura é recusada mesmo quando enviada diretamente à API;
- token ausente, inválido ou expirado resulta em `401`;
- permissão insuficiente resulta em `403`;
- limite de tentativas de login resulta em `429`.
