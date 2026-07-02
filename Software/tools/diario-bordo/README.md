# Diário de Bordo Coletivo do BinGo

Ferramenta interna para registrar as atividades diárias dos integrantes do
BinGo. O sistema manterá um histórico por integrante, permitirá consultar
pendências e, em uma etapa futura, exportará os registros para planilha.

Este diretório é um mini projeto independente. Ele não deve compartilhar
código, configuração ou banco de dados com o backend principal do BinGo.

## Estado atual

O backend Spring Boot foi inicializado e a documentação funcional básica foi
definida. Entidades, migrations e endpoints ainda não foram implementados.

## Funcionalidades previstas para a V1

- acesso por senha coletiva, armazenada em variável de ambiente;
- cadastro e seleção de integrantes;
- registro de uma atividade por integrante e por dia;
- opção de registrar que não houve atividade;
- consulta por integrante, área, data e status;
- identificação de relatórios pendentes;
- evidências armazenadas como links.

Upload de arquivos e exportação para `.xlsx` ficam fora da primeira etapa.

## Tecnologias

- Java 21;
- Spring Boot e Maven Wrapper;
- Spring Web MVC;
- Spring Data JPA;
- Bean Validation;
- PostgreSQL.

## Estrutura

```text
diario-bordo/
|-- backend/   # API Spring Boot
|-- database/  # migrations SQL
|-- docs/      # arquitetura e contratos
|-- frontend/  # aplicação web futura
`-- README.md
```

## Documentação

- [Arquitetura](docs/architecture.md)
- [Modelo de dados](docs/database-model.md)
- [Contrato da API](docs/api-contract.md)
- [Fluxo do frontend](docs/frontend-flow.md)

## Executar o backend

O projeto ainda precisa da configuração de conexão com o PostgreSQL antes de
iniciar com JPA. Depois dessa etapa, no Windows, a execução será feita a partir
de `backend/`:

```powershell
.\mvnw.cmd spring-boot:run
```

As credenciais e a senha coletiva não devem ser versionadas. Elas serão
fornecidas por variáveis de ambiente documentadas em `.env.example` quando a
configuração correspondente for implementada.
