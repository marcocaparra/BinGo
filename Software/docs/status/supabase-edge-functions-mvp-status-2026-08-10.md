# Status — Supabase Edge Functions MVP

Atualização: `2026-08-12`

Este arquivo distingue o que existe no repositório do que foi executado ou implantado. O repositório é a fonte adotada nesta etapa; nenhum estado remoto foi inferido.

## Estado implementado

As migrations local e Supabase removem `deposits.size`, o limite para itens pequenos e todas as pontuações por tamanho. `school_settings` passa a concentrar `deposit_bincoins_base = 8`, `deposit_class_xp_base = 19` e `class_weekly_xp_goal = 100`.

O catálogo global `waste_categories` contém seis códigos canônicos. Todos nascem com bônus zero na migration; apenas as seeds de desenvolvimento aplicam a matriz provisória de 100% para bateria, 50% para dispositivo móvel e 25% para cabo ou fio.

`deposits` relaciona a categoria confirmada, registra sua origem e preserva `bonus_rate_applied` e `bonus_bincoins_awarded`. Descartes válidos preexistentes são migrados para `UNKNOWN/UNIDENTIFIED` com bônus zero antes da remoção de tamanho.

`register_deposit_v1` implementa a operação atômica, idempotência sequencial e concorrente, detecção de colisão de payload, atualização de saldos e auditoria. A execução foi restringida a `service_role`, e escrita direta nas tabelas críticas foi revogada de `anon` e `authenticated`.

O FastAPI de referência aceita apenas os campos do contrato novo, calcula o bônus com arredondamento para o inteiro mais próximo e expõe categoria, origem, taxa e bônus no resultado e nos históricos. O Totem Simulator também deixou de enviar tamanho.

A fundação Deno versionada existe em `supabase/functions`, com dependência e lockfile fixados. O módulo compartilhado autentica `X-Machine-Id` e `X-Api-Key`, localiza a máquina com `service_role` e entrega somente `{ id, schoolId }` aos handlers futuros. Não existe Function HTTP implantável nesta etapa.

A API key permanece fora do frontend no desenho do Orange Pi e deve ser carregada pelo serviço local por configuração protegida. A revogação MVP consiste em substituir ou remover `machines.api_key_hash`; não foi criada infraestrutura de expiração, múltiplas chaves ou rotação automática. O status operacional da máquina não bloqueia autenticação.

## Regra oficial

Todo e-lixo válido usa a mesma recompensa-base. A categoria pode acrescentar somente BinCoins; XP permanece fixo em 19 por evento válido. Sem aluno identificado, o evento concede `0` BinCoins e `19` XP. Evento inválido concede `0/0` e não recebe categoria canônica.

`BATTERY`, `MOBILE_DEVICE`, `CABLE_WIRE`, `PERIPHERAL`, `OTHER_EWASTE` e `UNKNOWN` são os grupos do MVP. `UNKNOWN` exige origem `UNIDENTIFIED`; categorias conhecidas usam `AI_CONFIRMED` ou `USER_CORRECTED`.

## Validação comprovada

Os testes Python/SQLite cobrem contrato, categorias, bônus, descarte anônimo, descarte inválido, categoria inativa, combinação de origem, snapshot histórico, retry e colisão de `event_id`. A suíte executada em `2026-08-12` passou com `35` testes e deixou o teste PostgreSQL opt-in separado.

As cinco migrations foram reproduzidas com sucesso no Supabase local/PostgreSQL 17. A seed rica criou uma escola, sete turmas, setenta alunos e aplicou somente no ambiente local a matriz provisória de bônus. `supabase test db --local` passou com `20` testes pgTAP, e a prova PostgreSQL com duas chamadas simultâneas ao mesmo `event_id` passou sem duplicar evento, BinCoins ou XP.

A auditoria final confirmou ausência de `deposits.size` e dos campos de configuração por tamanho, seis categorias ativas, execução da RPC negada a `anon` e `authenticated` e concedida a `service_role`. Essas evidências comprovam o estado local, mas não a aplicação no projeto Supabase hospedado.

A fundação das Edge Functions foi validada com Deno 2.9.4. `deno fmt --check`, `deno lint` e `deno check` passaram. Os seis testes unitários de autenticação passaram, e o teste opt-in somente leitura autenticou a máquina da seed através da Data API do Supabase local.

O módulo não aplica `trim()` à API key. O teste unitário comprova a comparação literal quando o adaptador preserva whitespace; em uma requisição Fetch real, o runtime normaliza whitespace HTTP nas extremidades antes de entregar o header ao módulo. Essa limitação foi documentada em vez de ser contornada artificialmente.

## Pendências reais

A Edge Function HTTP ainda precisa ser criada para combinar a autenticação compartilhada, validar e rejeitar campos fora do contrato, chamar a RPC e mapear os demais erros. O teste atual com `machine_id` e `school_id` no body comprova apenas que a autenticação não lê esses campos; o futuro endpoint deverá rejeitá-los. As policies completas de leitura para Mobile e administração continuam fora deste recorte; esta migration protege as escritas críticas, mas não substitui o desenho geral de RLS.

O FastAPI continua divergindo em dois pontos e não foi alterado: aplica `strip()` à chave e pode responder `404` quando a máquina não existe. A fundação Edge não chama `trim()` e padroniza ausência, formato inválido, máquina inexistente e chave incorreta como `401 MACHINE_AUTHENTICATION_FAILED`.

Antes do deploy remoto, executar `supabase migration list` no projeto vinculado e comparar o histórico com o estado local validado. Se o banco remoto contiver dados históricos úteis em `size`, exportá-los antes da migration destrutiva.

Os valores provisórios das seeds não são política ambiental de produção. Ativação de qualquer bônus remoto requer aprovação formal e alteração controlada do catálogo.
