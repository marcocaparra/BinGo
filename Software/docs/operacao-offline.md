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

## Detecção de conexão

O serviço local do Orange Pi deve verificar periodicamente se o backend central está respondendo.

Endpoint sugerido no backend central:

```http
GET /health
```

Resposta esperada:

```json
{
  "status": "ok"
}
```

Regra de detecção:

```text
A cada 5 segundos, o Orange Pi chama /health.

Se o backend falhar 3 vezes seguidas:
    o Totem entra em modo seguro offline.

Se o backend voltar a responder 2 vezes seguidas:
    o Totem volta para o modo real online.
```

Essa regra evita que pequenas oscilações de rede façam a interface alternar rapidamente entre online e offline.

## Estado consultado pelo frontend

O serviço local deve expor um endpoint para o frontend consultar:

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

O frontend deve usar o campo `can_start_deposit` para decidir se libera ou bloqueia o fluxo.

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

Esse botão apenas força uma nova consulta ao `/local/status`. Ele não deve iniciar o fluxo de descarte.

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

O frontend consulta `/local/status` e só libera o fluxo quando `can_start_deposit = true`.

Se a conexão cair durante o fluxo antes da inserção física, o fluxo é cancelado. Se cair depois da inserção física, o Totem não confirma pontos e orienta o aluno a chamar um responsável.

O modo demonstração pode simular o fluxo sem internet, mas deve estar identificado como demonstração e nunca alterar saldo real.
