/* A interface apresenta estado recebido; nunca promove etapas físicas por timer. */
window.BinGoOperational = {
  async start(kiosk, visuals) {
    "use strict";
    const api = new window.BinGoLocalApi.LocalApi();
    const { assets, talk, topbar, keyboardRows, normalize } = visuals;
    let session = null, context = null, stage = "loading", mode = "student";
    let segment = null, grade = null, studentId = null, pin = "", command = null;
    let busy = false, warning = "", filter = "", searchActive = false, keyboardShift = true;
    let pollTimer = null;
    const pendingStartKey = 'bingo-operational-start-v1';
    const allowed = action => session?.operational?.allowed_actions?.includes(action);
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
      clearTimeout(pollTimer);
      if (!busy && ['READY_TO_CAPTURE', 'CAPTURING', 'CLASSIFYING', 'HATCH_IN_PROGRESS'].includes(session?.state)) {
        // Only read durable state. This timer never completes or starts a cycle.
        pollTimer = setTimeout(async () => {
          if (busy) return;
          busy = true;
          try { session = await api.session(session.event_id); }
          catch { warning = 'Não foi possível consultar o ciclo. Chame um responsável; nenhum novo movimento será enviado.'; }
          finally { busy = false; render(); }
        }, 750);
      }
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
      else if (['INSERTION_READY', 'REVIEW'].includes(session?.state) && session?.operational?.execution_ready === false) html = panel('Ciclo indisponível', 'Nenhum movimento novo foi solicitado. Se o item já foi inserido, chame um responsável e mantenha as mãos afastadas.', button('Atualizar estado', 'refresh'));
      else if (session?.state === "INSERTION_READY") html = panel("Posicione um único item", "Ensaio com responsável presente. Insira um item e retire a mão do compartimento.", allowed('hand-removed') ? button("Retirei a mão", "hand-removed") : button("Atualizar estado", "refresh"));
      else if (['READY_TO_CAPTURE', 'CAPTURING', 'CLASSIFYING'].includes(session?.state)) html = panel("Analisando o item", "Aguarde a captura e a análise do item. Mantenha as mãos afastadas.", button("Atualizar estado", "refresh", "", false));
      else if (session?.state === 'REVIEW') {
        const vision = session.operational?.vision;
        const name = window.BinGoLocalApi.studentType(vision, vision?.decision?.item_id || vision?.observation?.itemId);
        html = panel(vision?.decision ? 'Autorizar ciclo mecânico' : 'Confira o item', vision?.decision ? `${name}. O responsável está presente e pronto para cortar a alimentação? Ao autorizar, ambas as escotilhas abrirão e fecharão. A sequência não confirma pontos.` : `Identificamos: ${name}. Confira antes de autorizar o movimento.`,
          allowed('hatch') ? button('Autorizar abertura e fechamento', 'hatch') : allowed('vision-review') ? button('Confirmar identificação', 'vision-confirm') + vision.allowed_candidates.map(id => button(window.BinGoLocalApi.studentType(vision, id), 'vision-correct', id, false)).join('') : button('Atualizar estado', 'refresh'));
      }
      else if (session?.state === 'HATCH_IN_PROGRESS') html = panel('Ciclo mecânico em execução', 'Mantenha as mãos afastadas. Aguardando o resultado durável do controlador.', button('Consultar estado', 'refresh', '', false));
      else if (session?.state === "REGISTRATION_PENDING") html = panel("Registro pendente", "O ciclo confirmado está preservado. Não faça outro descarte. A recompensa aguarda confirmação central.", button("Tentar registrar novamente", "retry-registration"));
      else if (session?.state === "REGISTERED") {
        visuals.renderReceipt(session, busy);
        if (warning) {
          const message = kiosk.querySelector('.simulation-badge');
          message.textContent = warning; message.setAttribute('role', 'alert');
        }
        return;
      } else if (["INDETERMINATE", "TECHNICAL_FAILURE", "RETURN_REQUIRED"].includes(session?.state)) {
        const operationalDone = session.operational?.commands?.some(c => c.command.operation === 'CYCLE_LOWER_HATCH' && c.source === 'PHYSICAL' && c.phase === 'COMPLETED' && c.result === 'SUCCEEDED');
        html = panel(operationalDone ? 'Sequência operacional concluída' : 'Chame um responsável', operationalDone ? 'O controlador concluiu a abertura e o fechamento. A queda do item e os pontos ainda não foram confirmados. O Totem permanece reservado para inspeção do responsável.' : session.state === 'RETURN_REQUIRED' ? 'O objeto foi recusado. Chame um responsável para retirar o item com segurança. Nenhum ponto foi registrado.' : 'O ciclo exige inspeção presencial. Não coloque as mãos nas escotilhas. O responsável deve isolar a alimentação antes de desobstruir; novos descartes estão bloqueados.', button('Atualizar estado', 'refresh'));
      }
      else if (["CANCELLED", "COMPLETED"].includes(session?.state)) html = panel("Sessão encerrada", session.state === "CANCELLED" ? "A preparação foi cancelada sem descarte." : "O registro está confirmado.", button("Voltar ao início", "status"));
      else html = panel("Aguardando confirmação", "Esta etapa depende de uma confirmação efetiva do serviço local.", button("Atualizar estado", "refresh"));
      kiosk.innerHTML = html;
    }
    async function checkStatus() {
      pin = ""; studentId = null; warning = ""; stage = "loading"; render();
      // Recuperação é consultada mesmo offline; não descartar ciclo ativo no browser.
      session = await api.active();
      const status = await api.status();
      if (session) {
        stage = "session";
        if (session.state === "IDENTIFYING" && status.can_start_deposit) context = await api.context();
        if (["IDENTIFYING", "AUTHENTICATING", "SAFETY", "PHYSICAL_BLOCKED"].includes(session.state) && !status.can_start_deposit) { stage = "unavailable"; warning = status.message; }
      } else {
        command = JSON.parse(sessionStorage.getItem(pendingStartKey) || 'null');
        if (command && status.can_start_deposit) { context = await api.context(); stage = 'class'; }
        else stage = status.can_start_deposit ? "idle" : "unavailable";
        warning = status.message || "";
      }
    }
    async function startSession() { session = await api.start(command); command = null; sessionStorage.removeItem(pendingStartKey); stage = "session"; }
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
      if (action === "class") {
        command = { command_id: crypto.randomUUID(), mode, class_id: value };
        sessionStorage.setItem(pendingStartKey, JSON.stringify(command));
        if (sessionStorage.getItem(pendingStartKey) !== JSON.stringify(command)) throw new Error('Storage unavailable');
        return startSession();
      }
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
      if (action === 'vision-confirm' || action === 'vision-correct') {
        if (!allowed('vision-review')) return;
        const vision = session.operational.vision;
        session = await api.action(session.event_id, 'vision-review', { capture_id: vision.capture_id, item_id: action === 'vision-confirm' ? vision.observation.itemId : value, action: action === 'vision-confirm' ? 'confirm' : 'correct' });
        return;
      }
      if (action === 'hatch') {
        if (!allowed('hatch')) return;
        session = await api.action(session.event_id, 'hatch');
        return;
      }
      if (action === 'hand-removed') {
        if (!allowed('hand-removed')) return;
        session = await api.action(session.event_id, 'hand-removed', { hand_removed: true });
        return;
      }
      if (["cancel", "retry-registration", "finish", "hand-removed"].includes(action)) { session = await api.action(session.event_id, action); pin = ""; return; }
    }
    try {
      const devApi = new window.BinGoLocalApi.DevApi();
      if (await devApi.isDev()) return window.BinGoOperational.startDev(kiosk, visuals, devApi);
      const retained = sessionStorage.getItem(pendingStartKey);
      if (retained) command = JSON.parse(retained);
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
        warning = error.code === "STUDENT_PIN_INVALID" ? "Não foi possível confirmar seu PIN. Tente novamente." : error.code === "PHYSICAL_INTEGRATION_REQUIRED" ? "A integração física ainda não está disponível." : error.code === 'TOTEM_UNAVAILABLE' && session ? 'Descarte indisponível. Se já inseriu o item, chame um responsável.' : "Não foi possível confirmar a operação. Nenhum sucesso foi presumido.";
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
    let correctionItem = null, photo = null, photoLoading = null;
    const pendingPhases = ['INTENT', 'DISPATCHING', 'ACCEPTED'];
    const completedMotion = operation => snapshot?.commands.some(c => c.command.operation === operation && c.phase === 'COMPLETED' && c.result === 'SUCCEEDED');
    const failedMotion = () => snapshot?.commands.some(c => !pendingPhases.includes(c.phase) && !(c.phase === 'COMPLETED' && c.result === 'SUCCEEDED'));
    const openPin = () => snapshot?.session.state === 'PHYSICAL_BLOCKED' && allowed('open') && !failedMotion();
    const hatchPin = () => snapshot?.session.state === 'REVIEW' && (stage === 'hatch-pin' || !!snapshot.vision?.decision) && allowed('hatch') && !failedMotion();
    const saved = name => { try { const id = sessionStorage.getItem(keys[name]); return uuid.test(id || "") ? id : null; } catch { return null; } };
    const remember = (name, id) => { try { sessionStorage.setItem(keys[name], id); return sessionStorage.getItem(keys[name]) === id; } catch { return false; } };
    const forget = name => { try { sessionStorage.removeItem(keys[name]); } catch { /* GET active remains authoritative. */ } };
    const allowed = action => snapshot?.allowed_actions.includes(action) === true;
    const identifying = () => snapshot?.session.state === "IDENTIFYING" && snapshot.session.mode === "student" && allowed("identify");
    const terminal = () => ["CANCELLED", "COMPLETED"].includes(snapshot?.session.state) && !['PENDING'].includes(snapshot?.economy?.status);
    function message(error) {
      if (error.code === "INVALID_RESPONSE") return "O serviço retornou uma resposta inconsistente. Consulte a sessão novamente.";
      if (error.status === 401) return "PIN não confirmado. Tente novamente.";
      if (error.status === 422) return "Dados inválidos. Selecione a turma e o aluno e informe quatro números.";
      if (error.status === 409) return "Há um conflito com a sessão ou identidade persistida. Confira o vínculo recuperado ou chame um responsável.";
      if (error.status === 403) return "Não foi possível confirmar sua identificação. Peça ajuda a um responsável.";
      if (error.status === 503) return "O serviço está indisponível no momento. Peça ajuda a um responsável.";
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
      if (snapshot?.economy?.status === 'CONFIRMED') {
        visuals.renderReceipt({...snapshot.session,state:'REGISTERED',receipt:snapshot.economy.receipt},busy);
        const finish = kiosk.querySelector('[data-op="finish"]');
        finish.removeAttribute('data-op'); finish.dataset.devOp = 'economic-finish';
        return;
      }
      let screen = ({ loading: "sleep", idle: command ? "idle" : "sleep", welcome: "idle", identity: "identity", segment: "segment", year: "year", classes: "class", students: "student", pin: "pin" })[stage];
      let notice = warning;
      if (snapshot?.vision?.recapture_error && !notice) notice = 'Não foi possível refotografar ou analisar. A tentativa anterior foi preservada. Confira o item ou tente tirar outra foto.';
      if (snapshot?.economy?.status === 'PENDING') notice = 'Registro pendente. Aguarde a confirmação. Não faça outro descarte.';
      const riskReported = snapshot?.session.state === "CANCELLED" && snapshot.session.failure_code === "SAFETY_RISK";
      if (snapshot?.economy?.status === 'PENDING') screen = 'computing';
      else if (uncertain) screen = "unavailable";
      else if (snapshot?.session.state === "SAFETY" && snapshot.identity) screen = "safety";
      else if (riskReported) screen = "teacher";
      else if (failedMotion() || snapshot?.session.state === 'INDETERMINATE') screen = stage === 'help' ? 'teacher' : 'mechanical-error';
      else if (openPin() || hatchPin()) screen = 'pin';
      else if (snapshot?.session.state === 'INSERTION_READY') screen = stage === 'hand' ? 'hand-confirm' : 'insert';
      else if (snapshot?.session.state === 'READY_TO_CAPTURE') screen = 'classification';
      else if (snapshot?.session.state === 'OPENING') screen = 'opening';
      else if (snapshot?.session.state === 'DOOR_OPEN' && completedMotion('OPEN_INSERTION_DOOR')) screen = stage === 'hand' ? 'hand-confirm' : 'insert';
      else if (snapshot?.session.state === 'CLOSING') screen = 'door-progress';
      else if (snapshot?.session.state === 'CAPTURING') screen = 'classification';
      else if (snapshot?.session.state === 'CLASSIFYING') screen = snapshot.vision?.provenance?.observations.some(r => r.origin === 'AWS_REKOGNITION' && (r.status === 'needs-secondary' || r.confidence < 0.75)) ? 'secondary-analysis' : 'classification';
      else if (snapshot?.session.state === 'RETURN_REQUIRED') screen = 'rejected';
      else if (snapshot?.session.state === 'TECHNICAL_FAILURE') screen = snapshot.vision?.error_code === 'CLASSIFICATION_INCONCLUSIVE' ? 'rejected' : 'vision-error';
      else if (snapshot?.session.state === 'REVIEW' && snapshot.vision) screen = stage === 'correct-item' && allowed('vision-review') ? 'correct-item' : snapshot.vision.decision ? 'computing' : 'recognized';
      else if (snapshot?.session.state === 'DOOR_CLOSED' && !allowed('review-fixture')) screen = 'door-progress';
      else if (['DOOR_CLOSED', 'REVIEW'].includes(snapshot?.session.state) && completedMotion('CLOSE_INSERTION_DOOR')) screen = 'review';
      else if (snapshot?.session.state === 'HATCH_IN_PROGRESS') screen = 'computing';
      else if (terminal()) { screen = "idle"; notice = notice || "A sessão foi encerrada. Nenhum recibo econômico ou pontuação foi gerado."; }
      else if (snapshot && !identifying()) { screen = "teacher"; if (!snapshot.commands.length) notice = notice || "Sessão já avançou. Consulte o estado persistido; nenhum movimento foi solicitado por esta tela."; }
      else if (stage !== "loading" && !online) { screen = "unavailable"; notice = notice || "Não foi possível confirmar sua identificação agora. Peça ajuda a um responsável."; }
      renderIdentity({
        screen, stage: screen === "unavailable" ? "unavailable" : stage, state: snapshot?.session.state || stage,
        eventId: snapshot?.session.event_id, busy, uncertain, terminal: terminal(), command,
        warning: notice, pinLength: pin.length, grade, filter, searchActive, keyboardShift, keyFeedback, keyboardClosing,
        riskReported, safetyAllowed: allowed("safety"), cancelAllowed: allowed('cancel'), mechanicalPin: openPin() || hatchPin(),
        reviewAllowed: allowed('review-fixture') || allowed('hatch') || allowed('vision-review'),
        vision: snapshot?.vision, correctionItem, correctionAllowed: allowed('vision-review') && (screen !== 'recognized' || photo?.id === snapshot?.vision?.capture_id),
        recaptureAllowed: allowed('vision-recapture'),
        retryAllowed: allowed('vision-analyze') && snapshot?.vision?.phase === 'FAILED',
        analyzeAllowed: allowed('vision-analyze') && photo?.id === snapshot?.vision?.capture_id,
        ...window.BinGoLocalApi.schoolLabels(context?.classes || [], segment),
        classes: (context?.classes || []).filter(c => (!segment || c.segment === segment) && (!grade || c.grade === grade)),
        students: (context?.students || []).filter(s => s.class_id === selectedClass && normalize(s.name).includes(normalize(filter))).sort((a, b) => a.name.localeCompare(b.name, "pt-BR")),
      });
      if (['camera', 'recognized'].includes(screen) && snapshot?.vision?.image_available) {
        const id = snapshot.vision.capture_id, event = snapshot.session.event_id;
        if (photo?.id === id) {
          const canvas = kiosk.querySelector('[data-camera-canvas]');
          if (canvas) { canvas.width = photo.bitmap.width; canvas.height = photo.bitmap.height; canvas.getContext('2d').drawImage(photo.bitmap, 0, 0); canvas.dataset.loaded = 'true'; }
          const image = kiosk.querySelector('[data-session-photo]');
          if (image) { image.src = photo.url; image.hidden = false; }
        } else if (photoLoading !== id) {
          photoLoading = id;
          api.photo(event, id).then(async blob => ({ bitmap: await createImageBitmap(blob), url: URL.createObjectURL(blob) })).then(({ bitmap, url }) => {
            if (snapshot?.session.event_id === event && snapshot?.vision?.capture_id === id && ['CAPTURING', 'REVIEW'].includes(snapshot?.session.state)) { photo?.bitmap.close(); if (photo) URL.revokeObjectURL(photo.url); photo = { id, bitmap, url }; render(); }
            else { bitmap.close(); URL.revokeObjectURL(url); }
          }).catch(async error => { warning = message(error); try { await inspectMotion(); } catch { uncertain = true; } render(); });
        }
      } else if (photo) { photo.bitmap.close(); URL.revokeObjectURL(photo.url); photo = null; photoLoading = null; }
    }

    function accept(value) {
      if (snapshot?.session.event_id !== value.session.event_id) { selectedClass = null; student = null; }
      snapshot = value; pin = ""; command = null; searchActive = false; keyboardClosing = false; clearTimeout(closeTimer); forget("command");
      remember("event", snapshot.session.event_id);
      stage = identifying() ? student ? "pin" : selectedClass ? "students" : "classes" : value.session.state === 'REVIEW' && stage === 'hatch-pin' ? 'hatch-pin' : "session";
      clearTimeout(pollTimer);
      if (!departed && (snapshot.economy?.status === 'PENDING' || snapshot.commands.some(c => pendingPhases.includes(c.phase)) || (['HATCH_IN_PROGRESS', 'CLASSIFYING'].includes(snapshot.session.state) || snapshot.session.state === 'CAPTURING') && !failedMotion() || ['DOOR_CLOSED', 'READY_TO_CAPTURE'].includes(snapshot.session.state) && !allowed('review-fixture'))) {
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
      if (action === "refresh") { photoLoading = null; await recover(); if (snapshot?.commands.length) await inspectMotion(); return; }
      if (action === 'economic-finish') {
        await api.request(`/local/dev/sessions/${snapshot.session.event_id}/economic-finish`,{});
        snapshot=null; forget('event'); forget('command'); await recover(); return;
      }
      if (action === "new" && terminal()) { snapshot = null; command = null; selectedClass = null; student = null; forget("event"); forget("command"); await recover(); if (online && !snapshot) stage = value === "idle" ? "idle" : "identity"; return; }
      if (action === 'end-test') {
        if (!['TECHNICAL_FAILURE', 'RETURN_REQUIRED'].includes(snapshot?.session.state) || !allowed('cancel')) return recover();
        const ended = await api.cancel(snapshot.session.event_id);
        if (ended.session.state !== 'CANCELLED') throw new LocalApiError('INVALID_RESPONSE');
        accept(ended);
        return;
      }
      if (action === "cancel" && allowed("cancel")) return accept(await api.cancel(snapshot.session.event_id));
      if (action === "wake") { stage = "welcome"; return; }
      if (action === 'help') { stage = 'help'; return; }
      if (action === 'correction' && allowed('vision-review')) { correctionItem = snapshot.vision.observation.itemId; stage = 'correct-item'; return; }
      if (action === 'recapture' && allowed('vision-recapture')) {
        const event = snapshot.session.event_id, v = snapshot.vision;
        const last = v.capture_history?.at(-1)?.recapture_id || 'initial';
        const key = `bingo.dev.recapture.${event}.${v.capture_id}.${last}`;
        let intent = sessionStorage.getItem(key);
        if (!intent) { intent = crypto.randomUUID(); sessionStorage.setItem(key,intent); }
        if (sessionStorage.getItem(key) !== intent) throw new LocalApiError('SESSION_STORAGE_UNAVAILABLE');
        accept(await api.visionRecapture(event,v.capture_id,intent));
        return;
      }
      if (action === 'correct-item' && allowed('vision-review') && snapshot.vision.allowed_candidates.includes(value)) { correctionItem = value; return; }
      if (action === 'retry-analysis' && allowed('vision-analyze') && snapshot.vision?.phase === 'FAILED') {
        const event = snapshot.session.event_id, v = snapshot.vision;
        // Reuse this intent if its HTTP response is lost. Only UUIDs enter storage.
        const key = `bingo.dev.analysis.${event}.${v.provenance?.analysis_id || v.capture_id}`;
        let intent = sessionStorage.getItem(key);
        if (!intent) { intent = crypto.randomUUID(); sessionStorage.setItem(key, intent); }
        accept(await api.visionAnalyze(event, v.capture_id, intent));
        return;
      }
      if (action === 'vision-analyze' && allowed('vision-analyze') && photo?.id === snapshot.vision.capture_id) { accept(await api.visionAnalyze(snapshot.session.event_id, snapshot.vision.capture_id)); return; }
      if (action === 'recognition-confirm' && allowed('vision-review')) { const v = snapshot.vision; accept(await api.visionReview(snapshot.session.event_id, v.capture_id, v.observation.itemId, 'confirm')); return; }
      if (action === 'apply-correction') {
        if (!allowed('vision-review')) return;
        const v = snapshot.vision;
        accept(await api.visionReview(snapshot.session.event_id, v.capture_id, correctionItem, 'correct'));
        return;
      }
      if (action === "begin") { await recover(); if (!snapshot && online) stage = "identity"; return; }
      if (action === "mode") {
        if (value !== "student") { warning = "A identificação somente por turma ainda não está homologada neste DEV. Escolha participar com seu perfil."; return; }
        segment = null; grade = null; stage = segments().length ? "segment" : "classes"; return;
      }
      if (action === "segment" && segments().includes(value)) { segment = value; grade = null; stage = grades().length ? "year" : "classes"; return; }
      if (action === "grade" && grades().includes(value)) { grade = value; stage = "classes"; return; }
      if (action === "back") {
        if (stage === 'correct-item') { stage = 'session'; return; }
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
      if (action === 'inserted' && (snapshot?.session.state === 'INSERTION_READY' || snapshot?.session.state === 'DOOR_OPEN' && completedMotion('OPEN_INSERTION_DOOR'))) { stage = 'hand'; return; }
      if (action === 'hand' && snapshot?.session.state === 'INSERTION_READY' && allowed('hand-removed')) {
        await inspectMotion();
        if (!allowed('hand-removed') || snapshot.session.state !== 'INSERTION_READY') return;
        const key = `bingo.dev.hand.${snapshot.session.event_id}`;
        let id = sessionStorage.getItem(key);
        if (!id) { id = crypto.randomUUID(); sessionStorage.setItem(key, id); }
        if (sessionStorage.getItem(key) !== id) throw new LocalApiError('SESSION_STORAGE_UNAVAILABLE');
        accept(await api.handRemoved(snapshot.session.event_id, id));
        return;
      }
      if (action === 'hand' && snapshot?.session.state === 'DOOR_OPEN' && allowed('close')) return move('close', { hand_removed: true });
      if (action === 'discard') {
        await inspectMotion();
        if (failedMotion()) return;
        if (allowed('vision-review')) {
          const v = snapshot.vision;
          accept(await api.visionReview(snapshot.session.event_id, v.capture_id, v.observation.itemId, 'confirm'));
        }
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
      const local = ["wake", "mode", "segment", "grade", "classes", "students", "student", "search-toggle", "search-key", "correction", "correct-item"].includes(action) || action === "pin" && value !== "OK" || action === "back" && snapshot?.session.state !== "SAFETY";
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
