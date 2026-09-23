(function () {
  "use strict";

  const app = document.querySelector("#app");

  const deposits = [
    { time: "15:42", student: "Ana Clara M.", className: "9º A", item: "Celular", points: "+120", status: "Validado" },
    { time: "14:18", student: "Lucas P.", className: "8º B", item: "Cabo USB", points: "+45", status: "Validado" },
    { time: "11:07", student: "Perfil da turma", className: "7º A", item: "Mouse", points: "+70", status: "Só turma" },
    { time: "09:35", student: "Marina S.", className: "9º A", item: "Pilha", points: "+30", status: "Revisão" },
  ];

  const discardStats = Object.freeze({ total: 1284, today: 32, week: 184 });

  const helpRequests = [
    { id: "AJ-104", place: "Totem Biblioteca", reason: "Item não reconhecido após nova tentativa", time: "Há 4 min", priority: "Alta", status: "Aguardando" },
    { id: "AJ-103", place: "Totem Pátio", reason: "Aluno pediu acompanhamento de um adulto", time: "Há 18 min", priority: "Média", status: "Em atendimento" },
    { id: "AJ-101", place: "Totem Biblioteca", reason: "Porta não confirmou o fechamento", time: "Hoje, 09:12", priority: "Baixa", status: "Resolvida" },
  ];

  const redemptions = [
    { id: "RG-208", code: "B7K4-92", student: "Ana Clara M.", className: "9º A", reward: "Suco natural", requestedAt: "Hoje, 15:31", expiresAt: "Amanhã, 15:31", status: "Pendente" },
    { id: "RG-207", code: "M2P8-41", student: "Lucas P.", className: "8º B", reward: "Caneta temática", requestedAt: "Hoje, 13:46", expiresAt: "Amanhã, 13:46", status: "Pendente" },
    { id: "RG-205", code: "Q6T3-18", student: "Marina S.", className: "9º A", reward: "Ticket da cantina", requestedAt: "Hoje, 10:12", expiresAt: "Amanhã, 10:12", status: "Pendente" },
    { id: "RG-201", code: "H9C5-73", student: "Rafael G.", className: "7º A", reward: "Caneta temática", requestedAt: "Hoje, 08:20", expiresAt: "Entregue às 09:04", status: "Entregue" },
  ];

  const machines = [
    { name: "Totem Biblioteca", code: "BT-001", status: "Online", color: "#39d353", ink: "#176e2a", bg: "#e8faec", lastSeen: "Agora · 16:40", camera: "Disponível", door: "Fechada", deposits: "18 hoje", version: "v0.8.0" },
    { name: "Totem Pátio", code: "BT-002", status: "Com problema", color: "#ffb020", ink: "#785510", bg: "#fff5d9", lastSeen: "Há 2 min · 16:38", camera: "Disponível", door: "Aberta", deposits: "11 hoje", version: "v0.8.0" },
    { name: "Totem Laboratório", code: "BT-003", status: "Offline", color: "#e52b3a", ink: "#9c2030", bg: "#fff0f2", lastSeen: "Há 38 min · 16:02", camera: "Sem resposta", door: "Indefinido", deposits: "3 hoje", version: "v0.7.4" },
  ];

  const viewMeta = {
    overview: { label: "Visão geral", icon: "layout-dashboard", title: "Operação de hoje", subtitle: "O que precisa de atenção na escola, sem esconder o contexto técnico." },
    deposits: { label: "Descartes", icon: "archive-restore", title: "Descartes recentes", subtitle: "Itens validados pelos Totens e sua situação operacional." },
    help: { label: "Solicitações de ajuda", icon: "circle-help", title: "Solicitações de ajuda", subtitle: "Fila de apoio enviada pelos Totens para acompanhamento da equipe." },
    redemptions: { label: "Resgates", icon: "ticket-check", title: "Resgates pendentes", subtitle: "Confirme a entrega das recompensas solicitadas pelos alunos." },
    machines: { label: "Totens", icon: "monitor-cog", title: "Estado dos Totens", subtitle: "Disponibilidade, sinais recentes e informações essenciais dos equipamentos." },
  };

  const state = {
    authenticated: false,
    view: "overview",
    scenario: "normal",
    helpFilter: "Todas",
    redemptionFilter: "Pendentes",
    redemptionToDeliver: null,
    toast: "",
  };

  function openHelpCount() {
    return helpRequests.filter((item) => item.status !== "Resolvida").length;
  }

  function pendingRedemptionCount() {
    return redemptions.filter((item) => item.status === "Pendente").length;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function icon(name, className = "") {
    return `<i data-lucide="${name}" class="${className}" aria-hidden="true"></i>`;
  }

  function accessTemplate() {
    return `
      <main class="access-page">
        <section class="access-brand" aria-labelledby="access-title">
          <div class="brand-lockup">
            <img src="../../totem_ui/assets/brand/logo_bingo_sem_slogan_clean.png" alt="BinGo" />
            <span>Admin Lite</span>
          </div>
          <div class="access-copy">
            <p class="access-kicker">Operação escolar</p>
            <h1 id="access-title">Acompanhe o que acontece nos Totens.</h1>
            <p>Depósitos, pedidos de ajuda e estado dos equipamentos reunidos em uma visão direta para a equipe responsável.</p>
          </div>
          <div class="access-footnote">${icon("shield-check")} Ambiente interno do Colégio ENIAC</div>
        </section>
        <section class="access-panel-wrap" aria-label="Acesso técnico">
          <form class="access-panel" id="access-form">
            <p class="eyebrow">Acesso técnico</p>
            <h2>Entrar no Admin</h2>
            <p>Use seu acesso autorizado para acompanhar a operação da escola.</p>
            <div class="field">
              <label for="admin-email">E-mail institucional</label>
              <input id="admin-email" name="email" type="email" autocomplete="username" value="alencar@bingo.demo" required />
            </div>
            <div class="field">
              <label for="admin-password">Senha</label>
              <input id="admin-password" name="password" type="password" autocomplete="current-password" value="123456" required />
            </div>
            <button class="primary-button" type="submit"><span>Acessar o Admin</span>${icon("arrow-right")}</button>
            <div class="access-note">
              ${icon("shield-check")}
              <span><strong>Ambiente demonstrativo.</strong> A autenticação segura será conectada ao contrato do backend.</span>
            </div>
          </form>
        </section>
      </main>`;
  }

  function navButton(key, count = "") {
    const meta = viewMeta[key];
    return `
      <button class="nav-button" type="button" data-view="${key}" aria-current="${state.view === key ? "page" : "false"}">
        <span class="nav-glyph">${icon(meta.icon)}</span>
        <span>${meta.label}</span>
        ${count ? `<span class="nav-count" aria-label="${count} pendentes">${count}</span>` : ""}
      </button>`;
  }

  function shellTemplate() {
    const meta = viewMeta[state.view];
    return `
      <div class="admin-shell">
        <aside class="sidebar" aria-label="Navegação principal">
          <div class="sidebar-brand">
            <img src="../../totem_ui/assets/brand/logo_bingo_sem_slogan_clean.png" alt="BinGo" />
            <span>Admin Lite</span>
          </div>
          <nav class="side-nav">
            ${navButton("overview")}
            ${navButton("deposits")}
            ${navButton("help", String(openHelpCount()))}
            ${navButton("redemptions", String(pendingRedemptionCount()))}
            ${navButton("machines")}
          </nav>
          <div class="sidebar-footer">
            <div class="operator">
              <span class="operator-avatar" aria-hidden="true">GA</span>
              <span><strong>Gustavo Alencar</strong><small>Operador demonstrativo</small></span>
            </div>
            <button class="text-button" type="button" data-action="logout">${icon("log-out")}<span>Sair da demonstração</span></button>
          </div>
        </aside>
        <div class="main-area">
          <header class="topbar">
            <div class="topbar-copy">
              <strong>Colégio ENIAC</strong>
              <span>Última atualização demonstrativa: agora</span>
            </div>
            <div class="topbar-actions">
              <span class="status-pill">${icon("circle-check")}Sistema operacional</span>
              <label>
                <span class="sr-only">Cenário da demonstração</span>
                <select class="demo-select" id="scenario-select" aria-label="Cenário da demonstração">
                  <option value="normal" ${state.scenario === "normal" ? "selected" : ""}>Dados normais</option>
                  <option value="loading" ${state.scenario === "loading" ? "selected" : ""}>Carregando</option>
                  <option value="empty" ${state.scenario === "empty" ? "selected" : ""}>Sem dados</option>
                  <option value="error" ${state.scenario === "error" ? "selected" : ""}>Falha de conexão</option>
                </select>
              </label>
            </div>
          </header>
          <main class="page-content" tabindex="-1">
            <div class="page-heading">
              <div>
                <p class="eyebrow">Admin Lite</p>
                <h1>${meta.title}</h1>
                <p>${meta.subtitle}</p>
              </div>
              <span class="source-pill">${icon("database")}Dados demonstrativos</span>
            </div>
            ${renderContent()}
          </main>
        </div>
        ${redemptionDialogTemplate()}
        ${state.toast ? `<div class="toast" role="status">${escapeHtml(state.toast)}</div>` : ""}
      </div>`;
  }

  function renderContent() {
    if (state.scenario === "loading") {
      return `<section class="state-panel" aria-label="Carregando dados"><div class="skeleton-stack"><div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div></div></section>`;
    }
    if (state.scenario === "empty") {
      return stateTemplate("inbox", "Nada por aqui agora", "Quando novos registros chegarem, eles aparecerão nesta área.");
    }
    if (state.scenario === "error") {
      return stateTemplate("circle-alert", "Não foi possível atualizar", "Confira a conexão e tente novamente. Nenhuma ação foi realizada.", true);
    }

    switch (state.view) {
      case "deposits": return depositsTemplate();
      case "help": return helpTemplate();
      case "redemptions": return redemptionsTemplate();
      case "machines": return machinesTemplate();
      default: return overviewTemplate();
    }
  }

  function stateTemplate(iconName, title, body, retry = false) {
    return `
      <section class="state-panel">
        <div class="state-content">
          <span class="state-icon">${icon(iconName)}</span>
          <h2>${title}</h2>
          <p>${body}</p>
          ${retry ? `<button class="secondary-button" type="button" data-action="retry" style="margin-top:18px">${icon("rotate-cw")}<span>Tentar novamente</span></button>` : ""}
        </div>
      </section>`;
  }

  function overviewTemplate() {
    return `
      <section class="summary-grid" aria-label="Resumo operacional">
        ${summaryCard("Descartes validados", discardStats.total.toLocaleString("pt-BR"), `${discardStats.today} hoje · ${discardStats.week} nesta semana`, "#00aeef", "archive-restore")}
        ${summaryCard("Ajudas abertas", String(openHelpCount()), "1 aguardando · 1 em atendimento", "#e52b3a", "circle-help")}
        ${summaryCard("Resgates pendentes", String(pendingRedemptionCount()), "Aguardam validação da entrega", "#ffb020", "ticket-check")}
        ${summaryCard("Totens online", "1 de 3", "1 com problema · 1 offline", "#39d353", "monitor-check")}
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head">
            <div><h2>Atividade recente</h2><p>Eventos que ajudam a acompanhar a operação.</p></div>
            <button class="secondary-button" type="button" data-view="deposits"><span>Ver descartes</span>${icon("arrow-right")}</button>
          </header>
          <div class="activity-list">
            ${deposits.slice(0, 3).map((item) => activityRow(item)).join("")}
          </div>
        </section>
        <section class="panel">
          <header class="panel-head">
            <div><h2>Precisa de atenção</h2><p>Prioridades para a equipe responsável.</p></div>
          </header>
          <div class="attention-list">
            ${attentionItem("Solicitação AJ-104", "Item não reconhecido na Biblioteca.", "#e52b3a", "circle-help")}
            ${attentionItem(`${pendingRedemptionCount()} resgates pendentes`, "Recompensas aguardam confirmação de entrega.", "#ffb020", "ticket-check")}
            ${attentionItem("Totem Laboratório offline", "Último sinal recebido há 38 minutos.", "#e52b3a", "wifi-off")}
          </div>
        </section>
      </div>`;
  }

  function summaryCard(label, value, note, accent, iconName) {
    return `<article class="summary-card" style="--accent:${accent}"><span class="summary-icon">${icon(iconName)}</span><small>${label}</small><strong>${value}</strong><span>${note}</span></article>`;
  }

  function activityRow(item) {
    const tagClass = item.status === "Validado" ? "tag--success" : item.status === "Revisão" ? "tag--warning" : "tag--blue";
    return `
      <article class="activity-row">
        <span class="activity-icon">${icon(itemIcon(item.item))}</span>
        <div class="row-copy"><strong>${item.student}</strong><span>${item.item} · ${item.className}</span></div>
        <div class="row-meta"><strong>${item.points} pts</strong><br />${item.time}</div>
        <span class="tag ${tagClass}">${item.status}</span>
      </article>`;
  }

  function itemIcon(item) {
    if (item === "Celular") return "smartphone";
    if (item === "Cabo USB") return "cable";
    if (item === "Mouse") return "mouse";
    return "battery-medium";
  }

  function attentionItem(title, body, accent, iconName) {
    return `<article class="attention-item" style="--accent:${accent}"><span class="attention-icon">${icon(iconName)}</span><div><strong>${title}</strong><span>${body}</span></div></article>`;
  }

  function depositsTemplate() {
    return `
      <section class="period-metrics" aria-label="Quantidades de descartes">
        ${periodMetric("Total registrado", discardStats.total.toLocaleString("pt-BR"), "database")}
        ${periodMetric("Hoje", String(discardStats.today), "calendar-days")}
        ${periodMetric("Nesta semana", String(discardStats.week), "calendar-range")}
      </section>
      <div class="toolbar">
        <div class="filter-group" aria-label="Filtros de descartes">
          <button class="filter-button" type="button" aria-pressed="true">Hoje</button>
          <button class="filter-button" type="button" aria-pressed="false">Validados</button>
          <button class="filter-button" type="button" aria-pressed="false">Em revisão</button>
        </div>
        <button class="secondary-button" type="button" data-action="export-demo">${icon("download")}<span>Exportar visão</span></button>
      </div>
      <section class="panel" aria-label="Tabela de descartes">
        <table class="data-table">
          <thead><tr><th>Horário</th><th>Aluno ou perfil</th><th>Turma</th><th>Item</th><th>Pontos</th><th>Estado</th></tr></thead>
          <tbody>
            ${deposits.map((item) => `<tr><td>${item.time}</td><td><strong>${item.student}</strong></td><td>${item.className}</td><td>${item.item}</td><td>${item.points}</td><td><span class="tag ${item.status === "Validado" ? "tag--success" : item.status === "Revisão" ? "tag--warning" : "tag--blue"}">${item.status}</span></td></tr>`).join("")}
          </tbody>
        </table>
      </section>`;
  }

  function periodMetric(label, value, iconName) {
    return `<article class="period-metric"><span>${icon(iconName)}</span><div><small>${label}</small><strong>${value}</strong></div></article>`;
  }

  function helpTemplate() {
    const filtered = state.helpFilter === "Todas" ? helpRequests : helpRequests.filter((item) => item.status === state.helpFilter);
    return `
      <div class="toolbar">
        <div class="filter-group" aria-label="Filtros das solicitações">
          ${["Todas", "Aguardando", "Em atendimento", "Resolvida"].map((filter) => `<button class="filter-button" type="button" data-help-filter="${filter}" aria-pressed="${state.helpFilter === filter}">${filter}</button>`).join("")}
        </div>
      </div>
      <section class="panel help-list" aria-label="Fila de solicitações de ajuda">
        ${filtered.length ? filtered.map((item) => helpRow(item)).join("") : `<div style="padding:20px">${stateTemplate("inbox", "Nenhuma solicitação neste filtro", "Escolha outro estado para continuar a consulta.")}</div>`}
      </section>`;
  }

  function helpRow(item) {
    const priorityColor = item.priority === "Alta" ? "#e52b3a" : item.priority === "Média" ? "#ffb020" : "#39d353";
    const statusClass = item.status === "Resolvida" ? "tag--success" : item.status === "Em atendimento" ? "tag--blue" : "tag--warning";
    return `
      <article class="help-row">
        <span class="priority-line" style="--accent:${priorityColor}" aria-label="Prioridade ${item.priority}"></span>
        <div class="row-copy"><strong>${item.place}</strong><span>${item.id} · ${item.reason}</span></div>
        <div class="row-meta"><strong>${item.priority}</strong><br />prioridade</div>
        <div class="row-meta"><span class="tag ${statusClass}">${item.status}</span><br />${item.time}</div>
        <button class="row-action ${item.status === "Aguardando" ? "row-action--primary" : ""}" type="button" data-help-action="${item.id}">${icon(item.status === "Aguardando" ? "hand" : "arrow-up-right")}<span>${item.status === "Aguardando" ? "Assumir" : "Ver detalhes"}</span></button>
      </article>`;
  }

  function redemptionsTemplate() {
    const filtered = state.redemptionFilter === "Todas"
      ? redemptions
      : redemptions.filter((item) => item.status === (state.redemptionFilter === "Pendentes" ? "Pendente" : "Entregue"));
    return `
      <div class="toolbar">
        <div class="filter-group" aria-label="Filtros dos resgates">
          ${["Pendentes", "Entregues", "Todas"].map((filter) => `<button class="filter-button" type="button" data-redemption-filter="${filter}" aria-pressed="${state.redemptionFilter === filter}">${filter}</button>`).join("")}
        </div>
        <span class="queue-summary">${icon("clock-3")}<strong>${pendingRedemptionCount()}</strong> aguardando entrega</span>
      </div>
      <section class="panel redemption-list" aria-label="Fila de resgates">
        ${filtered.length ? filtered.map((item) => redemptionRow(item)).join("") : stateTemplate("badge-check", "Fila concluída", "Não há resgates aguardando entrega neste momento.")}
      </section>`;
  }

  function redemptionRow(item) {
    const pending = item.status === "Pendente";
    return `
      <article class="redemption-row">
        <span class="redemption-icon">${icon(pending ? "ticket" : "badge-check")}</span>
        <div class="row-copy"><strong>${item.reward}</strong><span>${item.student} · ${item.className}</span></div>
        <div class="redemption-code"><small>Código</small><strong>${item.code}</strong></div>
        <div class="row-meta"><strong>${item.requestedAt}</strong><br />${item.expiresAt}</div>
        <span class="tag ${pending ? "tag--warning" : "tag--success"}">${item.status}</span>
        ${pending
          ? `<button class="row-action row-action--primary" type="button" data-redemption-deliver="${item.id}">${icon("package-check")}<span>Validar entrega</span></button>`
          : `<span class="delivered-label">${icon("check")} Concluído</span>`}
      </article>`;
  }

  function redemptionDialogTemplate() {
    const item = redemptions.find((redemption) => redemption.id === state.redemptionToDeliver);
    if (!item) return "";
    return `
      <div class="dialog-backdrop" data-action="cancel-redemption">
        <section class="confirm-dialog" role="dialog" aria-modal="true" aria-labelledby="redemption-dialog-title" data-dialog-panel>
          <span class="confirm-dialog-icon">${icon("package-check")}</span>
          <p class="eyebrow">Simulação de resgate</p>
          <h2 id="redemption-dialog-title">Confirmar entrega?</h2>
          <p>Confira o código <strong>${item.code}</strong> e entregue <strong>${item.reward}</strong> para ${item.student}.</p>
          <div class="dialog-note">${icon("shield-check")} Esta ação será apenas demonstrativa até a integração com o backend.</div>
          <div class="dialog-actions">
            <button class="secondary-button" type="button" data-action="cancel-redemption">Cancelar</button>
            <button class="primary-button" type="button" data-action="confirm-redemption">${icon("check")}<span>Confirmar entrega</span></button>
          </div>
        </section>
      </div>`;
  }

  function machinesTemplate() {
    return `
      <section class="machine-grid" aria-label="Equipamentos cadastrados">
        ${machines.map((machine) => `
          <article class="machine-card" style="--status-color:${machine.color};--status-ink:${machine.ink};--status-bg:${machine.bg}">
            <div class="machine-card-head">
              <div><h2>${machine.name}</h2><p>${machine.code}</p></div>
              <span class="health-pill">${icon(machine.status === "Online" ? "circle-check" : machine.status === "Com problema" ? "triangle-alert" : "wifi-off")}${machine.status}</span>
            </div>
            <div class="machine-metrics">
              ${machineMetric("Câmera", machine.camera)}
              ${machineMetric("Porta", machine.door)}
              ${machineMetric("Depósitos", machine.deposits)}
              ${machineMetric("Versão", machine.version)}
            </div>
            <footer class="machine-footer"><span class="last-seen">${icon("radio")}<span>Última comunicação<br /><strong>${machine.lastSeen}</strong></span></span><button class="text-button" type="button" data-machine="${machine.code}"><span>Ver diagnóstico</span>${icon("arrow-up-right")}</button></footer>
          </article>`).join("")}
      </section>`;
  }

  function machineMetric(label, value) {
    return `<div class="machine-metric"><small>${label}</small><strong>${value}</strong></div>`;
  }

  function showToast(message) {
    state.toast = message;
    render();
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => {
      state.toast = "";
      render();
    }, 2600);
  }

  function bindEvents() {
    document.querySelector("#access-form")?.addEventListener("submit", (event) => {
      event.preventDefault();
      state.authenticated = true;
      render();
      window.scrollTo(0, 0);
    });

    document.querySelectorAll("[data-view]").forEach((button) => {
      button.addEventListener("click", () => {
        state.view = button.dataset.view;
        state.scenario = "normal";
        render();
        document.querySelector(".page-content")?.focus();
      });
    });

    document.querySelector("#scenario-select")?.addEventListener("change", (event) => {
      state.scenario = event.target.value;
      render();
    });

    document.querySelectorAll("[data-help-filter]").forEach((button) => {
      button.addEventListener("click", () => {
        state.helpFilter = button.dataset.helpFilter;
        render();
      });
    });

    document.querySelectorAll("[data-help-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const request = helpRequests.find((item) => item.id === button.dataset.helpAction);
        if (request?.status === "Aguardando") {
          request.status = "Em atendimento";
          showToast(`${request.id} marcado em atendimento somente nesta demonstração.`);
          return;
        }
        showToast("Detalhes completos dependem do contrato de dados do backend.");
      });
    });

    document.querySelectorAll("[data-redemption-filter]").forEach((button) => {
      button.addEventListener("click", () => {
        state.redemptionFilter = button.dataset.redemptionFilter;
        render();
      });
    });

    document.querySelectorAll("[data-redemption-deliver]").forEach((button) => {
      button.addEventListener("click", () => {
        state.redemptionToDeliver = button.dataset.redemptionDeliver;
        render();
        document.querySelector("[data-action='confirm-redemption']")?.focus();
      });
    });

    document.querySelectorAll("[data-action='cancel-redemption']").forEach((element) => {
      element.addEventListener("click", (event) => {
        if (event.target.closest("[data-dialog-panel]") && !event.target.closest("button")) return;
        state.redemptionToDeliver = null;
        render();
      });
    });

    document.querySelector("[data-action='confirm-redemption']")?.addEventListener("click", () => {
      const item = redemptions.find((redemption) => redemption.id === state.redemptionToDeliver);
      if (!item || item.status !== "Pendente") return;
      item.status = "Entregue";
      item.expiresAt = "Entregue agora";
      state.redemptionToDeliver = null;
      showToast(`${item.id} entregue somente nesta demonstração.`);
    });

    document.querySelector("[data-action='logout']")?.addEventListener("click", () => {
      state.authenticated = false;
      state.view = "overview";
      state.scenario = "normal";
      render();
      window.scrollTo(0, 0);
    });

    document.querySelector("[data-action='retry']")?.addEventListener("click", () => {
      state.scenario = "normal";
      showToast("Dados demonstrativos carregados novamente.");
    });

    document.querySelector("[data-action='export-demo']")?.addEventListener("click", () => {
      showToast("A exportação será conectada quando o contrato do Admin estiver definido.");
    });

    document.querySelectorAll("[data-machine]").forEach((button) => {
      button.addEventListener("click", () => showToast("Diagnóstico detalhado aguardando integração com a saúde do Totem."));
    });
  }

  function render() {
    app.innerHTML = state.authenticated ? shellTemplate() : accessTemplate();
    if (window.lucide) {
      window.lucide.createIcons({ attrs: { "stroke-width": 2.2 } });
    }
    bindEvents();
  }

  render();
})();
