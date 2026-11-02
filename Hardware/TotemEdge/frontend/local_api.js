/* Apenas API local de mesma origem; sem configuração ou credenciais remotas. */
(function (root) {
  "use strict";
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const states = new Set(["IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED", "OPENING", "DOOR_OPEN", "CLOSING", "DOOR_CLOSED", "CAPTURING", "CLASSIFYING", "REVIEW", "RETURN_REQUIRED", "HATCH_IN_PROGRESS", "REGISTRATION_PENDING", "REGISTERING", "REGISTERED", "INDETERMINATE", "TECHNICAL_FAILURE", "CANCELLED", "COMPLETED"]);
  class LocalApiError extends Error {
    constructor(code, status = null) { super("Não foi possível confirmar a operação local."); this.code = code; this.status = status; }
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
    async request(path, body, metadata = false) {
      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), 10000);
      try {
        const response = await this.fetcher(path, { method: body === undefined ? "GET" : "POST", credentials: "same-origin", redirect: "error", cache: "no-store", signal: abort.signal, headers: body === undefined ? { Accept: "application/json" } : { Accept: "application/json", "Content-Type": "application/json", "X-Totem-Request": "1" }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
        if (!response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) throw new LocalApiError("INVALID_RESPONSE");
        const data = await response.json();
        if (!response.ok) throw new LocalApiError(typeof data?.error?.code === "string" ? data.error.code : "LOCAL_UNAVAILABLE", response.status);
        return metadata ? { data, runtime: response.headers.get("X-Totem-Runtime") } : data;
      } catch (error) {
        if (error instanceof LocalApiError) throw error;
        throw new LocalApiError(abort.signal.aborted || error?.name === "AbortError" ? "LOCAL_TIMEOUT" : "LOCAL_UNAVAILABLE");
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
  function journalEntry(entry, event) {
    const phases = { INTENT: 'PENDING', DISPATCHING: 'PENDING', ACCEPTED: 'PENDING', COMPLETED: 'SUCCEEDED', REJECTED: 'UNAVAILABLE', FAILED: 'FAILURE', TIMED_OUT: 'UNKNOWN', CANCELLED: 'UNKNOWN', INDETERMINATE: 'UNKNOWN', ABORTED: 'UNAVAILABLE' };
    if (!entry || entry.source !== 'SIMULATED' || entry.command?.event_id !== event || !uuid.test(entry.command?.mechanical_command_id) ||
        !['OPEN_INSERTION_DOOR', 'CLOSE_INSERTION_DOOR', 'CYCLE_LOWER_HATCH', 'CONFIRM_INITIAL_STATE'].includes(entry.command.operation) ||
        !Object.hasOwn(phases, entry.phase) || !(phases[entry.phase] === entry.result || entry.phase === 'FAILED' && entry.result === 'UNKNOWN')) throw new LocalApiError('INVALID_RESPONSE');
    return entry;
  }
  function devSnapshot(value) {
    const s = value?.session, identity = value?.identity;
    if (value?.economy != null) {
      const e = value.economy;
      if (!['AWAITING_COMPLETION','PENDING','CONFIRMED'].includes(e.status) || e.status !== 'CONFIRMED' && e.receipt !== null) throw new LocalApiError('INVALID_RESPONSE');
      if (e.status === 'CONFIRMED') snapshot({...s,state:'REGISTERED',receipt:e.receipt});
      if (e.status !== 'AWAITING_COMPLETION' && s?.state !== 'COMPLETED') throw new LocalApiError('INVALID_RESPONSE');
    }
    const actions = new Set(["identify", "safety", "cancel", "open", "close", "hatch", "confirm-initial", "review-fixture", "vision-review", "vision-analyze"]);
    if (value?.source !== "SIMULATED" || !s || !uuid.test(s.event_id) || !states.has(s.state) || !uuid.test(s.class_id) || !["student", "class_only"].includes(s.mode) || s.receipt !== null ||
        !Array.isArray(value.commands) || value.commands.some(c => !c || c.source !== "SIMULATED") ||
        !Array.isArray(value.allowed_actions) || value.allowed_actions.some(a => !actions.has(a)) || new Set(value.allowed_actions).size !== value.allowed_actions.length ||
        !(identity === null || typeof identity === "object" && identity)) throw new LocalApiError("INVALID_RESPONSE");
    if (identity) {
      if (s.mode !== "student" || identity.source !== "SUPABASE_DEV_PIN_V1" || identity.event_id !== s.event_id || identity.class_id !== s.class_id || identity.student_id !== s.student_id ||
          [identity.machine_id, identity.school_id, identity.class_id, identity.student_id].some(id => !uuid.test(id)) || typeof identity.project_ref !== "string" || !identity.project_ref ||
          typeof identity.validated_at !== "string" || !Number.isFinite(Date.parse(identity.validated_at)) || typeof s.student_name !== "string" || typeof s.class_name !== "string" || s.state === "IDENTIFYING") throw new LocalApiError("INVALID_RESPONSE");
    } else if (s.student_id !== null || s.mode === "student" && s.state === "SAFETY") throw new LocalApiError("INVALID_RESPONSE");
    value.commands.forEach(entry => journalEntry(entry, s.event_id));
    if (value.vision != null) {
      const v = value.vision, ids = ['battery', 'cable', 'phone', 'small', 'unknown'];
      const r = v.observation;
      if (r?.detected_types != null && (typeof r.detected_types !== 'object' || Array.isArray(r.detected_types) || Object.entries(r.detected_types).some(([id, name]) => !r.candidateIds?.includes(id) || typeof name !== 'string' || !name.trim() || name.length > 120))) throw new LocalApiError('INVALID_RESPONSE');
      if (!Array.isArray(v.allowed_candidates) || v.allowed_candidates.some(id => !ids.includes(id)) || new Set(v.allowed_candidates).size !== v.allowed_candidates.length || v.allowed_candidates.some(id => id !== 'unknown' && !r?.candidateIds.includes(id)) || v.allowed_candidates.length && (v.phase !== 'COMPLETED' || r?.status !== 'recognized')) throw new LocalApiError('INVALID_RESPONSE');
      if (v.event_id !== s.event_id || !uuid.test(v.capture_id) || !uuid.test(v.close_command_id) ||
          !value.commands.some(c => c.command.mechanical_command_id === v.close_command_id && c.command.operation === 'CLOSE_INSERTION_DOOR' && c.phase === 'COMPLETED') ||
          !['CAPTURING', 'CLASSIFYING', 'COMPLETED', 'FAILED'].includes(v.phase) ||
          r && (!['recognized', 'rejected', 'needs-secondary'].includes(r.status) || !Array.isArray(r.candidateIds) || r.candidateIds.some(id => !ids.includes(id)) ||
          new Set(r.candidateIds).size !== r.candidateIds.length || typeof r.confidence !== 'number' || !Number.isFinite(r.confidence) || r.confidence < 0 || r.confidence > 1 ||
          !['AWS_REKOGNITION', 'GEMINI_FALLBACK'].includes(r.origin) || r.status === 'recognized' && (!ids.includes(r.itemId) || !r.candidateIds.includes(r.itemId))) ||
          v.phase === 'COMPLETED' && !r || v.decision && (!r || r.status !== 'recognized' || !ids.includes(v.decision.item_id) || !v.allowed_candidates.includes(v.decision.item_id) || !['confirm', 'correct'].includes(v.decision.action))) throw new LocalApiError('INVALID_RESPONSE');
    }
    return value;
  }
  class DevApi extends LocalApi {
    async visionAnalyze(id, captureId, analysisAttemptId) {
      if (!uuid.test(id) || !uuid.test(captureId) || analysisAttemptId !== undefined && !uuid.test(analysisAttemptId)) throw new LocalApiError('INVALID_ID');
      const body = { capture_id: captureId };
      if (analysisAttemptId !== undefined) body.analysis_attempt_id = analysisAttemptId;
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/vision-analyze`, body));
      if (value.session.event_id !== id || value.vision?.capture_id !== captureId) throw new LocalApiError('INVALID_RESPONSE');
      return value;
    }
    async photo(id, captureId) {
      if (!uuid.test(id) || !uuid.test(captureId)) throw new LocalApiError('INVALID_ID');
      const abort = new AbortController();
      const timer = setTimeout(() => abort.abort(), 10000);
      try {
        const response = await this.fetcher(`/local/simulation/sessions/${id}/vision-image/${captureId}`, { headers: { Accept: 'image/jpeg', 'X-Totem-Request': '1' }, credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: abort.signal });
        if (!response.ok) throw new LocalApiError('VISION_IMAGE_UNAVAILABLE', response.status);
        if (response.headers.get('content-type') !== 'image/jpeg' || response.headers.get('x-capture-id') !== captureId) throw new LocalApiError('INVALID_RESPONSE');
        const blob = await response.blob();
        if (!blob.size || blob.size > 5 * 1024 * 1024) throw new LocalApiError('INVALID_RESPONSE');
        return blob;
      } catch (error) {
        if (error instanceof LocalApiError) throw error;
        throw new LocalApiError(abort.signal.aborted || error?.name === 'AbortError' ? 'LOCAL_TIMEOUT' : 'LOCAL_UNAVAILABLE');
      } finally { clearTimeout(timer); }
    }

    async visionReview(id, captureId, itemId, action) {
      if (!uuid.test(id) || !uuid.test(captureId) || !['battery', 'cable', 'phone', 'small', 'unknown'].includes(itemId) || !['confirm', 'correct'].includes(action)) throw new LocalApiError('INVALID_LOCAL_CONTRACT', 422);
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/vision-review`, { capture_id: captureId, item_id: itemId, action }));
      if (value.session.event_id !== id || value.vision?.capture_id !== captureId || value.vision?.decision?.item_id !== itemId || value.vision?.decision?.action !== action) throw new LocalApiError('INVALID_RESPONSE');
      return value;
    }
    async action() { throw new LocalApiError("DEV_ACTION_NOT_SUPPORTED"); }
    async isDev() {
      const response = await this.request("/health", undefined, true);
      if (response.data?.status !== "ok") throw new LocalApiError("INVALID_RESPONSE");
      return response.runtime === "dev-integration";
    }
    async health() {
      const data = await this.request("/local/dev/health");
      if (data?.central !== "AVAILABLE" || !((data.scope === "SUPABASE_DEV_READ_ONLY" && data.economic_registration === false) || (data.scope === "SUPABASE_DEV_ECONOMIC" && data.economic_registration === true)) || data.mechanical_source !== "SIMULATED") throw new LocalApiError("INVALID_RESPONSE");
      return data;
    }
    async context() {
      const data = await this.request("/local/dev/context");
      if (!data || [data.school, data.machine].some(n => !n || !uuid.test(n.id) || typeof n.name !== "string") || !Array.isArray(data.classes) || !Array.isArray(data.students) ||
          data.classes.some(c => !c || !uuid.test(c.id) || typeof c.name !== "string" || c.segment !== null && typeof c.segment !== "string" || c.grade !== null && typeof c.grade !== "string") ||
          data.students.some(s => !s || !uuid.test(s.id) || !uuid.test(s.class_id) || typeof s.name !== "string" || s.status !== "ACTIVE" || !data.classes.some(c => c.id === s.class_id)) ||
          new Set(data.classes.map(c => c.id)).size !== data.classes.length || new Set(data.students.map(s => s.id)).size !== data.students.length) throw new LocalApiError("INVALID_RESPONSE");
      return data;
    }
    async active() {
      const data = await this.request("/local/simulation/sessions/active");
      if (!data || !Object.hasOwn(data, "snapshot")) throw new LocalApiError("INVALID_RESPONSE");
      return data.snapshot === null ? null : devSnapshot(data.snapshot);
    }
    async start(commandId) {
      if (!uuid.test(commandId)) throw new LocalApiError("INVALID_LOCAL_CONTRACT", 422);
      return devSnapshot(await this.request("/local/simulation/sessions", { command_id: commandId }));
    }
    async session(id) {
      if (!uuid.test(id)) throw new LocalApiError("INVALID_ID");
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}`));
      if (value.session.event_id !== id) throw new LocalApiError("INVALID_RESPONSE");
      return value;
    }
    async identify(id, classId, studentId, pin) {
      const body = { class_id: classId, student_id: studentId, pin };
      try {
        if (![id, classId, studentId].every(value => uuid.test(value)) || typeof pin !== "string" || !/^[0-9]{4}$/.test(pin)) throw new LocalApiError("INVALID_LOCAL_CONTRACT", 422);
        const value = devSnapshot(await this.request(`/local/dev/sessions/${id}/identity`, body));
        if (value.session.event_id !== id || value.identity?.class_id !== classId || value.identity?.student_id !== studentId || !value.identity) throw new LocalApiError("INVALID_RESPONSE");
        return value;
      } finally { body.pin = ""; pin = ""; }
    }
    async safety(id, hasRisk) {
      if (!uuid.test(id) || typeof hasRisk !== "boolean") throw new LocalApiError("INVALID_LOCAL_CONTRACT", 422);
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/safety`, { has_risk: hasRisk }));
      if (value.session.event_id !== id || !value.identity || ["IDENTIFYING", "AUTHENTICATING", "SAFETY"].includes(value.session.state) ||
          hasRisk && (value.session.state !== "CANCELLED" || value.session.failure_code !== "SAFETY_RISK")) throw new LocalApiError("INVALID_RESPONSE");
      return value;
    }
    async motion(id, operation, commandId, options = {}) {
      if (!uuid.test(id) || !uuid.test(commandId) || !['open', 'close', 'hatch'].includes(operation) ||
          (operation !== 'close' ? typeof options.pin !== 'string' || !/^[0-9]{4}$/.test(options.pin) || Object.keys(options).some(k => k !== 'pin') : options.hand_removed !== true || Object.keys(options).some(k => k !== 'hand_removed'))) throw new LocalApiError('INVALID_LOCAL_CONTRACT', 422);
      const body = { mechanical_command_id: commandId, ...options };
      try {
        const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/${operation}`, body));
        if (value.session.event_id !== id) throw new LocalApiError('INVALID_RESPONSE');
        const entry = value.commands.find(c => c.command.mechanical_command_id === commandId);
        if (!entry || entry.command.operation !== ({ open: 'OPEN_INSERTION_DOOR', close: 'CLOSE_INSERTION_DOOR', hatch: 'CYCLE_LOWER_HATCH' })[operation]) throw new LocalApiError('INVALID_RESPONSE');
        return value;
      } finally { if ('pin' in body) body.pin = ''; }
    }
    async reviewFixture(id) {
      if (!uuid.test(id)) throw new LocalApiError('INVALID_ID');
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/review-fixture`, {}));
      if (value.session.event_id !== id || !value.identity || value.session.state !== 'REVIEW') throw new LocalApiError('INVALID_RESPONSE');
      return value;
    }
    async journal(id, commandId) {
      if (!uuid.test(id) || !uuid.test(commandId)) throw new LocalApiError('INVALID_ID');
      const value = await this.request(`/local/simulation/sessions/${id}/commands/${commandId}`);
      if (value?.source !== 'SIMULATED' || !Array.isArray(value.history) || journalEntry(value.command, id).command.mechanical_command_id !== commandId) throw new LocalApiError('INVALID_RESPONSE');
      return value;
    }
    async cancel(id) {
      if (!uuid.test(id)) throw new LocalApiError("INVALID_ID");
      const value = devSnapshot(await this.request(`/local/simulation/sessions/${id}/cancel`, {}));
      if (value.session.event_id !== id) throw new LocalApiError("INVALID_RESPONSE");
      return value;
    }
  }
  function schoolLabels(classes, segment) {
    const labels = { ENSINO_MEDIO: "ENSINO MÉDIO", FUNDAMENTAL_2: "ENSINO FUNDAMENTAL 2" };
    const selected = classes.filter(c => c.segment === segment);
    return {
      segments: classes.every(c => c.segment) ? [...new Set(classes.map(c => c.segment))].map(id => ({ id, name: labels[id] || id })) : [],
      grades: selected.every(c => c.grade) ? [...new Set(selected.map(c => c.grade))].map(id => {
        const match = String(id).match(/^([1-9])(?:[º°ªo])?(?:\s*[_ -]?\s*ANO)?$/i);
        const valid = segment === "ENSINO_MEDIO" ? [1, 2, 3] : segment === "FUNDAMENTAL_2" ? [6, 7, 8, 9] : [];
        return { id, name: match && valid.includes(Number(match[1])) ? `${match[1]}° ANO` : id };
      }) : [],
    };
  }
  function studentType(vision, id) {
    const unknown = 'Lixo eletrônico não identificado';
    if (id === 'unknown') return unknown;
    const value = vision?.observation?.detected_types?.[id];
    const names = { headphones: 'Fone de ouvido', headset: 'Fone de ouvido', earphones: 'Fone de ouvido', 'computer mouse': 'Mouse', mouse: 'Mouse', keyboard: 'Teclado', 'printed circuit board': 'Placa eletrônica', 'electronic component': 'Componente eletrônico', 'battery charger': 'Carregador de bateria', battery: 'Pilha ou bateria', 'alkaline battery': 'Pilha alcalina', 'lithium battery': 'Bateria de lítio', cable: 'Cabo', 'usb cable': 'Cabo USB', wire: 'Fio', wiring: 'Fiação', 'electrical wiring': 'Fiação elétrica', 'power cord': 'Cabo de alimentação', 'mobile phone': 'Celular', 'cell phone': 'Celular', smartphone: 'Celular', telephone: 'Telefone' };
    if (typeof value === 'string' && value.trim() && value.length <= 120 && !/\b(small|medium|large|pequeno|médio|medio|grande|aws|rekognition|gemini|fallback)\b|item pequeno|eletr[oô]nico pequeno/i.test(value)) return names[value.toLowerCase()] || value;
    return ({ battery: 'Pilha ou bateria', cable: 'Cabo', phone: 'Celular' })[id] || unknown;
  }
  root.BinGoLocalApi = { LocalApi, LocalApiError, DevApi, schoolLabels, studentType };
  if (typeof module !== "undefined") module.exports = root.BinGoLocalApi;
})(typeof window === "undefined" ? globalThis : window);
