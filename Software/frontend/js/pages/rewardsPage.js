import { requireAuth, getMe } from "../api/auth.js";
import { fetchRewards, redeemReward } from "../api/rewards.js";

requireAuth();

const els = {
  rewardsGrid: document.getElementById("rewards-grid"),
  userName: document.getElementById("userName"),
  userBins: document.getElementById("userBins"),
  successModal: document.getElementById("success-modal"),
  redemptionCode: document.getElementById("redemption-code"),
  modalCloseBtn: document.getElementById("modal-close-btn"),
  toast: document.getElementById("toast"),
};

let currentUser = null;
let rewardsData = [];

async function init() {
  try {
    const [rewards, user] = await Promise.all([fetchRewards(), getMe()]);
    currentUser = user;
    rewardsData = rewards;
    updateHeader();
    renderRewards(rewardsData);
  } catch {
    showToast("Erro ao carregar recompensas.");
  }
}

function firstNameOf(name) {
  if (!name) return "Usuário";
  const s = String(name).trim().split(/\s+/);
  return s[0];
}

function updateHeader() {
  if (!currentUser) return;
  els.userName.textContent = firstNameOf(currentUser.name);
  els.userBins.textContent = currentUser.total_points ?? 0;
}

function renderRewards(rewards) {
  els.rewardsGrid.innerHTML = "";
  if (!rewards || rewards.length === 0) {
    els.rewardsGrid.innerHTML = "<p>Nenhuma recompensa disponível no momento.</p>";
    return;
  }
  rewards.forEach(r => els.rewardsGrid.appendChild(createRewardCard(r)));
}

function createRewardCard(reward) {
  const wrap = document.createElement("div");
  wrap.className = "reward-card";
  const canAfford = Number(currentUser.total_points) >= Number(reward.cost);

  const exp = new Date(reward.expires_at);
  const today = new Date(); today.setHours(0,0,0,0);
  const tomorrow = new Date(today); tomorrow.setDate(tomorrow.getDate()+1);
  const onlyDate = d => { const x = new Date(d); x.setHours(0,0,0,0); return x.getTime(); };
  let when = exp.toLocaleDateString("pt-BR");
  if (onlyDate(exp) === onlyDate(today)) when = "HOJE";
  else if (onlyDate(exp) === onlyDate(tomorrow)) when = "AMANHÃ";

  const desc = formatDescription(reward.description, reward.location);

  wrap.innerHTML = `
    <div class="reward-title" title="${reward.name}">${reward.name}</div>
    <p class="reward-desc">${desc}</p>
    <div class="expiry-box"><span class="until">RESGATE ATÉ:</span> <span class="when">${when}</span></div>
    <button class="redeem-btn" data-id="${reward.id}" ${!canAfford ? "disabled" : ""}>
      <span class="redeem-left">RESGATAR</span>
      <span class="redeem-cost">
        <img src="../assets/images/bin-coin.png" alt="BinCoin">
        ${reward.cost}
      </span>
    </button>
  `;
  wrap.querySelector(".redeem-btn").addEventListener("click", handleRedeemClick);
  return wrap;
}

function formatDescription(text, location) {
  if (!text || !location) return text || "";
  const safeLoc = location.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const re = new RegExp(safeLoc, "g");
  return text.replace(re, `<em>${location}</em>`);
}

async function handleRedeemClick(e) {
  const btn = e.currentTarget;
  const id = btn.dataset.id;
  btn.disabled = true;
  try {
    const res = await redeemReward(id);
    currentUser.total_points = res.new_total_points;
    updateHeader();
    els.redemptionCode.textContent = res.redemption_code;
    els.successModal.classList.remove("hidden");
    els.successModal.classList.add("show");
    document.body.classList.add("modal-open");
    document.querySelectorAll(".redeem-btn").forEach(b => {
      const cost = Number(rewardsData.find(r => String(r.id) === String(b.dataset.id))?.cost ?? Number.MAX_SAFE_INTEGER);
      b.disabled = Number(currentUser.total_points) < cost;
    });
  } catch {
    showToast("Não foi possível resgatar a recompensa.");
    btn.disabled = false;
  }
}

els.modalCloseBtn.addEventListener("click", () => {
  els.successModal.classList.add("closing");
  setTimeout(() => {
    els.successModal.classList.remove("show","closing");
    els.successModal.classList.add("hidden");
    document.body.classList.remove("modal-open");
  }, 200);
});

function showToast(msg) {
  els.toast.textContent = msg;
  els.toast.classList.remove("hidden");
  setTimeout(() => els.toast.classList.add("hidden"), 3000);
}

init();
