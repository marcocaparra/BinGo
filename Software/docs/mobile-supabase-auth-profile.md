# Mobile: Supabase Auth e perfil autenticado

## Escopo atual

O Mobile possui dois caminhos isolados:

- modo piloto: explícito, local, sem autenticação e sem acesso ao Supabase;
- conta demo autenticada: e-mail/senha no Supabase Auth e leitura remota somente do perfil.

Recompensas, histórico, ranking, carteira, missões, impacto e resgates continuam simulados exclusivamente dentro do modo piloto. Eles não são exibidos no fluxo autenticado.

## Configuração do Flutter

O app espera estes valores de build:

- `SUPABASE_URL`: URL do projeto;
- `SUPABASE_PUBLISHABLE_KEY`: chave pública apropriada para aplicações cliente.

Não use `service_role` nem outra credencial privilegiada no Flutter.

Modo piloto, sem configuração Supabase:

```powershell
cd mobile/bingo_app
flutter pub get
flutter run
```

Modo autenticado:

```powershell
cd mobile/bingo_app
flutter run --dart-define=SUPABASE_URL=<url> --dart-define=SUPABASE_PUBLISHABLE_KEY=<public-key>
```

Sem os dois `dart-define`, o piloto continua disponível e a tentativa de login real mostra erro explícito. O cliente Supabase é criado sob demanda; abrir o piloto não o inicializa.

## Banco local e migrations

O baseline backend de autorização foi recriado por migrations versionadas em `database/migrations` e `supabase/migrations`. Ele habilita RLS nas tabelas de domínio e permite a `authenticated` somente a leitura do próprio registro em `students`, da própria turma em `classes` e da própria escola em `schools`. Esta entrega não alterou o Flutter nem substituiu mocks do Mobile.

Com Supabase CLI e Docker disponíveis:

```powershell
supabase start
supabase db reset
```

O reset aplica as migrations existentes em `supabase/migrations/`, incluindo o baseline atual de Auth/RLS. O vínculo continua sendo provisionado por `students.auth_user_id`; usuário Auth sem aluno associado recebe resultado vazio, e aluno sem `auth_user_id` não é visível por uma sessão autenticada.

Historicamente, a fixture de domínio era executada de forma explícita em desenvolvimento com o comando abaixo. O arquivo referenciado não existe no baseline atual; o comando fica preservado apenas como registro e não deve ser tratado como executável nesta branch:

```powershell
psql <local-postgres-url> -v ON_ERROR_STOP=1 -c "set bingo.seed_environment = 'development'" -f database/seeds/009_seed_mobile_authenticated_demo_domain.sql
```

Use `staging` no lugar de `development` somente no ambiente correspondente. Qualquer outro valor, ou valor ausente, faz a fixture abortar. A fixture usa IDs determinísticos, faz upsert transacional e não apaga dados.

## Provisionamento da conta demo

1. Crie o usuário de e-mail/senha pelo painel administrativo do Supabase Auth no ambiente de desenvolvimento ou staging. Não coloque a senha em migration, seed ou código.
2. Copie o UUID do usuário criado.
3. Vincule o UUID somente ao aluno determinístico da fixture:

```sql
update public.students
set auth_user_id = '<auth-user-uuid>',
    updated_at = now()
where id = '31000000-0000-4000-8000-000000000001';
```

4. Confirme que exatamente uma linha foi alterada e que nenhum outro aluno usa esse UUID.

Não foi criado script com `service_role`: para uma única conta técnica, o provisionamento manual inicial é a alternativa menos invasiva. Caso isso precise ser automatizado, o script futuro deverá ser local, explícito, protegido por ambiente e nunca importado pelo Flutter.

## Testes

Testes Flutter, sem internet:

```powershell
cd mobile/bingo_app
flutter test test/access_flow_test.dart test/session_gate_test.dart test/profile_repository_test.dart test/profile_screen_test.dart
```

O baseline estrutural é validado junto da suíte pgTAP:

```powershell
supabase test db
```

`supabase/functions/tests/authorization-rls.integration.test.ts` complementa a inspeção estática com usuários reais do Supabase Auth local. Ele valida leitura própria, isolamento de outro aluno e de outra escola, escola/turma relacionadas, identidade sem vínculo, bloqueio de alterações críticas, bloqueio de dados privados para `anon`, catálogo público e privilégios mínimos de `service_role`. Sua execução é opt-in por `BINGO_AUTH_RLS_INTEGRATION=1` e exige apenas credenciais do ambiente local de teste.

## Limitações e decisões de segurança

- O baseline comprova grants e policies de `students`, `classes` e `schools`, mas a integração do App e as demais áreas simuladas permanecem fora desta entrega.
- Leituras simples usam Supabase Auth e RLS; operações críticas continuam reservadas às Edge Functions e RPCs.
- A FK de `students.auth_user_id` para `auth.users.id` não foi criada sem validar previamente os registros do projeto remoto.
- O indicador de restauração autenticada em `SharedPreferences` não contém sessão nem credenciais. O SDK do Supabase gerencia a sessão.
- Sessão inválida retorna à entrada. Erro de rede permanece erro e oferece nova tentativa; nenhum desses estados ativa o piloto.
- Níveis, conquistas, BinCoins e métricas ambientais são declarados indisponíveis no perfil autenticado, pois não existem no modelo consultado por esta integração.
