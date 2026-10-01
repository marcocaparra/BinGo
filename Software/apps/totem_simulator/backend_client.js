(function (root) {
  "use strict";
  const PENDING_KEY = "bingo.totem.pending-deposit.v1";
  const fields = [
    "event_id",
    "class_id",
    "student_id",
    "is_valid",
    "detected_type",
    "waste_category_code",
    "category_source",
  ];
  const uuid =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  class BackendError extends Error {
    constructor(message, status = 0, code = "BACKEND_RESULT_UNKNOWN") {
      super(message);
      this.status = status;
      this.code = code;
    }
  }
  function loopbackUrl(value) {
    const url = new URL(value);
    if (
      !["http:", "https:"].includes(url.protocol) ||
      !["127.0.0.1", "localhost"].includes(url.hostname) ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    ) {
      throw new Error("O browser deve acessar somente o serviço loopback.");
    }
    return url;
  }
  function validatePending(payload) {
    if (
      !payload ||
      Object.keys(payload).length !== fields.length ||
      fields.some((key) => !Object.hasOwn(payload, key)) ||
      !uuid.test(payload.event_id) ||
      !uuid.test(payload.class_id) ||
      (payload.student_id !== null && !uuid.test(payload.student_id)) ||
      typeof payload.is_valid !== "boolean" ||
      (payload.detected_type !== null &&
        typeof payload.detected_type !== "string") ||
      (payload.is_valid
        ? ![
            "BATTERY",
            "CABLE_WIRE",
            "MOBILE_DEVICE",
            "PERIPHERAL",
            "OTHER_EWASTE",
          ].includes(payload.waste_category_code) ||
          !["AI_CONFIRMED", "USER_CORRECTED"].includes(payload.category_source)
        : payload.waste_category_code !== null ||
          payload.category_source !== null)
    ) {
      throw new Error(
        "Registro local pendente inválido. Não inicie outro ciclo; preserve o armazenamento para diagnóstico.",
      );
    }
    return payload;
  }
  function createClient({
    baseUrl = root.BinGoRuntime?.baseUrl ?? "http://127.0.0.1:8765",
    fetchImpl = (...args) => root.fetch(...args),
    storage = root.localStorage,
    timeoutMs = 20000,
  } = {}) {
    const cloud = root.BinGoRuntime?.mode === "cloud";
    if (cloud && baseUrl !== "")
      throw new Error("Cloud demo must use same-origin paths.");
    const base = cloud ? "" : loopbackUrl(baseUrl).href.replace(/\/$/, "");
    async function request(path, payload) {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetchImpl(`${base}/bingo/${path}`, {
          method: payload === undefined ? "GET" : "POST",
          headers: { "Content-Type": "application/json" },
          body: payload === undefined ? undefined : JSON.stringify(payload),
          signal: controller.signal,
        });
        let body;
        try {
          body = await response.json();
        } catch {
          throw new BackendError(
            "Resposta inválida do backend.",
            response.status,
            "INVALID_BACKEND_RESPONSE",
          );
        }
        if (!response.ok)
          throw new BackendError(
            body.error?.message || "Não foi possível concluir a operação.",
            response.status,
            body.error?.code,
          );
        if (!body || typeof body !== "object" || Array.isArray(body))
          throw new BackendError(
            "Resposta inválida do backend.",
            response.status,
            "INVALID_BACKEND_RESPONSE",
          );
        return { status: response.status, body };
      } catch (error) {
        if (error instanceof BackendError) throw error;
        throw new BackendError(
          "Sem confirmação do backend. Tente novamente com o mesmo evento.",
        );
      } finally {
        clearTimeout(timer);
      }
    }
    function pending() {
      const raw = storage.getItem(PENDING_KEY);
      return raw === null ? null : validatePending(JSON.parse(raw));
    }
    return {
      request: async (path, payload) => (await request(path, payload)).body,
      async readiness() {
        const { status, body } = await request("health");
        if (
          status !== 200 ||
          body.status !== "AVAILABLE" ||
          body.can_start_deposit !== true
        )
          throw new BackendError(
            "Backend indisponível. Nenhum novo item pode ser recebido.",
            status,
            "BACKEND_UNAVAILABLE",
          );
        return body;
      },
      pending,
      commit(payload) {
        validatePending(payload);
        const current = pending();
        if (current && JSON.stringify(current) !== JSON.stringify(payload))
          throw new Error(
            "Já existe um evento aguardando confirmação. Recupere-o antes de iniciar outro.",
          );
        // This durable write is the simulator's irreversible item-drop point.
        // If storage fails, nothing is sent and the item is not received.
        storage.setItem(PENDING_KEY, JSON.stringify(payload));
        return pending();
      },
      async retryPending() {
        const payload = pending();
        if (!payload) throw new Error("Nenhum evento pendente.");
        const { status, body } = await request("deposits", payload);
        if (
          ![200, 201].includes(status) ||
          body.event_id !== payload.event_id ||
          !uuid.test(body.id) ||
          [
            "points_awarded_student",
            "points_awarded_class",
            "bonus_bincoins_awarded",
          ].some((key) => !Number.isSafeInteger(body[key]) || body[key] < 0)
        ) {
          throw new BackendError(
            "Registro ainda sem confirmação válida. Preserve o evento.",
            status,
            "INVALID_BACKEND_RESPONSE",
          );
        }
        // A confirmed write remains confirmed even if cleanup fails. Retrying
        // the durable copy is safe and must not initiate a second cycle.
        try {
          storage.removeItem(PENDING_KEY);
        } catch {
          return { payload, deposit: body, cleanupFailed: true };
        }
        return { payload, deposit: body };
      },
    };
  }
  root.BinGoBackend = { createClient, loopbackUrl, BackendError, PENDING_KEY };
  if (typeof module !== "undefined" && module.exports)
    module.exports = root.BinGoBackend;
})(globalThis);
