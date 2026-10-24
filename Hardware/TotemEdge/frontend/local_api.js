/* Apenas API local de mesma origem; sem configuração ou credenciais remotas. */
(function (root) {
  "use strict";
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const states = new Set(["IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED", "OPENING", "DOOR_OPEN", "CLOSING", "DOOR_CLOSED", "CAPTURING", "CLASSIFYING", "REVIEW", "RETURN_REQUIRED", "HATCH_IN_PROGRESS", "REGISTRATION_PENDING", "REGISTERING", "REGISTERED", "INDETERMINATE", "TECHNICAL_FAILURE", "CANCELLED", "COMPLETED"]);
  class LocalApiError extends Error {
    constructor(code) { super("Não foi possível confirmar a operação local."); this.code = code; }
  }
  function snapshot(value) {
    if (!value || !uuid.test(value.event_id) || !states.has(value.state) || !["student", "class_only"].includes(value.mode) || !uuid.test(value.class_id)) throw new LocalApiError("INVALID_RESPONSE");
    const confirmed = ["REGISTERED", "COMPLETED"].includes(value.state);
    const receipt = value.receipt;
    if (confirmed && (!receipt || receipt.event_id !== value.event_id || !uuid.test(receipt.id) || ["points_awarded_student", "points_awarded_class", "bonus_bincoins_awarded"].some(key => !Number.isSafeInteger(receipt[key]) || receipt[key] < 0))) throw new LocalApiError("INVALID_RESPONSE");
    if (!confirmed && receipt !== null) throw new LocalApiError("INVALID_RESPONSE");
    return value;
  }
  class LocalApi {
    constructor(fetcher = root.fetch.bind(root)) { this.fetcher = fetcher; }
    async request(path, body) {
      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), 10000);
      try {
        const response = await this.fetcher(path, { method: body === undefined ? "GET" : "POST", credentials: "same-origin", cache: "no-store", signal: abort.signal, headers: body === undefined ? { Accept: "application/json" } : { Accept: "application/json", "Content-Type": "application/json", "X-Totem-Request": "1" }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
        if (!response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new LocalApiError("INVALID_RESPONSE");
        const data = await response.json();
        if (!response.ok) throw new LocalApiError(typeof data?.error?.code === "string" ? data.error.code : "LOCAL_UNAVAILABLE");
        return data;
      } catch (error) {
        if (error instanceof LocalApiError) throw error;
        throw new LocalApiError("LOCAL_UNAVAILABLE");
      } finally { clearTimeout(timer); }
    }
    async status() {
      const data = await this.request("/local/status");
      if (!data || !["ONLINE", "OFFLINE"].includes(data.status) || typeof data.can_start_deposit !== "boolean" || (data.status === "ONLINE") !== data.can_start_deposit || (data.can_start_deposit ? data.message !== null : typeof data.message !== "string")) throw new LocalApiError("INVALID_RESPONSE");
      return data;
    }
    async active() {
      const data = await this.request("/local/sessions/active");
      if (!data || !Object.hasOwn(data, "session")) throw new LocalApiError("INVALID_RESPONSE");
      return data.session === null ? null : snapshot(data.session);
    }
    async context() {
      const data = await this.request("/local/context");
      if (!data || !Array.isArray(data.classes) || !Array.isArray(data.students) || data.classes.some(c => !uuid.test(c.id) || typeof c.name !== "string") || data.students.some(s => !uuid.test(s.id) || !uuid.test(s.class_id) || typeof s.name !== "string")) throw new LocalApiError("INVALID_RESPONSE");
      return data;
    }
    async start(body) { return snapshot(await this.request("/local/sessions", body)); }
    async session(id) { if (!uuid.test(id)) throw new LocalApiError("INVALID_ID"); return snapshot(await this.request(`/local/sessions/${id}`)); }
    async action(id, action, body = {}) {
      if (!uuid.test(id) || !["pin", "safety", "hand-removed", "cancel", "retry-registration", "finish"].includes(action)) throw new LocalApiError("INVALID_ID");
      return snapshot(await this.request(`/local/sessions/${id}/${action}`, body));
    }
  }
  root.BinGoLocalApi = { LocalApi, LocalApiError };
  if (typeof module !== "undefined") module.exports = root.BinGoLocalApi;
})(typeof window === "undefined" ? globalThis : window);
