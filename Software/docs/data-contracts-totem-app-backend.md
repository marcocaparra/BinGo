# Contrato Totem, App e backend — descarte V1

Revisão: `2026-09-15`

Este contrato define o evento entregue pelo Totem e a resposta oficial da camada server-side. O cliente descreve o ciclo físico e a classificação final; somente o servidor calcula BinCoins, bônus e XP.

A unidade oficial aprovada foi redenominada por fator `100`: `8` BinCoins antigos correspondem a `800` BinCoins novos e `19` XP antigos correspondem a `1900` XP novos. A relação econômica não mudou, e isso não é formatação de frontend. A migration está versionada e validada localmente e foi aplicada e aprovada no postflight do `bingo-dev`; `register_deposit_v1` continua lendo as configurações persistidas e produz a nova unidade sem multiplicação no cliente. Este contrato não afirma aplicação ou validação em produção.

## Responsabilidades

O Totem autentica o aluno quando aplicável, conduz a classificação, permite confirmar ou corrigir a categoria, conclui o ciclo mecânico e só então envia o evento. A saída bruta mais relevante da visão permanece em `detected_type`; a decisão final usa um código de `waste_categories` e informa se foi confirmada, corrigida ou permaneceu não identificada.

A Edge Function autentica `X-Machine-Id` e `X-Api-Key`, ignora qualquer pretensão do cliente de definir escola, máquina ou pontuação e chama `register_deposit_v1`. A RPC deriva a escola da máquina e executa toda a gravação de forma atômica.

A fundação compartilhada em `supabase/functions/_shared` valida os headers, consulta a máquina com cliente server-side e entrega à Function somente a identidade imutável `{ id, schoolId }`. O módulo de autenticação não lê o body, e `register-deposit-v1` rejeita `machine_id`, `school_id` e qualquer outro campo fora do contrato.

## Requisição

```http
POST /v1/deposits
X-Machine-Id: <uuid>
X-Api-Key: <secret>
Content-Type: application/json
```

`POST /v1/deposits` é o caminho público conceitual. No roteamento nativo atualmente implementado, a chamada local é `POST http://127.0.0.1:54321/functions/v1/register-deposit-v1`. Ainda não existe alias de gateway entre esses caminhos.

```json
{
  "event_id": "uuid",
  "class_id": "uuid",
  "student_id": "uuid-ou-null",
  "is_valid": true,
  "detected_type": "mobile_phone",
  "waste_category_code": "MOBILE_DEVICE",
  "category_source": "AI_CONFIRMED"
}
```

Para evento válido, `waste_category_code` e `category_source` são obrigatórios. `UNKNOWN` usa `UNIDENTIFIED`; uma categoria conhecida usa `AI_CONFIRMED` ou `USER_CORRECTED`. Para evento inválido, os dois campos devem ser nulos ou omitidos. `student_id` pode ser nulo, mas `class_id` continua obrigatório.

Não fazem parte do contrato: `size`, `school_id`, `machine_id`, quantidade, BinCoins, XP, taxa ou bônus. Campos extras são rejeitados pelo backend de referência.

## Autenticação técnica

`X-Machine-Id` deve conter um UUID hifenizado e `X-Api-Key` deve estar presente e não vazio. O módulo não aplica `trim()`, mudança de caixa ou normalização Unicode à API key. Essa é uma divergência deliberada do FastAPI de referência, que aplica `strip()`; as credenciais atuais conhecidas não possuem espaços nas extremidades e continuam compatíveis. A implementação ainda está sujeita à normalização de whitespace que o próprio padrão Fetch realiza ao construir `Headers`, antes de o valor chegar ao módulo.

A busca server-side lê somente `id`, `school_id` e `api_key_hash`. O formato persistido permanece `base64(salt)$base64(PBKDF2-HMAC-SHA256)`, com 120.000 iterações. Máquina inexistente, UUID malformado, header ausente, hash ausente ou inválido e chave incorreta produzem a mesma resposta, sem revelar se o identificador existe:

A `service_role` recebe somente `SELECT` nessas três colunas de `machines`; não recebe escrita nem leitura das demais colunas por essa permissão. `anon` e `authenticated` não recebem acesso a `api_key_hash`.

```json
{
  "error": {
    "code": "MACHINE_AUTHENTICATION_FAILED",
    "message": "Credenciais técnicas inválidas."
  }
}
```

Essa resposta usa HTTP `401`. Falhas internas usam HTTP `500` com o código público `INTERNAL_ERROR`, sem detalhes de banco, hash ou configuração.

## Readiness central

O contrato conceitual `GET /health` está materializado localmente como `GET http://127.0.0.1:54321/functions/v1/health-v1` e exige os mesmos headers técnicos. Ele avalia somente a parcela central necessária ao início de um descarte: chegada ao runtime, autenticação técnica pela Data API e PostgreSQL operacional em condição gravável detectável por consulta somente leitura.

