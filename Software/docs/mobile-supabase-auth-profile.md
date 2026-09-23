# Mobile: Supabase Auth e perfil autenticado

## Escopo atual

O Mobile possui dois caminhos isolados:

- modo piloto: explícito, local, sem autenticação e sem acesso ao Supabase;
- conta autenticada: e-mail/senha no Supabase Auth e leituras remotas autorizadas, incluindo perfil, Ranking V1 e Jornada da própria turma.

O perfil autenticado reutiliza o frontend final para nome, escola, turma, saldo individual de BinCoins, XP da turma e Trilha do Restaurador. `students.points_student_balance` representa BinCoins no V1, e `classes.points_class_balance` representa XP da turma. Não existe um saldo separado de pontos pessoais; o primeiro tile do perfil autenticado apresenta a quantidade histórica de descartes válidos identificados.

A Trilha do Restaurador V1 é derivada exclusivamente da quantidade histórica de descartes válidos identificados do aluno. Não existe contador ou nível persistido no aluno. Missões, BinCoins e XP da turma não participam do cálculo. `get_student_profile_progress_v1()` não recebe `student_id`: deriva o aluno de `auth.uid()` e retorna contagem, nível, restante e progresso. Os níveis são `NONE` em 0; `APPRENTICE` em 1–4; `EXPLORER` em 5–9; `RESTORER` em 10–19; `GUARDIAN` em 20–49; e `HERO` a partir de 50.

Avatar e tema do perfil autenticado são preferências cosméticas locais. O Mobile reutiliza `ProfileCustomization` e `SharedPreferencesCustomizationStore`, mas isola contas reais com as chaves `bingo.profile.<student_id>.avatar` e `bingo.profile.<student_id>.theme`. Essas preferências não são sincronizadas nem enviadas ao Supabase. Os defaults continuam `b1n-default` e `city-blue`, e os bloqueios usam o nível real retornado pela Trilha. O modo piloto mantém suas chaves locais anteriores.

No Ranking V1 autenticado, `classes.points_class_balance` é a única pontuação. A RPC `get_class_ranking_v1()` deriva a escola de `auth.uid()` e retorna somente identificador, nome e saldo das turmas dessa escola, já ordenados por saldo decrescente e UUID crescente como desempate técnico temporário. O modo autenticado não usa `classRows` ou outro dado demonstrativo como fallback.

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

O mesmo repository chama `get_student_profile_progress_v1()` sem parâmetros, exige exatamente uma linha, confere o `student_id` retornado contra o perfil já carregado e valida contagem, código, nível, restante e fração de progresso. Falhas de sessão, rede ou payload permanecem erros autenticados e nunca ativam mocks do piloto.

O Ranking usa `RemoteRankingRepository` e `SupabaseRankingDataSource`, sem consulta Supabase dentro do widget. A RPC não aceita parâmetros e não amplia a leitura RLS global de `classes`: sua superfície dedicada valida server-side o vínculo do aluno autenticado e retorna somente as colunas necessárias. A mesma lista ordenada alimenta posição da própria turma e pódio; resposta não vazia sem a própria turma é tratada como inconsistência, não como posição zero.

A Jornada usa `RemoteClassJourneyRepository` e `SupabaseClassJourneyDataSource`, também sem consulta dentro de widgets. `get_class_journey_v1()` não recebe identidade; deriva escola e turma de `auth.uid()` e retorna os três estágios da campanha vigente. O Shell carrega um único snapshot e o compartilha com Home, Ranking e mapa. Os códigos server-side selecionam somente os três cenários visuais existentes; nenhuma opção autenticada permite simulação local. Falha, ausência ou payload malformado nunca ativa dados demo. Métricas ambientais sem fonte aprovada continuam indisponíveis.

Com Supabase CLI e Docker disponíveis:

```powershell
supabase start
supabase db reset
```

O reset aplica as migrations existentes em `supabase/migrations/`, incluindo o baseline atual de Auth/RLS. O vínculo continua sendo provisionado por `students.auth_user_id`; usuário Auth sem aluno associado recebe resultado vazio, e aluno sem `auth_user_id` não é visível por uma sessão autenticada.

Em `2026-09-04`, o projeto hospedado `bingo-dev` (`ddxmohrjcxuibswmrtla`) possuía as nove migrations atuais do repositório e as Edge Functions `register-deposit-v1` e `health-v1` ativas. A seed `database/seeds/010_bingo_dev_demo_dataset.sql` foi aplicada uma única vez e deixou o conjunto demo com sete turmas e setenta alunos, dez alunos determinísticos por turma. O aluno smoke permaneceu vinculado ao Supabase Auth com `16` BinCoins, sua turma preservou `19` XP, e o depósito e o audit log preexistentes permaneceram únicos. O postflight confirmou que a seed não alterou usuários Auth, RLS, policies, migrations ou Edge Functions e não criou depósitos, resgates, recompensas ou logs adicionais.

Em `2026-09-21`, um novo preflight somente leitura confirmou que o mesmo projeto estava alinhado às 19 migrations locais, até `20260919120000_get_class_ranking_v1.sql`. As migrations de Missões `012–018` e a migration de Ranking `019` estão aplicadas no `bingo-dev`; esta comprovação não declara o estado de produção.

