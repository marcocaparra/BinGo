# Vision API Tester Backend

Backend minimo para salvar projetos de avaliacao, imagens, execucoes de providers de visao computacional e avaliacoes humanas.

Esta versao possui integracao real com Amazon Rekognition para o provider `aws-rekognition` e Google Cloud Vision para o provider `google-cloud-vision`.

## Stack

- Java 21
- Spring Boot 4.1.0
- PostgreSQL 16
- Flyway
- Docker Compose
- Storage local para uploads
- AWS SDK for Java v2
- Google Cloud Vision Java client

## Subir banco local

```powershell
docker compose up -d
```

O compose cria um PostgreSQL em `localhost:5433`:

- database: `vision_api_tester`
- user: `vision_api_tester`
- password: `vision_api_tester`

## Configurar AWS Rekognition

O backend usa o profile AWS local:

```text
vision-api-tester
```

Variaveis suportadas:

```powershell
$env:AWS_PROFILE="vision-api-tester"
$env:AWS_REGION="us-east-1"
$env:AWS_REKOGNITION_MIN_CONFIDENCE="55"
$env:AWS_REKOGNITION_MAX_LABELS="20"
```

## Configurar Google Cloud Vision

O backend usa Application Default Credentials (ADC) da Google Cloud CLI.

Projeto esperado:

```text
vision-api-tester-503219
```

Variaveis suportadas:

```powershell
$env:GOOGLE_CLOUD_PROJECT="vision-api-tester-503219"
$env:GOOGLE_CLOUD_VISION_MAX_RESULTS="20"
```

## Rodar backend

```powershell
.\mvnw.cmd spring-boot:run
```

Por padrao, a API sobe em `http://localhost:8080`.

