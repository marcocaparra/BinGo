# Supabase Edge Functions MVP — descarte e pontuação

Revisão: `2026-08-13`

Status: schema, contrato, RPC PostgreSQL, autenticação técnica e Edge Function HTTP implementados e comprovados localmente. Não há comprovação de deploy no Supabase hospedado.

## Arquitetura

```text
Totem autenticado
  → Edge Function valida X-Machine-Id e X-Api-Key
  → Edge chama register_deposit_v1 com service_role
  → RPC valida relações, categoria e idempotência
  → RPC grava evento, saldos e auditoria na mesma transação
  → Edge devolve a fotografia persistida
```

A Edge Function não deve executar vários `insert` e `update` independentes. Sua responsabilidade é autenticação técnica, validação de forma, chamada da RPC e tradução controlada de erros. A regra de negócio crítica fica no PostgreSQL para que `event_id`, saldos e auditoria compartilhem a mesma transação.

## Fundação de autenticação técnica

`supabase/functions/_shared/machine-auth.ts` fornece `authenticateMachine(request)` e `withMachineAuthentication(handler)`. O primeiro valida `X-Machine-Id` e `X-Api-Key`, consulta `machines` com o cliente administrativo server-side e devolve somente a identidade imutável `{ id, schoolId }`. O segundo envolve handlers futuros e padroniza respostas sem expor `api_key_hash`, service role ou erros do PostgREST.

O cliente administrativo é criado de forma lazy com `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`, disponíveis somente no ambiente seguro da Function. A consulta seleciona apenas `id`, `school_id` e `api_key_hash`. O hash continua no formato produzido pelo FastAPI e pelas seeds: PBKDF2-HMAC-SHA256, salt em base64, 120.000 iterações e digest de 32 bytes.

A migration de suporte concede a `service_role` somente `SELECT (id, school_id, api_key_hash)` em `machines`. Ela não concede `SELECT` amplo, escrita ou leitura de outras colunas. `anon` e `authenticated` continuam sem acesso a `api_key_hash`; esses limites são cobertos por pgTAP.

O módulo compara a API key recebida sem chamar `trim()` ou aplicar outra normalização. Isso diverge conscientemente do `strip()` do FastAPI; as chaves atuais conhecidas, sem espaços nas extremidades, permanecem válidas. O runtime Fetch pode normalizar whitespace de headers antes da execução do módulo, comportamento externo que não é contornado. Nenhum bloqueio usa `machines.status`.

Todas as falhas de credencial retornam HTTP `401` com `MACHINE_AUTHENTICATION_FAILED`, inclusive UUID malformado e máquina inexistente. Falhas de infraestrutura retornam HTTP `500` com `INTERNAL_ERROR`. O corpo nunca informa se o UUID existe.

O módulo não lê o body e não deriva autoridade de `machine_id` ou `school_id` enviados pelo cliente. Esse isolamento é apenas responsabilidade da autenticação; cada futura Function HTTP deverá rejeitar explicitamente esses campos em seu próprio schema.

No Orange Pi, a API key pertence ao serviço local, nunca ao frontend kiosk. O serviço carrega o segredo por configuração protegida e acrescenta os headers técnicos ao fazer a chamada remota. No MVP, a revogação ocorre substituindo ou removendo `machines.api_key_hash`; não há múltiplas chaves, expiração ou rotação automática.

## Entrada da Function

O nome físico é `register-deposit-v1` e a URL local é `POST http://127.0.0.1:54321/functions/v1/register-deposit-v1`. Esse caminho implementa hoje o contrato conceitual `POST /v1/deposits`; nenhum alias de gateway foi criado. Métodos diferentes de `POST` recebem `405` antes da autenticação. A Function não implementa CORS nesta etapa e não introduz credencial técnica no Totem Web.

O corpo aceita `event_id`, `class_id`, `student_id`, `is_valid`, `detected_type`, `waste_category_code` e `category_source`. A máquina e a escola são derivadas da credencial técnica. `size`, valores de recompensa, taxa e bônus são proibidos.

Para descarte válido, a categoria deve existir, estar ativa e respeitar sua origem. `UNKNOWN/UNIDENTIFIED` representa lixo eletrônico aceito cuja classe não pôde ser determinada. Para descarte inválido, categoria e origem são nulas.

## Chamada da RPC

```ts
const { data, error } = await supabase.rpc("register_deposit_v1", {
  p_event_id: body.event_id,
  p_machine_id: machine.id,
  p_class_id: body.class_id,
  p_is_valid: body.is_valid,
  p_student_id: body.student_id ?? null,
  p_detected_type: body.detected_type ?? null,
  p_waste_category_code: body.waste_category_code ?? null,
  p_category_source: body.category_source ?? null,
});
```

A chamada usa um cliente server-side com `service_role`. A chave deve permanecer em secret da Function. A função PostgreSQL revoga execução de `anon` e `authenticated`, define `search_path = ''` e qualifica explicitamente todas as relações.

## Pontuação

`school_settings` fornece 8 BinCoins de base, 19 XP e meta semanal de 100 XP por padrão. O bônus individual é arredondado ao inteiro mais próximo e somado à base. O XP não recebe multiplicador.

O catálogo de produção nasce com taxas zero. A matriz `BATTERY 100%`, `MOBILE_DEVICE 50%` e `CABLE_WIRE 25%` existe somente nas seeds de desenvolvimento. A Edge Function nunca contém essa matriz em código.

## Idempotência e concorrência

`deposits.event_id` é único. Um replay sequencial retorna o registro existente antes de consultar a taxa atual, preservando a fotografia mesmo se a categoria tiver sido alterada ou desativada. Em disputa concorrente, `INSERT ... ON CONFLICT DO NOTHING` faz apenas uma chamada vencer; a perdedora lê o evento já persistido. Payload divergente para o mesmo identificador resulta em conflito.

## Erros esperados

A Edge mapeia qualquer falha de autenticação técnica para `401` com `MACHINE_AUTHENTICATION_FAILED`, contrato inválido para `422`, categoria inexistente/inativa para `404`, contexto inexistente ou fora da escola uniformemente para `404` e colisão semântica de `event_id` para `409`. Esses mapeamentos foram fixados depois de testes da RPC comprovarem `23503`, `23505`, `23514` e `P0002`. Erros internos usam `500/INTERNAL_ERROR` sem expor SQL, PostgREST, hashes ou a chave técnica.

Uma criação responde `201`; um retry idêntico responde `200` com a mesma fotografia. O marcador interno `was_replayed` não é exposto ao cliente.

## Validação antes do deploy

O replay completo local executa `supabase db reset`, `supabase test db`, formatação, lint, tipos, testes Deno e a integração HTTP. A inspeção de efeitos usa conexão administrativa exclusiva do banco local de teste, sem ampliar os privilégios de produção da `service_role`. A prova cobre criação, replay, conflito e duas requisições concorrentes para o mesmo `event_id`, verificando um único depósito, uma única auditoria e uma única aplicação de saldo. Antes de qualquer deploy, ainda é obrigatório comparar `supabase migration list` com o projeto vinculado.
