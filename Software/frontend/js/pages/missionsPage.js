import { requireAuth, getMe } from "../api/auth.js";
import { fetchMyMissions, fetchAvailableMissions, acceptMission } from "../api/missions.js";

requireAuth();

/* ----------------------- helpers locais (evita ReferenceError) ----------------------- */
function enableOnlyListsScroll() {
  // deixa as listas roláveis sem estourar o layout
  document.querySelectorAll(".boards .list").forEach((el) => {
    el.style.overflowY = "auto";
    el.style.webkitOverflowScrolling = "touch";
  });
}

function ensureListClass(nodes = []) {
  nodes.forEach((n) => { if (n && !n.classList.contains("list")) n.classList.add("list"); });
}

function clear(n) { if (n) n.innerHTML = ""; }
function el(tag, cls) { const n = document.createElement(tag); if (cls) n.className = cls; return n; }
function computePct(cur = 0, tgt = 1) { if (!tgt) return 0; const v = Math.round((cur / tgt) * 100); return Math.max(0, Math.min(100, v)); }
function escapeHtml(s = "") { return String(s).replace(/[&<>"']/g, (m) => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m])); }
function showEmpty(container, text) { clear(container); const box = el("div", "empty"); box.textContent = text; container.appendChild(box); }
/* ------------------------------------------------------------------------------------- */

const els = {
  available: document.getElementById("missions-pending"),
  active: document.getElementById("missions-active"),
  done: document.getElementById("missions-done"),
  backBtn: document.getElementById("backBtn"),
  confetti: document.getElementById("confetti"),
  toast: document.getElementById("toast"),
};

enableOnlyListsScroll();
ensureListClass([els.available, els.active, els.done]);

els.backBtn?.addEventListener("click", () => history.back());

loadHeaderData();
init();

async function loadHeaderData() {
  try {
    const user = await getMe();
    const rawName = user?.name || "Usuário";
    const firstName = String(rawName).trim().split(/\s+/)[0];
    document.getElementById("userName").textContent = firstName;

    const bins = (typeof user?.total_bins === "number") ? user.total_bins : (user?.total_points ?? 0);
    document.getElementById("userBins").textContent = bins;
  } catch (error) {
    console.error("Erro ao carregar dados do header:", error);
    document.getElementById("userName").textContent = "Herói";
  }
}

async function init() {
  try {
    skeletons();

    const [userMissions, availableMissions] = await Promise.all([
      fetchMyMissions(),
      fetchAvailableMissions(),
    ]);

    // ids que o usuário já tem (qualquer status)
    const acceptedIds = new Set(userMissions.map((m) => m.id));
    const availableToAccept = availableMissions.filter((m) => !acceptedIds.has(m.id));

    const active = userMissions.filter((m) => m.status === "IN_PROGRESS");
    const done = userMissions.filter((m) => m.status === "COMPLETED");

    renderAvailable(availableToAccept);
    renderActive(active);
    renderDone(done);
  } catch (err) {
    console.error("❌ Falha ao carregar missões:", err);
    showToast("Erro ao carregar missões.");
    // mostra vazios para não deixar os quadros em branco
    renderAvailable([]);
    renderActive([]);
    renderDone([]);
  }
}

function renderAvailable(list) {
  clear(els.available);
  if (!list.length) return showEmpty(els.available, "Nenhuma nova missão disponível.");
  list.forEach((m) => els.available.appendChild(createAvailableCard(m)));
}

function renderActive(list) {
  clear(els.active);
  if (!list.length) return showEmpty(els.active, "Nenhuma missão ativa no momento.");
  list.forEach((m) => els.active.appendChild(createActiveCard(m)));
}

function renderDone(list) {
  clear(els.done);
  if (!list.length) return showEmpty(els.done, "Nenhuma missão concluída ainda.");
  list.forEach((m) => els.done.appendChild(createDoneCard(m)));
}

function createAvailableCard(mission) {
  const card = el("div", "mission");
  card.innerHTML = `
    <div class="title">
      <h3>${escapeHtml(mission.title)}</h3>
      <span class="badge">+${mission.points} Bins</span>
    </div>
    <div class="meta">${escapeHtml(mission.description)}</div>
    <div class="actions">
      <button class="btn secondary" data-accept-id="${mission.id}">ACEITAR</button>
    </div>
  `;
  card.querySelector("[data-accept-id]")
    .addEventListener("click", (e) => handleAcceptMission(e, mission, card));
  return card;
}

function createActiveCard(mission) {
  const pct = computePct(mission.current, mission.target);
  const card = el("div", "mission");
  card.innerHTML = `
    <div class="title">
      <h3>${escapeHtml(mission.title)}</h3>
      <span class="badge">+${mission.points} Bins</span>
    </div>
    <div class="meta">${escapeHtml(mission.description)}</div>
    <div class="progress">
      <div class="bar" style="width:${pct}%"></div>
      <span class="pct">${pct}%</span>
    </div>
    <div class="meta">${mission.current || 0} / ${mission.target}</div>
  `;
  return card;
}

function createDoneCard(mission) {
  const card = el("div", "mission done");
  card.innerHTML = `
    <div class="title">
      <h3>${escapeHtml(mission.title)}</h3>
      <span class="badge">✅ Concluída</span>
    </div>
    <div class="meta">${escapeHtml(mission.description)}</div>
    <div class="progress"><div class="bar"></div></div>
    <div class="meta">Recompensa: +${mission.points} Bins</div>
  `;
  return card;
}

async function handleAcceptMission(event, mission, cardElement) {
  const btn = event.currentTarget;
  btn.disabled = true;
  btn.textContent = "ACEITANDO...";
  try {
    await acceptMission(mission.id);
    mission.status = "IN_PROGRESS";
    mission.current = mission.current ?? 0;

    showToast("Missão aceita! 🌱");

    cardElement.style.transition = "opacity .3s, transform .3s";
    cardElement.style.opacity = 0;
    cardElement.style.transform = "scale(0.9)";

    setTimeout(() => {
      cardElement.remove();
      if (!els.available.querySelector(":scope > *")) {
        showEmpty(els.available, "Nenhuma nova missão disponível.");
      }
      const empty = els.active.querySelector(".empty");
      if (empty) clear(els.active);
      els.active.insertBefore(createActiveCard(mission), els.active.firstChild);
    }, 300);
  } catch (err) {
    console.error("Erro ao aceitar missão:", err);
    showToast("Erro ao aceitar missão.");
    btn.disabled = false;
    btn.textContent = "ACEITAR";
  }
}

function skeletons() {
  [els.available, els.active, els.done].forEach((target) => {
    clear(target);
    const sk = el("div", "mission");
    sk.style.opacity = ".5";
    sk.innerHTML = `
      <div class="title">
        <h3 style="background:#2a6a9e; border-radius:4px; width:70%; height:1rem;"></h3>
      </div>
      <div class="meta" style="background:#2a6a9e; border-radius:4px; width:90%; height:2rem;"></div>
    `;
    target.appendChild(sk);
  });
}

function showToast(msg) {
  const t = els.toast;
  if (!t) return;
  t.textContent = msg;
  t.classList.remove("hidden");
  setTimeout(() => t.classList.add("hidden"), 2200);
}