## Variaveis suportadas

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`
- `SERVER_PORT`
- `STORAGE_ROOT`
- `CORS_ALLOWED_ORIGINS`
- `AWS_PROFILE`
- `AWS_REGION`
- `AWS_REKOGNITION_MIN_CONFIDENCE`
- `AWS_REKOGNITION_MAX_LABELS`
- `GOOGLE_CLOUD_PROJECT`
- `GOOGLE_CLOUD_VISION_MAX_RESULTS`

O storage padrao fica em `../storage/uploads`.

## Endpoints principais

```text
GET    /api/health
GET    /api/projects
POST   /api/projects
GET    /api/classification-categories
POST   /api/classification-categories
POST   /api/images
DELETE /api/images/{imageId}
POST   /api/images/{imageId}/analyze
PUT    /api/images/{imageId}/validation
POST   /api/provider-results
GET    /api/provider-results?imageId={uuid}
PUT    /api/provider-results/{providerRunId}/evaluation
GET    /api/history
GET    /api/dashboard
```

### Criar projeto

```json
POST /api/projects
{
  "name": "Hardware Lab",
  "description": "Avaliacao manual de objetos eletronicos"
}
```

### Upload de imagem

Envie `multipart/form-data` para `/api/images`:

- `projectId`: UUID do projeto
- `file`: arquivo de imagem

### Executar analise

```json
POST /api/images/{imageId}/analyze
{
  "providers": ["aws-rekognition", "google-cloud-vision"]
}
```

Comportamento atual:

- `aws-rekognition`: chama Amazon Rekognition real usando o profile AWS local.
- `google-cloud-vision`: chama Google Cloud Vision real usando ADC.

O endpoint salva `provider_runs`, `provider_labels` e `raw_response` no banco, retornando os resultados persistidos.

### Motor de classificacao de e-waste

Cada resultado de provider e classificado contra o catalogo ativo. O motor compara as labels com o codigo, o nome e os aliases de cada classe, normaliza acentos e pontuacao, exige limites completos de palavras e agrega evidencias de labels diferentes.

O `ProviderRun` persiste:

- `suggestedClass`, apenas quando a decisao e segura;
- `classificationStatus`: `CLASSIFIED`, `NO_MATCH`, `BELOW_THRESHOLD` ou `AMBIGUOUS`;
- `classificationScore` e `classificationMargin`;
- `classificationEngineVersion`;
- `classificationEvidence`, com label, termo reconhecido e contribuicao para o score.
- `ewasteEligibility`, calculada junto com a classificacao.

O score minimo atual e `50`, e a margem minima entre as duas classes mais bem pontuadas e `5`. Avaliacoes humanas continuam sendo a verdade de referencia e nao sao sobrescritas pela sugestao automatica.

Desde `ewaste-rules-v3`, evidencias adicionais usam retorno decrescente. A primeira evidencia define o score inicial; cada evidencia seguinte acrescenta apenas uma fracao do espaco restante ate 100:

```text
score += (100 - score) * (contribuicao / 100) * 0.20
```

Isso substitui a soma linear com corte em 100, que podia transformar candidatos diferentes em empates artificiais. O motor tambem preserva internamente os candidatos acima do threshold cuja diferenca para o vencedor esteja dentro da margem de ambiguidade.

`ELECTRONIC_DEVICE` e uma categoria generica para labels que identificam um objeto eletronico sem determinar sua classe exata. Categorias genericas nao competem no ranking da classe do objeto: se `ELECTRONIC_DEVICE` tiver score maior, mas `CHARGER` superar o threshold especifico, `CHARGER` permanece como sugestao. Sem evidencia especifica suficiente, `suggestedClass` permanece nulo, mas evidencia generica forte e coerente pode confirmar `ewasteEligibility = ELIGIBLE`.

O comportamento nao depende de listas espalhadas no motor. Cada categoria possui metadados persistidos:

- `categoryType`: `SPECIFIC`, `GENERIC` ou `FALLBACK`;
- `defaultEwasteEligibility`: `ELIGIBLE`, `NOT_ELIGIBLE` ou `REVIEW`.

Categorias amplas como `ELECTRONIC_DEVICE`, `COMPUTER_HARDWARE` e `ELECTRONIC_COMPONENT` sao configuradas como `GENERIC`. Classes de objeto como `CHARGER`, `PCB` e `PHONE` sao `SPECIFIC`. Os candidatos genericos continuam disponiveis para reforcar a decisao de elegibilidade, mas nao substituem a classe especifica.

O MVP retorna uma unica classe especifica. Uma evolucao futura podera modelar a taxonomia hierarquica e devolver simultaneamente a classe geral (`ELECTRONIC_DEVICE`) e uma classe especifica. A avaliacao humana continua sendo a verdade de referencia.

### Elegibilidade de e-lixo

O backend calcula `ewasteEligibility` no momento da classificacao e persiste a decisao no `ProviderRun`:

- `ELIGIBLE`: categoria especifica com `defaultEwasteEligibility = ELIGIBLE`, ou categoria especifica ainda nao categorizada reforcada por evidencia generica elegivel;
- `NOT_ELIGIBLE`: categoria classificada com `defaultEwasteEligibility = NOT_ELIGIBLE`;
- `REVIEW`: ausencia de evidencia suficiente, evidencia conflitante ou categoria sem metadado conclusivo;
- em `AMBIGUOUS`, `ELIGIBLE` quando todos os candidatos relevantes sao classes de e-lixo, `NOT_ELIGIBLE` quando todos sao `INVALID`, e `REVIEW` quando existe mistura de elegibilidade.

Assim, uma ambiguidade entre `CHARGER` e `ELECTRONIC_DEVICE` preserva a classe especifica como inconclusiva, mas retorna `ELIGIBLE`. O backend e a fonte de verdade; o frontend apenas exibe o valor persistido nos resultados e no historico. Registros anteriores a essa coluna recebem backfill conservador e nao sao reclassificados silenciosamente com uma versao futura do catalogo.

### Validacao humana e metricas independentes

A verdade humana pertence a imagem e e registrada uma unica vez em `PUT /api/images/{imageId}/validation`:

- `imageValidationStatus`: `VALID` ou `INVALID`;
- `humanIsEwaste`: verdade binaria quando a imagem e valida;
- `humanConfirmedClassId`: classe especifica opcional;
- `humanNote`: observacao opcional.

Cada `ProviderRun` preserva sua previsao automatica e recebe, sem sobrescreve-la, `eligibilityCorrect` e `classificationCorrect`. Um provider pode acertar a deteccao de e-lixo e errar a classe. `REVIEW` e imagem invalida nao sao convertidos em erro binario, e a identificacao especifica fica sem avaliacao quando o humano nao informou uma classe.

A Dashboard separa, por provider, acuracia de deteccao de e-lixo, precisao, recall, falsos positivos, falsos negativos, taxa de `REVIEW`, acuracia da classe especifica e taxa de classificacao especifica. O Historico mostra a verdade da imagem e as duas decisoes de cada provider.

Aliases podem ser cadastrados junto com uma classe:

```json
POST /api/classification-categories
{
  "code": "LAPTOP",
  "name": "Laptop",
  "aliases": ["Notebook", "Portable computer"]
}
```

O parametro `q` de `GET /api/classification-categories?q=notebook` pesquisa codigo, nome e aliases.

### Excluir imagem completa

```text
DELETE /api/images/{imageId}
```

Remove a imagem, suas analises, labels e avaliacoes associadas. O arquivo local tambem e removido do storage.

### Salvar resultado manualizado de provider

Este endpoint continua disponivel para testes manuais ou importacoes.

```json
POST /api/provider-results
{
  "imageId": "00000000-0000-0000-0000-000000000000",
  "provider": "AWS Rekognition",
  "responseTimeMs": 1260,
  "labels": [
    { "name": "Can", "confidence": 95.3 },
    { "name": "Tin", "confidence": 92.1 }
  ],
  "rawResponse": {
    "Labels": [
      { "Name": "Can", "Confidence": 95.3 }
    ],
    "ResponseMetadata": {
      "RequestId": "manual-request"
    }
  }
}
```

### Salvar avaliacao humana

```json
PUT /api/provider-results/{providerRunId}/evaluation
{
  "correctClassId": "00000000-0000-0000-0000-000000000001",
  "evaluationResult": "PARTIAL",
  "targetObject": true,
  "humanNote": "Identificou objeto semelhante, mas nao a classe esperada."
}
```
