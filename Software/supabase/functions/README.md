# Fundação compartilhada das Edge Functions

Este diretório contém código server-side reutilizável pelas futuras Supabase
Edge Functions. Ele ainda não expõe uma Function HTTP implantável.

`_shared/machine-auth.ts` autentica `X-Machine-Id` e `X-Api-Key`, consulta a
máquina com um cliente Supabase de service role e entrega ao handler somente a
identidade imutável `{ id, schoolId }`. O módulo nunca lê do body a autoridade
da máquina ou da escola.

As credenciais do runtime vêm exclusivamente de `SUPABASE_URL` e
`SUPABASE_SERVICE_ROLE_KEY`. Arquivos `.env` locais são ignorados e não podem
ser versionados.

Execute a suíte determinística com `deno task test`. O teste local de
integração, somente leitura, é ativado por `BINGO_EDGE_AUTH_INTEGRATION=1` e
exige no ambiente do processo `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`BINGO_EDGE_TEST_MACHINE_ID`, `BINGO_EDGE_TEST_API_KEY` e
`BINGO_EDGE_TEST_SCHOOL_ID`.
