# Contrato de API para Integração de Hardware (Lixeira Inteligente)

Este documento define o contrato da API para comunicação entre a lixeira inteligente (hardware) e o backend do sistema BinGo. São especificados endpoints, formatos de requisição e resposta, além dos códigos de status HTTP.

---

## 1. Endpoint Principal

- **Função:** Enviar uma imagem capturada pela lixeira para classificação e, se aplicável, geração de código único de descarte.
- **URL:** `/device/classify_image`
- **Método:** `POST`
- **Content-Type:** `application/json`

---

## 2. Formato da Requisição

A requisição deve conter um JSON com o campo `image_base64`, representando a imagem codificada em Base64.

### Exemplo

```json
{
  "image_base64": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/4g..."
}
```

---

## 3. Formato da Resposta

A resposta será um JSON com o resultado da classificação e, se aplicável, o código único gerado.

### 3.1. Resposta para Item Eletrônico

```json
{
  "status": "success",
  "message": "Item classificado como Eletrônico. Código único gerado.",
  "classification": "Eletrônico",
  "unique_code": "BIN001-XYZ-12345"
}
```

### 3.2. Resposta para Item Não Eletrônico

```json
{
  "status": "success",
  "message": "Item classificado como Não Eletrônico. Não é necessário código.",
  "classification": "Não Eletrônico"
}
```

### 3.3. Resposta de Erro

```json
{
  "status": "error",
  "message": "Erro ao processar a imagem: Formato inválido ou dados corrompidos."
}
```

---

## 4. Códigos de Status HTTP

| Código | Descrição                   | Significado                                                                 |
|--------|-----------------------------|-----------------------------------------------------------------------------|
| 200    | OK                          | Requisição processada com sucesso; resposta contém a classificação.         |
| 400    | Bad Request                 | Corpo da requisição malformado ou dados inválidos (ex.: image_base64 ausente ou corrompido). |
| 500    | Internal Server Error       | Erro inesperado no backend ao processar a requisição.                       |

---

## 5. Observações

- O campo `unique_code` só será retornado quando o item for classificado como "Eletrônico".
- Para outros tipos de materiais, o campo `unique_code` não estará presente na resposta.
- Certifique-se de enviar imagens válidas e corretamente codificadas em Base64.