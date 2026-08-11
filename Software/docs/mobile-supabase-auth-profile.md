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

> **Aviso de baseline — 2026-08-10:** este documento registrava uma entrega feita em outra linha de desenvolvimento. A branch `feature/supabase-edge-functions-mvp` contém o cliente Mobile de Supabase Auth, mas não contém `supabase/migrations/20260802120000_mobile_profile_rls.sql`, `supabase/tests/mobile_profile_rls.sql` nem a fixture `database/seeds/009_seed_mobile_authenticated_demo_domain.sql`. As instruções históricas abaixo que dependem desses arquivos não comprovam funcionamento no baseline atual.

Com Supabase CLI e Docker disponíveis:

```powershell
supabase start
supabase db reset
```

O reset aplica somente as migrations que realmente existem em `supabase/migrations/`. No baseline atual, isso **não inclui** RLS mínima de perfil. A migration histórica precisa ser recuperada ou recriada e validada em uma tarefa própria antes de qualquer leitura direta do perfil.

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

Teste SQL comportamental histórico de RLS contra Supabase local já migrado:

```powershell
psql <local-postgres-url> -v ON_ERROR_STOP=1 -f supabase/tests/mobile_profile_rls.sql
```

O arquivo `supabase/tests/mobile_profile_rls.sql` não existe no baseline atual. A versão histórica usava transação com rollback e validava leitura própria, bloqueio de outro aluno, escola/turma relacionadas, bloqueio de alteração de saldo, bloqueio do papel anônimo e ausência de exposição para identidade sem vínculo. Esses cenários continuam sendo requisitos para o teste a recuperar ou recriar, não evidência de teste disponível nesta branch.

## Limitações e decisões de segurança

- A intenção histórica da leitura remota usa `students`, `classes` e `schools`; grants e policies correspondentes não estão comprovados no baseline atual.
- Não há Edge Function nesta etapa.
- A FK de `students.auth_user_id` para `auth.users.id` não foi criada sem validar previamente os registros do projeto remoto.
- O indicador de restauração autenticada em `SharedPreferences` não contém sessão nem credenciais. O SDK do Supabase gerencia a sessão.
- Sessão inválida retorna à entrada. Erro de rede permanece erro e oferece nova tentativa; nenhum desses estados ativa o piloto.
- Níveis, conquistas, BinCoins e métricas ambientais são declarados indisponíveis no perfil autenticado, pois não existem no modelo consultado por esta integração.
