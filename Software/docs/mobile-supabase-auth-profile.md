# Mobile: Supabase Auth e perfil autenticado

## Escopo atual

O Mobile possui dois caminhos isolados:

- modo piloto: explícito, local, sem autenticação e sem acesso ao Supabase;
- conta autenticada: e-mail/senha no Supabase Auth e leitura remota do próprio perfil, turma e escola.

O perfil autenticado reutiliza o frontend final somente para nome, escola, turma, saldo individual de BinCoins e XP da turma. `students.points_student_balance` representa BinCoins no V1, e `classes.points_class_balance` representa XP da turma. Não existe um saldo separado de pontos pessoais.

Recompensas, histórico, ranking, extrato/carteira, missões, níveis, conquistas, impacto e resgates continuam simulados exclusivamente dentro do modo piloto. Eles não são exibidos no fluxo autenticado.

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

O baseline backend de autorização foi recriado por migrations versionadas em `database/migrations` e `supabase/migrations`. Ele habilita RLS nas tabelas de domínio e permite a `authenticated` somente a leitura do próprio registro em `students`, da própria turma em `classes` e da própria escola em `schools`.

O Flutter implementa esse recorte com `SupabaseAuthGateway`, `RemoteProfileRepository` e `SupabaseProfileDataSource`. A consulta de `students` explicita `auth_user_id == currentUser.id`, sem substituir a RLS como autoridade de segurança. O repository deriva `class_id` e `school_id`, lê as relações permitidas e rejeita turma de outra escola ou dados obrigatórios malformados.

Com Supabase CLI e Docker disponíveis:

```powershell
supabase start
supabase db reset
```

O reset aplica as migrations existentes em `supabase/migrations/`, incluindo o baseline atual de Auth/RLS. O vínculo continua sendo provisionado por `students.auth_user_id`; usuário Auth sem aluno associado recebe resultado vazio, e aluno sem `auth_user_id` não é visível por uma sessão autenticada.

Em `2026-09-04`, o projeto hospedado `bingo-dev` (`ddxmohrjcxuibswmrtla`) possuía as nove migrations atuais do repositório e as Edge Functions `register-deposit-v1` e `health-v1` ativas. A seed `database/seeds/010_bingo_dev_demo_dataset.sql` foi aplicada uma única vez e deixou o conjunto demo com sete turmas e setenta alunos, dez alunos determinísticos por turma. O aluno smoke permaneceu vinculado ao Supabase Auth com `16` BinCoins, sua turma preservou `19` XP, e o depósito e o audit log preexistentes permaneceram únicos. O postflight confirmou que a seed não alterou usuários Auth, RLS, policies, migrations ou Edge Functions e não criou depósitos, resgates, recompensas ou logs adicionais.

Historicamente, a fixture de domínio era executada de forma explícita em desenvolvimento com o comando abaixo. O arquivo referenciado não existe no baseline atual; o comando fica preservado apenas como registro e não deve ser tratado como executável nesta branch:

```powershell
psql <local-postgres-url> -v ON_ERROR_STOP=1 -c "set bingo.seed_environment = 'development'" -f database/seeds/009_seed_mobile_authenticated_demo_domain.sql
```

Use `staging` no lugar de `development` somente no ambiente correspondente. Qualquer outro valor, ou valor ausente, faz a fixture abortar. A fixture usa IDs determinísticos, faz upsert transacional e não apaga dados.

## Provisionamento da conta demo

No `bingo-dev`, a conta smoke já está vinculada ao aluno `30000000-0000-4000-8000-000000000001`; não repita o provisionamento nesse projeto. Para provisionar uma conta equivalente em outro ambiente de desenvolvimento ou staging:

1. Crie o usuário de e-mail/senha pelo painel administrativo do Supabase Auth no ambiente de desenvolvimento ou staging. Não coloque a senha em migration, seed ou código.
2. Copie o UUID do usuário criado.
3. Vincule o UUID somente ao aluno determinístico da fixture:

```sql
update public.students
set auth_user_id = '<auth-user-uuid>',
    updated_at = now()
where id = '30000000-0000-4000-8000-000000000001';
```

4. Confirme que exatamente uma linha foi alterada e que nenhum outro aluno usa esse UUID.

Não foi criado script com `service_role`: para uma única conta técnica, o provisionamento manual inicial é a alternativa menos invasiva. Caso isso precise ser automatizado, o script futuro deverá ser local, explícito, protegido por ambiente e nunca importado pelo Flutter.

## Testes

Testes Flutter, sem internet:

```powershell
cd mobile/bingo_app
flutter test test/access_flow_test.dart test/session_gate_test.dart test/profile_repository_test.dart test/profile_screen_test.dart
```

Smoke hospedado opt-in, com as credenciais disponíveis somente no ambiente do host:

```powershell
cd mobile/bingo_app
powershell -ExecutionPolicy Bypass -File tool/run_hosted_mobile_smoke.ps1
```

O runner exige `BINGO_MOBILE_TEST_EMAIL` e `BINGO_MOBILE_TEST_PASSWORD`, obtém a configuração pública do projeto Supabase vinculado sem imprimi-la e executa apenas `test/hosted_mobile_smoke_test.dart`. Senha, access token, refresh token e chaves não são registrados. O teste é ignorado pela suíte comum, salvo quando o runner define explicitamente `BINGO_HOSTED_SMOKE=1`.

Em `2026-08-27`, o smoke contra `bingo-dev` comprovou login, sessão válida, leitura de uma linha própria em `students`, uma turma, uma escola, `16` BinCoins, `19` XP, zero linhas de outro aluno, restauração após recriação do cliente e logout. BinCoins e XP são uma fotografia da conta de teste, não parâmetros de regra.

Após a aplicação da seed 010 em `2026-09-04`, um novo hosted smoke do Mobile foi executado e aprovado. Ele comprovou login e sessão válida, exatamente uma linha própria em `students`, a turma e a escola relacionadas, invisibilidade dos outros 69 alunos sob RLS, `16` BinCoins, `19` XP, restauração da sessão após recriação do cliente e logout. Assim, o fluxo de Auth, perfil e leituras RLS permaneceu válido com o conjunto demo de setenta alunos.

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
- A sessão persistida pelo SDK é a fonte de verdade; o indicador auxiliar não impede a restauração de uma sessão válida.
- Sessão inválida retorna à entrada. Erro de rede permanece erro e oferece nova tentativa; nenhum desses estados ativa o piloto.
- BinCoins e XP da turma estão disponíveis no perfil autenticado. Níveis, conquistas, histórico, ranking, recompensas, resgates e métricas ambientais permanecem indisponíveis até possuírem fonte real e autorização próprias.
