# Supabase Edge Functions

Este diretório contém a fundação compartilhada e a primeira Function HTTP
implantável do BinGo. `_shared/machine-auth.ts` autentica `X-Machine-Id` e
`X-Api-Key`, consulta somente `id`, `school_id` e `api_key_hash` com
`service_role` e entrega ao handler a identidade imutável `{ id, schoolId }`. O
segredo administrativo vem exclusivamente de `SUPABASE_URL` e
`SUPABASE_SERVICE_ROLE_KEY` no ambiente seguro do runtime.

`register-deposit-v1` atende localmente em
`POST http://127.0.0.1:54321/functions/v1/register-deposit-v1`. Ela valida o
método antes da autenticação, rejeita campos extras, não aceita autoridade ou
recompensa do body e faz uma única chamada a `register_deposit_v1`. Criação
responde `201` e replay idêntico responde `200`. Não há CORS implementado na
Function.

Execute `deno task fmt:check`, `deno task lint`, `deno task check` e
`deno task test` com Deno 2. Para integração local, inicie
`supabase functions serve --no-verify-jwt` e execute
`deno task test:integration` com `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`BINGO_EDGE_TEST_MACHINE_ID`, `BINGO_EDGE_TEST_API_KEY`,
`BINGO_EDGE_TEST_SCHOOL_ID`, `BINGO_EDGE_DEPOSIT_URL` e
`BINGO_EDGE_TEST_DATABASE_URL`. A URL de banco é usada somente pelo teste para
inspecionar efeitos persistidos sem ampliar as permissões de produção da
`service_role`.
