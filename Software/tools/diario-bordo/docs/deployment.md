# Publicação Gratuita

Esta versão foi preparada para um piloto interno com frontend no Cloudflare Pages, API no Koyeb Free e PostgreSQL no Neon Free. Os serviços gratuitos não oferecem SLA; a API pode dormir depois de uma hora sem tráfego e o frontend aguarda o servidor acordar antes de liberar o acesso.

## Ordem De Publicação

1. Envie a branch `release/diario-bordo-v0` ao GitHub.
2. Crie o projeto do frontend no Cloudflare Pages para reservar o endereço `pages.dev`.
3. Crie o banco PostgreSQL no Neon.
4. Crie o serviço da API no Koyeb usando o `Dockerfile` desta pasta.
5. Atualize `VITE_API_BASE_URL` no Cloudflare Pages e faça um novo deploy.
6. Execute o smoke test descrito ao final.

## Cloudflare Pages

Conecte o repositório privado do BinGo e use:

```text
Branch de produção: release/diario-bordo-v0
Diretório raiz: Software/tools/diario-bordo/frontend
Comando de build: npm ci && npm run build
Diretório de saída: dist
Node.js: 22
VITE_API_BASE_URL: https://ENDERECO-DA-API.koyeb.app
VITE_ATTACHMENTS_ENABLED: false
```

O arquivo `public/_headers` adiciona proteções do navegador ao deploy. Use o endereço gratuito `pages.dev`; domínio próprio é opcional e não faz parte do custo zero.

## Neon PostgreSQL

Crie um projeto no plano Free e guarde separadamente host, banco, usuário e senha. Para o Spring Boot, a URL precisa começar com `jdbc:`:

```text
DATABASE_URL=jdbc:postgresql://HOST/DB?sslmode=require
DATABASE_USERNAME=USUARIO
DATABASE_PASSWORD=SENHA
```

As migrations `V1` a `V6` são aplicadas automaticamente pelo Flyway no primeiro início da API. Não execute os arquivos manualmente em um banco vazio.

Para o backup do GitHub Actions, crie o secret `DIARY_DATABASE_URL` com a URL PostgreSQL normal fornecida pelo Neon, sem o prefixo `jdbc:`.

## Koyeb Free

Crie um Web Service conectado ao GitHub com estas opções:

```text
Branch: release/diario-bordo-v0
Diretório de trabalho: Software/tools/diario-bordo
Builder: Dockerfile
Dockerfile: Dockerfile
Instância: Free
Porta: 8080
Health check: GET /health
```

Cadastre como secrets ou variáveis protegidas:

```text
DATABASE_URL=jdbc:postgresql://HOST/DB?sslmode=require
DATABASE_USERNAME=USUARIO
DATABASE_PASSWORD=SENHA
DIARY_TEAM_PIN=PIN_NUMERICO_DE_6_DIGITOS
DIARY_ADMIN_PIN=OUTRO_PIN_NUMERICO_DE_6_DIGITOS
DIARY_AUTH_SIGNING_SECRET=SEGREDO_ALEATORIO_COM_32_OU_MAIS_CARACTERES
DIARY_PUBLIC_BASE_URL=https://ENDERECO-DA-API.koyeb.app
CORS_ALLOWED_ORIGINS=https://ENDERECO-DO-FRONTEND.pages.dev
ATTACHMENTS_ENABLED=false
DATABASE_MAX_POOL_SIZE=3
DATABASE_MIN_IDLE=0
```

Gere o segredo no PowerShell:

```powershell
[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
```

Não reutilize os PINs de desenvolvimento e não adicione segredos a arquivos do GitHub.

## Evidências E Anexos

Uploads ficam desligados nesta fase porque o disco da instância gratuita não é persistente. O formulário exige um link ou texto de evidência; arquivos devem ser enviados ao Google Drive, OneDrive, GitHub ou serviço equivalente e compartilhados por link.

Os links continuam aparecendo no histórico e no relatório Markdown. A tabela e o código de anexos permanecem compatíveis com uma futura integração ao Cloudflare R2.

## Backup

O workflow `Diario de Bordo Backup` executa `pg_dump` diariamente às 03h no horário de Brasília e guarda o artefato privado por 14 dias. Depois de cadastrar `DIARY_DATABASE_URL`, execute o workflow manualmente uma vez e confirme que o arquivo `.dump` e o manifesto foram gerados.

## Smoke Test

1. Abra o endereço `pages.dev` em janela anônima.
2. Confirme a tela `Preparando o Diário de Bordo...` e aguarde a API.
3. Entre como equipe com o PIN de seis dígitos.
4. Preencha um registro usando um link de evidência.
5. Saia e entre como coordenação.
6. Confira, edite e exporte o registro em Markdown.
7. Tente escolher e enviar uma data futura; a interface e a API devem recusar.
8. Feche o navegador e confirme que a sessão não permanece aberta.

## Retorno Seguro

Se um deploy falhar, mantenha o último deployment saudável no Cloudflare e no Koyeb. A branch de produção só deve receber commits já validados pelo workflow `Diario de Bordo CI`.