```json
{
  "status": "AVAILABLE",
  "can_start_deposit": true,
  "scope": "CENTRAL_BACKEND",
  "checked_at": "2026-08-15T12:00:00.000Z"
}
```

Somente HTTP `200` com `AVAILABLE` e `can_start_deposit = true` autoriza o consumidor a considerar o backend central saudável. Um readiness negativo comprovado pelo handler retorna HTTP `503`, `UNAVAILABLE` e `can_start_deposit = false`. Credencial inválida retorna `401` e não é convertida em estado de saúde. Timeout, ausência de resposta, HTTP `500` ou qualquer outra falha também são fail-closed, pois a autenticação pode falhar antes que a RPC consiga produzir um `503` confiável.

O contrato não testa IA, turma, categoria ou regras de negócio e não implementa polling, estado do Orange Pi ou `/local/status`. A integração com o futuro serviço local permanece pendente e separada.

## Resposta

```json
{
  "id": "uuid",
  "event_id": "uuid",
  "waste_category_code": "MOBILE_DEVICE",
  "category_source": "AI_CONFIRMED",
  "bonus_rate_applied": "0.5000",
  "bonus_bincoins_awarded": 400,
  "points_awarded_student": 1200,
  "points_awarded_class": 1900,
  "created_at": "2026-08-12T12:00:00Z"
}
```

O exemplo acima representa a unidade oficial após a redenominação, com bônus de `50%`. Os números efetivamente retornados são sempre a fotografia persistida, não uma simulação nem uma multiplicação visual do cliente. No `bingo-dev`, respostas e históricos persistidos já usam a unidade nova; outros ambientes só podem ser considerados convertidos mediante evidência própria. Consultas de histórico devem exibir o total e podem separar o bônus usando `bonus_bincoins_awarded`.

A primeira criação retorna HTTP `201`. Um replay idêntico retorna HTTP `200` com a mesma fotografia e sem reaplicar saldos ou auditoria.

## Regras de recompensa

Com aluno identificado, evento válido concede a base configurada mais `round(base × bonus_rate)`. A regra-alvo usa base `800` BinCoins e `1900` XP; sem aluno, concede `0` BinCoins e o XP normal. Evento inválido concede `0/0`. A categoria jamais altera o XP.

`bonus_rate` continua percentual e não é multiplicado por `100`. Assim, base `800` com taxa `0.50` produz bônus `400` e total `1200`. A redenominação de bases, saldos, snapshots e custos relacionados está implementada e validada localmente e aplicada no `bingo-dev`; o postflight comprovou defaults `800/1900/10000`, preservação literal do audit log histórico e criação de `POINTS_UNIT_REDENOMINATED_V1`. Em 2026-09-15, o Mobile autenticado já instalado no dispositivo, sem reinstalação nem novo `flutter run`, exibiu os valores hospedados na nova unidade. Nenhuma dessas evidências comprova produção. Para eventual aplicação em outro ambiente, novos descartes e resgates deverão ser suspensos e as transações em voo deverão terminar antes da migration.

As taxas da migration são zero em todos os ambientes. As seeds locais usam provisoriamente 100% para bateria, 50% para dispositivo móvel e 25% para cabo ou fio. Esses números servem para desenvolvimento e teste; não são política ambiental aprovada de produção.

## Idempotência, erros e retry

O Totem cria um `event_id` por ciclo e o reutiliza após timeout. Repetição idêntica retorna o evento original e não altera saldos. O mesmo identificador com dados diferentes produz `409`. Contrato inválido produz `422`, categoria inexistente ou desativada produz `404`, e contexto inexistente ou fora da escola também produz `404` uniforme.

O Totem não confirma a recompensa antes da resposta server-side. Caso a queda física tenha ocorrido e a conexão seja perdida, o retry usa o mesmo identificador. Novos ciclos continuam bloqueados quando serviços críticos já estão indisponíveis.

## Segurança e histórico

Clientes não escrevem diretamente em `deposits`, `students`, `classes`, `audit_logs`, `school_settings` ou `waste_categories`. A RPC é exclusiva de `service_role`, e o segredo correspondente nunca é distribuído ao Totem ou ao App.

No Orange Pi, `X-Api-Key` fica fora do frontend e dos arquivos JavaScript da interface. O serviço local responsável pela comunicação remota carrega a credencial por variável de ambiente, arquivo protegido ou mecanismo seguro equivalente e adiciona o header ao chamar a Function. O frontend conversa com esse serviço local e não recebe o segredo.

No MVP, revogar uma máquina significa substituir `machines.api_key_hash` pelo hash de uma nova credencial ou remover seu valor. Não existe nesta etapa infraestrutura de múltiplas chaves, expiração ou rotação automática. O estado operacional da máquina não participa da autenticação técnica enquanto não houver decisão oficial correspondente.

O App consulta saldos e histórico de acordo com suas policies futuras, mas não recalcula eventos. A taxa, o bônus e os totais gravados no descarte preservam a decisão aplicada no momento do ciclo.
