# Como rodar o Vision API Tester localmente

Este guia ensina a subir o projeto completo em ambiente local:

- PostgreSQL via Docker Compose
- Backend Spring Boot
- Frontend Vite + React

Os comandos abaixo foram pensados para PowerShell no Windows.

## Requisitos

- Docker Desktop
- Java 21
- Node.js e npm
- PowerShell
- AWS CLI configurado com o profile `vision-api-tester`, para usar Amazon Rekognition real
- Google Cloud CLI com Application Default Credentials configuradas, para usar Google Cloud Vision real

## Portas usadas

```text
PostgreSQL: localhost:5433
Backend:    http://localhost:8080
Frontend:   http://localhost:5173
```

## 1. Subir o banco de dados

Abra um terminal na pasta do backend:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\backend"
```

Suba o PostgreSQL:

```powershell
docker compose up -d
```

O banco configurado pelo compose usa:

```text
database: vision_api_tester
user:     vision_api_tester
password: vision_api_tester
host:     localhost
port:     5433
```

Para conferir se a porta esta respondendo:

```powershell
Test-NetConnection -ComputerName localhost -Port 5433
```

O campo esperado e:

```text
TcpTestSucceeded : True
```

## 2. Rodar o backend

Na pasta do backend:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\backend"
```

Rode a aplicacao:

```powershell
.\mvnw.cmd spring-boot:run
```

O backend sobe em:

```text
http://localhost:8080
```

Em outro terminal, teste o health check:

```powershell
Invoke-RestMethod http://localhost:8080/api/health
```

Resultado esperado:

```text
status : ok
service: vision-api-tester-backend
```

## 3. Rodar o frontend

Abra outro terminal na pasta do frontend:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\frontend"
```

Instale as dependencias, se ainda nao tiver instalado:

```powershell
npm install
```

Rode o Vite:

```powershell
npm run dev
```

Abra no navegador:

```text
http://localhost:5173/dashboard
```

## 4. Testar o fluxo completo

Com banco, backend e frontend rodando:

1. Acesse `http://localhost:5173/new-test`.
2. Crie ou selecione um projeto.
3. Selecione uma imagem local.
4. Selecione os providers desejados.
5. Clique em `Executar teste`.
6. O frontend enviara a imagem para o backend.
7. O backend executara a analise em `/api/images/{imageId}/analyze`.
   - `aws-rekognition` chama Amazon Rekognition real.
   - `google-cloud-vision` chama Google Cloud Vision real.
8. Os resultados serao salvos no banco e exibidos na tela.
9. Salve a avaliacao humana para cada provider.
10. Acesse `Dashboard` e `Historico` para ver os dados persistidos.

## Endpoints principais

```text
GET    /api/health
GET    /api/projects
POST   /api/projects
POST   /api/images
POST   /api/images/{imageId}/analyze
GET    /api/provider-results?imageId={uuid}
POST   /api/provider-results
DELETE /api/images/{imageId}
PUT    /api/provider-results/{providerRunId}/evaluation
GET    /api/history
GET    /api/dashboard
```

## Variaveis de ambiente uteis

Backend:

```powershell
$env:DB_URL="jdbc:postgresql://localhost:5433/vision_api_tester"
$env:DB_USERNAME="vision_api_tester"
$env:DB_PASSWORD="vision_api_tester"
$env:SERVER_PORT="8080"
$env:AWS_PROFILE="vision-api-tester"
$env:AWS_REGION="us-east-1"
$env:AWS_REKOGNITION_MIN_CONFIDENCE="55"
$env:AWS_REKOGNITION_MAX_LABELS="20"
$env:GOOGLE_CLOUD_PROJECT="vision-api-tester-503219"
$env:GOOGLE_CLOUD_VISION_MAX_RESULTS="20"
```

Frontend:

```powershell
$env:VITE_API_BASE_URL="http://localhost:8080/api"
```

Depois rode:

```powershell
npm run dev
```

## Problemas comuns

### Docker nao esta acessivel

Se `docker compose up -d` falhar, abra o Docker Desktop e tente novamente.

### Porta 8080 ocupada

Descubra o processo:

```powershell
netstat -ano | findstr :8080
```

Encerre pelo PID:

```powershell
Stop-Process -Id SEU_PID -Force
```

### Porta 5173 ocupada

O Vite pode tentar outra porta automaticamente. Se isso acontecer, use a URL exibida no terminal.

### Backend nao conecta no banco

Confirme que o PostgreSQL esta rodando em `5433`:

```powershell
Test-NetConnection -ComputerName localhost -Port 5433
```

Se nao estiver respondendo, volte ao passo de subir o banco:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\backend"
docker compose up -d
```

## Build de validacao

Backend:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\backend"
.\mvnw.cmd test
```

Frontend:

```powershell
cd "C:\Users\Predeus\Documents\Vision API Tester\frontend"
npm run build
```
