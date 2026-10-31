/* A interface apresenta estado recebido; nunca promove etapas físicas por timer. */
window.BinGoOperational = {
  async start(kiosk, visuals) {
    "use strict";
    const api = new window.BinGoLocalApi.LocalApi();
    const { assets, talk, topbar, keyboardRows, normalize } = visuals;
    let session = null, context = null, stage = "loading", mode = "student";
    let segment = null, grade = null, studentId = null, pin = "", command = null;
    let busy = false, warning = "", filter = "", searchActive = false, keyboardShift = true;
    const escape = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
    const button = (label, action, value = "", primary = true) => `<button class="${primary ? "primary-action" : "secondary-action"}" data-op="${action}" data-value="${escape(value)}" ${busy ? "disabled" : ""}>${escape(label)}</button>`;
    const list = (label, action, value) => `<button class="list-button" data-op="${action}" data-value="${escape(value)}" ${busy || action === "class" && command ? "disabled" : ""}><span>${escape(label)}</span></button>`;
    function searchKeyboard() {
      if (!searchActive) return "";
      const key = (label, value, wide = false) => `<button class="keyboard-key ${wide ? "keyboard-key--wide" : ""}" data-op="search-key" data-value="${escape(value)}">${escape(label)}</button>`;
      return `<div class="visual-keyboard">${keyboardRows.map(row => `<div class="keyboard-row">${row.map(letter => key(keyboardShift ? letter.toUpperCase() : letter, letter)).join("")}</div>`).join("")}<div class="keyboard-row">${key("Maiúsculas", "shift", true)}${key("Espaço", "space", true)}${key("Apagar", "backspace", true)}${key("Fechar", "close", true)}</div></div>`;
    }
    function panel(title, text, actions = "") {
      return `<section class="screen screen--corner screen--stack-action" data-operational-state="${escape(session?.state || stage)}">${topbar(title, { back: false })}<div class="content-zone content-zone--corner">${talk(assets.b1nIdeaCorner, escape(text), "corner")}<div class="status-panel"><strong>${escape(title)}</strong>${warning ? `<p role="alert">${escape(warning)}</p>` : ""}</div></div><div class="action-zone action-zone--stack">${actions}</div></section>`;
    }
    function render() {
      let html;
      if (stage === "loading") html = panel("Verificando", "Consultando o serviço local do Totem.");
      else if (stage === "unavailable") html = panel("Totem temporariamente indisponível", "A operação real está bloqueada. Tente novamente ou chame um responsável.", button("Verificar novamente", "status") + (["IDENTIFYING", "SAFETY", "PHYSICAL_BLOCKED"].includes(session?.state) ? button("Cancelar preparação", "cancel", "", false) : ""));
      else if (!session && stage === "idle") html = panel("Pronto", "Trouxe um eletrônico sem uso? Eu te guio.", button("Iniciar descarte", "begin"));
      else if (!session && stage === "identity") html = panel("Participar", "Como você quer participar?", button("Participar com meu perfil", "mode", "student") + button("Contribuir só com a turma", "mode", "class_only", false));
      else if (!session && stage === "segment") html = panel("Segmento", "Escolha seu segmento.", `<div class="list">${[...new Set(context.classes.map(c => c.segment || "Turmas"))].map(s => list(s, "segment", s)).join("")}</div>`);
      else if (!session && stage === "year") html = panel("Ano", "Escolha seu ano ou série.", `<div class="list">${[...new Set(context.classes.filter(c => (c.segment || "Turmas") === segment).map(c => c.grade || "Turmas"))].map(g => list(g, "grade", g)).join("")}</div>`);
      else if (!session && stage === "class") html = panel("Turma", "Escolha sua turma.", `<div class="list">${context.classes.filter(c => (c.segment || "Turmas") === segment && (c.grade || "Turmas") === grade).map(c => list(c.name, "class", c.id)).join("") || "Nenhuma turma disponível."}</div>` + (command ? button("Retomar tentativa", "resume-start") : "") + button("Cancelar", "reset-selection", "", false));
      else if (session?.state === "IDENTIFYING" && stage !== "pin") html = `<section class="screen screen--student screen--no-action ${searchActive ? "is-searching" : ""}" data-operational-state="IDENTIFYING">${topbar("Aluno", { back: false })}<div class="student-layout">${talk(assets.b1nDoubtCorner, "Busque ou escolha seu nome.", "corner student-guide")}<button class="search-box" data-op="search-toggle" aria-label="Busca de aluno">${escape(filter || "Digite seu nome...")}</button><div class="student-list">${context?.students.filter(s => s.class_id === session.class_id && normalize(s.name).includes(normalize(filter))).map(s => list(s.name, "student", s.id)).join("") || "Nenhum aluno disponível."}</div>${searchKeyboard()}<p role="alert">${escape(warning)}</p></div><div class="action-zone">${button("Cancelar", "cancel", "", false)}</div></section>`;
      else if (session?.state === "IDENTIFYING") html = `<section class="screen screen--pin" data-operational-state="IDENTIFYING">${topbar("PIN", { back: false })}<div class="content-zone content-zone--pin">${talk(assets.b1nPrivacyCorner, "Digite seu PIN de quatro números.", "corner character-privacy")}<div class="pin-display">${[0, 1, 2, 3].map(i => `<span class="pin-dot ${i < pin.length ? "filled" : ""}"></span>`).join("")}</div><div class="pin-pad">${["1", "2", "3", "4", "5", "6", "7", "8", "9", "Apagar", "0", "OK"].map(key => `<button class="key" data-op="pin-key" data-value="${key}" ${busy || (key === "OK" && pin.length !== 4) ? "disabled" : ""}>${key}</button>`).join("")}</div><p role="alert">${escape(warning)}</p></div><div class="action-zone">${button("Cancelar", "cancel", "", false)}</div></section>`;
      else if (session?.state === "SAFETY") html = panel("Segurança", "O objeto apresenta vazamento, estufamento, líquidos, partes cortantes ou outro risco?", button("Não apresenta risco", "safe") + button("Apresenta risco", "risk", "", false));
      else if (session?.state === "PHYSICAL_BLOCKED") html = panel("Integração física pendente", "Nenhum movimento foi solicitado. O equipamento ainda não está homologado.", button("Encerrar preparação", "cancel"));
      else if (session?.state === "DOOR_OPEN") html = panel("Posicione um único item", "Depois de posicionar o objeto, retire a mão do compartimento.", button("Retirei a mão", "hand-removed"));
      else if (session?.state === "REGISTRATION_PENDING") html = panel("Registro pendente", "O ciclo confirmado está preservado. Não faça outro descarte. A recompensa aguarda confirmação central.", button("Tentar registrar novamente", "retry-registration"));
      else if (session?.state === "REGISTERED") {
        const receipt = session.receipt; // Validado pelo cliente: sucesso depende do recibo central.
        html = `<section class="screen screen--success" data-operational-state="REGISTERED">${topbar("Concluído", { back: false })}<div class="content-zone content-zone--success">${talk(assets.b1nReward, "Descarte registrado pelo backend central.", "big character-reward")}<div class="reward-list"><div class="metric"><span>XP da turma</span><strong>+${receipt.points_awarded_class}</strong></div>${session.mode === "student" ? `<div class="metric"><span>Seus BinCoins</span><strong>+${receipt.points_awarded_student}</strong></div>` : ""}</div></div><div class="action-zone">${button("Concluir", "finish")}</div></section>`;
      } else if (["INDETERMINATE", "TECHNICAL_FAILURE", "RETURN_REQUIRED"].includes(session?.state)) html = panel("Chame um responsável", session.state === "RETURN_REQUIRED" ? "O objeto foi recusado. A devolução depende da integração física; nenhum descarte válido foi registrado." : "O estado do ciclo exige recuperação. Novos descartes estão bloqueados.", button("Atualizar estado", "refresh"));
      else if (["CANCELLED", "COMPLETED"].includes(session?.state)) html = panel("Sessão encerrada", session.state === "CANCELLED" ? "A preparação foi cancelada sem descarte." : "O registro está confirmado.", button("Voltar ao início", "status"));
      else html = panel("Aguardando confirmação", "Esta etapa depende de uma confirmação efetiva do serviço local.", button("Atualizar estado", "refresh"));
      kiosk.innerHTML = html;
    }
    async function checkStatus() {
      pin = ""; studentId = null; command = null; warning = ""; stage = "loading"; render();
      // Recuperação é consultada mesmo offline; não descartar ciclo ativo no browser.
      session = await api.active();
      const status = await api.status();
      if (session) {
        stage = "session";
        if (session.state === "IDENTIFYING" && status.can_start_deposit) context = await api.context();
        if (["IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED"].includes(session.state) && !status.can_start_deposit) { stage = "unavailable"; warning = status.message; }
      } else { stage = status.can_start_deposit ? "idle" : "unavailable"; warning = status.message || ""; }
    }
    async function startSession() { session = await api.start(command); command = null; stage = "session"; }
    async function handle(action, value) {
      warning = "";
      if (action === "status") return checkStatus();
      if (action === "search-toggle") { searchActive = !searchActive; return; }
      if (action === "search-key") {
        if (value === "close") searchActive = false;
        else if (value === "backspace") filter = filter.slice(0, -1);
        else if (value === "space") filter += " ";
        else if (value === "shift") keyboardShift = !keyboardShift;
        else { filter += keyboardShift ? value.toUpperCase() : value; keyboardShift = false; }
        return;
      }
      if (action === "begin") {
        const status = await api.status();
        if (!status.can_start_deposit) { stage = "unavailable"; warning = status.message; return; }
        context = await api.context(); stage = "identity"; return;
      }
      if (action === "mode") { mode = value; stage = "segment"; return; }
      if (action === "segment") { segment = value; stage = "year"; return; }
      if (action === "grade") { grade = value; stage = "class"; return; }
      if (action === "class") { command = { command_id: crypto.randomUUID(), mode, class_id: value }; return startSession(); }
      if (action === "resume-start") return startSession();
      if (action === "reset-selection") {
        if (command) {
          session = await api.active();
          if (session) { command = null; stage = "session"; return; }
        }
        command = null; stage = "identity"; return;
      }
      if (action === "student") { studentId = value; pin = ""; searchActive = false; stage = "pin"; return; }
      if (action === "pin-key") {
        if (value === "Apagar") pin = pin.slice(0, -1);
        else if (value === "OK") {
          if (pin.length !== 4) return;
          const entered = pin; pin = ""; render();
          session = await api.action(session.event_id, "pin", { student_id: studentId, pin: entered }); stage = "session";
        } else if (/^[0-9]$/.test(value) && pin.length < 4) pin += value;
        return;
      }
      if (action === "safe" || action === "risk") { session = await api.action(session.event_id, "safety", { has_risk: action === "risk" }); return; }
      if (action === "refresh") { session = await api.session(session.event_id); return; }
      if (["cancel", "retry-registration", "finish", "hand-removed"].includes(action)) { session = await api.action(session.event_id, action); pin = ""; return; }
    }
    try {
      const devApi = new window.BinGoLocalApi.DevApi();
      if (await devApi.isDev()) return window.BinGoOperational.startDev(kiosk, visuals, devApi);
    } catch {
      stage = "unavailable"; warning = "Não foi possível confirmar o perfil local. Verifique a conexão e atualize a página."; render();
      kiosk.addEventListener("click", () => window.location.reload(), { once: true });
      return;
    }
    kiosk.addEventListener("click", async event => {
      const target = event.target.closest("button[data-op]");
      if (!target || target.disabled || busy) return;
      busy = true; render();
      try { await handle(target.dataset.op, target.dataset.value); }
      catch (error) {
        warning = error.code === "STUDENT_PIN_INVALID" ? "Não foi possível confirmar seu PIN. Tente novamente." : error.code === "PHYSICAL_INTEGRATION_REQUIRED" ? "A integração física ainda não está disponível." : "Não foi possível confirmar a operação. Nenhum sucesso foi presumido.";
        pin = "";
        if (stage === "loading" || !session && !command) stage = "unavailable";
      } finally { busy = false; render(); }
    });
    render();
    try { await checkStatus(); }
    catch { stage = session ? "session" : "unavailable"; warning = "Não foi possível consultar o serviço local. Novos descartes estão bloqueados."; }
    render();
  },
  async startDev(kiosk, visuals, api) {
    "use strict";
    const { normalize, renderIdentity } = visuals;
    const { LocalApiError } = window.BinGoLocalApi;
    const keys = { event: "bingo.dev.event", command: "bingo.dev.command" };
    const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    let snapshot = null, context = null, stage = "loading", selectedClass = null, student = null;
    let pin = "", command = null, online = false, busy = false, warning = "", uncertain = false;
    let segment = null, grade = null, filter = "", searchActive = false, keyboardShift = true, keyFeedback = null, feedbackTimer;
    let keyboardClosing = false, closeTimer;
    let pollTimer, departed = false;
    const pendingPhases = ['INTENT', 'DISPATCHING', 'ACCEPTED'];
    const completedMotion = operation => snapshot?.commands.some(c => c.command.operation === operation && c.phase === 'COMPLETED' && c.result === 'SUCCEEDED');
    const failedMotion = () => snapshot?.commands.some(c => !pendingPhases.includes(c.phase) && !(c.phase === 'COMPLETED' && c.result === 'SUCCEEDED'));
    const openPin = () => snapshot?.session.state === 'PHYSICAL_BLOCKED' && allowed('open') && !failedMotion();
    const hatchPin = () => snapshot?.session.state === 'REVIEW' && stage === 'hatch-pin' && allowed('hatch') && !failedMotion();
    const saved = name => { try { const id = sessionStorage.getItem(keys[name]); return uuid.test(id || "") ? id : null; } catch { return null; } };
    const remember = (name, id) => { try { sessionStorage.setItem(keys[name], id); return sessionStorage.getItem(keys[name]) === id; } catch { return false; } };
    const forget = name => { try { sessionStorage.removeItem(keys[name]); } catch { /* GET active remains authoritative. */ } };
    const allowed = action => snapshot?.allowed_actions.includes(action) === true;
    const identifying = () => snapshot?.session.state === "IDENTIFYING" && snapshot.session.mode === "student" && allowed("identify");
    const terminal = () => ["CANCELLED", "COMPLETED"].includes(snapshot?.session.state);
    function message(error) {
      if (error.code === "INVALID_RESPONSE") return "O serviço retornou uma resposta inconsistente. Consulte a sessão novamente.";
      if (error.status === 401) return "PIN não confirmado. Tente novamente.";
      if (error.status === 422) return "Dados inválidos. Selecione a turma e o aluno e informe quatro números.";
      if (error.status === 409) return "Há um conflito com a sessão ou identidade persistida. Confira o vínculo recuperado ou chame um responsável.";
      if (error.status === 403) return "Não foi possível autorizar a identificação neste contexto DEV.";
      if (error.status === 503) return "A central DEV está indisponível. Vínculos persistidos permanecem preservados.";
      if (error.code === "SESSION_STORAGE_UNAVAILABLE") return "O navegador não permite preservar o identificador da tentativa. Nenhuma nova sessão foi solicitada.";
      return "Não foi possível confirmar a resposta do serviço local. Consulte a sessão antes de tentar novamente.";
    }
    const segments = () => {
      const classes = context?.classes || [];
      return classes.every(c => c.segment) ? [...new Set(classes.map(c => c.segment))] : [];
    };
    const grades = () => {
      const classes = (context?.classes || []).filter(c => c.segment === segment);
      return classes.every(c => c.grade) ? [...new Set(classes.map(c => c.grade))] : [];
    };
    function render() {
      let screen = ({ loading: "sleep", idle: command ? "idle" : "sleep", welcome: "idle", identity: "identity", segment: "segment", year: "year", classes: "class", students: "student", pin: "pin" })[stage];
      let notice = warning;
      const riskReported = snapshot?.session.state === "CANCELLED" && snapshot.session.failure_code === "SAFETY_RISK";
      if (uncertain) screen = "unavailable";
      else if (snapshot?.session.state === "SAFETY" && snapshot.identity) screen = "safety";
      else if (riskReported) screen = "teacher";
      else if (failedMotion() || snapshot?.session.state === 'INDETERMINATE') screen = stage === 'help' ? 'teacher' : 'mechanical-error';
      else if (openPin() || hatchPin()) screen = 'pin';
      else if (snapshot?.session.state === 'OPENING') screen = 'opening';
      else if (snapshot?.session.state === 'DOOR_OPEN' && completedMotion('OPEN_INSERTION_DOOR')) screen = stage === 'hand' ? 'hand-confirm' : 'insert';
      else if (snapshot?.session.state === 'CLOSING') screen = 'door-progress';
      else if (['DOOR_CLOSED', 'REVIEW'].includes(snapshot?.session.state) && completedMotion('CLOSE_INSERTION_DOOR')) screen = 'review';
      else if (snapshot?.session.state === 'HATCH_IN_PROGRESS') screen = 'computing';
      else if (terminal()) { screen = "idle"; notice = notice || "A sessão foi encerrada. Nenhum recibo econômico ou pontuação foi gerado."; }
      else if (snapshot && !identifying()) { screen = "teacher"; if (!snapshot.commands.length) notice = notice || "Sessão já avançou. Consulte o estado persistido; nenhum movimento foi solicitado por esta tela."; }
      else if (stage !== "loading" && !online) { screen = "unavailable"; notice = notice || "Novas autenticações exigem a central DEV disponível."; }
      renderIdentity({
        screen, stage: screen === "unavailable" ? "unavailable" : stage, state: snapshot?.session.state || stage,
        eventId: snapshot?.session.event_id, busy, uncertain, terminal: terminal(), command,
        warning: notice, pinLength: pin.length, grade, filter, searchActive, keyboardShift, keyFeedback, keyboardClosing,
        riskReported, safetyAllowed: allowed("safety"), cancelAllowed: allowed('cancel'), mechanicalPin: openPin() || hatchPin(),
        reviewAllowed: allowed('review-fixture') || allowed('hatch'),
        ...window.BinGoLocalApi.schoolLabels(context?.classes || [], segment),
        classes: (context?.classes || []).filter(c => (!segment || c.segment === segment) && (!grade || c.grade === grade)),
        students: (context?.students || []).filter(s => s.class_id === selectedClass && normalize(s.name).includes(normalize(filter))).sort((a, b) => a.name.localeCompare(b.name, "pt-BR")),
      });
    }
    function accept(value) {
      if (snapshot?.session.event_id !== value.session.event_id) { selectedClass = null; student = null; }
      snapshot = value; pin = ""; command = null; searchActive = false; keyboardClosing = false; clearTimeout(closeTimer); forget("command");
      remember("event", snapshot.session.event_id);
      stage = identifying() ? student ? "pin" : selectedClass ? "students" : "classes" : value.session.state === 'REVIEW' && stage === 'hatch-pin' ? 'hatch-pin' : "session";
      clearTimeout(pollTimer);
      if (!departed && (snapshot.commands.some(c => pendingPhases.includes(c.phase)) || snapshot.session.state === 'HATCH_IN_PROGRESS' && !failedMotion())) {
        // This timer only schedules durable GETs. It never decides a movement's
        // duration/result and never retries a POST.
        pollTimer = setTimeout(async () => {
          if (busy || departed) { if (!departed) accept(snapshot); return; }
          busy = true;
          try { await inspectMotion(); }
          catch (error) { uncertain = true; warning = message(error); }
          finally { busy = false; render(); }
        }, 500);
      }
    }
    async function inspectMotion() {
      const id = snapshot.session.event_id;
      const value = await api.session(id);
      for (const entry of value.commands) await api.journal(id, entry.command.mechanical_command_id);
      accept(value);
    }
    async function move(operation, options) {
      const id = snapshot.session.event_id;
      // Recheck durable state and journal even when the last response was lost.
      await inspectMotion();
      if (!allowed(operation) || failedMotion() || snapshot.commands.some(c => pendingPhases.includes(c.phase))) return;
      const key = `bingo.dev.motion.${id}.${operation}`;
      let identifier;
      try {
        identifier = sessionStorage.getItem(key) || crypto.randomUUID();
        if (!uuid.test(identifier)) throw new Error('Invalid pointer');
        sessionStorage.setItem(key, identifier);
        if (sessionStorage.getItem(key) !== identifier) throw new Error('Storage unavailable');
      } catch { throw new LocalApiError('SESSION_STORAGE_UNAVAILABLE'); }
      try { accept(await api.motion(id, operation, identifier, options)); }
      finally { if ('pin' in options) options.pin = ''; }
    }
    async function recover() {
      pin = ""; uncertain = false;
      const active = await api.active();
      const id = snapshot?.session.event_id || saved("event");
      if (active) accept(active);
      else if (id) {
        try { accept(await api.session(id)); }
        catch (error) { if (error.status !== 404) throw error; snapshot = null; forget("event"); }
      }
      if (!snapshot || identifying()) {
        online = false; context = null;
        try { await api.health(); context = await api.context(); online = true; }
        catch (error) { warning = message(error); }
        if (selectedClass && !context?.classes.some(c => c.id === selectedClass)) { selectedClass = null; student = null; }
        if (segment && !segments().includes(segment)) { segment = null; grade = null; }
        if (grade && !grades().includes(grade)) grade = null;
        if (student && !context?.students.some(s => s.id === student && s.class_id === selectedClass)) student = null;
        stage = snapshot ? student ? "pin" : selectedClass ? "students" : "classes" : "idle";
        if (!snapshot) command = command || saved("command");
      }
    }
    async function createSession() {
      command = command || saved("command") || crypto.randomUUID();
      if (!remember("command", command)) throw new LocalApiError("SESSION_STORAGE_UNAVAILABLE");
      accept(await api.start(command));
    }
    function closeKeyboard() {
      searchActive = false; keyboardShift = true; keyboardClosing = true; clearTimeout(closeTimer);
      closeTimer = setTimeout(() => { keyboardClosing = false; if (stage === "students" && identifying()) render(); }, 260);
    }
    async function handle(action, value) {
      warning = "";
      if (!["search-key", "search-toggle"].includes(action)) { keyboardClosing = false; clearTimeout(closeTimer); }
      if (action === "refresh") { await recover(); if (snapshot?.commands.length) await inspectMotion(); return; }
      if (action === "new" && terminal()) { snapshot = null; command = null; selectedClass = null; student = null; forget("event"); forget("command"); await recover(); if (online && !snapshot) stage = value === "idle" ? "idle" : "identity"; return; }
      if (action === "cancel" && allowed("cancel")) return accept(await api.cancel(snapshot.session.event_id));
      if (action === "wake") { stage = "welcome"; return; }
      if (action === 'help') { stage = 'help'; return; }
      if (action === "begin") { await recover(); if (!snapshot && online) stage = "identity"; return; }
      if (action === "mode") {
        if (value !== "student") { warning = "A identificação somente por turma ainda não está homologada neste DEV. Escolha participar com seu perfil."; return; }
        segment = null; grade = null; stage = segments().length ? "segment" : "classes"; return;
      }
      if (action === "segment" && segments().includes(value)) { segment = value; grade = null; stage = grades().length ? "year" : "classes"; return; }
      if (action === "grade" && grades().includes(value)) { grade = value; stage = "classes"; return; }
      if (action === "back") {
        pin = ""; filter = ""; searchActive = false;
        // Developer decision: the existing SAFETY back control cancels the
        // preparation; it never rewinds an authenticated backend session.
        if (snapshot?.session.state === "SAFETY") { if (allowed("cancel")) accept(await api.cancel(snapshot.session.event_id)); else await recover(); return; }
        if (stage === "pin") { student = null; stage = "students"; }
        else if (stage === "students") { selectedClass = null; stage = "classes"; }
        else if (stage === "classes") stage = grade ? "year" : segment ? "segment" : "identity";
        else if (stage === "year") stage = "segment";
        else if (stage === "segment") stage = "identity";
        else stage = "welcome";
        return;
      }
      if (action === "safety" && ["safe", "risk"].includes(value)) {
        if (snapshot?.session.state !== "SAFETY" || !snapshot.identity || !allowed("safety")) return recover();
        accept(await api.safety(snapshot.session.event_id, value === "risk"));
        return;
      }
      if (action === 'inserted' && snapshot?.session.state === 'DOOR_OPEN' && completedMotion('OPEN_INSERTION_DOOR')) { stage = 'hand'; return; }
      if (action === 'hand' && snapshot?.session.state === 'DOOR_OPEN' && allowed('close')) return move('close', { hand_removed: true });
      if (action === 'discard') {
        await inspectMotion();
        if (failedMotion()) return;
        if (allowed('review-fixture') && snapshot.session.state === 'DOOR_CLOSED') accept(await api.reviewFixture(snapshot.session.event_id));
        if (snapshot.session.state === 'REVIEW' && allowed('hatch')) stage = 'hatch-pin';
        return;
      }
      if (action === "search-toggle") { keyboardClosing = false; clearTimeout(closeTimer); searchActive = true; if (!filter) keyboardShift = true; return; }
      if (action === "search-key") {
        keyFeedback = value;
        clearTimeout(feedbackTimer);
        feedbackTimer = setTimeout(() => { keyFeedback = null; if (stage === "students" && identifying()) render(); }, 300);
        if (value === "clear") { filter = ""; closeKeyboard(); }
        else if (value === "backspace") { filter = filter.slice(0, -1); keyboardShift = filter.length === 0; }
        else if (value === "space") { filter += " "; keyboardShift = false; }
        else if (value === "shift") keyboardShift = !keyboardShift;
        else if (/^[a-zç]$/.test(value)) { filter += keyboardShift ? value.toUpperCase() : value; keyboardShift = false; }
        return;
      }
      if (action === "resume" && command) { await createSession(); return recover(); }
      if (action === "classes" && identifying() && online) { stage = "classes"; selectedClass = null; student = null; pin = ""; return; }
      if (action === "class" && online && context?.classes.some(c => c.id === value)) {
        if (!snapshot) await createSession();
        if (!identifying()) return;
        selectedClass = value; student = null; filter = ""; stage = "students"; return;
      }
      if (action === "students" && identifying() && online) { student = null; pin = ""; stage = "students"; return; }
      if (action === "student" && identifying() && online && context?.students.some(s => s.id === value && s.class_id === selectedClass)) { student = value; pin = ""; searchActive = false; stage = "pin"; return; }
      if (action === "pin" && (identifying() && online || openPin() || hatchPin())) {
        if (value === "Apagar") pin = pin.slice(0, -1);
        else if (value === "OK" && pin.length === 4) {
          let entered = pin; pin = ""; render();
          try {
            if (openPin() || hatchPin()) { const operation = openPin() ? 'open' : 'hatch'; await api.health(); await move(operation, { pin: entered }); }
            else accept(await api.identify(snapshot.session.event_id, selectedClass, student, entered));
          }
          finally { entered = ""; }
        } else if (/^[0-9]$/.test(value) && pin.length < 4) pin += value;
      }
    }
    kiosk.addEventListener("click", async event => {
      const target = event.target.closest("[data-dev-op]");
      if (!target && searchActive && !busy && event.target.closest("[data-search-screen]")) { closeKeyboard(); render(); return; }
      if (!target || target.disabled || busy) return;
      const action = target.dataset.devOp, value = target.dataset.value;
      const local = ["wake", "mode", "segment", "grade", "classes", "students", "student", "search-toggle", "search-key"].includes(action) || action === "pin" && value !== "OK" || action === "back" && snapshot?.session.state !== "SAFETY";
      if (!local) { busy = true; render(); }
      try { await handle(action, value); }
      catch (error) {
        pin = ""; warning = message(error);
        if ([403, 503].includes(error.status) || error.status === 401 && error.code !== "STUDENT_PIN_INVALID" || ["LOCAL_TIMEOUT", "LOCAL_UNAVAILABLE"].includes(error.code)) online = false;
        try {
          if (snapshot) await inspectMotion();
          else { const active = await api.active(); if (active) accept(active); }
          if (!snapshot) { stage = "idle"; uncertain = true; }
          if (error.status === 409 && snapshot?.identity) warning += ` Vínculo recuperado: ${snapshot.session.student_name}.`;
        } catch { uncertain = true; }
      } finally { if (!local) busy = false; render(); }
    });
    busy = true;
    render();
    try { await recover(); }
    catch (error) { uncertain = true; warning = message(error); }
    finally { busy = false; render(); }
    window.addEventListener("pagehide", () => { pin = ""; student = null; departed = true; clearTimeout(pollTimer); });
  },
};
