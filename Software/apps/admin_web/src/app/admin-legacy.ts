// @ts-nocheck
// Renderer demonstrativo. Regras de acesso permanecem centralizadas em admin-access.ts.
import { ADMIN_ROLES, canAccessView, firstViewForRole } from './admin-access';

export function mountAdmin(app: HTMLElement): void {

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

  const schools = [
    { name: "Colégio ENIAC", city: "Guarulhos · SP", students: "428 alunos", machines: "3 Totens", status: "Ativa" },
    { name: "Escola Horizonte", city: "São Paulo · SP", students: "312 alunos", machines: "2 Totens", status: "Implantação" },
    { name: "Instituto Nova Geração", city: "Campinas · SP", students: "506 alunos", machines: "3 Totens", status: "Ativa" },
  ];

  const students = [
    { name: "Ana Clara Martins", email: "ana.martins@aluno.demo", registration: "20261042", className: "9º A", balance: "340", status: "Ativa" },
    { name: "Lucas Pereira", email: "lucas.pereira@aluno.demo", registration: "20261087", className: "8º B", balance: "215", status: "Ativo" },
    { name: "Marina Santos", email: "marina.santos@aluno.demo", registration: "20261103", className: "9º A", balance: "180", status: "Ativa" },
    { name: "Rafael Gomes", email: "rafael.gomes@aluno.demo", registration: "20261128", className: "7º A", balance: "95", status: "Inativo" },
  ];

  const classes = [
    { name: "9º A", students: "31 alunos", xp: "12.480 XP", participation: "84%", status: "Ativa" },
    { name: "8º B", students: "29 alunos", xp: "10.920 XP", participation: "79%", status: "Ativa" },
    { name: "7º A", students: "33 alunos", xp: "9.740 XP", participation: "72%", status: "Ativa" },
  ];

  const administrators = [
    { name: "Gustavo Alencar", email: "alencar@bingo.demo", role: "ADMIN_B", scope: "Colégio ENIAC", status: "Ativo" },
    { name: "Paula Mendes", email: "paula@eniac.demo", role: "ADMIN_C", scope: "Colégio ENIAC", status: "Ativa" },
    { name: "Equipe BinGo", email: "admin@bingo.demo", role: "ADMIN_A", scope: "Global", status: "Ativa" },
  ];

  const products = [
    { name: "Suco natural", price: "120 BinCoins", stock: "18 unidades", status: "Ativo" },
    { name: "Caneta temática", price: "90 BinCoins", stock: "7 unidades", status: "Ativa" },
    { name: "Ticket da cantina", price: "160 BinCoins", stock: "Ilimitado", status: "Ativo" },
    { name: "Prêmio surpresa", price: "240 BinCoins", stock: "Sem estoque", status: "Inativo" },
  ];

  const missions = [
    { name: "Circuito dos cabos", type: "Missão semanal", period: "18–25 set", status: "Ativa" },
    { name: "Alerta SCR4P", type: "Evento global", period: "28 set", status: "Pendente" },
  ];

  const economySettings = [
    { title: "Valor-base por descarte", value: "30", unit: "pontos", description: "Usado como referência antes dos bônus ambientais.", icon: "gauge" },
    { title: "Teto do BinBazar", value: "300", unit: "BinCoins", description: "Preço máximo permitido para produtos escolares.", icon: "badge-dollar-sign" },
    { title: "Bônus por categoria", value: "2", unit: "×", description: "Taxa global aplicada conforme a categoria ambiental.", icon: "leaf" },
    { title: "Meta territorial", value: "8", unit: "descartes", description: "Referência atual para avanço de cenário.", icon: "map" },
  ];

  const classRequests = [
    { id: "TT-032", student: "Marina Santos", current: "9º A", destination: "9º B", author: "Paula Mendes", status: "Pendente" },
    { id: "TT-029", student: "Lucas Pereira", current: "8º A", destination: "8º B", author: "Paula Mendes", status: "Aprovada" },
  ];

  const viewMeta = {
    overview: { label: "Visão geral", icon: "layout-dashboard", title: "Operação de hoje", subtitle: "O que precisa de atenção na escola, sem esconder o contexto técnico." },
    schools: { label: "Escolas", icon: "school", title: "Escolas participantes", subtitle: "Estrutura global das escolas vinculadas ao ecossistema BinGo." },
    administrators: { label: "Administradores", icon: "shield-user", title: "Contas administrativas", subtitle: "Acessos ativos e inativos dentro do escopo permitido." },
    students: { label: "Alunos", icon: "users", title: "Alunos da escola", subtitle: "Consulta e administração dos participantes do Colégio ENIAC." },
    classes: { label: "Turmas", icon: "users-round", title: "Turmas da escola", subtitle: "Organização das turmas e participação dos alunos." },
    pending: { label: "Pendências", icon: "list-todo", title: "Pendências da escola", subtitle: "Decisões administrativas e operações que precisam de atenção." },
    requests: { label: "Solicitações", icon: "send", title: "Minhas solicitações", subtitle: "Pedidos operacionais enviados para avaliação dos administradores da escola." },
    deposits: { label: "Descartes", icon: "archive-restore", title: "Descartes recentes", subtitle: "Itens validados pelos Totens e sua situação operacional." },
    help: { label: "Solicitações de ajuda", icon: "circle-help", title: "Solicitações de ajuda", subtitle: "Fila de apoio enviada pelos Totens para acompanhamento da equipe." },
    products: { label: "Produtos e estoque", icon: "package-open", title: "Produtos do BinBazar", subtitle: "Catálogo, preço, disponibilidade e estoque administrados pela escola." },
    redemptions: { label: "Resgates", icon: "ticket-check", title: "Resgates pendentes", subtitle: "Confirme a entrega das recompensas solicitadas pelos alunos." },
    missions: { label: "Missões", icon: "flag", title: "Missões do BinGo", subtitle: "Ciclos globais disponíveis e sua situação nas escolas." },
    machines: { label: "Totens", icon: "monitor-cog", title: "Estado dos Totens", subtitle: "Disponibilidade, sinais recentes e informações essenciais dos equipamentos." },
    economy: { label: "Economia", icon: "sliders-horizontal", title: "Configurações econômicas", subtitle: "Valores-base, bônus ambientais, metas e teto global do BinBazar." },
  };

  const state = {
    authenticated: false,
    role: "ADMIN_C",
    view: "overview",
    scenario: "normal",
    helpFilter: "Todas",
    redemptionFilter: "Pendentes",
    redemptionToDeliver: null,
    activeOperation: null,
    toast: "",
  };

  const operationDefinitions = {
    "student-create": { title: "Cadastrar aluno", icon: "user-plus", submit: "Cadastrar aluno" },
    "student-edit": { title: "Editar dados do aluno", icon: "square-pen", submit: "Salvar alterações" },
    "student-view": { title: "Consultar aluno", icon: "user-round-search", submit: "Fechar" },
    "class-create": { title: "Criar turma", icon: "users-round", submit: "Criar turma" },
    "class-edit": { title: "Editar turma", icon: "square-pen", submit: "Salvar alterações" },
    "request-create": { title: "Solicitar troca de turma", icon: "send", submit: "Enviar solicitação" },
    "request-review": { title: "Analisar troca de turma", icon: "check-check", submit: "Aprovar troca" },
    "request-cancel": { title: "Cancelar solicitação", icon: "circle-x", submit: "Confirmar cancelamento" },
    "product-create": { title: "Cadastrar produto", icon: "package-plus", submit: "Cadastrar produto" },
    "product-edit": { title: "Editar produto e estoque", icon: "package-open", submit: "Salvar alterações" },
    "admin-create": { title: "Cadastrar administrador", icon: "shield-plus", submit: "Cadastrar acesso" },
    "admin-open": { title: "Gerenciar administrador", icon: "shield-user", submit: "Salvar estado" },
    "redemption-cancel": { title: "Cancelar resgate reservado", icon: "ticket-x", submit: "Cancelar resgate" },
    "school-create": { title: "Cadastrar escola", icon: "school", submit: "Cadastrar escola" },
    "school-open": { title: "Detalhes da escola", icon: "school", submit: "Salvar estado" },
    "mission-create": { title: "Criar missão global", icon: "flag", submit: "Criar missão" },
    "mission-edit": { title: "Editar missão global", icon: "flag", submit: "Salvar missão" },
    "economy-edit": { title: "Editar regra econômica", icon: "sliders-horizontal", submit: "Salvar regra" },
    "machine-view": { title: "Diagnóstico do Totem", icon: "monitor-cog", submit: "Fechar" },
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
            <img src="assets/brand/logo-bingo.png" alt="BinGo" />
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
              <label for="admin-role">Perfil demonstrativo</label>
              <select id="admin-role" name="role" data-role-select>
                ${Object.values(ADMIN_ROLES).map((role) => `<option value="${role.code}" ${state.role === role.code ? "selected" : ""}>${role.shortLabel}</option>`).join("")}
              </select>
              <small class="field-hint">No produto real, o perfil virá da autenticação e será validado pelo backend.</small>
            </div>
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
    const role = ADMIN_ROLES[state.role];
    const overviewMeta = state.role === "ADMIN_A"
      ? { title: "Visão global do BinGo", subtitle: "Estrutura, implantação e saúde do ecossistema sem interferir na operação cotidiana das escolas." }
      : state.role === "ADMIN_B"
        ? { title: "Gestão do Colégio ENIAC", subtitle: "Pessoas, pendências e recursos que precisam da administração da escola." }
        : { title: "Operação de hoje", subtitle: "O que precisa de atenção na escola, sem esconder o contexto técnico." };
    const meta = state.view === "overview" ? { ...viewMeta.overview, ...overviewMeta } : viewMeta[state.view];
    return `
      <div class="admin-shell">
        <aside class="sidebar" aria-label="Navegação principal">
          <div class="sidebar-brand">
            <img src="assets/brand/logo-bingo.png" alt="BinGo" />
            <span>Admin Lite</span>
          </div>
          <nav class="side-nav">
            ${role.views.map((view) => navButton(
              view,
              view === "help" ? String(openHelpCount()) : view === "redemptions" || view === "pending" ? String(pendingRedemptionCount()) : "",
            )).join("")}
          </nav>
          <div class="sidebar-footer">
            <div class="operator">
              <span class="operator-avatar" aria-hidden="true">${role.operatorInitials}</span>
              <span><strong>${role.operatorName}</strong><small>${role.shortLabel}</small></span>
            </div>
            <button class="text-button" type="button" data-action="logout">${icon("log-out")}<span>Sair da demonstração</span></button>
          </div>
        </aside>
        <div class="main-area">
          <header class="topbar">
            <div class="topbar-copy">
              <strong>${role.scope}</strong>
              <span>Última atualização demonstrativa: agora</span>
            </div>
            <div class="topbar-actions">
              <span class="status-pill">${icon("circle-check")}Sistema operacional</span>
              <label>
                <span class="sr-only">Perfil demonstrativo</span>
                <select class="demo-select" data-role-switch aria-label="Perfil demonstrativo">
                  ${Object.values(ADMIN_ROLES).map((option) => `<option value="${option.code}" ${state.role === option.code ? "selected" : ""}>${option.shortLabel}</option>`).join("")}
                </select>
              </label>
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
                <p class="eyebrow">${role.shortLabel}</p>
                <h1>${meta.title}</h1>
                <p>${meta.subtitle}</p>
              </div>
              <span class="source-pill">${icon("database")}Dados demonstrativos</span>
            </div>
            ${renderContent()}
          </main>
        </div>
        ${redemptionDialogTemplate()}
        ${operationDialogTemplate()}
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
      case "schools": return schoolsTemplate();
      case "administrators": return administratorsTemplate();
      case "students": return studentsTemplate();
      case "classes": return classesTemplate();
      case "pending": return pendingTemplate();
      case "requests": return requestsTemplate();
      case "deposits": return depositsTemplate();
      case "help": return helpTemplate();
      case "products": return productsTemplate();
      case "redemptions": return redemptionsTemplate();
      case "missions": return missionsTemplate();
      case "machines": return machinesTemplate();
      case "economy": return economyTemplate();
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
    if (state.role === "ADMIN_A") return globalOverviewTemplate();
    if (state.role === "ADMIN_B") return schoolOverviewTemplate();
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

  function globalOverviewTemplate() {
    return `
      <section class="summary-grid" aria-label="Resumo global">
        ${summaryCard("Escolas cadastradas", "3", "2 ativas · 1 em implantação", "#00aeef", "school")}
        ${summaryCard("Administradores ativos", "6", "1 global · 5 escolares", "#8a2cff", "shield-user")}
        ${summaryCard("Totens operacionais", "6 de 8", "1 com problema · 1 offline", "#39d353", "monitor-check")}
        ${summaryCard("Missões globais", "4", "2 ativas · 2 programadas", "#ffb020", "flag")}
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head"><div><h2>Implantação das escolas</h2><p>Estrutura geral sem filas operacionais locais.</p></div><button class="secondary-button" data-view="schools"><span>Ver escolas</span>${icon("arrow-right")}</button></header>
          <div class="entity-list">${schools.map((school) => entityRow("school", school.name, school.city, `${school.students} · ${school.machines}`, school.status)).join("")}</div>
        </section>
        <section class="panel">
          <header class="panel-head"><div><h2>Saúde do ecossistema</h2><p>Sinais que exigem acompanhamento do BinGo.</p></div></header>
          <div class="attention-list">
            ${attentionItem("Totem Laboratório offline", "Último sinal há 38 minutos no Colégio ENIAC.", "#e52b3a", "wifi-off")}
            ${attentionItem("Escola Horizonte em implantação", "Dois Totens aguardam vínculo operacional.", "#ffb020", "school")}
            ${attentionItem("Ciclo SCR4P programado", "Início previsto para a próxima segunda-feira.", "#8a2cff", "flag")}
          </div>
        </section>
      </div>`;
  }

  function schoolOverviewTemplate() {
    return `
      <section class="summary-grid" aria-label="Resumo da escola">
        ${summaryCard("Alunos ativos", "427", "1 aluno inativo", "#00aeef", "users")}
        ${summaryCard("Turmas", "14", "9º A lidera a participação", "#8a2cff", "users-round")}
        ${summaryCard("Pendências", String(pendingRedemptionCount() + 1), "3 resgates · 1 troca de turma", "#ffb020", "list-todo")}
        ${summaryCard("Totens online", "1 de 3", "1 com problema · 1 offline", "#39d353", "monitor-check")}
      </section>
      <div class="dashboard-grid">
        <section class="panel">
          <header class="panel-head"><div><h2>Pendências prioritárias</h2><p>Decisões administrativas e entregas da escola.</p></div><button class="secondary-button" data-view="pending"><span>Ver pendências</span>${icon("arrow-right")}</button></header>
          <div class="attention-list">
            ${attentionItem("Troca de turma TT-032", "Marina Santos aguarda decisão para o 9º B.", "#8a2cff", "users-round")}
            ${attentionItem(`${pendingRedemptionCount()} resgates pendentes`, "Produtos reservados aguardam entrega.", "#ffb020", "ticket-check")}
            ${attentionItem("Totem Laboratório offline", "Último sinal recebido há 38 minutos.", "#e52b3a", "wifi-off")}
          </div>
        </section>
        <section class="panel">
          <header class="panel-head"><div><h2>Participação das turmas</h2><p>Visão coletiva, sem exposição individual.</p></div></header>
          <div class="entity-list">${classes.map((item) => entityRow("users-round", item.name, item.students, `${item.xp} · ${item.participation}`, item.status)).join("")}</div>
        </section>
      </div>`;
  }

  function entityRow(iconName, title, subtitle, meta, status, action = "") {
    const statusClass = ["Ativa", "Ativo", "Online", "Aprovada"].includes(status) ? "tag--success" : status === "Pendente" || status === "Implantação" ? "tag--warning" : "tag--danger";
    return `<article class="entity-row"><span class="activity-icon">${icon(iconName)}</span><div class="row-copy"><strong>${title}</strong><span>${subtitle}</span></div><div class="row-meta"><strong>${meta}</strong></div><span class="tag ${statusClass}">${status}</span>${action}</article>`;
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
    const statusClass = pending ? "tag--warning" : item.status === "Entregue" ? "tag--success" : "tag--danger";
    return `
      <article class="redemption-row">
        <span class="redemption-icon">${icon(pending ? "ticket" : "badge-check")}</span>
        <div class="row-copy"><strong>${item.reward}</strong><span>${item.student} · ${item.className}</span></div>
        <div class="redemption-code"><small>Código</small><strong>${item.code}</strong></div>
        <div class="row-meta"><strong>${item.requestedAt}</strong><br />${item.expiresAt}</div>
        <span class="tag ${statusClass}">${item.status}</span>
        ${pending
          ? `<div class="row-actions"><button class="row-action row-action--primary" type="button" data-redemption-deliver="${item.id}">${icon("package-check")}<span>Validar entrega</span></button><button class="row-action" type="button" data-contract-action="redemption-cancel" data-entity-key="${item.id}">${icon("ticket-x")}<span>Cancelar</span></button></div>`
          : `<span class="delivered-label">${icon(item.status === "Entregue" ? "check" : "x")} ${item.status === "Entregue" ? "Concluído" : "Cancelado"}</span>`}
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

  function formField(name, label, value = "", options = null, readonly = false) {
    const safeValue = escapeHtml(value);
    const control = options
      ? `<select id="operation-${name}" name="${name}" ${readonly ? "disabled" : ""}>${options.map((option) => `<option value="${escapeHtml(option)}" ${option === value ? "selected" : ""}>${escapeHtml(option)}</option>`).join("")}</select>`
      : `<input id="operation-${name}" name="${name}" value="${safeValue}" ${readonly ? "readonly" : ""} required />`;
    return `<div class="field"><label for="operation-${name}">${label}</label>${control}</div>`;
  }

  function operationFields(action, index, key) {
    const student = Number.isInteger(index) ? students[index] : null;
    const classItem = Number.isInteger(index) ? classes[index] : null;
    const request = Number.isInteger(index) ? classRequests[index] : null;
    const product = Number.isInteger(index) ? products[index] : null;
    const admin = key ? administrators.find((item) => item.email === key) : null;
    const school = key ? schools.find((item) => item.name === key) : null;
    const mission = Number.isInteger(index) ? missions[index] : null;
    const economy = Number.isInteger(index) ? economySettings[index] : null;
    const machine = key ? machines.find((item) => item.code === key) : null;
    if (action.startsWith("student-")) {
      const readonly = action === "student-view";
      return `${formField("name", "Nome completo", student?.name || "", null, readonly)}
        ${formField("email", "E-mail institucional", student?.email || "", null, readonly)}
        ${formField("registration", "RA ou matrícula", student?.registration || "", null, readonly)}
        ${formField("className", "Turma", student?.className || classes[0].name, classes.map((item) => item.name), readonly)}
        ${readonly ? `<div class="dialog-note">${icon("eye")} Consulta sem permissão para editar saldo, PIN ou dados cadastrais.</div>` : ""}`;
    }
    if (action.startsWith("class-")) {
      return `${formField("name", "Nome da turma", classItem?.name || "")}
        ${formField("status", "Estado", classItem?.status || "Ativa", ["Ativa", "Inativa"])}`;
    }
    if (action === "request-create") {
      return `${formField("student", "Aluno", students[0].name, students.map((item) => item.name))}
        ${formField("destination", "Nova turma", classes[0].name, classes.map((item) => item.name))}
        <div class="dialog-note">${icon("info")} A troca só será aplicada depois da aprovação de um Admin B.</div>`;
    }
    if (action === "request-review" || action === "request-cancel") {
      return `<div class="operation-summary"><strong>${escapeHtml(request?.student || "Solicitação")}</strong><span>${escapeHtml(request?.current || "")} → ${escapeHtml(request?.destination || "")}</span><small>${escapeHtml(request?.id || "")}</small></div>
        <div class="dialog-note">${icon("history")} A decisão ficará registrada somente nesta demonstração.</div>`;
    }
    if (action.startsWith("product-")) {
      return `${formField("name", "Produto", product?.name || "")}
        ${formField("price", "Preço em BinCoins", product?.price?.replace(" BinCoins", "") || "90")}
        ${formField("stock", "Estoque", product?.stock?.replace(" unidades", "") || "10")}
        ${formField("status", "Disponibilidade", product?.status || "Ativo", ["Ativo", "Inativo"])}`;
    }
    if (action.startsWith("admin-")) {
      const roleOptions = state.role === "ADMIN_B" ? ["ADMIN_C"] : ["ADMIN_A", "ADMIN_B", "ADMIN_C"];
      return `${formField("name", "Nome", admin?.name || "")}
        ${formField("email", "E-mail institucional", admin?.email || "")}
        ${formField("role", "Perfil", admin?.role || roleOptions[0], roleOptions)}
        ${formField("status", "Estado do acesso", admin?.status || "Ativo", ["Ativo", "Inativo"])}
        <div class="dialog-note">${icon("shield-check")} O backend deverá validar escopo, impedir auto-inativação e registrar auditoria.</div>`;
    }
    if (action === "redemption-cancel") {
      const redemption = redemptions.find((item) => item.id === key);
      return `<div class="operation-summary"><strong>${escapeHtml(redemption?.reward || "Resgate")}</strong><span>${escapeHtml(redemption?.student || "")} · ${escapeHtml(redemption?.code || "")}</span><small>Os BinCoins deverão ser estornados pelo backend de forma atômica.</small></div>
        <div class="dialog-note">${icon("triangle-alert")} Confirme apenas quando a recompensa não será entregue.</div>`;
    }
    if (action.startsWith("school-")) {
      return `${formField("name", "Nome da escola", school?.name || "")}
        ${formField("city", "Cidade e estado", school?.city || "")}
        ${formField("status", "Estado", school?.status || "Implantação", ["Implantação", "Ativa", "Inativa"])}
        <div class="dialog-note">${icon("database")} Vínculos, identificadores e isolamento dos dados serão definidos pelo backend.</div>`;
    }
    if (action.startsWith("mission-")) {
      return `${formField("name", "Nome da missão", mission?.name || "")}
        ${formField("type", "Tipo", mission?.type || "Missão semanal", ["Missão semanal", "Evento global"])}
        ${formField("period", "Período", mission?.period || "A definir")}
        ${formField("status", "Estado", mission?.status || "Pendente", ["Pendente", "Ativa", "Encerrada"])}`;
    }
    if (action === "economy-edit") {
      return `<div class="operation-summary"><strong>${escapeHtml(economy?.title || "Regra")}</strong><span>${escapeHtml(economy?.description || "")}</span></div>
        ${formField("value", `Valor em ${economy?.unit || "unidades"}`, economy?.value || "")}
        <div class="dialog-note">${icon("history")} A regra futura não poderá recalcular registros já confirmados.</div>`;
    }
    if (action === "machine-view") {
      return `<div class="operation-summary"><strong>${escapeHtml(machine?.name || "Totem")}</strong><span>${escapeHtml(machine?.code || "")} · ${escapeHtml(machine?.status || "")}</span><small>Última comunicação: ${escapeHtml(machine?.lastSeen || "indisponível")}</small></div>
        <div class="diagnostic-grid">${machineMetric("Câmera", machine?.camera || "-")}${machineMetric("Porta", machine?.door || "-")}${machineMetric("Versão", machine?.version || "-")}</div>
        <div class="dialog-note">${icon("radio")} Telemetria detalhada e comandos remotos dependem do serviço do Totem.</div>`;
    }
    return `<div class="dialog-note">${icon("plug-zap")} Esta etapa depende do contrato técnico do backend e permanece apenas como prévia visual.</div>`;
  }

  function operationDialogTemplate() {
    const operation = state.activeOperation;
    if (!operation) return "";
    const definition = operationDefinitions[operation.action] || {
      title: "Fluxo preparado",
      icon: "panels-top-left",
      submit: "Fechar",
    };
    const isViewOnly = operation.action === "student-view" || operation.action === "machine-view" || !operationDefinitions[operation.action];
    return `
      <div class="dialog-backdrop" data-operation-close>
        <section class="confirm-dialog operation-dialog" role="dialog" aria-modal="true" aria-labelledby="operation-dialog-title" data-dialog-panel>
          <span class="confirm-dialog-icon">${icon(definition.icon)}</span>
          <p class="eyebrow">Dados demonstrativos</p>
          <h2 id="operation-dialog-title">${definition.title}</h2>
          <form id="operation-form">
            <div class="operation-fields">${operationFields(operation.action, operation.index, operation.key)}</div>
            <div class="dialog-actions">
              <button class="secondary-button" type="button" data-operation-close>${isViewOnly ? "Fechar" : "Cancelar"}</button>
              ${isViewOnly ? "" : operation.action === "request-review" ? `<button class="danger-button" type="button" data-operation-reject>${icon("x")}<span>Recusar</span></button>` : ""}
              ${isViewOnly ? "" : `<button class="primary-button" type="submit">${icon("check")}<span>${definition.submit}</span></button>`}
            </div>
          </form>
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
            <footer class="machine-footer"><span class="last-seen">${icon("radio")}<span>Última comunicação<br /><strong>${machine.lastSeen}</strong></span></span><button class="text-button" type="button" data-contract-action="machine-view" data-entity-key="${machine.code}"><span>Ver diagnóstico</span>${icon("arrow-up-right")}</button></footer>
          </article>`).join("")}
      </section>`;
  }

  function machineMetric(label, value) {
    return `<div class="machine-metric"><small>${label}</small><strong>${value}</strong></div>`;
  }

  function pageToolbar(actionLabel = "", actionName = "") {
    if (!actionLabel) return "";
    return `<div class="toolbar toolbar--end"><button class="primary-button compact-button" type="button" data-contract-action="${actionName}">${icon("plus")}<span>${actionLabel}</span></button></div>`;
  }

  function schoolsTemplate() {
    return `${pageToolbar("Cadastrar escola", "school-create")}
      <section class="panel entity-list" aria-label="Escolas cadastradas">
        ${schools.map((school) => entityRow("school", school.name, school.city, `${school.students} · ${school.machines}`, school.status, `<button class="row-action" data-contract-action="school-open" data-entity-key="${school.name}">${icon("arrow-up-right")}<span>Abrir</span></button>`)).join("")}
      </section>`;
  }

  function administratorsTemplate() {
    const visibleAdmins = state.role === "ADMIN_B" ? administrators.filter((admin) => admin.role === "ADMIN_C") : administrators;
    const label = state.role === "ADMIN_B" ? "Cadastrar Admin C" : "Cadastrar administrador";
    return `${pageToolbar(label, "admin-create")}
      <section class="panel entity-list" aria-label="Administradores">
        ${visibleAdmins.map((admin) => entityRow("shield-user", admin.name, `${admin.email} · ${admin.scope}`, admin.role, admin.status, `<button class="row-action" data-contract-action="admin-open" data-entity-key="${admin.email}">${icon("settings")}<span>Gerenciar</span></button>`)).join("")}
      </section>
      <p class="contract-note">${icon("history")} Contas são inativadas, nunca apagadas. Ninguém pode desativar a própria conta.</p>`;
  }

  function studentsTemplate() {
    const canEdit = state.role === "ADMIN_B";
    return `${canEdit ? pageToolbar("Cadastrar aluno", "student-create") : ""}
      <section class="panel" aria-label="Alunos da escola">
        <table class="data-table">
          <thead><tr><th>Aluno</th><th>RA ou matrícula</th><th>Turma</th><th>BinCoins</th><th>Estado</th><th>${canEdit ? "Ação" : "Acesso"}</th></tr></thead>
          <tbody>${students.map((student, index) => `<tr><td><strong>${student.name}</strong><br><small>${student.email}</small></td><td>${student.registration}</td><td>${student.className}</td><td>${student.balance}</td><td><span class="tag ${student.status === "Inativo" ? "tag--danger" : "tag--success"}">${student.status}</span></td><td><button class="row-action" data-contract-action="student-${canEdit ? "edit" : "view"}" data-entity-index="${index}">${icon(canEdit ? "square-pen" : "eye")}<span>${canEdit ? "Editar" : "Consultar"}</span></button></td></tr>`).join("")}</tbody>
        </table>
      </section>
      <p class="contract-note">${icon("shield-check")} Saldo, PIN, senha e identificadores internos nunca são editados manualmente.</p>`;
  }

  function classesTemplate() {
    return `${pageToolbar("Criar turma", "class-create")}
      <section class="panel entity-list" aria-label="Turmas da escola">
        ${classes.map((item, index) => entityRow("users-round", item.name, item.students, `${item.xp} · ${item.participation}`, item.status, `<button class="row-action" data-contract-action="class-edit" data-entity-index="${index}">${icon("square-pen")}<span>Editar</span></button>`)).join("")}
      </section>`;
  }

  function pendingTemplate() {
    return `
      <section class="pending-groups">
        <div class="panel">
          <header class="panel-head"><div><h2>Trocas de turma</h2><p>Exigem decisão de um Admin B.</p></div><span class="tag tag--warning">1 pendente</span></header>
          <div class="entity-list">${classRequests.map((request, index) => entityRow("users-round", `${request.student} · ${request.id}`, `${request.current} → ${request.destination}`, `Solicitado por ${request.author}`, request.status, request.status === "Pendente" ? `<button class="row-action row-action--primary" data-contract-action="request-review" data-entity-index="${index}">${icon("check-check")}<span>Analisar</span></button>` : "")).join("")}</div>
        </div>
        <div class="panel">
          <header class="panel-head"><div><h2>Resgates reservados</h2><p>Produtos aguardando entrega ou cancelamento.</p></div><button class="secondary-button" data-view="redemptions"><span>Ver fila</span>${icon("arrow-right")}</button></header>
          <div class="entity-list">${redemptions.filter((item) => item.status === "Pendente").map((item) => entityRow("ticket", item.reward, `${item.student} · ${item.className}`, item.code, item.status)).join("")}</div>
        </div>
      </section>`;
  }

  function requestsTemplate() {
    return `${pageToolbar("Solicitar troca de turma", "request-create")}
      <section class="panel entity-list" aria-label="Minhas solicitações">
        ${classRequests.map((request, index) => entityRow("send", `${request.student} · ${request.id}`, `${request.current} → ${request.destination}`, request.author, request.status, request.status === "Pendente" ? `<button class="row-action" data-contract-action="request-cancel" data-entity-index="${index}">${icon("x")}<span>Cancelar</span></button>` : "")).join("")}
      </section>
      <p class="contract-note">${icon("info")} A turma só muda depois da aprovação de um Admin B.</p>`;
  }

  function productsTemplate() {
    return `${pageToolbar("Cadastrar produto", "product-create")}
      <section class="panel entity-list" aria-label="Produtos do BinBazar">
        ${products.map((product, index) => entityRow("package-open", product.name, product.stock, product.price, product.status, `<button class="row-action" data-contract-action="product-edit" data-entity-index="${index}">${icon("square-pen")}<span>Editar</span></button>`)).join("")}
      </section>
      <p class="contract-note">${icon("badge-dollar-sign")} O preço deve respeitar o teto global definido pelo BinGo.</p>`;
  }

  function missionsTemplate() {
    const canManage = state.role === "ADMIN_A";
    return `${canManage ? pageToolbar("Criar missão global", "mission-create") : ""}
      <section class="panel entity-list" aria-label="Missões globais">
        ${missions.map((mission, index) => entityRow(mission.type === "Evento global" ? "shield" : "flag", mission.name, `${mission.type} · todas as escolas`, mission.period, mission.status, canManage ? `<button class="row-action" data-contract-action="mission-edit" data-entity-index="${index}">${icon("square-pen")}<span>Editar</span></button>` : "")).join("")}
      </section>
      ${!canManage ? `<p class="contract-note">${icon("eye")} A escola consulta as Missões globais, mas não cria Missões no V1.</p>` : ""}`;
  }

  function economyTemplate() {
    return `
      <section class="settings-grid">
        ${economySettings.map((setting, index) => settingCard(setting.title, `${setting.value} ${setting.unit}`, setting.description, setting.icon, index)).join("")}
      </section>
      <p class="contract-note">${icon("history")} Alterações futuras não modificam descartes, resgates ou pontuações já registrados.</p>`;
  }

  function settingCard(title, value, description, iconName, index) {
    return `<article class="setting-card"><span class="activity-icon">${icon(iconName)}</span><div><small>${title}</small><strong>${value}</strong><p>${description}</p></div><button class="row-action" data-contract-action="economy-edit" data-entity-index="${index}">${icon("square-pen")}<span>Editar</span></button></article>`;
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

  function formValues(form) {
    return Object.fromEntries(new FormData(form).entries());
  }

  function submitOperation(form) {
    const operation = state.activeOperation;
    if (!operation) return;
    const values = formValues(form);
    const index = operation.index;
    switch (operation.action) {
      case "student-create":
        students.push({ ...values, balance: "0", status: "Ativo" });
        break;
      case "student-edit":
        Object.assign(students[index], values);
        break;
      case "class-create":
        classes.push({ name: values.name, students: "0 alunos", xp: "0 XP", participation: "0%", status: values.status });
        break;
      case "class-edit":
        Object.assign(classes[index], { name: values.name, status: values.status });
        break;
      case "request-create": {
        const student = students.find((item) => item.name === values.student);
        classRequests.unshift({ id: `TT-${String(33 + classRequests.length).padStart(3, "0")}`, student: values.student, current: student?.className || "Sem turma", destination: values.destination, author: ADMIN_ROLES[state.role].operatorName, status: "Pendente" });
        break;
      }
      case "request-review":
        classRequests[index].status = "Aprovada";
        break;
      case "request-cancel":
        classRequests[index].status = "Cancelada";
        break;
      case "product-create":
        products.push({ name: values.name, price: `${values.price} BinCoins`, stock: `${values.stock} unidades`, status: values.status });
        break;
      case "product-edit":
        Object.assign(products[index], { name: values.name, price: `${values.price} BinCoins`, stock: values.stock === "Ilimitado" ? values.stock : `${values.stock} unidades`, status: values.status });
        break;
      case "admin-create":
        administrators.push({ name: values.name, email: values.email, role: values.role, scope: state.role === "ADMIN_A" ? "Global" : "Colégio ENIAC", status: values.status });
        break;
      case "admin-open": {
        const admin = administrators.find((item) => item.email === operation.key);
        if (admin) Object.assign(admin, values);
        break;
      }
      case "redemption-cancel": {
        const redemption = redemptions.find((item) => item.id === operation.key);
        if (redemption) {
          redemption.status = "Cancelado";
          redemption.expiresAt = "Cancelado agora";
        }
        break;
      }
      case "school-create":
        schools.push({ name: values.name, city: values.city, students: "0 alunos", machines: "0 Totens", status: values.status });
        break;
      case "school-open": {
        const school = schools.find((item) => item.name === operation.key);
        if (school) Object.assign(school, values);
        break;
      }
      case "mission-create":
        missions.push({ name: values.name, type: values.type, period: values.period, status: values.status });
        break;
      case "mission-edit":
        Object.assign(missions[index], values);
        break;
      case "economy-edit":
        economySettings[index].value = values.value;
        break;
      default:
        break;
    }
    const completedTitle = operationDefinitions[operation.action]?.title || "Operação";
    state.activeOperation = null;
    showToast(`${completedTitle} concluído somente nesta demonstração.`);
  }

  function bindEvents() {
    document.querySelector("#access-form")?.addEventListener("submit", (event) => {
      event.preventDefault();
      const selectedRole = document.querySelector("[data-role-select]")?.value;
      if (selectedRole && ADMIN_ROLES[selectedRole]) state.role = selectedRole;
      state.view = firstViewForRole(state.role);
      state.authenticated = true;
      render();
      window.scrollTo(0, 0);
    });

    document.querySelectorAll("[data-view]").forEach((button) => {
      button.addEventListener("click", () => {
        if (!canAccessView(state.role, button.dataset.view)) {
          showToast("Este perfil não possui acesso a essa área.");
          return;
        }
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

    document.querySelector("[data-role-switch]")?.addEventListener("change", (event) => {
      state.role = event.target.value;
      state.view = firstViewForRole(state.role);
      state.scenario = "normal";
      state.redemptionToDeliver = null;
      state.activeOperation = null;
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
      state.activeOperation = null;
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

    document.querySelectorAll("[data-contract-action]").forEach((button) => {
      button.addEventListener("click", () => {
        const rawIndex = button.dataset.entityIndex;
        state.activeOperation = {
          action: button.dataset.contractAction,
          index: rawIndex === undefined ? null : Number(rawIndex),
          key: button.dataset.entityKey || null,
        };
        render();
        document.querySelector("#operation-dialog-title")?.focus();
      });
    });

    document.querySelectorAll("[data-operation-close]").forEach((element) => {
      element.addEventListener("click", (event) => {
        if (element.classList.contains("dialog-backdrop") && event.target !== element) return;
        state.activeOperation = null;
        render();
      });
    });

    document.querySelector("#operation-form")?.addEventListener("submit", (event) => {
      event.preventDefault();
      submitOperation(event.currentTarget);
    });

    document.querySelector("[data-operation-reject]")?.addEventListener("click", () => {
      const operation = state.activeOperation;
      if (!operation || operation.action !== "request-review") return;
      classRequests[operation.index].status = "Recusada";
      state.activeOperation = null;
      showToast("Solicitação recusada somente nesta demonstração.");
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
}