Depois desse preflight, `20260921120000_get_student_profile_progress_v1.sql` foi aplicada somente no `bingo-dev`. O postflight confirmou 20 migrations alinhadas, a assinatura sem parâmetros, `STABLE`, `SECURITY DEFINER`, `search_path` vazio e execução apenas por `authenticated`. Não houve aplicação em produção.

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
flutter test test/ranking_repository_test.dart test/authenticated_ranking_screen_test.dart
flutter test test/class_journey_repository_test.dart test/authenticated_class_journey_screen_test.dart
```

Smoke hospedado opt-in, com as credenciais disponíveis somente no ambiente do host:

```powershell
cd mobile/bingo_app
powershell -ExecutionPolicy Bypass -File tool/run_hosted_mobile_smoke.ps1
```

O runner exige `BINGO_MOBILE_TEST_EMAIL` e `BINGO_MOBILE_TEST_PASSWORD`, obtém pelo CLI a configuração pública e uma chave secreta moderna do projeto Supabase vinculado sem imprimi-las e executa apenas `test/hosted_mobile_smoke_test.dart`. A chave secreta existe somente no processo opt-in para criar e remover a identidade Auth temporária sem vínculo; não é passada ao aplicativo, persistida ou registrada. Senha, access token, refresh token e chaves não aparecem no log. O teste é ignorado pela suíte comum, salvo quando o runner define explicitamente `BINGO_HOSTED_SMOKE=1`.

Em `2026-08-27`, o smoke contra `bingo-dev` comprovou login, sessão válida, leitura de uma linha própria em `students`, uma turma, uma escola, `16` BinCoins, `19` XP, zero linhas de outro aluno, restauração após recriação do cliente e logout. BinCoins e XP são uma fotografia da conta de teste, não parâmetros de regra.

Após a aplicação da seed 010 em `2026-09-04`, um novo hosted smoke do Mobile foi executado e aprovado. Ele comprovou login e sessão válida, exatamente uma linha própria em `students`, a turma e a escola relacionadas, invisibilidade dos outros 69 alunos sob RLS, `16` BinCoins, `19` XP, restauração da sessão após recriação do cliente e logout. Assim, o fluxo de Auth, perfil e leituras RLS permaneceu válido com o conjunto demo de setenta alunos.

Em `2026-09-21`, após a migration da Trilha, o runner hospedado foi aprovado contra o `bingo-dev`. O repository real retornou exatamente um progresso para o aluno autenticado: 2 descartes válidos, nível 1 `APPRENTICE`, 3 restantes e progresso `0.4`, além de 3300 BinCoins e 3800 XP da turma. A contagem foi confrontada com as linhas válidas reais em `deposits`. Uma identidade Auth temporária sem aluno recebeu zero linhas e foi removida ao final; `anon` não executou a RPC. A recriação do store local preservou avatar e tema no namespace do mesmo aluno e uma segunda identidade recebeu os defaults, sem gravação de personalização no Supabase. Os testes de widgets relacionados ao Perfil, incluindo header, badge, Trilha, B1N, bloqueios e modo piloto, também passaram sem mudança de golden.

O baseline estrutural é validado junto da suíte pgTAP:

```powershell
supabase test db
```

`supabase/functions/tests/authorization-rls.integration.test.ts` complementa a inspeção estática com usuários reais do Supabase Auth local. Ele valida leitura própria, isolamento de outro aluno e de outra escola, escola/turma relacionadas, identidade sem vínculo, bloqueio de alterações críticas, bloqueio de dados privados para `anon`, catálogo público e privilégios mínimos de `service_role`. Sua execução é opt-in por `BINGO_AUTH_RLS_INTEGRATION=1` e exige apenas credenciais do ambiente local de teste.

## Limitações e decisões de segurança

- O baseline comprova grants e policies de `students`, `classes` e `schools`; o Ranking V1 usa uma RPC autenticada dedicada e somente leitura, sem ampliar a policy global de `classes`.
- Leituras simples usam Supabase Auth e RLS; operações críticas continuam reservadas às Edge Functions e RPCs.
- A FK de `students.auth_user_id` para `auth.users.id` não foi criada sem validar previamente os registros do projeto remoto.
- O indicador de restauração autenticada em `SharedPreferences` não contém sessão nem credenciais. O SDK do Supabase gerencia a sessão.
- A sessão persistida pelo SDK é a fonte de verdade; o indicador auxiliar não impede a restauração de uma sessão válida.
- Sessão inválida retorna à entrada. Erro de rede permanece erro e oferece nova tentativa; nenhum desses estados ativa o piloto.
- BinCoins e XP da turma estão disponíveis no perfil autenticado. O Ranking V1 usa o saldo atual de XP das turmas da mesma escola. A Jornada/BinGópolis possui implementação local própria, mas só ficará disponível contra o `bingo-dev` após a promoção controlada da migration `021`, provisionamento da campanha e postflight. Peso recuperado e demais métricas ambientais permanecem sem fonte e não usam os snapshots demo.
