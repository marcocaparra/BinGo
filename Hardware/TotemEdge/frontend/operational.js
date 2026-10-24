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
};
