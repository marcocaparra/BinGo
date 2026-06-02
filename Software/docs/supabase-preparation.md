# Preparação Para Supabase Auth

## Decisão de autenticação

O BinGo deve usar Supabase Auth para o login do app por e-mail e senha. Isso deixa o armazenamento de senha, hash, recuperação de senha, sessão, refresh token e emissão de JWT sob responsabilidade da plataforma de autenticação, em vez de duplicar esse mecanismo dentro da tabela de domínio `students`.

A tabela `students` continua sendo a entidade de domínio do aluno. Ela deve guardar os dados necessários para as regras do produto: escola, turma, nome, saldo de pontos, status, vínculo com descartes e resgates, e o PIN usado no Totem. Ela não deve armazenar `password_hash` para o login do app.

## Vínculo entre students e Supabase Auth

O campo `students.auth_user_id` prepara o vínculo entre o aluno do domínio BinGo e o usuário autenticado pelo Supabase Auth. Ele é `uuid`, `unique` e inicialmente nullable.

Esse campo precisa ser nullable porque uma escola pode pré-cadastrar alunos antes que eles ativem uma conta no app. Nesse estado, o aluno já existe para fins de turma, pontos, histórico e uso do Totem, mas ainda não possui usuário em `auth.users`.

No Postgres local usado via Docker, o schema `auth.users` normalmente não existe. Por isso, a preparação atual não cria uma foreign key real para `auth.users(id)`. Em um ambiente Supabase, o vínculo pode ser tratado logicamente pela aplicação ou formalizado em uma migration específica de Supabase, se a equipe decidir que a FK operacional vale o acoplamento ao schema `auth`.

## Separação entre app e Totem

O login do app e o login do Totem são fluxos diferentes. O app deve autenticar por e-mail e senha usando Supabase Auth. O Totem deve continuar usando `students.pin_hash`, porque o PIN é uma credencial curta e contextual, adequada ao uso presencial no equipamento.

Essa separação evita misturar senha de app com PIN operacional. Também permite que um aluno exista no sistema e use o Totem antes de criar uma conta no app, mantendo o cadastro escolar como fonte de verdade do domínio.

## RLS futura

Quando o projeto migrar para Supabase, as tabelas com escopo por escola provavelmente precisarão de Row Level Security: `schools`, `classes`, `students`, `admins`, `machines`, `rewards`, `deposits`, `redemptions`, `audit_logs` e `school_settings`.

As políticas devem ser desenhadas depois que os papéis reais estiverem claros. A regra central deve ser impedir vazamento entre escolas e permitir que o aluno autenticado acesse apenas seus próprios dados ou dados agregados permitidos da sua turma/escola. Admins devem ter acesso limitado à escola em que atuam. Máquinas/totens não devem depender de permissões amplas de usuário final.

## Leitura direta e operações transacionais

O app poderá fazer leitura direta, com RLS, de dados de baixo risco: perfil do próprio aluno, turma, saldo, histórico próprio de descartes, histórico próprio de resgates e catálogo de recompensas ativas da escola.

Operações que alteram saldo, estoque, resgates, auditoria ou estado operacional devem continuar passando pelo backend ou por funções transacionais controladas. Isso inclui registrar depósito, calcular pontos, atualizar saldo individual e da turma, criar resgate, expirar resgate, entregar recompensa, decrementar estoque, resetar PIN, escrever `audit_logs` e processar eventos vindos de máquinas.

O motivo é consistência. O banco possui saldos materializados em `students` e `classes`, além de eventos históricos em `deposits` e `redemptions`. Essas mudanças precisam ocorrer de forma atômica, com validação de regras e auditoria, em vez de serem feitas por múltiplos writes diretos do cliente.
