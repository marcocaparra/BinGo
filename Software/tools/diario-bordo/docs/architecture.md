# Arquitetura

## Visão geral

```text
Frontend (React/Vite no Cloudflare Pages)
        |
        | HTTP/REST com JSON
        v
Backend (Java 21 e Spring Boot)
        |
        | Spring Data JPA/JDBC
        v
PostgreSQL
```

O frontend consumirá uma API REST e não acessará o banco diretamente. O
backend será responsável pelas validações, regras de negócio, data oficial e
persistência.

## Organização do backend

O pacote-base é `com.bingo.diario`:

```text
config/      configurações globais, como CORS e relógio
controller/  entrada HTTP e delegação para os services
dto/         contratos de entrada e saída
exception/   exceções e tratamento padronizado de erros
model/       entidades JPA e enums
repository/  acesso ao PostgreSQL com Spring Data JPA
service/     regras de negócio e transações
```

Controllers não devem retornar entidades JPA diretamente. Requests serão
validados com Bean Validation e responses usarão DTOs.

## Decisões da V1

- A data oficial usa o fuso `America/Sao_Paulo`.
- Os PINs vêm de variáveis de ambiente e são usados somente no login; as demais requisições usam token assinado com validade de oito horas.
- Dez falhas de login pelo mesmo IP bloqueiam novas tentativas por quinze minutos.
- O esquema é controlado por migrations Flyway em `database/migrations/`.
- O Hibernate validará o esquema com `ddl-auto=validate` depois da migration inicial.
- Na publicação gratuita inicial, evidências serão textos e URLs; uploads ficam desativados.
- Relatórios não serão removidos fisicamente na V1.

## Limites

O mini projeto permanece dentro de `tools/diario-bordo/`. Nenhuma parte dele
deve depender das pastas `backend/`, `database/`, `apps/` ou `mobile/` do
produto principal.
