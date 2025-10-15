
# Contrato de API – Integração Hardware BinGo

Este documento detalha o contrato de integração entre o hardware (lixeira inteligente) e o backend do BinGo, refletindo o funcionamento real do sistema.

---

## 1. Fluxo de Integração

1. **Captura e envio da imagem:**
   - O hardware captura a imagem do descarte e envia para o backend via API REST.
2. **Classificação e geração de código:**
   - O backend processa a imagem, classifica o material e, se necessário, gera um código único de descarte.
3. **Retorno para o hardware:**
   - O backend retorna o resultado da classificação e o código (se aplicável) para o hardware.

---

## 2. Endpoint Principal

- **URL:** `/device/classify_image`
- **Método:** `POST`
- **Content-Type:** `application/json`
- **Descrição:** Recebe uma imagem em Base64, classifica o material e retorna o resultado.

---

## 3. Requisição

```json
{
  "image_base64": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/4g..."
}
```

---

## 4. Resposta

### 4.1. Item Eletrônico
```json
{
  "status": "success",
  "message": "Item classificado como Eletrônico. Código único gerado.",
  "classification": "Eletrônico",
  "unique_code": "BIN001-XYZ-12345"
}
```

### 4.2. Item Não Eletrônico
```json
{
  "status": "success",
  "message": "Item classificado como Não Eletrônico. Não é necessário código.",
  "classification": "Não Eletrônico"
}
```

### 4.3. Erro
```json
{
  "status": "error",
  "message": "Erro ao processar a imagem: Formato inválido ou dados corrompidos."
}
```

---

## 5. Códigos de Status HTTP

| Código | Descrição           | Significado                                                        |
|--------|---------------------|--------------------------------------------------------------------|
| 200    | OK                  | Requisição processada com sucesso; resposta contém a classificação.|
| 400    | Bad Request         | Dados inválidos ou imagem ausente/corrompida.                      |
| 500    | Internal Server Error| Erro inesperado no backend.                                        |

---

## 6. Observações Práticas

- O campo `unique_code` só é retornado para itens classificados como "Eletrônico".
- Para outros materiais, o campo não aparece.
- O backend valida o formato da imagem e retorna erro se estiver inválido.
- O endpoint pode ser expandido para outros tipos de materiais no futuro.
- O fluxo de integração é assíncrono e tolerante a falhas: o hardware pode reprocessar ou reenviar em caso de erro.

---