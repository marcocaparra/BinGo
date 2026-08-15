# Plano B — Operação Offline do Totem BinGo!

## Objetivo

Este documento define como o Totem BinGo! deve se comportar quando estiver sem conexão com o backend central ou quando algum serviço necessário para o fluxo real estiver indisponível.

A regra principal é simples: se o Totem não conseguir se comunicar com o backend central antes do início do fluxo, ele não deve permitir um descarte real. Nesse caso, o Totem entra em modo seguro e mostra uma tela de indisponibilidade.

O Orange Pi continua ligado, a interface local continua aberta e o sistema continua verificando se a conexão voltou. O que fica bloqueado é o fluxo real de uso: login, validação por IA, descarte, pontuação, saldo, ranking e resgate.

## Funcionamento geral

O Totem terá um serviço local rodando no Orange Pi. Esse serviço será responsável por verificar se o backend central está acessível e informar ao frontend se o fluxo real pode ou não começar.

O frontend do Totem não deve testar internet diretamente. Ele deve apenas consultar o serviço local do Orange Pi.

Fluxo simplificado:

```text
Frontend do Totem
↓
Serviço local no Orange Pi
↓
Backend central
```

Se o backend central responder normalmente, o Totem opera em modo real. Se o backend central não responder, o Totem entra em modo seguro offline.

Resumo dos modos:

```text
Online = fluxo real liberado
Offline = fluxo real bloqueado
Demonstração = fluxo simulado, sem alterar dados reais
```

## Readiness do backend central

O backend central possui uma única Edge Function autenticada, `health-v1`, que materializa conceitualmente `GET /health`. No ambiente Supabase local, sua rota nativa é:

```http
GET /functions/v1/health-v1
X-Machine-Id: <uuid>
X-Api-Key: <secret>
```

Uma resposta saudável tem HTTP `200` e o seguinte contrato:

```json
{
  "status": "AVAILABLE",
  "can_start_deposit": true,
  "scope": "CENTRAL_BACKEND",
  "checked_at": "2026-08-15T12:00:00.000Z"
}
```

Quando o handler consegue comprovar readiness negativo, responde HTTP `503` com `status = UNAVAILABLE` e `can_start_deposit = false`. Credencial inválida responde `401` e não significa falha de saúde. Uma indisponibilidade de PostgreSQL ou Data API pode interromper a autenticação antes da RPC; timeout, ausência de resposta, `500` ou qualquer outra resposta diferente do sucesso exato também exige comportamento fail-closed. Portanto, somente `200 + AVAILABLE + can_start_deposit=true` libera um novo ciclo.

O check central cobre chegada ao runtime, autenticação técnica/Data API e PostgreSQL disponível em condição gravável verificável sem escrita. Ele não chama IA, não consulta turma ou catálogo e não executa RPC de negócio. Não possui CORS, polling, contadores ou estado persistente.

## Estado consultado pelo frontend — pendência local

O contrato abaixo permanece uma responsabilidade futura do serviço local do Orange Pi e não foi implementado ou simulado nesta entrega. Esse serviço poderá expor um endpoint para o frontend consultar:

```http
GET /local/status
```

Quando o Totem estiver online, a resposta deve indicar que o fluxo pode começar:

```json
{
  "status": "ONLINE",
  "can_start_deposit": true,
  "message": null
}
```

Quando o Totem estiver offline, a resposta deve bloquear o início do fluxo:

```json
{
  "status": "OFFLINE",
  "can_start_deposit": false,
  "message": "Totem temporariamente indisponível. Estamos sem conexão no momento."
}
```

O frontend deverá usar o campo `can_start_deposit` para decidir se libera ou bloqueia o fluxo quando essa integração local existir.

Regra da interface:

```text
Se can_start_deposit = true:
    mostrar tela inicial normal.

Se can_start_deposit = false:
    mostrar tela de sem conexão.
```

## Tela de modo seguro

Quando o Totem estiver offline, a interface deve mostrar uma tela simples e clara. O aluno não deve conseguir iniciar login, descarte, resgate ou validação de item.

Mensagem principal:

```text
Totem temporariamente indisponível
```

Mensagem secundária:

```text
Estamos sem conexão no momento.
Tente novamente em alguns minutos ou chame um responsável.
```

Mensagem opcional com identidade do projeto:

```text
BinGópolis está reconectando...
```

O botão recomendado é:

```text
Verificar novamente
```

Quando o serviço local for implementado, esse botão apenas forçará uma nova consulta ao `/local/status`. Ele não deverá iniciar o fluxo de descarte.

## Queda de conexão durante o fluxo

Se a conexão cair antes do aluno iniciar o descarte, o Totem apenas mostra a tela de sem conexão.

Se a conexão cair depois que o aluno já começou o fluxo, o comportamento depende do momento da queda.

Se a conexão cair antes da inserção física do item, o fluxo deve ser cancelado e o Totem deve voltar para a tela de modo seguro.

Se a conexão cair depois da inserção física do item, o Totem não deve confirmar pontos. A interface deve informar que não foi possível concluir a validação e orientar o aluno a chamar um responsável.

Mensagem recomendada:

```text
A conexão caiu durante o descarte.

Não foi possível confirmar seus pontos agora.
Chame um responsável.
```

No V1, o Totem não deve prometer pontuação offline se a validação depende do backend central e da API de IA.

## Falha da API de IA

A falha da API de IA não é necessariamente a mesma coisa que falta de internet. Pode existir internet e o backend estar acessível, mas a IA falhar ou demorar demais para responder.

Nesse caso, o Totem não deve aceitar o item automaticamente.

Mensagem recomendada:

```text
Não conseguimos validar o item agora.
Tente novamente ou chame um responsável.
```

Regra:

```text
Se a IA falhar antes da inserção física:
    cancelar validação e pedir nova tentativa.

Se a IA falhar depois da inserção física:
    não confirmar pontos e pedir responsável.
```

## Modo demonstração

O modo demonstração é separado do modo real e do modo offline.

Ele pode funcionar sem internet, mas deve deixar claro que os dados são simulados. Nenhum saldo real, ranking real, histórico real ou resgate real deve ser alterado.

Mensagem obrigatória:

```text
Modo demonstração ativo.
Os dados exibidos são simulados e não alteram o saldo real.
```

Regra:

```text
Modo real online:
    registra descarte e pontuação de verdade.

Modo offline:
    bloqueia descarte real.

Modo demonstração:
    simula o fluxo, mas não altera dados reais.
```

## Regra curta

Se o Totem não conseguir se comunicar com o backend central, ele deve entrar em modo seguro offline e bloquear descartes reais.

O Orange Pi continua ligado, mantém a interface aberta e verifica periodicamente se a conexão voltou.

Na integração futura, o frontend consultará `/local/status` e só liberará o fluxo quando `can_start_deposit = true`.

Se a conexão cair durante o fluxo antes da inserção física, o fluxo é cancelado. Se cair depois da inserção física, o Totem não confirma pontos e orienta o aluno a chamar um responsável.

O modo demonstração pode simular o fluxo sem internet, mas deve estar identificado como demonstração e nunca alterar saldo real.
