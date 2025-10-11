import { requireAuth } from "../api/auth.js";
import { fetchMyMissions, fetchAvailableMissions, acceptMission } from "../api/missions.js";

requireAuth();

const els = {
  available: document.getElementById("missions-pending"),
  active: document.getElementById("missions-active"),
  done: document.getElementById("missions-done"),
  backBtn: document.getElementById("backBtn"),
  confetti: document.getElementById("confetti"),
  toast: document.getElementById("toast"),
};

els.backBtn?.addEventListener("click", () => history.back());

async function init() {
  try {
    skeletons();
    const [userMissions, availableMissions] = await Promise.all([
      fetchMyMissions(),
      fetchAvailableMissions()
    ]);

    const acceptedMissionIds = userMissions.map(m => m.id);
    const availableToAccept = availableMissions.filter(m => !acceptedMissionIds.includes(m.id));
    
    const active = userMissions.filter(m => m.status.toUpperCase().includes("PROGRESSO"));
    const done = userMissions.filter(m => m.status.toUpperCase() === "COMPLETED");

    renderAvailable(availableToAccept);
    renderActive(active);
    renderDone(done);

  } catch (err) {
    console.error("❌ Falha ao carregar missões:", err);
    showToast("Erro ao carregar missões.");
  }
}

function renderAvailable(list) {
  clear(els.available);
  if (!list.length) return showEmpty(els.available, "Nenhuma nova missão disponível.");

  list.forEach(m => {
    const card = el("div", "mission");
    card.innerHTML = `
      <div class="title">
        <h3>${escapeHtml(m.title)}</h3>
        <span class="badge">+${m.points} pts</span>
      </div>
      <div class="meta">${escapeHtml(m.description)}</div>
      <div class="actions">
        <button class="btn secondary" data-accept-id="${m.id}">ACEITAR</button>
      </div>
    `;

    card.querySelector("[data-accept-id]").addEventListener("click", async (e) => {
      const btn = e.currentTarget;
      btn.disabled = true;
      btn.textContent = "ACEITANDO...";
      try {
        await acceptMission(m.id);
        showToast("Missão aceita! 🌱");
        card.style.transition = "opacity .3s, transform .3s";
        card.style.opacity = 0;
        card.style.transform = "scale(0.9)";
        setTimeout(() => {
          card.remove();
          if (els.available.children.length === 0) showEmpty(els.available, "Nenhuma nova missão disponível.");
          const newActiveCard = createActiveCard(m);
          if (els.active.querySelector('.empty')) clear(els.active);
          els.active.insertBefore(newActiveCard, els.active.firstChild);
        }, 300);
      } catch (err) {
        showToast("Erro ao aceitar missão.");
        btn.disabled = false;
        btn.textContent = "ACEITAR";
      }
    });
    
    els.available.appendChild(card);
  });
}

function renderActive(list) {
  clear(els.active);
  if (!list.length) return showEmpty(els.active, "Nenhuma missão ativa no momento.");
  list.forEach(m => {
    const card = createActiveCard(m);
    els.active.appendChild(card);
  });
}

function renderDone(list) {
  clear(els.done);
  if (!list.length) return showEmpty(els.done, "Nenhuma missão concluída ainda.");
  list.forEach(m => {
    const card = el("div", "mission done");
    card.innerHTML = `
      <div class="title">
        <h3>${escapeHtml(m.title)}</h3>
        <span class="badge">✅</span>
      </div>
      <div class="meta">Recompensa: +${m.points} pts</div>
    `;
    els.done.appendChild(card);
  });
}

function createActiveCard(mission) {
  const pct = computePct(mission.current, mission.target);
  const card = el("div", "mission");
  card.innerHTML = `
    <div class="title">
      <h3>${escapeHtml(mission.title)}</h3>
      <span class="badge">+${mission.points} pts</span>
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

function skeletons() {
  [els.available, els.active, els.done].forEach(target => {
    clear(target);
    for (let i = 0; i < 1; i++) {
      const sk = el("div", "mission");
      sk.style.opacity = ".5";
      sk.innerHTML = `<div class="title"><h3 style="background:#2a6a9e; border-radius:4px; width:70%; height:1rem;"></h3></div><div class="meta" style="background:#2a6a9e; border-radius:4px; width:90%; height:2rem;"></div>`;
      target.appendChild(sk);
    }
  });
}

function showEmpty(container, text){
  clear(container);
  const box = el("div", "empty");
  box.textContent = text;
  container.appendChild(box);
}

function clear(n){ n.innerHTML = ""; }
function el(tag, cls){ const n = document.createElement(tag); if(cls) n.className = cls; return n; }
function computePct(cur = 0, tgt = 1){ if (!tgt) return 0; const v = Math.round((cur / tgt) * 100); return Math.max(0, Math.min(100, v)); }
function escapeHtml(s = ""){ return String(s).replace(/[&<>"']/g, m => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m])); }

function showToast(msg){
  const t = els.toast;
  t.textContent = msg;
  t.classList.remove("hidden");
  setTimeout(() => t.classList.add("hidden"), 2200);
}

init();