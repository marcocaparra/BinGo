import { requireAuth, getMe, logout } from "../api/auth.js";
import { apiFetch } from "../api/http.js";

requireAuth();

const els = {
  userName: document.getElementById("userName"),
  userUsername: document.getElementById("userUsername"),
  userBins: document.getElementById("userBins"),
  userLevelLabel: document.getElementById("userLevelLabel"),
  levelFill: document.getElementById("levelFill"),
  discardCount: document.getElementById("discardCount"),
  achievementsGrid: document.getElementById("achievementsGrid"),
  historyList: document.getElementById("historyList"),
  logoutBtn: document.getElementById("logoutBtn"),
};

init();

async function init() {
  const user = await getMe();
  fillHeader(user);
  bindLogout();

  const achievements = await safeAchievements();
  renderAchievements(achievements);

  const historyAPI = await safeHistory();
  const history = historyAPI.length
    ? historyAPI
    : fallbackHistoryFromAchievements(achievements);
  renderHistory(history);

  setupCutlineOnScroll(els.historyList);
}

function setupCutlineOnScroll(container) {
  if (!container) return;
  const toggle = () => {
    if (container.scrollTop > 2) container.classList.add("show-cutline");
    else container.classList.remove("show-cutline");
  };
  toggle();
  container.addEventListener("scroll", toggle, { passive: true });
}

function firstNameOf(name) {
  if (!name) return "Usuário";
  return String(name).trim().split(/\s+/)[0];
}

function fillHeader(user) {
  els.userName.textContent = firstNameOf(user.name);
  els.userUsername.textContent = "@" + (user.username || "user");
  els.userBins.textContent = user.total_points ?? 0;
  els.discardCount.textContent = user.discard_count ?? 0;

  const levelNames = {
    1: "Semeador", 2: "Plantador", 3: "Cuidador", 4: "Guardião", 5: "Mestre Verde",
  };
  const levelNum = user.level ?? 1;
  els.userLevelLabel.textContent = levelNames[levelNum] || `Nível ${levelNum}`;
  els.levelFill.style.width = levelProgress(user.total_points) + "%";
}

function levelProgress(points = 0) {
  const step = 200;
  const pct = ((points % step) / step) * 100;
  return Math.max(4, Math.min(100, Math.round(pct)));
}

function bindLogout() {
  els.logoutBtn?.addEventListener("click", logout);
}

async function safeAchievements() {
  try { return await apiFetch("/achievements/me/"); } catch { return []; }
}

async function safeHistory() {
  try { return await apiFetch("/activity/me"); } catch { return []; }
}

function fallbackHistoryFromAchievements(achievements) {
  return achievements.slice(0, 12).map((a) => ({
    date: new Date(a.unlocked_at || Date.now()).toISOString(),
    text: `Desbloqueou conquista ${a.achievement?.name || ""}`,
  }));
}

function resolveAsset(url) {
  if (!url) return "/public/assets/images/trophy.png";
  if (/^https?:\/\//i.test(url)) return url;
  if (url.startsWith("/assets/")) return "/public" + url;
  return url.startsWith("/public") ? url : "/public" + (url.startsWith("/") ? url : "/" + url);
}

function renderAchievements(list) {
  const root = els.achievementsGrid;
  root.innerHTML = "";
  if (!list || list.length === 0) {
    root.innerHTML = `<div class="ach-card"><div class="ach-name">Sem conquistas</div></div>`;
    return;
  }
  list.forEach((item) => {
    const c = document.createElement("div");
    c.className = "ach-card";
    const imgSrc = resolveAsset(item.achievement?.badge_image_url);
    c.innerHTML = `
      <img class="ach-img" src="${sanitize(imgSrc)}" alt="badge"
           onerror="this.src='/public/assets/images/trophy.png'">
      <div class="ach-name">${sanitize(item.achievement?.name || "")}</div>
      <div class="ach-points">+${Number(item.achievement?.points_reward || 0)} Bins</div>
    `;
    root.appendChild(c);
  });
}

function renderHistory(items) {
  const root = els.historyList;
  root.innerHTML = "";
  if (!items || items.length === 0) {
    root.innerHTML = `<div class="history-item"><span class="desc">Sem atividades recentes</span></div>`;
    return;
  }
  items.forEach((ev) => {
    const n = document.createElement("div");
    n.className = "history-item";
    n.innerHTML = `
      <span class="date">${formatBR(ev.date)}</span>
      <span class="desc">${sanitize(ev.text || "")}</span>
    `;
    root.appendChild(n);
  });
}

function formatBR(dt) {
  try { return new Date(dt).toLocaleDateString("pt-BR"); } catch { return "—"; }
}
function sanitize(s) { return String(s || "").replace(/[<>]/g, ""); }