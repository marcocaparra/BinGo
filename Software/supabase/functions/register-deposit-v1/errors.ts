export type PublicErrorCode =
  | "METHOD_NOT_ALLOWED"
  | "INVALID_DEPOSIT_CONTRACT"
  | "WASTE_CATEGORY_NOT_FOUND"
  | "DEPOSIT_CONTEXT_NOT_FOUND"
  | "EVENT_ID_CONFLICT"
  | "INTERNAL_ERROR";

const PUBLIC_MESSAGES: Readonly<Record<PublicErrorCode, string>> = Object
  .freeze({
    METHOD_NOT_ALLOWED: "Método não permitido.",
    INVALID_DEPOSIT_CONTRACT: "Contrato de descarte inválido.",
    WASTE_CATEGORY_NOT_FOUND: "Categoria de lixo eletrônico não encontrada.",
    DEPOSIT_CONTEXT_NOT_FOUND: "Contexto do descarte não encontrado.",
    EVENT_ID_CONFLICT:
      "Identificador de evento reutilizado com conteúdo diferente.",
    INTERNAL_ERROR: "Erro interno do servidor.",
  });

export function publicError(
  status: number,
  code: PublicErrorCode,
  headers?: HeadersInit,
): Response {
  const responseHeaders = new Headers(headers);
  responseHeaders.set("Cache-Control", "no-store");

  return Response.json(
    { error: { code, message: PUBLIC_MESSAGES[code] } },
    { status, headers: responseHeaders },
  );
}
